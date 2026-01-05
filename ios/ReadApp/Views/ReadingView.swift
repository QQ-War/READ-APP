import SwiftUI
import UIKit

// MARK: - Core Types
private struct PageTurnRequest: Equatable {
    let direction: UIPageViewController.NavigationDirection
    let animated: Bool
    let targetIndex: Int
    let targetSnapshot: PageSnapshot? // 跨章节时携带目标快照
    let targetChapterIndex: Int?     // 目标章节索引
    let timestamp: TimeInterval

    init(
        direction: UIPageViewController.NavigationDirection,
        animated: Bool,
        targetIndex: Int,
        targetSnapshot: PageSnapshot? = nil,
        targetChapterIndex: Int? = nil
    ) {
        self.direction = direction
        self.animated = animated
        self.targetIndex = targetIndex
        self.targetSnapshot = targetSnapshot
        self.targetChapterIndex = targetChapterIndex
        self.timestamp = Date().timeIntervalSince1970
    }
    
    static func == (lhs: PageTurnRequest, rhs: PageTurnRequest) -> Bool {
        lhs.timestamp == rhs.timestamp
    }
}

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
    let chapterUrl: String? // 新增
    
    static var empty: ChapterCache {
        ChapterCache(pages: [], renderStore: nil, pageInfos: nil, contentSentences: [], rawContent: "", attributedText: NSAttributedString(), paragraphStarts: [], chapterPrefixLen: 0, isFullyPaginated: false, chapterUrl: nil)
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
    let contentSentences: [String]? // 新增：保存原始句子用于漫画渲染
    let chapterUrl: String? // 新增
}

// MARK: - ReadingView
enum ReaderTapLocation {
    case left, right, middle
}

struct ReadingView: View {
    let book: Book
    private let logger = LogManager.shared
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
    
    // 漫画模式占位符，用于缓存 key 保持稳定
    private let mangaPlaceholderStore = TextKit2RenderStore(attributedString: NSAttributedString(), layoutWidth: 1)
    
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
    @State private var showDetailFromHeader = false
    
    // Sleep Timer State
    @State private var timerRemaining: Int = 0
    @State private var timerActive = false
    @State private var sleepTimer: Timer? = nil
    
    // Replace Rule State
    @State private var showAddReplaceRule = false
    @State private var pendingReplaceRule: ReplaceRule?
    
    // Page Turn & Navigation State
    @State private var pageTurnRequest: PageTurnRequest? = nil
    @State private var isExplicitlySwitchingChapter = false
    @State private var currentChapterIsManga = false
    @State private var lastEffectiveMode: ReadingMode? = nil
    
    // 旋转与布局增强
    @State private var isForceLandscape = false

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

    private var effectiveReadingMode: ReadingMode {
        if currentChapterIsManga { return .vertical }
        return preferences.readingMode
    }

    // MARK: - Body
    var body: some View {
        NavigationView {
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
            }
            .navigationBarHidden(true)
            .navigationBarBackButtonHidden(true)
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .onChange(of: effectiveReadingMode) { newMode in
            guard let oldMode = lastEffectiveMode, oldMode != newMode else {
                lastEffectiveMode = newMode
                return
            }
            
            // 执行进度同步
            if oldMode == .vertical && newMode == .horizontal {
                // 垂直 -> 水平：找到当前看到的段落，跳转到包含该段落的页
                if let targetSentence = currentVisibleSentenceIndex {
                    let pStarts = currentCache.paragraphStarts
                    let prefixLen = currentCache.chapterPrefixLen
                    if targetSentence < pStarts.count {
                        let charOffset = pStarts[targetSentence] + prefixLen
                        if let pageIdx = currentCache.pages.firstIndex(where: { NSLocationInRange(charOffset, $0.globalRange) }) {
                            self.currentPageIndex = pageIdx
                            self.pageTurnRequest = PageTurnRequest(direction: .forward, animated: false, targetIndex: pageIdx)
                        }
                    }
                }
            } else if oldMode == .horizontal && newMode == .vertical {
                // 水平 -> 垂直：获取当前页起始段落，滚动到该段落
                if let targetSentence = pageStartSentenceIndex(for: currentPageIndex) {
                    self.pendingScrollToSentenceIndex = targetSentence
                    self.handlePendingScroll()
                }
            }
            
            lastEffectiveMode = newMode
        }
        .onAppear {
            lastEffectiveMode = effectiveReadingMode
        }
        .onChange(of: isForceLandscape) { newValue in
            // 强制旋转逻辑
            updateAppOrientation(landscape: newValue)
        }
        .onDisappear {
            // 退出阅读器时恢复竖屏
            if isForceLandscape { updateAppOrientation(landscape: false) }
        }
        .sheet(isPresented: $showChapterList) { ChapterListView(chapters: chapters, currentIndex: currentChapterIndex, bookUrl: book.bookUrl ?? "") { index in
            currentChapterIndex = index
            pendingJumpToFirstPage = true
            loadChapterContent()
            showChapterList = false
        } } // ChapterListView
        .sheet(isPresented: $showFontSettings) { 
            ReaderOptionsSheet(preferences: preferences, isMangaMode: currentChapterIsManga) 
        } // ReaderOptionsSheet
        .sheet(isPresented: $showAddReplaceRule) { ReplaceRuleEditView(viewModel: replaceRuleViewModel, rule: pendingReplaceRule) } // ReplaceRuleEditView
        .onChange(of: replaceRuleViewModel.rules) { _ in updateProcessedContent(from: rawContent) }
        .onChange(of: pendingScrollToSentenceIndex) { _ in handlePendingScroll() }
        .alert("错误", isPresented: .constant(errorMessage != nil)) { Button("确定") { errorMessage = nil } } message: {
            if let error = errorMessage { Text(error) }
        }
        .onDisappear { saveProgress() }
        .onChange(of: ttsManager.isPlaying) { handleTTSPlayStateChange($0) }
        .onChange(of: ttsManager.isPaused) { handleTTSPauseStateChange($0) }
        .onChange(of: ttsManager.currentSentenceIndex) { _ in handleTTSSentenceChange() }
        .onChange(of: scenePhase) { handleScenePhaseChange($0) }
        .task {
            await loadChapters()
            await replaceRuleViewModel.fetchRules()
            enterReadingSessionIfNeeded()
        }
    }

    // MARK: - UI Components
    
    private var backgroundView: some View { Color(UIColor.systemBackground) }

    @ViewBuilder
    private func mainContent(safeArea: EdgeInsets) -> some View {
        if currentChapterIsManga {
            // 路径 1: 原生 UIKit 漫画模式
            MangaNativeReader(
                sentences: contentSentences,
                chapterUrl: chapters.indices.contains(currentChapterIndex) ? chapters[currentChapterIndex].url : nil,
                showUIControls: $showUIControls,
                currentVisibleIndex: Binding(
                    get: { currentVisibleSentenceIndex ?? 0 },
                    set: { currentVisibleSentenceIndex = $0 }
                ),
                pendingScrollIndex: $pendingScrollToSentenceIndex
            )
            .ignoresSafeArea()
        } else if preferences.readingMode == .horizontal {
            // 路径 2: 水平翻页模式 (小说)
            horizontalReader(safeArea: safeArea)
        } else {
            // 路径 3: 垂直滚动模式 (小说)
            verticalReader.padding(.top, safeArea.top).padding(.bottom, safeArea.bottom)
        }
    }
    
    private func updateMangaModeState() {
        // 漫画模式判定（对标 legado.koplugin 分类逻辑）
        // 1. 手动强制
        if let url = book.bookUrl, preferences.manualMangaUrls.contains(url) {
            currentChapterIsManga = true
            return
        }
        // 2. 纯图片章节 (内容极短且包含图片占位符)
        if rawContent.count < 500 && rawContent.contains("__IMG__") {
            currentChapterIsManga = true
            return
        }
        // 3. 漫画书类型 (2)
        if book.type == 2 {
            currentChapterIsManga = true
            return
        }
        
        let imageCount = contentSentences.filter { $0.hasPrefix("__IMG__") }.count
        if imageCount > 0 {
            let ratio = Double(imageCount) / Double(contentSentences.count)
            // 4. 高密度图片 (15% 以上)
            currentChapterIsManga = ratio > 0.15
        } else {
            currentChapterIsManga = false
        }
    }
    
    private var verticalReader: some View {
        GeometryReader {
            geometry in
            ScrollViewReader {
                proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // 置顶锚点
                        Color.clear.frame(height: 1).id("top_marker")
                        
                        let primaryHighlight = ttsManager.isPlaying ? (ttsManager.currentSentenceIndex + ttsBaseIndex) : lastTTSSentenceIndex
                        let secondaryHighlights = ttsManager.isPlaying ? Set(ttsManager.preloadedIndices.map { $0 + ttsBaseIndex }) : Set<Int>()
                        
                        RichTextView(
                            sentences: contentSentences,
                            fontSize: preferences.fontSize,
                            lineSpacing: preferences.lineSpacing,
                            highlightIndex: primaryHighlight,
                            secondaryIndices: secondaryHighlights,
                            isPlayingHighlight: ttsManager.isPlaying,
                            scrollProxy: scrollProxy,
                            chapterUrl: chapters.indices.contains(currentChapterIndex) ? chapters[currentChapterIndex].url : nil
                        )
                        .padding(.horizontal, currentChapterIsManga ? 0 : preferences.pageHorizontalMargin)
                    }
                    .frame(maxWidth: .infinity) // 确保全宽响应
                    .contentShape(Rectangle()) // 确保空白处可点击
                    .onTapGesture {
                        withAnimation { showUIControls.toggle() }
                    }
                }
                .id("v_reader_scroll_\(currentChapterIndex)") // 强制刷新视图防止内容卡死
                .coordinateSpace(name: "scroll")
                .onPreferenceChange(SentenceFramePreferenceKey.self) { updateVisibleSentenceIndex(frames: $0, viewportHeight: geometry.size.height) }
                .onChange(of: contentSentences) { _ in
                    if preferences.readingMode == .vertical && isExplicitlySwitchingChapter {
                        // 强制置顶到锚点
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            withAnimation { proxy.scrollTo("top_marker", anchor: .top) }
                            isExplicitlySwitchingChapter = false
                        }
                    }
                }
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
            // 如果是漫画模式，强制 0 边距以占满屏幕
            let horizontalMargin: CGFloat = currentChapterIsManga ? 0 : preferences.pageHorizontalMargin
            let verticalMargin: CGFloat = currentChapterIsManga ? 0 : 10
            
            let availableSize = CGSize(
                width: max(0, geometry.size.width - safeArea.leading - safeArea.trailing - horizontalMargin * 2),
                height: max(0, geometry.size.height - safeArea.top - safeArea.bottom - verticalMargin * 2)
            )

