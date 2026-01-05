import SwiftUI
import UIKit

// MARK: - ReadingView
enum ReaderTapLocation {
    case left, right, middle
}

struct ReadingView: View {
    let book: Book
    let logger = LogManager.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var apiService: APIService
    @StateObject var ttsManager = TTSManager.shared
    @StateObject var preferences = UserPreferences.shared
    @StateObject var replaceRuleViewModel = ReplaceRuleViewModel()

    // Chapter and Content State
    @State var chapters: [BookChapter] = []
    @State var currentChapterIndex: Int
    @State var rawContent = ""
    @State var currentContent = ""
    @State var contentSentences: [String] = []
    
    // UI State
    @State var isLoading = false
    @State var showChapterList = false
    @State var errorMessage: String?
    @State var showUIControls = false
    @State var showFontSettings = false
    
    // Reading Progress & Position
    @State var pendingResumePos: Double?
    @State var pendingResumeCharIndex: Int?
    @State var pendingResumeLocalBodyIndex: Int?
    @State var pendingResumeLocalChapterIndex: Int?
    @State var pendingResumeLocalPageIndex: Int?
    @State var didApplyResumePos = false
    @State var initialServerChapterIndex: Int?
    @State var didEnterReadingSession = false
    @State var shouldApplyResumeOnce = false
    @State var shouldSyncPageAfterPagination = false

    // Vertical (Scrolling) Reader State
    @State var scrollProxy: ScrollViewProxy?
    @State var currentVisibleSentenceIndex: Int?
    @State var pendingScrollToSentenceIndex: Int?

    // Horizontal (Paging) Reader State
    @State var currentPageIndex: Int = 0
    @State var currentCache: ChapterCache = .empty
    @State var prevCache: ChapterCache = .empty
    @State var nextCache: ChapterCache = .empty
    @State var pendingJumpToLastPage = false
    @State var pendingJumpToFirstPage = false
    @State var pageSize: CGSize = .zero
    @State var isPageTransitioning = false
    @State var pendingBufferPageIndex: Int?
    @State var lastHandledPageIndex: Int?
    @StateObject var contentControllerCache = ReadContentViewControllerCache()
    @State var hasInitialPagination = false
    
    // 漫画模式占位符，用于缓存 key 保持稳定
    let mangaPlaceholderStore = TextKit2RenderStore(attributedString: NSAttributedString(), layoutWidth: 1)
    
    // Repagination Control
    @State var isRepaginateQueued = false
    @State var lastPaginationKey: PaginationKey?
    @State var suppressRepaginateOnce = false
    
    // TTS State
    @State var lastTTSSentenceIndex: Int?
    @State var ttsBaseIndex: Int = 0
    @State var pendingFlipId: UUID = UUID()
    @State var isTTSSyncingPage = false
    @State var suppressTTSSync = false
    @State var suppressPageIndexChangeOnce = false
    @State var isAutoFlipping: Bool = false
    @State var isTTSAutoChapterChange = false
    @State var pausedChapterIndex: Int?
    @State var pausedPageIndex: Int?
    @State var needsTTSRestartAfterPause = false
    @State var lastAdjacentPrepareAt: TimeInterval = 0
    @State var pendingTTSRequest: TTSPlayRequest?
    @State var showDetailFromHeader = false
    
    // Sleep Timer State
    @State var timerRemaining: Int = 0
    @State var timerActive = false
    @State var sleepTimer: Timer? = nil
    
    // Replace Rule State
    @State var showAddReplaceRule = false
    @State var pendingReplaceRule: ReplaceRule?
    
    // Page Turn & Navigation State
    @State var pageTurnRequest: PageTurnRequest? = nil
    @State var isExplicitlySwitchingChapter = false
    @State var currentChapterIsManga = false
    @State var lastEffectiveMode: ReadingMode? = nil
    
    // 旋转与布局增强
    @State var isForceLandscape = false

    struct PaginationKey: Hashable {
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
    
    struct TTSPlayRequest {
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
    
    func updateMangaModeState() {
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
    
    private var cacheRefresher: some View {
        Group {
            let stores: [TextKit2RenderStore?] = [currentCache.renderStore, prevCache.renderStore, nextCache.renderStore, mangaPlaceholderStore]
            let _ = contentControllerCache.retainActive(stores: stores)
        }
        .frame(width: 0, height: 0)
    }

    // MARK: - Pagination & Navigation
    
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

    func snapshot(from cache: ChapterCache) -> PageSnapshot {
        PageSnapshot(pages: cache.pages, renderStore: cache.renderStore, pageInfos: cache.pageInfos, contentSentences: cache.contentSentences, chapterUrl: cache.chapterUrl)
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
    
    // MARK: - Logic & Actions
    
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
