import SwiftUI
import UIKit
import CoreText

struct ReadingView: View {
    let book: Book
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var apiService: APIService
    @StateObject private var ttsManager = TTSManager.shared
    @StateObject private var preferences = UserPreferences.shared
    @StateObject private var replaceRuleViewModel = ReplaceRuleViewModel()
    
    @State private var chapters: [BookChapter] = []
    @State private var currentChapterIndex: Int
    @State private var currentContent = ""
    @State private var rawContent = ""
    @State private var contentSentences: [String] = []
    @State private var isLoading = false
    @State private var showChapterList = false
    @State private var errorMessage: String?
    @State private var showUIControls = false
    @State private var scrollProxy: ScrollViewProxy?
    @State private var lastTTSSentenceIndex: Int?
    @State private var showFontSettings = false
    @State private var currentPageIndex: Int = 0
    @State private var paginatedPages: [PaginatedPage] = []
    
    init(book: Book) {
        self.book = book
        _currentChapterIndex = State(initialValue: book.durChapterIndex ?? 0)
        // 从服务器加载的进度初始化
        _lastTTSSentenceIndex = State(initialValue: Int(book.durChapterPos ?? 0))
    }
    
    var body: some View {
        ZStack {
            Color(UIColor.systemBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                if preferences.readingMode == .horizontal && !ttsManager.isPlaying {
                    GeometryReader { geometry in
                        let contentInsets = EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
                        let width = geometry.size.width
                        let tapHandler: (CGFloat) -> Void = { tapX in
                            if showUIControls {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    showUIControls = false
                                }
                            } else if tapX < width / 3 {
                                goToPreviousPage()
                            } else if tapX < width * 2 / 3 {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    showUIControls = true
                                }
                            } else {
                                goToNextPage()
                            }
                        }

                        let tabView = TabView(selection: $currentPageIndex) {
                            ForEach(Array(paginatedPages.enumerated()), id: \.offset) { index, page in
                                Text(page.text)
                                    .font(.system(size: preferences.fontSize))
                                    .lineSpacing(preferences.lineSpacing)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                    .padding(contentInsets)
                                    .tag(index)
                            }
                        }
                        .tabViewStyle(PageTabViewStyle())
                        .onAppear {
                            repaginateContent(in: geometry.size, contentInsets: contentInsets)
                        }
                        .onChange(of: contentSentences) { _ in
                            repaginateContent(in: geometry.size, contentInsets: contentInsets)
                        }
                        .onChange(of: preferences.fontSize) { _ in
                            repaginateContent(in: geometry.size, contentInsets: contentInsets)
                        }
                        .onChange(of: preferences.lineSpacing) { _ in
                            repaginateContent(in: geometry.size, contentInsets: contentInsets)
                        }
                        .onChange(of: currentPageIndex) { newIndex in
                            if paginatedPages.indices.contains(newIndex) {
                                lastTTSSentenceIndex = paginatedPages[newIndex].startSentenceIndex
                            }
                        }

                        if #available(iOS 17.0, *) {
                            let singleTap = SpatialTapGesture(count: 1)
                                .onEnded { value in
                                    tapHandler(value.location.x)
                                }
                            tabView.simultaneousGesture(singleTap)
                        } else {
                            let fallbackTap = TapGesture()
                                .onEnded {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        showUIControls.toggle()
                                    }
                                }
                            tabView.simultaneousGesture(fallbackTap)
                        }
                    }
                } else {
                    // 内容区域
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                if currentChapterIndex < chapters.count {
                                    Text(chapters[currentChapterIndex].title)
                                        .font(.title2)
                                        .fontWeight(.bold)
                                        .padding(.bottom, 8)
                                        .opacity(showUIControls ? 1 : 0)
                                        .accessibilityHidden(!showUIControls)
                                }
                                
                                if !contentSentences.isEmpty && ttsManager.isPlaying {
                                    // TTS播放模式
                                    VStack(alignment: .leading, spacing: preferences.fontSize * 0.8) {
                                        ForEach(Array(contentSentences.enumerated()), id: \.offset) { index, sentence in
                                            Text("　　" + sentence.trimmingCharacters(in: .whitespacesAndNewlines))
                                                .font(.system(size: preferences.fontSize))
                                                .lineSpacing(preferences.lineSpacing)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .fixedSize(horizontal: false, vertical: true)
                                                .padding(.vertical, 6)
                                                .padding(.horizontal, 8)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 4)
                                                        .fill(
                                                            index == ttsManager.currentSentenceIndex
                                                                ? Color.blue.opacity(0.25)
                                                                : (ttsManager.preloadedIndices.contains(index) && index > ttsManager.currentSentenceIndex)
                                                                    ? Color.green.opacity(0.15)
                                                                    : Color.clear
                                                        )
                                                        .animation(.easeInOut(duration: 0.3), value: ttsManager.currentSentenceIndex)
                                                )
                                                .id(index)
                                        }
                                    }
                                } else {
                                    // 普通阅读模式
                                    RichTextView(
                                        sentences: contentSentences,
                                        fontSize: preferences.fontSize,
                                        lineSpacing: preferences.lineSpacing,
                                        highlightIndex: lastTTSSentenceIndex,
                                        scrollProxy: scrollProxy
                                    )
                                }
                            }
                            .padding()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                showUIControls.toggle()
                            }
                        }
                        .onChange(of: ttsManager.currentSentenceIndex) { newIndex in
                            if ttsManager.isPlaying && !contentSentences.isEmpty {
                                withAnimation {
                                    proxy.scrollTo(newIndex, anchor: .center)
                                }
                            }
                        }
                        .onAppear {
                            scrollProxy = proxy
                        }
                    }
                }
                
                if preferences.readingMode != .horizontal {
                    controlBar
                        .opacity(showUIControls ? 1 : 0)
                        .allowsHitTesting(showUIControls)
                        .accessibilityHidden(!showUIControls)
                }
            }
            

            if showUIControls {
                GeometryReader { proxy in
                    VStack {
                        topBar
                            .padding(.top, proxy.safeAreaInsets.top + 6)
                        Spacer()
                    }
                }
                .allowsHitTesting(showUIControls)
                .accessibilityHidden(!showUIControls)
            }
            if isLoading {
                ProgressView("加载中...")
                    .padding()
                    .background(Color(UIColor.systemBackground))
                    .cornerRadius(10)
                    .shadow(radius: 10)
            }
            if preferences.readingMode == .horizontal {
                VStack {
                    Spacer()
                    controlBar
                }
                .opacity(showUIControls ? 1 : 0)
                .allowsHitTesting(showUIControls)
                .accessibilityHidden(!showUIControls)
            }
        }
        .navigationTitle(book.name ?? "阅读")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarHidden(true)
        .sheet(isPresented: $showChapterList) {
            ChapterListView(
                chapters: chapters,
                currentIndex: currentChapterIndex,
                onSelectChapter: { index in
                    currentChapterIndex = index
                    loadChapterContent()
                    showChapterList = false
                }
            )
        }
        .sheet(isPresented: $showFontSettings) {
            FontSizeSheet(fontSize: $preferences.fontSize)
        }
        .task {
            await loadChapters()
            await replaceRuleViewModel.fetchRules()
        }
        .onChange(of: replaceRuleViewModel.rules) { _ in
            updateProcessedContent(from: rawContent)
        }
        .alert("错误", isPresented: .constant(errorMessage != nil)) {
            Button("确定") { errorMessage = nil }
        } message: {
            if let error = errorMessage { Text(error) }
        }
        .onDisappear {
            saveProgress()
        }
        .onChange(of: ttsManager.isPlaying) { isPlaying in
            if !isPlaying {
                showUIControls = true
                if ttsManager.currentSentenceIndex > 0 && ttsManager.currentSentenceIndex <= contentSentences.count {
                    lastTTSSentenceIndex = ttsManager.currentSentenceIndex
                }
            }
        }
    }
    
    // MARK: - 内容处理

    private func updateProcessedContent(from rawText: String) {
        if rawText.isEmpty {
            currentContent = "章节内容为空"
            contentSentences = []
            return
        }
        let processedContent = applyReplaceRules(to: rawText)
        currentContent = processedContent
        contentSentences = splitIntoParagraphs(processedContent)
    }

    private func applyReplaceRules(to content: String) -> String {
        var processedContent = content
        let enabledRules = replaceRuleViewModel.rules.filter { $0.isEnabled == true }
        
        for rule in enabledRules {
            do {
                let regex = try NSRegularExpression(pattern: rule.pattern, options: .caseInsensitive)
                let range = NSRange(location: 0, length: processedContent.utf16.count)
                processedContent = regex.stringByReplacingMatches(in: processedContent, options: [], range: range, withTemplate: rule.replacement)
            } catch {
                LogManager.shared.log("无效的净化规则: '\(rule.pattern)'. 错误: \(error)", category: "错误")
            }
        }
        return processedContent
    }

    private func removeHTMLAndSVG(_ text: String) -> String {
        var result = text
        let svgPattern = "<svg[^>]*>.*?</svg>"
        if let svgRegex = try? NSRegularExpression(pattern: svgPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            result = svgRegex.stringByReplacingMatches(in: result, options: [], range: NSRange(location: 0, length: result.utf16.count), withTemplate: "")
        }
        let imgPattern = "<img[^>]*>"
        if let imgRegex = try? NSRegularExpression(pattern: imgPattern, options: [.caseInsensitive]) {
            result = imgRegex.stringByReplacingMatches(in: result, options: [], range: NSRange(location: 0, length: result.utf16.count), withTemplate: "")
        }
        return result
    }
    
    private func splitIntoParagraphs(_ text: String) -> [String] {
        return text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
    
    // MARK: - 数据加载
    private func loadChapters() async {
        isLoading = true
        do {
            chapters = try await apiService.fetchChapterList(bookUrl: book.bookUrl ?? "", bookSourceUrl: book.origin)
            loadChapterContent()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
    
    private func loadChapterContent() {
        guard currentChapterIndex < chapters.count else { return }
        isLoading = true
        Task {
            do {
                let content = try await apiService.fetchChapterContent(
                    bookUrl: book.bookUrl ?? "",
                    bookSourceUrl: book.origin,
                    index: currentChapterIndex
                )
                
                await MainActor.run {
                    if content.isEmpty {
                        currentContent = "章节内容为空"
                        errorMessage = "章节内容为空"
                        contentSentences = []
                        rawContent = ""
                    } else {
                        let cleanedContent = removeHTMLAndSVG(content)
                        rawContent = cleanedContent
                        updateProcessedContent(from: cleanedContent)
                    }
                    isLoading = false
                    
                    if ttsManager.isPlaying {
                        let currentBookUrl = book.bookUrl ?? ""
                        if ttsManager.bookUrl != currentBookUrl || ttsManager.currentChapterIndex != currentChapterIndex {
                            ttsManager.stop()
                        }
                    }
                    preloadNextChapter()
                }
            } catch {
                await MainActor.run {
                    errorMessage = "获取章节失败: \(error.localizedDescription)"
                    isLoading = false
                }
            }
        }
    }
    
    // MARK: - 章节导航
    private func previousChapter() {
        guard currentChapterIndex > 0 else { return }
        currentChapterIndex -= 1
        loadChapterContent()
        saveProgress()
    }
    
    private func nextChapter() {
        guard currentChapterIndex < chapters.count - 1 else { return }
        currentChapterIndex += 1
        loadChapterContent()
        saveProgress()
    }
    
    // MARK: - TTS 控制
    private func toggleTTS() {
        if ttsManager.isPlaying {
            if ttsManager.isPaused {
                ttsManager.resume()
            } else {
                ttsManager.pause()
            }
        } else {
            startTTS()
        }
    }
    
    private func startTTS() {
        showUIControls = true
        
        // 优先使用最后播放的索引，其次是服务器加载的索引
        let pageStartIndex = paginatedPages.indices.contains(currentPageIndex)
            ? paginatedPages[currentPageIndex].startSentenceIndex
            : nil
        let fallbackIndex = lastTTSSentenceIndex ?? Int(book.durChapterPos ?? 0)
        let startIndex = preferences.readingMode == .horizontal ? (pageStartIndex ?? fallbackIndex) : fallbackIndex
        lastTTSSentenceIndex = startIndex
        
        ttsManager.startReading(
            text: currentContent,
            chapters: chapters,
            currentIndex: currentChapterIndex,
            bookUrl: book.bookUrl ?? "",
            bookSourceUrl: book.origin,
            bookTitle: book.name ?? "未知书名",
            coverUrl: book.displayCoverUrl,
            onChapterChange: { newIndex in
                currentChapterIndex = newIndex
                loadChapterContent()
                saveProgress()
            },
            startAtSentenceIndex: startIndex
        )
    }
    
    // MARK: - 进度与预加载
    private func preloadNextChapter() {
        guard currentChapterIndex < chapters.count - 1 else { return }
        let nextChapterIndex = currentChapterIndex + 1
        Task {
            _ = try? await apiService.fetchChapterContent(
                bookUrl: book.bookUrl ?? "",
                bookSourceUrl: book.origin,
                index: nextChapterIndex
            )
        }
    }
    
    private func saveProgress() {
        guard let bookUrl = book.bookUrl else { return }
        Task {
            do {
                let title = currentChapterIndex < chapters.count ? chapters[currentChapterIndex].title : nil
                let position = ttsManager.isPlaying ? Double(ttsManager.currentSentenceIndex) : Double(lastTTSSentenceIndex ?? 0)
                
                try await apiService.saveBookProgress(
                    bookUrl: bookUrl,
                    index: currentChapterIndex,
                    pos: position,
                    title: title
                )
            } catch {
                print("保存进度失败: \(error)")
            }
        }
    }

    private func repaginateContent(in size: CGSize, contentInsets: EdgeInsets) {
        let contentSize = CGSize(
            width: max(0, size.width - (contentInsets.leading + contentInsets.trailing)),
            height: max(0, size.height - (contentInsets.top + contentInsets.bottom))
        )
        paginatedPages = TextPaginator.paginate(
            contentSentences,
            in: contentSize,
            fontSize: preferences.fontSize,
            lineSpacing: preferences.lineSpacing
        )
        currentPageIndex = 0
    }

    private func goToPreviousPage() {
        if currentPageIndex > 0 {
            withAnimation { currentPageIndex -= 1 }
        } else if currentChapterIndex > 0 {
            previousChapter()
        }
    }

    private func goToNextPage() {
        if currentPageIndex < paginatedPages.count - 1 {
            withAnimation { currentPageIndex += 1 }
        } else if currentChapterIndex < chapters.count - 1 {
            nextChapter()
        }
    }

    @ViewBuilder
    private var controlBar: some View {
        if ttsManager.isPlaying && !contentSentences.isEmpty {
            TTSControlBar(
                ttsManager: ttsManager,
                currentChapterIndex: currentChapterIndex,
                chaptersCount: chapters.count,
                onPreviousChapter: previousChapter,
                onNextChapter: nextChapter,
                onShowChapterList: { showChapterList = true }
            )
        } else {
            NormalControlBar(
                currentChapterIndex: currentChapterIndex,
                chaptersCount: chapters.count,
                onPreviousChapter: previousChapter,
                onNextChapter: nextChapter,
                onShowChapterList: { showChapterList = true },
                onToggleTTS: toggleTTS,
                onShowFontSettings: { showFontSettings = true }
            )
        }
    }

    @ViewBuilder
    private var topBar: some View {
        HStack(spacing: 12) {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.title3)
                    .frame(width: 36, height: 36)
            }
            Spacer()
            Text(book.name ?? "阅读")
                .font(.headline)
                .lineLimit(1)
            Spacer()
            Color.clear
                .frame(width: 36, height: 36)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(UIColor.systemBackground).opacity(0.95))
        .shadow(color: Color.black.opacity(0.1), radius: 4, y: 2)
    }

}


