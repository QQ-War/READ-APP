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
    
    // 过滤和排序后的书籍列表
    var filteredAndSortedBooks: [Book] {
        // ... (保持原有排序逻辑不变)
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
        List {
            ForEach(filteredAndSortedBooks) { book in
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
        }
        .animation(.easeInOut(duration: 0.3), value: isReversed)
        .navigationTitle("书架")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, prompt: "搜索书名或作者")
        .refreshable { await loadBooks() }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { withAnimation { isReversed.toggle() } }) {
                    HStack(spacing: 4) {
                        Image(systemName: isReversed ? "arrow.up" : "arrow.down")
                        Text(isReversed ? "倒序" : "正序")
                    }.font(.caption)
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack {
                    Button(action: { showingDocumentPicker = true }) { Image(systemName: "plus") }
                    NavigationLink(destination: SettingsView()) { Image(systemName: "gearshape") }
                }
            }
        }
        .sheet(isPresented: $showingDocumentPicker) {
            DocumentPicker { url in Task { await importBook(from: url) } }
        }
        .fullScreenCover(item: $selectedBook) { book in
            ReadingView(book: book).environmentObject(apiService)
        }
        .task { if apiService.books.isEmpty { await loadBooks() } }
        .overlay {
            if isRefreshing {
                ProgressView("加载中...")
            } else if filteredAndSortedBooks.isEmpty && !apiService.books.isEmpty {
                ContentUnavailableView("未找到匹配的书籍", systemImage: "magnifyingglass")
            }
        }
        .alert("错误", isPresented: .constant(apiService.errorMessage != nil)) {
            Button("确定") { apiService.errorMessage = nil }
        } message: {
            if let error = apiService.errorMessage { Text(error) }
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
    
    private func loadBooks() async {
        isRefreshing = true
        do {
            try await apiService.fetchBookshelf()
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
