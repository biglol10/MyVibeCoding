import Foundation

public struct LargeFileScanner: Sendable {
    private let roots: [URL]
    private let minimumSize: Int64
    private let recursive: Bool

    public init(
        roots: [URL],
        minimumSize: Int64 = 500 * 1_024 * 1_024,
        recursive: Bool = true
    ) {
        self.roots = roots
        self.minimumSize = minimumSize
        self.recursive = recursive
    }

    public func scan() async throws -> [LargeFileCandidate] {
        var candidates: [LargeFileCandidate] = []
        for root in roots {
            guard !isSystemRoot(root) else { continue }
            guard FileManager.default.fileExists(atPath: root.path) else { continue }
            candidates.append(contentsOf: try scan(root: root))
        }
        return candidates.sorted {
            if $0.size == $1.size {
                return $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending
            }
            return $0.size > $1.size
        }
    }

    private func scan(root: URL) throws -> [LargeFileCandidate] {
        var results: [LargeFileCandidate] = []
        let displayRoot = root
        let resolvedRoot = root.resolvingSymlinksInPath().standardizedFileURL
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isPackageKey, .contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else {
            return []
        }

        for case let url as URL in enumerator {
            if shouldSkipDirectory(url) {
                enumerator.skipDescendants()
                continue
            }

            if shouldSkipPackage(url) {
                enumerator.skipDescendants()
                continue
            }

            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey])
            guard values?.isRegularFile == true else { continue }

            let size = Int64(values?.fileSize ?? 0)
            guard size >= minimumSize else { continue }

            results.append(
                LargeFileCandidate(
                    url: displayURL(for: url, displayRoot: displayRoot, resolvedRoot: resolvedRoot),
                    size: size,
                    modifiedAt: values?.contentModificationDate,
                    kind: LargeFileKind.infer(from: url),
                    rootURL: displayRoot,
                    defaultSelected: false
                )
            )
        }

        return results
    }

    private func shouldSkipDirectory(_ url: URL) -> Bool {
        guard !recursive else { return false }
        return (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    private func displayURL(for url: URL, displayRoot: URL, resolvedRoot: URL) -> URL {
        let resolvedPath = resolvedRoot.path
        let urlPath = url.path
        if urlPath.hasPrefix("/private/var/") {
            return URL(fileURLWithPath: String(urlPath.dropFirst("/private".count)))
        }
        if urlPath.hasPrefix("/private" + displayRoot.path) {
            return URL(fileURLWithPath: String(urlPath.dropFirst("/private".count)))
        }
        guard displayRoot.path != resolvedPath else { return url }
        guard urlPath == resolvedPath || urlPath.hasPrefix(resolvedPath + "/") else { return url }

        let suffix = String(urlPath.dropFirst(resolvedPath.count))
        return URL(fileURLWithPath: displayRoot.path + suffix)
    }

    private func shouldSkipPackage(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if ["app", "framework", "bundle", "photoslibrary"].contains(ext) {
            return true
        }
        return (try? url.resourceValues(forKeys: [.isPackageKey]).isPackage) == true
    }

    private func isSystemRoot(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return path == "/System"
            || path.hasPrefix("/System/")
            || path == "/bin"
            || path.hasPrefix("/bin/")
            || path == "/sbin"
            || path.hasPrefix("/sbin/")
            || path == "/usr"
            || path.hasPrefix("/usr/")
    }
}
