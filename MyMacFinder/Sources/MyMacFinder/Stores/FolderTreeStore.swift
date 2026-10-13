import Combine
import Foundation

struct FolderTreeNode: Identifiable, Equatable {
    let url: URL
    let title: String
    let isCycle: Bool
    var id: URL { url }
}

struct FolderTreeRow: Identifiable {
    let node: FolderTreeNode
    let depth: Int
    var id: URL { node.id }
}

@MainActor
final class FolderTreeStore: ObservableObject {
    @Published private(set) var rootURL: URL?
    @Published private(set) var expanded: Set<URL> = []
    @Published private(set) var children: [URL: [FolderTreeNode]] = [:]
    @Published private(set) var loading: Set<URL> = []
    @Published private(set) var errors: [URL: String] = [:]
    private let reader: any FileSystemServicing
    private var tokens: [URL: UUID] = [:]
    private var showHidden = false

    init(reader: any FileSystemServicing = FileSystemService()) { self.reader = reader }

    var rows: [FolderTreeRow] {
        guard let rootURL else { return [] }
        var result: [FolderTreeRow] = []
        func append(_ node: FolderTreeNode, depth: Int) {
            result.append(FolderTreeRow(node: node, depth: depth))
            guard depth < 64, expanded.contains(node.url), !node.isCycle else { return }
            for child in children[node.url] ?? [] { append(child, depth: depth + 1) }
        }
        append(FolderTreeNode(url: rootURL, title: rootURL.lastPathComponent.isEmpty ? "/" : rootURL.lastPathComponent, isCycle: false), depth: 0)
        return result
    }

    func followNavigation(to url: URL, showHidden: Bool) async {
        let url = url.standardizedFileURL
        if let rootURL, Self.isWithin(url, root: rootURL), self.showHidden == showHidden {
            // Keep the current tree root while navigating within it.
        } else {
            await setRoot(url, showHidden: showHidden)
        }
        guard let rootURL, Self.isWithin(url, root: rootURL) else { return }
        let components = url.pathComponents.dropFirst(rootURL.pathComponents.count)
        var parent = rootURL
        // Reveal the current folder in its existing tree without traversing unrelated branches.
        for component in components.dropLast() {
            let childPath = parent.appendingPathComponent(component).path
            guard let node = children[parent]?.first(where: { $0.url.path == childPath }), !node.isCycle else { break }
            if !expanded.contains(node.url) { await toggle(node) }
            parent = node.url
        }
    }

    func setRoot(_ url: URL, showHidden: Bool) async {
        tokens.removeAll()
        children = [:]; errors = [:]; loading = []; expanded = []
        rootURL = url.standardizedFileURL
        self.showHidden = showHidden
        await toggle(tryRootNode(url))
    }

    func toggle(_ node: FolderTreeNode) async {
        guard !node.isCycle else { return }
        let url = node.url
        if expanded.contains(url) {
            expanded.remove(url)
            tokens.removeValue(forKey: url)
            loading.remove(url)
            return
        }
        expanded.insert(url)
        await loadChildren(at: url)
    }

    func refreshExpandedDirectory(_ url: URL) async {
        let url = url.standardizedFileURL
        guard expanded.contains(url) else { return }
        await loadChildren(at: url)
    }

    private func loadChildren(at url: URL) async {
        let token = UUID()
        tokens[url] = token
        loading.insert(url); errors.removeValue(forKey: url)
        let expectedRoot = rootURL
        do {
            let entries = try await reader.contentsOfDirectory(at: url, options: DirectoryReadOptions(showHiddenFiles: showHidden))
            guard rootURL == expectedRoot, tokens[url] == token, expanded.contains(url) else { return }
            let ancestorPaths = ancestorCanonicalPaths(for: url)
            children[url] = entries.filter { $0.isDirectoryLike && $0.kind != .package }.map {
                FolderTreeNode(url: $0.url, title: $0.name, isCycle: ancestorPaths.contains($0.url.resolvingSymlinksInPath().standardizedFileURL.path))
            }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        } catch {
            guard rootURL == expectedRoot, tokens[url] == token, expanded.contains(url) else { return }
            children[url] = []
            errors[url] = error.localizedDescription
        }
        guard tokens[url] == token else { return }
        loading.remove(url)
    }

    private func tryRootNode(_ url: URL) -> FolderTreeNode {
        FolderTreeNode(url: url.standardizedFileURL, title: url.lastPathComponent, isCycle: false)
    }

    private func ancestorCanonicalPaths(for url: URL) -> Set<String> {
        guard let rootURL else { return [] }
        var ancestor = url.standardizedFileURL
        var paths: Set<String> = []
        for _ in 0..<65 {
            paths.insert(ancestor.resolvingSymlinksInPath().standardizedFileURL.path)
            if ancestor.path == rootURL.path { break }
            let parent = ancestor.deletingLastPathComponent()
            if parent.path == ancestor.path { break }
            ancestor = parent
        }
        return paths
    }

    private static func isWithin(_ url: URL, root: URL) -> Bool {
        let child = url.standardizedFileURL.pathComponents
        let parent = root.standardizedFileURL.pathComponents
        return child.count >= parent.count && Array(child.prefix(parent.count)) == parent
    }
}
