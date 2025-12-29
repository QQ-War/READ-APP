import SwiftUI

struct SourceListView: View {
    @StateObject private var viewModel = SourceListViewModel()
    
    // For specific source search via swipe action
    @State private var showingBookSearchView = false
    @State private var selectedBookSource: BookSource?

    var body: some View {
        VStack {
            GlobalSearchBar(text: $viewModel.searchText, placeholder: "搜索全部书源...")
                .padding()

            if viewModel.searchText.isEmpty {
                sourceManagementView
            } else {
                globalSearchView
            }
        }
        .navigationTitle("书源管理")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink(destination: SourceEditView()) {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingBookSearchView) {
            if let bookSource = selectedBookSource {
                BookSearchView(viewModel: BookSearchViewModel(bookSource: bookSource))
            }
        }
    }
    
    @ViewBuilder
    private var sourceManagementView: some View {
        ZStack {
            if viewModel.isLoading && viewModel.sources.isEmpty {
                ProgressView("正在加载书源...")
            } else if let errorMessage = viewModel.errorMessage {
                VStack {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .padding()
                    Button("重试") {
                        viewModel.fetchSources()
                    }
                }
            }
            else {
                List {
                    ForEach(viewModel.sources) { source in
                        NavigationLink(destination: SourceEditView(sourceId: source.bookSourceUrl)) {
                            HStack {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(source.bookSourceName)
                                        .font(.headline)
                                        .foregroundColor(source.enabled ? .primary : .secondary)
                                    
                                    if let group = source.bookSourceGroup, !group.isEmpty {
                                        Text("分组: \(group)")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Text(source.bookSourceUrl)
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                                
                                Spacer()
                                
                                Toggle("", isOn: Binding(
                                    get: { source.enabled },
                                    set: { _ in viewModel.toggleSource(source: source) }
                                ))
                                .labelsHidden()
                            }
                            .padding(.vertical, 4)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                selectedBookSource = source
                                showingBookSearchView = true
                            } label: {
                                Label("搜索", systemImage: "magnifyingglass")
                            }
                            .tint(.blue)
                        }
                    }
                    .onDelete(perform: deleteSource)
                }
                .refreshable {
                    viewModel.fetchSources()
                }
            }
        }
    }
    
    @ViewBuilder
    private var globalSearchView: some View {
        List {
            ForEach(viewModel.searchResults) { book in
                BookSearchResultRow(book: book) {
                    Task {
                        // For global search results, directly call APIService to save
                        // or handle errors appropriately
                        do {
                            try await APIService.shared.saveBook(book: book)
                            // Optionally, show a success message
                            print("Book \(book.name ?? "") added successfully!")
                        } catch {
                            // Optionally, show an error message
                            print("Failed to add book \(book.name ?? ""): \(error.localizedDescription)")
                        }
                    }
                }
            }
            if viewModel.isSearching {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            }
        }
    }
    
    private func deleteSource(at offsets: IndexSet) {
        offsets.forEach { index in
            let source = viewModel.sources[index]
            viewModel.deleteSource(source: source)
        }
    }
}

// MARK: - BookSearchResultRow
struct BookSearchResultRow: View {
    let book: Book
    let onAddToBookshelf: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AsyncImage(url: book.displayCoverUrl.flatMap(URL.init)) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Color.gray.opacity(0.3)
            }
            .frame(width: 60, height: 80)
            .cornerRadius(4)

            VStack(alignment: .leading, spacing: 4) {
                Text(book.name ?? "未知书籍")
                    .font(.headline)
                    .lineLimit(2)
                Text(book.author ?? "未知作者")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text(book.intro ?? "")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                if let sourceName = book.sourceDisplayName {
                    Text("来源: \(sourceName)")
                        .font(.caption2)
                        .foregroundColor(.accentColor)
                        .padding(.top, 2)
                }
            }
            
            Spacer()

            Button(action: onAddToBookshelf) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - SearchBar
struct GlobalSearchBar: View {
    @Binding var text: String
    var placeholder: String
    var onSearchButtonClicked: (() -> Void)?
    
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
                    onSearchButtonClicked?()
                }
        }
    }
}


struct SourceListView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            SourceListView()
        }
    }
}
