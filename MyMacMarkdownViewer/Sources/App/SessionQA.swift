import AppKit
import WebKit

@MainActor
enum SessionQA {
    static func run(model: AppModel) async {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--qa-root"), args.indices.contains(index + 1),
              let stageIndex = args.firstIndex(of: "--qa-session"), args.indices.contains(stageIndex + 1),
              let web = model.bridge.webView else { return }
        let root = URL(fileURLWithPath: args[index + 1]).standardizedFileURL
        let allowed = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MyMarkdownViewer/QA").standardizedFileURL
        guard root.path.hasPrefix(allowed.path + "/") else { return }
        let stage = args[stageIndex + 1]
        guard ["seed", "check", "blank", "missing", "explicit"].contains(stage) else { return }
        var result: [String: Any] = ["stage": stage]
        do {
            if stage == "seed" {
                try await model.setQAWorkspace(root)
                await model.open(root.appendingPathComponent("document.md"))
                _ = try await model.bridge.snapshot()
                _ = try await web.callAsyncJavaScript("window.MarkdownHost.receive({type:'jump',...window.MarkdownHost.snapshot(),from:1500,to:1500}); await new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r))); const s=document.querySelector('.cm-scroller'); s.scrollTop=1200; s.dispatchEvent(new Event('scroll'));", arguments: [:], in: nil, contentWorld: .page)
            } else if stage == "blank" { await model.newDocument() }
            try await Task.sleep(for: .milliseconds(900))
            let snapshot = try await model.bridge.snapshot()
            result["path"] = model.documentURL?.path ?? NSNull()
            result["folder"] = model.folderURL?.path ?? NSNull()
            result["anchor"] = snapshot["anchor"]
            result["scrollTop"] = snapshot["scrollTop"]
            result["notice"] = model.errorMessage ?? ""
            result["dirty"] = model.isDirty
            result["lastDocument"] = UserDefaults.standard.string(forKey: "lastDocument") ?? NSNull()
            if stage == "seed" || stage == "check" {
                result["passed"] = model.documentURL?.lastPathComponent == "document.md" && model.folderURL == root
                    && (snapshot["anchor"] as? Int) == 1500 && (snapshot["scrollTop"] as? Double ?? 0) > 500
            } else if stage == "missing" { result["passed"] = model.documentURL == nil && model.errorMessage != nil && model.folderURL == root }
            else if stage == "explicit" { result["passed"] = model.documentURL?.lastPathComponent == "explicit.md" }
            else { result["passed"] = model.documentURL == nil && UserDefaults.standard.string(forKey: "lastDocument") == nil }
            guard await model.canClose() else { throw CocoaError(.userCancelled) }
            UserDefaults.standard.synchronize()
        } catch { result["passed"] = false; result["error"] = error.localizedDescription }
        try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
            .write(to: root.appendingPathComponent("session-\(stage).json"), options: .atomic)
        // Leave this Swift task before AppKit starts its termination event loop.
        RunLoop.main.perform { NSApp.terminate(nil) }
    }
}
