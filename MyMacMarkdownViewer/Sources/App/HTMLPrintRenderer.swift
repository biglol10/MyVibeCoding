import AppKit
import PDFKit
import WebKit

@MainActor
final class HTMLPrintRenderer: NSObject, WKNavigationDelegate {
    private let webView: WKWebView
    private let hostWindow: NSPanel
    private var continuation: CheckedContinuation<Void, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var printContinuation: CheckedContinuation<Bool, Never>?
    private var activePrintOperation: NSPrintOperation?

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 720, height: 900), configuration: configuration)
        hostWindow = NSPanel(contentRect: webView.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        webView.navigationDelegate = self
        hostWindow.contentView = webView
        hostWindow.alphaValue = 0.01
        hostWindow.ignoresMouseEvents = true
    }

    private func load(_ html: String) async throws {
        hostWindow.orderFrontRegardless()
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled else { return }
                self?.finish(.failure(URLError(.timedOut)))
            }
            webView.loadHTMLString(Self.restricted(html), baseURL: nil)
        }
    }

    private static func restricted(_ html: String) -> String {
        let policy = #"<meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; style-src 'unsafe-inline'; font-src data:;">"#
        let pagination = #"<style>@media print{h1,h2,h3,h4,h5,h6{break-after:avoid-page;page-break-after:avoid}p,li{orphans:3;widows:3}thead,tr,pre,blockquote,img,svg{break-inside:avoid-page;page-break-inside:avoid}}</style>"#
        guard let expression = try? NSRegularExpression(pattern: "(?i)<head(?:\\s[^>]*)?>"),
              let match = expression.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range, in: html) else { return policy + html + pagination }
        var result = html
        result.insert(contentsOf: policy, at: range.upperBound)
        if let closing = result.range(of: "</head>", options: [.caseInsensitive]) {
            result.insert(contentsOf: pagination, at: closing.lowerBound)
        } else {
            result.append(pagination)
        }
        return result
    }

    private func finish(_ result: Result<Void, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timeoutTask?.cancel(); timeoutTask = nil
        if case .failure = result { webView.stopLoading() }
        continuation.resume(with: result)
    }

    private func run(_ operation: NSPrintOperation, for window: NSWindow) async -> Bool {
        await withCheckedContinuation { continuation in
            printContinuation = continuation
            activePrintOperation = operation
            operation.runModal(for: window, delegate: self,
                               didRun: #selector(printOperationDidRun(_:success:contextInfo:)), contextInfo: nil)
        }
    }

    @objc nonisolated private func printOperationDidRun(_ operation: NSPrintOperation, success: Bool,
                                                        contextInfo: UnsafeMutableRawPointer?) {
        Task { @MainActor [weak self] in self?.completePrint(success: success) }
    }

    private func completePrint(success: Bool) {
        guard let continuation = printContinuation else { return }
        printContinuation = nil; activePrintOperation = nil
        continuation.resume(returning: success)
    }

    func savePDF(html: String, to url: URL) async throws {
        defer { hostWindow.orderOut(nil) }
        try await load(html)
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyMarkdownViewer-Export-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        hostWindow.contentView?.layoutSubtreeIfNeeded()
        hostWindow.displayIfNeeded()
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.paperSize = NSSize(width: 595, height: 842)
        info.topMargin = 36; info.bottomMargin = 36; info.leftMargin = 36; info.rightMargin = 36
        info.horizontalPagination = .fit; info.verticalPagination = .automatic
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = temporaryURL
        let operation = webView.printOperation(with: info)
        operation.showsPrintPanel = false; operation.showsProgressPanel = false
        guard await run(operation, for: hostWindow) else { throw CocoaError(.fileWriteUnknown) }
        guard FileManager.default.fileExists(atPath: temporaryURL.path) else { throw CocoaError(.fileWriteUnknown) }
        let pdfData = try Data(contentsOf: temporaryURL, options: [.mappedIfSafe])
        guard let pdf = PDFDocument(data: pdfData), pdf.pageCount > 0 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: [.forReplacing], error: &coordinationError) { coordinatedURL in
            do { try pdfData.write(to: coordinatedURL, options: [.atomic]) }
            catch { writeError = error }
        }
        if let coordinationError { throw coordinationError }
        if let writeError { throw writeError }
    }

    func printDocument(html: String) async throws {
        defer { hostWindow.orderOut(nil) }
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyMarkdownViewer-Print-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        try await savePDF(html: html, to: temporaryURL)
        guard let document = PDFDocument(url: temporaryURL) else { throw CocoaError(.fileReadCorruptFile) }
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        guard let operation = document.printOperation(for: info, scalingMode: .pageScaleDownToFit, autoRotate: true) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        _ = await run(operation, for: NSApp.keyWindow ?? hostWindow)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 preferences: WKWebpagePreferences,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
        preferences.allowsContentJavaScript = false
        let allowed = navigationAction.targetFrame?.isMainFrame == true
            && navigationAction.navigationType == .other
            && navigationAction.request.url?.absoluteString == "about:blank"
        decisionHandler(allowed ? .allow : .cancel, preferences)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await webView.callAsyncJavaScript("await document.fonts.ready; return true",
                                                          arguments: [:], in: nil, contentWorld: .page)
                hostWindow.contentView?.layoutSubtreeIfNeeded()
                hostWindow.displayIfNeeded()
                finish(.success(()))
            } catch { finish(.failure(error)) }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish(.failure(error)) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finish(.failure(error)) }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { finish(.failure(CocoaError(.coderReadCorrupt))) }
}
