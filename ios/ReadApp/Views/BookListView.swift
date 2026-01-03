import SwiftUI

struct BookListView: View {
    @EnvironmentObject var apiService: APIService
    @StateObject private var preferences = UserPreferences.shared
    @State private var isRefreshing = false
    @State private var searchText = ""
    @State private var isReversed = false
    @State private var showingActionSheet = false  // 显示操作菜单
    @State private var showingDocumentPicker = false
    @State private var selectedBook: Book?
    @State private var showingDeleteBookAlert = false
    @State private var bookToDelete: Book?
    
    // Online Search State
    @State private var onlineResults: [Book] = []
    @State private var isSearchingOnline = false
    @State private var searchTask: Task<Void, Never>? = nil
    @State private var selectedOnlineBook: Book?
    @State private var showAddSuccessAlert = false
    
    // 过滤和排序后的书籍列表
    var filteredAndSortedBooks: [Book] {
        let filtered: [Book]
        if searchText.isEmpty {
            filtered = apiService.books
        } else {
            filtered = apiService.books.filter { book in
                (book.name?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                (book.author?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
        
        let sorted: [Book]
        if preferences.bookshelfSortByRecent {
            sorted = filtered.sorted { book1, book2 in
                let time1 = book1.durChapterTime ?? 0
                let time2 = book2.durChapterTime ?? 0
                if time1 == 0 && time2 == 0 { return false }
                if time1 == 0 { return false }
                if time2 == 0 { return true }
                return time1 > time2
            }
        } else {
            sorted = filtered
        }
        return isReversed ? sorted.reversed() : sorted
    }
    
    var body: some View {
        Group {
            List {
                if !searchText.isEmpty {
                    if !filteredAndSortedBooks.isEmpty {
                        Section(header: Text("书架书籍")) {
                            ForEach(filteredAndSortedBooks) { book in
                                bookRowView(for: book)
                            }
                        }
                    }
                    
                    if preferences.searchSourcesFromBookshelf {
                        Section(header: Text("全网搜索")) {
                            if isSearchingOnline {
                                HStack {
                                    Spacer()
                                    ProgressView()
                                    Spacer()
                                }
                            } else if onlineResults.isEmpty {
                                Text("未找到相关书籍").foregroundColor(.secondary).font(.caption)
                            } else {
                                ForEach(onlineResults) { book in
                                    BookSearchResultRow(book: book) {
                                        Task {
                                            await addBookToBookshelf(book: book)
                                        }
                                    }
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        self.selectedOnlineBook = book
                                    }
                                }
                            }
                        }
                    }
                } else {
                    ForEach(filteredAndSortedBooks) { book in
                        bookRowView(for: book)
                    }
                }
            }
            .animation(.easeInOut(duration: 0.3), value: isReversed)
            .navigationTitle("书架")
            .navigationBarTitleDisplayMode(.large)
            .toolbar(content: listToolbarContent)
        }
        .searchable(text: $searchText, prompt: "搜索书名或作者")
        .onChange(of: searchText) { newValue in
            handleSearchChange(newValue)
        }
        .refreshable { await loadBooks() }
        .sheet(isPresented: $showingDocumentPicker) {
            DocumentPicker { url in Task { await importBook(from: url) } }
        }
        .fullScreenCover(item: $selectedBook) { book in
            ReadingView(book: book).environmentObject(apiService)
        }
        .fullScreenCover(item: $selectedOnlineBook) { book in
            BookDetailView(book: book).environmentObject(apiService)
        }
        .task { if apiService.books.isEmpty { await loadBooks() } }
        .overlay {
            if isRefreshing {
                ProgressView("加载中...")
            } else if searchText.isEmpty && apiService.books.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "book.closed")
                        .font(.largeTitle)
                    Text("书架空空如也")
                        .font(.headline)
                }
                .foregroundColor(.secondary)
            }
        }
        .alert("错误", isPresented: .constant(apiService.errorMessage != nil)) {
            Button("确定") { apiService.errorMessage = nil }
        } message: {
            if let error = apiService.errorMessage { Text(error) }
        }
        .alert("已加入书架", isPresented: $showAddSuccessAlert) {
            Button("确定", role: .cancel) { }
        }
        .alert("移出书架", isPresented: $showingDeleteBookAlert) {
            Button("取消", role: .cancel) { bookToDelete = nil }
            Button("移出", role: .destructive) {
                if let book = bookToDelete { deleteBookFromShelf(book) }
                bookToDelete = nil
            }
        } message: {
            Text("确定要将《\(bookToDelete?.name ?? "未知书名")》从书架移除吗？")
        }
    }

