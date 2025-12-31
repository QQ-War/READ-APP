import SwiftUI
import UIKit

// MARK: - Chapter Cache
private struct ChapterCache {
    let pages: [PaginatedPage]
    let store: TextKitRenderStore?
    let contentSentences: [String]
    let attributedText: NSAttributedString
    let paragraphStarts: [Int]
    let chapterPrefixLen: Int
    let isFullyPaginated: Bool
    
    static var empty: ChapterCache {
        ChapterCache(pages: [], store: nil, contentSentences: [], attributedText: NSAttributedString(), paragraphStarts: [], chapterPrefixLen: 0, isFullyPaginated: false)
    }
}

final class ReadContentViewControllerCache: ObservableObject {
    struct Key: Hashable {
        let storeID: ObjectIdentifier
        let pageIndex: Int
        let chapterOffset: Int
    }

    private var controllers: [Key: ReadContentViewController] = [:]

    func controller(
        for store: TextKitRenderStore,
        pageIndex: Int,
        chapterOffset: Int,
        builder: () -> ReadContentViewController
    ) -> ReadContentViewController {
        let key = Key(storeID: ObjectIdentifier(store), pageIndex: pageIndex, chapterOffset: chapterOffset)
        if let cached = controllers[key], cached.renderStore === store {
            return cached
        }
        let controller = builder()
        controllers[key] = controller
        return controller
    }

    func retainActive(stores: [TextKitRenderStore?]) {
        let activeIDs = Set(stores.compactMap { $0.map { ObjectIdentifier($0) } })
        if activeIDs.isEmpty {
            controllers.removeAll()
            return
        }
        controllers = controllers.filter { activeIDs.contains($0.key.storeID) }
    }
}

