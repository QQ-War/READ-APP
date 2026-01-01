import SwiftUI
import UIKit

// MARK: - Core Types
private struct PaginatedPage {
    let globalRange: NSRange
    let startSentenceIndex: Int
}

private struct TK2PageInfo {
    let range: NSRange
    let yOffset: CGFloat
    let pageHeight: CGFloat // Allocated page height (e.g., pageSize.height)
    let actualContentHeight: CGFloat // Actual height used by content on this page
    let startSentenceIndex: Int
    let contentInset: CGFloat
}

private struct ChapterCache {
    let pages: [PaginatedPage]
    let renderStore: TextKit2RenderStore?
    let pageInfos: [TK2PageInfo]?
    let contentSentences: [String]
    let rawContent: String
    let attributedText: NSAttributedString
    let paragraphStarts: [Int]
    let chapterPrefixLen: Int
    let isFullyPaginated: Bool
    
    static var empty: ChapterCache {
        ChapterCache(pages: [], renderStore: nil, pageInfos: nil, contentSentences: [], rawContent: "", attributedText: NSAttributedString(), paragraphStarts: [], chapterPrefixLen: 0, isFullyPaginated: false)
    }
}



private final class ReadContentViewControllerCache: ObservableObject {
    struct Key: Hashable {
        let storeID: ObjectIdentifier
        let pageIndex: Int
        let chapterOffset: Int
    }

    private var controllers: [Key: ReadContentViewController] = [:]

    func controller(
        for store: TextKit2RenderStore,
        pageIndex: Int,
        chapterOffset: Int,
        builder: () -> ReadContentViewController
    ) -> ReadContentViewController {
        let key = Key(storeID: ObjectIdentifier(store), pageIndex: pageIndex, chapterOffset: chapterOffset)
        if let cached = controllers[key] {
            return cached
        }
        let controller = builder()
        controllers[key] = controller
        return controller
    }

    func retainActive(stores: [TextKit2RenderStore?]) {
        let activeIDs = Set(stores.compactMap { $0.map { ObjectIdentifier($0) } })
        if activeIDs.isEmpty {
            controllers.removeAll()
            return
        }
        controllers = controllers.filter { activeIDs.contains($0.key.storeID) }
    }
}

private struct PageSnapshot {
    let pages: [PaginatedPage]
    let renderStore: TextKit2RenderStore?
    let pageInfos: [TK2PageInfo]?
}

// MARK: - ReadingView
enum ReaderTapLocation {
    case left, right, middle
}

struct ReadingView: View {
    let book: Book
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var apiService: APIService
    @StateObject private var ttsManager = TTSManager.shared
    @StateObject private var preferences = UserPreferences.shared
    @StateObject private var replaceRuleViewModel = ReplaceRuleViewModel()

    // Chapter and Content State
    @State private var chapters: [BookChapter] = []
    @State private var currentChapterIndex: Int
    @State private var rawContent = ""
    @State private var currentContent = ""
    @State private var contentSentences: [String] = []
    
    // UI State
    @State private var isLoading = false
    @State private var showChapterList = false
    @State private var errorMessage: String?
    @State private var showUIControls = false
    @State private var showFontSettings = false
    
    // Reading Progress & Position
    @State private var pendingResumePos: Double?
    @State private var pendingResumeCharIndex: Int?
    @State private var pendingResumeLocalBodyIndex: Int?
    @State private var pendingResumeLocalChapterIndex: Int?
    @State private var pendingResumeLocalPageIndex: Int?
    @State private var didApplyResumePos = false
    @State private var initialServerChapterIndex: Int?
    @State private var didEnterReadingSession = false
    @State private var shouldApplyResumeOnce = false
    @State private var shouldSyncPageAfterPagination = false

    // Vertical (Scrolling) Reader State
    @State private var scrollProxy: ScrollViewProxy?
    @State private var currentVisibleSentenceIndex: Int?
    @State private var pendingScrollToSentenceIndex: Int?

    // Horizontal (Paging) Reader State
    @State private var currentPageIndex: Int = 0
    @State private var currentCache: ChapterCache = .empty
    @State private var prevCache: ChapterCache = .empty
    @State private var nextCache: ChapterCache = .empty
    @State private var pendingJumpToLastPage = false
    @State private var pendingJumpToFirstPage = false
    @State private var pageSize: CGSize = .zero
    @State private var isPageTransitioning = false
    @State private var pendingBufferPageIndex: Int?
    @State private var lastHandledPageIndex: Int?
    @StateObject private var contentControllerCache = ReadContentViewControllerCache()
    @State private var hasInitialPagination = false
    
    // Repagination Control
    @State private var isRepaginateQueued = false
    @State private var lastPaginationKey: PaginationKey?
    @State private var suppressRepaginateOnce = false
    
    // TTS State
    @State private var lastTTSSentenceIndex: Int?
    @State private var ttsBaseIndex: Int = 0
    @State private var pendingFlipId: UUID = UUID()
    @State private var isTTSSyncingPage = false
    @State private var suppressTTSSync = false
    @State private var suppressPageIndexChangeOnce = false
    @State private var isAutoFlipping: Bool = false
    @State private var isTTSAutoChapterChange = false
    @State private var pausedChapterIndex: Int?
    @State private var pausedPageIndex: Int?
    @State private var needsTTSRestartAfterPause = false
    @State private var lastAdjacentPrepareAt: TimeInterval = 0
    @State private var pendingTTSRequest: TTSPlayRequest?
    
    // Replace Rule State
    @State private var showAddReplaceRule = false
    @State private var pendingReplaceRule: ReplaceRule?

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
    
    private struct TTSPlayRequest {
        let pageIndexOverride: Int?
        let showControls: Bool
    }

    init(book: Book) {
        self.book = book
        let serverIndex = book.durChapterIndex ?? 0
        let localProgress = book.bookUrl.flatMap { UserPreferences.shared.getReadingProgress(bookUrl: $0) }
        
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

    // MARK: - Body
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
        .sheet(isPresented: $showChapterList) { ChapterListView(chapters: chapters, currentIndex: currentChapterIndex) { index in
            currentChapterIndex = index
            pendingJumpToFirstPage = true
            loadChapterContent()
            showChapterList = false
        } }
        .sheet(isPresented: $showFontSettings) { FontSizeSheet(preferences: preferences) }
        .sheet(isPresented: $showAddReplaceRule) { ReplaceRuleEditView(viewModel: replaceRuleViewModel, rule: pendingReplaceRule) }
        .onChange(of: showAddReplaceRule) { value in if !value { pendingReplaceRule = nil } }
        .task {
            await loadChapters()
            await replaceRuleViewModel.fetchRules()
            enterReadingSessionIfNeeded()
        }
        .onChange(of: replaceRuleViewModel.rules) { _ in updateProcessedContent(from: rawContent) }
        .onChange(of: pendingScrollToSentenceIndex) { _ in handlePendingScroll() }
        .alert("错误", isPresented: .constant(errorMessage != nil)) { Button("确定") { errorMessage = nil } } message: {
            if let error = errorMessage { Text(error) }
        }
        .onDisappear { saveProgress() }
        .onChange(of: ttsManager.isPlaying) { handleTTSPlayStateChange($0) }
        .onChange(of: ttsManager.isPaused) { handleTTSPauseStateChange($0) }
        .onChange(of: ttsManager.currentSentenceIndex) { _ in handleTTSSentenceChange() }
        .onChange(of: ttsManager.currentSentenceDuration) { _ in handleTTSSentenceChange() }
        .onChange(of: scenePhase) { handleScenePhaseChange($0) }
    }

    // MARK: - UI Components
    
    private var backgroundView: some View { Color(UIColor.systemBackground) }

    @ViewBuilder
    private func mainContent(safeArea: EdgeInsets) -> some View {
        if preferences.readingMode == .horizontal {
            horizontalReader(safeArea: safeArea)
        } else {
            verticalReader.padding(.top, safeArea.top).padding(.bottom, safeArea.bottom)
        }
    }
    
    private var verticalReader: some View {
        GeometryReader {
            geometry in
            ScrollViewReader {
                proxy in
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
                .onTapGesture { handleReaderTap(location: .middle) }
                .onChange(of: ttsManager.currentSentenceIndex) { newIndex in
                    if ttsManager.isPlaying, !contentSentences.isEmpty {
                        withAnimation { proxy.scrollTo(newIndex, anchor: .center) }
                    }
                }
                .onPreferenceChange(SentenceFramePreferenceKey.self) { updateVisibleSentenceIndex(frames: $0, viewportHeight: geometry.size.height) }
                .onAppear {
                    scrollProxy = proxy
                    handlePendingScroll()
                }
            }
        }
    }
    
    private func horizontalReader(safeArea: EdgeInsets) -> some View {
        GeometryReader {
            geometry in
            let horizontalMargin: CGFloat = preferences.pageHorizontalMargin
            let verticalMargin: CGFloat = 10
            
            let availableSize = CGSize(
                width: max(0, geometry.size.width - safeArea.leading - safeArea.trailing - horizontalMargin * 2),
                height: max(0, geometry.size.height - safeArea.top - safeArea.bottom - verticalMargin * 2)
            )

            let contentSize = availableSize
            horizontalReaderBody(geometry: geometry, safeArea: safeArea, availableSize: availableSize, contentSize: contentSize)
            .onAppear { if contentSize.width > 0 { scheduleRepaginate(in: contentSize) } }
            .onChange(of: contentSentences) { _ in if contentSize.width > 0 { scheduleRepaginate(in: contentSize) } }
            .onChange(of: preferences.fontSize) { _ in if contentSize.width > 0 { scheduleRepaginate(in: contentSize) } }
            .onChange(of: preferences.lineSpacing) { _ in if contentSize.width > 0 { scheduleRepaginate(in: contentSize) } }
            .onChange(of: preferences.pageHorizontalMargin) { _ in if contentSize.width > 0 { scheduleRepaginate(in: contentSize) } }
            .onChange(of: geometry.size) { _ in if contentSize.width > 0 { scheduleRepaginate(in: contentSize) } }
            .onChange(of: currentPageIndex) { newIndex in
                if isTTSSyncingPage {
                    isTTSSyncingPage = false
                    if let startIndex = pageStartSentenceIndex(for: newIndex) { lastTTSSentenceIndex = startIndex }
                    return
                }
                handlePageIndexChange(newIndex)
            }
        }
    }

