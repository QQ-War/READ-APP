import SwiftUI

struct BookSearchView: View {
    @ObservedObject var viewModel: BookSearchViewModel
    @Environment(\.presentationMode) var presentationMode // For dismissing the view
    
    @State private var showingAddSuccessAlert = false
    @State private var showingAddFailureAlert = false
    @State private var alertMessage = ""

    var body: some View {
        NavigationView {
            VStack {
                SearchBar(text: $viewModel.searchText, placeholder: "搜索书籍...") { // Use Chinese characters directly
                    Task {
                        await viewModel.performSearch()
                    }
                }
                .padding(.horizontal)
                
                if viewModel.isLoading && viewModel.searchResults.isEmpty {
                    ProgressView("正在搜索...") // Use Chinese characters directly
                        .padding()
                } else if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .padding()
                } else if viewModel.searchResults.isEmpty && !viewModel.searchText.isEmpty && !viewModel.isLoading {
                    Text("没有找到相关书籍。") // Use Chinese characters directly
                        .foregroundColor(.gray)
                        .padding()
                } else {
                    List {
                        ForEach(viewModel.searchResults) {
                            book in
                            BookSearchRow(book: book) {
                                Task {
                                    await addBookToBookshelf(book: book)
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
                            Text("已加载全部结果。") // Use Chinese characters directly
                                .foregroundColor(.gray)
                                .font(.caption)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 8)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("在 \"\(viewModel.bookSource.bookSourceName)\" 中搜索") // Use Chinese characters directly and escape quotes correctly
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { // Use Chinese characters directly
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
            .alert("添加书架", isPresented: $showingAddSuccessAlert) { // Use Chinese characters directly
                Button("确定", role: .cancel) { } // Use Chinese characters directly
            } message: {
                Text("书籍已成功添加到书架。") // Use Chinese characters directly
            }
            .alert("添加书架失败", isPresented: $showingAddFailureAlert) { // Use Chinese characters directly
                Button("确定", role: .cancel) { } // Use Chinese characters directly
            } message: {
                Text(alertMessage)
            }
        }
    }
    
    private func addBookToBookshelf(book: Book) async {
        await viewModel.addToBookshelf(book: book)
        if let error = viewModel.errorMessage {
            alertMessage = error
            showingAddFailureAlert = true
        } else {
            showingAddSuccessAlert = true
        }
    }
}

// MARK: - SearchBar
struct SearchBar: View {
    @Binding var text: String
    var placeholder: String
    var onSearchButtonClicked: () -> Void
    
    var body: some View {
        HStack {
            TextField(placeholder, text: $text)
                .padding(7)
                .padding(.horizontal, 25)
                .background(Color(.systemGray6))
                .cornerRadius(8)
                .overlay(
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.gray)
                            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 8)
                        
                        if !text.isEmpty {
                            Button(action: {
                                self.text = ""
                            }) {
                                Image(systemName: "multiply.circle.fill")
                                    .foregroundColor(.gray)
                                    .padding(.trailing, 8)
                            }
                        }
                    }
                )
                .submitLabel(.search)
                .onSubmit {
                    onSearchButtonClicked()
                }
        }
    }
}

// MARK: - BookSearchRow
struct BookSearchRow: View {
    let book: Book
    let onAddToBookshelf: () -> Void
    
    var body: some View {
        HStack(alignment: .top) {
            if let coverUrlString = book.displayCoverUrl, let url = URL(string: coverUrlString) {
                AsyncImage(url: url) { image in
                    image.resizable()
                } placeholder: {
                    ProgressView()
                }
                .frame(width: 60, height: 80)
                .cornerRadius(5)
                .shadow(radius: 2)
            } else {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 60, height: 80)
                    .overlay(Image(systemName: "book.closed.fill").foregroundColor(.white))
            }
            
            VStack(alignment: .leading) {
                Text(book.name ?? "未知书名") // Use Chinese characters directly
                    .font(.headline)
                    .lineLimit(1)
                Text(book.author ?? "未知作者") // Use Chinese characters directly
                    .font(.subheadline)
                    .foregroundColor(.gray)
                Text(book.intro ?? "无简介") // Use Chinese characters directly
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            Spacer() 
            
            Button(action: onAddToBookshelf) {
                Text("加入书架") // Use Chinese characters directly
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(5)
            }
            .buttonStyle(.plain) // Prevent whole row from being tappable
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview
struct BookSearchView_Previews: PreviewProvider {
    static var previews: some View {
        BookSearchView(viewModel: BookSearchViewModel(bookSource: BookSource.mock()))
    }
}
