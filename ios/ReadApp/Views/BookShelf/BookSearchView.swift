import SwiftUI

struct BookSearchView: View {
    @ObservedObject var viewModel: BookSearchViewModel
    @Environment(\.presentationMode) var presentationMode // For dismissing the view
    
    @State private var showingAddSuccessAlert = false
    @State private var showingAddFailureAlert = false
    @State private var alertMessage = ""
    @State private var errorSheet: SelectableMessage?

    var body: some View {
        NavigationView {
            List {
                if viewModel.isLoading && viewModel.searchResults.isEmpty {
                    HStack {
                        Spacer()
                        ProgressView("正在搜索...")
                        Spacer()
                    }
                } else if viewModel.searchResults.isEmpty && !viewModel.searchText.isEmpty && !viewModel.isLoading {
                    Text("没有找到相关书籍。")
                        .foregroundColor(.gray)
                        .padding()
                } else {
                    ForEach(viewModel.searchResults) { book in
                        NavigationLink(destination: BookDetailView(book: book)) {
                            BookSearchResultRow(book: book) {
                                // Add button is removed from row, this callback is no-op
                            }
                        }
                    }
                    
                    if viewModel.canLoadMore && !viewModel.isLoading {
                        ProgressView()
                            .onAppear {
                                Task {
                                    await viewModel.performSearch(loadMore: true)
                                }
                            }
                    } else if !viewModel.canLoadMore && !viewModel.searchResults.isEmpty {
                        Text("已加载全部结果。")
                            .foregroundColor(.gray)
                            .font(.caption)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 8)
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("搜索: \(viewModel.bookSource.bookSourceName)")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $viewModel.searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索书籍...")
            .onChange(of: viewModel.searchText) { _ in
                Task { await viewModel.performSearch() }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
            .sheet(item: $errorSheet) { sheet in
                SelectableMessageSheet(title: sheet.title, message: sheet.message) {
                    viewModel.errorMessage = nil
                    errorSheet = nil
                }
            }
        }
        .onChange(of: viewModel.errorMessage) { newValue in
            guard let message = newValue, !message.isEmpty else { return }
            errorSheet = SelectableMessage(title: "错误", message: message)
        }
    }
}

// MARK: - BookSearchRow (Removed custom implementation as it uses BookSearchResultRow)

// MARK: - SearchBar (Removed as it uses .searchable)

// MARK: - Preview
struct BookSearchView_Previews: PreviewProvider {
    static var previews: some View {
        BookSearchView(viewModel: BookSearchViewModel(bookSource: BookSource.mock()))
    }
}