// MARK: - ReadingView
enum ReaderTapLocation {
    case left
    case right
    case middle
}

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
    @State private var pendingResumePos: Double?
    @State private var pendingResumeCharIndex: Int?
    @State private var pendingScrollToSentenceIndex: Int?
    @State private var didApplyResumePos = false
    @State private var showAddReplaceRule = false
    @State private var pendingReplaceRule: ReplaceRule?
    @State private var pendingResumeLocalBodyIndex: Int?
    @State private var pendingResumeLocalChapterIndex: Int?
    @State private var pendingResumeLocalPageIndex: Int?
    @State private var initialServerChapterIndex: Int?
    @State private var isRepaginateQueued = false
    @State private var lastPaginationKey: PaginationKey?
    
    // Pagination State
    @State private var currentPageIndex: Int = 0
    @State private var currentCache: ChapterCache = .empty
    @State private var prevCache: ChapterCache = .empty
    @State private var nextCache: ChapterCache = .empty
    @State private var pendingJumpToLastPage = false
    @State private var pendingJumpToFirstPage = false
    @State private var pageSize: CGSize = .zero
    @State private var isPageTransitioning = false
    @State private var ttsBaseIndex: Int = 0
    @State private var pendingFlipId: UUID = UUID()
    @State private var isTTSSyncingPage = false
    @State private var suppressTTSSync = false
    @State private var pausedChapterIndex: Int?
    @State private var pausedPageIndex: Int?
    @State private var needsTTSRestartAfterPause = false
    @State private var lastAdjacentPrepareAt: TimeInterval = 0
    
    // Pagination Cache for seamless transition
    @State private var isAutoFlipping: Bool = false
    @StateObject private var contentControllerCache = ReadContentViewControllerCache()
    @State private var pendingBufferPageIndex: Int?
    @State private var lastHandledPageIndex: Int?

    // Unified Insets for consistency
    private let horizontalPadding: CGFloat = 20
    private let verticalPadding: CGFloat = 40
    private let initialPageBatch: Int = 12
    private let prefetchPageBatch: Int = 8
    private let bufferedPageBatch: Int = 6

    init(book: Book) {
        self.book = book
        let serverIndex = book.durChapterIndex ?? 0
        let localProgress = book.bookUrl.flatMap { UserPreferences.shared.getReadingProgress(bookUrl: $0) }
        
        // Sync logic: Compare timestamps (normalize to milliseconds)
        let rawServerTime = book.durChapterTime ?? 0
        let serverTime: Int64 = rawServerTime < 1_000_000_000_000 ? rawServerTime * 1000 : rawServerTime
        let localTime = Int64(localProgress?.timestamp ?? 0)
        
        let useServer = serverTime > localTime
        
        let startIndex = useServer ? serverIndex : (localProgress?.chapterIndex ?? serverIndex)
        
        _currentChapterIndex = State(initialValue: startIndex)
        _lastTTSSentenceIndex = State(initialValue: nil)
        _pendingResumePos = State(initialValue: book.durChapterPos)
        
        if useServer {
            _pendingResumeLocalBodyIndex = State(initialValue: nil)
            _pendingResumeLocalChapterIndex = State(initialValue: nil)
            _pendingResumeLocalPageIndex = State(initialValue: nil)
        } else {
            _pendingResumeLocalBodyIndex = State(initialValue: localProgress?.bodyCharIndex)
            _pendingResumeLocalChapterIndex = State(initialValue: localProgress?.chapterIndex)
            _pendingResumeLocalPageIndex = State(initialValue: localProgress?.pageIndex)
        }
        
        _initialServerChapterIndex = State(initialValue: serverIndex)
    }

    private struct PaginationKey: Hashable {
        let width: Int
        let height: Int
        let fontSize: Int
        let lineSpacing: Int
        let margin: Int
        let sentenceCount: Int
        let chapterIndex: Int
        let resumeCharIndex: Int
        let resumePageIndex: Int
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
                    pendingJumpToFirstPage = true
                    loadChapterContent()
                    showChapterList = false
                }
            )
        }
        .sheet(isPresented: $showFontSettings) {
            FontSizeSheet(preferences: preferences)
        }
        .sheet(isPresented: $showAddReplaceRule) {
            ReplaceRuleEditView(viewModel: replaceRuleViewModel, rule: pendingReplaceRule)
        }
        .onChange(of: showAddReplaceRule) { isPresented in
            if !isPresented {
                pendingReplaceRule = nil
            }
        }
        .task {
            await loadChapters()
            await replaceRuleViewModel.fetchRules()
        }
        .onChange(of: replaceRuleViewModel.rules) { _ in
            updateProcessedContent(from: rawContent)
        }
        .onChange(of: pendingScrollToSentenceIndex) { pending in
            guard preferences.readingMode != .horizontal else { return }
            guard let index = pending, let proxy = scrollProxy else { return }
            withAnimation {
                proxy.scrollTo(index, anchor: .center)
            }
            pendingScrollToSentenceIndex = nil
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
        .onChange(of: ttsManager.isPaused) { isPaused in
            if isPaused {
                pausedChapterIndex = currentChapterIndex
                pausedPageIndex = currentPageIndex
                needsTTSRestartAfterPause = false
            } else {
                needsTTSRestartAfterPause = false
            }
        }
        .onChange(of: ttsManager.currentSentenceIndex) { newIndex in
            if preferences.readingMode == .horizontal && ttsManager.isPlaying {
                if !suppressTTSSync {
                    syncPageForSentenceIndex(newIndex)
                }
                scheduleAutoFlip(duration: ttsManager.currentSentenceDuration)
                suppressTTSSync = false
            }
        }
        .onChange(of: ttsManager.currentSentenceDuration) { duration in
             if preferences.readingMode == .horizontal && ttsManager.isPlaying {
                 scheduleAutoFlip(duration: duration)
             }
        }
    }

    private var backgroundView: some View {
        Color(UIColor.systemBackground)
    }

    @ViewBuilder
    private func mainContent(safeArea: EdgeInsets) -> some View {
        if preferences.readingMode == .horizontal {
            horizontalReader(safeArea: safeArea)
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
                    handleReaderTap(location: .middle)
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
                    if let pending = pendingScrollToSentenceIndex {
                        withAnimation {
                            proxy.scrollTo(pending, anchor: .center)
                        }
                        pendingScrollToSentenceIndex = nil
                    }
                }
            }
        }
    }
    
    private func horizontalReader(safeArea: EdgeInsets) -> some View {
        GeometryReader { geometry in
            // Define desired margins *within* the safe area
            let horizontalMargin: CGFloat = preferences.pageHorizontalMargin
            let verticalMargin: CGFloat = 10
            
            let availableSize = CGSize(
                width: max(0, geometry.size.width - safeArea.leading - safeArea.trailing - horizontalMargin * 2),
                height: max(0, geometry.size.height - safeArea.top - safeArea.bottom - verticalMargin * 2)
            )

            // The precise size for both pagination and rendering
            let contentSize = availableSize
            horizontalReaderBody(
                geometry: geometry,
                safeArea: safeArea,
                horizontalMargin: horizontalMargin,
                verticalMargin: verticalMargin,
                availableSize: availableSize,
                contentSize: contentSize
            )
            .onAppear {
                if contentSize.width > 0 && contentSize.height > 0 {
                    scheduleRepaginate(in: contentSize)
                }
            }
            .onChange(of: contentSentences) { _ in
                if contentSize.width > 0 && contentSize.height > 0 {
                    scheduleRepaginate(in: contentSize)
                }
            }
            .onChange(of: preferences.fontSize) { _ in
                if contentSize.width > 0 && contentSize.height > 0 {
                    scheduleRepaginate(in: contentSize)
                }
            }
            .onChange(of: preferences.lineSpacing) { _ in
                if contentSize.width > 0 && contentSize.height > 0 {
                    scheduleRepaginate(in: contentSize)
                }
            }
            .onChange(of: preferences.pageHorizontalMargin) { _ in
                if contentSize.width > 0 && contentSize.height > 0 {
                    scheduleRepaginate(in: contentSize)
                }
            }
            .onChange(of: geometry.size) { _ in
                 if contentSize.width > 0 && contentSize.height > 0 {
                    scheduleRepaginate(in: contentSize)
                }
            }
            .onChange(of: currentPageIndex) { newIndex in
                // This logic handles TTS restart on manual flip
                if isTTSSyncingPage {
                    isTTSSyncingPage = false
                    if let startIndex = pageStartSentenceIndex(for: newIndex) {
                        lastTTSSentenceIndex = startIndex
                    }
                    return
                }

                handlePageIndexChange(newIndex)
            }
        }
    }

    private func horizontalReaderBody(
        geometry: GeometryProxy,
        safeArea: EdgeInsets,
        horizontalMargin: CGFloat,
        verticalMargin: CGFloat,
        availableSize: CGSize,
        contentSize: CGSize
    ) -> some View {
        VStack(spacing: 0) {
            Spacer().frame(height: safeArea.top + verticalMargin)
            HStack(spacing: 0) {
                Color.clear
                    .frame(width: safeArea.leading + horizontalMargin)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        handleReaderTap(location: .left)
                    }
                
                if availableSize.width > 0 && availableSize.height > 0 {
                        ZStack(alignment: .bottomTrailing) {
                            cacheRefresher
                            let currentVC = makeContentViewController(cache: currentCache, pageIndex: currentPageIndex, chapterOffset: 0)
                        let prevVC = makeContentViewController(cache: prevCache, pageIndex: max(0, prevCache.pages.count - 1), chapterOffset: -1)
                        let nextVC = makeContentViewController(cache: nextCache, pageIndex: 0, chapterOffset: 1)

                        ReadPageViewController(
                            snapshot: PageSnapshot(pages: currentCache.pages, renderStore: currentCache.store),
                            prevSnapshot: PageSnapshot(pages: prevCache.pages, renderStore: prevCache.store),
                            nextSnapshot: PageSnapshot(pages: nextCache.pages, renderStore: nextCache.store),
                            currentPageIndex: $currentPageIndex,
                            pageSpacing: preferences.pageInterSpacing,
                            isAtChapterStart: currentPageIndex == 0,
                            isAtChapterEnd: currentCache.isFullyPaginated && currentPageIndex >= max(0, currentCache.pages.count - 1),
                            isScrollEnabled: !(ttsManager.isPlaying && preferences.lockPageOnTTS),
                            onTransitioningChanged: { transitioning in
                                pageTransitionChanged(isTransitioning: transitioning)
                            },
                            onTapLocation: { location in
                                handleReaderTap(location: location)
                            },
                onChapterChange: { offset in
                    isAutoFlipping = true
                    handleChapterSwitch(offset: offset)
                },
                onAdjacentPrefetch: { offset in
                    if offset > 0 {
                        if nextCache.pages.isEmpty { prepareAdjacentChapters(for: currentChapterIndex) }
                    } else if offset < 0 {
                        if prevCache.pages.isEmpty { prepareAdjacentChapters(for: currentChapterIndex) }
                    }
                },
                onAddReplaceRule: { selectedText in
                    presentReplaceRuleEditor(selectedText: selectedText)
                },
                currentContentViewController: currentVC,
                prevContentViewController: prevVC,
                nextContentViewController: nextVC
            )
                            .id(preferences.pageInterSpacing)
                            .frame(width: contentSize.width, height: contentSize.height)
                        
                        if !showUIControls && currentCache.pages.count > 0 {
                            let displayCurrent = currentPageIndex + 1
                            Group {
                                if currentCache.isFullyPaginated {
                                    let total = max(currentCache.pages.count, displayCurrent)
                                    let percentage = Int((Double(displayCurrent) / Double(total)) * 100)
                                    Text("\(displayCurrent)/\(total) (\(percentage)%)")
                                } else if let range = pageRange(for: currentPageIndex),
                                          currentCache.attributedText.length > 0 {
                                    let progress = Double(NSMaxRange(range)) / Double(currentCache.attributedText.length)
                                    let percentage = Int(progress * 100)
                                    Text("\(displayCurrent)/\(currentCache.pages.count)+ (\(percentage)%)")
                                } else {
                                    Text("\(displayCurrent)/\(currentCache.pages.count)+")
                                }
                            }
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.trailing, 8)
                            .padding(.bottom, 2)
                            .transition(.opacity.animation(.easeInOut(duration: 0.3)))
                        }
                    }
                    .frame(width: availableSize.width, height: availableSize.height)
                } else {
                    // Placeholder for when size is zero
                    Rectangle().fill(Color.clear)
                }
                
                Color.clear
                    .frame(width: safeArea.trailing + horizontalMargin)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        handleReaderTap(location: .right)
                    }
            }
            Spacer().frame(height: safeArea.bottom + verticalMargin)
        }
        .frame(width: geometry.size.width, height: geometry.size.height)
    }

    // MARK: - Pagination & Navigation

    private func repaginateContent(in size: CGSize, with newContentSentences: [String]? = nil) {
        let sentences = newContentSentences ?? contentSentences
        let chapterTitle = chapters.indices.contains(currentChapterIndex)
            ? chapters[currentChapterIndex].title
            : nil

        let newAttrText = TextKitPaginator.createAttributedText(sentences: sentences, fontSize: preferences.fontSize, lineSpacing: preferences.lineSpacing, chapterTitle: chapterTitle)
        let newPStarts = TextKitPaginator.paragraphStartIndices(sentences: sentences)
        let newPrefixLen = (chapterTitle?.isEmpty ?? true) ? 0 : (chapterTitle! + "\n").utf16.count
        
        guard newAttrText.length > 0, size.width > 0, size.height > 0 else {
            currentCache = .empty
            return
        }

        let resumeCharIndex = pendingResumeCharIndex
        let focusCharIndex: Int? = currentCache.pages.indices.contains(currentPageIndex)
            ? currentCache.pages[currentPageIndex].globalRange.location
            : resumeCharIndex

        let renderStore = TextKitPaginator.createRenderStore(fullText: newAttrText, size: size)
        var pages: [PaginatedPage] = []
        var isFully = false

        func appendPages(_ count: Int) {
            let result = TextKitPaginator.appendPages(
                renderStore: renderStore,
                paragraphStarts: newPStarts,
                prefixLen: newPrefixLen,
                maxPages: count
            )
            pages.append(contentsOf: result.pages)
            isFully = result.reachedEnd
        }

        if pendingJumpToLastPage {
            while !isFully {
                appendPages(max(prefetchPageBatch * 2, 16))
            }
            currentPageIndex = max(0, pages.count - 1)
            pendingJumpToLastPage = false
            pendingJumpToFirstPage = false
        } else {
            appendPages(initialPageBatch)
            if let targetCharIndex = focusCharIndex {
                while pageIndexForChar(targetCharIndex, in: pages) == nil && !isFully {
                    appendPages(prefetchPageBatch)
                }
                if let pageIndex = pageIndexForChar(targetCharIndex, in: pages) {
                    currentPageIndex = pageIndex
                }
            } else if pendingJumpToFirstPage || currentCache.pages.isEmpty {
                currentPageIndex = 0
            }
            pendingJumpToFirstPage = false
        }

        if pages.isEmpty {
            currentPageIndex = 0
        } else if currentPageIndex >= pages.count {
            currentPageIndex = pages.count - 1
        }

        currentCache = ChapterCache(
            pages: pages,
            store: renderStore,
            contentSentences: sentences,
            attributedText: newAttrText,
            paragraphStarts: newPStarts,
            chapterPrefixLen: newPrefixLen,
            isFullyPaginated: isFully
        )
        if let localPage = pendingResumeLocalPageIndex,
           pendingResumeLocalChapterIndex == currentChapterIndex,
           pages.indices.contains(localPage) {
            currentPageIndex = localPage
            pendingResumeLocalPageIndex = nil
        }
        if resumeCharIndex != nil {
            pendingResumeCharIndex = nil
        }
        ensurePageBuffer(around: currentPageIndex)
        triggerAdjacentPrefetchIfNeeded(force: true)
    }

    private func pageIndexForChar(_ index: Int, in pages: [PaginatedPage]) -> Int? {
        guard index >= 0 else { return nil }
        for (i, page) in pages.enumerated() {
            if NSLocationInRange(index, page.globalRange) { return i }
        }
        return nil
    }

    private func ensurePageBuffer(around index: Int) {
        ensurePages(upTo: index + prefetchPageBatch)
    }

    private func triggerAdjacentPrefetchIfNeeded(force: Bool = false) {
        guard pageSize.width > 0, pageSize.height > 0 else { return }
        let now = Date().timeIntervalSince1970
        if !force, now - lastAdjacentPrepareAt < 1.0 { return }
        let needsPrev = currentChapterIndex > 0 && prevCache.pages.isEmpty
        let needsNext = currentChapterIndex < chapters.count - 1 && nextCache.pages.isEmpty
        guard needsPrev || needsNext else { return }
        lastAdjacentPrepareAt = now
        prepareAdjacentChapters(for: currentChapterIndex)
    }

    private func ensurePages(upTo index: Int) {
        guard let store = currentCache.store, !currentCache.pages.isEmpty else { return }
        guard !currentCache.isFullyPaginated else { return }
        guard currentCache.pages.count <= index else { return }

        var pages = currentCache.pages
        var isFully = currentCache.isFullyPaginated
        var didAppend = false

        while pages.count <= index && !isFully {
            let result = TextKitPaginator.appendPages(
                renderStore: store,
                paragraphStarts: currentCache.paragraphStarts,
                prefixLen: currentCache.chapterPrefixLen,
                maxPages: prefetchPageBatch
            )
            if result.pages.isEmpty {
                isFully = true
                break
            }
            pages.append(contentsOf: result.pages)
            isFully = result.reachedEnd
            didAppend = true
        }

        guard didAppend else { return }
        currentCache = ChapterCache(
            pages: pages,
            store: store,
            contentSentences: currentCache.contentSentences,
            attributedText: currentCache.attributedText,
            paragraphStarts: currentCache.paragraphStarts,
            chapterPrefixLen: currentCache.chapterPrefixLen,
            isFullyPaginated: isFully
        )
    }

    private func ensurePagesForCharIndex(_ index: Int) -> Int? {
        if let pageIndex = pageIndexForChar(index, in: currentCache.pages) { return pageIndex }
        guard let store = currentCache.store, !currentCache.pages.isEmpty else { return nil }
        guard !currentCache.isFullyPaginated else { return nil }

        var pages = currentCache.pages
        var isFully = currentCache.isFullyPaginated
        var didAppend = false

        while pageIndexForChar(index, in: pages) == nil && !isFully {
            let result = TextKitPaginator.appendPages(
                renderStore: store,
                paragraphStarts: currentCache.paragraphStarts,
                prefixLen: currentCache.chapterPrefixLen,
                maxPages: prefetchPageBatch
            )
            if result.pages.isEmpty {
                isFully = true
                break
            }
            pages.append(contentsOf: result.pages)
            isFully = result.reachedEnd
            didAppend = true
        }

        if didAppend {
            currentCache = ChapterCache(
                pages: pages,
                store: store,
                contentSentences: currentCache.contentSentences,
                attributedText: currentCache.attributedText,
                paragraphStarts: currentCache.paragraphStarts,
                chapterPrefixLen: currentCache.chapterPrefixLen,
                isFullyPaginated: isFully
            )
        }

        return pageIndexForChar(index, in: pages)
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
        if currentPageIndex < currentCache.pages.count - 1 {
            currentPageIndex += 1
        } else if !currentCache.isFullyPaginated {
            ensurePages(upTo: currentPageIndex + 1)
            if currentPageIndex < currentCache.pages.count - 1 {
                currentPageIndex += 1
            }
        } else if currentChapterIndex < chapters.count - 1 {
            pendingJumpToFirstPage = true
            nextChapter()
        }
    }

    private func handleReaderTap(location: ReaderTapLocation) {
        if showUIControls {
            showUIControls = false
            return
        }
        if location == .middle {
            showUIControls = true
            return
        }
        if ttsManager.isPlaying && preferences.lockPageOnTTS { return }
        switch location {
        case .left:
            goToPreviousPage()
        case .right:
            goToNextPage()
        case .middle:
            showUIControls = true
        }
    }

    private func handlePageIndexChange(_ newIndex: Int) {
        pendingBufferPageIndex = newIndex
        processPendingPageChangeIfReady()
    }

    private func processPendingPageChangeIfReady() {
        guard !isPageTransitioning else { return }
        guard let newIndex = pendingBufferPageIndex else { return }
        if lastHandledPageIndex == newIndex {
            return
        }
        pendingBufferPageIndex = nil
        lastHandledPageIndex = newIndex

        ensurePageBuffer(around: newIndex)
        if newIndex <= 1 || newIndex >= max(0, currentCache.pages.count - 2) {
            triggerAdjacentPrefetchIfNeeded()
        }

        if ttsManager.isPlaying && !ttsManager.isPaused && !isAutoFlipping {
            if !preferences.lockPageOnTTS {
                ttsManager.stop()
                startTTS(pageIndexOverride: newIndex, showControls: false)
            }
        }
        if ttsManager.isPlaying && ttsManager.isPaused {
            needsTTSRestartAfterPause = true
        }
        isAutoFlipping = false

        if let startIndex = pageStartSentenceIndex(for: newIndex) {
            lastTTSSentenceIndex = startIndex
        }
    }

    private func pageTransitionChanged(isTransitioning: Bool) {
        isPageTransitioning = isTransitioning
        if !isTransitioning {
            processPendingPageChangeIfReady()
        }
    }

    private func makeContentViewController(cache: ChapterCache, pageIndex: Int, chapterOffset: Int) -> ReadContentViewController? {
        guard let store = cache.store else { return nil }
        guard pageIndex >= 0, pageIndex < store.containers.count else { return nil }
        return contentControllerCache.controller(
            for: store,
            pageIndex: pageIndex,
            chapterOffset: chapterOffset
        ) {
            ReadContentViewController(
                pageIndex: pageIndex,
                renderStore: store,
                chapterOffset: chapterOffset,
                onAddReplaceRule: { selectedText in
                    presentReplaceRuleEditor(selectedText: selectedText)
                },
                onTapLocation: { location in
                    handleReaderTap(location: location)
                }
            )
        }
    }

    private func refreshContentControllerCache() {
        contentControllerCache.retainActive(stores: [currentCache.store, prevCache.store, nextCache.store])
    }

    private var cacheRefresher: some View {
        refreshContentControllerCache()
        return EmptyView()
    }

    private func scheduleRepaginate(in size: CGSize) {
        pageSize = size
        let key = PaginationKey(
            width: Int((size.width * 100).rounded()),
            height: Int((size.height * 100).rounded()),
            fontSize: Int((preferences.fontSize * 10).rounded()),
            lineSpacing: Int((preferences.lineSpacing * 10).rounded()),
            margin: Int((preferences.pageHorizontalMargin * 10).rounded()),
            sentenceCount: contentSentences.count,
            chapterIndex: currentChapterIndex,
            resumeCharIndex: pendingResumeCharIndex ?? -1,
            resumePageIndex: pendingResumeLocalPageIndex ?? -1
        )
        if key == lastPaginationKey {
            return
        }
        lastPaginationKey = key
        if isRepaginateQueued {
            return
        }
        isRepaginateQueued = true
        DispatchQueue.main.async {
            repaginateContent(in: size)
            isRepaginateQueued = false
        }
    }

    private func pageIndexForSentence(_ index: Int) -> Int? {
        guard !currentCache.pages.isEmpty else { return nil }
        for i in 0..<currentCache.pages.count {
            let startIndex = currentCache.pages[i].startSentenceIndex
            let nextStart = (i + 1 < currentCache.pages.count)
                ? currentCache.pages[i + 1].startSentenceIndex
                : Int.max
            if index >= startIndex && index < nextStart {
                return i
            }
        }
        return nil
    }

    private func pageRange(for pageIndex: Int) -> NSRange? {
        if let store = currentCache.store, pageIndex >= 0, pageIndex < store.containers.count {
            let container = store.containers[pageIndex]
            let glyphRange = store.layoutManager.glyphRange(for: container)
            return store.layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        }
        if currentCache.pages.indices.contains(pageIndex) {
            return currentCache.pages[pageIndex].globalRange
        }
        return nil
    }

    private func pageStartSentenceIndex(for pageIndex: Int) -> Int? {
        guard let range = pageRange(for: pageIndex) else { return nil }
        let adjustedLocation = max(0, range.location - currentCache.chapterPrefixLen)
        return currentCache.paragraphStarts.lastIndex(where: { $0 <= adjustedLocation }) ?? 0
    }

    private func globalCharIndexForSentence(_ index: Int) -> Int? {
        guard index >= 0, index < currentCache.paragraphStarts.count else { return nil }
        return currentCache.paragraphStarts[index] + currentCache.chapterPrefixLen
    }

    private func syncPageForSentenceIndex(_ index: Int) {
        guard index >= 0, preferences.readingMode == .horizontal else { return }
        
        let realIndex = index + ttsBaseIndex
        
        // Only flip page immediately if the sentence starts AFTER the current page.
        // If it starts ON this page (even partially), we wait for auto flip.
        if currentCache.pages.indices.contains(currentPageIndex),
           let sentenceStart = globalCharIndexForSentence(realIndex) {
            let pageRange = currentCache.pages[currentPageIndex].globalRange
            let sentenceLen = contentSentences.indices.contains(realIndex) ? contentSentences[realIndex].utf16.count : 0
            if sentenceLen > 0 {
                let sentenceRange = NSRange(location: sentenceStart, length: sentenceLen)
                if NSIntersectionRange(sentenceRange, pageRange).length > 0 {
                    return
                }
            } else if NSLocationInRange(sentenceStart, pageRange) {
                return
            }
        }

        if let pageIndex = pageIndexForSentence(realIndex) ?? (globalCharIndexForSentence(realIndex).flatMap { ensurePagesForCharIndex($0) }),
           pageIndex != currentPageIndex {
            isTTSSyncingPage = true
            withAnimation { currentPageIndex = pageIndex }
            DispatchQueue.main.async {
                isTTSSyncingPage = false
            }
            return
        }
    }
    
    private func scheduleAutoFlip(duration: TimeInterval) {
        guard duration > 0, ttsManager.isPlaying, preferences.readingMode == .horizontal else { return }
        
        pendingFlipId = UUID()
        let taskId = pendingFlipId
        
        let index = ttsManager.currentSentenceIndex
        let realIndex = index + ttsBaseIndex
        
        guard currentCache.pages.indices.contains(currentPageIndex),
              let sentenceStart = globalCharIndexForSentence(realIndex) else { return }
              
        let sentenceLen = contentSentences.indices.contains(realIndex) ? contentSentences[realIndex].utf16.count : 0
        guard sentenceLen > 0 else { return }
        
        let sentenceRange = NSRange(location: sentenceStart, length: sentenceLen)
        let pageRange = currentCache.pages[currentPageIndex].globalRange
        
        let intersection = NSIntersectionRange(sentenceRange, pageRange)
        let sentenceEnd = NSMaxRange(sentenceRange)
        let pageStart = pageRange.location
        let pageEnd = NSMaxRange(pageRange)

        if sentenceStart >= pageStart, sentenceEnd > pageEnd, intersection.length > 0 {
            let visibleRatio = Double(intersection.length) / Double(sentenceLen)
            let delay = duration * visibleRatio

            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                if self.pendingFlipId == taskId {
                    isAutoFlipping = true
                    goToNextPage()
                }
            }
        }
    }
    
    private func prepareAdjacentChapters(for chapterIndex: Int) {
        guard pageSize.width > 0, pageSize.height > 0 else { return }
        
        // Prepare Next Chapter "gate"
        let nextIndex = chapterIndex + 1
        if nextIndex < chapters.count {
            Task {
                if let cache = await paginateChapter(at: nextIndex, forGate: true) {
                    await MainActor.run { self.nextCache = cache }
                }
            }
        } else {
            nextCache = .empty
        }
        
        // Prepare Previous Chapter "gate"
        let prevIndex = chapterIndex - 1
        if prevIndex >= 0 {
            Task {
                if let cache = await paginateChapter(at: prevIndex, forGate: true, fromEnd: true) {
                    await MainActor.run { self.prevCache = cache }
                }
            }
        } else {
            prevCache = .empty
        }
    }

    private func handleChapterSwitch(offset: Int) {
        // Cancel any pending timed flip
        pendingFlipId = UUID()
        
        if offset == 1 { // Switched to Next Chapter
            guard !nextCache.pages.isEmpty else { return }
            currentChapterIndex += 1
            prevCache = currentCache
            currentCache = nextCache
            nextCache = .empty
            currentPageIndex = 0
            pendingJumpToFirstPage = true
            
        } else if offset == -1 { // Switched to Prev Chapter
            guard !prevCache.pages.isEmpty else { return }
            currentChapterIndex -= 1
            nextCache = currentCache
            currentCache = prevCache
            prevCache = .empty
            currentPageIndex = currentCache.pages.count - 1
            pendingJumpToLastPage = true
        }

        // Trigger full layout load for the new current chapter & preload for new adjacent chapters
        loadChapterContent()
    }
    
    // This function re-paginates the current chapter with a full layout,
    // replacing the "gate" cache if necessary.
    private func repaginateCurrentChapterWindow(sentences: [String]? = nil) {
        guard pageSize.width > 0, pageSize.height > 0 else { return }
        
        if let sentences = sentences, !sentences.isEmpty {
            repaginateContent(in: pageSize, with: sentences)
            return
        }
        
        guard !rawContent.isEmpty else { return } // Should be called after content is loaded
        let processed = applyReplaceRules(to: rawContent)
        let newSentences = splitIntoParagraphs(processed)
        repaginateContent(in: pageSize, with: newSentences)
    }

    private func paginateChapter(at index: Int, forGate: Bool, fromEnd: Bool = false) async -> ChapterCache? {
        guard let content = try? await apiService.fetchChapterContent(bookUrl: book.bookUrl ?? "", bookSourceUrl: book.origin, index: index) else {
            return nil
        }
        
        let cleaned = removeHTMLAndSVG(content)
        let processed = applyReplaceRules(to: cleaned)
        let sentences = splitIntoParagraphs(processed)
        let title = chapters[index].title
        
        let attrText = TextKitPaginator.createAttributedText(sentences: sentences, fontSize: preferences.fontSize, lineSpacing: preferences.lineSpacing, chapterTitle: title)
        let pStarts = TextKitPaginator.paragraphStartIndices(sentences: sentences)
        let prefixLen = (title.isEmpty) ? 0 : (title + "\n").utf16.count

        let renderStore = TextKitPaginator.createRenderStore(fullText: attrText, size: pageSize)
        var pages: [PaginatedPage] = []
        var isFully = false

        func appendPages(_ count: Int) {
            let result = TextKitPaginator.appendPages(
                renderStore: renderStore,
                paragraphStarts: pStarts,
                prefixLen: prefixLen,
                maxPages: count
            )
            pages.append(contentsOf: result.pages)
            isFully = result.reachedEnd
        }

        func appendUntilBuffer(_ target: Int) {
            while pages.count < target && !isFully {
                appendPages(prefetchPageBatch)
            }
        }

        let bufferGoal = max(bufferedPageBatch, initialPageBatch)

        if forGate {
            if fromEnd {
                while !isFully {
                    appendPages(max(prefetchPageBatch * 2, 16))
                }
            } else {
                appendPages(initialPageBatch)
                appendUntilBuffer(bufferGoal)
            }
        } else {
            appendPages(initialPageBatch)
            appendUntilBuffer(bufferGoal)
        }

        return ChapterCache(
            pages: pages,
            store: renderStore,
            contentSentences: sentences,
            attributedText: attrText,
            paragraphStarts: pStarts,
            chapterPrefixLen: prefixLen,
            isFullyPaginated: isFully
        )
    }

    // MARK: - Logic & Actions (Loading, Saving, etc.)
    
    private func updateProcessedContent(from rawText: String) {
        let processedContent = applyReplaceRules(to: rawText)
        let trimmedContent = processedContent.trimmingCharacters(in: .whitespacesAndNewlines)
        let isEffectivelyEmpty = trimmedContent.isEmpty
        let timestamp = String(format: "%.2f", Date().timeIntervalSince1970)
        let content = isEffectivelyEmpty ? "章节内容为空\n\(timestamp)" : processedContent
        currentContent = content
        contentSentences = splitIntoParagraphs(content)
        applyResumeProgressIfNeeded(sentences: contentSentences)
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

    private func applyResumeProgressIfNeeded(sentences: [String]) {
        guard !didApplyResumePos else { return }
        let hasLocalResume = pendingResumeLocalBodyIndex != nil
            && pendingResumeLocalChapterIndex == currentChapterIndex
        let pos = pendingResumePos ?? 0
        if !hasLocalResume && pos <= 0 {
            return
        }
        let chapterTitle = chapters.indices.contains(currentChapterIndex)
            ? chapters[currentChapterIndex].title
            : nil
        let prefixLen = (chapterTitle?.isEmpty ?? true) ? 0 : (chapterTitle! + "\n").utf16.count
        let paragraphStarts = TextKitPaginator.paragraphStartIndices(sentences: sentences)
        let lastSentence = sentences.last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let bodyLength = (paragraphStarts.last ?? 0) + lastSentence.utf16.count
        guard bodyLength > 0 else { return }

        let bodyIndex: Int
        if let localIndex = pendingResumeLocalBodyIndex,
           pendingResumeLocalChapterIndex == currentChapterIndex {
            bodyIndex = localIndex
            pendingResumeLocalBodyIndex = nil
            pendingResumeLocalChapterIndex = nil
            pendingResumeLocalPageIndex = nil
        } else {
            // New logic: if pos > 1, treat as char index; else treat as ratio
            if pos > 1.0 {
                bodyIndex = Int(pos)
            } else {
                let ratio = min(max(pos, 0.0), 1.0)
                bodyIndex = Int(Double(bodyLength) * ratio)
            }
        }
        let clampedBodyIndex = max(0, min(bodyIndex, max(0, bodyLength - 1)))
        pendingResumeCharIndex = clampedBodyIndex + prefixLen
        let sentenceIndex = paragraphStarts.lastIndex(where: { $0 <= clampedBodyIndex }) ?? 0
        lastTTSSentenceIndex = sentenceIndex
        pendingScrollToSentenceIndex = sentenceIndex
        didApplyResumePos = true
    }

    private func presentReplaceRuleEditor(selectedText: String) {
        let trimmed = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        pendingReplaceRule = makeReplaceRuleDraft(from: trimmed)
        showAddReplaceRule = true
    }

    private func makeReplaceRuleDraft(from text: String) -> ReplaceRule {
        let escapedPattern = NSRegularExpression.escapedPattern(for: text)
        let shortName: String
        if text.count > 12 {
            shortName = String(text.prefix(12)) + "..."
        } else {
            shortName = text
        }
        return ReplaceRule(
            id: nil,
            name: "正文净化-\(shortName)",
            groupname: "",
            pattern: escapedPattern,
            replacement: "",
            scope: book.name ?? "",
            scopeTitle: false,
            scopeContent: true,
            excludeScope: "",
            isEnabled: true,
            isRegex: true,
            timeoutMillisecond: 3000,
            ruleorder: 0
        )
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
        // First split by newlines to preserve paragraph structure as much as possible
        let blocks = text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            
        // Simple regex to split by common sentence terminators while keeping them attached to the sentence if possible.
        // Or simply split. Splitting by punctuation improves TTS granularity.
        // Let's use a simple approach: split by [。！？!?] followed by nothing or whitespace
        // But re-joining them with \n in createAttributedText will alter layout.
        // CONSTRAINT: We cannot easily change sentence splitting without affecting layout if createAttributedText joins with \n.
        // However, if we split a long paragraph into multiple "sentences", they will be rendered as separate paragraphs.
        // This is a trade-off. For now, let's keep the original logic to strictly preserve layout,
        // relying on the Lazy Flip logic to handle cross-page reading.
        // Only if the user explicitly requested finer granularity should we do this.
        // User said: "根据字符时间的长度来大体计算".
        // Let's stick to the original logic for now to ensure layout correctness.
        return blocks
    }
    
    private func loadChapters() async {
        isLoading = true
        do {
            chapters = try await apiService.fetchChapterList(bookUrl: book.bookUrl ?? "", bookSourceUrl: book.origin)
            if currentChapterIndex < 0 || currentChapterIndex >= chapters.count {
                currentChapterIndex = max(0, chapters.count - 1)
                pendingResumeLocalBodyIndex = nil
                pendingResumeLocalChapterIndex = nil
                if let fallback = initialServerChapterIndex, fallback >= 0, fallback < chapters.count {
                    currentChapterIndex = fallback
                }
            }
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
                    resetPaginationState()
                    rawContent = cleanedContent
                    updateProcessedContent(from: cleanedContent)
                    isLoading = false
                    ttsBaseIndex = 0
                    if ttsManager.isPlaying {
                        if ttsManager.bookUrl != book.bookUrl || ttsManager.currentChapterIndex != currentChapterIndex {
                            ttsManager.stop()
                        }
                    }
                    prepareAdjacentChapters(for: currentChapterIndex)
                }
            } catch {
                await MainActor.run {
                    errorMessage = "加载章节失败：\(error.localizedDescription)"
                    isLoading = false
                }
            }
        }
    }

    private func resetPaginationState() {
        currentCache = .empty
        prevCache = .empty
        nextCache = .empty
        currentPageIndex = 0
        lastAdjacentPrepareAt = 0
        pendingBufferPageIndex = nil
        lastHandledPageIndex = nil
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
            if ttsManager.isPaused {
                if preferences.readingMode == .horizontal,
                   let pausedChapterIndex,
                   let pausedPageIndex,
                   (pausedChapterIndex != currentChapterIndex || pausedPageIndex != currentPageIndex || needsTTSRestartAfterPause) {
                    ttsManager.stop()
                    startTTS(pageIndexOverride: currentPageIndex)
                    needsTTSRestartAfterPause = false
                } else {
                    ttsManager.resume()
                }
            } else {
                pausedChapterIndex = currentChapterIndex
                pausedPageIndex = currentPageIndex
                ttsManager.pause()
            }
        } else {
            needsTTSRestartAfterPause = false
            startTTS()
        }
    }
    
    private func startTTS(pageIndexOverride: Int? = nil, showControls: Bool = true) {
        if showControls {
            showUIControls = true
        }
        suppressTTSSync = true
        needsTTSRestartAfterPause = false
        let fallbackIndex = lastTTSSentenceIndex ?? 0
        
        var startIndex = fallbackIndex
        var textForTTS = contentSentences.joined(separator: "\n")
        let pageIndex = pageIndexOverride ?? currentPageIndex
        
        if preferences.readingMode == .horizontal {
            if let pageRange = pageRange(for: pageIndex),
               let pageStartIndex = pageStartSentenceIndex(for: pageIndex) {
                startIndex = pageStartIndex
                
                if currentCache.paragraphStarts.indices.contains(startIndex) {
                    let sentenceStartGlobal = currentCache.paragraphStarts[startIndex] + currentCache.chapterPrefixLen
                    let pageStartGlobal = pageRange.location
                    let offset = max(0, pageStartGlobal - sentenceStartGlobal)
                    
                    if offset > 0 && startIndex < contentSentences.count {
                        let firstSentence = contentSentences[startIndex]
                        if offset < firstSentence.utf16.count {
                            let start = firstSentence.utf16.index(firstSentence.utf16.startIndex, offsetBy: offset)
                            if let strIndex = String.Index(start, within: firstSentence) {
                                let partialFirstSentence = String(firstSentence[strIndex...])
                                var sentences = [partialFirstSentence]
                                if startIndex + 1 < contentSentences.count {
                                    sentences.append(contentsOf: contentSentences[(startIndex + 1)...])
                                }
                                textForTTS = sentences.joined(separator: "\n")
                                ttsBaseIndex = startIndex
                                startIndex = 0
                            }
                        }
                    } else if startIndex < contentSentences.count {
                        let sentences = contentSentences[startIndex...]
                        textForTTS = sentences.joined(separator: "\n")
                        ttsBaseIndex = startIndex
                        startIndex = 0
                    }
                }
            }
        } else {
            startIndex = currentVisibleSentenceIndex ?? fallbackIndex
            ttsBaseIndex = 0
        }

        let trimmedText = textForTTS.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }
        
        lastTTSSentenceIndex = ttsBaseIndex + startIndex

        let shouldSpeakChapterTitle = preferences.readingMode == .horizontal
            && pageIndex == 0
            && currentCache.chapterPrefixLen > 0

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
            startAtSentenceIndex: startIndex,
            shouldSpeakChapterTitle: shouldSpeakChapterTitle
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
            let bodyIndex = currentProgressBodyCharIndex()
            
            if let index = bodyIndex {
                preferences.saveReadingProgress(
                    bookUrl: bookUrl,
                    chapterIndex: currentChapterIndex,
                    pageIndex: currentPageIndex,
                    bodyCharIndex: index
                )
            }
            
            // Send character index as 'pos' instead of ratio for better cross-platform compatibility
            let posToSave = Double(bodyIndex ?? 0)
            try? await apiService.saveBookProgress(
                bookUrl: bookUrl,
                index: currentChapterIndex,
                pos: posToSave,
                title: title
            )
        }
    }

    private func currentProgressBodyCharIndex() -> Int? {
        if preferences.readingMode == .horizontal {
            guard let range = pageRange(for: currentPageIndex) else { return nil }
            let offset = max(0, min(range.length - 1, range.length / 2))
            let bodyLocation = range.location - currentCache.chapterPrefixLen + offset
            return max(0, bodyLocation)
        }
        let sentenceIndex = currentVisibleSentenceIndex ?? lastTTSSentenceIndex ?? 0
        let paragraphStarts = TextKitPaginator.paragraphStartIndices(sentences: contentSentences)
        guard sentenceIndex >= 0, sentenceIndex < paragraphStarts.count else { return nil }
        return paragraphStarts[sentenceIndex]
    }

    private func currentProgressRatio() -> Double? {
        guard let bodyIndex = currentProgressBodyCharIndex() else { return nil }
        let bodyLength = currentBodyLength()
        guard bodyLength > 0 else { return nil }
        let ratio = Double(bodyIndex) / Double(bodyLength)
        return min(max(ratio, 0.0), 1.0)
    }

    private func currentBodyLength() -> Int {
        let paragraphStarts = TextKitPaginator.paragraphStartIndices(sentences: contentSentences)
        let lastSentence = contentSentences.last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (paragraphStarts.last ?? 0) + lastSentence.utf16.count
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
                Button("返回") { dismiss() }
                VStack(alignment: .leading, spacing: 2) {
                    Text(book.name ?? "阅读").font(.headline).fontWeight(.bold).lineLimit(1)
                    Text(chapters.indices.contains(currentChapterIndex) ? chapters[currentChapterIndex].title : "未知章节")
                        .font(.caption).foregroundColor(.secondary).lineLimit(1)
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
            TTSControlBar(ttsManager: ttsManager, currentChapterIndex: currentChapterIndex, chaptersCount: chapters.count, onPreviousChapter: previousChapter, onNextChapter: nextChapter, onShowChapterList: { showChapterList = true }, onTogglePlayPause: toggleTTS)
        } else {
            NormalControlBar(currentChapterIndex: currentChapterIndex, chaptersCount: chapters.count, onPreviousChapter: previousChapter, onNextChapter: nextChapter, onShowChapterList: { showChapterList = true }, onToggleTTS: toggleTTS, onShowFontSettings: { showFontSettings = true })
        }
    }
}

