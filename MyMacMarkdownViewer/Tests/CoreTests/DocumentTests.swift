import Foundation
import Testing
@testable import MyMarkdownCore

struct DocumentTests {
    @Test func unchangedBytesIncludingBOMAndMixedNewlines() throws {
        let data = Data([0xEF, 0xBB, 0xBF]) + Data("# 제목\r\n\r\n한글 👩🏽‍💻\nlast\r".utf8)
        let codec = try DocumentCodec(data: data)
        #expect(codec.encode(codec.originalText) == data)
        #expect(codec.originalText == "# 제목\n\n한글 👩🏽‍💻\nlast\n")
        let edited = codec.encode(codec.originalText.replacingOccurrences(of: "제목", with: "바뀐 제목"))
        #expect(edited.starts(with: [0xEF, 0xBB, 0xBF]))
        #expect(String(data: edited.dropFirst(3), encoding: .utf8)?.contains("한글 👩🏽‍💻\nlast\r") == true)
    }

    @Test func largeUniformRewriteKeepsBOMEndingsAndFinalNewline() throws {
        for ending in ["\n", "\r\n", "\r"] {
            let source = (0..<4000).map { "기존 줄 \($0)" }.joined(separator: ending)
            let text = (0..<4000).map { "바뀐 줄 \($0) 😀" }.joined(separator: "\n") + "\n"
            let codec = try DocumentCodec(data: Data([0xEF, 0xBB, 0xBF]) + Data(source.utf8))
            let began = Date.now
            let bytes = codec.encode(text)
            #expect(Date.now.timeIntervalSince(began) < 2)
            #expect(bytes == Data([0xEF, 0xBB, 0xBF]) + Data(text.replacingOccurrences(of: "\n", with: ending).utf8))
        }
    }

    @Test func largeMixedRewritePreservesStableAndMatchedLineTerminators() throws {
        let old = "prefix\r\n" + (0..<4000).map { "old \($0)\n" }.joined() + "unchanged middle\r" + (0..<4000).map { "tail \($0)\n" }.joined() + "suffix\r\n"
        let text = "prefix\n" + (0..<4000).map { "new \($0)\n" }.joined() + "unchanged middle\n" + (0..<4000).map { "changed \($0)\n" }.joined() + "suffix\n"
        let codec = try DocumentCodec(data: Data(old.utf8))
        let began = Date.now
        let encoded = codec.encode(text)
        #expect(Date.now.timeIntervalSince(began) < 2)
        let output = String(data: encoded, encoding: .utf8)!
        #expect(DocumentCodec.normalize(output) == text)
        #expect(output.hasPrefix("prefix\r\n"))
        #expect(output.contains("unchanged middle\rchanged 0\r\n"))
        #expect(output.hasSuffix("suffix\r\n"))
    }

    @Test func unsupportedEncodingFailsWithoutLossyConversion() {
        #expect(throws: DocumentError.unsupportedEncoding) { try DocumentCodec(data: Data([0xFF, 0xFE, 0x41, 0x00])) }
        #expect(throws: DocumentError.unsupportedEncoding) { try DocumentCodec(data: Data([0xC0, 0xAF])) }
    }

    @Test func utf16ChangesPreserveKoreanAndEmoji() throws {
        let source = "한글😀ABC"
        let result = try TextChange.apply([TextChange(from: 2, to: 4, insert: "👩🏽‍💻"), TextChange(from: 5, to: 6, insert: "수정")], to: source)
        #expect(result == "한글👩🏽‍💻A수정C")
        #expect(throws: DocumentError.invalidChange) { try TextChange.apply([TextChange(from: 3, to: 4, insert: "")], to: source) }
        #expect(throws: DocumentError.invalidChange) { try TextChange.apply([TextChange(from: 0, to: 3, insert: ""), TextChange(from: 2, to: 4, insert: "")], to: source) }
    }

    @Test func themeDefaultsAreDark() throws {
        #expect(ReadingSettings().theme == .dark)
        var settings = ReadingSettings(); settings.theme = .system
        let restored = try JSONDecoder().decode(ReadingSettings.self, from: JSONEncoder().encode(settings))
        #expect(restored.theme == .system)
    }

