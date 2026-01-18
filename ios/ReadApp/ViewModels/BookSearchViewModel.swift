import Foundation
import Combine
import SwiftUI

protocol BookshelfSaving {
    func saveBook(book: Book, useReplaceRule: Int) async throws
}

class BookSearchViewModel: ObservableObject {
    @Published var searchText: String = ""
    @Published var searchResults: [Book] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var currentPage: Int = 1
    @Published var canLoadMore: Bool = true
    
    let bookSource: BookSource // The specific source to search within
    private var apiService: APIServiceProtocol // Use protocol for testability
    private let bookshelfSaver: BookshelfSaving?
    
    init(bookSource: BookSource, apiService: APIServiceProtocol = APIService.shared, bookshelfSaver: BookshelfSaving? = nil) {
        self.bookSource = bookSource
        self.apiService = apiService
        self.bookshelfSaver = bookshelfSaver
    }
    
    @MainActor
    func performSearch(loadMore: Bool = false) async {
        guard !searchText.isEmpty else {
            searchResults = []
            canLoadMore = true // Reset for new search
            return
        }
        
        if loadMore && !canLoadMore { return } // If trying to load more but no more data
        
        isLoading = true
        errorMessage = nil
        
        if !loadMore {
            currentPage = 1 // Reset page for a new search query
            searchResults = []
        }
        
        do {
            let newBooks = try await apiService.searchBook(
                keyword: searchText,
                bookSourceUrl: bookSource.bookSourceUrl,
                page: currentPage
            )
            
            if newBooks.isEmpty {
                canLoadMore = false // No more results
            } else {
                searchResults.append(contentsOf: newBooks)
                currentPage += 1 // Increment page for next load more
                canLoadMore = true // Assume more until proven otherwise by an empty result
            }
        } catch {
            errorMessage = "搜索失败: \(error.localizedDescription)"
            canLoadMore = false
        }
        isLoading = false
    }
    
    @MainActor
    func addToBookshelf(book: Book) async {
        isLoading = true
        errorMessage = nil
        do {
            if let bookshelfSaver {
                try await bookshelfSaver.saveBook(book: book, useReplaceRule: 0)
            } else {
                try await apiService.saveBook(book: book, useReplaceRule: 0)
            }
            // Optionally, update the book object in searchResults to indicate it's added
            if searchResults.firstIndex(where: { $0.id == book.id }) != nil {
                // Since Book is a struct, we might need to recreate it if we wanted to change a property directly,
                // but for now, we just indicate success.
                // Or if there was an 'isAddedToBookshelf' property on Book, we'd update it here.
                LogManager.shared.log("书籍 '\(book.name ?? "")' 已添加到书架。", category: "书架操作")
            }
        } catch {
            errorMessage = "添加到书架失败: \(error.localizedDescription)"
        }
        isLoading = false
    }
}

// Protocol for APIService to enable mocking in tests
protocol APIServiceProtocol {
    func searchBook(keyword: String, bookSourceUrl: String, page: Int) async throws -> [Book]
    func saveBook(book: Book, useReplaceRule: Int) async throws
    func fetchBookSources() async throws -> [BookSource] // Keep this to avoid breaking SourceListViewModel
    // Add other methods that might be called from view models if needed
}

extension APIService: APIServiceProtocol {}
