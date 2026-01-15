import SwiftUI

struct BookDetailView: View {
    let book: Book
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var apiService: APIService
    
    private var currentBook: Book {
        apiService.books.first { $0.bookUrl == book.bookUrl } ?? book
    }
    @StateObject private var preferences = UserPreferences.shared
    @State private var chapters: [BookChapter] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
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
    @State private var showingAddSuccessAlert = false
    @State private var showingRemoveSuccessAlert = false
    @State private var selectedGroupIndex: Int = 0
    
    private var isInBookshelf: Bool {
        apiService.books.contains { $0.bookUrl == book.bookUrl }
    }
    
    private var chapterGroups: [Int] {
        guard !chapters.isEmpty else { return [] }
        return Array(0...((chapters.count - 1) / 50))
    }
    
    private var isManuallyMarkedAsManga: Bool {
        guard let url = book.bookUrl else { return false }
        return preferences.manualMangaUrls.contains(url)
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                
                mangaToggleSection
                
                actionButtonsSection
                
                downloadControls
                
                introSection
                
                chaptersListSection
            }
        }
        .navigationTitle(book.name ?? "书籍详情")
        .navigationBarTitleDisplayMode(.inline)
        .ifAvailableHideTabBar()
        .confirmationDialog("选择缓存范围", isPresented: $showingDownloadOptions, titleVisibility: .visible) {
            Button("缓存全文") { startDownload(start: 1, end: chapters.count) }
            Button("缓存后续 50 章") { 
                let current = (currentBook.durChapterIndex ?? 0) + 1
                startDownload(start: current, end: min(current + 50, chapters.count)) 
            }
            Button("自定义范围") { withAnimation { showCustomRange = true } }
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
        .onChange(of: downloadManager.jobs) { _ in refreshCachedStatus() }
        .alert("提示", isPresented: .constant(errorMessage != nil)) {
            Button("确定") { errorMessage = nil }
        } message: {
            if let error = errorMessage { Text(error) }
        }
        .alert("清除缓存", isPresented: $showingClearCacheAlert) {
            Button("取消", role: .cancel) { }
            Button("清除", role: .destructive) { clearBookCache() }
        } message: {
            Text("确定要删除本书所有的离线缓存内容吗？")
        }
        .alert("已加入书架", isPresented: $showingAddSuccessAlert) { Button("确定", role: .cancel) { } }
        .alert("已从书架移除", isPresented: $showingRemoveSuccessAlert) { Button("确定", role: .cancel) { } }
        .sheet(isPresented: $showingSourceSwitch) {
            SourceSwitchView(bookName: book.name ?? "", author: book.author ?? "", currentSource: book.origin ?? "") { newBook in
                updateBookSource(with: newBook)
            }
        }
    }
    
    // MARK: - Subviews
    
    private var mangaToggleSection: some View {
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
        .background(Color.gray.opacity(0.05))
        .cornerRadius(10)
        .padding(.horizontal)
    }
    
    private var actionButtonsSection: some View {
        HStack(spacing: 16) {
            Button(action: { showingSourceSwitch = true }) {
                Label("换源阅读", systemImage: "arrow.2.squarepath")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.orange.opacity(0.1))
                    .foregroundColor(.orange)
                    .cornerRadius(8)
            }
            
            Button(action: { showingClearCacheAlert = true }) {
                Label("清除缓存", systemImage: "trash")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.1))
                    .foregroundColor(.red)
                    .cornerRadius(8)
            }
        }
        .padding(.horizontal)
    }
    
    private var introSection: some View {
        Group {
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
        }
    }
    
    private var chaptersListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("目录").font(.headline)
                Spacer()
                Text("共 \(chapters.count) 章").font(.caption).foregroundColor(.secondary)
            }
            .padding(.horizontal)
            
            if chapterGroups.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(chapterGroups, id: \.self) { index in
                            let start = index * 50 + 1
                            let end = min((index + 1) * 50, chapters.count)
                            Button(action: { selectedGroupIndex = index }) {
                                Text("\(start)-\(end)")
                                    .font(.caption)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(selectedGroupIndex == index ? Color.blue : Color.gray.opacity(0.1))
                                    .foregroundColor(selectedGroupIndex == index ? .white : .primary)
                                    .cornerRadius(16)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
            
            if isLoading {
                HStack { Spacer(); ProgressView(); Spacer() }.padding()
            } else {
                let startIndex = selectedGroupIndex * 50
                let endIndex = min(startIndex + 50, chapters.count)
                let visibleChapters = chapters.indices.contains(startIndex) ? Array(chapters[startIndex..<endIndex]) : []
                
                LazyVStack(spacing: 0) {
                    ForEach(visibleChapters) { chapter in
                        chapterRow(chapter)
                    }
                }
            }
        }
    }

    private var headerSection: some View {
        HStack(alignment: .top, spacing: 16) {
            if let coverUrl = book.displayCoverUrl {
                AsyncImage(url: URL(string: coverUrl)) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.gray.opacity(0.3)
                }
                .frame(width: 100, height: 140)
                .cornerRadius(8)
                .shadow(radius: 4)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text(book.name ?? "未知书名").font(.title2).fontWeight(.bold)
                Text(book.author ?? "未知作者").font(.subheadline).foregroundColor(.secondary)
                Text(book.originName ?? "未知来源").font(.caption).padding(.horizontal, 8).padding(.vertical, 4).background(Color.blue.opacity(0.1)).foregroundColor(.blue).cornerRadius(4)
                
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
                    Text("开始阅读")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .fullScreenCover(isPresented: $isReading, onDismiss: {
                    Task { try? await apiService.fetchBookshelf() }
                }) {
                    ReadingView(book: currentBook).environmentObject(apiService)
                }
            }
        }
        .padding(.horizontal)
        .padding(.top)
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
                        Button("开始缓存") {
                            withAnimation { showCustomRange = false }
                            startDownload(start: Int(startChapter), end: Int(endChapter))
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
    
    private func chapterRow(_ chapter: BookChapter) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(chapter.title).font(.subheadline).lineLimit(1)
                Spacer()
                if cachedChapters.contains(chapter.index) {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green).font(.caption)
                }
            }
            .padding(.vertical, 12).padding(.horizontal)
            Divider().padding(.leading)
        }
    }
    
    // MARK: - Logic
    
    private func loadData() async {
        isLoading = true
        do {
            chapters = try await apiService.fetchChapterList(bookUrl: book.bookUrl ?? "", bookSourceUrl: book.origin)
            if endChapter.isEmpty { endChapter = "\(chapters.count)" }
            let initialIndex = currentBook.durChapterIndex ?? 0
            selectedGroupIndex = initialIndex / 50
            refreshCachedStatus()
        } catch { errorMessage = error.localizedDescription }
        isLoading = false
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
    
    private func toggleManualManga() {
        guard let url = book.bookUrl else { return }
        if preferences.manualMangaUrls.contains(url) {
            preferences.manualMangaUrls.remove(url)
        } else {
            preferences.manualMangaUrls.insert(url)
        }
    }

    private func updateBookSource(with newBook: Book) {
        Task {
            do {
                guard let oldUrl = book.bookUrl, let newUrl = newBook.bookUrl, let sourceUrl = newBook.origin else { return }
                isLoading = true
                try await apiService.changeBookSource(oldBookUrl: oldUrl, newBookUrl: newUrl, newBookSourceUrl: sourceUrl)
                try await apiService.fetchBookshelf()
                await MainActor.run { isLoading = false; dismiss() }
            } catch { await MainActor.run { isLoading = false; errorMessage = "换源失败: \(error.localizedDescription)" } }
        }
    }
    
    private func addToBookshelf() {
        Task {
            do {
                try await apiService.saveBook(book: book)
                try await apiService.fetchBookshelf()
                await MainActor.run { showingAddSuccessAlert = true }
            } catch { await MainActor.run { errorMessage = error.localizedDescription } }
        }
    }
    
    private func removeFromBookshelf() {
        guard let bookUrl = book.bookUrl else { return }
        Task {
            do {
                try await apiService.deleteBook(bookUrl: bookUrl)
                try await apiService.fetchBookshelf()
                await MainActor.run { showingRemoveSuccessAlert = true }
            } catch { await MainActor.run { errorMessage = error.localizedDescription } }
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