    @Test func nightThemePersistsWithoutChangingExistingChoices() throws {
        for theme in ThemeChoice.allCases {
            var settings = ReadingSettings(); settings.theme = theme; settings.fontSize = 19
            settings.focusMode = true; settings.typewriterMode = true
            let restored = try JSONDecoder().decode(ReadingSettings.self, from: JSONEncoder().encode(settings))
            #expect(restored == settings)
        }
        let previous = Data(#"{"theme":"dark","fontSize":17,"lineHeight":1.7,"contentWidth":800,"fontFamily":"system","autosave":true}"#.utf8)
        let migrated = try JSONDecoder().decode(ReadingSettings.self, from: previous)
        #expect(migrated.theme == .dark)
        #expect(!migrated.focusMode)
        #expect(!migrated.typewriterMode)
        #expect(ReadingSettings().theme == .dark)
        #expect(ThemeChoice.allCases == [.dark, .night, .light, .system])
    }

    @Test func saveConflictAndDeletionNeverReplaceExternalBytes() async throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("doc.md"), store = FileStore(supportURL: root.appendingPathComponent("support"))
        try Data("old\r\n".utf8).write(to: file)
        let opened = try await store.read(file)
        try Data("external".utf8).write(to: file, options: .atomic)
        await #expect(throws: DocumentError.conflict) { try await store.save(file, text: "mine\n", codec: opened.codec, expectedHash: opened.hash) }
        #expect(try String(contentsOf: file, encoding: .utf8) == "external")
        try FileManager.default.removeItem(at: file)
        await #expect(throws: DocumentError.deleted) { try await store.save(file, text: "mine", codec: opened.codec, expectedHash: opened.hash) }
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func atomicSaveAndBackupPreserveBaseline() async throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("doc.md"), support = root.appendingPathComponent("support")
        let store = FileStore(supportURL: support)
        let original = Data([0xEF, 0xBB, 0xBF]) + Data("first\r\n".utf8)
        try original.write(to: file)
        let opened = try await store.read(file)
        let saved = try await store.save(file, text: "first\nsecond\n", codec: opened.codec, expectedHash: opened.hash)
        #expect(try Data(contentsOf: file) == saved.codec.originalData)
        #expect(saved.codec.hasBOM)
        #expect(saved.codec.lineEnding == "\r\n")
        let directory = support.appendingPathComponent("Backups/" + DocumentCodec.hash(Data(file.path.utf8)))
        let backups = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        #expect(backups.count == 1)
        #expect(try Data(contentsOf: backups[0]) == original)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).allSatisfy { !$0.hasSuffix(".tmp") })
    }

    @Test func concurrentSavesWithSameBaselineOnlyOneWins() async throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("doc.md"), store = FileStore(supportURL: root.appendingPathComponent("support"))
        try Data("baseline".utf8).write(to: file)
        let opened = try await store.read(file)
        let results = await withTaskGroup(of: Bool.self, returning: [Bool].self) { group in
            for text in ["first", "second"] { group.addTask { do { _ = try await store.save(file, text: text, codec: opened.codec, expectedHash: opened.hash); return true } catch { return false } } }
            var results: [Bool] = []; for await result in group { results.append(result) }; return results
        }
        #expect(results.filter { $0 }.count == 1)
        #expect(["first", "second"].contains(try String(contentsOf: file, encoding: .utf8)))
    }

    @Test func initialSaveCreatesFileAndRefusesAnUnexpectedExistingTarget() async throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("new.md")
        let store = FileStore(supportURL: root.appendingPathComponent("support"))
        let codec = try DocumentCodec(data: Data())
        let text = "# 새 문서\n\n```json\n{\"title\": \"한글 👋\"}\n```\n"
        let saved = try await store.save(file, text: text, codec: codec, expectedHash: nil)
        #expect(try Data(contentsOf: file) == Data(text.utf8))
        #expect(saved.codec.originalText == text)
        await #expect(throws: DocumentError.conflict) { try await store.save(file, text: "overwrite", codec: codec, expectedHash: nil) }
        #expect(try Data(contentsOf: file) == Data(text.utf8))
    }

    @Test func symlinkTargetsAreNotWrittenOrTraversed() async throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("real.md"), link = root.appendingPathComponent("link.md")
        try Data("safe".utf8).write(to: file)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        let store = FileStore(supportURL: root.appendingPathComponent("support"))
        await #expect(throws: DocumentError.unsafePath) { try await store.read(link) }
        #expect(try FolderScanner.children(of: root).map(\.name) == ["real.md"])
    }

    @Test func scannerListsMarkdownExtensionVariantsButSkipsSymlinkFiles() throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        for name in ["guide.markdown", "README.MARKDOWN", "notes.MD"] {
            try Data(name.utf8).write(to: root.appendingPathComponent(name))
        }
        let linked = root.appendingPathComponent("linked.MARKDOWN")
        try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: root.appendingPathComponent("guide.markdown"))

        #expect(try FolderScanner.children(of: root).map(\.name) == ["guide.markdown", "notes.MD", "README.MARKDOWN"])
        #expect(FolderScanner.index(root).map(\.lastPathComponent) == ["guide.markdown", "notes.MD", "README.MARKDOWN"])
    }

    @Test func recoverySurvivesStoreRecreation() async throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let record = RecoveryRecord(id: UUID().uuidString, path: nil, text: "복구 👋", codec: try DocumentCodec(data: Data()), revision: 7)
        try await FileStore(supportURL: root).writeRecovery(record)
        let restored = try await FileStore(supportURL: root).recoveries()
        #expect(restored.count == 1); #expect(restored[0].text == record.text); #expect(restored[0].revision == 7)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MyMarkdownTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true); return url
    }
}
