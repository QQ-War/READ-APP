import SwiftUI

struct BookListView: View {
    @EnvironmentObject var bookshelfStore: BookshelfStore
    @EnvironmentObject var sourceStore: SourceStore
    @StateObject private var preferences = UserPreferences.shared
    @State private var showingDocumentPicker = false
    @State private var selectedBook: Book?
    @State private var showingDeleteBookAlert = false
    @State private var bookToDelete: Book?
    @State private var selectedBookForDetail: Book?
    @StateObject private var listViewModel = BookshelfListViewModel()
    // 过滤和排序后的书籍列表
    var filteredAndSortedBooks: [Book] {
        listViewModel.filteredAndSortedBooks
    }
    
    var body: some View {
        ZStack {
            // 隐式导航触发器：必须放在这里
            if let book = selectedBookForDetail {
                NavigationLink(
                    destination: BookDetailView(book: book).environmentObject(bookshelfStore),
                    isActive: Binding(
                        get: { selectedBookForDetail != nil },
                        set: { if !$0 { selectedBookForDetail = nil } }
                    )
                ) { EmptyView() }
            }

            List {
                // ... rest of list content ...
                if !listViewModel.searchText.isEmpty {
                    if !filteredAndSortedBooks.isEmpty {
                        Section(header: Text("书架书籍")) {
                            ForEach(filteredAndSortedBooks) { book in
                                bookRowView(for: book)
                                    .listRowBackground(preferences.isLiquidGlassEnabled ? Color.clear : nil)
                            }
                        }
                    }
                    
                    if preferences.searchSourcesFromBookshelf {
                        Section(header: Text("全网搜索")) {
                            if listViewModel.isSearchingOnline {
                                HStack {
                                    Spacer()
                                    ProgressView()
                                    Spacer()
                                }
                                .listRowBackground(preferences.isLiquidGlassEnabled ? Color.clear : nil)
                            } else if listViewModel.onlineResults.isEmpty {
                                Text("未找到相关书籍").foregroundColor(.secondary).font(.caption)
                                    .listRowBackground(preferences.isLiquidGlassEnabled ? Color.clear : nil)
                            } else {
                                ForEach(listViewModel.onlineResults) { book in
                                    NavigationLink(destination: BookDetailView(book: book).environmentObject(bookshelfStore)) {
                                        BookSearchResultRow(book: book) {
                                            Task {
                                                await addBookToBookshelf(book: book)
                                            }
                                        }
                                    }
                                    .listRowBackground(preferences.isLiquidGlassEnabled ? Color.clear : nil)
                                }
                            }
                        }
                    }
                } else {
                    ForEach(filteredAndSortedBooks) { book in
                        bookRowView(for: book)
                            .listRowBackground(preferences.isLiquidGlassEnabled ? Color.clear : nil)
                    }
                }
            }
            .glassyListStyle()
            .animation(.easeInOut(duration: 0.3), value: listViewModel.isReversed)
            .navigationTitle("书架")
            .navigationBarTitleDisplayMode(.large)
            .toolbar(content: listToolbarContent)
            .searchable(text: $listViewModel.searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索书名或作者")
        }
        .onChange(of: listViewModel.searchText) { _ in
            listViewModel.handleSearchChange()
        }
        .onChange(of: preferences.searchSourcesFromBookshelf) { _ in
            listViewModel.handleSearchChange()
        }
        .refreshable { await listViewModel.loadBooks() }
        .sheet(isPresented: $showingDocumentPicker) {
            DocumentPicker { url in Task { await importBook(from: url) } }
        }
        .fullScreenCover(item: $selectedBook) { book in
            if book.type == 1 {
                AudioReadingView(book: book).environmentObject(bookshelfStore)
            } else {
                ReadingView(book: book).environmentObject(bookshelfStore)
            }
        }
        .task { 
            listViewModel.configure(bookshelfStore: bookshelfStore, sourceStore: sourceStore, preferences: preferences)
            await listViewModel.loadBooks()
            if sourceStore.availableSources.isEmpty { await sourceStore.refreshSources() }
        }
        .overlay {
            if listViewModel.isRefreshing && bookshelfStore.books.isEmpty {
                ProgressView("加载中...")
            } else if !listViewModel.isRefreshing && listViewModel.searchText.isEmpty && bookshelfStore.books.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "book.closed")
                        .font(.largeTitle)
                    Text("书架空空如也")
                        .font(.headline)
                }
                .foregroundColor(.secondary)
            }
        }
        .alert("操作结果", isPresented: $listViewModel.showAddResultAlert) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(listViewModel.addResultMessage)
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

    private func addBookToBookshelf(book: Book) async {
        await listViewModel.addBookToBookshelf(book)
    }

    @ViewBuilder
    private func bookRowView(for book: Book) -> some View {
        HStack(spacing: 0) {
            // 左侧封面：点击设置状态触发 ZStack 中的 NavigationLink
            Button(action: { selectedBookForDetail = book }) {
                BookCoverImage(url: book.displayCoverUrl)
            }
            .frame(width: 60, height: 80)
            .buttonStyle(PlainButtonStyle())
            
            // 右侧信息：点击直接进入阅读器
            Button(action: { 
                // 启动阅读器前先更新一次排序时间，确保书籍排到最前
                bookshelfStore.updateProgress(bookUrl: book.bookUrl ?? "", index: book.durChapterIndex ?? 0, pos: book.durChapterPos ?? 0, title: book.durChapterTitle, updateTimestamp: true)
                selectedBook = book 
            }) {
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
            Button { selectedBookForDetail = book } label: {
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
        Button(action: { withAnimation { listViewModel.isReversed.toggle() } }) {
            HStack(spacing: 4) {
                Image(systemName: listViewModel.isReversed ? "arrow.up" : "arrow.down")
                Text(listViewModel.isReversed ? "倒序" : "正序")
            }.font(.caption)
        }
    }

    @ViewBuilder
    private var listToolbarTrailingItems: some View {
        HStack(spacing: 16) {
            // 搜索配置按钮：始终可见
            NavigationLink(destination: PreferredSourcesView().environmentObject(sourceStore)) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .foregroundColor(preferences.searchSourcesFromBookshelf ? .blue : .secondary)
            }
            
            Button(action: { showingDocumentPicker = true }) { 
                Image(systemName: "plus") 
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
        await listViewModel.loadBooks()
    }
    
    private func importBook(from url: URL) async {
        listViewModel.isRefreshing = true
        do {
            try await bookshelfStore.importBook(from: url)
            await listViewModel.loadBooks()
        } catch {
            if Task.isCancelled || error is CancellationError {
                listViewModel.isRefreshing = false
                return
            }
            bookshelfStore.errorMessage = "导入失败: \(error.localizedDescription)"
        }
        listViewModel.isRefreshing = false
    }
    
    private func clearAllRemoteCache() {
        Task {
            do {
                try await APIService.shared.clearAllRemoteCache()
                // 清除成功后刷新书架
                await loadBooks()
            } catch {
                if Task.isCancelled || error is CancellationError {
                    return
                }
                bookshelfStore.errorMessage = "清除缓存失败: \(error.localizedDescription)"
            }
        }
    }

    private func deleteBookFromShelf(_ book: Book) {
        guard let bookUrl = book.bookUrl, !bookUrl.isEmpty else {
            bookshelfStore.errorMessage = "删除失败: 书籍地址为空"
            return
        }
        Task {
            do {
                try await bookshelfStore.deleteBook(bookUrl: bookUrl)
            } catch {
                if Task.isCancelled || error is CancellationError {
                    return
                }
                bookshelfStore.errorMessage = "删除失败: \(error.localizedDescription)"
            }
        }
    }
}

// 辅助子视图：封面
struct BookCoverImage: View {
    let url: String?
    var body: some View {
        CachedRemoteImage(urlString: url) { image in
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
    
    private var progressText: String {
        let pos = book.durChapterPos ?? 0
        if pos <= 0 { return "" }
        // 兼容旧版索引和新版比例，并封顶 100%
        let percent: Int
        if pos > 1.0 {
            percent = 100 
        } else {
            percent = Int(pos * 100)
        }
        return " (\(percent)%)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(book.name ?? "未知书名").font(.headline).lineLimit(1)
            Text(book.author ?? "未知作者").font(.subheadline).foregroundColor(.secondary).lineLimit(1)
            if let latest = book.latestChapterTitle {
                Text("最新: \(latest)").font(.caption).foregroundColor(.secondary).lineLimit(1)
            }
            if book.type == 1 {
                Text("音频书")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
            HStack {
                if let dur = book.durChapterTitle {
                    Text("读至: \(dur)\(progressText)").font(.caption2).foregroundColor(.blue).lineLimit(1)
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