            let contentSize = availableSize
            horizontalReaderBody(geometry: geometry, safeArea: safeArea, availableSize: availableSize, contentSize: contentSize, hMargin: horizontalMargin)
            .onAppear { if contentSize.width > 0 { scheduleRepaginate(in: contentSize) } }
            .onChange(of: contentSentences) { _ in if contentSize.width > 0 { scheduleRepaginate(in: contentSize) } }
            .onChange(of: preferences.fontSize) { _ in if contentSize.width > 0 { scheduleRepaginate(in: contentSize) } }
            .onChange(of: preferences.lineSpacing) { _ in if contentSize.width > 0 { scheduleRepaginate(in: contentSize) } }
            .onChange(of: preferences.pageHorizontalMargin) { _ in if contentSize.width > 0 { scheduleRepaginate(in: contentSize) } }
            .onChange(of: geometry.size) { _ in if contentSize.width > 0 { scheduleRepaginate(in: contentSize) } }
            .onChange(of: currentPageIndex) { newIndex in
                if isTTSSyncingPage {
                    // 仅更新索引，不释放锁，也不触发 handlePageIndexChange
                    if let startIndex = pageStartSentenceIndex(for: newIndex) { lastTTSSentenceIndex = startIndex }
                    return
                }
                handlePageIndexChange(newIndex)
            }
        }
    }

    private func horizontalReaderBody(geometry: GeometryProxy, safeArea: EdgeInsets, availableSize: CGSize, contentSize: CGSize, hMargin: CGFloat) -> some View {
        VStack(spacing: 0) {
            Spacer().frame(height: safeArea.top + (currentChapterIsManga ? 0 : 10))
            HStack(spacing: 0) {
                Color.clear.frame(width: safeArea.leading + hMargin).contentShape(Rectangle()).onTapGesture { handleReaderTap(location: .left) }
                
                if availableSize.width > 0 {
                    if hasInitialPagination {
                        ZStack(alignment: .bottomTrailing) {
                            cacheRefresher
                            let currentVC = makeContentViewController(snapshot: snapshot(from: currentCache), pageIndex: currentPageIndex, chapterOffset: 0)
                            let prevVC = makeContentViewController(snapshot: snapshot(from: prevCache), pageIndex: max(0, prevCache.pages.count - 1), chapterOffset: -1)
                            let nextVC = makeContentViewController(snapshot: snapshot(from: nextCache), pageIndex: 0, chapterOffset: 1)

                            ReadPageViewController(
                                snapshot: snapshot(from: currentCache),
                                prevSnapshot: snapshot(from: prevCache),
                                nextSnapshot: snapshot(from: nextCache),
                                currentPageIndex: $currentPageIndex,
                                pageTurnRequest: $pageTurnRequest,
                                pageSpacing: preferences.pageInterSpacing,
                                transitionStyle: preferences.pageTurningMode == .simulation ? .pageCurl : .scroll,
                                onTransitioningChanged: { self.isPageTransitioning = $0 },
                                onTapLocation: handleReaderTap,
                                onChapterChange: { offset in self.isAutoFlipping = true; self.handleChapterSwitch(offset: offset) },
                                onAdjacentPrefetch: { offset in
                                    let needsPrepare = offset > 0 ? nextCache.pages.isEmpty : prevCache.pages.isEmpty
                                    if needsPrepare { prepareAdjacentChapters(for: currentChapterIndex) }
                                },
                                onAddReplaceRule: presentReplaceRuleEditor,
                                onChapterSwitchRequest: { chapterIdx, pageIdx in
                                    self.finalizeAnimatedChapterSwitch(targetChapter: chapterIdx, targetPage: pageIdx)
                                },
                                currentContentViewController: currentVC,
                                prevContentViewController: prevVC,
                                nextContentViewController: nextVC,
                                makeViewController: makeContentViewController
                            )
                            .id("\(preferences.pageInterSpacing)_\(preferences.pageTurningMode.rawValue)_\(currentChapterIsManga)")
                            .frame(width: contentSize.width, height: contentSize.height)

                            if !showUIControls && currentCache.pages.count > 0 && !currentChapterIsManga {
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
                }
                
                Color.clear.frame(width: safeArea.trailing + hMargin).contentShape(Rectangle()).onTapGesture { handleReaderTap(location: .right) }
            }
            Spacer().frame(height: safeArea.bottom + (currentChapterIsManga ? 0 : 10))
        }
        .frame(width: geometry.size.width, height: geometry.size.height)
    }
    
    @ViewBuilder private func topBar(safeArea: EdgeInsets) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button("返回") { dismiss() }
                
                Button(action: { showDetailFromHeader = true }) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(book.name ?? "阅读").font(.headline).fontWeight(.bold).lineLimit(1)
                        Text(chapters.indices.contains(currentChapterIndex) ? chapters[currentChapterIndex].title : "未知章节").font(.caption).foregroundColor(.secondary).lineLimit(1)
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .background(
                    NavigationLink(destination: BookDetailView(book: book).environmentObject(apiService), isActive: $showDetailFromHeader) {
                        EmptyView()
                    }
                )
                
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
            TTSControlBar(
                ttsManager: ttsManager,
                currentChapterIndex: currentChapterIndex,
                chaptersCount: chapters.count,
                timerRemaining: timerRemaining,
                timerActive: timerActive,
                onPreviousChapter: { previousChapter() },
                onNextChapter: { nextChapter() },
                onShowChapterList: { showChapterList = true },
                onTogglePlayPause: toggleTTS,
                onSetTimer: { minutes in toggleSleepTimer(minutes: minutes) }
            )
        } else {
            NormalControlBar(
                currentChapterIndex: currentChapterIndex,
                chaptersCount: chapters.count,
                isMangaMode: currentChapterIsManga,
                isForceLandscape: $isForceLandscape, // 传入旋转状态
                onPreviousChapter: { previousChapter() },
                onNextChapter: { nextChapter() },
                onShowChapterList: { showChapterList = true },
                onToggleTTS: toggleTTS,
                onShowFontSettings: { showFontSettings = true }
            )
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
            let absoluteIndex = ttsManager.currentSentenceIndex + ttsBaseIndex
            pendingScrollToSentenceIndex = absoluteIndex
            handlePendingScroll()
        }
    }
    
    private var cacheRefresher: some View {
        Group {
            let stores: [TextKit2RenderStore?] = [currentCache.renderStore, prevCache.renderStore, nextCache.renderStore, mangaPlaceholderStore]
            let _ = contentControllerCache.retainActive(stores: stores)
        }
        .frame(width: 0, height: 0)
    }

    // MARK: - Pagination & Navigation
    
    private func repaginateContent(in size: CGSize, with newContentSentences: [String]? = nil) {
        let sentences = newContentSentences ?? contentSentences
        let chapterTitle = chapters.indices.contains(currentChapterIndex) ? chapters[currentChapterIndex].title : nil

        // 如果是漫画模式，每张图片（或每段文字）作为一页
        if currentChapterIsManga {
            var pages: [PaginatedPage] = []
            var currentOffset = 0
            for (idx, sentence) in sentences.enumerated() {
                let len = sentence.utf16.count
                pages.append(PaginatedPage(globalRange: NSRange(location: currentOffset, length: len), startSentenceIndex: idx))
                currentOffset += len + 1
            }
            
            if pendingJumpToLastPage { currentPageIndex = max(0, pages.count - 1) }
            else if pendingJumpToFirstPage { currentPageIndex = 0 }
            else if currentPageIndex >= pages.count { currentPageIndex = 0 }
            
            pendingJumpToLastPage = false
            pendingJumpToFirstPage = false
            
            // 确保此处传入了 chapterUrl
            let currentUrl = chapters.indices.contains(currentChapterIndex) ? chapters[currentChapterIndex].url : nil
            currentCache = ChapterCache(pages: pages, renderStore: nil, pageInfos: nil, contentSentences: sentences, rawContent: rawContent, attributedText: NSAttributedString(string: sentences.joined(separator: "\n")), paragraphStarts: [], chapterPrefixLen: 0, isFullyPaginated: true, chapterUrl: currentUrl)
            hasInitialPagination = true
            return
        }

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
        
        currentCache = ChapterCache(pages: result.pages, renderStore: tk2Store, pageInfos: result.pageInfos, contentSentences: sentences, rawContent: rawContent, attributedText: newAttrText, paragraphStarts: newPStarts, chapterPrefixLen: newPrefixLen, isFullyPaginated: true, chapterUrl: chapters.indices.contains(currentChapterIndex) ? chapters[currentChapterIndex].url : nil)
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
        if currentPageIndex > 0 { 
            pageTurnRequest = PageTurnRequest(direction: .reverse, animated: true, targetIndex: currentPageIndex - 1)
        }
        else if currentChapterIndex > 0 {
            pendingJumpToLastPage = true
            previousChapter(animated: true)
        }
    }

    private func goToNextPage() {
        if currentPageIndex < currentCache.pages.count - 1 { 
            pageTurnRequest = PageTurnRequest(direction: .forward, animated: true, targetIndex: currentPageIndex + 1)
        }
        else if currentChapterIndex < chapters.count - 1 {
            pendingJumpToFirstPage = true
            nextChapter(animated: true)
        }
    }

    private func handleReaderTap(location: ReaderTapLocation) {
        if showUIControls { showUIControls = false; return }
        if location == .middle { showUIControls = true; return }
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
        guard pageIndex >= 0 else { return nil }
        
        // 验证索引
        if let store = snapshot.renderStore {
            guard let infos = snapshot.pageInfos, pageIndex < infos.count else { return nil }
        } else if let sentences = snapshot.contentSentences {
            guard pageIndex < sentences.count else { return nil }
        } else {
            return nil
        }

        let vc = contentControllerCache.controller(for: snapshot.renderStore ?? mangaPlaceholderStore, pageIndex: pageIndex, chapterOffset: chapterOffset) {
            ReadContentViewController(
                pageIndex: pageIndex, 
                renderStore: snapshot.renderStore,
                sentences: snapshot.contentSentences,
                chapterUrl: snapshot.chapterUrl, // 关键修复：传递章节 URL
                chapterOffset: chapterOffset,
                onAddReplaceRule: { selectedText in presentReplaceRuleEditor(selectedText: selectedText) },
                onTapLocation: { location in handleReaderTap(location: location) }
            )
        }
        
        // 更新高亮状态 (仅文本模式)
        if snapshot.renderStore != nil {
            if chapterOffset == 0 {
                vc.updateHighlights(
                    index: ttsManager.isPlaying ? (ttsManager.currentSentenceIndex + ttsBaseIndex) : lastTTSSentenceIndex,
                    secondary: ttsManager.isPlaying ? Set(ttsManager.preloadedIndices.map { $0 + ttsBaseIndex }) : [],
                    isPlaying: ttsManager.isPlaying,
                    starts: currentCache.paragraphStarts,
                    prefixLen: currentCache.chapterPrefixLen
                )
            } else {
                vc.updateHighlights(index: nil, secondary: [], isPlaying: false, starts: [], prefixLen: 0)
            }
            
            if let infos = snapshot.pageInfos, pageIndex < infos.count {
                vc.configureTK2Page(info: infos[pageIndex])
            }
        }
        
        return vc
    }

    private func snapshot(from cache: ChapterCache) -> PageSnapshot {
        PageSnapshot(pages: cache.pages, renderStore: cache.renderStore, pageInfos: cache.pageInfos, contentSentences: cache.contentSentences, chapterUrl: cache.chapterUrl)
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
        if currentCache.pages.indices.contains(pageIndex) {
            return currentCache.pages[pageIndex].startSentenceIndex
        }
        
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

    private func updateAppOrientation(landscape: Bool) {
        let mask: UIInterfaceOrientationMask = landscape ? .landscapeRight : .portrait
        
        // 1. 设置支持的旋转方向（通过通知或通知中心触发）
        // 这里依赖于项目中 AppDelegate 或 RootViewController 已经处理了通知
        
        // 2. 现代请求几何更新 (iOS 16+)
        if #available(iOS 16.0, *) {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { error in
                    print("几何更新失败: \(error.localizedDescription)")
                }
            }
        } else {
            // 传统方案 (iOS 15及以下)
            UIDevice.current.setValue(mask.rawValue, forKey: "orientation")
            UIViewController.attemptRotationToDeviceOrientation()
        }
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
            isAutoFlipping = true // 标记为自动翻页，防止 handlePageIndexChange 重启播放
            // 使用动画请求进行 TTS 自动翻页
            pageTurnRequest = PageTurnRequest(direction: .forward, animated: true, targetIndex: pageIndex)
            
            // 延长锁定期，确保动画和状态稳定
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                self.isTTSSyncingPage = false
                self.isAutoFlipping = false
            }
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

    private func applyCachedChapter(_ cache: ChapterCache, chapterIndex: Int, jumpToFirst: Bool, jumpToLast: Bool, animated: Bool = false) {
        suppressRepaginateOnce = true
        currentChapterIndex = chapterIndex
        currentCache = cache
        rawContent = cache.rawContent
        currentContent = cache.contentSentences.joined(separator: "\n")
        contentSentences = cache.contentSentences
        currentVisibleSentenceIndex = nil
        pendingScrollToSentenceIndex = nil
        
        let targetIdx = jumpToLast ? max(0, cache.pages.count - 1) : 0
        self.pageTurnRequest = PageTurnRequest(direction: jumpToLast ? .reverse : .forward, animated: animated, targetIndex: targetIdx)
        self.currentPageIndex = targetIdx
        
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
                isFullyPaginated: result.reachedEnd,
                chapterUrl: currentCache.chapterUrl
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
            isFullyPaginated: result.reachedEnd,
            chapterUrl: currentCache.chapterUrl
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
        let effectiveType = (book.bookUrl.map { preferences.manualMangaUrls.contains($0) } == true) ? 2 : (book.type ?? 0)
        guard let content = try? await apiService.fetchChapterContent(bookUrl: book.bookUrl ?? "", bookSourceUrl: book.origin, index: index, contentType: effectiveType) else { return nil }
        
        let cleaned = removeHTMLAndSVG(content)
        
        // 获取当前章节 URL 并尝试“Cookie 预热”
        let chapterUrl = chapters[index].url
        if book.type == 2 || cleaned.contains("__IMG__") {
            prewarmCookies(for: chapterUrl)
        }
        
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
        
        return ChapterCache(pages: result.pages, renderStore: tk2Store, pageInfos: result.pageInfos, contentSentences: sentences, rawContent: cleaned, attributedText: attrText, paragraphStarts: pStarts, chapterPrefixLen: prefixLen, isFullyPaginated: result.reachedEnd, chapterUrl: chapters[index].url)
    }

    // MARK: - Logic & Actions
    
    private func updateProcessedContent(from rawText: String) {
        let processedContent = applyReplaceRules(to: rawText)
        let trimmedContent = processedContent.trimmingCharacters(in: .whitespacesAndNewlines)
        let isEffectivelyEmpty = trimmedContent.isEmpty
        let content = isEffectivelyEmpty ? "章节内容为空" : processedContent
        currentContent = content
        contentSentences = splitIntoParagraphs(content)
        updateMangaModeState() // 更新模式
        
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
        if preferences.isVerboseLoggingEnabled {
            logger.log("开始处理内容，原始长度: \(text.count)", category: "漫画调试")
        }
        
        var result = text
        // 移除干扰标签
        result = result.replacingOccurrences(of: "<script[^>]*>.*?</script>", with: "", options: [.regularExpression, .caseInsensitive])
        result = result.replacingOccurrences(of: "<style[^>]*>.*?</style>", with: "", options: [.regularExpression, .caseInsensitive])
        result = result.replacingOccurrences(of: "<svg[^>]*>.*?</svg>", with: "", options: [.regularExpression, .caseInsensitive])
        
        // 1. 使用较宽松的正则提取所有 src
        let imgPattern = "<img[^>]+(?:src|data-src)\s*=\s*["']?([^"'\s>]+)["']?[^>]*>"
        
        if let regex = try? NSRegularExpression(pattern: imgPattern, options: .caseInsensitive) {
            let matches = regex.matches(in: result, options: [], range: NSRange(location: 0, length: result.utf16.count))
            
            // 倒序替换，防止偏移量失效
            for match in matches.reversed() {
                if let urlRange = Range(match.range(at: 1), in: result) {
                    let url = String(result[urlRange])
                    
                    // 2. 严格过滤：排除网页链接，保留图片链接
                    let lowerUrl = url.lowercased()
                    let isWebPage = lowerUrl.contains("/mobile/comics/") || lowerUrl.contains("/chapter/") || lowerUrl.contains("/comics/")
                    let isImageHost = lowerUrl.contains("image") || lowerUrl.contains("img") || lowerUrl.contains("tn1")
                    let isImageExt = lowerUrl.contains(".webp") || lowerUrl.contains(".jpg") || lowerUrl.contains(".png") || lowerUrl.contains(".jpeg") || lowerUrl.contains(".gif")
                    
                    // 特殊逻辑：如果是主站域名但完全不含 image/img/tn1 标识，且没有图片后缀，基本确定是网页
                    let isKuaikanPage = lowerUrl.contains("kuaikanmanhua.com") && !isImageHost && !isImageExt
                    
                    if !isWebPage && !isKuaikanPage && (isImageExt || url.contains("?")) {
                        // 有效图片：替换为占位符
                        if let fullRange = Range(match.range, in: result) {
                            result.replaceSubrange(fullRange, with: "\n__IMG__\(url)\n")
                        }
                    } else {
                        // 无效图片/网页链接：直接删除该标签
                        if let fullRange = Range(match.range, in: result) {
                            result.removeSubrange(fullRange)
                        }
                    }
                }
            }
            
            if preferences.isVerboseLoggingEnabled {
                logger.log("完成图片标签清洗，保留了有效的图片占位符", category: "漫画调试")
            }
        }
        
        // 移除所有其他 HTML 标签
        result = result.replacingOccurrences(of: "<[^>]+>", with: "\n", options: .regularExpression)
        
        return result
    }
    
    private func splitIntoParagraphs(_ text: String) -> [String] {
        let lines = text.components(separatedBy: "\n")
        var finalParagraphs: [String] = []
        
        // 启发式判断：如果全文包含图片且文本较少，极可能是漫画，开启更强过滤
        let likelyManga = text.contains("__IMG__") && text.count < 5000
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            
            // 过滤：如果一段内容仅仅是 URL 且没有识别标记，说明是 HTML 剥离后的杂质
            let lowerTrimmed = trimmed.lowercased()
            let isRawUrl = lowerTrimmed.hasPrefix("http") || lowerTrimmed.hasPrefix("//")
            // 高熵文本拦截：很长的连续字母数字串（无空格）通常是杂质
            // 在可能为漫画的章节中，开启更严格的拦截（长度 > 30 且无空格）
            let isHighEntropy = likelyManga && trimmed.count > 30 && !trimmed.contains(" ")
            
            if (isRawUrl || isHighEntropy) && !trimmed.contains("__IMG__") {
                continue
            }
            
            // 进一步拆分，确保 __IMG__ 独立成行
            let parts = trimmed.components(separatedBy: "__IMG__")
            if parts.count > 1 {
                for (i, part) in parts.enumerated() {
                    let p = part.trimmingCharacters(in: .whitespaces)
                    if i == 0 {
                        if !p.isEmpty { finalParagraphs.append(p) }
                    } else {
                        let urlAndText = part
                        let urlParts = urlAndText.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
                        let url = String(urlParts[0]).trimmingCharacters(in: .whitespaces)
                        if !url.isEmpty { finalParagraphs.append("__IMG__" + url) }
                        if urlParts.count > 1 {
                            let remaining = String(urlParts[1]).trimmingCharacters(in: .whitespaces)
                            if !remaining.isEmpty { finalParagraphs.append(remaining) }
                        }
                    }
                }
            } else {
                finalParagraphs.append(trimmed)
            }
        }
        return finalParagraphs
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

        if ttsManager.isPlaying {
            if ttsManager.bookUrl == book.bookUrl {
                // 同一本书：恢复对焦
                currentChapterIndex = ttsManager.currentChapterIndex
                ttsBaseIndex = ttsManager.currentBaseSentenceIndex
                lastTTSSentenceIndex = ttsManager.currentSentenceIndex + ttsBaseIndex
                didApplyResumePos = true 
                pendingResumeLocalBodyIndex = nil
                pendingResumeLocalChapterIndex = nil
                pendingResumeLocalPageIndex = nil
                pendingResumePos = nil
                shouldSyncPageAfterPagination = true
                isTTSSyncingPage = true
                loadChapterContent()
                return
            } else {
                // 不同书：停止之前的播放，并触发保存
                logger.log("检测到切换书籍，停止旧书 TTS 并保存进度: \(ttsManager.bookUrl)", category: "TTS")
                ttsManager.stop()
            }
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
        
        // 判断是否为漫画模式（考虑手动标记）
        let effectiveType = (book.bookUrl.map { preferences.manualMangaUrls.contains($0) } == true) ? 2 : (book.type ?? 0)
        
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
                let content = try await apiService.fetchChapterContent(bookUrl: book.bookUrl ?? "", bookSourceUrl: book.origin, index: chapterIndex, contentType: effectiveType)
                
                // 1. Heavy processing on background thread
                let cleaned = removeHTMLAndSVG(content)
                
                // 获取当前章节 URL 并尝试“Cookie 预热”
                let chapterUrl = chapters[chapterIndex].url
                if book.type == 2 || cleaned.contains("__IMG__") {
                    prewarmCookies(for: chapterUrl)
                }
                
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
                        
                        initialCache = ChapterCache(pages: result.pages, renderStore: tk2Store, pageInfos: result.pageInfos, contentSentences: sentences, rawContent: cleaned, attributedText: attrText, paragraphStarts: pStarts, chapterPrefixLen: prefixLen, isFullyPaginated: result.reachedEnd, chapterUrl: chapterTitle.isEmpty ? book.bookUrl : chapters[chapterIndex].url)
                        
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
                    
                    self.rawContent = cleaned
                    if let cache = initialCache {
                        self.contentSentences = sentences
                        updateMangaModeState() // 关键：更新模式
                        self.currentContent = processed
                        self.currentCache = cache
                        
                        // 初始对焦：静默同步模式
                        if let ttsIdx = capturedTTSIndex {
                            self.isTTSSyncingPage = true
                            self.isAutoFlipping = true // 关键：标记为自动对焦，防止重启 TTS
                            self.lastTTSSentenceIndex = ttsIdx
                        }
                        
                        // 先设页码，再发跳转指令
                        self.currentPageIndex = targetPageIndex
                        self.pageTurnRequest = PageTurnRequest(direction: .forward, animated: false, targetIndex: targetPageIndex)
                        
                        self.didApplyResumePos = true 
                        if !self.hasInitialPagination, !cache.pages.isEmpty { self.hasInitialPagination = true }
                        
                        // Set the pagination key to current state to prevent immediate redundant re-pagination
                        self.lastPaginationKey = PaginationKey(width: Int(targetPageSize.width * 100), height: Int(targetPageSize.height * 100), fontSize: Int(fontSize * 10), lineSpacing: Int(lineSpacing * 10), margin: Int(margin * 10), sentenceCount: sentences.count, chapterIndex: chapterIndex, resumeCharIndex: -1, resumePageIndex: -1)
                        
                        // 给予足够宽裕的时间（0.8s）让 UIKit 的 setViewControllers 完成
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                            self.isTTSSyncingPage = false
                            self.isAutoFlipping = false
                        }
                    } else {
                        // 回落逻辑
                        updateProcessedContent(from: cleaned)
                    }
                    
                    if self.shouldSyncPageAfterPagination {
                        let currentIndex = self.ttsManager.currentSentenceIndex + self.ttsBaseIndex
                        let baselineIndex = capturedTTSIndex ?? currentIndex
                        if abs(currentIndex - baselineIndex) >= 2 {
                            self.syncPageForSentenceIndex(self.ttsManager.currentSentenceIndex)
                        }
                        self.shouldSyncPageAfterPagination = false
                    }
                    
                    // 垂直模式置顶逻辑
                    if self.preferences.readingMode == .vertical && capturedTTSIndex == nil && !shouldResume {
                        self.pendingScrollToSentenceIndex = 0
                        self.handlePendingScroll()
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
    
    private func previousChapter(animated: Bool = false) {
        guard currentChapterIndex > 0 else { return }
        isExplicitlySwitchingChapter = true // 标记开始切章
        didApplyResumePos = true
        currentVisibleSentenceIndex = nil
        let targetIndex = currentChapterIndex - 1
        
        if !prevCache.pages.isEmpty {
            let cached = prevCache
            if animated {
                // 带动画：不立即更新状态，先发翻页请求
                pageTurnRequest = PageTurnRequest(
                    direction: .reverse,
                    animated: true,
                    targetIndex: max(0, cached.pages.count - 1),
                    targetSnapshot: snapshot(from: cached),
                    targetChapterIndex: targetIndex
                )
            } else {
                // 不带动画：立即更新状态（如目录跳转）
                nextCache = currentCache
                prevCache = .empty
                applyCachedChapter(cached, chapterIndex: targetIndex, jumpToFirst: false, jumpToLast: true, animated: false)
                finishChapterSwitch()
            }
            return
        }
        currentChapterIndex = targetIndex
        loadChapterContent()
        saveProgress()
    }
    
    private func nextChapter(animated: Bool = false) {
        guard currentChapterIndex < chapters.count - 1 else { return }
        isExplicitlySwitchingChapter = true // 标记开始切章
        didApplyResumePos = true
        currentVisibleSentenceIndex = nil
        let targetIndex = currentChapterIndex + 1
        
        if !nextCache.pages.isEmpty {
            let cached = nextCache
            if animated {
                // 带动画：先发请求，不切数据
                pageTurnRequest = PageTurnRequest(
                    direction: .forward,
                    animated: true,
                    targetIndex: 0,
                    targetSnapshot: snapshot(from: cached),
                    targetChapterIndex: targetIndex
                )
            } else {
                // 不带动画：立即更新
                prevCache = currentCache
                nextCache = .empty
                applyCachedChapter(cached, chapterIndex: targetIndex, jumpToFirst: true, jumpToLast: false, animated: false)
                finishChapterSwitch()
            }
            return
        }
        currentChapterIndex = targetIndex
        loadChapterContent()
        saveProgress()
    }
    
    private func finalizeAnimatedChapterSwitch(targetChapter: Int, targetPage: Int) {
        let isForward = targetChapter > currentChapterIndex
        let cached = isForward ? nextCache : prevCache
        guard !cached.pages.isEmpty else { return }
        
        // 交换缓存
        if isForward {
            prevCache = currentCache
            nextCache = .empty
        } else {
            nextCache = currentCache
            prevCache = .empty
        }
        
        // 更新主状态
        suppressRepaginateOnce = true
        currentChapterIndex = targetChapter
        currentCache = cached
        rawContent = cached.rawContent
        currentContent = cached.contentSentences.joined(separator: "\n")
        contentSentences = cached.contentSentences
        currentVisibleSentenceIndex = nil
        pendingScrollToSentenceIndex = nil
        
        currentPageIndex = targetPage
        
        // 完成后续逻辑（TTS等）
        finishChapterSwitch()
    }
    
    private func finishChapterSwitch() {
        ttsBaseIndex = 0
        prepareAdjacentChaptersIfNeeded(for: currentChapterIndex)
        if ttsManager.isPlaying && !ttsManager.isPaused {
            lastTTSSentenceIndex = 0
            requestTTSPlayback(pageIndexOverride: currentPageIndex, showControls: false)
        }
        saveProgress()
    }
    
    private func prewarmCookies(for urlString: String) {
        guard let url = URL(string: urlString) else { return }
        if preferences.isVerboseLoggingEnabled { logger.log("正在预热 Cookie: \(urlString)", category: "漫画调试") }
        
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD" // 轻量级请求
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_4_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4.1 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        
        URLSession.shared.dataTask(with: request) { _, _, _ in
            // 仅需请求发生，系统会自动处理 Set-Cookie
            if self.preferences.isVerboseLoggingEnabled { self.logger.log("Cookie 预热完成", category: "漫画调试") }
        }.resume()
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
        ttsManager.startReading(text: textForTTS, chapters: chapters, currentIndex: currentChapterIndex, bookUrl: book.bookUrl ?? "", bookSourceUrl: book.origin, bookTitle: book.name ?? "阅读", coverUrl: book.displayCoverUrl, onChapterChange: {
            self.isAutoFlipping = true
            if self.switchChapterUsingCacheIfAvailable(targetIndex: $0, jumpToFirst: true, jumpToLast: false) {
                self.lastTTSSentenceIndex = 0
                self.saveProgress()
                return
            }
            self.isTTSAutoChapterChange = true
            self.didApplyResumePos = true
            self.currentVisibleSentenceIndex = nil
            self.currentChapterIndex = $0
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
            if first.key != currentVisibleSentenceIndex {
                currentVisibleSentenceIndex = first.key
            }
        }
    }
    
    private func toggleSleepTimer(minutes: Int) {
        sleepTimer?.invalidate()
        sleepTimer = nil
        
        if minutes == 0 {
            timerRemaining = 0
            timerActive = false
            return
        }
        
        timerRemaining = minutes
        timerActive = true
        
        sleepTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            if self.timerRemaining > 1 {
                self.timerRemaining -= 1
            } else {
                self.timerRemaining = 0
                self.timerActive = false
                self.sleepTimer?.invalidate()
                self.sleepTimer = nil
                self.ttsManager.stop() // 时间到，停止播放
            }
        }
    }
}

	private struct ReadPageViewController: UIViewControllerRepresentable {
	    var snapshot: PageSnapshot
	    var prevSnapshot: PageSnapshot?
	    var nextSnapshot: PageSnapshot?
    
    @Binding var currentPageIndex: Int
    @Binding var pageTurnRequest: PageTurnRequest?
    var pageSpacing: CGFloat
    var transitionStyle: UIPageViewController.TransitionStyle
    var onTransitioningChanged: (Bool) -> Void
    var onTapLocation: (ReaderTapLocation) -> Void
    var onChapterChange: (Int) -> Void
    var onAdjacentPrefetch: (Int) -> Void
    var onAddReplaceRule: (String) -> Void
    var onChapterSwitchRequest: (Int, Int) -> Void // 新增：通知父级完成状态同步
    var currentContentViewController: ReadContentViewController?
    var prevContentViewController: ReadContentViewController?
    var nextContentViewController: ReadContentViewController?
    var makeViewController: (PageSnapshot, Int, Int) -> ReadContentViewController?

    func makeUIViewController(context: Context) -> UIPageViewController {
        let pvc = UIPageViewController(transitionStyle: transitionStyle, navigationOrientation: .horizontal, options: [UIPageViewController.OptionsKey.interPageSpacing: pageSpacing])
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
        
        // 处理翻页请求
        if let request = pageTurnRequest {
            context.coordinator.handlePageTurnRequest(request, in: pvc)
        } else {
            context.coordinator.updateSnapshotIfNeeded(snapshot, currentPageIndex: currentPageIndex)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: ReadPageViewController
        var isAnimating = false
        private var lastProcessedRequestTimestamp: TimeInterval = 0
	        private var snapshot: PageSnapshot?
	        private var pendingSnapshot: PageSnapshot?
        weak var pageViewController: UIPageViewController? 
        var currentContentViewController: ReadContentViewController?
        var prevContentViewController: ReadContentViewController?
        var nextContentViewController: ReadContentViewController?
        
        init(_ parent: ReadPageViewController) { self.parent = parent }
        
        func handlePageTurnRequest(_ request: PageTurnRequest, in pvc: UIPageViewController) {
            guard request.timestamp > lastProcessedRequestTimestamp else { return }
            lastProcessedRequestTimestamp = request.timestamp
            
            // 动画锁
            if isAnimating { return }
            
            // 确定快照：如果请求自带快照（跨章），则用请求的；否则用当前的。
            let activeSnapshot = request.targetSnapshot ?? snapshot ?? parent.snapshot
            guard request.targetIndex >= 0, request.targetIndex < activeSnapshot.pages.count else {
                DispatchQueue.main.async { self.parent.pageTurnRequest = nil }
                return
            }
            
            guard let vc = parent.makeViewController(activeSnapshot, request.targetIndex, 0) else { return }
            
            isAnimating = true
            pvc.setViewControllers([vc], direction: request.direction, animated: request.animated) { finished in
                self.isAnimating = false
                if finished {
                    DispatchQueue.main.async {
                        // 如果是跨章请求，通知父级进行真正的数据结构交换
                        if let targetChapter = request.targetChapterIndex {
                            self.parent.onChapterSwitchRequest(targetChapter, request.targetIndex)
                        } else {
                            self.parent.currentPageIndex = request.targetIndex
                        }
                        self.parent.pageTurnRequest = nil
                    }
                }
            }
        }

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
    let renderStore: TextKit2RenderStore?
    let sentences: [String]?
    let chapterUrl: String? // 新增
    let chapterOffset: Int
    let onAddReplaceRule: ((String) -> Void)?
    let onTapLocation: ((ReaderTapLocation) -> Void)?
    
    // Highlight state
    var highlightIndex: Int?
    var secondaryIndices: Set<Int> = []
    var isPlayingHighlight: Bool = false
    var paragraphStarts: [Int] = []
    var chapterPrefixLen: Int = 0
    
    private var tk2View: ReadContent2View?
    private var pendingPageInfo: TK2PageInfo?
    
    init(pageIndex: Int, renderStore: TextKit2RenderStore?, sentences: [String]? = nil, chapterUrl: String? = nil, chapterOffset: Int, onAddReplaceRule: ((String) -> Void)?, onTapLocation: ((ReaderTapLocation) -> Void)?) {
        self.pageIndex = pageIndex
        self.renderStore = renderStore
        self.sentences = sentences
        self.chapterUrl = chapterUrl
        self.chapterOffset = chapterOffset
        self.onAddReplaceRule = onAddReplaceRule
        self.onTapLocation = onTapLocation
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.systemBackground
        if let store = renderStore {
            setupTK2View(store: store)
        }
    }
    
    private func setupTK2View(store: TextKit2RenderStore) {
         let v = ReadContent2View(frame: view.bounds)
         v.autoresizingMask = [.flexibleWidth, .flexibleHeight]
         v.renderStore = store
         v.onTapLocation = onTapLocation
         v.onAddReplaceRule = onAddReplaceRule
         v.highlightIndex = highlightIndex
         v.secondaryIndices = secondaryIndices
         v.isPlayingHighlight = isPlayingHighlight
         v.paragraphStarts = paragraphStarts
         v.chapterPrefixLen = chapterPrefixLen
         view.addSubview(v)
         self.tk2View = v
         if let pendingPageInfo {
             v.pageInfo = pendingPageInfo
             v.setNeedsDisplay()
         }
    }
    
    func updateHighlights(index: Int?, secondary: Set<Int>, isPlaying: Bool, starts: [Int], prefixLen: Int) {
        self.highlightIndex = index
        self.secondaryIndices = secondary
        self.isPlayingHighlight = isPlaying
        self.paragraphStarts = starts
        self.chapterPrefixLen = prefixLen
        
        tk2View?.highlightIndex = index
        tk2View?.secondaryIndices = secondary
        tk2View?.isPlayingHighlight = isPlaying
        tk2View?.paragraphStarts = starts
        tk2View?.chapterPrefixLen = prefixLen
        tk2View?.setNeedsDisplay()
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
    let bookUrl: String
    let onSelectChapter: (Int) -> Void
    @Environment(\.dismiss) var dismiss
    @State private var isReversed = false
    @State private var selectedGroupIndex: Int
    
    init(chapters: [BookChapter], currentIndex: Int, bookUrl: String, onSelectChapter: @escaping (Int) -> Void) {
        self.chapters = chapters
        self.currentIndex = currentIndex
        self.bookUrl = bookUrl
        self.onSelectChapter = onSelectChapter
        self._selectedGroupIndex = State(initialValue: currentIndex / 50)
    }
    
    var chapterGroups: [Int] {
        guard !chapters.isEmpty else { return [] }
        return Array(0...((chapters.count - 1) / 50))
    }
    
    var displayedChapters: [(offset: Int, element: BookChapter)] {
        let startIndex = selectedGroupIndex * 50
        let endIndex = min(startIndex + 50, chapters.count)
        let slice = chapters.indices.contains(startIndex) ? Array(chapters[startIndex..<endIndex].enumerated()).map { (offset: $0.offset + startIndex, element: $0.element) } : []
        return isReversed ? Array(slice.reversed()) : slice
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
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
                        .padding()
                    }
                    Divider()
                }
                
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
                                    if LocalCacheManager.shared.isChapterCached(bookUrl: bookUrl, index: item.offset) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                            .font(.caption)
                                    }
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
    var chapterUrl: String? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: fontSize * 0.8) {
            ForEach(Array(sentences.enumerated()), id: \.offset) { index, sentence in
                if sentence.contains("__IMG__") {
                    let urlString = extractImageUrl(from: sentence)
                    MangaImageView(url: urlString, referer: chapterUrl)
                        .id(index)
                        .padding(.vertical, 4)
                } else {
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            if let highlightIndex = highlightIndex, let scrollProxy = scrollProxy {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { withAnimation { scrollProxy.scrollTo(highlightIndex, anchor: .center) } }
            }
        }
    }
    
    private func extractImageUrl(from text: String) -> String {
        // 查找 __IMG__ 标记后的内容，直到遇到空格或结尾
        guard let range = text.range(of: "__IMG__") else { return "" }
        let urlPart = text[range.upperBound...]
        // 提取连续的 URL 字符，遇到换行或空格停止
        let url = urlPart.prefix { !$0.isWhitespace }
        return String(url)
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

private struct MangaImageView: View {
    let url: String
    let referer: String?
    @EnvironmentObject var apiService: APIService
    @StateObject private var preferences = UserPreferences.shared
    private let logger = LogManager.shared
    
    var body: some View {
        let finalURL = resolveURL(url)
        RemoteImageView(url: finalURL, refererOverride: referer)
            .frame(maxWidth: .infinity)
            .onAppear {
                if preferences.isVerboseLoggingEnabled {
                    let logReferer = referer?.replacingOccurrences(of: "http://", with: "https://") ?? "无"
                    logger.log("准备加载图片: \(finalURL?.lastPathComponent ?? "无效"), 来源: \(logReferer)", category: "漫画调试")
                }
            }
    }
    
    private func resolveURL(_ original: String) -> URL? {
        if original.hasPrefix("http") {
            return URL(string: original)
        }
        let baseURL = apiService.baseURL.replacingOccurrences(of: "/api/\(APIService.apiVersion)", with: "")
        let resolved = original.hasPrefix("/") ? (baseURL + original) : (baseURL + "/" + original)
        return URL(string: resolved)
    }
}

// MARK: - Zoomable ScrollView for Manga
struct ZoomableScrollView<Content: View>: UIViewRepresentable {
    private var content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.maximumZoomScale = 4.0
        scrollView.minimumZoomScale = 1.0
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.backgroundColor = .clear

        let hostedView = UIHostingController(rootView: content)
        hostedView.view.translatesAutoresizingMaskIntoConstraints = false
        hostedView.view.backgroundColor = .clear
        scrollView.addSubview(hostedView.view)

        NSLayoutConstraint.activate([
            hostedView.view.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            hostedView.view.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            hostedView.view.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            hostedView.view.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            hostedView.view.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor)
        ])

        return scrollView
    }

    func updateUIView(_ uiView: UIScrollView, context: Context) { }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, UIScrollViewDelegate {
        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            return scrollView.subviews.first
        }
    }
}

