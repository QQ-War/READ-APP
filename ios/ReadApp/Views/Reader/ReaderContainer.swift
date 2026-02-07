import SwiftUI
import UIKit

// MARK: - 布局规范
struct ReaderLayoutSpec {
    let topInset: CGFloat
    let bottomInset: CGFloat
    let sideMargin: CGFloat
    let pageSize: CGSize
}

// MARK: - SwiftUI 桥接入口
struct ReaderContainerRepresentable: UIViewControllerRepresentable {
    let book: Book
    @ObservedObject var readerSettings: ReaderSettingsStore
    @ObservedObject var ttsManager: TTSManager
    @ObservedObject var replaceRuleViewModel: ReplaceRuleViewModel
    
    @Binding var chapters: [BookChapter]
    @Binding var currentChapterIndex: Int
    @Binding var isMangaMode: Bool
    @Binding var isLoading: Bool // 新增
    
    var onToggleMenu: () -> Void
    var onAddReplaceRule: (String) -> Void
    var onProgressChanged: (Int, Double) -> Void
    var onToggleTTS: ((@escaping () -> Void) -> Void)?
    var onRefreshChapter: ((@escaping () -> Void) -> Void)?
    var readingMode: ReadingMode
    var safeAreaInsets: EdgeInsets 
    
    class Coordinator {
        var parent: ReaderContainerRepresentable
        init(_ parent: ReaderContainerRepresentable) { self.parent = parent }
        func handleChapterChange(_ index: Int) {
            DispatchQueue.main.async { self.parent.currentChapterIndex = index }
        }
        func handleProgress(_ idx: Int, _ pos: Double) {
            self.parent.onProgressChanged(idx, pos)
        }
        func handleChaptersLoaded(_ list: [BookChapter]) {
            DispatchQueue.main.async { self.parent.chapters = list }
        }
        func handleModeDetected(_ isManga: Bool) {
            DispatchQueue.main.async { self.parent.isMangaMode = isManga }
        }
    }
    
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    
    func makeUIViewController(context: Context) -> ReaderContainerViewController {
        let vc = ReaderContainerViewController()
        vc.book = book; vc.readerSettings = readerSettings; vc.ttsManager = ttsManager
        vc.replaceRuleViewModel = replaceRuleViewModel
        vc.onToggleMenu = onToggleMenu; vc.onAddReplaceRuleWithText = { onAddReplaceRule($0) }
        vc.onChapterIndexChanged = { idx in context.coordinator.handleChapterChange(idx) }
        vc.onProgressChanged = { idx, pos in context.coordinator.handleProgress(idx, pos) }
        vc.onChaptersLoaded = { list in context.coordinator.handleChaptersLoaded(list) }
        vc.onModeDetected = { isManga in context.coordinator.handleModeDetected(isManga) }
        vc.onLoadingChanged = { loading in DispatchQueue.main.async { self.isLoading = loading } }
        onToggleTTS?({ [weak vc] in vc?.toggleTTS() })
        onRefreshChapter?({ [weak vc] in vc?.refreshCurrentChapter() })
        return vc
    }
    
    func updateUIViewController(_ vc: ReaderContainerViewController, context: Context) {
        context.coordinator.parent = self
        vc.updateLayout(safeArea: safeAreaInsets)
        vc.updateSettings(readerSettings)
        vc.updateReplaceRules(replaceRuleViewModel.rules)
        vc.verticalThreshold = readerSettings.verticalThreshold
        
        // 外部跳转检测逻辑优化
        if !vc.isInternalTransitioning && vc.lastReportedChapterIndex != currentChapterIndex {
            vc.markUserNavigation()
            vc.jumpToChapter(currentChapterIndex)
        }
        
        let desiredMode: ReadingMode
        if readingMode == .vertical {
            desiredMode = .vertical
        } else if readerSettings.pageTurningMode == .simulation {
            desiredMode = .horizontal
        } else {
            desiredMode = .newHorizontal
        }
        if vc.currentReadingMode != desiredMode { vc.switchReadingMode(to: desiredMode) }
        vc.syncTTSState()
    }
}

// MARK: - UIKit 核心容器
class ReaderContainerViewController: UIViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate, UIScrollViewDelegate, HorizontalCollectionViewDelegate {
    let logger = LogManager.shared
    var book: Book!; var chapters: [BookChapter] = []; var readerSettings: ReaderSettingsStore!; var ttsManager: TTSManager!; var replaceRuleViewModel: ReplaceRuleViewModel?
    var onToggleMenu: (() -> Void)?; var onAddReplaceRuleWithText: ((String) -> Void)?; var onProgressChanged: ((Int, Double) -> Void)?
    var onChapterIndexChanged: ((Int) -> Void)?; var onChaptersLoaded: (([BookChapter]) -> Void)?; var onModeDetected: ((Bool) -> Void)?; var onLoadingChanged: ((Bool) -> Void)?

        private struct ReaderSettingsSnapshot: Equatable {

            let fontSize: CGFloat

            let lineSpacing: CGFloat

            let pageHorizontalMargin: CGFloat

            let readingFontName: String

            let readingTheme: ReadingTheme

            let isInfiniteScrollEnabled: Bool

            let infiniteScrollSwitchThreshold: CGFloat

            let verticalDampingFactor: CGFloat

            let mangaMaxZoom: CGFloat

            let mangaChapterZoomEnabled: Bool

            let pageTurningMode: PageTurningMode

            let ttsFollowCooldown: TimeInterval

            let verticalThreshold: CGFloat

            let progressFontSize: CGFloat

            let isProgressDynamicColorEnabled: Bool

        }

        

