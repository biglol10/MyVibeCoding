import Foundation
import MyMacSearchCore
import Observation

@MainActor
@Observable
public final class SearchViewModel {
    public var query = "" {
        didSet {
            guard query != oldValue else { return }
            if oldValue.isEmpty, !query.isEmpty, sort == .modifiedNewest {
                sort = .relevance
                return
            }
            scheduleSearch()
        }
    }
    public var sort: SearchSort = .modifiedNewest {
        didSet {
            guard sort != oldValue else { return }
            scheduleSearch()
        }
    }
    public private(set) var rows: [IndexedEntry] = []
    public var selectedEntryID: Int64?
    public private(set) var parserError: SearchQueryParseError?
    public private(set) var searchError: String?
    public private(set) var isSearching = false
    public private(set) var isLoadingMore = false
    public private(set) var canLoadMore = false
    public private(set) var tokens: [SearchQueryToken] = []
    public private(set) var recentSearches: [RecentSearch] = []
    public private(set) var savedSearches: [SavedSearch] = []
    public private(set) var libraryError: String?

    private let searcher: any IndexSearching
    private let libraryStore: (any SearchLibraryStoring)?
    private let onExplicitSortChange: @MainActor (SearchSort) -> Void
    private let debounce: Duration
    private let pageSize: Int
    private var parsedQuery = SearchQuery()
    private var nextCursor: SearchPageCursor?
    private var searchGeneration: UInt64 = 0
    private var searchTask: Task<Void, Never>?
    private var loadMoreTask: Task<Void, Never>?

    public init(
        searcher: any IndexSearching,
        libraryStore: (any SearchLibraryStoring)? = nil,
        initialSort: SearchSort = .modifiedNewest,
        onExplicitSortChange: @escaping @MainActor (SearchSort) -> Void = { _ in },
        debounce: Duration = .milliseconds(60),
        pageSize: Int = 200
    ) {
        self.searcher = searcher
        self.libraryStore = libraryStore
        self.sort = initialSort
        self.onExplicitSortChange = onExplicitSortChange
        self.debounce = debounce
        self.pageSize = min(max(pageSize, 1), 500)
        reloadLibrary()
    }

    deinit {
        MainActor.assumeIsolated {
            searchTask?.cancel()
            loadMoreTask?.cancel()
        }
    }

    public func refresh() {
        scheduleSearch()
    }

    public func loadMore() {
        guard let cursor = nextCursor, !isLoadingMore, parserError == nil else { return }
        let generation = searchGeneration
        let query = parsedQuery
        let request = SearchRequest(query: query, sort: sort)
        isLoadingMore = true
        loadMoreTask?.cancel()
        loadMoreTask = Task { [weak self, searcher, pageSize] in
            do {
                let page = try await searcher.search(
                    request: request,
                    limit: pageSize,
                    after: cursor
                )
                guard let self, self.searchGeneration == generation else { return }
                let existingPaths = Set(self.rows.map(\.path))
                self.rows.append(contentsOf: page.entries.filter { !existingPaths.contains($0.path) })
                self.nextCursor = page.nextCursor
                self.canLoadMore = page.nextCursor != nil
                self.searchError = nil
                self.isLoadingMore = false
                self.loadMoreTask = nil
            } catch is CancellationError {
                guard let self, self.searchGeneration == generation else { return }
                self.isLoadingMore = false
                self.loadMoreTask = nil
            } catch {
                guard let self, self.searchGeneration == generation else { return }
                self.searchError = error.localizedDescription
                self.isLoadingMore = false
                self.loadMoreTask = nil
            }
        }
    }

    public func chooseSort(_ sort: SearchSort) {
        self.sort = sort
        onExplicitSortChange(sort)
    }