// MARK: - UIPageViewController Wrapper
struct PageSnapshot {
    let pages: [PaginatedPage]
    let renderStore: TextKitRenderStore?
}

struct ReadPageViewController: UIViewControllerRepresentable {
    var snapshot: PageSnapshot
    var prevSnapshot: PageSnapshot?
    var nextSnapshot: PageSnapshot?
    
    @Binding var currentPageIndex: Int
    var pageSpacing: CGFloat
    var isAtChapterStart: Bool
    var isAtChapterEnd: Bool
    var isScrollEnabled: Bool
    var onTransitioningChanged: (Bool) -> Void
    var onTapLocation: (ReaderTapLocation) -> Void
    var onChapterChange: (Int) -> Void // offset: -1 or 1
    var onAdjacentPrefetch: (Int) -> Void // offset: -1 or 1
    var onAddReplaceRule: (String) -> Void
    var currentContentViewController: ReadContentViewController?
    var prevContentViewController: ReadContentViewController?
    var nextContentViewController: ReadContentViewController?

    func makeUIViewController(context: Context) -> UIPageViewController {
        let pvc = UIPageViewController(
            transitionStyle: .scroll,
            navigationOrientation: .horizontal,
            options: [UIPageViewController.OptionsKey.interPageSpacing: pageSpacing]
        )
        // pvc.dataSource is set in updateUIViewController
        pvc.delegate = context.coordinator
        context.coordinator.pageViewController = pvc
        pvc.view.backgroundColor = UIColor.systemBackground
        
        return pvc
    }