        private var currentBackgroundColor: UIColor {

            if UserPreferences.shared.isLiquidGlassEnabled &&

                [.system, .day, .night].contains(readerSettings.readingTheme) {

                return .clear

            }

            return readerSettings.readingTheme.backgroundColor

        }

    

        private var lastSettingsSnapshot: ReaderSettingsSnapshot?
    private var lastReplaceRules: [ReplaceRule]?
    
    var safeAreaTop: CGFloat = ReaderConstants.Layout.safeAreaTopDefault {
        didSet {
            verticalVC?.safeAreaTop = safeAreaTop
            mangaVC?.safeAreaTop = safeAreaTop
        }
    }
    var safeAreaBottom: CGFloat = ReaderConstants.Layout.safeAreaBottomDefault
    var currentLayoutSpec: ReaderLayoutSpec {
        ReaderMath.layoutSpec(
            safeAreaTop: safeAreaTop,
            safeAreaBottom: safeAreaBottom,
            viewSafeArea: view.safeAreaInsets,
            pageHorizontalMargin: readerSettings.pageHorizontalMargin,
            bounds: view.bounds
        )
    }

    
    var currentChapterIndex: Int = 0
    var lastReportedChapterIndex: Int = -1
    var verticalThreshold: CGFloat = 80 {
        didSet {
            verticalVC?.threshold = verticalThreshold
            mangaVC?.threshold = verticalThreshold
        }
    }

    var currentReadingMode: ReadingMode = .vertical
    private var activePaginationAnchor: Int = 0 // 分页锚点
    struct TransitionState {
        var isTransitioning: Bool = false
        var timestamp: TimeInterval = 0
    }
    var transitionState = TransitionState()
    var isInternalTransitioning: Bool {
        get { transitionState.isTransitioning }
        set {
            transitionState.isTransitioning = newValue
            if newValue {
                transitionState.timestamp = Date().timeIntervalSince1970
            }
        }
    }
    var isFirstLoad = true
    var isAutoScrolling = false
    private var ttsSyncCoordinator: TTSReadingSyncCoordinator?
    private lazy var ttsBridge: ReaderTTSBridge = {
        ReaderTTSBridge(
            followCooldown: { [weak self] in self?.readerSettings.ttsFollowCooldown ?? 0 },
            scheduleCatchUp: { [weak self] delay in self?.ttsSyncCoordinator?.scheduleCatchUp(delay: delay) }
        )
    }()

    var chapterBuilder: ReaderChapterBuilder?
    let layoutManager = ReaderLayoutManager()
    var currentCache: ChapterCache = .empty
    var nextCache: ChapterCache = .empty
    var prevCache: ChapterCache = .empty
    var currentPageIndex: Int = 0
    
    private var visibleHorizontalPageIndex: Int? {
        guard let pageVC = horizontalVC?.viewControllers?.first as? PageContentViewController else { return nil }
        guard pageVC.chapterOffset == 0 else { return nil }
        return pageVC.pageIndex
    }
    
    func horizontalPageIndexForDisplay() -> Int {
        if let visible = visibleHorizontalPageIndex, visible >= 0, visible < currentCache.pages.count {
            return visible
        }
        return currentPageIndex
    }
    
    private func previewSentences(from startIndex: Int, limit: Int) -> [String] {
        guard !currentCache.contentSentences.isEmpty else { return [] }
        var lines: [String] = []
        for idx in startIndex..<min(startIndex + limit, currentCache.contentSentences.count) {
            lines.append(sanitizedPreviewText(currentCache.contentSentences[idx]))
        }
        return lines
    }
    
    private func sanitizedPreviewText(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ")
        guard trimmed.count > ReaderConstants.Text.previewSnippetLength else { return trimmed }
        let endIndex = trimmed.index(trimmed.startIndex, offsetBy: ReaderConstants.Text.previewSnippetLength)
        return String(trimmed[..<endIndex]) + "…"
    }
    
    private func visibleTopSentenceInfo() -> (index: Int, sentences: [String]) {
        guard !currentCache.contentSentences.isEmpty else { return (0, []) }
        let startIndex: Int
        if currentReadingMode == .vertical {
            startIndex = verticalVC?.getCurrentSentenceIndex() ?? 0
        } else {
            let pageIndex = horizontalPageIndexForDisplay()
            if let pageInfos = currentCache.pageInfos, pageIndex < pageInfos.count {
                startIndex = pageInfos[pageIndex].startSentenceIndex
            } else {
                startIndex = 0
            }
        }
        let sentences = previewSentences(from: startIndex, limit: 2)
        return (startIndex, sentences)
    }
    
    private func horizontalPageStartSnippet(for pageIndex: Int, limit: Int) -> String {
        guard let pageInfos = currentCache.pageInfos, pageIndex < pageInfos.count else { return "" }
        let range = pageInfos[pageIndex].range
        let attributed = currentCache.attributedText.string as NSString
        let validLen = max(0, min(limit, attributed.length - range.location))
        guard validLen > 0 else { return "" }
        let fragment = attributed.substring(with: NSRange(location: range.location, length: validLen))
        return sanitizedPreviewText(fragment)
    }
    
    var isMangaMode = false
    var latestVisibleFragmentLines: [String] = []

    var verticalVC: VerticalTextViewController?
    var horizontalVC: UIPageViewController?
    var mangaVC: (UIViewController & MangaReadable)?
    var newHorizontalVC: HorizontalCollectionViewController?
    var prebuiltNextMangaVC: (UIViewController & MangaReadable)?
    var prebuiltNextIndex: Int?

    let progressLabel = UILabel()
    private var lastLayoutSignature: String = ""
    var loadToken: Int = 0
    let prefetchCoordinator = ReaderPrefetchCoordinator()
    
