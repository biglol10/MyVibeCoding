import AppKit
import SwiftUI
import WebKit
import UniformTypeIdentifiers

@MainActor
final class EditorBridge: NSObject, ObservableObject, WKScriptMessageHandler, WKNavigationDelegate, WKURLSchemeHandler {
    weak var model: AppModel?
    private(set) var webView: WKWebView?
    private var tasks: [ObjectIdentifier: Task<Void, Never>] = [:]
    private var sendTask: Task<Void, Never>?
    var isReady = false

    var editorDirectory: URL {
        #if SWIFT_PACKAGE
        Bundle.module.url(forResource: "Editor", withExtension: nil)!
        #else
        Bundle.main.url(forResource: "Editor", withExtension: nil)!
        #endif
    }

    func makeWebView() -> WKWebView {
        if let webView { return webView }
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(self, forURLScheme: "app")
        config.userContentController.add(self, name: "editor")
        config.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = self
        view.setValue(false, forKey: "drawsBackground")
        view.underPageBackgroundColor = model?.canvasNSColor ?? NSColor(red: 0.098, green: 0.106, blue: 0.118, alpha: 1)
        view.allowsBackForwardNavigationGestures = false
        webView = view
        view.load(URLRequest(url: URL(string: "app://bundle/index.html")!))
        return view
    }

    func send(_ payload: [String: Any]) {
        guard isReady, let data = try? JSONSerialization.data(withJSONObject: payload), let json = String(data: data, encoding: .utf8) else { return }
        let previous = sendTask
        sendTask = Task { [weak self] in
            await previous?.value
            do { _ = try await self?.webView?.callAsyncJavaScript("window.MarkdownHost.receive(JSON.parse(payload))", arguments: ["payload": json], in: nil, contentWorld: .page) }
            catch { self?.model?.showError(error) }
        }
    }

    func snapshot(newBase: String? = nil) async throws -> [String: Any] {
        guard isReady, let webView else { throw CocoaError(.coderReadCorrupt) }
        await sendTask?.value
        let result: Any?
        if let newBase { result = try await webView.callAsyncJavaScript("return window.MarkdownHost.prepareSaveAs(base)", arguments: ["base": newBase], in: nil, contentWorld: .page) }
        else { result = try await webView.callAsyncJavaScript("return window.MarkdownHost.snapshot()", arguments: [:], in: nil, contentWorld: .page) }
        guard let snapshot = result as? [String: Any] else { throw CocoaError(.coderReadCorrupt) }
        return snapshot
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, message.frameInfo.request.url?.scheme == "app", message.frameInfo.request.url?.host == "bundle",
              let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        if type == "ready" { isReady = true; model?.editorReady(); return }
        model?.receive(body)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        let url = navigationAction.request.url
        if url?.scheme == "app", url?.host == "bundle", navigationAction.navigationType == .other { decisionHandler(.allow) }
        else { decisionHandler(.cancel) }
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        isReady = false
        model?.webProcessTerminated()
        webView.reload()
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard let requestURL = urlSchemeTask.request.url else { return }
        let key = ObjectIdentifier(urlSchemeTask)
        let target: URL
        var mime = "application/octet-stream"
        if requestURL.host == "bundle" {
            let path = requestURL.path == "/" ? "index.html" : String(requestURL.path.dropFirst())
            target = editorDirectory.appendingPathComponent(path).standardizedFileURL
            guard target.path.hasPrefix(editorDirectory.standardizedFileURL.path + "/") else { urlSchemeTask.didFailWithError(CocoaError(.fileReadNoPermission)); return }
            switch target.pathExtension {
            case "html": mime = "text/html"
            case "js": mime = "application/javascript"
            case "css": mime = "text/css"
            case "woff2": mime = "font/woff2"
            case "woff": mime = "font/woff"
            case "ttf": mime = "font/ttf"
            default: mime = UTType(filenameExtension: target.pathExtension)?.preferredMIMEType ?? mime
            }
        } else if requestURL.host == "assets", let model {
            let parts = URLComponents(url: requestURL, resolvingAgainstBaseURL: false)?.percentEncodedPath.split(separator: "/") ?? []
            guard parts.count == 2, parts[0].removingPercentEncoding == model.sessionID,
                  let raw = parts[1].removingPercentEncoding,
                  let base = model.documentURL?.deletingLastPathComponent(),
                  let resolved = URL(string: raw, relativeTo: base)?.absoluteURL, resolved.isFileURL else {
                urlSchemeTask.didFailWithError(CocoaError(.fileReadNoPermission)); return
            }
            target = resolved.standardizedFileURL.resolvingSymlinksInPath()
            guard model.access.canRead(target), UTType(filenameExtension: target.pathExtension)?.conforms(to: .image) == true else {
                urlSchemeTask.didFailWithError(CocoaError(.fileReadNoPermission)); return
            }
            mime = UTType(filenameExtension: target.pathExtension)?.preferredMIMEType ?? mime
        } else { urlSchemeTask.didFailWithError(CocoaError(.fileReadNoPermission)); return }
        let contentType = mime
        tasks[key] = Task { [weak self] in
            do {
                var data = try await Task.detached(priority: .userInitiated) { try Data(contentsOf: target) }.value
                if requestURL.host == "bundle", target == self?.editorDirectory.appendingPathComponent("index.html"),
                   let html = String(data: data, encoding: .utf8) {
                    // Set the trusted bundle's theme before HTML/CSS can paint its first frame.
                    let initialTheme = self?.model?.resolvedTheme ?? "dark"
                    data = Data(html.replacingOccurrences(of: "data-theme=\"dark\"", with: "data-theme=\"\(initialTheme)\"").utf8)
                }
                guard !Task.isCancelled else { return }
                urlSchemeTask.didReceive(URLResponse(url: requestURL, mimeType: contentType, expectedContentLength: data.count, textEncodingName: contentType.hasPrefix("text/") ? "utf-8" : nil))
                urlSchemeTask.didReceive(data); urlSchemeTask.didFinish()
            } catch { if !Task.isCancelled { urlSchemeTask.didFailWithError(error) } }
            self?.tasks.removeValue(forKey: key)
        }
    }
    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) { tasks.removeValue(forKey: ObjectIdentifier(urlSchemeTask))?.cancel() }
}

struct EditorWebView: NSViewRepresentable {
    @ObservedObject var model: AppModel
    func makeNSView(context: Context) -> WKWebView { model.bridge.makeWebView() }
    func updateNSView(_ nsView: WKWebView, context: Context) {
        nsView.appearance = NSAppearance(named: model.usesDarkAppearance ? .darkAqua : .aqua)
        nsView.underPageBackgroundColor = model.canvasNSColor
    }
}