    private func horizontalReaderBody(geometry: GeometryProxy, safeArea: EdgeInsets, availableSize: CGSize, contentSize: CGSize) -> some View {
        VStack(spacing: 0) {
            Spacer().frame(height: safeArea.top + 10)
            HStack(spacing: 0) {
                Color.clear.frame(width: safeArea.leading + preferences.pageHorizontalMargin).contentShape(Rectangle()).onTapGesture { handleReaderTap(location: .left) }
                
                if availableSize.width > 0 {
                    if hasInitialPagination {
                        ZStack(alignment: .bottomTrailing) {
                            cacheRefresher
                            let currentVC = makeContentViewController(snapshot: snapshot(from: currentCache), pageIndex: currentPageIndex, chapterOffset: 0)
                            let prevVC = makeContentViewController(snapshot: snapshot(from: prevCache), pageIndex: max(0, prevCache.pages.count - 1), chapterOffset: -1)
                            let nextVC = makeContentViewController(snapshot: snapshot(from: nextCache), pageIndex: 0, chapterOffset: 1)

                            ReadPageViewController(
                                snapshot: PageSnapshot(pages: currentCache.pages, renderStore: currentCache.renderStore, pageInfos: currentCache.pageInfos),
                                prevSnapshot: PageSnapshot(pages: prevCache.pages, renderStore: prevCache.renderStore, pageInfos: prevCache.pageInfos),
                                nextSnapshot: PageSnapshot(pages: nextCache.pages, renderStore: nextCache.renderStore, pageInfos: nextCache.pageInfos),
                                currentPageIndex: $currentPageIndex,
                                pageSpacing: preferences.pageInterSpacing,
                                onTransitioningChanged: { self.isPageTransitioning = $0 },
                                onTapLocation: handleReaderTap,
                                onChapterChange: { offset in self.isAutoFlipping = true; self.handleChapterSwitch(offset: offset) },
                                onAdjacentPrefetch: { offset in
                                    let needsPrepare = offset > 0 ? nextCache.pages.isEmpty : prevCache.pages.isEmpty
                                    if needsPrepare { prepareAdjacentChapters(for: currentChapterIndex) }
                                },
                                onAddReplaceRule: presentReplaceRuleEditor,
                                currentContentViewController: currentVC,
                                prevContentViewController: prevVC,
                                nextContentViewController: nextVC,
                                makeViewController: makeContentViewController
                            )
                            .id(preferences.pageInterSpacing)
                            .frame(width: contentSize.width, height: contentSize.height)

                            if !showUIControls && currentCache.pages.count > 0 {
                                let displayCurrent = currentPageIndex + 1
                                Group {
                                    if currentCache.isFullyPaginated {
                                        let total = max(currentCache.pages.count, displayCurrent)
                                        Text("\(displayCurrent)/\(total) (\(Int((Double(displayCurrent) / Double(total)) * 100))%)")
                                    } else if let range = pageRange(for: currentPageIndex), currentCache.attributedText.length > 0 {
                                        let progress = Double(NSMaxRange(range)) / Double(currentCache.attributedText.length)
                                        Text("\(displayCurrent)/\(currentCache.pages.count)+ (\(Int(progress * 100))%)")
                                    } else {
                                        Text("\(displayCurrent)/\(currentCache.pages.count)+")
                                    }
                                }
                                .font(.caption2).foregroundColor(.secondary).padding(.trailing, 8).padding(.bottom, 2)
                                .transition(.opacity.animation(.easeInOut(duration: 0.3)))
                            }
                        }
                        .frame(width: availableSize.width, height: availableSize.height)
                    } else {
                        Color.clear.frame(width: contentSize.width, height: contentSize.height)
                    }
                } else {
                    Rectangle().fill(Color.clear)
                }
                
                Color.clear.frame(width: safeArea.trailing + preferences.pageHorizontalMargin).contentShape(Rectangle()).onTapGesture { handleReaderTap(location: .right) }
            }
            Spacer().frame(height: safeArea.bottom + 10)
        }
        .frame(width: geometry.size.width, height: geometry.size.height)
    }
    