    func updateUIViewController(_ pvc: UIPageViewController, context: Context) {
        context.coordinator.parent = self
        context.coordinator.currentContentViewController = currentContentViewController
        context.coordinator.prevContentViewController = prevContentViewController
        context.coordinator.nextContentViewController = nextContentViewController

        // Dynamically enable/disable swipe
        if isScrollEnabled {
            pvc.dataSource = context.coordinator
        } else {
            pvc.dataSource = nil
        }
        context.coordinator.updateSnapshotIfNeeded(snapshot, currentPageIndex: currentPageIndex)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: ReadPageViewController
        var isAnimating = false
        private var snapshot: PageSnapshot?
        private var pendingSnapshot: PageSnapshot?
        weak var pageViewController: UIPageViewController?
        var currentContentViewController: ReadContentViewController?
        var prevContentViewController: ReadContentViewController?
        var nextContentViewController: ReadContentViewController?
        
        init(_ parent: ReadPageViewController) { self.parent = parent }
        
        func updateSnapshotIfNeeded(_ newSnapshot: PageSnapshot, currentPageIndex: Int) {
            guard let store = newSnapshot.renderStore, !newSnapshot.pages.isEmpty else { return }
            // Only update if store changed or page count changed drastically (re-pagination)
            // Or if we need to force reset
            if shouldReplaceSnapshot(with: newSnapshot) {
                if isAnimating {
                    pendingSnapshot = newSnapshot
                    return
                }
                snapshot = newSnapshot
            } else if let current = snapshot, newSnapshot.pages.count > current.pages.count {
                if isAnimating {
                    pendingSnapshot = newSnapshot
                } else {
                    snapshot = newSnapshot
                }
            }
            let activeSnapshot = snapshot ?? newSnapshot
            
            // Sync UI if needed
            guard let pvc = pageViewController else { return }
            
            // Check current visible VC
            if let currentVC = pvc.viewControllers?.first as? ReadContentViewController,
               currentVC.chapterOffset == 0,
               currentVC.pageIndex == currentPageIndex,
               currentVC.renderStore === store {
                return
            }
            
            // Set new VC
            let pageCount = activeSnapshot.renderStore?.containers.count ?? activeSnapshot.pages.count
            if currentPageIndex < pageCount {
                let vc: ReadContentViewController
                if let custom = currentContentViewController,
                   custom.chapterOffset == 0,
                   custom.pageIndex == currentPageIndex,
                   custom.renderStore === store {
                    vc = custom
                } else {
                    vc = ReadContentViewController(
                        pageIndex: currentPageIndex,
                        renderStore: store,
                        chapterOffset: 0,
                        onAddReplaceRule: parent.onAddReplaceRule,
                        onTapLocation: parent.onTapLocation
                    )
                }
                pvc.setViewControllers([vc], direction: .forward, animated: false)
            }
        }
        
        private func shouldReplaceSnapshot(with newSnapshot: PageSnapshot) -> Bool {
            guard let current = snapshot else { return true }
            if current.renderStore !== newSnapshot.renderStore { return true }
            if newSnapshot.pages.count < current.pages.count { return true }
            return false
        }

        func pageViewController(_ pvc: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
            guard let vc = viewController as? ReadContentViewController else { return nil }
            
            // Logic for Current Chapter
            if vc.chapterOffset == 0 {
                let index = vc.pageIndex
                if index > 0 {
                    return ReadContentViewController(
                        pageIndex: index - 1,
                        renderStore: vc.renderStore,
                        chapterOffset: 0,
                        onAddReplaceRule: parent.onAddReplaceRule,
                        onTapLocation: parent.onTapLocation
                    )
                } else {
                    // Reached start of current chapter -> Try to fetch Previous Chapter
                    if let prevVC = parent.prevContentViewController,
                       prevVC.chapterOffset == -1 {
                        return prevVC
                    }
                    if let prev = parent.prevSnapshot, let store = prev.renderStore, !prev.pages.isEmpty {
                        let lastIndex = prev.pages.count - 1
                        return ReadContentViewController(
                            pageIndex: lastIndex,
                            renderStore: store,
                            chapterOffset: -1,
                            onAddReplaceRule: parent.onAddReplaceRule,
                            onTapLocation: parent.onTapLocation
                        )
                    }
                    parent.onAdjacentPrefetch(-1)
                }
            }
            // Logic for Previous Chapter (user is scrolling back deeper into prev chapter)
            else if vc.chapterOffset == -1 {
                let index = vc.pageIndex
                if index > 0 {
                    return ReadContentViewController(
                        pageIndex: index - 1,
                        renderStore: vc.renderStore,
                        chapterOffset: -1,
                        onAddReplaceRule: parent.onAddReplaceRule,
                        onTapLocation: parent.onTapLocation
                    )
                }
                // If we reach start of prev chapter, we stop (or could implement prev-prev)
            }
            // Logic for Next Chapter (user scrolled back from next chapter to current)
            else if vc.chapterOffset == 1 {
                let index = vc.pageIndex
                if index > 0 {
                    return ReadContentViewController(
                        pageIndex: index - 1,
                        renderStore: vc.renderStore,
                        chapterOffset: 1,
                        onAddReplaceRule: parent.onAddReplaceRule,
                        onTapLocation: parent.onTapLocation
                    )
                } else {
                    // Reached start of Next Chapter -> Go back to Current Chapter
                    if let current = parent.snapshot.renderStore, !parent.snapshot.pages.isEmpty {
                        let lastIndex = parent.snapshot.pages.count - 1
                        return ReadContentViewController(
                            pageIndex: lastIndex,
                            renderStore: current,
                            chapterOffset: 0,
                            onAddReplaceRule: parent.onAddReplaceRule,
                            onTapLocation: parent.onTapLocation
                        )
                    }
                }
            }
            
            return nil
        }

        func pageViewController(_ pvc: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
            guard let vc = viewController as? ReadContentViewController else { return nil }
            
            // Logic for Current Chapter
            if vc.chapterOffset == 0 {
                let index = vc.pageIndex
                let pageCount = vc.renderStore.containers.count
                if index < pageCount - 1 {
                    return ReadContentViewController(
                        pageIndex: index + 1,
                        renderStore: vc.renderStore,
                        chapterOffset: 0,
                        onAddReplaceRule: parent.onAddReplaceRule,
                        onTapLocation: parent.onTapLocation
                    )
                } else {
                    // Reached end of current chapter -> Try to fetch Next Chapter
                        if let nextVC = parent.nextContentViewController,
                           nextVC.chapterOffset == 1 {
                            return nextVC
                        }
                        if let next = parent.nextSnapshot, let store = next.renderStore, !next.pages.isEmpty {
                            return ReadContentViewController(
                                pageIndex: 0,
                                renderStore: store,
                                chapterOffset: 1,
                                onAddReplaceRule: parent.onAddReplaceRule,
                                onTapLocation: parent.onTapLocation
                            )
                        }
                    parent.onAdjacentPrefetch(1)
                }
            }
            // Logic for Next Chapter (user is scrolling deeper into next chapter)
            else if vc.chapterOffset == 1 {
                let index = vc.pageIndex
                let pageCount = vc.renderStore.containers.count
                if index < pageCount - 1 {
                    return ReadContentViewController(
                        pageIndex: index + 1,
                        renderStore: vc.renderStore,
                        chapterOffset: 1,
                        onAddReplaceRule: parent.onAddReplaceRule,
                        onTapLocation: parent.onTapLocation
                    )
                }
            }
            // Logic for Previous Chapter (user scrolled forward from prev to current)
            else if vc.chapterOffset == -1 {
                let index = vc.pageIndex
                let pageCount = vc.renderStore.containers.count
                if index < pageCount - 1 {
                    return ReadContentViewController(
                        pageIndex: index + 1,
                        renderStore: vc.renderStore,
                        chapterOffset: -1,
                        onAddReplaceRule: parent.onAddReplaceRule,
                        onTapLocation: parent.onTapLocation
                    )
                } else {
                     // Reached end of Prev Chapter -> Go to Current Chapter
                     if let current = parent.snapshot.renderStore, !parent.snapshot.pages.isEmpty {
                         return ReadContentViewController(
                             pageIndex: 0,
                             renderStore: current,
                             chapterOffset: 0,
                             onAddReplaceRule: parent.onAddReplaceRule,
                             onTapLocation: parent.onTapLocation
                         )
                     }
                }
            }
            
            return nil
        }
        
        func pageViewController(_ pvc: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) {
            isAnimating = true
            parent.onTransitioningChanged(true)
        }

        func pageViewController(_ pvc: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
            if completed, let visibleVC = pvc.viewControllers?.first as? ReadContentViewController {
                // If we are still in current chapter (offset 0), update index
                if visibleVC.chapterOffset == 0 {
                    parent.currentPageIndex = visibleVC.pageIndex
                } 
                // If we successfully switched to Next/Prev chapter
                else {
                    // Notify parent to switch data source completely
                    parent.onChapterChange(visibleVC.chapterOffset)
                }
            }
            isAnimating = false
            parent.onTransitioningChanged(false)
            if let nextSnapshot = pendingSnapshot {
                snapshot = nextSnapshot
                pendingSnapshot = nil
                updateSnapshotIfNeeded(nextSnapshot, currentPageIndex: parent.currentPageIndex)
            }
        }
    }
}

