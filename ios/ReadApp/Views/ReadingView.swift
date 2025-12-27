import SwiftUI
import UIKit

// MARK: - ReadingView
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
    @State private var currentVisibleSentenceIndex: Int?
    @State private var showFontSettings = false
    
    // Pagination State
    @State private var currentPageIndex: Int = 0
    @State private var paginatedPages: [PaginatedPage] = []
    @State private var attributedContent: NSAttributedString?
    @State private var pendingJumpToLastPage = false

    // Unified Insets for consistency
    private let horizontalPadding: CGFloat = 20
    private let verticalPadding: CGFloat = 40

    init(book: Book) {
        self.book = book
        _currentChapterIndex = State(initialValue: book.durChapterIndex ?? 0)
        _lastTTSSentenceIndex = State(initialValue: Int(book.durChapterPos ?? 0))
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                backgroundView
                mainContent(safeArea: proxy.safeAreaInsets)
                
                if showUIControls {
                    topBar(safeArea: proxy.safeAreaInsets)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    
                    bottomBar(safeArea: proxy.safeAreaInsets)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                
                if isLoading { loadingOverlay }
            }
            .animation(.easeInOut(duration: 0.2), value: showUIControls)
            .ignoresSafeArea()
            .navigationBarHidden(true)
            .navigationBarBackButtonHidden(true)
        }
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
        .onChange(of: ttsManager.currentSentenceIndex) { newIndex in
            if preferences.readingMode == .horizontal && ttsManager.isPlaying {
                syncPageForSentenceIndex(newIndex)
            }
        }
    }

    private var backgroundView: some View {
        Color(UIColor.systemBackground)
    }

    @ViewBuilder
    private func mainContent(safeArea: EdgeInsets) -> some View {
        if preferences.readingMode == .horizontal {
            horizontalReader
        } else {
            verticalReader
                .padding(.top, safeArea.top)
                .padding(.bottom, safeArea.bottom)
        }
    }
    
    private var verticalReader: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    let primaryHighlight = ttsManager.isPlaying ? ttsManager.currentSentenceIndex : lastTTSSentenceIndex
                    let secondaryHighlights = ttsManager.isPlaying ? ttsManager.preloadedIndices : Set<Int>()
                    RichTextView(
                        sentences: contentSentences,
                        fontSize: preferences.fontSize,
                        lineSpacing: preferences.lineSpacing,
                        highlightIndex: primaryHighlight,
                        secondaryIndices: secondaryHighlights,
                        isPlayingHighlight: ttsManager.isPlaying,
                        scrollProxy: scrollProxy
                    )
                    .padding()
                }
                .coordinateSpace(name: "scroll")
                .contentShape(Rectangle())
                .onTapGesture {
                    showUIControls.toggle()
                }
                .onChange(of: ttsManager.currentSentenceIndex) { newIndex in
                    if ttsManager.isPlaying && !contentSentences.isEmpty {
                        withAnimation {
                            proxy.scrollTo(newIndex, anchor: .center)
                        }
                    }
                }
                .onPreferenceChange(SentenceFramePreferenceKey.self) { frames in
                    updateVisibleSentenceIndex(frames: frames, viewportHeight: geometry.size.height)
                }
                .onAppear {
                    scrollProxy = proxy
                }
            }
        }
    }
    
    private var horizontalReader: some View {
        GeometryReader { geometry in
            // Calculate content area size, leaving space for status bar and bottom operation area
            let contentSize = CGSize(
                width: max(0, geometry.size.width - horizontalPadding * 2),
                height: max(0, geometry.size.height - verticalPadding * 2)
            )
            
            // ReadPageViewController is now placed directly within a frame matching contentSize
            ReadPageViewController(
                pages: paginatedPages,
                attributedContent: attributedContent,
                currentPageIndex: $currentPageIndex,
                onTapMiddle: { showUIControls.toggle() },
                onTapLeft: { goToPreviousPage() },
                onTapRight: { goToNextPage() },
                onSwipeToPreviousChapter: { 
                    if currentChapterIndex > 0 {
                        pendingJumpToLastPage = true
                        previousChapter()
                    }
                },
                onSwipeToNextChapter: {
                    if currentChapterIndex < chapters.count - 1 {
                        nextChapter()
                    }
                }
            )
            .frame(width: contentSize.width, height: contentSize.height)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2) // Center the content area
            .onAppear {
                repaginateContent(in: contentSize)
            }
            .onChange(of: contentSentences) { _ in
                repaginateContent(in: contentSize)
            }
            .onChange(of: preferences.fontSize) { _ in
                repaginateContent(in: contentSize)
            }
            .onChange(of: preferences.lineSpacing) { _ in
                repaginateContent(in: contentSize)
            }
            .onChange(of: currentPageIndex) { newIndex in
                if paginatedPages.indices.contains(newIndex) {
                    lastTTSSentenceIndex = paginatedPages[newIndex].startSentenceIndex
                }
            }
        }
    }

    // MARK: - Pagination & Navigation

    private func repaginateContent(in size: CGSize) {
        let chapterTitle = chapters.indices.contains(currentChapterIndex)
            ? chapters[currentChapterIndex].title
            : nil
            
        let result = TextKitPaginator.paginate(
            sentences: contentSentences,
            in: size,
            fontSize: preferences.fontSize,
            lineSpacing: preferences.lineSpacing,
            chapterTitle: chapterTitle
        )
        
        self.attributedContent = result.attributedText
        self.paginatedPages = result.pages
        
        if pendingJumpToLastPage {
            currentPageIndex = max(paginatedPages.count - 1, 0)
            pendingJumpToLastPage = false
        } else {
            // Keep position if possible (e.g. after font resize)
            if let lastIndex = lastTTSSentenceIndex, let page = pageIndexForSentence(lastIndex) {
                currentPageIndex = page
            } else {
                currentPageIndex = 0
            }
        }
    }
    
    private func goToPreviousPage() {
        if currentPageIndex > 0 {
            currentPageIndex -= 1
        } else if currentChapterIndex > 0 {
            pendingJumpToLastPage = true
            previousChapter()
        }
    }

    private func goToNextPage() {
        if currentPageIndex < paginatedPages.count - 1 {
            currentPageIndex += 1
        } else if currentChapterIndex < chapters.count - 1 {
            nextChapter()
        }
    }

    private func pageIndexForSentence(_ index: Int) -> Int? {
        guard !paginatedPages.isEmpty else { return nil }
        for i in 0..<paginatedPages.count {
            let startIndex = paginatedPages[i].startSentenceIndex
            let nextStart = (i + 1 < paginatedPages.count)
                ? paginatedPages[i + 1].startSentenceIndex
                : Int.max
            if index >= startIndex && index < nextStart {
                return i
            }
        }
        return nil
    }

    private func syncPageForSentenceIndex(_ index: Int) {
        guard index >= 0, preferences.readingMode == .horizontal else { return }
        if let pageIndex = pageIndexForSentence(index), pageIndex != currentPageIndex {
            withAnimation { currentPageIndex = pageIndex }
        }
    }

    // MARK: - Logic & Actions (Loading, Saving, etc.)
    
    private func updateProcessedContent(from rawText: String) {
        let processedContent = applyReplaceRules(to: rawText)
        currentContent = processedContent.isEmpty ? "章节内容为空" : processedContent
        contentSentences = splitIntoParagraphs(currentContent)
    }

    private func applyReplaceRules(to content: String) -> String {
        var processedContent = content
        let enabledRules = replaceRuleViewModel.rules.filter { $0.isEnabled == true }
        for rule in enabledRules {
            if let regex = try? NSRegularExpression(pattern: rule.pattern, options: .caseInsensitive) {
                let range = NSRange(location: 0, length: processedContent.utf16.count)
                processedContent = regex.stringByReplacingMatches(in: processedContent, options: [], range: range, withTemplate: rule.replacement)
            }
        }
        return processedContent
    }

    private func removeHTMLAndSVG(_ text: String) -> String {
        var result = text
        let svgPattern = "<svg[^>]*>.*?<\/svg>"
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
                let content = try await apiService.fetchChapterContent(bookUrl: book.bookUrl ?? "", bookSourceUrl: book.origin, index: currentChapterIndex)
                await MainActor.run {
                    let cleanedContent = removeHTMLAndSVG(content)
                    rawContent = cleanedContent
                    updateProcessedContent(from: cleanedContent)
                    isLoading = false
                    if ttsManager.isPlaying {
                        if ttsManager.bookUrl != book.bookUrl || ttsManager.currentChapterIndex != currentChapterIndex {
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
    
    private func toggleTTS() {
        if ttsManager.isPlaying {
            if ttsManager.isPaused { ttsManager.resume() } else { ttsManager.pause() }
        } else {
            startTTS()
        }
    }
    
    private func startTTS() {
        showUIControls = true
        let fallbackIndex = lastTTSSentenceIndex ?? Int(book.durChapterPos ?? 0)
        let startIndex = preferences.readingMode == .horizontal
            ? (paginatedPages.indices.contains(currentPageIndex) ? paginatedPages[currentPageIndex].startSentenceIndex : fallbackIndex)
            : (currentVisibleSentenceIndex ?? fallbackIndex)
        let textForTTS = contentSentences.isEmpty
            ? currentContent
            : contentSentences.joined(separator: "\n")
        let trimmedText = textForTTS.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        let maxIndex = max(contentSentences.count - 1, 0)
        let boundedStartIndex = max(0, min(startIndex, maxIndex))
        lastTTSSentenceIndex = boundedStartIndex

        ttsManager.startReading(
            text: textForTTS,
            chapters: chapters,
            currentIndex: currentChapterIndex,
            bookUrl: book.bookUrl ?? "",
            bookSourceUrl: book.origin,
            bookTitle: book.name ?? "\u{9605}\u{8BFB}",
            coverUrl: book.displayCoverUrl,
            onChapterChange: { newIndex in
                currentChapterIndex = newIndex
                loadChapterContent()
                saveProgress()
            },
            startAtSentenceIndex: boundedStartIndex
        )
    }
    
    private func preloadNextChapter() {
        guard currentChapterIndex < chapters.count - 1 else { return }
        Task { _ = try? await apiService.fetchChapterContent(bookUrl: book.bookUrl ?? "", bookSourceUrl: book.origin, index: currentChapterIndex + 1) }
    }
    
    private func saveProgress() {
        guard let bookUrl = book.bookUrl else { return }
        Task {
            let title = currentChapterIndex < chapters.count ? chapters[currentChapterIndex].title : nil
            let position = Double(ttsManager.isPlaying ? ttsManager.currentSentenceIndex : (lastTTSSentenceIndex ?? 0))
            try? await apiService.saveBookProgress(bookUrl: bookUrl, index: currentChapterIndex, pos: position, title: title)
        }
    }

    private func updateVisibleSentenceIndex(frames: [Int: CGRect], viewportHeight: CGFloat) {
        let visible = frames.filter { $0.value.maxY > 0 && $0.value.minY < viewportHeight }
        if let first = visible.min(by: { $0.value.minY < $1.value.minY }) {
            if first.key != currentVisibleSentenceIndex { currentVisibleSentenceIndex = first.key }
        }
    }

    // MARK: - UI Components
    @ViewBuilder private func topBar(safeArea: EdgeInsets) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: { dismiss() }) { Image(systemName: "chevron.left").font(.title3).frame(width: 44, height: 44) }
                VStack(alignment: .leading, spacing: 2) {
                     Text(book.name ?? "阅读").font(.headline).fontWeight(.bold).lineLimit(1)
                     Text(chapters.indices.contains(currentChapterIndex) ? chapters[currentChapterIndex].title : "加载中...").font(.caption).foregroundColor(.secondary).lineLimit(1)
                }
                Spacer()
                Color.clear.frame(width: 44, height: 44)
            }
            .padding(.top, safeArea.top).padding(.horizontal, 12).padding(.bottom, 8).background(.thinMaterial)
            Spacer()
        }
    }
    
    @ViewBuilder private func bottomBar(safeArea: EdgeInsets) -> some View {
        VStack(spacing: 0) {
            Spacer()
            controlBar.padding(.bottom, safeArea.bottom).background(.thinMaterial)
        }
    }
    
    private var loadingOverlay: some View {
        ProgressView("加载中...").padding().background(Color(UIColor.systemBackground).opacity(0.8)).cornerRadius(10).shadow(radius: 10)
    }

    @ViewBuilder private var controlBar: some View {
        if ttsManager.isPlaying && !contentSentences.isEmpty {
            TTSControlBar(ttsManager: ttsManager, currentChapterIndex: currentChapterIndex, chaptersCount: chapters.count, onPreviousChapter: previousChapter, onNextChapter: nextChapter, onShowChapterList: { showChapterList = true })
        } else {
            NormalControlBar(currentChapterIndex: currentChapterIndex, chaptersCount: chapters.count, onPreviousChapter: previousChapter, onNextChapter: nextChapter, onShowChapterList: { showChapterList = true }, onToggleTTS: toggleTTS, onShowFontSettings: { showFontSettings = true })
        }
    }
}

