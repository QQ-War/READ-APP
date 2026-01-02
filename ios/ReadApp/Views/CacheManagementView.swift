import SwiftUI

struct CacheManagementView: View {
    @EnvironmentObject var apiService: APIService
    @State private var cachedBooks: [CachedBookInfo] = []
    @State private var isLoading = false
    @State private var totalSize: Int64 = 0
    
    struct CachedBookInfo: Identifiable {
        let id: String // bookUrl or hash
        let name: String
        let author: String
        let size: Int64
        let chapterCount: Int
    }
    
    var body: some View {
        List {
            Section(header: Text("总体统计")) {
                HStack {
                    Text("总占用空间")
                    Spacer()
                    Text(LocalCacheManager.shared.formatSize(totalSize))
                        .fontWeight(.bold)
                }
                
                Button(role: .destructive, action: clearAllCache) {
                    Text("清除所有缓存")
                }
                .disabled(cachedBooks.isEmpty)
            }
            
            Section(header: Text("书籍详情")) {
                if isLoading {
                    ProgressView()
                } else if cachedBooks.isEmpty {
                    Text("暂无离线缓存").foregroundColor(.secondary)
                } else {
                    ForEach(cachedBooks) { info in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(info.name).font(.headline)
                                Text("\(info.author) • \(info.chapterCount) 章已下载")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            Text(LocalCacheManager.shared.formatSize(info.size))
                                .font(.subheadline).foregroundColor(.gray)
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
        .navigationTitle("离线缓存管理")
        .task {
            await loadCachedData()
        }
    }
    
    private func loadCachedData() async {
        isLoading = true
        var infos: [CachedBookInfo] = []
        var total: Int64 = 0
        
        // 遍历当前书架中的书籍
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
        
        // TODO: 这里还可以增加检查磁盘上存在但不在书架上的残留文件夹逻辑
        
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
}