// MARK: - Text Paginator
struct PaginatedPage {
    let text: String
    let startSentenceIndex: Int
}

struct TextPaginator {
    static func paginate(
        _ sentences: [String],
        in size: CGSize,
        fontSize: CGFloat,
        lineSpacing: CGFloat
    ) -> [PaginatedPage] {
        guard !sentences.isEmpty, size.width > 0, size.height > 0 else { return [] }

        let font = UIFont.systemFont(ofSize: fontSize)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = lineSpacing

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraphStyle
        ]

        let paragraphStarts = paragraphStartIndices(sentences: sentences)
        let fullText = fullContent(sentences: sentences)
        let attributedText = NSAttributedString(string: fullText, attributes: attributes)
        let framesetter = CTFramesetterCreateWithAttributedString(attributedText)
        let bounds = CGRect(origin: .zero, size: size)

        var pages: [PaginatedPage] = []
        var location = 0
        while location < attributedText.length {
            let range = CFRange(location: location, length: attributedText.length - location)
            let path = CGPath(rect: bounds, transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, range, path, nil)
            let visibleRange = CTFrameGetVisibleStringRange(frame)
            let length = visibleRange.length
            if length == 0 { break }
            let pageRange = NSRange(location: location, length: length)
            let pageText = (fullText as NSString).substring(with: pageRange)
            let startSentenceIndex = sentenceIndex(for: location, in: paragraphStarts)
            pages.append(PaginatedPage(text: pageText, startSentenceIndex: startSentenceIndex))
            location += length
        }

