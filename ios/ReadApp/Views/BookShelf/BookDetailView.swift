import SwiftUI

struct BookDetailView: View {
    let book: Book
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var bookshelfStore: BookshelfStore
    
    private var currentBook: Book {
        bookshelfStore.books.first { $0.bookUrl == book.bookUrl } ?? book
    }
    @StateObject private var preferences = UserPreferences.shared
    @State private var chapters: [BookChapter] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var errorSheet: SelectableMessage?
    @StateObject private var downloadManager = OfflineDownloadManager.shared
    
    // 下载与缓存状态
    @State private var startChapter: String = "1"
    @State private var endChapter: String = ""
    @State private var showCustomRange = false
    @State private var showingDownloadOptions = false
    @State private var cachedChapters: Set<Int> = []
    
    // 交互状态
    @State private var isReading = false
    @State private var showingSourceSwitch = false
    @State private var showingClearCacheAlert = false
    @State private var showingClearCacheOptions = false
    @State private var rangeActionType: RangeActionType = .download
    @State private var showingAddSuccessAlert = false
    
    enum RangeActionType {
        case download
        case clear
    }
    @State private var showingRemoveSuccessAlert = false
    @State private var showingChapterList = false
    
    private var isInBookshelf: Bool {
        bookshelfStore.books.contains { $0.bookUrl == book.bookUrl }
    }
    
    private var isManuallyMarkedAsManga: Bool {
        guard let url = book.bookUrl else { return false }
        return preferences.manualMangaUrls.contains(url)
    }
    
    private func toggleManualManga() {
        guard let url = book.bookUrl else { return }
        if preferences.manualMangaUrls.contains(url) {
            preferences.manualMangaUrls.remove(url)
        } else {
            preferences.manualMangaUrls.insert(url)
        }
    }

    private var isAudioBook: Bool {
        book.type == 1
    }

