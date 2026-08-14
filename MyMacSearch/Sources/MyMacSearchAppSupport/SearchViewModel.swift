import Foundation
import MyMacSearchCore
import Observation

@MainActor
@Observable
public final class SearchViewModel {
    public var query = "" {
        didSet {
            guard query != oldValue else { return }
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

    private let searcher: any IndexSearching
    private let debounce: Duration
    private let pageSize: Int
    private var parsedQuery = SearchQuery()
    private var nextCursor: SearchCursor?
    private var searchGeneration: UInt64 = 0
    private var searchTask: Task<Void, Never>?
    private var loadMoreTask: Task<Void, Never>?

    public init(
        searcher: any IndexSearching,
        debounce: Duration = .milliseconds(60),
        pageSize: Int = 200
    ) {
        self.searcher = searcher
        self.debounce = debounce
        self.pageSize = min(max(pageSize, 1), 500)
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
        isLoadingMore = true
        loadMoreTask?.cancel()
        loadMoreTask = Task { [weak self, searcher, pageSize] in
            do {
                let page = try await searcher.search(
                    query: query,
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

    private func scheduleSearch() {
        searchGeneration &+= 1
        let generation = searchGeneration
        searchTask?.cancel()
        loadMoreTask?.cancel()
        loadMoreTask = nil
        isLoadingMore = false

        let parsed: SearchQuery
        do {
            parsed = try SearchQueryParser.parse(query)
        } catch let error as SearchQueryParseError {
            parserError = error
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
        parsedQuery = parsed
        isSearching = true
        searchTask = Task { [weak self, searcher, debounce, pageSize] in
            do {
                if debounce > .zero {
                    try await Task.sleep(for: debounce)
                }
                let page = try await searcher.search(query: parsed, limit: pageSize, after: nil)
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
}