// MARK: - UIPageViewController Wrapper
struct ReadPageViewController: UIViewControllerRepresentable {
    var pages: [PaginatedPage]
    var attributedContent: NSAttributedString?
    @Binding var currentPageIndex: Int
    var onTapMiddle: () -> Void
    var onTapLeft: () -> Void
    var onTapRight: () -> Void
    var onSwipeToPreviousChapter: () -> Void
    var onSwipeToNextChapter: () -> Void

    func makeUIViewController(context: Context) -> UIPageViewController {
        let pvc = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal, options: nil)
        pvc.dataSource = context.coordinator
        pvc.delegate = context.coordinator
        
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        pvc.view.addGestureRecognizer(tap)
        
        // Listen to standard PanGesture to detect edge swipes for chapter changes
        context.coordinator.setupPanGesture(on: pvc.view)
        
        return pvc
    }

    func updateUIViewController(_ pvc: UIPageViewController, context: Context) {
        context.coordinator.parent = self
        guard !pages.isEmpty, let content = attributedContent, currentPageIndex < pages.count else { return }
        
        if let currentVC = pvc.viewControllers?.first as? ReadContentViewController, currentVC.pageIndex == currentPageIndex { return }
        
        let vc = ReadContentViewController(pageIndex: currentPageIndex, range: pages[currentPageIndex].range, attributedText: content)
        pvc.setViewControllers([vc], direction: .forward, animated: false)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: ReadPageViewController
        private var isEdgeSwiping = false

        init(_ parent: ReadPageViewController) { self.parent = parent }
        
        func setupPanGesture(on view: UIView) {
            // Find the built-in pan gesture to coordinate
            if let pan = view.gestureRecognizers?.first(where: { $0 is UIPanGestureRecognizer }) as? UIPanGestureRecognizer {
                pan.addTarget(self, action: #selector(handlePan(_:)))
            }
        }

        func pageViewController(_ pvc: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
            guard let vc = viewController as? ReadContentViewController else { return nil }
            let index = vc.pageIndex
            guard index > 0 else { return nil } // No previous page in this chapter
            
            let prevIndex = index - 1
            return ReadContentViewController(pageIndex: prevIndex, range: parent.pages[prevIndex].range, attributedText: parent.attributedContent!)
        }

        func pageViewController(_ pvc: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
            guard let vc = viewController as? ReadContentViewController else { return nil }
            let index = vc.pageIndex
            guard index < parent.pages.count - 1 else { return nil } // No next page in this chapter
            
            let nextIndex = index + 1
            return ReadContentViewController(pageIndex: nextIndex, range: parent.pages[nextIndex].range, attributedText: parent.attributedContent!)
        }
        
        func pageViewController(_ pvc: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
            if completed, let visibleVC = pvc.viewControllers?.first as? ReadContentViewController {
                parent.currentPageIndex = visibleVC.pageIndex
            }
        }
        
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            let x = gesture.location(in: gesture.view).x
            let w = gesture.view?.bounds.width ?? 0
            if x < w / 3 { parent.onTapLeft() } else if x > w * 2 / 3 { parent.onTapRight() } else { parent.onTapMiddle() }
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard gesture.state == .ended else { return }
            let translation = gesture.translation(in: gesture.view)
            let velocity = gesture.velocity(in: gesture.view)
            
            // Detect strong swipe at edges
            if parent.currentPageIndex == 0 && (translation.x > 100 || velocity.x > 500) {
                parent.onSwipeToPreviousChapter()
            } else if parent.currentPageIndex == parent.pages.count - 1 && (translation.x < -100 || velocity.x < -500) {
                parent.onSwipeToNextChapter()
            }
        }
    }
}

