import SwiftUI

struct SourceExploreContainerView: View {
    let source: BookSource
    @EnvironmentObject var bookshelfStore: BookshelfStore
    @StateObject private var viewModel: BookSearchViewModel
    @Environment(\.presentationMode) var presentationMode
    @StateObject private var exploreStore = SourceExploreStore()
    
    @State private var exploreKinds: [BookSource.ExploreKind] = []
    @State private var isLoadingKinds = false
    
    init(source: BookSource, bookshelfStore: BookshelfStore) {
        self.source = source
        _viewModel = StateObject(wrappedValue: BookSearchViewModel(bookSource: source, bookshelfSaver: bookshelfStore))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Search Bar
            HStack {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("搜索书籍...", text: $viewModel.searchText, onCommit: {
                        Task { await viewModel.performSearch() }
                    })
                    .textFieldStyle(PlainTextFieldStyle())
                    
                    if !viewModel.searchText.isEmpty {
                        Button(action: {
                            viewModel.searchText = ""
                            viewModel.searchResults = []
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(8)
                .background(Color(.systemGray6))
                .cornerRadius(10)
                
                if !viewModel.searchText.isEmpty || viewModel.isLoading {
                    Button("取消") {
                        viewModel.searchText = ""
                        viewModel.searchResults = []
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                    .padding(.leading, 8)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .padding()
            .animation(.default, value: viewModel.searchText.isEmpty)
            
            Divider()
            
            if viewModel.searchText.isEmpty && !viewModel.isLoading {
                // Categories/Explore Kinds
                if isLoadingKinds {
                    VStack {
                        Spacer()
                        ProgressView("正在加载分类...")
                        Spacer()
                    }
                } else if exploreKinds.isEmpty {
                    VStack {
                        Spacer()
                        Text("该书源暂无发现配置")
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("发现分类")
                                .font(.headline)
                                .padding(.horizontal)
                                .padding(.top)
                            
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 12) {
                                ForEach(exploreKinds) { kind in
                                    NavigationLink(destination: SourceExploreView(viewModel: exploreStore.viewModel(for: source, kind: kind))) {
                                        Text(kind.title)
                                            .font(.subheadline)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 8)
                                            .frame(maxWidth: .infinity)
                                            .background(Color.blue.opacity(0.1))
                                            .foregroundColor(.blue)
                                            .cornerRadius(8)
                                            .glassyButtonStyle()
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
            } else {
                // Search Results
                List {
                    if viewModel.isLoading && viewModel.searchResults.isEmpty {
                        HStack {
                            Spacer()
                            ProgressView("正在搜索...")
                            Spacer()
                        }
                    } else if viewModel.searchResults.isEmpty && !viewModel.isLoading {
                        VStack {
                            Spacer()
                            Text("没有找到相关书籍。")
                                .foregroundColor(.gray)
                                .frame(maxWidth: .infinity, alignment: .center)
                            Spacer()
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    } else {
                        ForEach(viewModel.searchResults) { book in
                            NavigationLink(destination: BookDetailView(book: book)) {
                                BookSearchResultRow(book: book) {
                                    // Managed in BookDetailView
                                }
                            }
                        }
                        
                        if viewModel.canLoadMore && !viewModel.isLoading {
                            HStack {
                                Spacer()
                                ProgressView()
                                    .onAppear {
                                        Task { await viewModel.performSearch(loadMore: true) }
                                    }
                                Spacer()
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(source.bookSourceName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadExploreKinds()
        }
    }
    
    private func loadExploreKinds() {
        guard exploreKinds.isEmpty else { return }
        isLoadingKinds = true
        Task {
            do {
                let kinds = try await APIService.shared.fetchExploreKinds(bookSourceUrl: source.bookSourceUrl)
                await MainActor.run {
                    self.exploreKinds = kinds
                    self.isLoadingKinds = false
                }
            } catch {
                await MainActor.run {
                    self.isLoadingKinds = false
                }
            }
        }
    }
}