    var body: some View {
        content
            .navigationTitle(book.name ?? "书籍详情")
            .navigationBarTitleDisplayMode(.inline)
            .ifAvailableHideTabBar()
        .confirmationDialog("选择缓存范围", isPresented: $showingDownloadOptions, titleVisibility: .visible) {
            Button("缓存全文") { startDownload(start: 1, end: chapters.count) }
            Button("缓存未读") {
                let current = (currentBook.durChapterIndex ?? 0) + 1
                startDownload(start: current, end: chapters.count)
            }
            Button("缓存后续 50 章") { 
                let current = (currentBook.durChapterIndex ?? 0) + 1
                startDownload(start: current, end: min(current + 50, chapters.count)) 
            }
            Button("自定义范围") { 
                rangeActionType = .download
                withAnimation { showCustomRange = true } 
            }
            Button("取消", role: .cancel) { }
        }
        .confirmationDialog("清除缓存选项", isPresented: $showingClearCacheOptions, titleVisibility: .visible) {
            Button("清除已读 (1-\((currentBook.durChapterIndex ?? 0)))") {
                let current = currentBook.durChapterIndex ?? 0
                if current > 0 {
                    LocalCacheManager.shared.clearChapterRange(bookUrl: book.bookUrl ?? "", start: 0, end: current - 1)
                    refreshCachedStatus()
                }
            }
            Button("清除到开头 (1-\((currentBook.durChapterIndex ?? 0) + 1))") {
                let current = currentBook.durChapterIndex ?? 0
                LocalCacheManager.shared.clearChapterRange(bookUrl: book.bookUrl ?? "", start: 0, end: current)
                refreshCachedStatus()
            }
            Button("自定义区间") {
                rangeActionType = .clear
                withAnimation { showCustomRange = true }
            }
            Button("清空所有离线内容", role: .destructive) {
                showingClearCacheAlert = true
            }
            Button("取消", role: .cancel) { }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if let job = downloadManager.job(for: book.bookUrl ?? "") {
                    Button("停止", role: .destructive) { downloadManager.cancel(jobId: job.id) }
                }
            }
        }
        .task { await loadData() }
        .onReceive(downloadManager.$jobs) { _ in refreshCachedStatus() }
        .sheet(item: $errorSheet) { sheet in
            SelectableMessageSheet(title: sheet.title, message: sheet.message) {
                errorMessage = nil
                errorSheet = nil
            }
        }
        .alert("清除缓存", isPresented: $showingClearCacheAlert) {
            Button("取消", role: .cancel) { }
            Button("清除", role: .destructive) { clearBookCache() }
        } message: {
            Text("确定要删除本书所有的离线缓存内容吗？")
        }
        .alert("已加入书架", isPresented: $showingAddSuccessAlert) {
            Button("确定", role: .cancel) { }
        }
        .alert("已从书架移除", isPresented: $showingRemoveSuccessAlert) {
            Button("确定", role: .cancel) { }
        }
        .sheet(isPresented: $showingSourceSwitch) {
            SourceSwitchView(bookName: book.name ?? "", author: book.author ?? "", currentSource: book.origin ?? "") { newBook in
                updateBookSource(with: newBook)
            }
        }
        .sheet(isPresented: $showingChapterList) {
            ChapterListView(
                chapters: chapters,
                currentIndex: currentBook.durChapterIndex ?? 0,
                bookUrl: book.bookUrl ?? "",
                cachedChapters: $cachedChapters,
                onSelectChapter: { index in
                    if let bookUrl = book.bookUrl {
                        bookshelfStore.updateProgress(bookUrl: bookUrl, index: index, pos: 0, title: chapters[index].title)
                    }
                    isReading = true
                },
                onRebuildChapterUrls: {
                    await loadData()
                }
            )
        }
        .onChange(of: errorMessage) { newValue in
            guard let message = newValue, !message.isEmpty else { return }
            errorSheet = SelectableMessage(title: "提示", message: message)
        }
    }

    private var content: AnyView {
        AnyView(
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // 1. 头部信息
                    headerSection
                    
                    if !isAudioBook {
                        // 漫画模式手动开关
                        HStack {
                            Label("强制漫画模式", systemImage: "photo.on.rectangle.angled")
                                .font(.subheadline)
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { isManuallyMarkedAsManga },
                                set: { _ in toggleManualManga() }
                            ))
                            .labelsHidden()
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(preferences.isLiquidGlassEnabled ? Color.clear : Color.gray.opacity(0.05))
                        .cornerRadius(10)
                        .glassyCard(cornerRadius: 12, padding: 0)
                        .padding(.horizontal)
                    }
                    
                    // 2. 操作按钮区
                    HStack(spacing: 16) {
                        Button(action: { showingSourceSwitch = true }) {
                            Label("换源阅读", systemImage: "arrow.2.squarepath")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(Color.orange.opacity(0.1))
                                .foregroundColor(.orange)
                                .cornerRadius(8)
                        }
                        
                        Button(action: { showingClearCacheOptions = true }) {
                            Label("清除缓存", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(Color.red.opacity(0.1))
                                .foregroundColor(.red)
                                .cornerRadius(8)
                        }
                    }
                    .padding(.horizontal)
                    
                    // 3. 下载控制区
                    downloadControls
                    
                    // 4. 简介区
                    if let intro = book.intro, !intro.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("简介").font(.headline)
                            Text(intro)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .lineLimit(nil)
                        }
                        .padding(.horizontal)
                    }
                    
                    // 5. 目录
                    Button(action: { showingChapterList = true }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("目录").font(.headline).foregroundColor(.primary)
                                if !chapters.isEmpty {
                                    let currentIdx = currentBook.durChapterIndex ?? 0
                                    let currentTitle = chapters.indices.contains(currentIdx) ? chapters[currentIdx].title : "第一章"
                                    Text("当前进度: \(currentTitle)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            Text("共 \(chapters.count) 章").font(.subheadline).foregroundColor(.secondary)
                            Image(systemName: "chevron.right").font(.subheadline).foregroundColor(.secondary)
                        }
                        .padding()
                        .background(preferences.isLiquidGlassEnabled ? Color.clear : Color.gray.opacity(0.05))
                        .cornerRadius(12)
                        .glassyCard(cornerRadius: 12, padding: 0)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                }
            }
            .refreshable {
                await loadData()
            }
            .background(preferences.isLiquidGlassEnabled ? Color.clear : nil)
            .liquidGlassBackground()
        )
    }
    
    // MARK: - Subviews
    
    private var headerSection: some View {
        HStack(alignment: .top, spacing: 16) {
            if let coverUrl = book.displayCoverUrl {
                CachedRemoteImage(urlString: coverUrl) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.gray.opacity(0.3)
                }
                .frame(width: 100, height: 140)
                .cornerRadius(8)
                .shadow(radius: 4)
                .clipped()
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text(book.name ?? "未知书名").font(.title2).fontWeight(.bold)
                Text(book.author ?? "未知作者").font(.subheadline).foregroundColor(.secondary)
                HStack(spacing: 8) {
                    Text(book.originName ?? "未知来源")
                        .font(.caption)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .cornerRadius(4)
                    if isAudioBook {
                        Text("音频书")
                            .font(.caption)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.orange.opacity(0.1))
                            .foregroundColor(.orange)
                            .cornerRadius(4)
                    }
                }
                
                Spacer()
                
                if isInBookshelf {
                    Button(action: removeFromBookshelf) {
                        Label("移出书架", systemImage: "minus.circle")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.red.opacity(0.1))
                            .foregroundColor(.red)
                            .cornerRadius(8)
                    }
                } else {
                    Button(action: addToBookshelf) {
                        Label("加入书架", systemImage: "plus.circle")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
                            .cornerRadius(8)
                    }
                }
                
                Button(action: { isReading = true }) {
                    Text(isAudioBook ? "开始播放" : "开始阅读")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .fullScreenCover(isPresented: $isReading) {
                    if isAudioBook {
                        AudioReadingView(book: currentBook).environmentObject(bookshelfStore)
                    } else {
                        ReadingView(book: currentBook).environmentObject(bookshelfStore)
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.top)
        .glassyCard(cornerRadius: 16, padding: 12)
    }
    
    private var downloadControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("离线缓存").font(.headline)
                Spacer()
                if downloadManager.job(for: book.bookUrl ?? "") == nil {
                    Button(action: { showingDownloadOptions = true }) {
                        HStack {
                            Image(systemName: "arrow.down.circle")
                            Text("选择范围")
                        }
                        .padding(.horizontal, 12).padding(.vertical, 6).background(Color.blue.opacity(0.1)).cornerRadius(16)
                    }
                }
            }
            
            if showCustomRange && downloadManager.job(for: book.bookUrl ?? "") == nil {
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("从第几章").font(.caption).foregroundColor(.secondary)
                            TextField("1", text: $startChapter).keyboardType(.numberPad).textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("到第几章").font(.caption).foregroundColor(.secondary)
                            TextField("\(chapters.count)", text: $endChapter).keyboardType(.numberPad).textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                    }
                    HStack(spacing: 20) {
                        Button(action: { withAnimation { showCustomRange = false } }) {
                            Text("取消").foregroundColor(.secondary)
                        }
                        Spacer()
                        Button(rangeActionType == .download ? "开始缓存" : "开始清理") {
                            withAnimation { showCustomRange = false }
                            if rangeActionType == .download {
                                startDownload(start: Int(startChapter), end: Int(endChapter))
                            } else {
                                startClearRange(start: Int(startChapter), end: Int(endChapter))
                            }
                        }
                        .font(.system(size: 16, weight: .bold))
                    }
                }
                .padding(.vertical, 8).transition(.move(edge: .top).combined(with: .opacity))
            }
            
            if let job = downloadManager.job(for: book.bookUrl ?? "") {
                VStack(spacing: 8) {
                    let total = max(1, job.totalUnits)
                    ProgressView(value: Double(job.completedUnits), total: Double(total)).tint(.blue)
                    Text(job.message).font(.caption).foregroundColor(.secondary)
                    if job.status == .failed, let error = job.lastError {
                        Text("失败原因: \(error)").font(.caption2).foregroundColor(.red)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding().background(Color.gray.opacity(0.05)).cornerRadius(12).padding(.horizontal)
    }
    
    // MARK: - Logic
    
    private func loadData() async {
        isLoading = true
        defer { isLoading = false }
        do {
            chapters = try await APIService.shared.fetchChapterList(bookUrl: book.bookUrl ?? "", bookSourceUrl: book.origin)
            if endChapter.isEmpty { endChapter = "\(chapters.count)" }
            refreshCachedStatus()
        } catch {
            if Task.isCancelled || error is CancellationError {
                return
            }
            errorMessage = error.localizedDescription
        }
    }
    
    private func refreshCachedStatus() {
        var cached = Set<Int>()
        for chapter in chapters {
            if LocalCacheManager.shared.isChapterCached(bookUrl: book.bookUrl ?? "", index: chapter.index) {
                cached.insert(chapter.index)
            }
        }
        self.cachedChapters = cached
    }
    
    private func clearBookCache() {
        LocalCacheManager.shared.clearCache(for: book.bookUrl ?? "")
        refreshCachedStatus()
    }
    
    private func startClearRange(start: Int?, end: Int?) {
        guard let start = start, let end = end, start > 0, end >= start, end <= chapters.count else {
            errorMessage = "请输入有效的章节范围 (1-\(chapters.count))"
            return
        }
        LocalCacheManager.shared.clearChapterRange(bookUrl: book.bookUrl ?? "", start: start - 1, end: end - 1)
        refreshCachedStatus()
    }
    
    private func updateBookSource(with newBook: Book) {
        Task {
            do {
                guard let oldUrl = book.bookUrl, let newUrl = newBook.bookUrl, let sourceUrl = newBook.origin else { return }
                
                isLoading = true
                try await APIService.shared.changeBookSource(oldBookUrl: oldUrl, newBookUrl: newUrl, newBookSourceUrl: sourceUrl)
                
                // 换源成功后，先刷新书架，然后通知父级并返回
                await bookshelfStore.refreshBookshelf()
                await MainActor.run {
                    isLoading = false
                    dismiss() // 换源后通常需要重新打开详情页
                }
            } catch { 
                if Task.isCancelled || error is CancellationError {
                    await MainActor.run {
                        isLoading = false
                    }
                    return
                }
                await MainActor.run {
                    isLoading = false
                    errorMessage = "换源失败: \(error.localizedDescription)" 
                }
            }
        }
    }
    
    private func addToBookshelf() {
        Task {
            do {
                try await bookshelfStore.saveBook(book)
                await bookshelfStore.refreshBookshelf()
                await MainActor.run {
                    showingAddSuccessAlert = true
                }
            } catch {
                if Task.isCancelled || error is CancellationError {
                    return
                }
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    private func removeFromBookshelf() {
        guard let bookUrl = book.bookUrl else { return }
        Task {
            do {
                try await bookshelfStore.deleteBook(bookUrl: bookUrl)
                await MainActor.run {
                    showingRemoveSuccessAlert = true
                }
            } catch {
                if Task.isCancelled || error is CancellationError {
                    return
                }
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    private func startDownload(start: Int?, end: Int?) {
        guard let start = start, let end = end, start > 0, end >= start, end <= chapters.count else {
            errorMessage = "请输入有效的章节范围 (1-\(chapters.count))"
            return
        }
        let isManga = book.type == 2 || preferences.manualMangaUrls.contains(book.bookUrl ?? "")
        _ = downloadManager.startDownload(book: book, chapters: chapters, start: start, end: end, isManga: isManga)
    }
}

// MARK: - Source Switch View
struct SourceSwitchView: View {
    let bookName: String
    let author: String
    let currentSource: String
    let onSelect: (Book) -> Void
    @Environment(\.dismiss) var dismiss
    @State private var searchResults: [Book] = []
    @State private var isSearching = false
    
    var body: some View {
        NavigationView {
            List {
                if isSearching {
                    HStack { Spacer(); ProgressView("正在全网匹配来源..."); Spacer() }
                } else if searchResults.isEmpty {
                    VStack(spacing: 12) {
                        Text("未找到书名完全一致的备选源").foregroundColor(.secondary)
                        Text("建议：检查书源是否启用或书籍是否更名").font(.caption2).foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                } else {
                    Section(header: GlassySectionHeader(title: "完全匹配的结果 (\(searchResults.count))")) {
                        ForEach(searchResults) { book in
                            let isAuthorMatch = book.author == author
                            Button(action: { onSelect(book); dismiss() }) {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(book.originName ?? "未知源").font(.headline)
                                        Spacer()
                                        if isAuthorMatch {
                                            Text("推荐")
                                                .font(.caption2).bold()
                                                .padding(.horizontal, 6).padding(.vertical, 2)
                                                .background(Color.green.opacity(0.1))
                                                .foregroundColor(.green).cornerRadius(4)
                                        }
                                        if book.origin == currentSource { 
                                            Text("当前").font(.caption2)
                                                .padding(.horizontal, 6).padding(.vertical, 2)
                                                .background(Color.blue.opacity(0.1))
                                                .foregroundColor(.blue).cornerRadius(4)
                                        }
                                    }
                                    
                                    HStack {
                                        Text(book.name ?? "").font(.subheadline)
                                        Text("•")
                                        Text(book.author ?? "未知作者")
                                            .foregroundColor(isAuthorMatch ? .primary : .secondary)
                                    }
                                    .font(.subheadline)
                                    
                                    if let latest = book.latestChapterTitle { 
                                        Text("最新: \(latest)").font(.caption2).foregroundColor(.secondary).lineLimit(1) 
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .glassyListStyle()
            .navigationTitle("更换来源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("关闭") { dismiss() }.glassyToolbarButton() } }
            .task { await performSearch() }
        }
    }
    
    private func performSearch() async {
        isSearching = true
        let sources = (try? await APIService.shared.fetchBookSources()) ?? []
        let enabledSources = sources.filter { $0.enabled }
        
        var allMatches: [Book] = []
        
        await withTaskGroup(of: [Book]?.self) { group in
            for source in enabledSources { 
                group.addTask { 
                    // 仅使用书名搜索，确保搜得到
                    return try? await APIService.shared.searchBook(keyword: bookName, bookSourceUrl: source.bookSourceUrl)
                } 
            }
            for await result in group {
                if let books = result {
                    // 本地进行严格书名过滤
                    let exactMatches = books.filter { $0.name == bookName }
                    allMatches.append(contentsOf: exactMatches)
                }
            }
        }
        
        // 排序逻辑：作者一致的排最前面
        allMatches.sort { b1, b2 in
            let match1 = (b1.author == author) ? 1 : 0
            let match2 = (b2.author == author) ? 1 : 0
            return match1 > match2
        }
        
        await MainActor.run {
            self.searchResults = allMatches
            isSearching = false
        }
    }
}