final class SelectableTextView: UITextView {
    var onAddRule: ((String) -> Void)?

    @objc func addToReplaceRule() {
        guard selectedRange.location != NSNotFound, selectedRange.length > 0 else { return }
        let sourceText = attributedText?.string ?? text ?? ""
        let selected = (sourceText as NSString).substring(with: selectedRange)
        let trimmed = selected.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onAddRule?(trimmed)
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(addToReplaceRule) {
            return selectedRange.length > 0
        }
        return super.canPerformAction(action, withSender: sender)
    }
}

// MARK: - Content View Controller
class ReadContentViewController: UIViewController, UIGestureRecognizerDelegate {
    let pageIndex: Int
    let renderStore: TextKitRenderStore
    let textContainer: NSTextContainer
    let chapterOffset: Int // 0: Current, -1: Prev, 1: Next
    let onAddReplaceRule: ((String) -> Void)?
    let onTapLocation: ((ReaderTapLocation) -> Void)?
    
    private lazy var textView: SelectableTextView = {
        let tv = SelectableTextView(frame: CGRect(origin: .zero, size: renderStore.size), textContainer: textContainer)
        tv.isEditable = false
        tv.isScrollEnabled = false
        tv.isSelectable = true
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.backgroundColor = .clear
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.onAddRule = onAddReplaceRule
        return tv
    }()
    
