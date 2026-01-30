import SwiftUI

struct CacheManagementView: View {
    @EnvironmentObject var bookshelfStore: BookshelfStore
    @StateObject private var preferences = UserPreferences.shared
    @State private var cachedBooks: [CachedBookInfo] = []
    @State private var isLoading = false
    @State private var totalSize: Int64 = 0
    @StateObject private var downloadManager = OfflineDownloadManager.shared
    
    struct CachedBookInfo: Identifiable {
        let id: String 
        let name: String
        let author: String
        let size: Int64
        let chapterCount: Int
    }
    
    @State private var lastRefreshTime: Date = .distantPast
    
    var body: some View {
        content
            .navigationTitle("缓存与下载管理")
            .navigationBarTitleDisplayMode(.inline)
            .ifAvailableHideTabBar()
            .task { await loadCachedData() }
            .onReceive(downloadManager.$jobs) { _ in
                throttledRefresh()
            }
    }

    private func throttledRefresh() {
        let now = Date()
        // 限制刷新频率为每 2 秒最多一次，防止频繁更新导致 NavigationLink 闪退
        if now.timeIntervalSince(lastRefreshTime) < 2.0 { return }
        lastRefreshTime = now
        Task { await loadCachedData() }
    }

    private var content: AnyView {
        AnyView(
            List {
                strategySection
                mangaDownloadSection
                downloadingSection
                storageSection
                cachedBooksSection
            }
        )
    }
    
    // MARK: - Sections
    
    private var strategySection: some View {
        Section(header: Text("策略设置"), footer: Text("“自动离线”会将内容永久保存在手机上。“漫画后台预载”则在阅读时提前下载下一章到内存/缓存中，不一定永久保存，但能大幅提升翻页速度。")) {
            Toggle("文字章节自动离线", isOn: $preferences.isTextAutoCacheEnabled)
            Toggle("漫画图片自动离线", isOn: $preferences.isMangaAutoCacheEnabled)
            Toggle("漫画后台预载", isOn: $preferences.isMangaPreloadEnabled)
        }
    }