// MARK: - 支持 Header 的高性能图片加载组件
struct RemoteImageView: View {
    let url: URL?
    let refererOverride: String? // 新增：强制来源页覆盖
    @State private var image: UIImage? = nil
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @StateObject private var preferences = UserPreferences.shared
    private let logger = LogManager.shared

    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .frame(minHeight: 200) // 基础高度占位，防止容器塌陷
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "photo.fill")
                        .font(.largeTitle)
                        .foregroundColor(.gray)
                    Text(errorMessage ?? "图片加载失败")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let url = url {
                        Text(url.absoluteString).font(.system(size: 8)).lineLimit(1).foregroundColor(.gray)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 200) // 失败也要保持高度
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .onAppear(perform: loadImage)
        .onChange(of: url) { _ in loadImage() }
    }

    private func loadImage() {
        guard let url = url else {
            errorMessage = "URL 无效"
            return
        }
        
        if image != nil || isLoading { return }
        isLoading = true
        errorMessage = nil

        // 如果开启了强制代理，则直接跳过直接请求，进入代理逻辑
        if preferences.forceMangaProxy, let proxyURL = buildProxyURL(for: url) {
            if preferences.isVerboseLoggingEnabled { logger.log("开启强制代理模式，直接中转...", category: "漫画调试") }
            fetchImage(from: proxyURL, useProxy: true)
        } else {
            fetchImage(from: url, useProxy: false)
        }
    }

        private func fetchImage(from targetURL: URL, useProxy: Bool) {
            var request = URLRequest(url: targetURL)
            request.timeoutInterval = 15
            request.httpShouldHandleCookies = true
            request.cachePolicy = .returnCacheDataElseLoad
            
            // 1:1 模拟真实移动端浏览器请求头
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_4_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4.1 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
            request.setValue("image/webp,image/avif,image/apng,image/svg+xml,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
            request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
            request.setValue("gzip, deflate, br", forHTTPHeaderField: "Accept-Encoding")
            request.setValue("keep-alive", forHTTPHeaderField: "Connection")
            request.setValue("no-cors", forHTTPHeaderField: "Sec-Fetch-Mode")
            request.setValue("image", forHTTPHeaderField: "Sec-Fetch-Dest")
            request.setValue("cross-site", forHTTPHeaderField: "Sec-Fetch-Site")
            
            // 核心修正：Referer 精准策略
            var finalReferer = "https://m.kuaikanmanhua.com/" // 基础兜底
            
            if var customReferer = refererOverride, !customReferer.isEmpty {
                // 协议对齐
                if customReferer.hasPrefix("http://") {
                    customReferer = customReferer.replacingOccurrences(of: "http://", with: "https://")
                }
                // 补全斜杠
                if !customReferer.hasSuffix("/") {
                    customReferer += "/"
                }
                finalReferer = customReferer
            } else if let host = targetURL.host {
                // 自动推断兜底
                finalReferer = "https://\(host)/"
            }
            
            request.setValue(finalReferer, forHTTPHeaderField: "Referer")
    
            URLSession.shared.dataTask(with: request) { data, response, error in
                DispatchQueue.main.async {
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                    
                    if statusCode == 200, let data = data, !data.isEmpty, let loadedImage = UIImage(data: data) {
                        self.image = loadedImage
                        self.isLoading = false
                        if preferences.isVerboseLoggingEnabled { logger.log("图片加载成功: \(targetURL.lastPathComponent)", category: "漫画调试") }
                        return
                    }
    
                    // 错误处理与重试逻辑
                    if !useProxy {
                        if (statusCode == 403 || statusCode == 401) {
                            // 如果因为 Referer 被拒，尝试最简主站 Referer 重试
                            if preferences.isVerboseLoggingEnabled { logger.log("Referer 受阻(403)，降级重试...", category: "漫画调试") }
                            var retryRequest = request
                            retryRequest.setValue("https://m.kuaikanmanhua.com/", forHTTPHeaderField: "Referer")
                            URLSession.shared.dataTask(with: retryRequest) { data, response, _ in
                                DispatchQueue.main.async {
                                    let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                                    if code == 200, let data = data, !data.isEmpty, let loadedImage = UIImage(data: data) {
                                        self.image = loadedImage
                                        self.isLoading = false
                                        if preferences.isVerboseLoggingEnabled { logger.log("图片重试成功: \(targetURL.lastPathComponent)", category: "漫画调试") }
                                    } else if let proxyURL = buildProxyURL(for: targetURL) {
                                        if preferences.isVerboseLoggingEnabled { logger.log("重试失败(Code:\(code))，切换代理...", category: "漫画调试") }
                                        self.fetchImage(from: proxyURL, useProxy: true)
                                    } else {
                                        self.isLoading = false
                                        self.errorMessage = "加载失败"
                                    }
                                }
                            }.resume()
                        } else if let proxyURL = buildProxyURL(for: targetURL) {
                            if preferences.isVerboseLoggingEnabled { logger.log("直接请求失败(Code:\(statusCode))，尝试代理...", category: "漫画调试") }
                            self.fetchImage(from: proxyURL, useProxy: true)
                        } else {
                            self.isLoading = false
                            self.errorMessage = "加载失败"
                        }
                    } else {
                        self.isLoading = false
                        self.errorMessage = "加载失败"
                    }
                }
            }.resume()
        }
    private func buildProxyURL(for original: URL) -> URL? {
        let baseURL = APIService.shared.baseURL
        var components = URLComponents(string: "\(baseURL)/proxypng")
        components?.queryItems = [
            URLQueryItem(name: "url", value: original.absoluteString),
            URLQueryItem(name: "accessToken", value: UserPreferences.shared.accessToken)
        ]
        return components?.url
    }
}