        return pages
    }

    private static func fullContent(sentences: [String]) -> String {
        sentences
            .map { "    " + $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .joined(separator: "\n\n")
    }

    private static func paragraphStartIndices(sentences: [String]) -> [Int] {
        var starts: [Int] = []
        var currentIndex = 0
        for (idx, sentence) in sentences.enumerated() {
            starts.append(currentIndex)
            let paragraphText = "    " + sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            currentIndex += paragraphText.utf16.count
            if idx < sentences.count - 1 {
                currentIndex += 2
            }
        }
        return starts
    }

    private static func sentenceIndex(for location: Int, in starts: [Int]) -> Int {
        guard let index = starts.lastIndex(where: { $0 <= location }) else {
            return 0
        }
        return index
    }
}

// MARK: - Subviews (ChapterList, RichText, ControlBars)
struct ChapterListView: View {
    let chapters: [BookChapter]
    let currentIndex: Int
    let onSelectChapter: (Int) -> Void
    @Environment(\.dismiss) var dismiss
    @State private var isReversed = false
    
    var displayedChapters: [(offset: Int, element: BookChapter)] {
        let enumerated = Array(chapters.enumerated())
        return isReversed ? Array(enumerated.reversed()) : enumerated
    }
    
    var body: some View {
        NavigationView {
            ScrollViewReader { proxy in
                List {
                    ForEach(displayedChapters, id: \.element.id) { item in
                        Button(action: {
                            onSelectChapter(item.offset)
                            dismiss()
                        }) {
                            HStack {
                                Text(item.element.title)
                                    .foregroundColor(item.offset == currentIndex ? .blue : .primary)
                                    .fontWeight(item.offset == currentIndex ? .semibold : .regular)
                                Spacer()
                                if item.offset == currentIndex {
                                    Image(systemName: "book.fill").foregroundColor(.blue).font(.caption)
                                }
                            }
                        }
                        .id(item.offset)
                        .listRowBackground(item.offset == currentIndex ? Color.blue.opacity(0.1) : Color.clear)
                    }
                }
                .navigationTitle("目录（共\(chapters.count)章）")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(action: {
                            withAnimation { isReversed.toggle() }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                withAnimation { proxy.scrollTo(currentIndex, anchor: .center) }
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: isReversed ? "arrow.up" : "arrow.down")
                                Text(isReversed ? "倒序" : "正序")
                            }
                            .font(.caption)
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("关闭") { dismiss() }
                    }
                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        withAnimation { proxy.scrollTo(currentIndex, anchor: .center) }
                    }
                }
            }
        }
    }
}

