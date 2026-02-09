import Foundation

@MainActor
final class SourceSwitchViewModel: ObservableObject {
    @Published private(set) var searchResults: [Book] = []
    @Published private(set) var isSearching = false
    @Published private(set) var completedCount = 0
    @Published private(set) var totalCount = 0
    @Published private(set) var errorMessage: String?

    private var currentToken = UUID()
    private var lastQueryKey: String?
    private var lastResults: [Book] = []

    func performSearchIfNeeded(bookName: String, author: String) async {
        let key = "\(bookName)|\(author)"
        guard key != lastQueryKey else { return }
        await performSearch(bookName: bookName, author: author)
    }

    func performSearch(bookName: String, author: String) async {
        let token = UUID()
        currentToken = token
        lastQueryKey = "\(bookName)|\(author)"
        lastResults = []
        searchResults = []
        errorMessage = nil
        isSearching = true
        completedCount = 0

        let sources = (try? await APIService.shared.fetchBookSources()) ?? []
        let enabledSources = sources.filter { $0.enabled }
        totalCount = enabledSources.count

        guard !enabledSources.isEmpty else {
            isSearching = false
            return
        }

        await withTaskGroup(of: [Book]?.self) { group in
            for source in enabledSources {
                group.addTask {
                    try? await APIService.shared.searchBook(keyword: bookName, bookSourceUrl: source.bookSourceUrl)
                        .map { $0.withSourceName(source.bookSourceName) }
                }
            }

            for await result in group {
                guard token == currentToken else { return }
                if let books = result {
                    let exactMatches = books.filter { $0.name == bookName }
                    if !exactMatches.isEmpty {
                        lastResults.append(contentsOf: exactMatches)
                        lastResults = dedupeBooks(lastResults)
                        lastResults.sort { b1, b2 in
                            let match1 = (b1.author == author) ? 1 : 0
                            let match2 = (b2.author == author) ? 1 : 0
                            return match1 > match2
                        }
                        searchResults = lastResults
                    }
                }
                completedCount += 1
            }
        }

        if token == currentToken {
            isSearching = false
        }
    }

    private func dedupeBooks(_ books: [Book]) -> [Book] {
        var seen = Set<String>()
        var result: [Book] = []
        for book in books {
            let key = book.bookUrl ?? "\(book.origin ?? "")|\(book.name ?? "")|\(book.author ?? "")"
            if seen.contains(key) { continue }
            seen.insert(key)
            result.append(book)
        }
        return result
    }
}

private extension Book {
    func withSourceName(_ name: String?) -> Book {
        var updated = self
        updated.originName = name
        return updated
    }
}
