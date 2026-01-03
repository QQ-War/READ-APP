import SwiftUI

struct SourceExploreView: View {
    let source: BookSource
    let kind: BookSource.ExploreKind
    
    @EnvironmentObject var apiService: APIService
    @State private var books: [Book] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var currentPage = 1
    @State private var canLoadMore = true
    
    @State private var selectedBook: Book?
    @State private var showAddSuccessAlert = false
    @State private var showAddFailureAlert = false
    @State private var alertMessage = ""

    var body: some View {
        List {
            ForEach(books) { book in
                BookSearchResultRow(book: book) {
                    Task {
                        await addBookToBookshelf(book: book)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedBook = book
                }
            }
            
            if canLoadMore {
                HStack {
                    Spacer()
                    if isLoading {
                        ProgressView()
                    } else {
                        Text("上拉或点击加载更多")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .onAppear {
                                Task { await loadBooks(loadMore: true) }
                            }
                    }
                    Spacer()
                }
            }
        }
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .ifAvailableHideTabBar()
        .task {
            await loadBooks()
        }
        .fullScreenCover(item: $selectedBook) { book in
            BookDetailView(book: book).environmentObject(apiService)
        }
        .alert("添加书架", isPresented: $showAddSuccessAlert) {
            Button("确定", role: .cancel) { }
        } message: {
            Text("书籍已成功添加到书架。")
        }
        .alert("添加书架失败", isPresented: $showAddFailureAlert) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
    }
    
    private func loadBooks(loadMore: Bool = false) async {
        guard !isLoading && (canLoadMore || !loadMore) else { return }
        
        if loadMore {
            currentPage += 1
        } else {
            currentPage = 1
            books = []
        }
        
        isLoading = true
        do {
            let newBooks = try await apiService.exploreBook(bookSourceUrl: source.bookSourceUrl, ruleFindUrl: kind.url, page: currentPage)
            await MainActor.run {
                if newBooks.isEmpty {
                    canLoadMore = false
                } else {
                    self.books.append(contentsOf: newBooks)
                    if newBooks.count < 20 { // Simple heuristic for last page
                        canLoadMore = false
                    }
                }
                isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
    
    private func addBookToBookshelf(book: Book) async {
        do {
            try await apiService.saveBook(book: book)
            await MainActor.run {
                showAddSuccessAlert = true
            }
        } catch {
            await MainActor.run {
                alertMessage = error.localizedDescription
                showAddFailureAlert = true
            }
        }
    }
}
