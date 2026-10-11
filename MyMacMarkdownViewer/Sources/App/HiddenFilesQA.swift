import Foundation
import WebKit
#if SWIFT_PACKAGE
import MyMarkdownCore
#endif

@MainActor
enum HiddenFilesQA {
    static func run(model: AppModel, web: WKWebView, root: URL, relaunch: Bool) async {
        var report: [String: Any] = ["environment": "native macOS WKWebView", "relaunch": relaunch]
        let workspace = root.appendingPathComponent("workspace", isDirectory: true)
        let visible = workspace.appendingPathComponent("README.md")
        let design = workspace.appendingPathComponent(".claude/agents/design-reviewer.md")
        let paths = ["README.md", ".hidden.md", ".claude/agents/design-reviewer.md", ".claude/agents/refactorer.md", ".claude/skills/code-review-team/SKILL.md"]
        do {
            if relaunch {
                report["settingRestoredAfterRelaunch"] = model.settings.showHiddenFiles
                try await model.setQAWorkspace(workspace)
                try await waitUntil { !model.indexing && model.indexedFiles.count == paths.count }
                report["hiddenIndexRestoredAfterRelaunch"] = model.indexedFiles.contains(design)
                report["hiddenTreeRestoredAfterRelaunch"] = model.rootEntries.contains { $0.name == ".claude" }
            } else {
                for path in paths {
                    let file = workspace.appendingPathComponent(path)
                    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try Data(("# " + file.lastPathComponent + "\n\n숨김검증needle\n\n" + String(repeating: "읽던 문서와 편집 내용이 유지됩니다.\n\n", count: 70)).utf8).write(to: file)
                }
                model.settings.autosave = false
                model.settings.showHiddenFiles = false
                try await model.setQAWorkspace(workspace)
                try await model.resetQAFixture(visible)
                try await waitUntil { !model.indexing && model.indexedFiles == [visible] }
                report["defaultTreeHidesDotItems"] = !model.rootEntries.contains { $0.name.hasPrefix(".") }
                report["defaultQuickOpenHidesDotItems"] = model.indexedFiles == [visible]
                _ = try await web.callAsyncJavaScript("""
                    const snapshot = window.MarkdownHost.snapshot();
                    window.MarkdownHost.receive({ type: 'jump', sessionID: snapshot.sessionID, documentID: snapshot.documentID, from: 700 });
                    window.MarkdownHost.receive({ type: 'insert', sessionID: snapshot.sessionID, documentID: snapshot.documentID, text: 'QA unsaved edit ' });
                    document.querySelector('.cm-scroller').scrollTop = 700;
                    return window.MarkdownHost.snapshot();
                    """, arguments: [:], in: nil, contentWorld: .page)
                let before = try await model.bridge.snapshot(), session = model.sessionID
                model.settings.showHiddenFiles = true
                try await waitUntil { !model.indexing && model.indexedFiles.count == paths.count }
                let after = try await model.bridge.snapshot()
                report["enabledTreeShowsDotItems"] = model.rootEntries.contains { $0.name == ".claude" } && model.rootEntries.contains { $0.name == ".hidden.md" }
                report["enabledQuickOpenIncludesNestedHiddenFiles"] = model.indexedFiles.contains(design)
                report["documentAndSessionPreserved"] = model.documentURL == visible && model.sessionID == session
                report["unsavedTextPreserved"] = model.isDirty && before["text"] as? String == after["text"] as? String
                report["selectionPreserved"] = before["anchor"] as? Int == after["anchor"] as? Int && before["head"] as? Int == after["head"] as? Int
                report["scrollPreserved"] = abs((before["scrollTop"] as? Double ?? -1) - (after["scrollTop"] as? Double ?? -2)) < 1
                _ = await model.save()
                try await model.resetQAFixture(design)
                await model.revealCurrentFileInSidebar()
                report["hiddenCurrentDocumentRevealed"] = model.visibleFileRows.contains { $0.entry.url == design && $0.depth == 2 }
                model.folderQuery = "숨김검증needle"
                model.runFolderSearch()
                try await waitUntil { !model.folderSearching && model.folderSearchReport != nil }
                report["enabledFolderSearchIncludesHiddenFiles"] = model.folderSearchReport?.isComplete == true && model.folderSearchReport?.files.count == paths.count
                model.folderReplacement = "should never be saved"
                model.reviewFolderReplacement()
                guard let review = model.replacementReview else { throw CocoaError(.fileReadUnknown) }
                let hiddenBytes = try Data(contentsOf: design)
                model.settings.showHiddenFiles = false
                report["oldSearchAndReviewInvalidated"] = model.folderSearchReport == nil && model.replacementReview == nil
                let staleApply = await model.applyFolderReplacement(review, selected: [design])
                let afterStaleApply = try Data(contentsOf: design)
                report["staleReplacementRejected"] = staleApply == nil && afterStaleApply == hiddenBytes
                try await waitUntil { !model.indexing && model.indexedFiles == [visible] }
                report["hiddenDocumentStaysOpenWhenHiding"] = model.documentURL == design && model.currentFileRevealUnavailableReason?.contains("숨김") == true
                model.runFolderSearch()
                try await waitUntil { !model.folderSearching && model.folderSearchReport != nil }
                report["disabledSearchMatchesVisibleIndex"] = model.folderSearchReport?.files.map(\.url) == [visible]
                model.settings.showHiddenFiles = true
                try await waitUntil { !model.indexing && model.indexedFiles.count == paths.count }
                model.showFolderSearch(scope: workspace.appendingPathComponent(".claude", isDirectory: true))
                model.runFolderSearch()
                try await waitUntil { !model.folderSearching && model.folderSearchReport != nil }
                report["hiddenFolderScopeSearchWorks"] = model.folderSearchReport?.files.count == 3
                model.settings.showHiddenFiles = false
                report["hiddenScopeClearedWhenHiding"] = model.folderSearchScope == nil && model.folderSearchReport == nil
                model.settings.showHiddenFiles = true
                try await waitUntil { !model.indexing && model.indexedFiles.count == paths.count }
                if let claude = model.rootEntries.first(where: { $0.name == ".claude" }) { model.toggleFolder(claude) }
                model.runFolderSearch()
                model.settings.showHiddenFiles = false
                model.settings.showHiddenFiles = true
                model.settings.showHiddenFiles = false
                try await waitUntil { !model.indexing && model.indexedFiles == [visible] }
                report["rapidTogglesRejectStaleResults"] = !model.rootEntries.contains { $0.name.hasPrefix(".") } && !model.folderSearching && model.folderSearchReport == nil
                model.settings.showHiddenFiles = true
                try await waitUntil { !model.indexing && model.indexedFiles.count == paths.count }
                model.sidebarMode = "files"
                await model.revealCurrentFileInSidebar()
                let saved = UserDefaults.standard.data(forKey: "readingSettings")
                report["settingWrittenToPreferences"] = saved.flatMap { try? JSONDecoder().decode(ReadingSettings.self, from: $0) }?.showHiddenFiles == true
            }
            let checks = report.filter { $0.key != "relaunch" }.values.compactMap { $0 as? Bool }
            report["passed"] = checks.allSatisfy { $0 } && !checks.isEmpty
        } catch {
            report["passed"] = false; report["error"] = error.localizedDescription
        }
        try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: root.appendingPathComponent(relaunch ? "hidden-files-relaunch-qa.json" : "hidden-files-qa.json"), options: .atomic)
    }

    private static func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<300 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(30))
        }
        throw CocoaError(.fileReadUnknown)
    }
}