    @ViewBuilder private func topBar(safeArea: EdgeInsets) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button("返回") { dismiss() }
                VStack(alignment: .leading, spacing: 2) {
                    Text(book.name ?? "阅读").font(.headline).fontWeight(.bold).lineLimit(1)
                    Text(chapters.indices.contains(currentChapterIndex) ? chapters[currentChapterIndex].title : "未知章节").font(.caption).foregroundColor(.secondary).lineLimit(1)
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
    
    private var loadingOverlay: some View { ProgressView("加载中...").padding().background(Material.regular).cornerRadius(10).shadow(radius: 10) }

    @ViewBuilder private var controlBar: some View {
        if ttsManager.isPlaying && !contentSentences.isEmpty {
            TTSControlBar(ttsManager: ttsManager, currentChapterIndex: currentChapterIndex, chaptersCount: chapters.count, onPreviousChapter: previousChapter, onNextChapter: nextChapter, onShowChapterList: { showChapterList = true }, onTogglePlayPause: toggleTTS)
        } else {
            NormalControlBar(currentChapterIndex: currentChapterIndex, chaptersCount: chapters.count, onPreviousChapter: previousChapter, onNextChapter: nextChapter, onShowChapterList: { showChapterList = true }, onToggleTTS: toggleTTS, onShowFontSettings: { showFontSettings = true })
        }
    }

    // MARK: - Event Handlers
    
    private func handlePendingScroll() {
        guard preferences.readingMode != .horizontal, let index = pendingScrollToSentenceIndex, let proxy = scrollProxy else { return }
        withAnimation { proxy.scrollTo(index, anchor: .center) }
        pendingScrollToSentenceIndex = nil
    }
    
    private func handleTTSPlayStateChange(_ isPlaying: Bool) {
        if !isPlaying {
            showUIControls = true
            if ttsManager.currentSentenceIndex > 0 && ttsManager.currentSentenceIndex <= contentSentences.count {
                lastTTSSentenceIndex = ttsManager.currentSentenceIndex
            }
        }
    }
    
    private func handleTTSPauseStateChange(_ isPaused: Bool) {
        if isPaused {
            pausedChapterIndex = currentChapterIndex
            pausedPageIndex = currentPageIndex
            needsTTSRestartAfterPause = false
        } else {
            needsTTSRestartAfterPause = false
        }
    }
    
    private func handleTTSSentenceChange() {
        if preferences.readingMode == .horizontal && ttsManager.isPlaying {
            if !suppressTTSSync { syncPageForSentenceIndex(ttsManager.currentSentenceIndex) }
            scheduleAutoFlip(duration: ttsManager.currentSentenceDuration)
            suppressTTSSync = false
        }
    }

    private func handleScenePhaseChange(_ phase: ScenePhase) {
        if phase == .active {
            syncUIToTTSProgressIfNeeded()
        }
    }

    private func syncUIToTTSProgressIfNeeded() {
        guard ttsManager.isPlaying, ttsManager.bookUrl == book.bookUrl else { return }
        ttsBaseIndex = ttsManager.currentBaseSentenceIndex
        let targetChapter = ttsManager.currentChapterIndex

        if targetChapter != currentChapterIndex {
            if switchChapterUsingCacheIfAvailable(targetIndex: targetChapter, jumpToFirst: false, jumpToLast: false) {
                syncPageForSentenceIndex(ttsManager.currentSentenceIndex)
            } else {
                currentChapterIndex = targetChapter
                shouldSyncPageAfterPagination = true
                loadChapterContent()
            }
            return
        }

        if preferences.readingMode == .horizontal {
            syncPageForSentenceIndex(ttsManager.currentSentenceIndex)
        } else {
            pendingScrollToSentenceIndex = ttsManager.currentSentenceIndex
            handlePendingScroll()
        }
    }
    
    private var cacheRefresher: some View {
        Group {
            let stores: [TextKit2RenderStore?] = [currentCache.renderStore, prevCache.renderStore, nextCache.renderStore]
            let _ = contentControllerCache.retainActive(stores: stores)
        }
        .frame(width: 0, height: 0)
    }

    // MARK: - Pagination & Navigation
    
    private func repaginateContent(in size: CGSize, with newContentSentences: [String]? = nil) {
        let sentences = newContentSentences ?? contentSentences
        let chapterTitle = chapters.indices.contains(currentChapterIndex) ? chapters[currentChapterIndex].title : nil

        let newAttrText = TextKitPaginator.createAttributedText(sentences: sentences, fontSize: preferences.fontSize, lineSpacing: preferences.lineSpacing, chapterTitle: chapterTitle)
        let newPStarts = TextKitPaginator.paragraphStartIndices(sentences: sentences)
        let newPrefixLen = (chapterTitle?.isEmpty ?? true) ? 0 : (chapterTitle! + "\n").utf16.count
        
        guard newAttrText.length > 0, size.width > 0, size.height > 0 else {
            currentCache = .empty
            return
        }

        let resumeCharIndex = pendingResumeCharIndex
        let shouldJumpToFirst = pendingJumpToFirstPage
        let shouldJumpToLast = pendingJumpToLastPage
        let focusCharIndex: Int? = (shouldJumpToFirst || shouldJumpToLast)
            ? nil
            : (currentCache.pages.indices.contains(currentPageIndex) ? currentCache.pages[currentPageIndex].globalRange.location : resumeCharIndex)

        let tk2Store: TextKit2RenderStore
        if let existingStore = currentCache.renderStore, existingStore.layoutWidth == size.width {
            existingStore.update(attributedString: newAttrText, layoutWidth: size.width)
            tk2Store = existingStore
        } else {
            tk2Store = TextKit2RenderStore(attributedString: newAttrText, layoutWidth: size.width)
        }
        
        let inset = max(8, min(18, preferences.fontSize * 0.6))
        let result = TextKit2Paginator.paginate(renderStore: tk2Store, pageSize: size, paragraphStarts: newPStarts, prefixLen: newPrefixLen, contentInset: inset)
        
        if shouldJumpToLast {
            currentPageIndex = max(0, result.pages.count - 1)
        } else if shouldJumpToFirst {
            currentPageIndex = 0
        } else if let targetCharIndex = focusCharIndex, let pageIndex = pageIndexForChar(targetCharIndex, in: result.pages) {
            currentPageIndex = pageIndex
        } else if currentCache.pages.isEmpty {
            currentPageIndex = 0
        }
        pendingJumpToLastPage = false
        pendingJumpToFirstPage = false
        
        if result.pages.isEmpty { currentPageIndex = 0 }
        else if currentPageIndex >= result.pages.count { currentPageIndex = result.pages.count - 1 }
        
        currentCache = ChapterCache(pages: result.pages, renderStore: tk2Store, pageInfos: result.pageInfos, contentSentences: sentences, rawContent: rawContent, attributedText: newAttrText, paragraphStarts: newPStarts, chapterPrefixLen: newPrefixLen, isFullyPaginated: true)
        if !hasInitialPagination, !result.pages.isEmpty { hasInitialPagination = true }
        
        if let localPage = pendingResumeLocalPageIndex, pendingResumeLocalChapterIndex == currentChapterIndex, result.pages.indices.contains(localPage) {
            currentPageIndex = localPage
            pendingResumeLocalPageIndex = nil
        }
        if resumeCharIndex != nil { pendingResumeCharIndex = nil }
        triggerAdjacentPrefetchIfNeeded(force: true)
    }

    private func pageIndexForChar(_ index: Int, in pages: [PaginatedPage]) -> Int? {
        guard index >= 0 else { return nil }
        return pages.firstIndex(where: { NSLocationInRange(index, $0.globalRange) })
    }

    private func triggerAdjacentPrefetchIfNeeded(force: Bool = false) {
        guard pageSize.width > 0, pageSize.height > 0 else { return }
        let now = Date().timeIntervalSince1970
        if !force, now - lastAdjacentPrepareAt < 1.0 { return }
        if (currentChapterIndex > 0 && prevCache.pages.isEmpty) || (currentChapterIndex < chapters.count - 1 && nextCache.pages.isEmpty) {
            lastAdjacentPrepareAt = now
            prepareAdjacentChapters(for: currentChapterIndex)
        }
    }

    private func ensurePagesForCharIndex(_ index: Int) -> Int? {
        return pageIndexForChar(index, in: currentCache.pages)
    }
    
    private func goToPreviousPage() {
        if currentPageIndex > 0 { currentPageIndex -= 1 }
        else if currentChapterIndex > 0 {
            pendingJumpToLastPage = true
            previousChapter()
        }
    }

    private func goToNextPage() {
        if currentPageIndex < currentCache.pages.count - 1 { currentPageIndex += 1 }
        else if currentChapterIndex < chapters.count - 1 {
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
        case .left: goToPreviousPage()
        case .right: goToNextPage()
        case .middle: showUIControls = true
        }
    }

    private func handlePageIndexChange(_ newIndex: Int) {
        if suppressPageIndexChangeOnce {
            suppressPageIndexChangeOnce = false
            return
        }
        pendingBufferPageIndex = newIndex
        processPendingPageChangeIfReady()
    }

    private func processPendingPageChangeIfReady() {
        guard !isPageTransitioning, let newIndex = pendingBufferPageIndex else { return }
        if lastHandledPageIndex == newIndex { return }
        
        pendingBufferPageIndex = nil
        lastHandledPageIndex = newIndex

        if newIndex <= 1 || newIndex >= max(0, currentCache.pages.count - 2) {
            triggerAdjacentPrefetchIfNeeded()
        }

        if ttsManager.isPlaying && !ttsManager.isPaused && !isAutoFlipping {
            if !preferences.lockPageOnTTS {
                requestTTSPlayback(pageIndexOverride: newIndex, showControls: false)
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

    private func requestTTSPlayback(pageIndexOverride: Int?, showControls: Bool) {
        if contentSentences.isEmpty {
            pendingTTSRequest = TTSPlayRequest(pageIndexOverride: pageIndexOverride, showControls: showControls)
            return
        }
        ttsManager.stop()
        startTTS(pageIndexOverride: pageIndexOverride, showControls: showControls)
    }

    private func makeContentViewController(snapshot: PageSnapshot, pageIndex: Int, chapterOffset: Int) -> ReadContentViewController? {
        guard let store = snapshot.renderStore, let infos = snapshot.pageInfos, pageIndex >= 0, pageIndex < infos.count else { return nil }

        let vc = contentControllerCache.controller(for: store, pageIndex: pageIndex, chapterOffset: chapterOffset) {
            ReadContentViewController(
                pageIndex: pageIndex, renderStore: store, chapterOffset: chapterOffset,
                onAddReplaceRule: { selectedText in presentReplaceRuleEditor(selectedText: selectedText) },
                onTapLocation: { location in handleReaderTap(location: location) }
            )
        }
        vc.configureTK2Page(info: infos[pageIndex])
        return vc
    }

    private func snapshot(from cache: ChapterCache) -> PageSnapshot {
        PageSnapshot(pages: cache.pages, renderStore: cache.renderStore, pageInfos: cache.pageInfos)
    }

    private func scheduleRepaginate(in size: CGSize) {
        pageSize = size
        let key = PaginationKey(width: Int(size.width * 100), height: Int(size.height * 100), fontSize: Int(preferences.fontSize * 10), lineSpacing: Int(preferences.lineSpacing * 10), margin: Int(preferences.pageHorizontalMargin * 10), sentenceCount: contentSentences.count, chapterIndex: currentChapterIndex, resumeCharIndex: pendingResumeCharIndex ?? -1, resumePageIndex: pendingResumeLocalPageIndex ?? -1)

        if suppressRepaginateOnce {
            suppressRepaginateOnce = false
            lastPaginationKey = key
            return
        }
        
        if key == lastPaginationKey { return }
        lastPaginationKey = key
        if isRepaginateQueued { return }
        
        isRepaginateQueued = true
        DispatchQueue.main.async {
            self.repaginateContent(in: size)
            self.isRepaginateQueued = false
        }
    }

    private func pageRange(for pageIndex: Int) -> NSRange? {
        guard currentCache.pages.indices.contains(pageIndex) else { return nil }
        return currentCache.pages[pageIndex].globalRange
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

    private func pageIndexForSentence(_ index: Int) -> Int? {
        guard let charIndex = globalCharIndexForSentence(index) else { return nil }
        return currentCache.pages.firstIndex { NSLocationInRange(charIndex, $0.globalRange) }
    }

    private func syncPageForSentenceIndex(_ index: Int) {
        guard index >= 0, preferences.readingMode == .horizontal else { return }
        let realIndex = index + ttsBaseIndex
        
        if currentCache.pages.indices.contains(currentPageIndex), let sentenceStart = globalCharIndexForSentence(realIndex) {
            let pageRange = currentCache.pages[currentPageIndex].globalRange
            let sentenceLen = contentSentences.indices.contains(realIndex) ? contentSentences[realIndex].utf16.count : 0
            let sentenceRange = NSRange(location: sentenceStart, length: sentenceLen)
            if (sentenceLen > 0 && NSIntersectionRange(sentenceRange, pageRange).length > 0) || NSLocationInRange(sentenceStart, pageRange) { return }
        }

        if let pageIndex = pageIndexForSentence(realIndex) ?? (globalCharIndexForSentence(realIndex).flatMap { ensurePagesForCharIndex($0) }), pageIndex != currentPageIndex {
            isTTSSyncingPage = true
            withAnimation { currentPageIndex = pageIndex }
            DispatchQueue.main.async { self.isTTSSyncingPage = false }
        }
    }
    
    private func scheduleAutoFlip(duration: TimeInterval) {
        guard duration > 0, ttsManager.isPlaying, preferences.readingMode == .horizontal else { return }
        
        pendingFlipId = UUID()
        let taskId = pendingFlipId
        let realIndex = ttsManager.currentSentenceIndex + ttsBaseIndex
        
        guard currentCache.pages.indices.contains(currentPageIndex), let sentenceStart = globalCharIndexForSentence(realIndex) else { return }
        let sentenceLen = contentSentences.indices.contains(realIndex) ? contentSentences[realIndex].utf16.count : 0
        guard sentenceLen > 0 else { return }
        
        let sentenceRange = NSRange(location: sentenceStart, length: sentenceLen)
        let pageRange = currentCache.pages[currentPageIndex].globalRange
        let intersection = NSIntersectionRange(sentenceRange, pageRange)
        
        if sentenceStart >= pageRange.location, NSMaxRange(sentenceRange) > NSMaxRange(pageRange), intersection.length > 0 {
            let delay = duration * (Double(intersection.length) / Double(sentenceLen))
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                if self.pendingFlipId == taskId {
                    self.isAutoFlipping = true
                    self.goToNextPage()
                }
            }
        }
    }
    
    private func prepareAdjacentChapters(for chapterIndex: Int) {
        guard pageSize.width > 0, pageSize.height > 0 else { return }
        
        let nextIndex = chapterIndex + 1
        if nextIndex < chapters.count {
            Task { if let cache = await paginateChapter(at: nextIndex, forGate: true) { await MainActor.run { self.nextCache = cache } } }
        } else { nextCache = .empty }
        
        let prevIndex = chapterIndex - 1
        if prevIndex >= 0 {
            Task { if let cache = await paginateChapter(at: prevIndex, forGate: true, fromEnd: true) { await MainActor.run { self.prevCache = cache } } }
        } else { prevCache = .empty }
    }

    private func prepareAdjacentChaptersIfNeeded(for chapterIndex: Int) {
        guard pageSize.width > 0, pageSize.height > 0 else { return }
        
        let nextIndex = chapterIndex + 1
        if nextIndex < chapters.count, nextCache.pages.isEmpty {
            Task { if let cache = await paginateChapter(at: nextIndex, forGate: true) { await MainActor.run { self.nextCache = cache } } }
        }
        
        let prevIndex = chapterIndex - 1
        if prevIndex >= 0, prevCache.pages.isEmpty {
            Task { if let cache = await paginateChapter(at: prevIndex, forGate: true, fromEnd: true) { await MainActor.run { self.prevCache = cache } } }
        }
    }

    private func switchChapterUsingCacheIfAvailable(targetIndex: Int, jumpToFirst: Bool, jumpToLast: Bool) -> Bool {
        if targetIndex == currentChapterIndex + 1, !nextCache.pages.isEmpty {
            let cached = nextCache
            prevCache = currentCache
            nextCache = .empty
            applyCachedChapter(cached, chapterIndex: targetIndex, jumpToFirst: jumpToFirst, jumpToLast: jumpToLast)
            ttsBaseIndex = 0
            prepareAdjacentChaptersIfNeeded(for: currentChapterIndex)
            return true
        }
        if targetIndex == currentChapterIndex - 1, !prevCache.pages.isEmpty {
            let cached = prevCache
            nextCache = currentCache
            prevCache = .empty
            applyCachedChapter(cached, chapterIndex: targetIndex, jumpToFirst: jumpToFirst, jumpToLast: jumpToLast)
            ttsBaseIndex = 0
            prepareAdjacentChaptersIfNeeded(for: currentChapterIndex)
            return true
        }
        return false
    }

    private func applyCachedChapter(_ cache: ChapterCache, chapterIndex: Int, jumpToFirst: Bool, jumpToLast: Bool) {
        suppressRepaginateOnce = true
        currentChapterIndex = chapterIndex
        currentCache = cache
        rawContent = cache.rawContent
        currentContent = cache.contentSentences.joined(separator: "\n")
        contentSentences = cache.contentSentences
        currentVisibleSentenceIndex = nil
        pendingScrollToSentenceIndex = nil
        if jumpToLast {
            currentPageIndex = max(0, cache.pages.count - 1)
        } else if jumpToFirst {
            currentPageIndex = 0
        }
        if cache.pages.isEmpty { currentPageIndex = 0 }
        pendingJumpToFirstPage = false
        pendingJumpToLastPage = false
    }

    private func continuePaginatingCurrentChapterIfNeeded() {
        guard !currentCache.isFullyPaginated,
              let store = currentCache.renderStore,
              let lastPage = currentCache.pages.last,
              pageSize.width > 0, pageSize.height > 0 else { return }
        
        let startOffset = NSMaxRange(lastPage.globalRange)
        let inset = currentCache.pageInfos?.first?.contentInset ?? max(8, min(18, preferences.fontSize * 0.6))
        let result = TextKit2Paginator.paginate(
            renderStore: store,
            pageSize: pageSize,
            paragraphStarts: currentCache.paragraphStarts,
            prefixLen: currentCache.chapterPrefixLen,
            contentInset: inset,
            maxPages: Int.max,
            startOffset: startOffset
        )
        
        if result.pages.isEmpty {
            currentCache = ChapterCache(
                pages: currentCache.pages,
                renderStore: store,
                pageInfos: currentCache.pageInfos,
                contentSentences: currentCache.contentSentences,
                rawContent: currentCache.rawContent,
                attributedText: currentCache.attributedText,
                paragraphStarts: currentCache.paragraphStarts,
                chapterPrefixLen: currentCache.chapterPrefixLen,
                isFullyPaginated: result.reachedEnd
            )
            return
        }
        
        let newPages = currentCache.pages + result.pages
        let newInfos = (currentCache.pageInfos ?? []) + result.pageInfos
        currentCache = ChapterCache(
            pages: newPages,
            renderStore: store,
            pageInfos: newInfos,
            contentSentences: currentCache.contentSentences,
            rawContent: currentCache.rawContent,
            attributedText: currentCache.attributedText,
            paragraphStarts: currentCache.paragraphStarts,
            chapterPrefixLen: currentCache.chapterPrefixLen,
            isFullyPaginated: result.reachedEnd
        )
    }

    private func handleChapterSwitch(offset: Int) {
        pendingFlipId = UUID()
        didApplyResumePos = true // Mark as true to prevent auto-resuming from server/local storage
        let shouldContinuePlaying = ttsManager.isPlaying && !ttsManager.isPaused && ttsManager.bookUrl == book.bookUrl
        
        if offset == 1 {
            guard !nextCache.pages.isEmpty else {
                currentChapterIndex += 1
                loadChapterContent()
                return
            }
            let cached = nextCache
            let nextIndex = currentChapterIndex + 1
            prevCache = currentCache
            nextCache = .empty
            applyCachedChapter(cached, chapterIndex: nextIndex, jumpToFirst: true, jumpToLast: false)
            ttsBaseIndex = 0
            prepareAdjacentChaptersIfNeeded(for: currentChapterIndex)
            if shouldContinuePlaying {
                lastTTSSentenceIndex = 0
                requestTTSPlayback(pageIndexOverride: currentPageIndex, showControls: false)
            }
            return
        } else if offset == -1 {
            guard !prevCache.pages.isEmpty else {
                currentChapterIndex -= 1
                loadChapterContent()
                return
            }
            let cached = prevCache
            let prevIndex = currentChapterIndex - 1
            nextCache = currentCache
            prevCache = .empty
            applyCachedChapter(cached, chapterIndex: prevIndex, jumpToFirst: false, jumpToLast: true)
            ttsBaseIndex = 0
            prepareAdjacentChaptersIfNeeded(for: currentChapterIndex)
            if shouldContinuePlaying {
                lastTTSSentenceIndex = max(0, currentCache.paragraphStarts.count - 1)
                requestTTSPlayback(pageIndexOverride: currentPageIndex, showControls: false)
            }
            return
        }
        loadChapterContent()
    }
    
    private func repaginateCurrentChapterWindow(sentences: [String]? = nil) {
        guard pageSize.width > 0, pageSize.height > 0 else { return }
        
        if let sentences = sentences, !sentences.isEmpty {
            repaginateContent(in: pageSize, with: sentences)
            return
        }
        guard !rawContent.isEmpty else { return }
        repaginateContent(in: pageSize, with: splitIntoParagraphs(applyReplaceRules(to: rawContent)))
    }

    private func paginateChapter(at index: Int, forGate: Bool, fromEnd: Bool = false) async -> ChapterCache? {
        guard let content = try? await apiService.fetchChapterContent(bookUrl: book.bookUrl ?? "", bookSourceUrl: book.origin, index: index) else { return nil }
        
        let cleaned = removeHTMLAndSVG(content)
        let processed = applyReplaceRules(to: cleaned)
        let sentences = splitIntoParagraphs(processed)
        let title = chapters[index].title
        
        let attrText = TextKitPaginator.createAttributedText(sentences: sentences, fontSize: preferences.fontSize, lineSpacing: preferences.lineSpacing, chapterTitle: title)
        let pStarts = TextKitPaginator.paragraphStartIndices(sentences: sentences)
        let prefixLen = (title.isEmpty) ? 0 : (title + "\n").utf16.count

        let tk2Store = TextKit2RenderStore(attributedString: attrText, layoutWidth: pageSize.width)
        let limit = Int.max
        
        let inset = max(8, min(18, preferences.fontSize * 0.6))
        let result = TextKit2Paginator.paginate(renderStore: tk2Store, pageSize: pageSize, paragraphStarts: pStarts, prefixLen: prefixLen, contentInset: inset, maxPages: limit)
        
        return ChapterCache(pages: result.pages, renderStore: tk2Store, pageInfos: result.pageInfos, contentSentences: sentences, rawContent: cleaned, attributedText: attrText, paragraphStarts: pStarts, chapterPrefixLen: prefixLen, isFullyPaginated: result.reachedEnd)
    }

    // MARK: - Logic & Actions
    
    private func updateProcessedContent(from rawText: String) {
        let processedContent = applyReplaceRules(to: rawText)
        let trimmedContent = processedContent.trimmingCharacters(in: .whitespacesAndNewlines)
        let isEffectivelyEmpty = trimmedContent.isEmpty
        let content = isEffectivelyEmpty ? "章节内容为空" : processedContent
        currentContent = content
        contentSentences = splitIntoParagraphs(content)
        
        if shouldApplyResumeOnce && !didApplyResumePos {
            applyResumeProgressIfNeeded(sentences: contentSentences)
            shouldApplyResumeOnce = false
        }
    }

    private func applyReplaceRules(to content: String) -> String {
        var processedContent = content
        for rule in replaceRuleViewModel.rules where rule.isEnabled == true {
            if let regex = try? NSRegularExpression(pattern: rule.pattern, options: .caseInsensitive) {
                processedContent = regex.stringByReplacingMatches(in: processedContent, range: NSRange(location: 0, length: processedContent.utf16.count), withTemplate: rule.replacement)
            }
        }
        return processedContent
    }

    private func applyResumeProgressIfNeeded(sentences: [String]) {
        guard !didApplyResumePos else { return }
        let hasLocalResume = pendingResumeLocalBodyIndex != nil && pendingResumeLocalChapterIndex == currentChapterIndex
        let pos = pendingResumePos ?? 0
        if !hasLocalResume && pos <= 0 { return }
        
        let chapterTitle = chapters.indices.contains(currentChapterIndex) ? chapters[currentChapterIndex].title : nil
        let prefixLen = (chapterTitle?.isEmpty ?? true) ? 0 : (chapterTitle! + "\n").utf16.count
        let paragraphStarts = TextKitPaginator.paragraphStartIndices(sentences: sentences)
        let bodyLength = (paragraphStarts.last ?? 0) + (sentences.last?.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count ?? 0)
        guard bodyLength > 0 else { return }

        let bodyIndex: Int
        if let localIndex = pendingResumeLocalBodyIndex, pendingResumeLocalChapterIndex == currentChapterIndex {
            bodyIndex = localIndex
            pendingResumeLocalBodyIndex = nil; pendingResumeLocalChapterIndex = nil; pendingResumeLocalPageIndex = nil
        } else {
            bodyIndex = pos > 1.0 ? Int(pos) : Int(Double(bodyLength) * min(max(pos, 0.0), 1.0))
        }
        let clampedBodyIndex = max(0, min(bodyIndex, max(0, bodyLength - 1)))
        pendingResumeCharIndex = clampedBodyIndex + prefixLen
        lastTTSSentenceIndex = paragraphStarts.lastIndex(where: { $0 <= clampedBodyIndex }) ?? 0
        pendingScrollToSentenceIndex = lastTTSSentenceIndex
        handlePendingScroll()
        didApplyResumePos = true
    }

    private func presentReplaceRuleEditor(selectedText: String) {
        let trimmed = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let shortName = trimmed.count > 12 ? String(trimmed.prefix(12)) + "..." : trimmed
        pendingReplaceRule = ReplaceRule(id: nil, name: "正文净化-\(shortName)", groupname: "", pattern: NSRegularExpression.escapedPattern(for: trimmed), replacement: "", scope: book.name ?? "", scopeTitle: false, scopeContent: true, excludeScope: "", isEnabled: true, isRegex: true, timeoutMillisecond: 3000, ruleorder: 0)
        showAddReplaceRule = true
    }

    private func removeHTMLAndSVG(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(of: "<svg[^>]*>.*?</svg>", with: "", options: [.regularExpression, .caseInsensitive])
        result = result.replacingOccurrences(of: "<img[^>]*>", with: "", options: [.regularExpression, .caseInsensitive])
        return result
    }
    
    private func splitIntoParagraphs(_ text: String) -> [String] {
        return text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
    
    private func loadChapters() async {
        isLoading = true
        defer { isLoading = false }
        do {
            chapters = try await apiService.fetchChapterList(bookUrl: book.bookUrl ?? "", bookSourceUrl: book.origin)
            if !chapters.indices.contains(currentChapterIndex) {
                currentChapterIndex = max(0, chapters.count - 1)
                pendingResumeLocalBodyIndex = nil
                pendingResumeLocalChapterIndex = nil
                if let fallback = initialServerChapterIndex, chapters.indices.contains(fallback) {
                    currentChapterIndex = fallback
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func enterReadingSessionIfNeeded() {
        guard !didEnterReadingSession else { return }
        didEnterReadingSession = true

        if ttsManager.isPlaying && ttsManager.bookUrl == book.bookUrl {
            currentChapterIndex = ttsManager.currentChapterIndex
            lastTTSSentenceIndex = ttsManager.currentSentenceIndex
            ttsBaseIndex = ttsManager.currentBaseSentenceIndex
            didApplyResumePos = true // Prevent local/server resume from overriding TTS position
            pendingResumeLocalBodyIndex = nil
            pendingResumeLocalChapterIndex = nil
            pendingResumeLocalPageIndex = nil
            pendingResumePos = nil
            shouldSyncPageAfterPagination = true
            loadChapterContent()
            return
        }

        shouldApplyResumeOnce = true
        loadChapterContent()
    }
    
    private func loadChapterContent() {
        guard chapters.indices.contains(currentChapterIndex) else { return }
        
        let chapterIndex = currentChapterIndex
        let chapterTitle = chapters[chapterIndex].title
        let targetPageSize = pageSize
        let fontSize = preferences.fontSize
        let lineSpacing = preferences.lineSpacing
        let margin = preferences.pageHorizontalMargin
        
        // Capture all necessary resume state
        let resumePos = pendingResumePos
        let resumeLocalBodyIndex = pendingResumeLocalBodyIndex
        let resumeLocalChapterIndex = pendingResumeLocalChapterIndex
        let resumeLocalPageIndex = pendingResumeLocalPageIndex
        let capturedTTSIndex = lastTTSSentenceIndex
        let jumpFirst = pendingJumpToFirstPage
        let jumpLast = pendingJumpToLastPage
        let shouldResume = shouldApplyResumeOnce
        
        if currentCache.pages.isEmpty { isLoading = true }
        
        Task {
            do {
                let content = try await apiService.fetchChapterContent(bookUrl: book.bookUrl ?? "", bookSourceUrl: book.origin, index: chapterIndex)
                
                // 1. Heavy processing on background thread
                let cleaned = removeHTMLAndSVG(content)
                let processed = applyReplaceRules(to: cleaned)
                let sentences = splitIntoParagraphs(processed)
                
                await MainActor.run {
                    guard self.currentChapterIndex == chapterIndex else { return }
                    
                    var initialCache: ChapterCache? = nil
                    var targetPageIndex = 0
                    
                    // 2. Pre-paginate on main thread (TextKit2 is not thread-safe)
                    if targetPageSize.width > 0 {
                        let attrText = TextKitPaginator.createAttributedText(sentences: sentences, fontSize: fontSize, lineSpacing: lineSpacing, chapterTitle: chapterTitle)
                        let pStarts = TextKitPaginator.paragraphStartIndices(sentences: sentences)
                        let prefixLen = (chapterTitle.isEmpty) ? 0 : (chapterTitle + "\n").utf16.count
                        let tk2Store = TextKit2RenderStore(attributedString: attrText, layoutWidth: targetPageSize.width)
                        let inset = max(8, min(18, fontSize * 0.6))
                        let result = TextKit2Paginator.paginate(renderStore: tk2Store, pageSize: targetPageSize, paragraphStarts: pStarts, prefixLen: prefixLen, contentInset: inset)
                        
                        initialCache = ChapterCache(pages: result.pages, renderStore: tk2Store, pageInfos: result.pageInfos, contentSentences: sentences, rawContent: cleaned, attributedText: attrText, paragraphStarts: pStarts, chapterPrefixLen: prefixLen, isFullyPaginated: result.reachedEnd)
                        
                        // Determine where to land
                        if jumpLast {
                            targetPageIndex = max(0, result.pages.count - 1)
                        } else if jumpFirst {
                            targetPageIndex = 0
                        } else if let ttsIdx = capturedTTSIndex, ttsIdx < pStarts.count {
                            // High Priority: Align with TTS progress if available
                            let charOffset = pStarts[ttsIdx] + prefixLen
                            targetPageIndex = result.pages.firstIndex(where: { NSLocationInRange(charOffset, $0.globalRange) }) ?? 0
                        } else if shouldResume {
                            let bodyLength = (pStarts.last ?? 0) + (sentences.last?.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count ?? 0)
                            let bodyIndex: Int
                            if let localIndex = resumeLocalBodyIndex, resumeLocalChapterIndex == chapterIndex {
                                bodyIndex = localIndex
                            } else if let pos = resumePos, pos > 0 {
                                bodyIndex = pos > 1.0 ? Int(pos) : Int(Double(bodyLength) * min(max(pos, 0.0), 1.0))
                            } else {
                                bodyIndex = 0
                            }
                            let clampedBodyIndex = max(0, min(bodyIndex, max(0, bodyLength - 1)))
                            let charIndex = clampedBodyIndex + prefixLen
                            
                            if let pageIdx = result.pages.firstIndex(where: { NSLocationInRange(charIndex, $0.globalRange) }) {
                                targetPageIndex = pageIdx
                            } else if let localPage = resumeLocalPageIndex, resumeLocalChapterIndex == chapterIndex, result.pages.indices.contains(localPage) {
                                targetPageIndex = localPage
                            }
                        }
                    }
                    
                    // Synchronously update everything to avoid intermediate blank states
                    self.rawContent = cleaned
                    if let cache = initialCache {
                        self.contentSentences = sentences
                        self.currentContent = processed
                        if self.shouldSyncPageAfterPagination {
                            self.suppressPageIndexChangeOnce = true
                        }
                        self.currentCache = cache
                        self.currentPageIndex = targetPageIndex
                        self.didApplyResumePos = true // Mark as finished with initial resume
                        if !self.hasInitialPagination, !cache.pages.isEmpty { self.hasInitialPagination = true }
                        
                        // Set the pagination key to current state to prevent immediate redundant re-pagination
                        self.lastPaginationKey = PaginationKey(width: Int(targetPageSize.width * 100), height: Int(targetPageSize.height * 100), fontSize: Int(fontSize * 10), lineSpacing: Int(lineSpacing * 10), margin: Int(margin * 10), sentenceCount: sentences.count, chapterIndex: chapterIndex, resumeCharIndex: -1, resumePageIndex: -1)
                    } else {
                        // Fallback if size was 0, though unlikely here
                        updateProcessedContent(from: cleaned)
                    }
                    
                    if self.shouldSyncPageAfterPagination {
                        self.syncPageForSentenceIndex(self.ttsManager.currentSentenceIndex)
                        self.shouldSyncPageAfterPagination = false
                    }
                    self.isLoading = false
                    self.shouldApplyResumeOnce = false
                    self.pendingJumpToFirstPage = false
                    self.pendingJumpToLastPage = false
                    self.pendingResumeLocalBodyIndex = nil
                    self.pendingResumeLocalChapterIndex = nil
                    self.pendingResumeLocalPageIndex = nil
                    self.pendingResumePos = nil
                    
                    prepareAdjacentChapters(for: chapterIndex)
                    
                    if let request = pendingTTSRequest {
                        pendingTTSRequest = nil
                        requestTTSPlayback(pageIndexOverride: request.pageIndexOverride, showControls: request.showControls)
                    }
                    if isTTSAutoChapterChange { isTTSAutoChapterChange = false }
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
        currentCache = .empty; prevCache = .empty; nextCache = .empty
        currentPageIndex = 0; lastAdjacentPrepareAt = 0
        pendingBufferPageIndex = nil; lastHandledPageIndex = nil
    }
    
    private func previousChapter() {
        guard currentChapterIndex > 0 else { return }
        didApplyResumePos = true
        currentVisibleSentenceIndex = nil
        let targetIndex = currentChapterIndex - 1
        if !prevCache.pages.isEmpty {
            let cached = prevCache
            nextCache = currentCache
            prevCache = .empty
            applyCachedChapter(cached, chapterIndex: targetIndex, jumpToFirst: false, jumpToLast: true)
            ttsBaseIndex = 0
            prepareAdjacentChaptersIfNeeded(for: currentChapterIndex)
            if ttsManager.isPlaying && !ttsManager.isPaused {
                lastTTSSentenceIndex = max(0, currentCache.paragraphStarts.count - 1)
                requestTTSPlayback(pageIndexOverride: currentPageIndex, showControls: false)
            }
            saveProgress()
            return
        }
        currentChapterIndex = targetIndex
        loadChapterContent()
        saveProgress()
    }
    
    private func nextChapter() {
        guard currentChapterIndex < chapters.count - 1 else { return }
        didApplyResumePos = true
        currentVisibleSentenceIndex = nil
        let targetIndex = currentChapterIndex + 1
        if !nextCache.pages.isEmpty {
            let cached = nextCache
            prevCache = currentCache
            nextCache = .empty
            applyCachedChapter(cached, chapterIndex: targetIndex, jumpToFirst: true, jumpToLast: false)
            ttsBaseIndex = 0
            prepareAdjacentChaptersIfNeeded(for: currentChapterIndex)
            if ttsManager.isPlaying && !ttsManager.isPaused {
                lastTTSSentenceIndex = 0
                requestTTSPlayback(pageIndexOverride: currentPageIndex, showControls: false)
            }
            saveProgress()
            return
        }
        currentChapterIndex = targetIndex
        loadChapterContent()
        saveProgress()
    }
    
    private func toggleTTS() {
        if ttsManager.isPlaying {
            if ttsManager.isPaused {
                if preferences.readingMode == .horizontal, let pci = pausedChapterIndex, let ppi = pausedPageIndex, (pci != currentChapterIndex || ppi != currentPageIndex || needsTTSRestartAfterPause) {
                    ttsManager.stop(); startTTS(pageIndexOverride: currentPageIndex)
                } else {
                    ttsManager.resume()
                }
            } else {
                pausedChapterIndex = currentChapterIndex; pausedPageIndex = currentPageIndex; ttsManager.pause()
            }
        } else {
            startTTS()
        }
        needsTTSRestartAfterPause = false
    }
    
    private func startTTS(pageIndexOverride: Int? = nil, showControls: Bool = true) {
        if showControls { showUIControls = true }
        suppressTTSSync = true
        needsTTSRestartAfterPause = false
        
        var startIndex = lastTTSSentenceIndex ?? 0
        var textForTTS = contentSentences.joined(separator: "\n")
        let pageIndex = pageIndexOverride ?? currentPageIndex
        
        if preferences.readingMode == .horizontal, let pageRange = pageRange(for: pageIndex), let pageStartIndex = pageStartSentenceIndex(for: pageIndex) {
            startIndex = pageStartIndex
            if currentCache.paragraphStarts.indices.contains(startIndex) {
                let sentenceStartGlobal = currentCache.paragraphStarts[startIndex] + currentCache.chapterPrefixLen
                let offset = max(0, pageRange.location - sentenceStartGlobal)
                
                if offset > 0 && startIndex < contentSentences.count {
                    let firstSentence = contentSentences[startIndex]
                    if offset < firstSentence.utf16.count, let strIndex = String.Index(firstSentence.utf16.index(firstSentence.utf16.startIndex, offsetBy: offset), within: firstSentence) {
                        var sentences = [String(firstSentence[strIndex...])]
                        if startIndex + 1 < contentSentences.count { sentences.append(contentsOf: contentSentences[(startIndex + 1)...]) }
                        textForTTS = sentences.joined(separator: "\n")
                        ttsBaseIndex = startIndex; startIndex = 0
                    }
                } else if startIndex < contentSentences.count {
                    textForTTS = Array(contentSentences[startIndex...]).joined(separator: "\n")
                    ttsBaseIndex = startIndex; startIndex = 0
                }
            }
        } else {
            startIndex = currentVisibleSentenceIndex ?? startIndex
            ttsBaseIndex = 0
        }

        guard !textForTTS.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        lastTTSSentenceIndex = ttsBaseIndex + startIndex
        ttsManager.currentBaseSentenceIndex = ttsBaseIndex

        let speakTitle = preferences.readingMode == .horizontal && pageIndex == 0 && currentCache.chapterPrefixLen > 0
        ttsManager.startReading(text: textForTTS, chapters: chapters, currentIndex: currentChapterIndex, bookUrl: book.bookUrl ?? "", bookSourceUrl: book.origin, bookTitle: book.name ?? "阅读", coverUrl: book.displayCoverUrl, onChapterChange: { newIndex in
            self.isAutoFlipping = true
            if self.switchChapterUsingCacheIfAvailable(targetIndex: newIndex, jumpToFirst: true, jumpToLast: false) {
                self.lastTTSSentenceIndex = 0
                self.saveProgress()
                return
            }
            self.isTTSAutoChapterChange = true
            self.didApplyResumePos = true
            self.currentVisibleSentenceIndex = nil
            self.currentChapterIndex = newIndex
            self.pendingTTSRequest = nil
            self.loadChapterContent()
            self.saveProgress()
        }, startAtSentenceIndex: startIndex, shouldSpeakChapterTitle: speakTitle)
    }
    
    private func saveProgress() {
        guard let bookUrl = book.bookUrl else { return }
        Task {
            let title = chapters.indices.contains(currentChapterIndex) ? chapters[currentChapterIndex].title : nil
            let bodyIndex = currentProgressBodyCharIndex()
            if let index = bodyIndex {
                preferences.saveReadingProgress(bookUrl: bookUrl, chapterIndex: currentChapterIndex, pageIndex: currentPageIndex, bodyCharIndex: index)
            }
            let pos = progressRatio(for: bodyIndex)
            try? await apiService.saveBookProgress(bookUrl: bookUrl, index: currentChapterIndex, pos: pos, title: title)
        }
    }

    private func progressRatio(for bodyIndex: Int?) -> Double {
        guard let bodyIndex = bodyIndex else { return 0 }
        let pStarts = TextKitPaginator.paragraphStartIndices(sentences: contentSentences)
        let bodyLength = (pStarts.last ?? 0) + (contentSentences.last?.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count ?? 0)
        guard bodyLength > 0 else { return 0 }
        let clamped = max(0, min(bodyIndex, max(0, bodyLength - 1)))
        return Double(clamped) / Double(bodyLength)
    }

    private func currentProgressBodyCharIndex() -> Int? {
        if preferences.readingMode == .horizontal {
            guard let range = pageRange(for: currentPageIndex) else { return nil }
            let offset = max(0, min(range.length - 1, range.length / 2))
            return max(0, range.location - currentCache.chapterPrefixLen + offset)
        }
        let sentenceIndex = currentVisibleSentenceIndex ?? lastTTSSentenceIndex ?? 0
        let pStarts = TextKitPaginator.paragraphStartIndices(sentences: contentSentences)
        guard pStarts.indices.contains(sentenceIndex) else { return nil }
        return pStarts[sentenceIndex]
    }
    
    private func updateVisibleSentenceIndex(frames: [Int: CGRect], viewportHeight: CGFloat) {
        let visible = frames.filter { $0.value.maxY > 0 && $0.value.minY < viewportHeight }
        if let first = visible.min(by: { $0.value.minY < $1.value.minY }) {
            if first.key != currentVisibleSentenceIndex { currentVisibleSentenceIndex = first.key }
        }
    }
}

// MARK: - UIPageViewController Wrapper
	private struct ReadPageViewController: UIViewControllerRepresentable {
	    var snapshot: PageSnapshot
	    var prevSnapshot: PageSnapshot?
	    var nextSnapshot: PageSnapshot?
    
    @Binding var currentPageIndex: Int
    var pageSpacing: CGFloat
    var onTransitioningChanged: (Bool) -> Void
    var onTapLocation: (ReaderTapLocation) -> Void
    var onChapterChange: (Int) -> Void
    var onAdjacentPrefetch: (Int) -> Void
    var onAddReplaceRule: (String) -> Void
    var currentContentViewController: ReadContentViewController?
    var prevContentViewController: ReadContentViewController?
    var nextContentViewController: ReadContentViewController?
    var makeViewController: (PageSnapshot, Int, Int) -> ReadContentViewController?

    func makeUIViewController(context: Context) -> UIPageViewController {
        let pvc = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal, options: [UIPageViewController.OptionsKey.interPageSpacing: pageSpacing])
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

        pvc.dataSource = context.coordinator
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
        
        private func pageCountForChapterOffset(_ offset: Int) -> Int {
            let active = snapshot ?? parent.snapshot
            switch offset {
            case 0: return active.pages.count
            case -1: return parent.prevSnapshot?.pages.count ?? 0
            case 1: return parent.nextSnapshot?.pages.count ?? 0
            default: return 0
            }
        }

        func updateSnapshotIfNeeded(_ newSnapshot: PageSnapshot, currentPageIndex: Int) {
            guard newSnapshot.renderStore != nil, !newSnapshot.pages.isEmpty else { return }
            
            if shouldReplaceSnapshot(with: newSnapshot) {
                if isAnimating { pendingSnapshot = newSnapshot; return }
                snapshot = newSnapshot
            } else if let current = snapshot, newSnapshot.pages.count > current.pages.count {
                if isAnimating { pendingSnapshot = newSnapshot } else { snapshot = newSnapshot }
            }
            let activeSnapshot = snapshot ?? newSnapshot
            
            guard let pvc = pageViewController, let activeStore = activeSnapshot.renderStore else { return }
            
            if let currentVC = pvc.viewControllers?.first as? ReadContentViewController,
               currentVC.chapterOffset == 0, currentVC.pageIndex == currentPageIndex, currentVC.renderStore === activeStore {
                currentVC.configureTK2Page(info: activeSnapshot.pageInfos![currentPageIndex]) // Reconfigure and redraw if needed
                currentVC.redraw()
                return
            }
            
            if currentPageIndex < activeSnapshot.pages.count {
                let vc: ReadContentViewController?
                if let cached = currentContentViewController,
                   cached.chapterOffset == 0,
                   cached.pageIndex == currentPageIndex,
                   cached.renderStore === activeStore {
                    vc = cached
                } else {
                    vc = parent.makeViewController(activeSnapshot, currentPageIndex, 0)
                }
                if let vc {
                    pvc.setViewControllers([vc], direction: .forward, animated: false)
                }
            }
        }
        
        private func shouldReplaceSnapshot(with newSnapshot: PageSnapshot) -> Bool {
            guard let current = snapshot else { return true }
            if let t2 = current.renderStore, let nt2 = newSnapshot.renderStore { if t2 !== nt2 { return true } } else if current.renderStore != nil || newSnapshot.renderStore != nil { return true }
            if newSnapshot.pages.count < current.pages.count { return true }
            return false
        }

        func pageViewController(_ pvc: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
            guard let vc = viewController as? ReadContentViewController else { return nil }
            
            if vc.chapterOffset == 0 {
                if vc.pageIndex > 0 { return parent.makeViewController(parent.snapshot, vc.pageIndex - 1, 0) }
                else if let prev = parent.prevSnapshot, !prev.pages.isEmpty { return parent.makeViewController(prev, prev.pages.count - 1, -1) }
                else { parent.onAdjacentPrefetch(-1); return nil }
            }
            else if vc.chapterOffset == -1, let prev = parent.prevSnapshot, vc.pageIndex > 0 { return parent.makeViewController(prev, vc.pageIndex - 1, -1) }
            else if vc.chapterOffset == 1 {
                if vc.pageIndex > 0, let next = parent.nextSnapshot { return parent.makeViewController(next, vc.pageIndex - 1, 1) }
                else { return parent.makeViewController(parent.snapshot, parent.snapshot.pages.count - 1, 0) }
            }
            return nil
        }

        func pageViewController(_ pvc: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
            guard let vc = viewController as? ReadContentViewController else { return nil }
            
            if vc.chapterOffset == 0 {
                if vc.pageIndex < parent.snapshot.pages.count - 1 { return parent.makeViewController(parent.snapshot, vc.pageIndex + 1, 0) }
                else if let next = parent.nextSnapshot, !next.pages.isEmpty { return parent.makeViewController(next, 0, 1) }
                else { parent.onAdjacentPrefetch(1); return nil }
            }
            else if vc.chapterOffset == 1, let next = parent.nextSnapshot, vc.pageIndex < next.pages.count - 1 { return parent.makeViewController(next, vc.pageIndex + 1, 1) }
            else if vc.chapterOffset == -1, let prev = parent.prevSnapshot {
                if vc.pageIndex < prev.pages.count - 1 { return parent.makeViewController(prev, vc.pageIndex + 1, -1) }
                else { return parent.makeViewController(parent.snapshot, 0, 0) }
            }
            return nil
        }
        
        func pageViewController(_ pvc: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) {
            isAnimating = true
            parent.onTransitioningChanged(true)
        }

        func pageViewController(_ pvc: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
            if completed, let visibleVC = pvc.viewControllers?.first as? ReadContentViewController {
                if visibleVC.chapterOffset == 0 {
                    if parent.currentPageIndex != visibleVC.pageIndex { parent.currentPageIndex = visibleVC.pageIndex }
                } 
                else { parent.onChapterChange(visibleVC.chapterOffset) }
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

// MARK: - Other Views
private class ReadContentViewController: UIViewController, UIGestureRecognizerDelegate {
    let pageIndex: Int
    let renderStore: TextKit2RenderStore
    let chapterOffset: Int
    let onAddReplaceRule: ((String) -> Void)?
    let onTapLocation: ((ReaderTapLocation) -> Void)?
    
    private var tk2View: ReadContent2View?
    private var pendingPageInfo: TK2PageInfo?
    
    init(pageIndex: Int, renderStore: TextKit2RenderStore, chapterOffset: Int, onAddReplaceRule: ((String) -> Void)?, onTapLocation: ((ReaderTapLocation) -> Void)?) {
        self.pageIndex = pageIndex
        self.renderStore = renderStore
        self.chapterOffset = chapterOffset
        self.onAddReplaceRule = onAddReplaceRule
        self.onTapLocation = onTapLocation
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.systemBackground
        setupTK2View()
    }
    
    private func setupTK2View() {
         let v = ReadContent2View(frame: view.bounds)
         v.autoresizingMask = [.flexibleWidth, .flexibleHeight]
         v.renderStore = renderStore
         v.onTapLocation = onTapLocation
         v.onAddReplaceRule = onAddReplaceRule
         view.addSubview(v)
         self.tk2View = v
         if let pendingPageInfo {
             v.pageInfo = pendingPageInfo
             v.setNeedsDisplay()
         }
    }
    
    func configureTK2Page(info: TK2PageInfo) {
        pendingPageInfo = info
        tk2View?.pageInfo = info
        tk2View?.setNeedsDisplay()
    }

    func redraw() {
        tk2View?.setNeedsDisplay()
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
}

private struct TextKitPaginator {
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
        
        let body = sentences.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.joined(separator: "\n")
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

private struct ChapterListView: View {
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
            ScrollViewReader {
                proxy in
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
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { withAnimation { proxy.scrollTo(currentIndex, anchor: .center) } }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: isReversed ? "arrow.up" : "arrow.down")
                                Text(isReversed ? "倒序" : "正序")
                            }.font(.caption)
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("关闭") { dismiss() }
                    }
                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { withAnimation { proxy.scrollTo(currentIndex, anchor: .center) } }
                }
            }
        }
    }
}

private struct RichTextView: View {
    let sentences: [String]
    let fontSize: CGFloat
    let lineSpacing: CGFloat
    let highlightIndex: Int?
    let secondaryIndices: Set<Int>
    let isPlayingHighlight: Bool
    let scrollProxy: ScrollViewProxy?
    
    var body: some View {
        VStack(alignment: .leading, spacing: fontSize * 0.8) {
            ForEach(Array(sentences.enumerated()), id: \.offset) { index, sentence in
                Text(sentence.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.system(size: fontSize))
                    .lineSpacing(lineSpacing)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .background(GeometryReader { proxy in Color.clear.preference(key: SentenceFramePreferenceKey.self, value: [index: proxy.frame(in: .named("scroll"))]) })
                    .background(RoundedRectangle(cornerRadius: 4).fill(highlightColor(for: index)).animation(.easeInOut, value: highlightIndex))
                    .id(index)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            if let highlightIndex = highlightIndex, let scrollProxy = scrollProxy {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { withAnimation { scrollProxy.scrollTo(highlightIndex, anchor: .center) } }
            }
        }
    }

    private func highlightColor(for index: Int) -> Color {
        if isPlayingHighlight {
            if index == highlightIndex { return Color.blue.opacity(0.2) }
            if secondaryIndices.contains(index) { return Color.green.opacity(0.18) }
            return .clear
        }
        return index == highlightIndex ? Color.orange.opacity(0.2) : .clear
    }
}

private struct SentenceFramePreferenceKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) { value.merge(nextValue(), uniquingKeysWith: { $1 }) }
}

private struct TTSControlBar: View {
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
                        Text("上一段").font(.caption)
                    }
                    .foregroundColor(ttsManager.currentSentenceIndex <= 0 ? .gray : .blue)
                }
                .disabled(ttsManager.currentSentenceIndex <= 0)
                
                Spacer()
                VStack(spacing: 4) {
                    Text("段落进度").font(.caption).foregroundColor(.secondary)
                    Text("\(ttsManager.currentSentenceIndex + 1) / \(ttsManager.totalSentences)").font(.title2).fontWeight(.semibold)
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
                Button(action: { onTogglePlayPause() }) {
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

private struct NormalControlBar: View {
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
                    Image(systemName: "speaker.wave.2.circle.fill").font(.system(size: 32)).foregroundColor(.blue)
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

private struct FontSizeSheet: View {
    @ObservedObject var preferences: UserPreferences
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text("字体大小: \(String(format: "%.0f", preferences.fontSize))")
                        .font(.headline)
                    Slider(value: $preferences.fontSize, in: 12...30, step: 1)
                }
                
                VStack(spacing: 8) {
                    Text("左右边距: \(String(format: "%.0f", preferences.pageHorizontalMargin))")
                        .font(.headline)
                    Slider(value: $preferences.pageHorizontalMargin, in: 0...50, step: 1)
                }

                VStack(spacing: 8) {
                    Text("翻页间距: \(String(format: "%.0f", preferences.pageInterSpacing))")
                        .font(.headline)
                    Slider(value: $preferences.pageInterSpacing, in: 0...30, step: 1)
                }

                Toggle("播放时锁定翻页", isOn: $preferences.lockPageOnTTS)
                    .padding(.top)
                
                Spacer()
            }
            .padding()
        }
    }
}

// MARK: - TextKit 2 Implementation
private final class TextKit2RenderStore {
    let contentStorage: NSTextContentStorage
    let layoutManager: NSTextLayoutManager
    let textContainer: NSTextContainer
    var attributedString: NSAttributedString
    var layoutWidth: CGFloat // Stored layout width
    
    init(attributedString: NSAttributedString, layoutWidth: CGFloat) {
        self.attributedString = attributedString
        self.layoutWidth = layoutWidth // Store layout width
        
        contentStorage = NSTextContentStorage()
        contentStorage.textStorage = NSTextStorage(attributedString: attributedString)
        
        layoutManager = NSTextLayoutManager()
        contentStorage.addTextLayoutManager(layoutManager)
        
        textContainer = NSTextContainer(size: CGSize(width: layoutWidth, height: 0))
        textContainer.lineFragmentPadding = 0
        layoutManager.textContainer = textContainer
    }
    
    func update(attributedString newAttributedString: NSAttributedString, layoutWidth newLayoutWidth: CGFloat) {
        self.attributedString = newAttributedString
        self.contentStorage.textStorage = NSTextStorage(attributedString: newAttributedString)
        self.layoutWidth = newLayoutWidth
        self.textContainer.size = CGSize(width: newLayoutWidth, height: 0)
        // Re-binding container to force internal layout invalidation
        self.layoutManager.textContainer = nil
        self.layoutManager.textContainer = self.textContainer
    }
}

private struct TextKit2Paginator {
    
    struct PaginationResult {
        let pages: [PaginatedPage]
        let pageInfos: [TK2PageInfo]
        let reachedEnd: Bool
    }
    
    static func paginate(
        renderStore: TextKit2RenderStore,
        pageSize: CGSize,
        paragraphStarts: [Int],
        prefixLen: Int,
        contentInset: CGFloat,
        maxPages: Int = Int.max,
        startOffset: Int = 0
    ) -> PaginationResult {
        let layoutManager = renderStore.layoutManager
        let contentStorage = renderStore.contentStorage
        let documentRange = contentStorage.documentRange
        
        guard !documentRange.isEmpty, pageSize.width > 1, pageSize.height > 1 else {
            return PaginationResult(pages: [], pageInfos: [], reachedEnd: true)
        }

        layoutManager.ensureLayout(for: documentRange)

        var pages: [PaginatedPage] = []
        var pageInfos: [TK2PageInfo] = []
        var pageCount = 0
        let pageContentHeight = max(1, pageSize.height - contentInset * 2)
        
        var currentContentLocation: NSTextLocation = documentRange.location
        if startOffset > 0, let startLoc = contentStorage.location(documentRange.location, offsetBy: startOffset) {
            currentContentLocation = startLoc
        }
        
        // Helper to find the visual top Y of the line containing a specific location
        func findLineTopY(at location: NSTextLocation) -> CGFloat? {
            guard let fragment = layoutManager.textLayoutFragment(for: location) else { return nil }
            let fragFrame = fragment.layoutFragmentFrame
            let offsetInFrag = contentStorage.offset(from: fragment.rangeInElement.location, to: location)
            
            // If location is at start of fragment, return fragment minY (or first line minY)
            if offsetInFrag == 0 {
                if let firstLine = fragment.textLineFragments.first {
                    return firstLine.typographicBounds.minY + fragFrame.minY
                }
                return fragFrame.minY
            }
            
            // Otherwise find the specific line
            for line in fragment.textLineFragments {
                let lineRange = line.characterRange
                if offsetInFrag < lineRange.upperBound {
                    return line.typographicBounds.minY + fragFrame.minY
                }
            }
            // Fallback to fragment bottom if not found (shouldn't happen for valid loc)
            return fragFrame.maxY
        }

        while pageCount < maxPages {
            let remainingOffset = layoutManager.offset(from: currentContentLocation, to: documentRange.endLocation)
            guard remainingOffset > 0 else { break }
            
            // 1. Determine the start Y for this page based on the current content location
            // This ensures we align exactly to the top of the next line, ignoring previous page's bottom gaps.
            let rawPageStartY = findLineTopY(at: currentContentLocation) ?? 0
            let pixel = max(1.0 / UIScreen.main.scale, 0.5)
            let pageStartY = floor(rawPageStartY / pixel) * pixel
            
            let pageRect = CGRect(x: 0, y: pageStartY, width: pageSize.width, height: pageContentHeight)
            let lineEdgeInset = max(2.0, contentInset * 0.05)
            let lineEdgeSlack: CGFloat = 0
            
            var pageFragmentMaxY: CGFloat?
            var pageEndLocation: NSTextLocation = currentContentLocation
            
            layoutManager.enumerateTextLayoutFragments(from: currentContentLocation, options: [.ensuresLayout, .ensuresExtraLineFragment]) { fragment in
                let fragmentFrame = fragment.layoutFragmentFrame
                let fragmentRange = TextKit2Paginator.rangeFromTextRange(fragment.rangeInElement, in: contentStorage)
                
                if fragmentFrame.minY >= pageRect.maxY { return false }
                
                // If fragment is completely above (shouldn't happen with correct startY), skip
                if fragmentFrame.maxY <= pageStartY { return true }

                if pageFragmentMaxY == nil { pageFragmentMaxY = max(pageStartY, fragmentFrame.minY) }
                
                if fragmentFrame.maxY <= pageRect.maxY {
                    // Fragment fits entirely
                    pageFragmentMaxY = fragmentFrame.maxY
                    if let fragmentRange = fragmentRange,
                       let loc = contentStorage.location(documentRange.location, offsetBy: NSMaxRange(fragmentRange)) {
                        pageEndLocation = loc
                    } else {
                        pageEndLocation = fragment.rangeInElement.endLocation
                    }
                    return true
                } else {
                    // Fragment splits across page boundary
                    let currentStartOffset = contentStorage.offset(from: documentRange.location, to: currentContentLocation)
                    var foundVisibleLine = false
                    
                    for line in fragment.textLineFragments {
                        let lineRange = line.characterRange
                        // Calculate global offset for this line end
                        let lineEndGlobalOffset: Int
                        if let fragmentRange = fragmentRange {
                             lineEndGlobalOffset = fragmentRange.location + lineRange.upperBound
                        } else {
                             // Fallback approximation (unsafe but rare)
                             lineEndGlobalOffset = currentStartOffset + lineRange.upperBound
                        }
                        
                        // Skip lines before our start point
                        if lineEndGlobalOffset <= currentStartOffset { continue }

                        let lineFrame = line.typographicBounds.offsetBy(dx: fragmentFrame.origin.x, dy: fragmentFrame.origin.y)

                        if lineFrame.maxY <= pageRect.maxY - lineEdgeInset + lineEdgeSlack {
                            if let loc = contentStorage.location(documentRange.location, offsetBy: lineEndGlobalOffset) {
                                pageEndLocation = loc
                                pageFragmentMaxY = lineFrame.maxY
                                foundVisibleLine = true
                            }
                        } else {
                            break
                        }
                    }
                    
                    // If no lines fit (e.g. huge line or top of page), force at least one line if it's the first item
                    if !foundVisibleLine {
                         // Find the first line that effectively starts after our current location
                         if let firstLine = fragment.textLineFragments.first(where: { line in
                            let endOff = (fragmentRange?.location ?? 0) + line.characterRange.upperBound
                            return endOff > currentStartOffset
                         }) {
                             // If this is the VERY first line of the page and it doesn't fit, we must include it to avoid infinite loop
                             // Check if we haven't advanced pageEndLocation yet
                             let isAtPageStart = contentStorage.offset(from: currentContentLocation, to: pageEndLocation) == 0
                             
                             if isAtPageStart {
                                let endOffset = firstLine.characterRange.upperBound
                                let globalEndOffset = (fragmentRange?.location ?? 0) + endOffset
                                pageEndLocation = contentStorage.location(documentRange.location, offsetBy: globalEndOffset) ?? pageEndLocation
                                let lineFrame = firstLine.typographicBounds.offsetBy(dx: fragmentFrame.origin.x, dy: fragmentFrame.origin.y)
                                pageFragmentMaxY = lineFrame.maxY
                             }
                         }
                    }
                    return false
                }
            }
            
            let startOffset = contentStorage.offset(from: documentRange.location, to: currentContentLocation)
            var endOffset = contentStorage.offset(from: documentRange.location, to: pageEndLocation)
            
            // Failsafe: Ensure progress
            if endOffset <= startOffset {
                if let forced = layoutManager.location(currentContentLocation, offsetBy: 1) {
                    pageEndLocation = forced
                    endOffset = contentStorage.offset(from: documentRange.location, to: pageEndLocation)
                } else {
                    break
                }
            }

            let pageRange = NSRange(location: startOffset, length: endOffset - startOffset)
            let actualContentHeight = (pageFragmentMaxY ?? (pageStartY + pageContentHeight)) - pageStartY
            let adjustedLocation = max(0, pageRange.location - prefixLen)
            let startIdx = paragraphStarts.lastIndex(where: { $0 <= adjustedLocation }) ?? 0
            
            pages.append(PaginatedPage(globalRange: pageRange, startSentenceIndex: startIdx))
            pageInfos.append(TK2PageInfo(range: pageRange, yOffset: pageStartY, pageHeight: pageContentHeight, actualContentHeight: actualContentHeight, startSentenceIndex: startIdx, contentInset: contentInset))
            
            pageCount += 1
            currentContentLocation = pageEndLocation
        }

        let reachedEnd = layoutManager.offset(from: currentContentLocation, to: documentRange.endLocation) == 0
        return PaginationResult(pages: pages, pageInfos: pageInfos, reachedEnd: reachedEnd)
    }

    static func rangeFromTextRange(_ textRange: NSTextRange?, in content: NSTextContentStorage) -> NSRange? {
        guard let textRange = textRange else { return nil }
        let location = content.offset(from: content.documentRange.location, to: textRange.location)
        let length = content.offset(from: textRange.location, to: textRange.endLocation)
        return NSRange(location: location, length: length)
    }
}

private class ReadContent2View: UIView {
    var renderStore: TextKit2RenderStore?
    var pageInfo: TK2PageInfo?
    var onTapLocation: ((ReaderTapLocation) -> Void)?
    var onAddReplaceRule: ((String) -> Void)?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        self.backgroundColor = .clear
        self.clipsToBounds = true
        
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        self.addGestureRecognizer(tap)
        
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        self.addGestureRecognizer(longPress)
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    override func draw(_ rect: CGRect) {
        guard let store = renderStore, let info = pageInfo else { return }
        
        let context = UIGraphicsGetCurrentContext()
        context?.saveGState()
        
        // Clip to content area (exclude top/bottom insets) to avoid edge bleed
        let contentClip = CGRect(x: 0, y: info.contentInset, width: bounds.width, height: info.pageHeight)
        context?.clip(to: contentClip)
        
        // Translate context to start drawing from the current page's yOffset with vertical inset
        context?.translateBy(x: 0, y: -(info.yOffset - info.contentInset))
        
        let startLoc = store.contentStorage.location(store.contentStorage.documentRange.location, offsetBy: info.range.location)
        
        let contentStorage = store.contentStorage
        let pageStartOffset = info.range.location
        let pageEndOffset = NSMaxRange(info.range)
        var shouldStop = false
        
        store.layoutManager.enumerateTextLayoutFragments(from: startLoc, options: [.ensuresLayout]) { fragment in
            if shouldStop { return false }
            let frame = fragment.layoutFragmentFrame
            
            if frame.minY >= info.yOffset + info.pageHeight { return false }
            
            guard let fragmentRange = TextKit2Paginator.rangeFromTextRange(fragment.rangeInElement, in: contentStorage) else {
                if frame.maxY > info.yOffset {
                    fragment.draw(at: frame.origin, in: context!)
                }
                return true
            }
            
            let fragmentStart = fragmentRange.location
            let fragmentEnd = NSMaxRange(fragmentRange)
            
            if fragmentEnd <= pageStartOffset { return true }
            if fragmentStart >= pageEndOffset { return false }
            
            for line in fragment.textLineFragments {
                let lineStart = fragmentStart + line.characterRange.location
                let lineEnd = fragmentStart + line.characterRange.upperBound
                
                if lineEnd <= pageStartOffset { continue }
                if lineStart >= pageEndOffset {
                    shouldStop = true
                    break
                }
                
                let lineFrame = line.typographicBounds.offsetBy(dx: frame.origin.x, dy: frame.origin.y)
                if lineFrame.maxY <= info.yOffset { continue }
                if lineFrame.minY >= info.yOffset + info.pageHeight {
                    shouldStop = true
                    break
                }
                let lineDrawRect = CGRect(x: 0, y: lineFrame.minY, width: bounds.width, height: lineFrame.height)
                context?.saveGState()
                context?.clip(to: lineDrawRect)
                fragment.draw(at: frame.origin, in: context!)
                context?.restoreGState()
            }
            
            return !shouldStop
        }
        
        context?.restoreGState()
    }
    
    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let x = gesture.location(in: self).x
        let w = bounds.width
        if x < w / 3 { onTapLocation?(.left) }
        else if x > w * 2 / 3 { onTapLocation?(.right) }
        else { onTapLocation?(.middle) }
    }
    
    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, let store = renderStore, let info = pageInfo else { return }
        let point = gesture.location(in: self)
        let adjustedPoint = CGPoint(x: point.x, y: point.y + info.yOffset - info.contentInset)
        
        if let fragment = store.layoutManager.textLayoutFragment(for: adjustedPoint),
           let textElement = fragment.textElement,
           let nsRange = TextKit2Paginator.rangeFromTextRange(textElement.elementRange, in: store.contentStorage) {
            let text = (store.attributedString.string as NSString).substring(with: nsRange)
            becomeFirstResponder()
            let menu = UIMenuController.shared
            menu.showMenu(from: self, rect: CGRect(origin: point, size: .zero))
            self.pendingSelectedText = text
        }
    }
    
    private var pendingSelectedText: String? { didSet { if pendingSelectedText == nil { becomeFirstResponder() } } }
    
    override var canBecomeFirstResponder: Bool { true }
    
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        return action == #selector(addToReplaceRule)
    }
    
    @objc func addToReplaceRule() {
        if let text = pendingSelectedText { onAddReplaceRule?(text) }
    }
}