private struct SentenceFramePreferenceKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) { value.merge(nextValue(), uniquingKeysWith: { $1 }) }
}

private struct TTSControlBar: View {
    @ObservedObject var ttsManager: TTSManager
    @StateObject private var preferences = UserPreferences.shared
    let currentChapterIndex: Int
    let chaptersCount: Int
    
    let timerRemaining: Int
    let timerActive: Bool
    
    let onPreviousChapter: () -> Void
    let onNextChapter: () -> Void
    let onShowChapterList: () -> Void
    let onTogglePlayPause: () -> Void
    let onSetTimer: (Int) -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            // 第一行：播放进度与定时
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("段落进度").font(.caption2).foregroundColor(.secondary)
                    Text("\(ttsManager.currentSentenceIndex + 1) / \(ttsManager.totalSentences)")
                        .font(.system(.subheadline, design: .monospaced))
                        .fontWeight(.bold)
                }
                
                Spacer() 
                
                // 定时按钮
                Menu {
                    Button("取消定时") { onSetTimer(0) }
                    Divider()
                    Button("15 分钟") { onSetTimer(15) }
                    Button("30 分钟") { onSetTimer(30) }
                    Button("60 分钟") { onSetTimer(60) }
                    Button("90 分钟") { onSetTimer(90) }
                } label: {
                    Label(timerActive ? "\(timerRemaining)m" : "定时", systemImage: timerActive ? "timer" : "timer")
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(timerActive ? Color.orange.opacity(0.1) : Color.gray.opacity(0.1))
                        .foregroundColor(timerActive ? .orange : .secondary)
                        .cornerRadius(12)
                }
            }
            .padding(.horizontal, 20)
            
            // 第二行：语速调节
            HStack(spacing: 12) {
                Image(systemName: "speedometer").font(.caption).foregroundColor(.secondary)
                Slider(value: $preferences.speechRate, in: 50...300, step: 10)
                    .accentColor(.blue)
                Text("\(Int(preferences.speechRate))%")
                    .font(.system(.caption, design: .monospaced))
                    .frame(width: 45)
            }
            .padding(.horizontal, 20)
            
            // 第三行：核心播放控制
            HStack(spacing: 0) {
                IconButton(icon: "chevron.left", label: "上章", action: onPreviousChapter, enabled: currentChapterIndex > 0)
                Spacer()
                IconButton(icon: "backward.fill", label: "上段", action: { ttsManager.previousSentence() }, enabled: ttsManager.currentSentenceIndex > 0)
                Spacer()
                
                Button(action: onTogglePlayPause) {
                    ZStack {
                        Circle().fill(Color.blue).frame(width: 56, height: 56)
                        Image(systemName: ttsManager.isPaused ? "play.fill" : "pause.fill")
                            .font(.title2).foregroundColor(.white)
                    }
                }
                
                Spacer()
                IconButton(icon: "forward.fill", label: "下段", action: { ttsManager.nextSentence() }, enabled: ttsManager.currentSentenceIndex < ttsManager.totalSentences - 1)
                Spacer()
                IconButton(icon: "chevron.right", label: "下章", action: onNextChapter, enabled: currentChapterIndex < chaptersCount - 1)
            }
            .padding(.horizontal, 20)
            
            // 第四行：功能入口
            HStack {
                Button(action: onShowChapterList) {
                    Label("目录", systemImage: "list.bullet")
                }
                Spacer()
                Button(action: { ttsManager.stop() }) {
                    Label("停止播放", systemImage: "stop.circle")
                        .foregroundColor(.red)
                }
            }
            .font(.caption)
            .padding(.horizontal, 25)
            .padding(.bottom, 8)
        }
        .padding(.vertical, 12)
        .background(Color(UIColor.systemBackground))
        .shadow(color: Color.black.opacity(0.1), radius: 5, y: -2)
    }
}