// MARK: - Content View Controller
class ReadContentViewController: UIViewController {
    let pageIndex: Int
    let range: NSRange
    let attributedText: NSAttributedString
    
    private lazy var textView: UITextView = {
        let tv = UITextView()
        tv.isEditable = false; tv.isScrollEnabled = false; tv.isSelectable = false
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.backgroundColor = .clear
        tv.translatesAutoresizingMaskIntoConstraints = false
        return tv
    }()
    
    init(pageIndex: Int, range: NSRange, attributedText: NSAttributedString) {
        self.pageIndex = pageIndex; self.range = range; self.attributedText = attributedText
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.addSubview(textView)
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.topAnchor),
            textView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor), // No extra padding here
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        if range.location + range.length <= attributedText.length {
            textView.attributedText = attributedText.attributedSubstring(from: range)
        }
    }
}

// MARK: - TextKit Paginator
struct PaginatedPage { let range: NSRange; let startSentenceIndex: Int }
struct PaginationResult { let pages: [PaginatedPage]; let attributedText: NSAttributedString }

struct TextKitPaginator {
    static func paginate(sentences: [String], in size: CGSize, fontSize: CGFloat, lineSpacing: CGFloat, chapterTitle: String?) -> PaginationResult {
        guard !sentences.isEmpty, size.width > 0, size.height > 0 else { return PaginationResult(pages: [], attributedText: NSAttributedString()) }
        
        let fullAttributedText = createAttributedText(sentences: sentences, fontSize: fontSize, lineSpacing: lineSpacing, chapterTitle: chapterTitle)
        let textStorage = NSTextStorage(attributedString: fullAttributedText)
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        
        var pages: [PaginatedPage] = []
        var rangeOffset = 0
        let fullLength = textStorage.length
        let paragraphStarts = paragraphStartIndices(sentences: sentences)
        let prefixLen = (chapterTitle?.isEmpty ?? true) ? 0 : (chapterTitle! + "\n").utf16.count
        
        while rangeOffset < fullLength {
            let textContainer = NSTextContainer(size: size)
            textContainer.lineFragmentPadding = 0
            layoutManager.addTextContainer(textContainer)
            
            let glyphRange = layoutManager.glyphRange(for: textContainer)
            let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            
            if charRange.length == 0 { break }
            
            let adjustedLocation = max(0, charRange.location - prefixLen)
            let startIdx = paragraphStarts.lastIndex(where: { $0 <= adjustedLocation }) ?? 0
            pages.append(PaginatedPage(range: charRange, startSentenceIndex: startIdx))
            rangeOffset = NSMaxRange(charRange)
        }
        return PaginationResult(pages: pages, attributedText: fullAttributedText)
    }
    
