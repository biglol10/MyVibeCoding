import Foundation

/// Literal folder search. Offsets deliberately use UTF-16, matching AppKit and the editor bridge.
public enum FolderSearch {
    public struct Options: Sendable, Equatable {
        public var query: String
        public var caseSensitive: Bool
        public var maximumResults: Int
        public var maximumFileBytes: Int
        public var maximumRetainedBytes: Int

        public init(query: String, caseSensitive: Bool = false, maximumResults: Int = 1_000, maximumFileBytes: Int = 32 * 1024 * 1024, maximumRetainedBytes: Int = 64 * 1024 * 1024) {
            self.query = query
            self.caseSensitive = caseSensitive
            self.maximumResults = max(1, maximumResults)
            self.maximumFileBytes = max(1, min(maximumFileBytes, 32 * 1024 * 1024))
            self.maximumRetainedBytes = max(1, min(maximumRetainedBytes, 64 * 1024 * 1024))
        }
    }

    public struct Match: Sendable, Equatable, Identifiable {
        public let range: Range<Int>
        public let line: Int
        public let column: Int
        public let snippet: String
        public var id: String { "\(range.lowerBound):\(range.upperBound)" }
        public init(range: Range<Int>, line: Int, column: Int, snippet: String) {
            self.range = range; self.line = line; self.column = column; self.snippet = snippet
        }
    }

    public struct FileResult: Sendable, Identifiable {
        public let url: URL
        public let workspaceRoot: URL
        public let codec: DocumentCodec
        public let originalHash: String
        public let matches: [Match]
        public var id: String { url.path }
    }

    public struct Issue: Sendable, Equatable, Identifiable {
        public let url: URL
        public let message: String
        public var id: String { url.path + message }
        public init(url: URL, message: String) { self.url = url; self.message = message }
    }

    public struct ScanReport: Sendable {
        public let files: [FileResult]
        public let issues: [Issue]
        public let isTruncated: Bool
        public let wasCancelled: Bool
        public var isComplete: Bool { !isTruncated && !wasCancelled && issues.isEmpty }
        public var replacementPlan: ReplacementPlan { ReplacementPlan(files: files) }
    }

    public struct ReplacementPlan: Sendable {
        public struct File: Sendable, Identifiable {
            public let url: URL
            public let workspaceRoot: URL
            public let codec: DocumentCodec
            public let originalHash: String
            public let matches: [Match]
            public var id: String { url.path }
            fileprivate init(_ result: FileResult) {
                url = result.url; workspaceRoot = result.workspaceRoot; codec = result.codec; originalHash = result.originalHash; matches = result.matches
            }
        }
        public let files: [File]
        public init(files: [FileResult]) { self.files = files.map(File.init) }
    }

    public struct ApplyOutcome: Sendable, Identifiable, Equatable {
        public enum Status: String, Sendable { case saved, excluded, stale, failed, notAttempted }
        public let url: URL
        public let status: Status
        public let message: String?
        public var id: String { url.path }
    }

    public struct ApplyReport: Sendable {
        public let outcomes: [ApplyOutcome]
        public let preflightPassed: Bool
        public var savedCount: Int { outcomes.filter { $0.status == .saved }.count }
    }

    public static func scan(folder: URL, options: Options) async -> ScanReport {
        let task = Task.detached(priority: .userInitiated) { scanSynchronously(folder: folder, options: options) }
        return await withTaskCancellationHandler(operation: { await task.value }, onCancel: { task.cancel() })
    }

    /// Produces the reviewed output without touching disk.
    public static func preview(_ file: ReplacementPlan.File, replacement: String) throws -> String {
        try TextChange.apply(file.matches.map { TextChange(from: $0.range.lowerBound, to: $0.range.upperBound, insert: replacement) }, to: file.codec.originalText)
    }