    init(pageIndex: Int, renderStore: TextKitRenderStore, chapterOffset: Int, onAddReplaceRule: ((String) -> Void)?, onTapLocation: ((ReaderTapLocation) -> Void)?) {
        self.pageIndex = pageIndex
        self.renderStore = renderStore
        self.textContainer = renderStore.containers[pageIndex]
        self.chapterOffset = chapterOffset
        self.onAddReplaceRule = onAddReplaceRule
        self.onTapLocation = onTapLocation
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.systemBackground
        let item = UIMenuItem(title: "加入净化规则", action: #selector(SelectableTextView.addToReplaceRule))
        if !(UIMenuController.shared.menuItems?.contains(where: { $0.action == item.action }) ?? false) {
            var items = UIMenuController.shared.menuItems ?? []
            items.append(item)
            UIMenuController.shared.menuItems = items
        }
        view.addSubview(textView)
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.topAnchor),
            textView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor), // No extra padding here
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        attachTextTap()
    }

    private func attachTextTap() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTextTap(_:)))
        tap.cancelsTouchesInView = false
        tap.delaysTouchesBegan = false
        tap.delaysTouchesEnded = false
        tap.delegate = self
        if let longPress = textView.gestureRecognizers?.compactMap({ $0 as? UILongPressGestureRecognizer }).first {
            bindPageScrollToFail(longPress)
        }
        textView.addGestureRecognizer(tap)
    }

    private func bindPageScrollToFail(_ longPress: UILongPressGestureRecognizer) {
        var node: UIView? = view
        while let current = node {
            if let scroll = current as? UIScrollView {
                scroll.panGestureRecognizer.require(toFail: longPress)
                scroll.delaysContentTouches = false
                scroll.canCancelContentTouches = false
                break
            }
            node = current.superview
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }

    @objc private func handleTextTap(_ gesture: UITapGestureRecognizer) {
        if textView.selectedRange.length > 0 {
            return
        }
        let x = gesture.location(in: textView).x
        let w = textView.bounds.width
        guard w > 0 else { return }
        if x < w / 3 {
            onTapLocation?(.left)
        } else if x > w * 2 / 3 {
            onTapLocation?(.right)
        } else {
            onTapLocation?(.middle)
        }
    }
}