    static func createAttributedText(sentences: [String], fontSize: CGFloat, lineSpacing: CGFloat, chapterTitle: String?) -> NSAttributedString {
        let font = UIFont.systemFont(ofSize: fontSize)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = lineSpacing
        paragraphStyle.paragraphSpacing = fontSize * 0.5
        paragraphStyle.alignment = .justified
        
        let result = NSMutableAttributedString()
        if let title = chapterTitle, !title.isEmpty {
            let titleStyle = NSMutableParagraphStyle()
            titleStyle.alignment = .center; titleStyle.paragraphSpacing = fontSize * 2
            result.append(NSAttributedString(string: title + "\n", attributes: [.font: UIFont.boldSystemFont(ofSize: fontSize + 6), .paragraphStyle: titleStyle, .foregroundColor: UIColor.label]))
        }
        
        let body = sentences.map { "　　" + s.trimmingCharacters(in: .whitespacesAndNewlines) }.joined(separator: "\n")
        result.append(NSAttributedString(string: body, attributes: [.font: font, .paragraphStyle: paragraphStyle, .foregroundColor: UIColor.label]))
        return result
    }
    
    private static func paragraphStartIndices(sentences: [String]) -> [Int] {
        var starts: [Int] = []; var current = 0
        for (idx, s) in sentences.enumerated() {
            starts.append(current)
            current += ("　　" + s.trimmingCharacters(in: .whitespacesAndNewlines)).utf16.count + (idx < sentences.count - 1 ? 1 : 0)
        }
        return starts
    }
}

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
                    ForEach(displayedChapters, id: \.element.id) {
                        item in
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
    let secondaryIndices: Set<Int>
    let isPlayingHighlight: Bool
    let scrollProxy: ScrollViewProxy?
    
    var body: some View {
        VStack(alignment: .leading, spacing: fontSize * 0.8) {
            ForEach(Array(sentences.enumerated()), id: \.offset) {
                index, sentence in
                Text("　　" + sentence.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.system(size: fontSize))
                    .lineSpacing(lineSpacing)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: SentenceFramePreferenceKey.self,
                                value: [index: proxy.frame(in: .named("scroll"))]
                            )
                        }
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(highlightColor(for: index))
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

    private func highlightColor(for index: Int) -> Color {
        if isPlayingHighlight {
            if index == highlightIndex {
                return Color.blue.opacity(0.2)
            }
            if secondaryIndices.contains(index) {
                return Color.green.opacity(0.18)
            }
            return .clear
        }
        return index == highlightIndex ? Color.orange.opacity(0.2) : .clear
    }
}


private struct SentenceFramePreferenceKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
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
                        Text("\u{4E0A}\u{4E00}\u{6BB5}").font(.caption)
                    }
                    .foregroundColor(ttsManager.currentSentenceIndex <= 0 ? .gray : .blue)
                }
                .disabled(ttsManager.currentSentenceIndex <= 0)
                
                Spacer()
                VStack(spacing: 4) {
                    Text("\u{6BB5}\u{843D}\u{8FDB}\u{5EA6}").font(.caption).foregroundColor(.secondary)
                    Text("\(ttsManager.currentSentenceIndex + 1) / \(ttsManager.totalSentences)")
                        .font(.title2).fontWeight(.semibold)
                }
                Spacer()
                
                Button(action: { ttsManager.nextSentence() }) {
                    VStack(spacing: 4) {
                        Image(systemName: "arrow.forward.circle.fill").font(.title)
                        Text("\u{4E0B}\u{4E00}\u{6BB5}").font(.caption)
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
                        Text("\u{4E0A}\u{4E00}\u{7AE0}").font(.caption2)
                    }
                }.disabled(currentChapterIndex <= 0)
                
                Button(action: onShowChapterList) {
                    VStack(spacing: 2) {
                        Image(systemName: "list.bullet").font(.title3)
                        Text("\u{76EE}\u{5F55}").font(.caption2)
                    }
                }
                
                Spacer()
                Button(action: {
                    if ttsManager.isPaused { ttsManager.resume() } else { ttsManager.pause() }
                }) {
                    VStack(spacing: 2) {
                        Image(systemName: ttsManager.isPaused ? "play.circle.fill" : "pause.circle.fill")
                            .font(.system(size: 36)).foregroundColor(.blue)
                        Text(ttsManager.isPaused ? "\u{64AD}\u{653E}" : "\u{6682}\u{505C}").font(.caption2)
                    }
                }
                Spacer()
                
                Button(action: { ttsManager.stop() }) {
                    VStack(spacing: 2) {
                        Image(systemName: "xmark.circle.fill").font(.title3).foregroundColor(.red)
                        Text("\u{9000}\u{51FA}").font(.caption2).foregroundColor(.red)
                    }
                }
                
                Button(action: onNextChapter) {
                    VStack(spacing: 2) {
                        Image(systemName: "chevron.right").font(.title3)
                        Text("\u{4E0B}\u{4E00}\u{7AE0}").font(.caption2)
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
                    Text("\u{4E0A}\u{4E00}\u{7AE0}").font(.caption2)
                }
            }.disabled(currentChapterIndex <= 0)
            
            Button(action: onShowChapterList) {
                VStack(spacing: 4) {
                    Image(systemName: "list.bullet").font(.title2)
                    Text("\u{76EE}\u{5F55}").font(.caption2)
                }
            }
            
            Spacer()
            Button(action: onToggleTTS) {
                VStack(spacing: 4) {
                    Image(systemName: "speaker.wave.2.circle.fill")
                        .font(.system(size: 32)).foregroundColor(.blue)
                    Text("\u{542C}\u{4E66}").font(.caption2).foregroundColor(.blue)
                }
            }
            Spacer()
            
            Button(action: onShowFontSettings) {
                VStack(spacing: 4) {
                    Image(systemName: "textformat.size").font(.title2)
                    Text("\u{5B57}\u{4F53}").font(.caption2)
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
                Text("\u{5B57}\u{4F53}\u{5927}\u{5C0F}")
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
                    Button("\u{5B8C}\u{6210}") { 
                        dismiss() 
                    }
                }
            }
        }
    }
}