    public func saveCurrentSearch(name: String) {
        guard let libraryStore else { return }
        do {
            _ = try SearchQueryParser.parse(query)
            guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw SearchLibraryError.invalidQuery
            }
            _ = try libraryStore.save(name: name, query: query, sort: sort, at: Date())
            reloadLibrary()
        } catch {
            libraryError = error.localizedDescription
        }
    }

    public func renameSavedSearch(id: UUID, name: String) {
        mutateLibrary { try $0.rename(id: id, name: name) }
    }

    public func replaceSavedSearch(id: UUID) {
        mutateLibrary { try $0.replace(id: id, query: query, sort: sort, at: Date()) }
    }

    public func removeSavedSearch(id: UUID) {
        mutateLibrary { try $0.remove(id: id) }
    }

    public func moveSavedSearch(fromOffsets: IndexSet, toOffset: Int) {
        mutateLibrary { try $0.move(fromOffsets: fromOffsets, toOffset: toOffset) }
    }

    public func activateSavedSearch(_ id: UUID) {
        guard let saved = savedSearches.first(where: { $0.id == id }) else { return }
        sort = saved.sort
        query = saved.query
    }

    public func activateRecentSearch(_ recent: RecentSearch) {
        sort = recent.sort
        query = recent.query
    }

    public func clearRecentSearches() {
        mutateLibrary { try $0.clearRecent() }
    }

    public func removeToken(id: Int) {
        guard let token = tokens.first(where: { $0.id == id }) else { return }
        var characters = Array(query)
        guard token.characterRange.lowerBound >= 0,
              token.characterRange.upperBound <= characters.count else { return }
        characters.removeSubrange(token.characterRange)
        query = SearchLibraryStore.normalize(String(characters))
    }

    private func scheduleSearch() {
        searchGeneration &+= 1
        let generation = searchGeneration
        searchTask?.cancel()
        loadMoreTask?.cancel()
        loadMoreTask = nil
        isLoadingMore = false

        let parsed: ParsedSearchQuery
        do {
            parsed = try SearchQueryParser.parseDetailed(query)
        } catch let error as SearchQueryParseError {
            parserError = error
            tokens = []
            isSearching = false
            canLoadMore = false
            nextCursor = nil
            return
        } catch {
            searchError = error.localizedDescription
            isSearching = false
            return
        }

        parserError = nil
        tokens = parsed.tokens
        parsedQuery = parsed.query
        let requestedSort = sort
        isSearching = true
        searchTask = Task { [weak self, searcher, debounce, pageSize] in
            do {
                if debounce > .zero {
                    try await Task.sleep(for: debounce)
                }
                let request = SearchRequest(query: parsed.query, sort: requestedSort)
                let page = try await searcher.search(request: request, limit: pageSize, after: nil)
                guard let self, self.searchGeneration == generation, !Task.isCancelled else { return }
                let previousSelection = self.selectedEntryID
                self.rows = page.entries
                self.nextCursor = page.nextCursor
                self.canLoadMore = page.nextCursor != nil
                if let previousSelection,
                   page.entries.contains(where: { $0.id == previousSelection }) {
                    self.selectedEntryID = previousSelection
                } else {
                    self.selectedEntryID = page.entries.first?.id
                }
                self.searchError = nil
                self.isSearching = false
                self.searchTask = nil
                if !self.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   let libraryStore = self.libraryStore {
                    do {
                        try libraryStore.recordRecent(query: self.query, sort: requestedSort, usedAt: Date())
                        self.reloadLibrary()
                    } catch {
                        self.libraryError = error.localizedDescription
                    }
                }
            } catch is CancellationError {
                guard let self, self.searchGeneration == generation else { return }
                self.isSearching = false
                self.searchTask = nil
            } catch {
                guard let self, self.searchGeneration == generation else { return }
                self.searchError = error.localizedDescription
                self.isSearching = false
                self.searchTask = nil
            }
        }
    }

    private func reloadLibrary() {
        guard let libraryStore else { return }
        do {
            let library = try libraryStore.load()
            recentSearches = library.recent
            savedSearches = library.saved
            libraryError = nil
        } catch {
            libraryError = error.localizedDescription
        }
    }

    private func mutateLibrary(_ mutation: (any SearchLibraryStoring) throws -> Void) {
        guard let libraryStore else { return }
        do {
            try mutation(libraryStore)
            reloadLibrary()
        } catch {
            libraryError = error.localizedDescription
        }
    }
}