struct RichTextView: View {
    let sentences: [String]
    let fontSize: CGFloat
    let lineSpacing: CGFloat
    let highlightIndex: Int?
    let scrollProxy: ScrollViewProxy?
    
    var body: some View {
        VStack(alignment: .leading, spacing: fontSize * 0.8) {
            ForEach(Array(sentences.enumerated()), id: \.offset) { index, sentence in
                Text("　　" + sentence.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.system(size: fontSize))
                    .lineSpacing(lineSpacing)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(index == highlightIndex ? Color.orange.opacity(0.2) : Color.clear)
                            .animation(.easeInOut, value: highlightIndex)
                    )
                    .id(index)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            if let highlightIndex = highlightIndex, let scrollProxy = scrollProxy {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation { scrollProxy.scrollTo(highlightIndex, anchor: .center) }
                }
            }
        }
    }
}

struct TTSControlBar: View {
    @ObservedObject var ttsManager: TTSManager
    let currentChapterIndex: Int
    let chaptersCount: Int
    let onPreviousChapter: () -> Void
    let onNextChapter: () -> Void
    let onShowChapterList: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 20) {
                Button(action: { ttsManager.previousSentence() }) {
                    VStack(spacing: 4) {
                        Image(systemName: "arrow.backward.circle.fill").font(.title)
                        Text("上一段").font(.caption)
                    }
                    .foregroundColor(ttsManager.currentSentenceIndex <= 0 ? .gray : .blue)
                }
                .disabled(ttsManager.currentSentenceIndex <= 0)
                
                Spacer()
                VStack(spacing: 4) {
                    Text("段落进度").font(.caption).foregroundColor(.secondary)
                    Text("\(ttsManager.currentSentenceIndex + 1) / \(ttsManager.totalSentences)")
                        .font(.title2).fontWeight(.semibold)
                }
                Spacer()
                
                Button(action: { ttsManager.nextSentence() }) {
                    VStack(spacing: 4) {
                        Image(systemName: "arrow.forward.circle.fill").font(.title)
                        Text("下一段").font(.caption)
                    }
                    .foregroundColor(ttsManager.currentSentenceIndex >= ttsManager.totalSentences - 1 ? .gray : .blue)
                }
                .disabled(ttsManager.currentSentenceIndex >= ttsManager.totalSentences - 1)
            }
            .padding(.horizontal, 20).padding(.top, 12)
            
            Divider().padding(.horizontal, 20)
            
            HStack(spacing: 25) {
                Button(action: onPreviousChapter) {
                    VStack(spacing: 2) {
                        Image(systemName: "chevron.left").font(.title3)
                        Text("上一章").font(.caption2)
                    }
                }.disabled(currentChapterIndex <= 0)
                
                Button(action: onShowChapterList) {
                    VStack(spacing: 2) {
                        Image(systemName: "list.bullet").font(.title3)
                        Text("目录").font(.caption2)
                    }
                }
                
                Spacer()
                Button(action: {
                    if ttsManager.isPaused { ttsManager.resume() } else { ttsManager.pause() }
                }) {
                    VStack(spacing: 2) {
                        Image(systemName: ttsManager.isPaused ? "play.circle.fill" : "pause.circle.fill")
                            .font(.system(size: 36)).foregroundColor(.blue)
                        Text(ttsManager.isPaused ? "播放" : "暂停").font(.caption2)
                    }
                }
                Spacer()
                
                Button(action: { ttsManager.stop() }) {
                    VStack(spacing: 2) {
                        Image(systemName: "xmark.circle.fill").font(.title3).foregroundColor(.red)
                        Text("退出").font(.caption2).foregroundColor(.red)
                    }
                }
                
                Button(action: onNextChapter) {
                    VStack(spacing: 2) {
                        Image(systemName: "chevron.right").font(.title3)
                        Text("下一章").font(.caption2)
                    }
                }.disabled(currentChapterIndex >= chaptersCount - 1)
            }
            .padding(.horizontal, 20).padding(.bottom, 12)
        }
        .background(Color(UIColor.systemBackground))
        .shadow(color: Color.black.opacity(0.1), radius: 5, y: -2)
    }
}

