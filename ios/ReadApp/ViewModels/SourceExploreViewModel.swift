import Foundation

@MainActor
final class SourceExploreViewModel: ObservableObject {
    @Published private(set) var books: [Book] = []
    @Published private(set) var isLoading = false
    @Published private(set) var canLoadMore = true
    @Published private(set) var currentPage = 1
    @Published private(set) var hasLoaded = false
    @Published var errorMessage: String?

    let source: BookSource
    let kind: BookSource.ExploreKind

    init(source: BookSource, kind: BookSource.ExploreKind) {
        self.source = source
        self.kind = kind
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await loadBooks(loadMore: false)
    }

    func loadBooks(loadMore: Bool) async {
        guard !isLoading && (canLoadMore || !loadMore) else { return }

        if loadMore {
            currentPage += 1
        } else {
            currentPage = 1
            books = []
            canLoadMore = true
        }

        isLoading = true
        errorMessage = nil
        do {
            let newBooks = try await APIService.shared.exploreBook(
                bookSourceUrl: source.bookSourceUrl,
                ruleFindUrl: kind.url,
                page: currentPage
            )
            if newBooks.isEmpty {
                canLoadMore = false
            } else {
                books.append(contentsOf: newBooks)
                if newBooks.count < 20 {
                    canLoadMore = false
                }
            }
            hasLoaded = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

@MainActor
final class SourceExploreStore: ObservableObject {
    private var cache: [String: SourceExploreViewModel] = [:]

    func viewModel(for source: BookSource, kind: BookSource.ExploreKind) -> SourceExploreViewModel {
        let key = "\(source.bookSourceUrl)|\(kind.url)"
        if let existing = cache[key] {
            return existing
        }
        let created = SourceExploreViewModel(source: source, kind: kind)
        cache[key] = created
        return created
    }
}