    private func handleSearchChange(_ query: String) {
        searchTask?.cancel()
        
        guard !query.isEmpty && preferences.searchSourcesFromBookshelf else {
            onlineResults = []
            return
        }
        
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 800_000_000) // 800ms debounce
            if Task.isCancelled { return }
            
            await performOnlineSearch(query: query)
        }
    }
    
    private func performOnlineSearch(query: String) async {
        await MainActor.run { isSearchingOnline = true }
        
        do {
            let sources = try await apiService.fetchBookSources()
            let enabledSources = sources.filter { $0.enabled }
            
            // Filter by preferred sources if any are selected
            let targetSources = preferences.preferredSearchSourceUrls.isEmpty ? 
                enabledSources : 
                enabledSources.filter { preferences.preferredSearchSourceUrls.contains($0.bookSourceUrl) }
            
            var allResults: [Book] = []
            await withTaskGroup(of: [Book]?.self) { group in
                for source in targetSources {
                    group.addTask {
                        try? await apiService.searchBook(keyword: query, bookSourceUrl: source.bookSourceUrl)
                    }
                }
                
                for await result in group {
                    if let books = result {
                        allResults.append(contentsOf: books)
                    }
                }
            }
            
            await MainActor.run {
                self.onlineResults = allResults
                self.isSearchingOnline = false
            }
        } catch {
            await MainActor.run { self.isSearchingOnline = false }
        }
    }
    
    private func addBookToBookshelf(book: Book) async {
        do {
            try await apiService.saveBook(book: book)
            await MainActor.run { showAddSuccessAlert = true }
            await loadBooks()
        } catch {
            await MainActor.run { apiService.errorMessage = error.localizedDescription }
        }
    }

    @ViewBuilder
    private func bookRowView(for book: Book) -> some View {
        HStack(spacing: 0) {
            // 左侧封面：点击进入详情页
            NavigationLink(destination: BookDetailView(book: book).environmentObject(apiService)) {
                BookCoverImage(url: book.displayCoverUrl)
            }
            .frame(width: 60, height: 80)
            .buttonStyle(PlainButtonStyle())
            
            // 右侧信息：点击直接进入阅读器
            Button(action: { selectedBook = book }) {
                BookInfoArea(book: book)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                bookToDelete = book
                showingDeleteBookAlert = true
            } label: {
                Label("移出书架", systemImage: "trash")
            }
        }
        .contextMenu {
            Button { selectedBook = book } label: {
                Label("开始阅读", systemImage: "book")
            }
            NavigationLink(destination: BookDetailView(book: book).environmentObject(apiService)) {
                Label("书籍详情", systemImage: "info.circle")
            }
            Divider()
            Button(role: .destructive) {
                bookToDelete = book
                showingDeleteBookAlert = true
            } label: {
                Label("移出书架", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private var listToolbarLeadingItems: some View {
        Button(action: { withAnimation { isReversed.toggle() } }) {
            HStack(spacing: 4) {
                Image(systemName: isReversed ? "arrow.up" : "arrow.down")
                Text(isReversed ? "倒序" : "正序")
            }.font(.caption)
        }
    }

    @ViewBuilder
    private var listToolbarTrailingItems: some View {
        HStack(spacing: 16) {
            if !searchText.isEmpty {
                Menu {
                    Toggle("同时搜索书源", isOn: $preferences.searchSourcesFromBookshelf)
                    
                    if preferences.searchSourcesFromBookshelf {
                        Divider()
                        Text("选择搜索源")
                        Button(preferences.preferredSearchSourceUrls.isEmpty ? "✓ 全部启用源" : "全部启用源") {
                            preferences.preferredSearchSourceUrls = []
                        }
                        
                                                ForEach(apiService.availableSources.filter { $0.enabled }, id: \.bookSourceUrl) { source in
                                                    Button(action: { togglePreferredSource(source.bookSourceUrl) }) {
                                                        HStack {
                                                            Text(source.bookSourceName)
                                                            if preferences.preferredSearchSourceUrls.contains(source.bookSourceUrl) {
                                                                Image(systemName: "checkmark")
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        } label: {
                                            Image(systemName: "line.3.horizontal.decrease.circle")
                                                .foregroundColor(preferences.searchSourcesFromBookshelf ? .blue : .secondary)
                                        }
                                    }
                                    
                                    Button(action: { showingDocumentPicker = true }) {
                                        Image(systemName: "plus")
                                    }
                                    NavigationLink(destination: SettingsView()) {
                                        Image(systemName: "gearshape")
                                    }
                                }
                            }
                        
                            private func togglePreferredSource(_ url: String) {
                                if preferences.preferredSearchSourceUrls.contains(url) {
                                    preferences.preferredSearchSourceUrls.removeAll { $0 == url }
                                } else {
                                    preferences.preferredSearchSourceUrls.append(url)
                                }
                            }
                        
                            @ToolbarContentBuilder
                            private func listToolbarContent() -> some ToolbarContent {
                                ToolbarItem(placement: .navigationBarLeading) {
                                    listToolbarLeadingItems
                                }
                                ToolbarItem(placement: .navigationBarTrailing) {
                                    listToolbarTrailingItems
                                }
                            }
                            
                            private func loadBooks() async {
                                isRefreshing = true
                                do {
                                    try await apiService.fetchBookshelf()
                                    if apiService.availableSources.isEmpty {
                                        _ = try? await apiService.fetchBookSources()
                                    }
                                } catch {
                                    apiService.errorMessage = error.localizedDescription
                                }
                                isRefreshing = false
                            }    
    private func importBook(from url: URL) async {
        isRefreshing = true
        do {
            try await apiService.importBook(from: url)
            await loadBooks()
        } catch {
            apiService.errorMessage = "导入失败: \(error.localizedDescription)"
        }
        isRefreshing = false
    }
    
    private func clearAllRemoteCache() {
        Task {
            do {
                try await apiService.clearAllRemoteCache()
                // 清除成功后刷新书架
                await loadBooks()
            } catch {
                apiService.errorMessage = "清除缓存失败: \(error.localizedDescription)"
            }
        }
    }

    private func deleteBookFromShelf(_ book: Book) {
        guard let bookUrl = book.bookUrl, !bookUrl.isEmpty else {
            apiService.errorMessage = "删除失败: 书籍地址为空"
            return
        }
        Task {
            do {
                try await apiService.deleteBook(bookUrl: bookUrl)
                await MainActor.run {
                    apiService.books.removeAll { $0.bookUrl == bookUrl }
                }
            } catch {
                apiService.errorMessage = "删除失败: \(error.localizedDescription)"
            }
        }
    }
}

// 辅助子视图：封面
struct BookCoverImage: View {
    let url: String?
    var body: some View {
        AsyncImage(url: URL(string: url ?? "")) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            Rectangle().fill(Color.gray.opacity(0.3))
                .overlay(Image(systemName: "book.fill").foregroundColor(.gray))
        }
        .frame(width: 60, height: 80)
        .cornerRadius(4)
        .clipped()
    }
}

// 辅助子视图：信息区域
struct BookInfoArea: View {
    let book: Book
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(book.name ?? "未知书名").font(.headline).lineLimit(1)
            Text(book.author ?? "未知作者").font(.subheadline).foregroundColor(.secondary).lineLimit(1)
            if let latest = book.latestChapterTitle {
                Text("最新: \(latest)").font(.caption).foregroundColor(.secondary).lineLimit(1)
            }
            HStack {
                if let dur = book.durChapterTitle {
                    Text("读至: \(dur)").font(.caption2).foregroundColor(.blue).lineLimit(1)
                }
                Spacer()
                if let total = book.totalChapterNum {
                    Text("\(total)章").font(.caption2).foregroundColor(.secondary)
                }
            }
        }
        .padding(.leading, 8)
    }
}