private struct IconButton: View {
    let icon: String
    let label: String
    let action: () -> Void
    var enabled: Bool = true
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.title3)
                Text(label).font(.system(size: 10))
            }
            .frame(width: 44)
            .foregroundColor(enabled ? .primary : .gray.opacity(0.3))
        }
        .disabled(!enabled)
    }
}

private struct NormalControlBar: View {
    let currentChapterIndex: Int
    let chaptersCount: Int
    let isMangaMode: Bool
    @Binding var isForceLandscape: Bool // 新增
    let onPreviousChapter: () -> Void
    let onNextChapter: () -> Void
    let onShowChapterList: () -> Void
    let onToggleTTS: () -> Void
    let onShowFontSettings: () -> Void
    
    var body: some View {
        HStack(spacing: 0) {
            // 左侧：翻页与目录
            HStack(spacing: 20) {
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
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // 中间：功能扩展区（填充空白）
            HStack(spacing: 25) {
                if isMangaMode {
                    // 漫画模式特有按钮
                    Button(action: { withAnimation { isForceLandscape.toggle() } }) {
                        VStack(spacing: 4) {
                            Image(systemName: isForceLandscape ? "iphone.smartrotate.forward" : "iphone.landscape").font(.title2)
                            Text(isForceLandscape ? "竖屏" : "横屏").font(.caption2)
                        }
                    }
                    .foregroundColor(isForceLandscape ? .blue : .primary)
                } else {
                    Button(action: onToggleTTS) {
                        VStack(spacing: 4) {
                            Image(systemName: "speaker.wave.2.circle.fill").font(.system(size: 32)).foregroundColor(.blue)
                            Text("听书").font(.caption2).foregroundColor(.blue)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            
            // 右侧：选项与下一章
            HStack(spacing: 20) {
                Button(action: onShowFontSettings) {
                    VStack(spacing: 4) {
                        Image(systemName: isMangaMode ? "gearshape" : "slider.horizontal.3").font(.title2)
                        Text("选项").font(.caption2)
                    }
                }
                
                Button(action: onNextChapter) {
                    VStack(spacing: 4) {
                        Image(systemName: "chevron.right").font(.title2)
                        Text("下一章").font(.caption2)
                    }
                }.disabled(currentChapterIndex >= chaptersCount - 1)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(Color(UIColor.systemBackground))
        .shadow(color: Color.black.opacity(0.1), radius: 5, y: -2)
    }
}

private struct ReaderOptionsSheet: View {
    @ObservedObject var preferences: UserPreferences
    let isMangaMode: Bool
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            Form {
                if !isMangaMode {
                    Section(header: Text("显示设置")) {
                        Picker("阅读模式", selection: $preferences.readingMode) {
                            ForEach(ReadingMode.allCases) {
                                Text($0.localizedName).tag($0)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.vertical, 4)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("字体大小: \(String(format: "%.0f", preferences.fontSize))")
                                .font(.subheadline)
                            Slider(value: $preferences.fontSize, in: 12...30, step: 1)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("行间距: \(String(format: "%.0f", preferences.lineSpacing))")
                                .font(.subheadline)
                            Slider(value: $preferences.lineSpacing, in: 4...20, step: 2)
                        }
                    }
                    
                    Section(header: Text("页面布局")) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("左右边距: \(String(format: "%.0f", preferences.pageHorizontalMargin))")
                                .font(.subheadline)
                            Slider(value: $preferences.pageHorizontalMargin, in: 0...50, step: 1)
                        }
                    }
                }
                
                Section(header: Text("夜间模式")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("模式切换").font(.subheadline).foregroundColor(.secondary)
                        Picker("夜间模式", selection: $preferences.darkMode) {
                            ForEach(DarkModeConfig.allCases) {
                                Text($0.localizedName).tag($0)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.vertical, 4)
                }
                
                if isMangaMode {
                    Section(header: Text("高级设置")) {
                        Toggle("强制服务器代理", isOn: $preferences.forceMangaProxy)
                    }
                }
            }
            .navigationTitle("阅读选项")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
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
        
        guard !documentRange.isEmpty, pageSize.width > 1, pageSize.height > 1 else { return PaginationResult(pages: [], pageInfos: [], reachedEnd: true) }

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
            let lineEdgeInset = max(2.0, contentInset * 0.05) // Reduced inset for line edges
            let lineEdgeSlack: CGFloat = 0 // Slack for line edge detection
            
            var pageFragmentMaxY: CGFloat?
            var pageEndLocation: NSTextLocation = currentContentLocation
            
            layoutManager.enumerateTextLayoutFragments(from: currentContentLocation, options: [.ensuresLayout, .ensuresExtraLineFragment]) { fragment in
                let fragmentFrame = fragment.layoutFragmentFrame
                let fragmentRange = TextKit2Paginator.rangeFromTextRange(fragment.rangeInElement, in: contentStorage)
                
                if fragmentFrame.minY >= pageRect.maxY { return false } // Fragment starts below page bottom
                
                // If fragment is completely above (shouldn't happen with correct startY), skip
                if fragmentFrame.maxY <= pageStartY { return true } // Fragment ends above page top

                if pageFragmentMaxY == nil { pageFragmentMaxY = max(pageStartY, fragmentFrame.minY) } // Initialize with the highest point of the first visible fragment part
                
                if fragmentFrame.maxY <= pageRect.maxY {
                    // Fragment fits entirely
                    pageFragmentMaxY = fragmentFrame.maxY
                    if let fragmentRange = fragmentRange,
                       let loc = contentStorage.location(documentRange.location, offsetBy: NSMaxRange(fragmentRange)) {
                        pageEndLocation = loc
                    } else {
                        pageEndLocation = fragment.rangeInElement.endLocation
                    }
                    return true // Continue to next fragment
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
                            break // Line exceeds page boundary
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
                    return false // Stop enumeration after handling split fragment
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
                    break // Cannot advance, exit loop
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
    var highlightIndex: Int?
    var secondaryIndices: Set<Int> = []
    var isPlayingHighlight: Bool = false
    var paragraphStarts: [Int] = []
    var chapterPrefixLen: Int = 0
    
    private var tk2View: ReadContent2View? // This seems like a typo, should likely be a different name or removed if ReadContent2View is the class itself.
    private var pendingPageInfo: TK2PageInfo?
    
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
        
        // 渲染背景高亮
        if isPlayingHighlight {
            context?.saveGState()
            
            // 准备高亮范围映射
            func getRangeForSentence(_ index: Int) -> NSRange? {
                guard index >= 0 && index < paragraphStarts.count else { return nil }
                let start = paragraphStarts[index] + chapterPrefixLen
                let end = (index + 1 < paragraphStarts.count) ? (paragraphStarts[index + 1] + chapterPrefixLen) : store.attributedString.length
                return NSRange(location: start, length: end - start)
            }
            
            let highlightIndices = ([highlightIndex].compactMap { $0 }) + Array(secondaryIndices)
            
            for index in highlightIndices {
                guard let sRange = getRangeForSentence(index) else { continue }
                let intersection = NSIntersectionRange(sRange, info.range)
                if intersection.length <= 0 { continue }
                
                let color = (index == highlightIndex) ? UIColor.systemBlue.withAlphaComponent(0.2) : UIColor.systemGreen.withAlphaComponent(0.12)
                context?.setFillColor(color.cgColor)
                
                // 找到相交行的矩形区域
                store.layoutManager.enumerateTextLayoutFragments(from: store.contentStorage.location(store.contentStorage.documentRange.location, offsetBy: intersection.location), options: [.ensuresLayout]) { fragment in
                    let fFrame = fragment.layoutFragmentFrame
                    guard let fRange = TextKit2Paginator.rangeFromTextRange(fragment.rangeInElement, in: store.contentStorage) else { return true }
                    
                    if fRange.location >= NSMaxRange(intersection) { return false }
                    
                    for line in fragment.textLineFragments {
                        let lStart = fRange.location + line.characterRange.location
                        let lEnd = fRange.location + line.characterRange.upperBound
                        
                        let lInter = NSIntersectionRange(NSRange(location: lStart, length: lEnd - lStart), intersection)
                        if lInter.length > 0 {
                            // 计算行内具体字符的 X 偏移（简化处理：整行高亮，因为阅读器通常是按段落/句子请求音频）
                            let lineFrame = line.typographicBounds.offsetBy(dx: fFrame.origin.x, dy: fFrame.origin.y)
                            let highlightRect = CGRect(x: 0, y: lineFrame.minY, width: bounds.width, height: lineFrame.height)
                            context?.fill(highlightRect)
                        }
                    }
                    return true
                }
            }
            context?.restoreGState()
        }
        
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

private struct ControlButton: View {
    let icon: String; let label: String; let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 22))
                Text(label).font(.system(size: 10))
            }
            .frame(maxWidth: .infinity)
            .foregroundColor(.primary)
        }
    }
}

private struct NormalControlBar: View {
    let currentChapterIndex: Int
    let chaptersCount: Int
    let isMangaMode: Bool
    @Binding var isForceLandscape: Bool // 新增
    let onPreviousChapter: () -> Void
    let onNextChapter: () -> Void
    let onShowChapterList: () -> Void
    let onToggleTTS: () -> Void
    let onShowFontSettings: () -> Void
    
    var body: some View {
        HStack(spacing: 0) {
            // 左侧：翻页与目录
            HStack(spacing: 20) {
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
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // 中间：功能扩展区（填充空白）
            HStack(spacing: 25) {
                if isMangaMode {
                    // 漫画模式特有按钮
                    Button(action: { withAnimation { isForceLandscape.toggle() } }) {
                        VStack(spacing: 4) {
                            Image(systemName: isForceLandscape ? "iphone.smartrotate.forward" : "iphone.landscape").font(.title2)
                            Text(isForceLandscape ? "竖屏" : "横屏").font(.caption2)
                        }
                    }
                    .foregroundColor(isForceLandscape ? .blue : .primary)
                } else {
                    Button(action: onToggleTTS) {
                        VStack(spacing: 4) {
                            Image(systemName: "speaker.wave.2.circle.fill").font(.system(size: 32)).foregroundColor(.blue)
                            Text("听书").font(.caption2).foregroundColor(.blue)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            
            // 右侧：选项与下一章
            HStack(spacing: 20) {
                Button(action: onShowFontSettings) {
                    VStack(spacing: 4) {
                        Image(systemName: isMangaMode ? "gearshape" : "slider.horizontal.3").font(.title2)
                        Text("选项").font(.caption2)
                    }
                }
                
                Button(action: onNextChapter) {
                    VStack(spacing: 4) {
                        Image(systemName: "chevron.right").font(.title2)
                        Text("下一章").font(.caption2)
                    }
                }.disabled(currentChapterIndex >= chaptersCount - 1)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(Color(UIColor.systemBackground))
        .shadow(color: Color.black.opacity(0.1), radius: 5, y: -2)
    }
}

private struct ReaderOptionsSheet: View {
    @ObservedObject var preferences: UserPreferences
    let isMangaMode: Bool
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            Form {
                if !isMangaMode {
                    Section(header: Text("显示设置")) {
                        Picker("阅读模式", selection: $preferences.readingMode) {
                            ForEach(ReadingMode.allCases) {
                                Text($0.localizedName).tag($0)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.vertical, 4)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("字体大小: \(String(format: "%.0f", preferences.fontSize))")
                                .font(.subheadline)
                            Slider(value: $preferences.fontSize, in: 12...30, step: 1)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("行间距: \(String(format: "%.0f", preferences.lineSpacing))")
                                .font(.subheadline)
                            Slider(value: $preferences.lineSpacing, in: 4...20, step: 2)
                        }
                    }
                    
                    Section(header: Text("页面布局")) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("左右边距: \(String(format: "%.0f", preferences.pageHorizontalMargin))")
                                .font(.subheadline)
                            Slider(value: $preferences.pageHorizontalMargin, in: 0...50, step: 1)
                        }
                    }
                }
                
                Section(header: Text("夜间模式")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("模式切换").font(.subheadline).foregroundColor(.secondary)
                        Picker("夜间模式", selection: $preferences.darkMode) {
                            ForEach(DarkModeConfig.allCases) {
                                Text($0.localizedName).tag($0)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.vertical, 4)
                }
                
                if isMangaMode {
                    Section(header: Text("高级设置")) {
                        Toggle("强制服务器代理", isOn: $preferences.forceMangaProxy)
                    }
                }
            }
            .navigationTitle("阅读选项")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
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
        
        guard !documentRange.isEmpty, pageSize.width > 1, pageSize.height > 1 else { return PaginationResult(pages: [], pageInfos: [], reachedEnd: true) }

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
            let lineEdgeInset = max(2.0, contentInset * 0.05) // Reduced inset for line edges
            let lineEdgeSlack: CGFloat = 0 // Slack for line edge detection
            
            var pageFragmentMaxY: CGFloat?
            var pageEndLocation: NSTextLocation = currentContentLocation
            
            layoutManager.enumerateTextLayoutFragments(from: currentContentLocation, options: [.ensuresLayout, .ensuresExtraLineFragment]) { fragment in
                let fragmentFrame = fragment.layoutFragmentFrame
                let fragmentRange = TextKit2Paginator.rangeFromTextRange(fragment.rangeInElement, in: contentStorage)
                
                if fragmentFrame.minY >= pageRect.maxY { return false } // Fragment starts below page bottom
                
                // If fragment is completely above (shouldn't happen with correct startY), skip
                if fragmentFrame.maxY <= pageStartY { return true } // Fragment ends above page top

                if pageFragmentMaxY == nil { pageFragmentMaxY = max(pageStartY, fragmentFrame.minY) } // Initialize with the highest point of the first visible fragment part
                
                if fragmentFrame.maxY <= pageRect.maxY {
                    // Fragment fits entirely
                    pageFragmentMaxY = fragmentFrame.maxY
                    if let fragmentRange = fragmentRange,
                       let loc = contentStorage.location(documentRange.location, offsetBy: NSMaxRange(fragmentRange)) {
                        pageEndLocation = loc
                    } else {
                        pageEndLocation = fragment.rangeInElement.endLocation
                    }
                    return true // Continue to next fragment
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
                            break // Line exceeds page boundary
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
                    return false // Stop enumeration after handling split fragment
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
                    break // Cannot advance, exit loop
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
    var highlightIndex: Int?
    var secondaryIndices: Set<Int> = []
    var isPlayingHighlight: Bool = false
    var paragraphStarts: [Int] = []
    var chapterPrefixLen: Int = 0
    
    private var tk2View: ReadContent2View? // This seems like a typo, should likely be a different name or removed if ReadContent2View is the class itself.
    private var pendingPageInfo: TK2PageInfo?
    
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
        
        // 渲染背景高亮
        if isPlayingHighlight {
            context?.saveGState()
            
            // 准备高亮范围映射
            func getRangeForSentence(_ index: Int) -> NSRange? {
                guard index >= 0 && index < paragraphStarts.count else { return nil }
                let start = paragraphStarts[index] + chapterPrefixLen
                let end = (index + 1 < paragraphStarts.count) ? (paragraphStarts[index + 1] + chapterPrefixLen) : store.attributedString.length
                return NSRange(location: start, length: end - start)
            }
            
            let highlightIndices = ([highlightIndex].compactMap { $0 }) + Array(secondaryIndices)
            
            for index in highlightIndices {
                guard let sRange = getRangeForSentence(index) else { continue }
                let intersection = NSIntersectionRange(sRange, info.range)
                if intersection.length <= 0 { continue }
                
                let color = (index == highlightIndex) ? UIColor.systemBlue.withAlphaComponent(0.2) : UIColor.systemGreen.withAlphaComponent(0.12)
                context?.setFillColor(color.cgColor)
                
                // 找到相交行的矩形区域
                store.layoutManager.enumerateTextLayoutFragments(from: store.contentStorage.location(store.contentStorage.documentRange.location, offsetBy: intersection.location), options: [.ensuresLayout]) { fragment in
                    let fFrame = fragment.layoutFragmentFrame
                    guard let fRange = TextKit2Paginator.rangeFromTextRange(fragment.rangeInElement, in: store.contentStorage) else { return true }
                    
                    if fRange.location >= NSMaxRange(intersection) { return false }
                    
                    for line in fragment.textLineFragments {
                        let lStart = fRange.location + line.characterRange.location
                        let lEnd = fRange.location + line.characterRange.upperBound
                        
                        let lInter = NSIntersectionRange(NSRange(location: lStart, length: lEnd - lStart), intersection)
                        if lInter.length > 0 {
                            // 计算行内具体字符的 X 偏移（简化处理：整行高亮，因为阅读器通常是按段落/句子请求音频）
                            let lineFrame = line.typographicBounds.offsetBy(dx: fFrame.origin.x, dy: fFrame.origin.y)
                            let highlightRect = CGRect(x: 0, y: lineFrame.minY, width: bounds.width, height: lineFrame.height)
                            context?.fill(highlightRect)
                        }
                    }
                    return true
                }
            }
            context?.restoreGState()
        }
        
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

private struct ControlButton: View {
    let icon: String; let label: String; let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 22))
                Text(label).font(.system(size: 10))
            }
            .frame(maxWidth: .infinity)
            .foregroundColor(.primary)
        }
    }
}

private struct NormalControlBar: View {
    let currentChapterIndex: Int
    let chaptersCount: Int
    let isMangaMode: Bool
    @Binding var isForceLandscape: Bool // 新增
    let onPreviousChapter: () -> Void
    let onNextChapter: () -> Void
    let onShowChapterList: () -> Void
    let onToggleTTS: () -> Void
    let onShowFontSettings: () -> Void
    
    var body: some View {
        HStack(spacing: 0) {
            // 左侧：翻页与目录
            HStack(spacing: 20) {
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
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // 中间：功能扩展区（填充空白）
            HStack(spacing: 25) {
                if isMangaMode {
                    // 漫画模式特有按钮
                    Button(action: { withAnimation { isForceLandscape.toggle() } }) {
                        VStack(spacing: 4) {
                            Image(systemName: isForceLandscape ? "iphone.smartrotate.forward" : "iphone.landscape").font(.title2)
                            Text(isForceLandscape ? "竖屏" : "横屏").font(.caption2)
                        }
                    }
                    .foregroundColor(isForceLandscape ? .blue : .primary)
                } else {
                    Button(action: onToggleTTS) {
                        VStack(spacing: 4) {
                            Image(systemName: "speaker.wave.2.circle.fill").font(.system(size: 32)).foregroundColor(.blue)
                            Text("听书").font(.caption2).foregroundColor(.blue)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            
            // 右侧：选项与下一章
            HStack(spacing: 20) {
                Button(action: onShowFontSettings) {
                    VStack(spacing: 4) {
                        Image(systemName: isMangaMode ? "gearshape" : "slider.horizontal.3").font(.title2)
                        Text("选项").font(.caption2)
                    }
                }
                
                Button(action: onNextChapter) {
                    VStack(spacing: 4) {
                        Image(systemName: "chevron.right").font(.title2)
                        Text("下一章").font(.caption2)
                    }
                }.disabled(currentChapterIndex >= chaptersCount - 1)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(Color(UIColor.systemBackground))
        .shadow(color: Color.black.opacity(0.1), radius: 5, y: -2)
    }
}

private struct ReaderOptionsSheet: View {
    @ObservedObject var preferences: UserPreferences
    let isMangaMode: Bool
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            Form {
                if !isMangaMode {
                    Section(header: Text("显示设置")) {
                        Picker("阅读模式", selection: $preferences.readingMode) {
                            ForEach(ReadingMode.allCases) {
                                Text($0.localizedName).tag($0)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.vertical, 4)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("字体大小: \(String(format: "%.0f", preferences.fontSize))")
                                .font(.subheadline)
                            Slider(value: $preferences.fontSize, in: 12...30, step: 1)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("行间距: \(String(format: "%.0f", preferences.lineSpacing))")
                                .font(.subheadline)
                            Slider(value: $preferences.lineSpacing, in: 4...20, step: 2)
                        }
                    }
                    
                    Section(header: Text("页面布局")) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("左右边距: \(String(format: "%.0f", preferences.pageHorizontalMargin))")
                                .font(.subheadline)
                            Slider(value: $preferences.pageHorizontalMargin, in: 0...50, step: 1)
                        }
                    }
                }
                
                Section(header: Text("夜间模式")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("模式切换").font(.subheadline).foregroundColor(.secondary)
                        Picker("夜间模式", selection: $preferences.darkMode) {
                            ForEach(DarkModeConfig.allCases) {
                                Text($0.localizedName).tag($0)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.vertical, 4)
                }
                
                if isMangaMode {
                    Section(header: Text("高级设置")) {
                        Toggle("强制服务器代理", isOn: $preferences.forceMangaProxy)
                    }
                }
            }
            .navigationTitle("阅读选项")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
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
        
        guard !documentRange.isEmpty, pageSize.width > 1, pageSize.height > 1 else { return PaginationResult(pages: [], pageInfos: [], reachedEnd: true) }

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
            let lineEdgeInset = max(2.0, contentInset * 0.05) // Reduced inset for line edges
            let lineEdgeSlack: CGFloat = 0 // Slack for line edge detection
            
            var pageFragmentMaxY: CGFloat?
            var pageEndLocation: NSTextLocation = currentContentLocation
            
            layoutManager.enumerateTextLayoutFragments(from: currentContentLocation, options: [.ensuresLayout, .ensuresExtraLineFragment]) { fragment in
                let fragmentFrame = fragment.layoutFragmentFrame
                let fragmentRange = TextKit2Paginator.rangeFromTextRange(fragment.rangeInElement, in: contentStorage)
                
                if fragmentFrame.minY >= pageRect.maxY { return false } // Fragment starts below page bottom
                
                // If fragment is completely above (shouldn't happen with correct startY), skip
                if fragmentFrame.maxY <= pageStartY { return true } // Fragment ends above page top

                if pageFragmentMaxY == nil { pageFragmentMaxY = max(pageStartY, fragmentFrame.minY) } // Initialize with the highest point of the first visible fragment part
                
                if fragmentFrame.maxY <= pageRect.maxY {
                    // Fragment fits entirely
                    pageFragmentMaxY = fragmentFrame.maxY
                    if let fragmentRange = fragmentRange,
                       let loc = contentStorage.location(documentRange.location, offsetBy: NSMaxRange(fragmentRange)) {
                        pageEndLocation = loc
                    } else {
                        pageEndLocation = fragment.rangeInElement.endLocation
                    }
                    return true // Continue to next fragment
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
                            break // Line exceeds page boundary
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
                    return false // Stop enumeration after handling split fragment
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
                    break // Cannot advance, exit loop
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
    var highlightIndex: Int?
    var secondaryIndices: Set<Int> = []
    var isPlayingHighlight: Bool = false
    var paragraphStarts: [Int] = []
    var chapterPrefixLen: Int = 0
    
    private var tk2View: ReadContent2View? // This seems like a typo, should likely be a different name or removed if ReadContent2View is the class itself.
    private var pendingPageInfo: TK2PageInfo?
    
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
        
        // 渲染背景高亮
        if isPlayingHighlight {
            context?.saveGState()
            
            // 准备高亮范围映射
            func getRangeForSentence(_ index: Int) -> NSRange? {
                guard index >= 0 && index < paragraphStarts.count else { return nil }
                let start = paragraphStarts[index] + chapterPrefixLen
                let end = (index + 1 < paragraphStarts.count) ? (paragraphStarts[index + 1] + chapterPrefixLen) : store.attributedString.length
                return NSRange(location: start, length: end - start)
            }
            
            let highlightIndices = ([highlightIndex].compactMap { $0 }) + Array(secondaryIndices)
            
            for index in highlightIndices {
                guard let sRange = getRangeForSentence(index) else { continue }
                let intersection = NSIntersectionRange(sRange, info.range)
                if intersection.length <= 0 { continue }
                
                let color = (index == highlightIndex) ? UIColor.systemBlue.withAlphaComponent(0.2) : UIColor.systemGreen.withAlphaComponent(0.12)
                context?.setFillColor(color.cgColor)
                
                // 找到相交行的矩形区域
                store.layoutManager.enumerateTextLayoutFragments(from: store.contentStorage.location(store.contentStorage.documentRange.location, offsetBy: intersection.location), options: [.ensuresLayout]) { fragment in
                    let fFrame = fragment.layoutFragmentFrame
                    guard let fRange = TextKit2Paginator.rangeFromTextRange(fragment.rangeInElement, in: store.contentStorage) else { return true }
                    
                    if fRange.location >= NSMaxRange(intersection) { return false }
                    
                    for line in fragment.textLineFragments {
                        let lStart = fRange.location + line.characterRange.location
                        let lEnd = fRange.location + line.characterRange.upperBound
                        
                        let lInter = NSIntersectionRange(NSRange(location: lStart, length: lEnd - lStart), intersection)
                        if lInter.length > 0 {
                            // 计算行内具体字符的 X 偏移（简化处理：整行高亮，因为阅读器通常是按段落/句子请求音频）
                            let lineFrame = line.typographicBounds.offsetBy(dx: fFrame.origin.x, dy: fFrame.origin.y)
                            let highlightRect = CGRect(x: 0, y: lineFrame.minY, width: bounds.width, height: lineFrame.height)
                            context?.fill(highlightRect)
                        }
                    }
                    return true
                }
            }
            context?.restoreGState()
        }
        
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