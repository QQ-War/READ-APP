import SwiftUI
import UIKit

struct BookDetailView: View {
    let book: Book
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var apiService: APIService
    @State private var chapters: [BookChapter] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    // 下载与缓存状态
    @State private var startChapter: String = "1"
    @State private var endChapter: String = ""
    @State private var isDownloading = false
    @State private var showCustomRange = false
    @State private var showingDownloadOptions = false
    @State private var downloadProgress: Double = 0
    @State private var downloadMessage: String = ""
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

    private var groupCount: Int {
        chapterGroups.count
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 1. 头部信息
                headerSection
                
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
                
                // 5. 目录预览
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("目录").font(.headline)
                        Spacer()
                        Text("共 \(chapters.count) 章").font(.caption).foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                    
                    if groupCount > 1 {
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
        }
        .navigationTitle(book.name ?? "书籍详情")
        .navigationBarTitleDisplayMode(.inline)
        .ifAvailableHideTabBar()
        .confirmationDialog("选择缓存范围", isPresented: $showingDownloadOptions, titleVisibility: .visible) {
            Button("缓存全文") { startDownload(start: 1, end: chapters.count) }
            Button("缓存后续 50 章") { 
                let current = (book.durChapterIndex ?? 0) + 1
                startDownload(start: current, end: min(current + 50, chapters.count)) 
            }
            Button("自定义范围") { withAnimation { showCustomRange = true } }
            Button("取消", role: .cancel) { }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if isDownloading {
                    Button("停止", role: .destructive) { isDownloading = false }
                }
            }
        }
        .task { await loadData() }
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
        .alert("已加入书架", isPresented: $showingAddSuccessAlert) {
            Button("确定", role: .cancel) { }
        }
        .alert("已从书架移除", isPresented: $showingRemoveSuccessAlert) {
            Button("确定", role: .cancel) { }
        }
        .sheet(isPresented: $showingSourceSwitch) {
            SourceSwitchView(bookName: book.name ?? "", currentSource: book.origin ?? "") { newBook in
                updateBookSource(with: newBook)
            }
        }
    }
    
    // MARK: - Subviews
    
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
                .fullScreenCover(isPresented: $isReading) {
                    ReadingView(book: book).environmentObject(apiService)
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
                if !isDownloading {
                    Button(action: { showingDownloadOptions = true }) {
                        HStack {
                            Image(systemName: "arrow.down.circle")
                            Text("选择范围")
                        }
                        .padding(.horizontal, 12).padding(.vertical, 6).background(Color.blue.opacity(0.1)).cornerRadius(16)
                    }
                }
            }
            
            if showCustomRange && !isDownloading {
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
            
            if isDownloading || !downloadMessage.isEmpty {
                VStack(spacing: 8) {
                    ProgressView(value: downloadProgress, total: 1.0).tint(.blue)
                    Text(downloadMessage).font(.caption).foregroundColor(.secondary)
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
            // 自动跳转到当前章节所在的分组
            let initialIndex = book.durChapterIndex ?? 0
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
    
    private func updateBookSource(with newBook: Book) {
        Task {
            do {
                try await apiService.saveBook(book: newBook)
                await loadData()
            } catch { errorMessage = "换源失败: \(error.localizedDescription)" }
        }
    }
    
    private func addToBookshelf() {
        Task {
            do {
                try await apiService.saveBook(book: book)
                try await apiService.fetchBookshelf() // Refresh list
                await MainActor.run {
                    showingAddSuccessAlert = true
                }
            } catch {
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
                try await apiService.deleteBook(bookUrl: bookUrl)
                try await apiService.fetchBookshelf() // Refresh list
                await MainActor.run {
                    showingRemoveSuccessAlert = true
                }
            } catch {
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
        let targetRange = chapters.filter { $0.index >= (start - 1) && $0.index <= (end - 1) }
        guard !targetRange.isEmpty else { return }
        isDownloading = true; downloadProgress = 0; downloadMessage = "准备下载..."
        Task {
            var successCount = 0
            for (i, chapter) in targetRange.enumerated() {
                guard isDownloading else { break }
                await MainActor.run {
                    downloadMessage = "正在下载: \(chapter.title) (\(i+1)/\(targetRange.count))"
                    downloadProgress = Double(i + 1) / Double(targetRange.count)
                }
                do {
                    _ = try await apiService.fetchChapterContent(bookUrl: book.bookUrl ?? "", bookSourceUrl: book.origin, index: chapter.index)
                    successCount += 1
                    await MainActor.run { _ = self.cachedChapters.insert(chapter.index) }
                } catch { print("下载失败: \(chapter.title) - \(error.localizedDescription)") }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            await MainActor.run {
                isDownloading = false
                downloadMessage = successCount == targetRange.count ? "下载完成！" : "下载结束，成功 \(successCount)/\(targetRange.count) 章"
            }
        }
    }
}

// MARK: - Source Switch View
struct SourceSwitchView: View {
    let bookName: String
    let currentSource: String
    let onSelect: (Book) -> Void
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var apiService: APIService
    @State private var searchResults: [Book] = []
    @State private var isSearching = false
    
    var body: some View {
        NavigationView {
            List {
                if isSearching {
                    HStack { Spacer(); ProgressView("正在全网搜索来源..."); Spacer() }
                } else if searchResults.isEmpty {
                    Text("未找到其他可用来源").foregroundColor(.secondary)
                } else {
                    ForEach(searchResults) { book in
                        Button(action: { onSelect(book); dismiss() }) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(book.originName ?? "未知源").font(.headline)
                                    Spacer()
                                    if book.origin == currentSource { Text("当前源").font(.caption).foregroundColor(.blue) }
                                }
                                Text(book.author ?? "未知作者").font(.subheadline).foregroundColor(.secondary)
                                if let latest = book.latestChapterTitle { Text("最新: \(latest)").font(.caption2).foregroundColor(.gray) }
                            }
                        }
                    }
                }
            }
            .navigationTitle("更换来源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("关闭") { dismiss() } } }
            .task { await performSearch() }
        }
    }
    
    private func performSearch() async {
        isSearching = true
        let sources = (try? await apiService.fetchBookSources()) ?? []
        let enabledSources = sources.filter { $0.enabled }
        await withTaskGroup(of: [Book]?.self) { group in
            for source in enabledSources { group.addTask { try? await apiService.searchBook(keyword: bookName, bookSourceUrl: source.bookSourceUrl) } }
            for await result in group {
                if let books = result {
                    await MainActor.run { self.searchResults.append(contentsOf: books) }
                }
            }
        }
        isSearching = false
    }
}
