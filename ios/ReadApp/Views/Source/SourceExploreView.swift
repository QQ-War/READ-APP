import SwiftUI

struct SourceExploreView: View {
    @ObservedObject var viewModel: SourceExploreViewModel
    @EnvironmentObject var bookshelfStore: BookshelfStore
    
    @State private var showAddSuccessAlert = false
    @State private var showAddFailureAlert = false
    @State private var alertMessage = ""

    var body: some View {
        List {
            ForEach(viewModel.books) { book in
                NavigationLink(destination: BookDetailView(book: book)) {
                    BookSearchResultRow(book: book) {
                        Task {
                            await addBookToBookshelf(book: book)
                        }
                    }
                }
            }
            
            if viewModel.canLoadMore {
                HStack {
                    Spacer()
                    if viewModel.isLoading {
                        ProgressView()
                    } else {
                        Text("上拉或点击加载更多")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .onAppear {
                                Task { await viewModel.loadBooks(loadMore: true) }
                            }
                    }
                    Spacer()
                }
            }
        }
        .glassyListStyle()
        .navigationTitle(viewModel.kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .ifAvailableHideTabBar()
        .task {
            await viewModel.loadIfNeeded()
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
    
    private func addBookToBookshelf(book: Book) async {
        do {
            try await bookshelfStore.saveBook(book)
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