    private var mangaDownloadSection: some View {
        Section(header: Text("漫画下载设置")) {
            HStack {
                Text("图片并发数")
                Spacer()
                Text("\(preferences.mangaImageMaxConcurrent)")
                    .foregroundColor(.secondary)
            }
            Stepper("", value: $preferences.mangaImageMaxConcurrent, in: 1...6)
            Text("并发越大加载越快，但更容易超时")
                .font(.caption2)
                .foregroundColor(.secondary)

            HStack {
                Text("预加载张数")
                Spacer()
                Text("\(preferences.mangaPrefetchCount)")
                    .foregroundColor(.secondary)
            }
            Stepper("", value: $preferences.mangaPrefetchCount, in: 0...20)
            Text("提前加载的图片数量（含接近章节末尾时的下一章前几张）")
                .font(.caption2)
                .foregroundColor(.secondary)

            HStack {
                Text("内存缓存上限")
                Spacer()
                Text("\(preferences.mangaMemoryCacheMB) MB")
                    .foregroundColor(.secondary)
            }
            Stepper("", value: $preferences.mangaMemoryCacheMB, in: 20...300, step: 10)
            Text("限制内存占用，避免频繁回收")
                .font(.caption2)
                .foregroundColor(.secondary)

            HStack {
                Text("最近保留张数")
                Spacer()
                Text("\(preferences.mangaRecentKeepCount)")
                    .foregroundColor(.secondary)
            }
            Stepper("", value: $preferences.mangaRecentKeepCount, in: 0...200, step: 5)
            Text("保持最近浏览的图片不被快速释放")
                .font(.caption2)
                .foregroundColor(.secondary)

            HStack {
                Text("图片超时")
                Spacer()
                Text("\(Int(preferences.mangaImageTimeout)) 秒")
                    .foregroundColor(.secondary)
            }
            Stepper("", value: $preferences.mangaImageTimeout, in: 5...60, step: 5)
            Text("超时越大越稳，但等待更久")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
    
    private var downloadingSection: some View {
        Section(header: Text("正在下载")) {
            let jobs = downloadManager.activeOrFailedJobs()
            if jobs.isEmpty {
                Text("暂无活跃任务").foregroundColor(.secondary)
            } else {
                ForEach(jobs) { job in
                    DownloadJobRow(job: job, downloadManager: downloadManager)
                }
            }
        }
    }
    
    private var storageSection: some View {
        Section(header: Text("空间占用")) {
            HStack {
                Text("离线数据总量")
                Spacer()
                Text(LocalCacheManager.shared.formatSize(totalSize))
                    .fontWeight(.bold)
                    .foregroundColor(.blue)
            }
            
            Button(role: .destructive, action: clearAllCache) {
                Label("清空所有离线内容", systemImage: "trash")
            }
            .disabled(cachedBooks.isEmpty)
        }
    }
    
    private var cachedBooksSection: some View {
        Section(header: Text("已下载书籍 (\(cachedBooks.count))")) {
            if isLoading {
                HStack { Spacer(); ProgressView("正在扫描磁盘..."); Spacer() }.padding()
            } else if cachedBooks.isEmpty {
                Text("暂无离线缓存").foregroundColor(.secondary)
            } else {
                ForEach(cachedBooks) { info in
                    CachedBookRow(info: info, onDelete: { deleteCache(for: info) })
                }
            }
        }
    }
    
    // MARK: - Logic
    
    private func loadCachedData() async {
        isLoading = true
        var infos: [CachedBookInfo] = []
        var total: Int64 = 0
        for book in bookshelfStore.books {
            if let bookUrl = book.bookUrl {
                let size = LocalCacheManager.shared.getCacheSize(for: bookUrl)
                if size > 0 {
                    let count = LocalCacheManager.shared.getCachedChapterCount(for: bookUrl)
                    infos.append(CachedBookInfo(id: bookUrl, name: book.name ?? "未知书名", author: book.author ?? "未知作者", size: size, chapterCount: count))
                    total += size
                }
            }
        }
        await MainActor.run {
            self.cachedBooks = infos.sorted { $0.size > $1.size }
            self.totalSize = total
            self.isLoading = false
        }
    }
    
    private func deleteCache(for info: CachedBookInfo) {
        LocalCacheManager.shared.clearCache(for: info.id)
        Task { await loadCachedData() }
    }
    
    private func clearAllCache() {
        for info in cachedBooks { LocalCacheManager.shared.clearCache(for: info.id) }
        Task { await loadCachedData() }
    }
}

// MARK: - Helper Rows

struct DownloadJobRow: View {
    let job: OfflineDownloadJob
    let downloadManager: OfflineDownloadManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(job.bookName).font(.headline)
                Spacer()
                StatusBadge(status: job.status)
            }
            ProgressView(value: Double(job.completedUnits), total: Double(max(1, job.totalUnits))).tint(.blue)
            HStack {
                Text(job.message).font(.caption).foregroundColor(.secondary)
                Spacer()
                Text("\(job.completedUnits) / \(job.totalUnits)").font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary)
            }
            if job.status == .failed, let error = job.lastError {
                Text("失败原因: \(error)").font(.caption2).foregroundColor(.red)
            }
            HStack(spacing: 12) {
                if job.status == .downloading {
                    Button(action: { downloadManager.pause(jobId: job.id) }) { Label("暂停", systemImage: "pause.fill").font(.caption) }.buttonStyle(.bordered)
                } else {
                    Button(action: { downloadManager.resume(jobId: job.id) }) { Label("继续", systemImage: "play.fill").font(.caption) }.buttonStyle(.bordered)
                }
                Button(role: .destructive, action: { downloadManager.cancel(jobId: job.id) }) { Label("取消任务", systemImage: "xmark.circle").font(.caption) }.buttonStyle(.bordered)
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 8)
    }
}

struct CachedBookRow: View {
    let info: CacheManagementView.CachedBookInfo
    @EnvironmentObject var bookshelfStore: BookshelfStore
    let onDelete: () -> Void
    
    private var fullBook: Book {
        bookshelfStore.books.first { $0.bookUrl == info.id } ??
        Book(name: info.name, author: info.author, bookUrl: info.id)
    }
    
    var body: some View {
        NavigationLink(destination: BookDetailView(book: fullBook).environmentObject(bookshelfStore)) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(info.name).font(.headline)
                    Text("\(info.chapterCount) 个章节已离线").font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Text(LocalCacheManager.shared.formatSize(info.size)).font(.subheadline).foregroundColor(.gray)
            }
            .contentShape(Rectangle())
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive, action: onDelete) { Label("删除", systemImage: "trash") }
        }
    }
}

struct StatusBadge: View {
    let status: OfflineDownloadStatus
    var body: some View {
        Text(status.rawValue.uppercased()).font(.system(size: 8, weight: .bold)).padding(.horizontal, 6).padding(.vertical, 2).background(backgroundColor.opacity(0.1)).foregroundColor(backgroundColor).cornerRadius(4)
    }
    var backgroundColor: Color {
        switch status {
        case .downloading: return .blue
        case .paused: return .orange
        case .failed: return .red
        }
    }
}