    /// Checks every selected file before the first write. A later external write can still make a
    /// later individual save fail, so callers must present this as a partial, non-transactional result.
    public static func apply(plan: ReplacementPlan, replacement: String, including selectedURLs: Set<URL>? = nil, store: FileStore) async -> ApplyReport {
        let selected = plan.files.filter { isSelected($0.url, in: selectedURLs) }
        let excluded = plan.files.filter { !isSelected($0.url, in: selectedURLs) }
        var outcomes = excluded.map { ApplyOutcome(url: $0.url, status: .excluded, message: nil) }
        var previews: [(ReplacementPlan.File, String)] = []
        var preflightFailed = false
        for file in selected {
            do {
                guard FileManager.default.fileExists(atPath: file.url.path) else {
                    outcomes.append(ApplyOutcome(url: file.url, status: .stale, message: "검색 후 파일이 삭제되었습니다.")); preflightFailed = true; continue
                }
                try await validatePlanPath(file)
                guard try await store.read(file.url).hash == file.originalHash else {
                    outcomes.append(ApplyOutcome(url: file.url, status: .stale, message: "검색 후 파일이 변경되었습니다.")); preflightFailed = true; continue
                }
                previews.append((file, try preview(file, replacement: replacement)))
            } catch {
                outcomes.append(ApplyOutcome(url: file.url, status: isStale(error) ? .stale : .failed, message: errorMessage(error))); preflightFailed = true
            }
        }
        if preflightFailed {
            let checked = Set(outcomes.map(\.url))
            outcomes += selected.filter { !checked.contains($0.url) }.map { ApplyOutcome(url: $0.url, status: .notAttempted, message: "다른 선택 파일의 사전 확인이 실패해 적용하지 않았습니다.") }
            return ApplyReport(outcomes: ordered(outcomes, by: plan.files), preflightPassed: false)
        }
        for (file, output) in previews {
            do {
                try await validatePlanPath(file)
                _ = try await store.save(file.url, text: output, codec: file.codec, expectedHash: file.originalHash)
                outcomes.append(ApplyOutcome(url: file.url, status: .saved, message: nil))
            } catch {
                outcomes.append(ApplyOutcome(url: file.url, status: isStale(error) ? .stale : .failed, message: errorMessage(error)))
            }
        }
        return ApplyReport(outcomes: ordered(outcomes, by: plan.files), preflightPassed: true)
    }

    private static func ordered(_ outcomes: [ApplyOutcome], by files: [ReplacementPlan.File]) -> [ApplyOutcome] {
        let positions = Dictionary(uniqueKeysWithValues: files.enumerated().map { ($0.element.url, $0.offset) })
        return outcomes.sorted { (positions[$0.url] ?? .max) < (positions[$1.url] ?? .max) }
    }

    private static func isStale(_ error: Error) -> Bool {
        guard let documentError = error as? DocumentError else { return false }
        return documentError == .conflict || documentError == .deleted
    }

    private static func errorMessage(_ error: Error) -> String {
        if let documentError = error as? DocumentError { return documentError.localizedDescription }
        return "파일을 읽거나 저장할 수 없습니다. 접근 권한과 동기화 상태를 확인해 주세요."
    }

    private static func isSelected(_ url: URL, in selectedURLs: Set<URL>?) -> Bool {
        guard let selectedURLs else { return true }
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        return selectedURLs.contains { $0.resolvingSymlinksInPath().standardizedFileURL.path == path }
    }

    private static func validatePlanPath(_ file: ReplacementPlan.File) async throws {
        let documents = try await WorkspaceFiles().markdownDocuments(root: file.workspaceRoot, source: file.url)
        let target = file.url.resolvingSymlinksInPath().standardizedFileURL.path
        guard documents.contains(where: { $0.resolvingSymlinksInPath().standardizedFileURL.path == target }) else {
            throw WorkspaceFileError.unsafePath
        }
    }