// MARK: - TextKit Paginator
struct PaginatedPage { let globalRange: NSRange; let startSentenceIndex: Int }
struct AppendPaginationResult {
    let pages: [PaginatedPage]
    let reachedEnd: Bool
}

final class TextKitRenderStore {
    let textStorage: NSTextStorage
    let layoutManager: NSLayoutManager
    var containers: [NSTextContainer]
    let size: CGSize

    init(textStorage: NSTextStorage, layoutManager: NSLayoutManager, containers: [NSTextContainer], size: CGSize) {
        self.textStorage = textStorage
        self.layoutManager = layoutManager
        self.containers = containers
        self.size = size
    }
}

struct TextKitPaginator {
    static func createRenderStore(
        fullText: NSAttributedString,
        size: CGSize
    ) -> TextKitRenderStore {
        let textStorage = NSTextStorage(attributedString: fullText)
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        return TextKitRenderStore(textStorage: textStorage, layoutManager: layoutManager, containers: [], size: size)
    }

    static func appendPages(
        renderStore: TextKitRenderStore,
        paragraphStarts: [Int],
        prefixLen: Int,
        maxPages: Int
    ) -> AppendPaginationResult {
        let size = renderStore.size
        guard renderStore.textStorage.length > 0, size.width > 0, size.height > 0 else {
            return AppendPaginationResult(pages: [], reachedEnd: true)
        }

        var pages: [PaginatedPage] = []
        var reachedEnd = false

        for _ in 0..<maxPages {
            let textContainer = NSTextContainer(size: size)
            textContainer.lineFragmentPadding = 0
            renderStore.layoutManager.addTextContainer(textContainer)
            renderStore.containers.append(textContainer)

            let glyphRange = renderStore.layoutManager.glyphRange(for: textContainer)
            let charRange = renderStore.layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

            if charRange.length == 0 {
                renderStore.layoutManager.removeTextContainer(at: renderStore.containers.count - 1)
                renderStore.containers.removeLast()
                reachedEnd = true
                break
            }

            let globalRange = charRange
            let adjustedLocation = max(0, globalRange.location - prefixLen)
            let startIdx = paragraphStarts.lastIndex(where: { $0 <= adjustedLocation }) ?? 0
            pages.append(PaginatedPage(globalRange: globalRange, startSentenceIndex: startIdx))

            if NSMaxRange(globalRange) >= renderStore.textStorage.length {
                reachedEnd = true
                break
            }
        }

        return AppendPaginationResult(pages: pages, reachedEnd: reachedEnd)
    }
    