struct NormalControlBar: View {
    let currentChapterIndex: Int
    let chaptersCount: Int
    let onPreviousChapter: () -> Void
    let onNextChapter: () -> Void
    let onShowChapterList: () -> Void
    let onToggleTTS: () -> Void
    let onShowFontSettings: () -> Void
    
    var body: some View {
        HStack(spacing: 30) {
            Button(action: onPreviousChapter) {
                VStack(spacing: 4) {
                    Image(systemName: "chevron.left").font(.title2)
                    Text("上一章").font(.caption2)
                }
            }.disabled(currentChapterIndex <= 0)
            
            Button(action: onShowChapterList) {
                VStack(spacing: 4) {
                    Image(systemName: "list.bullet").font(.title2)
                    Text("目录").font(.caption2)
                }
            }
            
            Spacer()
            Button(action: onToggleTTS) {
                VStack(spacing: 4) {
                    Image(systemName: "speaker.wave.2.circle.fill")
                        .font(.system(size: 32)).foregroundColor(.blue)
                    Text("听书").font(.caption2).foregroundColor(.blue)
                }
            }
            Spacer()
            
            Button(action: onShowFontSettings) {
                VStack(spacing: 4) {
                    Image(systemName: "textformat.size").font(.title2)
                    Text("字体").font(.caption2)
                }
            }
            
            Button(action: onNextChapter) {
                VStack(spacing: 4) {
                    Image(systemName: "chevron.right").font(.title2)
                    Text("下一章").font(.caption2)
                }
            }.disabled(currentChapterIndex >= chaptersCount - 1)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(Color(UIColor.systemBackground))
        .shadow(color: Color.black.opacity(0.1), radius: 5, y: -2)
    }
}

struct FontSizeSheet: View {
    @Binding var fontSize: CGFloat
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                Text("字体大小")
                    .font(.headline)
                Text(String(format: "%.0f", fontSize))
                    .font(.system(size: 28, weight: .semibold))
                Slider(value: $fontSize, in: 12...30, step: 1)
                Spacer()
            }
            .padding(20)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }
}
