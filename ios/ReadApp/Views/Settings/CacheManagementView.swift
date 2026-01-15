import SwiftUI
import CryptoKit

struct CacheManagementView: View {
    @EnvironmentObject var apiService: APIService
    @StateObject private var preferences = UserPreferences.shared
    @State private var cachedBooks: [CachedBookInfo] = []
    @State private var isLoading = false
    @State private var totalSize: Int64 = 0
    @StateObject private var downloadManager = OfflineDownloadManager.shared
    
    struct CachedBookInfo: Identifiable {
        let id: String // bookUrl or hash
        let name: String
        let author: String
        let size: Int64
        let chapterCount: Int
    }
    
    var body: some View {
        List {
            Section(header: Text("策略设置"), footer: Text("“自动离线”会将内容永久保存在手机上。“漫画后台预载”则在阅读时提前下载下一章到内存/缓存中，不一定永久保存，但能大幅提升翻页速度。")) {
                Toggle("文字章节自动离线", isOn: $preferences.isTextAutoCacheEnabled)
                Toggle("漫画图片自动离线", isOn: $preferences.isMangaAutoCacheEnabled)
                Toggle("漫画后台预载", isOn: $preferences.isMangaPreloadEnabled)
            }

            Section(header: Text("正在下载")) {
                let jobs = downloadManager.activeOrFailedJobs()
                if jobs.isEmpty {
                    Text("暂无活跃任务").foregroundColor(.secondary)
                } else {
                    ForEach(jobs) { job in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(job.bookName).font(.headline)
                                Spacer()
                                StatusBadge(status: job.status)
                            }
                            
                            ProgressView(value: Double(job.completedUnits), total: Double(max(1, job.totalUnits)))
                                .tint(.blue)
                            
                            HStack {
                                Text(job.message).font(.caption).foregroundColor(.secondary)
                                Spacer()
                                Text("\(job.completedUnits) / \(job.totalUnits)")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }

                            if job.status == .failed, let error = job.lastError {
                                Text("失败原因: \(error)").font(.caption2).foregroundColor(.red)
                            }
                            
                            HStack(spacing: 12) {
                                if job.status == .downloading {
                                    Button(action: { downloadManager.pause(jobId: job.id) }) {
                                        Label("暂停", systemImage: "pause.fill").font(.caption)
                                    }
                                    .buttonStyle(.bordered)
                                } else {
                                    Button(action: { downloadManager.resume(jobId: job.id) }) {
                                        Label("继续", systemImage: "play.fill").font(.caption)
                                    }
                                    .buttonStyle(.bordered)
                                }
                                
                                Button(role: .destructive, action: { downloadManager.cancel(jobId: job.id) }) {
                                    Label("取消任务", systemImage: "xmark.circle").font(.caption)
                                }
                                .buttonStyle(.bordered)
                            }
                            .padding(.top, 4)
                        }
                        .padding(.vertical, 8)
                    }
                }
            }

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
            
            Section(header: Text("已下载书籍 (\(cachedBooks.count))")) {
                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView("正在扫描磁盘...")
                        Spacer()
                    }
                    .padding()
                } else if cachedBooks.isEmpty {
                    Text("暂无离线缓存").foregroundColor(.secondary)
                } else {
                    ForEach(cachedBooks) { info in
                        NavigationLink(destination: BookDetailView(book: Book(bookUrl: info.id, name: info.name, author: info.author)).environmentObject(apiService)) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(info.name).font(.headline)
                                    Text("\(info.chapterCount) 个章节已离线")
                                        .font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                Text(LocalCacheManager.shared.formatSize(info.size))
                                    .font(.subheadline).foregroundColor(.gray)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                deleteCache(for: info)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("缓存与下载管理")
        .navigationBarTitleDisplayMode(.inline)
        .ifAvailableHideTabBar()
        .task {
            await loadCachedData()
        }
        .onChange(of: downloadManager.jobs) { _ in
            Task { await loadCachedData() }
        }
    }
    
    private func loadCachedData() async {
        isLoading = true
        var infos: [CachedBookInfo] = []
        var total: Int64 = 0
        
        // 兼容现有逻辑：遍历当前书架中的书籍
        for book in apiService.books {
            if let bookUrl = book.bookUrl {
                let size = LocalCacheManager.shared.getCacheSize(for: bookUrl)
                if size > 0 {
                    let count = LocalCacheManager.shared.getCachedChapterCount(for: bookUrl, totalChapters: book.totalChapterNum ?? 0)
                    infos.append(CachedBookInfo(
                        id: bookUrl,
                        name: book.name ?? "未知书名",
                        author: book.author ?? "未知作者",
                        size: size,
                        chapterCount: count
                    ))
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
        for info in cachedBooks {
            LocalCacheManager.shared.clearCache(for: info.id)
        }
        Task { await loadCachedData() }
    }
    
    private func md5Hex(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashed = Insecure.MD5.hash(data: inputData)
        return hashed.map { String(format: "%02hhx", $0) }.joined()
    }
}

struct StatusBadge: View {
    let status: OfflineDownloadStatus
    
    var body: some View {
        Text(status.rawValue.uppercased())
            .font(.system(size: 8, weight: .bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(backgroundColor.opacity(0.1))
            .foregroundColor(backgroundColor)
            .cornerRadius(4)
    }
    
    var backgroundColor: Color {
        switch status {
        case .downloading: return .blue
        case .paused: return .orange
        case .failed: return .red
        }
    }
}
