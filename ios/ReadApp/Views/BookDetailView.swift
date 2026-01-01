import SwiftUI

struct BookDetailView: View {
    let book: Book
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var apiService: APIService
    @State private var chapters: [BookChapter] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    // 下载相关状态
    @State private var startChapter: String = "1"
    @State private var endChapter: String = ""
    @State private var isDownloading = false
    @State private var downloadProgress: Double = 0
    @State private var downloadMessage: String = ""
    @State private var cachedChapters: Set<Int> = []
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 头部信息
                headerSection
                
                // 下载控制区
                downloadSection
                
                // 简介区
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
                
                // 目录预览
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("目录").font(.headline)
                        Spacer()
                        Text("共 \(chapters.count) 章").font(.caption).foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                    
                    if isLoading {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }.padding()
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(chapters.prefix(10000)) { chapter in // 限制预览数量防止卡顿
                                chapterRow(chapter)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(book.name ?? "书籍详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(isDownloading ? "停止下载" : "") {
                    isDownloading = false
                }
                .foregroundColor(.red)
            }
        }
        .task {
            await loadData()
        }
        .alert("提示", isPresented: .constant(errorMessage != nil)) {
            Button("确定") { errorMessage = nil }
        } message: {
            if let error = errorMessage { Text(error) }
        }
    }
    
    private var headerSection: some View {
        HStack(alignment: .top, spacing: 16) {
            if let coverUrl = book.displayCoverUrl {
                AsyncImage(url: URL(string: coverUrl)) { image in
                    image.resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.gray.opacity(0.3)
                }
                .frame(width: 100, height: 140)
                .cornerRadius(8)
                .shadow(radius: 4)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text(book.name ?? "未知书名")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text(book.author ?? "未知作者")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Text(book.originName ?? "未知来源")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .foregroundColor(.blue)
                    .cornerRadius(4)
                
                Spacer()
                
                NavigationLink(destination: ReadingView(book: book).environmentObject(apiService)) {
                    Text("开始阅读")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
            }
        }
        .padding(.horizontal)
        .padding(.top)
    }
    
    private var downloadSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("离线缓存").font(.headline)
            
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("开始章节").font(.caption).foregroundColor(.secondary)
                    TextField("1", text: $startChapter)
                        .keyboardType(.numberPad)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("结束章节").font(.caption).foregroundColor(.secondary)
                    TextField("\(chapters.count)", text: $endChapter)
                        .keyboardType(.numberPad)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                
                Button(action: startDownload) {
                    if isDownloading {
                        ProgressView()
                    } else {
                        Text("开始缓存")
                            .fontWeight(.semibold)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(8)
                    }
                }
                .disabled(isDownloading || chapters.isEmpty)
            }
            
            if isDownloading || !downloadMessage.isEmpty {
                VStack(spacing: 4) {
                    ProgressView(value: downloadProgress, total: 1.0)
                    Text(downloadMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
        .padding(.horizontal)
    }
    
    private func chapterRow(_ chapter: BookChapter) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(chapter.title)
                    .font(.subheadline)
                    .lineLimit(1)
                Spacer()
                if cachedChapters.contains(chapter.index) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal)
            
            Divider().padding(.leading)
        }
    }
    
    // MARK: - Logic
    
    private func loadData() async {
        isLoading = true
        do {
            chapters = try await apiService.fetchChapterList(bookUrl: book.bookUrl ?? "", bookSourceUrl: book.origin)
            if endChapter.isEmpty {
                endChapter = "\(chapters.count)"
            }
            refreshCachedStatus()
        } catch {
            errorMessage = error.localizedDescription
        }
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
    
    private func startDownload() {
        guard let start = Int(startChapter), let end = Int(endChapter), start <= end else {
            errorMessage = "请输入有效的章节范围"
            return
        }
        
        let targetRange = chapters.filter { $0.index >= (start - 1) && $0.index <= (end - 1) }
        guard !targetRange.isEmpty else { return }
        
        isDownloading = true
        downloadProgress = 0
        downloadMessage = "准备下载..."
        
        Task {
            var successCount = 0
            for (i, chapter) in targetRange.enumerated() {
                guard isDownloading else { break }
                
                downloadMessage = "正在下载: \(chapter.title) (\(i+1)/\(targetRange.count))"
                downloadProgress = Double(i + 1) / Double(targetRange.count)
                
                do {
                    // APIService 内部会自动处理缓存存储
                    _ = try await apiService.fetchChapterContent(bookUrl: book.bookUrl ?? "", bookSourceUrl: book.origin, index: chapter.index)
                    successCount += 1
                    await MainActor.run {
                        cachedChapters.insert(chapter.index)
                    }
                } catch {
                    print("下载失败: \(chapter.title) - \(error.localizedDescription)")
                }
                
                // 稍微休眠，防止请求过快
                try? await Task.sleep(nanoseconds: 100_000_000) 
            }
            
            isDownloading = false
            downloadMessage = "下载完成，成功 \(successCount) 章"
        }
    }
}