    private static func scanSynchronously(folder: URL, options: Options) -> ScanReport {
        guard !options.query.isEmpty else { return ScanReport(files: [], issues: [Issue(url: folder, message: "검색할 텍스트가 비어 있습니다.")], isTruncated: false, wasCancelled: false) }
        let fm = FileManager.default
        // Check the user-selected spelling before resolving /var-style system aliases.
        guard isVisibleDirectory(folder) else { return ScanReport(files: [], issues: [Issue(url: folder, message: "폴더에 접근할 수 없거나 안전하지 않습니다.")], isTruncated: false, wasCancelled: false) }
        let workspaceRoot = folder.resolvingSymlinksInPath().standardizedFileURL
        var files: [FileResult] = [], issues: [Issue] = []
        guard isVisibleDirectory(workspaceRoot) else { return ScanReport(files: [], issues: [Issue(url: folder, message: "폴더에 접근할 수 없거나 안전하지 않습니다.")], isTruncated: false, wasCancelled: false) }
        guard let enumerator = fm.enumerator(at: workspaceRoot, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey, .isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { url, _ in
            issues.append(Issue(url: url, message: "폴더 항목을 읽을 수 없습니다.")); return true
        }) else {
            return ScanReport(files: [], issues: [Issue(url: folder, message: "폴더 목록을 읽을 수 없습니다.")], isTruncated: false, wasCancelled: false)
        }
        var truncated = false, totalMatches = 0, retainedBytes = 0
        for case let url as URL in enumerator {
            if Task.isCancelled { return ScanReport(files: files, issues: issues, isTruncated: truncated, wasCancelled: true) }
            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey, .isRegularFileKey]) else { issues.append(Issue(url: url, message: "파일 정보를 읽을 수 없습니다.")); continue }
            if values.isSymbolicLink == true || values.isPackage == true { if values.isDirectory == true { enumerator.skipDescendants() }; continue }
            guard values.isRegularFile == true, url.pathExtension.lowercased() == "md" else { continue }
            do {
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                var bytes = Data()
                while bytes.count <= options.maximumFileBytes {
                    if Task.isCancelled { return ScanReport(files: files, issues: issues, isTruncated: truncated, wasCancelled: true) }
                    let chunk = try handle.read(upToCount: min(1024 * 1024, options.maximumFileBytes + 1 - bytes.count)) ?? Data()
                    if chunk.isEmpty { break }
                    bytes.append(chunk)
                }
                guard bytes.count <= options.maximumFileBytes else {
                    issues.append(Issue(url: url, message: "검색 크기 한도를 넘는 문서는 건너뛰었습니다. 더 작은 문서로 나누어 검색하세요.")); continue
                }
                let codec = try DocumentCodec(data: bytes)
                let remaining = options.maximumResults - totalMatches
                let probeLimit = remaining == .max ? .max : remaining + 1
                let search = literalMatches(in: codec.originalText, options: options, limit: probeLimit)
                if search.wasCancelled { return ScanReport(files: files, issues: issues, isTruncated: truncated, wasCancelled: true) }
                let matches = Array(search.matches.prefix(remaining))
                if search.matches.count > remaining { truncated = true }
                if !matches.isEmpty {
                    guard retainedBytes + bytes.count <= options.maximumRetainedBytes else {
                        issues.append(Issue(url: url, message: "검색 결과의 문서 용량 한도에 도달했습니다. 더 작은 폴더에서 검색하세요."))
                        truncated = true; break
                    }
                    retainedBytes += bytes.count
                }
                totalMatches += matches.count
                if !matches.isEmpty { files.append(FileResult(url: url, workspaceRoot: workspaceRoot, codec: codec, originalHash: DocumentCodec.hash(codec.originalData), matches: matches)) }
                if truncated { break }
            } catch { issues.append(Issue(url: url, message: errorMessage(error))) }
        }
        return ScanReport(files: files, issues: issues, isTruncated: truncated, wasCancelled: false)
    }

    private static func isVisibleDirectory(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey]) else { return false }
        return values.isDirectory == true && values.isSymbolicLink != true && values.isPackage != true
    }

    private static func literalMatches(in text: String, options: Options, limit: Int) -> (matches: [Match], wasCancelled: Bool) {
        guard limit > 0 else { return ([], false) }
        let source = text as NSString
        let compare: NSString.CompareOptions = options.caseSensitive ? [] : .caseInsensitive
        var lineStarts = [0]
        for offset in 0..<source.length where source.character(at: offset) == 10 { lineStarts.append(offset + 1) }
        var start = 0, result: [Match] = []
        while start < source.length && result.count < limit {
            if Task.isCancelled { return (result, true) }
            let range = source.range(of: options.query, options: compare, range: NSRange(location: start, length: source.length - start))
            guard range.location != NSNotFound else { break }
            var low = 0, high = lineStarts.count
            while low < high {
                let middle = (low + high) / 2
                if lineStarts[middle] <= range.location { low = middle + 1 } else { high = middle }
            }
            let lineIndex = low - 1
            let lineStart = lineStarts[lineIndex]
            let lineEnd = lineIndex + 1 < lineStarts.count ? lineStarts[lineIndex + 1] - 1 : source.length
            result.append(Match(range: range.location..<(range.location + range.length), line: lineIndex + 1, column: range.location - lineStart + 1, snippet: source.substring(with: NSRange(location: lineStart, length: lineEnd - lineStart))))
            start = range.location + max(1, range.length)
        }
        return (result, false)
    }

}