    var prefetchedMangaNextIndex: Int?
    var prefetchedMangaNextContent: String?
    var lastChapterSwitchTime: TimeInterval = 0
    let chapterSwitchCooldown: TimeInterval = ReaderConstants.Interaction.chapterSwitchCooldown
    private var lastLoggedCacheChapterIndex: Int = -1
    private var lastLoggedNextUrl: String?
    private var lastLoggedPrevUrl: String?
    private var lastLoggedNextCount: Int = -1
    private var lastLoggedPrevCount: Int = -1
    lazy var pageTransitionCoordinator: ReaderTransitionCoordinator = {
        ReaderTransitionCoordinator(
            state: .init(
                isTransitioning: { [weak self] in self?.isInternalTransitioning ?? true },
                setTransitioning: { [weak self] value in self?.isInternalTransitioning = value },
                transitionToken: { [weak self] in self?.transitionState.timestamp ?? 0 },
                setTransitionToken: { [weak self] value in self?.transitionState.timestamp = value },
                activeView: { [weak self] in
                    guard let self else { return nil }
                    if self.currentReadingMode == .newHorizontal { return self.newHorizontalVC?.view }
                    if self.currentReadingMode == .horizontal { return self.horizontalVC?.view }
                    if self.currentReadingMode == .vertical { return self.verticalVC?.view }
                    return self.mangaVC?.view
                },
                containerView: { [weak self] in self?.view },
                themeColor: { [weak self] in self?.readerSettings.readingTheme.backgroundColor ?? .black }
            ),
            actions: .init(
                notifyInteractionEnd: { [weak self] in self?.notifyUserInteractionEnded() }
            )
        )
    }()
    lazy var interactionCoordinator: ReaderInteractionCoordinator = {
        ReaderInteractionCoordinator(
            state: .init(
                isTransitioning: { [weak self] in self?.isInternalTransitioning ?? true },
                currentPageIndex: { [weak self] in self?.currentPageIndex ?? 0 },
                currentChapterIndex: { [weak self] in self?.currentChapterIndex ?? 0 },
                totalChapters: { [weak self] in self?.chapters.count ?? 0 },
                pageCount: { [weak self] in self?.currentCache.pages.count ?? 0 },
                prevPageCount: { [weak self] in self?.prevCache.pages.count ?? 0 },
                hasPrevCache: { [weak self] in !(self?.prevCache.pages.isEmpty ?? true) },
                hasNextCache: { [weak self] in !(self?.nextCache.pages.isEmpty ?? true) },
                shouldAnimatePageTurn: { [weak self] in
                    guard let self else { return false }
                    return self.readerSettings.pageTurningMode != .none
                }
            ),
            actions: .init(
                notifyInteractionStart: { [weak self] in self?.notifyUserInteractionStarted() },
                notifyInteractionEnd: { [weak self] in self?.notifyUserInteractionEnded() },
                finalizeInteraction: { [weak self] in self?.finalizeUserInteraction() },
                updateHorizontalPage: { [weak self] index, animated in self?.updateHorizontalPage(to: index, animated: animated) },
                animateToAdjacentChapter: { [weak self] offset, targetPage, animated in
                    self?.animateToAdjacentChapter(offset: offset, targetPage: targetPage, animated: animated)
                },
                requestChapterSwitch: { [weak self] targetIndex, startAtEnd in
                    self?.requestChapterSwitch(to: targetIndex, startAtEnd: startAtEnd)
                }
            )
        )
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = currentBackgroundColor
        setupProgressLabel()
        currentChapterIndex = book.durChapterIndex ?? 0
        lastReportedChapterIndex = currentChapterIndex
        currentReadingMode = readerSettings.readingMode
        
        chapterBuilder = ReaderChapterBuilder(readerSettings: readerSettings, replaceRules: replaceRuleViewModel?.rules)
        loadChapters()
        ttsSyncCoordinator = TTSReadingSyncCoordinator(reader: self, ttsManager: ttsManager)
        ttsSyncCoordinator?.start()
        
        DisplayRateManager.shared.start()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        prefetchCoordinator.cancel()
        ttsSyncCoordinator?.stop()
        DisplayRateManager.shared.stop()
        Task {
            await ReaderProgressCoordinator.saveProgress(
                book: book,
                chapters: chapters,
                currentChapterIndex: currentChapterIndex,
                isMangaMode: isMangaMode,
                readingMode: currentReadingMode,
                currentCache: currentCache,
                currentPageIndex: currentPageIndex,
                verticalVC: verticalVC,
                mangaVC: mangaVC
            )
        }
    }

