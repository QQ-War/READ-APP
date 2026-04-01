import Foundation
import SwiftUI

@MainActor
final class BookshelfStore: ObservableObject {
    @Published private(set) var books: [Book] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let service: APIService

    init(service: APIService = APIService.shared) {
        self.service = service
        if let cachedBooks = LocalCacheManager.shared.loadBookshelfCache() {
            self.books = cachedBooks
        }
    }

    func refreshBookshelf() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let fetched = try await service.fetchBookshelf()
            books = fetched
            LocalCacheManager.shared.saveBookshelfCache(fetched)
        } catch {
            if Task.isCancelled || error is CancellationError {
                return
            }
            let nsError = error as NSError
            let detail = nsError.localizedDescription
            let codeInfo = "\(nsError.domain)#\(nsError.code)"
            errorMessage = "书架刷新失败(\(codeInfo)): \(detail)"
        }
    }

    func setBooks(_ updated: [Book]) {
        books = updated
        LocalCacheManager.shared.saveBookshelfCache(updated)
    }

    func saveBook(_ book: Book, useReplaceRule: Int = 0) async throws {
        try await service.saveBook(book: book, useReplaceRule: useReplaceRule)
        if !books.contains(where: { $0.bookUrl == book.bookUrl }) {
            books.append(book)
            LocalCacheManager.shared.saveBookshelfCache(books)
        }
    }

    func deleteBook(bookUrl: String) async throws {
        try await service.deleteBook(bookUrl: bookUrl)
        books.removeAll { $0.bookUrl == bookUrl }
        LocalCacheManager.shared.saveBookshelfCache(books)
    }

    func importBook(from url: URL) async throws {
        try await service.importBook(from: url)
        await refreshBookshelf()
    }

    func updateProgress(bookUrl: String, index: Int, pos: Double, title: String?, updateTimestamp: Bool = true) {
        guard let idx = books.firstIndex(where: { $0.bookUrl == bookUrl }) else { return }
        var updated = books[idx]
        updated.durChapterIndex = index
        updated.durChapterPos = pos
        updated.durChapterTitle = title
        if updateTimestamp {
            updated.durChapterTime = Int64(Date().timeIntervalSince1970 * 1000)
        }
        books[idx] = updated
        LocalCacheManager.shared.saveBookshelfCache(books)
    }
}

extension BookshelfStore: BookshelfSaving {
    func saveBook(book: Book, useReplaceRule: Int) async throws {
        try await saveBook(book, useReplaceRule: useReplaceRule)
    }
}
