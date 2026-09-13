import Foundation
import WebKit

@MainActor
enum FileRevealQA {
    static func run(model: AppModel, root: URL) async {
        guard let web = model.bridge.webView else { return }
        var report: [String: Any] = ["environment": "native macOS WKWebView", "physicalIMEVerified": false]
        do {
            let workspace = root.appendingPathComponent("workspace", isDirectory: true)
            let target = workspace.appendingPathComponent("A-target/B-inner/current-document.md")
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            for number in 0..<240 {
                let file = workspace.appendingPathComponent(String(format: "note-%03d.md", number))
                if !FileManager.default.fileExists(atPath: file.path) { try Data("# Sidebar fixture".utf8).write(to: file) }
            }
            let source = (0..<90).map { "## 읽던 위치 \($0)\n\n본문과 파일 목록은 따로 움직여야 합니다.\n\n" }.joined()
            try Data(source.utf8).write(to: target)
            model.settings.theme = .night; model.settings.autosave = false
            try await model.setQAWorkspace(workspace)
            try await model.resetQAFixture(target)
            for _ in 0..<100 {
                if model.rootEntries.count > 200 && !model.indexing { break }
                try await Task.sleep(for: .milliseconds(30))
            }
            guard model.rootEntries.count > 200 else { throw CocoaError(.fileReadUnknown) }
            _ = try await web.callAsyncJavaScript("""
                const snapshot = window.MarkdownHost.snapshot();
                window.MarkdownHost.receive({ type: 'jump', sessionID: snapshot.sessionID, documentID: snapshot.documentID, from: 700 });
                window.MarkdownHost.receive({ type: 'insert', sessionID: snapshot.sessionID, documentID: snapshot.documentID, text: 'QA edit ' });
                document.querySelector('.cm-scroller').scrollTop = 700;
                return window.MarkdownHost.snapshot();
                """, arguments: [:], in: nil, contentWorld: .page)
            try await Task.sleep(for: .milliseconds(150))
            let before = try await model.bridge.snapshot(), session = model.sessionID
            model.expanded = []; model.children = [:]
            model.refreshFolder()
            await model.revealCurrentFileInSidebar()
            try await Task.sleep(for: .milliseconds(350))
            await model.revealCurrentFileInSidebar()
            let after = try await model.bridge.snapshot()
            report["expandedAncestors"] = model.visibleFileRows.contains { $0.entry.name == "current-document.md" && $0.depth == 2 }
            report["survivesRefreshAndRepeatedReveal"] = model.visibleFileRows.contains { model.isCurrentSidebarFile($0.entry) }
            report["sameDocumentSession"] = session == model.sessionID
            report["sameText"] = before["text"] as? String == after["text"] as? String
            report["sameSelection"] = before["anchor"] is Int && before["head"] is Int
                && before["anchor"] as? Int == after["anchor"] as? Int && before["head"] as? Int == after["head"] as? Int
            report["sameScroll"] = (before["scrollTop"] as? Double ?? 0) > 500
                && abs((before["scrollTop"] as? Double ?? -1) - (after["scrollTop"] as? Double ?? -2)) < 1
            report["dirtyEditPreserved"] = model.isDirty && (after["text"] as? String)?.contains("QA edit ") == true
            report["fixtureFileCount"] = model.indexedFiles.count
            let checks = ["expandedAncestors", "survivesRefreshAndRepeatedReveal", "sameDocumentSession", "sameText", "sameSelection", "sameScroll", "dirtyEditPreserved"]
            report["passed"] = checks.allSatisfy { report[$0] as? Bool == true }
            _ = await model.save()
            // Leave a saved fixture with collapsed parents for real button/scroll QA.
            model.expanded = []; model.fileRevealRequest.map { model.completeSidebarReveal($0.id) }
        } catch {
            report["passed"] = false; report["error"] = error.localizedDescription
        }
        try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: root.appendingPathComponent("file-reveal-qa.json"), options: .atomic)
    }
}