    private func setupProgressLabel() {
        progressLabel.font = .monospacedDigitSystemFont(ofSize: readerSettings?.progressFontSize ?? 12, weight: .regular)
        progressLabel.textColor = readerSettings?.readingTheme.textColor ?? .white
        progressLabel.backgroundColor = .clear
        view.addSubview(progressLabel)
        progressLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            progressLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -ReaderConstants.ProgressLabel.trailing),
            progressLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -ReaderConstants.ProgressLabel.bottom)
        ])
    }
    
    private var lastKnownSize: CGSize = .zero
    private var pendingRelocationOffset: Int? // 记录正在进行的跳转目标

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard !isInternalTransitioning else { return }
        let b = view.bounds; verticalVC?.view.frame = b; horizontalVC?.view.frame = b; mangaVC?.view.frame = b; newHorizontalVC?.view.frame = b
        
        if b.size != lastKnownSize {
            let spec = currentLayoutSpec
            let signature = "\(Int(spec.pageSize.width))x\(Int(spec.pageSize.height))"
            if signature != lastLayoutSignature {
                lastLayoutSignature = signature
                lastKnownSize = b.size
                if !isMangaMode, currentCache.renderStore != nil, (currentReadingMode == .horizontal || currentReadingMode == .newHorizontal) {
                    rebuildPaginationForLayout()
                    if currentReadingMode == .newHorizontal {
                        newHorizontalVC?.collectionView.collectionViewLayout.invalidateLayout()
                        newHorizontalVC?.scrollToPageIndex(currentPageIndex, animated: false)
                    }
                }
            }
        }
    }

    private var lastSafeAreaTop: CGFloat?
    private var lastSafeAreaBottom: CGFloat?

    func updateLayout(safeArea: EdgeInsets) {
        let top = safeArea.top
        let bottom = safeArea.bottom
        if let lastTop = lastSafeAreaTop, let lastBottom = lastSafeAreaBottom {
            if abs(lastTop - top) < ReaderConstants.Interaction.interactionStartSnapThreshold && abs(lastBottom - bottom) < ReaderConstants.Interaction.interactionStartSnapThreshold {
                return
            }
        }
        lastSafeAreaTop = top
        lastSafeAreaBottom = bottom
        self.safeAreaTop = top
        self.safeAreaBottom = bottom
    }
        
        func updateSettings(_ settings: ReaderSettingsStore) {
            let snapshot = ReaderSettingsSnapshot(
                fontSize: settings.fontSize,
                lineSpacing: settings.lineSpacing,
                pageHorizontalMargin: settings.pageHorizontalMargin,
                readingFontName: settings.readingFontName,
                readingTheme: settings.readingTheme,
                isInfiniteScrollEnabled: settings.isInfiniteScrollEnabled,
                infiniteScrollSwitchThreshold: settings.infiniteScrollSwitchThreshold,
                verticalDampingFactor: settings.verticalDampingFactor,
                mangaMaxZoom: settings.mangaMaxZoom,
                mangaChapterZoomEnabled: settings.mangaChapterZoomEnabled,
                pageTurningMode: settings.pageTurningMode,
                ttsFollowCooldown: settings.ttsFollowCooldown,
                verticalThreshold: settings.verticalThreshold,
                progressFontSize: settings.progressFontSize,
                isProgressDynamicColorEnabled: UserPreferences.shared.isProgressDynamicColorEnabled
            )
            if lastSettingsSnapshot == snapshot { return }
            let previousSnapshot = lastSettingsSnapshot
            lastSettingsSnapshot = snapshot
            
            // 更新进度标签字体大小
            progressLabel.font = .monospacedDigitSystemFont(ofSize: settings.progressFontSize, weight: .regular)
            mangaVC?.progressLabel.font = .monospacedDigitSystemFont(ofSize: settings.progressFontSize, weight: .regular)

            guard let oldSettings = self.readerSettings else {
                self.readerSettings = settings
                chapterBuilder?.updateSettings(settings)
                view.backgroundColor = currentBackgroundColor
                verticalVC?.view.backgroundColor = currentBackgroundColor
                horizontalVC?.view.backgroundColor = currentBackgroundColor
                newHorizontalVC?.view.backgroundColor = currentBackgroundColor
                mangaVC?.view.backgroundColor = currentBackgroundColor
                return
            }
            self.readerSettings = settings
            chapterBuilder?.updateSettings(settings)
            view.backgroundColor = currentBackgroundColor
            verticalVC?.view.backgroundColor = currentBackgroundColor
            horizontalVC?.view.backgroundColor = currentBackgroundColor
            newHorizontalVC?.view.backgroundColor = currentBackgroundColor
            mangaVC?.view.backgroundColor = currentBackgroundColor

            if oldSettings.mangaMaxZoom != settings.mangaMaxZoom {
                mangaVC?.maxZoomScale = settings.mangaMaxZoom
            }
            if oldSettings.mangaChapterZoomEnabled != settings.mangaChapterZoomEnabled {
                mangaVC?.isChapterZoomEnabled = settings.mangaReaderMode == .collection ? settings.mangaChapterZoomEnabled : true
            }
            
            mangaVC?.updateProgressStyle()

            // 检测关键布局参数是否改变
            let layoutChanged = oldSettings.fontSize != settings.fontSize ||
                                oldSettings.lineSpacing != settings.lineSpacing ||
                                oldSettings.pageHorizontalMargin != settings.pageHorizontalMargin ||
                                oldSettings.readingFontName != settings.readingFontName ||
                                oldSettings.readingTheme != settings.readingTheme
            let turningModeChanged = previousSnapshot?.pageTurningMode != snapshot.pageTurningMode

            // 如果正在进行模式切换跳转，不在此处重新捕获进度，防止捕获到临时的 Offset 0
            let currentOffset = pendingRelocationOffset ?? getCurrentReadingCharOffset()

            // 确保正在切换模式时状态锁能正确管理
            if turningModeChanged || layoutChanged {
                self.isInternalTransitioning = false 
            }

            if turningModeChanged && !isMangaMode {
                rebuildHorizontalControllerForTurningModeChange()
            }

            if let v = verticalVC, v.isInfiniteScrollEnabled != settings.isInfiniteScrollEnabled {
                v.isInfiniteScrollEnabled = settings.isInfiniteScrollEnabled
                if !isMangaMode && currentReadingMode == .vertical {
                    updateVerticalAdjacent()
                }
            }

            if layoutChanged && !isMangaMode {
                // 无论是水平还是垂直模式，重绘时都带上锚点以保持位置
                reRenderCurrentContent(anchorOffset: currentOffset)
                
                // 只有在布局真正改变时，才在垂直模式下执行行级对齐滚动
                if currentReadingMode == .vertical && pendingRelocationOffset == nil {
                    DispatchQueue.main.asyncAfter(deadline: .now() + ReaderConstants.Interaction.progressDelayShort) { [weak self] in
                        self?.scrollToCharOffset(currentOffset, animated: false)
                    }
                }
            } else if !isMangaMode && currentReadingMode == .vertical {
                // 如果布局没变，仅更新相邻章节状态，不再强制滚动
                updateVerticalAdjacent()
            }
            
            // 确保进度 UI 随主题等设置更新
            updateProgressUI()
        }
        
                
        
        func updateReplaceRules(_ rules: [ReplaceRule]) {
            if lastReplaceRules == rules { return }
            lastReplaceRules = rules
            guard let ttsManager = ttsManager else {
                chapterBuilder?.updateReplaceRules(rules)
                return
            }
            let oldRules = ttsManager.replaceRules
            chapterBuilder?.updateReplaceRules(rules)
            ttsManager.replaceRules = rules
            
            // 只有当规则真的发生变化且非漫画模式时，才触发重绘
            if oldRules != rules && !isMangaMode {
                if !currentCache.rawContent.isEmpty {
                    let currentOffset = pendingRelocationOffset ?? getCurrentReadingCharOffset()
                    // 无论是水平还是垂直模式，重绘都应带上锚点
                    reRenderCurrentContent(anchorOffset: currentOffset)
                } else if currentReadingMode == .vertical {
                    updateVerticalAdjacent()
                }
            }
        }
        
                
        
                func jumpToChapter(_ index: Int, startAtEnd: Bool = false) {
                    requestChapterSwitch(to: index, startAtEnd: startAtEnd)
                }
        
            
        
                                func switchReadingMode(to mode: ReadingMode) {
        
            
        
                                    let offset = getCurrentReadingCharOffset()
        
            
        
                                    currentReadingMode = mode
        
                    
        
                    // 关键：设置挂起目标，防止跳转过程中进度被覆盖
        
                    pendingRelocationOffset = offset
        
        
                    
        
                    if mode == .horizontal || mode == .newHorizontal {
        
                        reRenderCurrentContent(anchorOffset: offset)
        
                        pendingRelocationOffset = nil // 水平模式重渲染即完成定位
        
                    } else {
        
                        setupReaderMode()
        
                        DispatchQueue.main.asyncAfter(deadline: .now() + ReaderConstants.Interaction.progressDelayNormal) { [weak self] in
        
                            guard let self = self else { return }
        
                            self.scrollToCharOffset(offset, animated: false)
        
                            self.pendingRelocationOffset = nil // 完成后解锁
        
                        }
        
                    }
        
                }
        
                
        
                    func getCurrentReadingCharOffset() -> Int {
        
                
        
                        // 如果有挂起的跳转，优先返回跳转目标，避免在视图未准备好时探测到 0
        
                
        
                        if let pending = pendingRelocationOffset {
        
                
        
        
                
        
                            return pending
        
                
        
                        }
        
                
        
                        
        
                
        
                        let offset: Int
        
                
        
                        if currentReadingMode == .vertical {
        
                
        
                            offset = verticalVC?.getCurrentCharOffset() ?? 0
        
                
        
        
                
        
                        } else if currentReadingMode == .newHorizontal && !currentCache.pages.isEmpty {
                            let idx = newHorizontalVC?.currentPageIndex ?? 0
                            if idx < currentCache.pages.count {
                                offset = currentCache.pages[idx].globalRange.location
                            } else {
                                offset = 0
                            }
                        } else if !currentCache.pages.isEmpty {
        
                
        
                            let idx = horizontalPageIndexForDisplay()
        
                
        
                            if idx < currentCache.pages.count {
        
                
        
                                offset = currentCache.pages[idx].globalRange.location
        
                
        
        
                
        
                            } else {
        
                
        
                                offset = 0
        
                
        
                            }
        
                
        
                        } else {
        
                
        
                            offset = 0
        
                
        
                        }
        
                
        
                        return offset
        
                
        
                    }
        
    func scrollToCharOffset(_ offset: Int, animated: Bool) {
        if currentReadingMode == .vertical {
            verticalVC?.scrollToCharOffset(offset, animated: animated)
        } else if currentReadingMode == .newHorizontal {
            if let targetPage = currentCache.pages.firstIndex(where: { page in
                offset >= page.globalRange.location && offset < (page.globalRange.location + page.globalRange.length)
            }) {
                newHorizontalVC?.scrollToPageIndex(targetPage, animated: animated)
            }
        } else {
            if let targetPage = currentCache.pages.firstIndex(where: { page in
                offset >= page.globalRange.location && offset < (page.globalRange.location + page.globalRange.length)
            }) {
                updateHorizontalPage(to: targetPage, animated: animated)
            } else {
            }
        }
    }

    
        
    
    func toggleTTS() {
        if ttsManager.isPlaying {
            if ttsManager.isPaused { ttsManager.resume() }
            else { ttsManager.pause() }
        } else {
            guard currentChapterIndex < chapters.count else { return }
            let startPos = currentStartPosition()
            startTTSReading(from: startPos)
        }
    }
    
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        notifyUserInteractionStarted()
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            notifyUserInteractionEnded()
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        notifyUserInteractionEnded()
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        if isAutoScrolling {
            isAutoScrolling = false
            return
        }
        notifyUserInteractionEnded()
    }

    func requestChapterSwitch(to index: Int, startAtEnd: Bool = false) {
        guard index >= 0 && index < chapters.count else { return }
        performJumpToChapter(index, startAtEnd: startAtEnd)
    }

    func requestChapterSwitch(offset: Int, preferSeamless: Bool, startAtEnd: Bool? = nil) {
        guard offset != 0 else { return }
        let targetIndex = currentChapterIndex + offset
        guard targetIndex >= 0 && targetIndex < chapters.count else { return }
        if preferSeamless, attemptSeamlessSwitch(offset: offset) {
            applyChapterLandingPage(offset: offset)
            return
        }
        let shouldStartAtEnd = startAtEnd ?? (offset < 0)
        performJumpToChapter(targetIndex, startAtEnd: shouldStartAtEnd)
    }

    private func performJumpToChapter(_ index: Int, startAtEnd: Bool) {
        activePaginationAnchor = 0
        let isNext = index > currentChapterIndex
        currentChapterIndex = index
        lastReportedChapterIndex = index
        onChapterIndexChanged?(index)
        
        if currentReadingMode == .newHorizontal || currentReadingMode == .horizontal {
            performChapterTransition(isNext: isNext) { [weak self] in
                self?.loadChapterContent(at: index, startAtEnd: startAtEnd)
            }
        } else {
            performChapterTransitionFade { [weak self] in
                self?.loadChapterContent(at: index, startAtEnd: startAtEnd)
            }
        }
    }

    private func attemptSeamlessSwitch(offset: Int) -> Bool {
        guard offset != 0 else { return false }
        let canSwap = (offset > 0 && nextCache.renderStore != nil) || (offset < 0 && prevCache.renderStore != nil)
        guard canSwap else { return false }

        if offset > 0 {
            prevCache = currentCache
            currentCache = nextCache
            nextCache = .empty
        } else {
            nextCache = currentCache
            currentCache = prevCache
            prevCache = .empty
        }

        applyChapterState(afterSeamlessOffset: offset)
        return true
    }

    private func applyChapterState(afterSeamlessOffset offset: Int) {
        currentChapterIndex += offset
        lastReportedChapterIndex = currentChapterIndex
        if currentReadingMode == .horizontal || currentReadingMode == .newHorizontal {
            currentPageIndex = offset > 0 ? 0 : max(0, currentCache.pages.count - 1)
        }
        onChapterIndexChanged?(currentChapterIndex)
        updateVerticalAdjacent()
        if currentReadingMode == .newHorizontal {
            updateNewHorizontalContent()
        } else if currentReadingMode == .horizontal {
            updateHorizontalPage(to: currentPageIndex, animated: false)
        }
        prefetchAdjacentChapters(index: currentChapterIndex)
    }

    private func applyChapterLandingPage(offset: Int) {
        if currentReadingMode == .horizontal || currentReadingMode == .newHorizontal {
            let target = offset > 0 ? 0 : max(0, currentCache.pages.count - 1)
            currentPageIndex = target
            
            // 核心重置：在更新内容前重置滚动状态，切断当前的拖拽/惯性
            newHorizontalVC?.resetScrollState()
            
            if currentReadingMode == .newHorizontal {
                updateNewHorizontalContent()
            } else {
                updateHorizontalPage(to: target, animated: false)
            }
        } else if currentReadingMode == .vertical {
            if offset > 0 { verticalVC?.scrollToTop(animated: false) }
            else { verticalVC?.scrollToBottom(animated: false) }
        }
    }

    private func rebuildHorizontalControllerForTurningModeChange() {
        if currentReadingMode == .newHorizontal {
            if readerSettings.pageTurningMode == .simulation {
                return
            }
            // 新版模式不需要重建控制器，只需要刷新内容以应用新的 Layout 设置
            updateNewHorizontalContent()
            return
        }
        guard currentReadingMode == .horizontal, !isMangaMode else { return }
        if readerSettings.pageTurningMode != .simulation {
            return
        }
        if readerSettings.pageTurningMode == .simulation {
            isInternalTransitioning = true
            horizontalVC?.view.removeFromSuperview()
            horizontalVC?.removeFromParent()
            horizontalVC = nil
            setupHorizontalMode()
            isInternalTransitioning = false
            return
        }
        isInternalTransitioning = true
        performChapterTransitionFade { [weak self] in
            guard let self = self else { return }
            self.horizontalVC?.view.removeFromSuperview()
            self.horizontalVC?.removeFromParent()
            self.horizontalVC = nil
            self.setupHorizontalMode()
            self.isInternalTransitioning = false
        }
    }


    func switchChapterSeamlessly(offset: Int) {
        if attemptSeamlessSwitch(offset: offset) { return }
        requestChapterSwitch(offset: offset, preferSeamless: false)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { return nil }
    func syncTTSState() {
        ttsBridge.syncState(ttsManager: ttsManager, context: makeTTSSyncContext())
    }

    private func updateHorizontalHighlight(index: Int?, secondary: Set<Int>, isPlaying: Bool, highlightRange: NSRange?) {
        guard let h = horizontalVC,
              let pageVC = h.viewControllers?.first as? PageContentViewController,
              let contentView = pageVC.view.subviews.first as? ReadContent2View else { return }
        contentView.highlightIndex = index
        contentView.secondaryIndices = secondary
        contentView.isPlayingHighlight = isPlaying
        contentView.highlightRange = highlightRange
    }

    func completePendingTTSPositionSync() {
        guard ttsBridge.hasPendingSync() else { return }
        syncTTSReadingPositionIfNeeded()
    }

    func handleUserScrollCatchUp() {
        guard ttsBridge.consumePendingSync() else { return }
        guard let bookUrl = book.bookUrl, ttsManager.bookUrl == bookUrl else { return }
        guard ttsManager.isPlaying && !ttsManager.isPaused else { return }

        if !isTTSPositionInCurrentPage() {
            let context = ReaderTTSBridge.RestartContext(
                currentChapterIndex: currentChapterIndex,
                chaptersCount: chapters.count,
                startPosition: { [weak self] in self?.currentStartPosition() ?? ReadingPosition(chapterIndex: 0, sentenceIndex: 0, sentenceOffset: 0, charOffset: 0) },
                startReading: { [weak self] position in self?.startTTSReading(from: position) }
            )
            ttsBridge.restartFromCurrentPage(context: context)
        } else {
            syncTTSState()
        }
    }

    private func isTTSPositionInCurrentPage() -> Bool {
        guard ttsManager.currentChapterIndex == currentChapterIndex else { return false }
        let context = ReaderPositionContextBuilder.makeTTSPagePositionContext(
            readingMode: currentReadingMode,
            currentChapterIndex: currentChapterIndex,
            paragraphStarts: currentCache.paragraphStarts,
            pageInfos: currentCache.pageInfos ?? [],
            paragraphIndentLength: ReaderConstants.Text.paragraphIndentLength,
            horizontalPageIndexForDisplay: { [weak self] in self?.horizontalPageIndexForDisplay() ?? 0 },
            newHorizontalCurrentPageIndex: { [weak self] in self?.newHorizontalVC?.currentPageIndex ?? 0 },
            isSentenceVisibleInVertical: { [weak self] index in self?.verticalVC?.isSentenceVisible(index: index) ?? true }
        )
        return ReaderPositionCalculator.isTTSPositionInCurrentPage(
            context: context,
            isReadingChapterTitle: ttsManager.isReadingChapterTitle,
            hasChapterTitleInSentences: ttsManager.hasChapterTitleInSentences,
            sentenceIndex: ttsManager.currentSentenceIndex,
            sentenceOffset: ttsManager.currentSentenceOffset
        )
    }

    private func makeTTSSyncContext() -> ReaderTTSBridge.SyncContext {
        ReaderTTSContextBuilder.makeSyncContext(
            isMangaMode: isMangaMode,
            currentReadingMode: currentReadingMode,
            isInfiniteScrollEnabled: readerSettings.isInfiniteScrollEnabled,
            currentChapterIndex: currentChapterIndex,
            currentChapterUrl: currentCache.chapterUrl,
            nextCacheHasRenderStore: nextCache.renderStore != nil,
            chapters: chapters,
            currentCache: currentCache,
            currentPageIndex: currentPageIndex,
            newHorizontalCurrentPageIndex: { [weak self] in self?.newHorizontalVC?.currentPageIndex ?? 0 },
            horizontalPageIndexForDisplay: { [weak self] in self?.horizontalPageIndexForDisplay() ?? 0 },
            verticalIsSentenceVisible: { [weak self] index in self?.verticalVC?.isSentenceVisible(index: index) ?? true },
            verticalEnsureSentenceVisible: { [weak self] index in self?.verticalVC?.ensureSentenceVisible(index: index) },
            verticalSetHighlight: { [weak self] idx, secondary, isPlaying, range in
                self?.verticalVC?.setHighlight(index: idx, secondaryIndices: secondary, isPlaying: isPlaying, highlightRange: range)
            },
            newHorizontalSetHighlight: { [weak self] idx, secondary, isPlaying, range in
                self?.newHorizontalVC?.updateHighlight(index: idx, secondary: secondary, isPlaying: isPlaying, highlightRange: range)
            },
            horizontalSetHighlight: { [weak self] idx, secondary, isPlaying, range in
                self?.updateHorizontalHighlight(index: idx, secondary: secondary, isPlaying: isPlaying, highlightRange: range)
            },
            scrollNewHorizontal: { [weak self] page, animated in self?.newHorizontalVC?.scrollToPageIndex(page, animated: animated) },
            scrollHorizontal: { [weak self] page, animated in self?.updateHorizontalPage(to: page, animated: animated) },
            requestChapterSwitchSeamless: { [weak self] offset in
                self?.requestChapterSwitch(offset: offset, preferSeamless: true)
            },
            paragraphIndentLength: paragraphIndentLength
        )
    }

    private func startTTSReading(from startPos: ReadingPosition) {
        let context = ReaderTTSBridge.StartContext(
            text: currentCache.rawContent,
            sentences: currentCache.contentSentences,
            chapters: chapters,
            currentIndex: currentChapterIndex,
            bookUrl: book.bookUrl ?? "",
            bookSourceUrl: book.origin ?? "",
            bookTitle: book.name ?? "未知书名",
            coverUrl: book.coverUrl,
            replaceRules: replaceRuleViewModel?.rules,
            textProcessor: { [rules = replaceRuleViewModel?.rules] text in
                ReadingTextProcessor.prepareText(text, rules: rules)
            },
            shouldSpeakChapterTitle: startPos.isAtChapterStart
        )
        let chapterChange = ReaderTTSBridge.ChapterChangeBuilderSource(
            currentReadingMode: currentReadingMode,
            currentChapterIndex: { [weak self] in self?.currentChapterIndex ?? 0 },
            isInfiniteScrollEnabled: { [weak self] in self?.readerSettings.isInfiniteScrollEnabled ?? false },
            hasNextHorizontalPages: { [weak self] in !(self?.nextCache.pages.isEmpty ?? true) },
            hasPrevHorizontalPages: { [weak self] in !(self?.prevCache.pages.isEmpty ?? true) },
            prevHorizontalPageCount: { [weak self] in self?.prevCache.pages.count ?? 0 },
            animateToAdjacent: { [weak self] offset, targetPage in
                Task { @MainActor in
                    self?.animateToAdjacentChapter(offset: offset, targetPage: targetPage)
                }
            },
            requestChapterSwitch: { [weak self] index in
                Task { @MainActor in
                    self?.requestChapterSwitch(to: index)
                }
            },
            requestChapterSwitchSeamless: { [weak self] offset in
                Task { @MainActor in
                    self?.requestChapterSwitch(offset: offset, preferSeamless: true)
                }
            },
            suppressFollow: { [weak self] in
                self?.ttsBridge.suppressFollow(for: ReaderConstants.Interaction.ttsSuppressDuration)
            }
        ).build()
        ttsBridge.startReading(ttsManager: ttsManager, context: context, startPos: startPos, chapterChange: chapterChange)
    }

    func finalizeUserInteraction() {
        ttsBridge.finalizeUserInteraction()
    }

    func notifyUserInteractionStarted() {
        DisplayRateManager.shared.requestHighRate(true)
        ttsBridge.startUserInteraction()
        ttsSyncCoordinator?.userInteractionStarted()
    }

    func safeToggleMenu() {
        guard !isInternalTransitioning else { return }
        onToggleMenu?()
    }

    func notifyUserInteractionEnded() {
        DisplayRateManager.shared.requestHighRate(false)
        ttsBridge.endUserInteraction()
    }

    func markUserNavigation() {
        ttsBridge.markUserNavigation()
    }
    
    func syncTTSReadingPositionIfNeeded() {
        guard ttsBridge.consumePendingSync() else { return }
        guard let bookUrl = book.bookUrl, ttsManager.bookUrl == bookUrl else { return }
        let position = currentStartPosition()
        ttsManager.updateReadingPosition(to: position)
    }


    deinit {
        prefetchCoordinator.cancel()
        ttsSyncCoordinator?.stop()
    }
    private func currentStartPosition() -> ReadingPosition {
        ReaderPositionCalculator.currentStartPosition(
            context: ReaderPositionCalculator.StartPositionContext(
                readingMode: currentReadingMode,
                currentCache: currentCache,
                currentChapterIndex: currentChapterIndex,
                currentPageIndex: currentPageIndex,
                paragraphIndentLength: paragraphIndentLength,
                horizontalPageIndexForDisplay: { [weak self] in self?.horizontalPageIndexForDisplay() ?? 0 },
                newHorizontalCurrentPageIndex: { [weak self] in self?.newHorizontalVC?.currentPageIndex ?? 0 },
                verticalCharOffset: { [weak self] in self?.verticalVC?.getCurrentCharOffset() ?? 0 },
                verticalLastReportedIndex: { [weak self] in self?.verticalVC?.lastReportedIndex ?? 0 }
            )
        )
    }
    func scrollToChapterEnd(animated: Bool) { 
        if isMangaMode {
            mangaVC?.scrollToBottom(animated: animated)
        } else if currentReadingMode == .vertical { 
            verticalVC?.scrollToBottom(animated: animated) 
        } else if currentReadingMode == .newHorizontal {
            let target = max(0, currentCache.pages.count - 1)
            currentPageIndex = target
            newHorizontalVC?.scrollToPageIndex(target, animated: animated)
        } else { 
            isAutoScrolling = animated
            updateHorizontalPage(to: max(0, currentCache.pages.count - 1), animated: animated) 
        } 
    }
    private func matchSentenceIndex(for snippet: String) -> (index: Int, offset: Int)? {
        let trimmed = snippet.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        for (idx, sentence) in currentCache.contentSentences.enumerated() {
            if let range = sentence.range(of: trimmed, options: [.anchored, .literal]) {
                let offset = sentence.distance(from: sentence.startIndex, to: range.lowerBound)
                return (idx, offset)
            } else if let range = sentence.range(of: trimmed, options: [.literal]) {
                let offset = sentence.distance(from: sentence.startIndex, to: range.lowerBound)
                return (idx, offset)
            }
        }
        return nil
    }

    // MARK: - HorizontalCollectionViewDelegate
    func horizontalCollectionView(_ collectionView: HorizontalCollectionViewController, didUpdatePageIndex index: Int) {
        self.currentPageIndex = index
        self.isInternalTransitioning = false
        self.onProgressChanged?(currentChapterIndex, Double(currentPageIndex) / Double(max(1, currentCache.pages.count)))
        updateProgressUI()
        notifyUserInteractionEnded()
    }
    
    func horizontalCollectionView(_ collectionView: HorizontalCollectionViewController, didTapMiddle: Bool) {
        safeToggleMenu()
    }
    
    func horizontalCollectionView(_ collectionView: HorizontalCollectionViewController, didTapLeft: Bool) {
        handlePageTap(isNext: false)
    }
    
    func horizontalCollectionView(_ collectionView: HorizontalCollectionViewController, didTapRight: Bool) {
        handlePageTap(isNext: true)
    }
    
    func horizontalCollectionView(_ collectionView: HorizontalCollectionViewController, requestChapterSwitch offset: Int) {
        if collectionView.isCompositeEdgeSwitch {
            // 复合页已经展示过临近页，直接切章避免二次动画
            self.requestChapterSwitch(offset: offset, preferSeamless: true)
            collectionView.isCompositeEdgeSwitch = false
            return
        }
        if offset > 0 && !nextCache.pages.isEmpty {
            animateToAdjacentChapter(offset: 1, targetPage: 0)
        } else if offset < 0 && !prevCache.pages.isEmpty {
            animateToAdjacentChapter(offset: -1, targetPage: prevCache.pages.count - 1)
        } else {
            self.requestChapterSwitch(offset: offset, preferSeamless: true)
        }
    }

    func presentImagePreview(url: URL) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.presentedViewController is ImagePreviewViewController {
                return
            }
            let vc = ImagePreviewViewController(imageURL: url)
            vc.modalPresentationStyle = .fullScreen
            self.present(vc, animated: true)
        }
    }
}
