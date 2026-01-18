import Foundation

@MainActor
final class BookshelfListViewModel: ObservableObject {
    @Published var searchText: String = ""
    @Published var isReversed = false
    @Published private(set) var onlineResults: [Book] = []
    @Published private(set) var isSearchingOnline = false
    @Published var isRefreshing = false
    @Published var addResultMessage = ""
    @Published var showAddResultAlert = false

    private var searchTask: Task<Void, Never>?
    private weak var bookshelfStore: BookshelfStore?
    private weak var sourceStore: SourceStore?
    private var preferences: UserPreferences?

    func configure(bookshelfStore: BookshelfStore, sourceStore: SourceStore, preferences: UserPreferences) {
        if self.bookshelfStore === bookshelfStore && self.sourceStore === sourceStore { return }
        self.bookshelfStore = bookshelfStore
        self.sourceStore = sourceStore
        self.preferences = preferences
    }

    var filteredAndSortedBooks: [Book] {
        guard let store = bookshelfStore else { return [] }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = query.isEmpty ? store.books : store.books.filter { book in
            (book.name?.localizedCaseInsensitiveContains(query) ?? false) ||
            (book.author?.localizedCaseInsensitiveContains(query) ?? false)
        }

        let sorted: [Book]
        if preferences?.bookshelfSortByRecent == true {
            sorted = base.sorted { book1, book2 in
                let time1 = book1.durChapterTime ?? 0
                let time2 = book2.durChapterTime ?? 0
                if time1 == 0 && time2 == 0 { return false }
                if time1 == 0 { return false }
                if time2 == 0 { return true }
                return time1 > time2
            }
        } else {
            sorted = base
        }
        return isReversed ? sorted.reversed() : sorted
    }

    func handleSearchChange() {
        searchTask?.cancel()
        guard let preferences else { return }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty && preferences.searchSourcesFromBookshelf else {
            onlineResults = []
            return
        }

        searchTask = Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            if Task.isCancelled { return }
            await performOnlineSearch(query: query)
        }
    }

    func loadBooks() async {
        guard let bookshelfStore else { return }
        isRefreshing = true
        await bookshelfStore.refreshBookshelf()
        isRefreshing = false
    }

    func addBookToBookshelf(_ book: Book) async {
        guard let bookshelfStore else { return }
        do {
            try await bookshelfStore.saveBook(book)
            addResultMessage = "已加入书架"
        } catch {
            addResultMessage = "加入失败: \(error.localizedDescription)"
        }
        showAddResultAlert = true
    }

    private func performOnlineSearch(query: String) async {
        guard let sourceStore, let preferences else { return }
        isSearchingOnline = true

        let sources = sourceStore.availableSources.isEmpty ? (await refreshSources()) : sourceStore.availableSources
        let enabledSources = sources.filter { $0.enabled }
        let targetSources = preferences.preferredSearchSourceUrls.isEmpty ?
            enabledSources :
            enabledSources.filter { preferences.preferredSearchSourceUrls.contains($0.bookSourceUrl) }

        var allResults: [Book] = []
        await withTaskGroup(of: [Book]?.self) { group in
            for source in targetSources {
                group.addTask {
                    try? await APIService.shared.searchBook(keyword: query, bookSourceUrl: source.bookSourceUrl)
                }
            }

            for await result in group {
                if let books = result {
                    allResults.append(contentsOf: books)
                }
            }
        }

        onlineResults = allResults
        isSearchingOnline = false
    }

    private func refreshSources() async -> [BookSource] {
        guard let sourceStore else { return [] }
        await sourceStore.refreshSources()
        return sourceStore.availableSources
    }
}