    static func createAttributedText(sentences: [String], fontSize: CGFloat, lineSpacing: CGFloat, chapterTitle: String?) -> NSAttributedString {
        let font = UIFont.systemFont(ofSize: fontSize)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = lineSpacing
        paragraphStyle.paragraphSpacing = fontSize * 0.5
        paragraphStyle.alignment = .justified
        paragraphStyle.firstLineHeadIndent = fontSize * 2
        
        let result = NSMutableAttributedString()
        if let title = chapterTitle, !title.isEmpty {
            let titleStyle = NSMutableParagraphStyle()
            titleStyle.alignment = .center; titleStyle.paragraphSpacing = fontSize * 2
            result.append(NSAttributedString(string: title + "\n", attributes: [.font: UIFont.boldSystemFont(ofSize: fontSize + 6), .paragraphStyle: titleStyle, .foregroundColor: UIColor.label]))
        }
        
        let body = sentences
            .map { sentence in sentence.trimmingCharacters(in: .whitespacesAndNewlines) }
            .joined(separator: "\n")
        result.append(NSAttributedString(string: body, attributes: [.font: font, .paragraphStyle: paragraphStyle, .foregroundColor: UIColor.label]))
        return result
    }
    
    static func paragraphStartIndices(sentences: [String]) -> [Int] {
        var starts: [Int] = []; var current = 0
        for (idx, s) in sentences.enumerated() {
            starts.append(current)
            current += (s.trimmingCharacters(in: .whitespacesAndNewlines)).utf16.count + (idx < sentences.count - 1 ? 1 : 0)
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
                Text(sentence.trimmingCharacters(in: .whitespacesAndNewlines))
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
    let onTogglePlayPause: () -> Void
    
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
                Button(action: { onTogglePlayPause() }) {
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
            }
            
            Button(action: onNextChapter) {
                VStack(spacing: 4) {
                    Image(systemName: "chevron.right").font(.title2)
                    Text("\u{4E0B}\u{4E00}\u{7AE0}").font(.caption2)
                }
            }.disabled(currentChapterIndex >= chaptersCount - 1)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(Color(UIColor.systemBackground))
        .shadow(color: Color.black.opacity(0.1), radius: 5, y: -2)
    }
}

struct FontSizeSheet: View {
    @ObservedObject var preferences: UserPreferences
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text("\u{5B57}\u{4F53}\u{5927}\u{5C0F}: \(String(format: "%.0f", preferences.fontSize))")
                        .font(.headline)
                    Slider(value: $preferences.fontSize, in: 12...30, step: 1)
                }
                
                VStack(spacing: 8) {
                    Text("\u{5DE6}\u{53F3}\u{8FB9}\u{8DDD}: \(String(format: "%.0f", preferences.pageHorizontalMargin))")
                        .font(.headline)
                    Slider(value: $preferences.pageHorizontalMargin, in: 0...50, step: 1)
                }

                VStack(spacing: 8) {
                    Text("\u{7FFB}\u{9875}\u{95F4}\u{8DDD}: \(String(format: "%.0f", preferences.pageInterSpacing))")
                        .font(.headline)
                    Slider(value: $preferences.pageInterSpacing, in: 0...30, step: 1)
                }

                Toggle("播放时锁定翻页", isOn: $preferences.lockPageOnTTS)
                    .padding(.top)

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
