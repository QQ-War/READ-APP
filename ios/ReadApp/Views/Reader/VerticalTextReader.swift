import UIKit

// MARK: - UIKit 核心控制器
class VerticalTextViewController: UIViewController, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    let scrollView = UIScrollView()
    private let prevContentView = VerticalTextContentView()
    private let currentContentView = VerticalTextContentView()
    private let nextContentView = VerticalTextContentView() // 下一章拼接视图
    private let switchHintLabel = UILabel()
    private var pendingSwitchDirection: Int = 0
    private var switchReady = false
    private var switchWorkItem: DispatchWorkItem?
    private var hintWorkItem: DispatchWorkItem?
    private var isShowingSwitchResultHint = false
    private var lastViewSize: CGSize = .zero
    var isInfiniteScrollEnabled: Bool = true {
        didSet {
            _ = oldValue
        }
    }
    private var isTransitioning = false
    private var isChapterSwitching = false
    private var suppressAutoSwitchUntil: TimeInterval = 0
    private var dragStartTime: TimeInterval = 0
    var dampingFactor: CGFloat = ReaderConstants.Interaction.textDampingFactor
    private let chapterGap: CGFloat = ReaderConstants.Interaction.chapterGap
    private var lastInfiniteSetting: Bool?

    var onVisibleIndexChanged: ((Int) -> Void)?; var onAddReplaceRule: ((String) -> Void)?; var onTapMenu: (() -> Void)?; var onImageTapped: ((URL) -> Void)?
    var onReachedBottom: (() -> Void)?; var onReachedTop: (() -> Void)?; var onChapterSwitched: ((Int) -> Void)?
    var onInteractionChanged: ((Bool) -> Void)?
    var safeAreaTop: CGFloat = 0; var chapterUrl: String?
    private struct CharDetectionConfig {
        static let minHorizontalInset: CGFloat = ReaderConstants.Interaction.minHorizontalInset
        static let minVerticalOffset: CGFloat = ReaderConstants.Interaction.minVerticalOffset
        static let maxVerticalOffset: CGFloat = ReaderConstants.Interaction.maxVerticalOffset
    }
    private let viewportTopMargin: CGFloat = ReaderConstants.Interaction.viewportTopMargin
    private var contentTopPadding: CGFloat { safeAreaTop + viewportTopMargin }
    private var horizontalMarginForDetection: CGFloat {
        max(CharDetectionConfig.minHorizontalInset, lastMargin)
    }
    private var verticalDetectionOffset: CGFloat {
        ReaderTextPositioning.detectionOffset(fontSize: lastFontSize, lineSpacing: lastLineSpacing)
    }
    var threshold: CGFloat = 80
    var seamlessSwitchThreshold: CGFloat = ReaderConstants.Interaction.seamlessSwitchThreshold
    
    private var renderStore: TextKit2RenderStore?; private var nextRenderStore: TextKit2RenderStore?; private var prevRenderStore: TextKit2RenderStore?
    private var currentSentences: [String] = []; private var nextSentences: [String] = []; private var prevSentences: [String] = []
    private var paragraphStarts: [Int] = []; private var sentenceYOffsets: [CGFloat] = []
    var lastReportedIndex: Int = -1; private var isUpdatingLayout = false; private var lastTTSSyncIndex: Int = -1
    
    private var lastHighlightIndex: Int?; private var lastSecondaryIndices: Set<Int> = []; private var lastFontSize: CGFloat = 0; private var lastLineSpacing: CGFloat = 0; private var lastMargin: CGFloat = 20
    
    // 无感置换状态记录
    private var previousContentHeight: CGFloat = 0
    private var lastPrevContentHeight: CGFloat = 0
    private var lastPrevHasContent = false
    
    // 无限流无缝切换标记 (0: 无, 1: 下一章, -1: 上一章)
    private var pendingSeamlessSwitch: Int = 0
    private var isAutoScrolling = false
    private var estimatedLineHeight: CGFloat = ReaderConstants.Interaction.estimatedLineHeight
    private lazy var seamlessSwitchCoordinator = ReaderSeamlessSwitchCoordinator(
        state: .init(
            isInfiniteScrollEnabled: { [weak self] in self?.isInfiniteScrollEnabled ?? false },
            pendingDirection: { [weak self] in self?.pendingSeamlessSwitch ?? 0 },
            setPendingDirection: { [weak self] value in self?.pendingSeamlessSwitch = value },
            nextAvailable: { [weak self] in self?.nextRenderStore != nil },
            prevAvailable: { [weak self] in self?.prevRenderStore != nil },
            currentTopY: { [weak self] in self?.currentContentView.frame.minY ?? 0 },
            currentBottomY: { [weak self] in self?.currentContentView.frame.maxY ?? 0 },
            contentHeight: { [weak self] in self?.scrollView.contentSize.height ?? 0 },
            viewportHeight: { [weak self] in self?.scrollView.bounds.height ?? 0 }
        ),
        params: .init(
            triggerPadding: ReaderConstants.Layout.extraSpacing,
            triggerMin: ReaderConstants.Interaction.seamlessTriggerMin
        )
    )

    override func viewDidLoad() {
        super.viewDidLoad()
        scrollView.delegate = self
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.showsVerticalScrollIndicator = true
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)
        scrollView.addSubview(prevContentView)
        scrollView.addSubview(currentContentView)
        scrollView.addSubview(nextContentView)
        setupSwitchHint()
        
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.delegate = self
        scrollView.addGestureRecognizer(tap)
        
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress))
        longPress.minimumPressDuration = ReaderConstants.Interaction.longPressDuration
        longPress.delegate = self
        scrollView.addGestureRecognizer(longPress)
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if view.bounds.size != lastViewSize {
            lastViewSize = view.bounds.size
            if !isUpdatingLayout { 
                scrollView.frame = view.bounds
                updateLayoutFrames() 
            }
        }
    }
    
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

    @objc private func handleTap(_ g: UITapGestureRecognizer) {
        let point = g.location(in: scrollView)
        if let url = imageURLForTap(point) {
            onImageTapped?(url)
            return
        }
        pendingSeamlessSwitch = 0
        suppressAutoSwitchUntil = Date().timeIntervalSince1970 + ReaderConstants.Interaction.autoSwitchSuppressDuration
        cancelSwitchHold()
        onTapMenu?()
    }

    private func imageURLForTap(_ point: CGPoint) -> URL? {
        let isInPrev = !prevContentView.isHidden && point.y < currentContentView.frame.minY
        let isInNext = !nextContentView.isHidden && point.y >= nextContentView.frame.minY
        let targetView = isInPrev ? prevContentView : (isInNext ? nextContentView : currentContentView)
        let store = isInPrev ? prevRenderStore : (isInNext ? nextRenderStore : renderStore)
        guard let store = store else { return nil }
        let local = CGPoint(x: point.x - targetView.frame.minX, y: point.y - targetView.frame.minY)
        return InlineImageHitTester.imageURL(at: local, in: store)
    }
    @objc private func handleLongPress(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began else { return }
        let p = g.location(in: scrollView)
        let isInPrev = !prevContentView.isHidden && p.y < currentContentView.frame.minY
        let isInNext = !nextContentView.isHidden && p.y >= nextContentView.frame.minY
        let s = isInPrev ? prevRenderStore : (isInNext ? nextRenderStore : renderStore)
        let cv = isInPrev ? prevContentView : (isInNext ? nextContentView : currentContentView)
        guard let store = s else { return }
        let pointInContent = g.location(in: cv)
        
        if let f = store.layoutManager.textLayoutFragment(for: pointInContent), 
           let te = f.textElement, let range = te.elementRange, 
           let r = TextKit2Paginator.rangeFromTextRange(range, in: store.contentStorage) {
            let txt = (store.attributedString.string as NSString).substring(with: r)
            // 直接触发，不再显示菜单
            onAddReplaceRule?(txt)
        }
    }

    override var canBecomeFirstResponder: Bool { true }


    @discardableResult
    func update(
        sentences: [String],
        nextSentences: [String]?,
        prevSentences: [String]?,
        title: String?,
        nextTitle: String?,
        prevTitle: String?,
        fontSize: CGFloat,
        lineSpacing: CGFloat,
        margin: CGFloat,
        highlightIndex: Int?,
        secondaryIndices: Set<Int>,
        isPlaying: Bool,
        renderStore: TextKit2RenderStore?,
        paragraphStarts: [Int],
        nextRenderStore: TextKit2RenderStore?,
        nextParagraphStarts: [Int],
        prevRenderStore: TextKit2RenderStore?,
        prevParagraphStarts: [Int]
    ) -> Bool {
        let marginChanged = self.lastMargin != margin
        self.lastMargin = margin
        
        let modeChanged = self.lastInfiniteSetting != isInfiniteScrollEnabled
        self.lastInfiniteSetting = isInfiniteScrollEnabled
        
        let trimmedSentences = sentences.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let trimmedNextSentences = (nextSentences ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let trimmedPrevSentences = (prevSentences ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        _ = nextSentences
        _ = prevSentences
        
        let contentChanged = self.currentSentences != trimmedSentences || lastFontSize != fontSize || lastLineSpacing != lineSpacing || marginChanged
        let nextChanged = self.nextSentences != trimmedNextSentences || marginChanged
        let prevChanged = self.prevSentences != trimmedPrevSentences || marginChanged
        
        let isChapterSwap = (trimmedSentences == self.nextSentences) && !trimmedSentences.isEmpty
        let isChapterSwapToPrev = (trimmedSentences == self.prevSentences) && !trimmedSentences.isEmpty
        
        var layoutNeeded = modeChanged // 关键：如果模式变了，必须重新布局
        
        if contentChanged || self.renderStore == nil || (renderStore != nil && self.renderStore !== renderStore) {
            self.previousContentHeight = currentContentView.frame.height
            self.currentSentences = trimmedSentences; self.lastFontSize = fontSize; self.lastLineSpacing = lineSpacing; isUpdatingLayout = true

            if let externalStore = renderStore {
                self.renderStore = externalStore
                if !paragraphStarts.isEmpty {
                    self.paragraphStarts = paragraphStarts
                }
                let width = ReaderMath.layoutWidth(containerWidth: (viewIfLoaded?.bounds.width ?? ReaderConstants.Layout.minLayoutWidthFallback), margin: margin)
                externalStore.update(attributedString: externalStore.attributedString, layoutWidth: width)
            } else {
                let titleText = title != nil && !title!.isEmpty ? title! + "\n" : ""
                let titleLen = titleText.utf16.count
                var pS: [Int] = []; var cP = titleLen
                for (idx, s) in trimmedSentences.enumerated() {
                    pS.append(cP)
                    cP += (s.utf16.count + 2)
                    if idx < trimmedSentences.count - 1 { cP += 1 }
                }
                self.paragraphStarts = pS
                
                let attr = createAttr(trimmedSentences, title: title, fontSize: fontSize, lineSpacing: lineSpacing)
                if let s = self.renderStore { s.update(attributedString: attr, layoutWidth: ReaderMath.layoutWidth(containerWidth: (viewIfLoaded?.bounds.width ?? ReaderConstants.Layout.minLayoutWidthFallback), margin: margin)) }
                else { self.renderStore = TextKit2RenderStore(attributedString: attr, layoutWidth: ReaderMath.layoutWidth(containerWidth: (viewIfLoaded?.bounds.width ?? ReaderConstants.Layout.minLayoutWidthFallback), margin: margin)) }
            }
            calculateSentenceOffsets(); isUpdatingLayout = false
            currentContentView.update(renderStore: self.renderStore, highlightIndex: highlightIndex, secondaryIndices: secondaryIndices, isPlaying: isPlaying, highlightRange: nil, paragraphStarts: self.paragraphStarts, margin: margin, forceRedraw: true)
            layoutNeeded = true
        }
        
        if nextChanged {
            self.nextSentences = trimmedNextSentences
            if trimmedNextSentences.isEmpty {
                self.nextRenderStore = nil
                nextContentView.isHidden = true
            } else {
                if let externalStore = nextRenderStore {
                    self.nextRenderStore = externalStore
                    let width = ReaderMath.layoutWidth(containerWidth: view.bounds.width, margin: margin)
                    externalStore.update(attributedString: externalStore.attributedString, layoutWidth: width)
                } else {
                    let attr = createAttr(trimmedNextSentences, title: nextTitle, fontSize: fontSize, lineSpacing: lineSpacing)
                    if let s = self.nextRenderStore { s.update(attributedString: attr, layoutWidth: ReaderMath.layoutWidth(containerWidth: view.bounds.width, margin: margin)) }
                    else { self.nextRenderStore = TextKit2RenderStore(attributedString: attr, layoutWidth: ReaderMath.layoutWidth(containerWidth: view.bounds.width, margin: margin)) }
                }
                nextContentView.update(renderStore: self.nextRenderStore, highlightIndex: nil, secondaryIndices: [], isPlaying: false, highlightRange: nil, paragraphStarts: nextParagraphStarts, margin: margin, forceRedraw: true)
            }
            layoutNeeded = true
        }
        
        if prevChanged {
            self.prevSentences = trimmedPrevSentences
            if trimmedPrevSentences.isEmpty {
                self.prevRenderStore = nil
                prevContentView.isHidden = true
            } else {
                if let externalStore = prevRenderStore {
                    self.prevRenderStore = externalStore
                    let width = ReaderMath.layoutWidth(containerWidth: view.bounds.width, margin: margin)
                    externalStore.update(attributedString: externalStore.attributedString, layoutWidth: width)
                } else {
                    let attr = createAttr(trimmedPrevSentences, title: prevTitle, fontSize: fontSize, lineSpacing: lineSpacing)
                    if let s = self.prevRenderStore { s.update(attributedString: attr, layoutWidth: ReaderMath.layoutWidth(containerWidth: view.bounds.width, margin: margin)) }
                    else { self.prevRenderStore = TextKit2RenderStore(attributedString: attr, layoutWidth: ReaderMath.layoutWidth(containerWidth: view.bounds.width, margin: margin)) }
                }
                prevContentView.update(renderStore: self.prevRenderStore, highlightIndex: nil, secondaryIndices: [], isPlaying: false, highlightRange: nil, paragraphStarts: prevParagraphStarts, margin: margin, forceRedraw: true)
            }
            layoutNeeded = true
        }
        
        if layoutNeeded {
            let oldOffset = scrollView.contentOffset.y
            let oldCurrY = currentContentView.frame.minY
            let wasPrevVisible = lastPrevHasContent
            let oldPrevHeightPlusGap = lastPrevHasContent ? (lastPrevContentHeight + chapterGap) : 0
            
            isUpdatingLayout = true
            updateLayoutFrames()
            
            if isTransitioning {
                self.view.alpha = 1
                self.scrollView.isUserInteractionEnabled = true
                self.isTransitioning = false
            } else if isInfiniteScrollEnabled {
                if isChapterSwap {
                    if wasPrevVisible { 
                        let newOffset = max(0, oldOffset - oldPrevHeightPlusGap)
                        scrollView.contentOffset.y = newOffset 
                    }
                } else if isChapterSwapToPrev {
                    let newPrevHeightPlusGap = lastPrevHasContent ? (lastPrevContentHeight + chapterGap) : 0
                    let newOffset = oldOffset + newPrevHeightPlusGap
                    scrollView.contentOffset.y = newOffset
                } else if prevChanged && !isChapterSwapToPrev {
                    if contentChanged || modeChanged {
                        let displacement = currentContentView.frame.minY - oldCurrY
                        if displacement != 0 { 
                            let newOffset = oldOffset + displacement
                            scrollView.contentOffset.y = newOffset 
                        }
                    }
                } else if modeChanged {
                    // 仅由于模式切换（非无限->无限）导致的布局变化，强制刷新当前 contentOffset 触发一次校验
                    let newOffset = oldOffset + (currentContentView.frame.minY - oldCurrY)
                    scrollView.contentOffset.y = newOffset
                }
            } else if modeChanged && !isInfiniteScrollEnabled {
                // 从无限流切回普通模式
                let displacement = currentContentView.frame.minY - oldCurrY
                let newOffset = oldOffset + displacement
                scrollView.contentOffset.y = newOffset
            }
            isUpdatingLayout = false

        }

        if lastHighlightIndex != highlightIndex || lastSecondaryIndices != secondaryIndices {
            lastHighlightIndex = highlightIndex; lastSecondaryIndices = secondaryIndices
            currentContentView.update(renderStore: renderStore, highlightIndex: highlightIndex, secondaryIndices: secondaryIndices, isPlaying: isPlaying, highlightRange: nil, paragraphStarts: paragraphStarts, margin: margin, forceRedraw: true)
        }
        
        applyScrollBehaviorIfNeeded()
        checkSeamlessSwitchAfterContentUpdate()
        return contentChanged
    }

    private func createAttr(_ sents: [String], title: String?, fontSize: CGFloat, lineSpacing: CGFloat) -> NSAttributedString {
        let fullAttr = NSMutableAttributedString()
        
        if let title = title, !title.isEmpty {
            let p = NSMutableParagraphStyle()
            p.alignment = .center
            p.paragraphSpacing = fontSize * ReaderConstants.Text.titleParagraphSpacingFactor
            fullAttr.append(NSAttributedString(string: title + "\n", attributes: [
                .font: ReaderFontProvider.titleFont(size: fontSize + 8),
                .foregroundColor: UserPreferences.shared.readingTheme.textColor,
                .paragraphStyle: p
            ]))
        }
        
        let text = sents.map { String(repeating: "　", count: paragraphIndentLength) + $0 }.joined(separator: "\n")
        let p = NSMutableParagraphStyle()
        p.lineSpacing = lineSpacing
        p.alignment = .justified
        fullAttr.append(NSAttributedString(string: text, attributes: [.font: ReaderFontProvider.bodyFont(size: fontSize), .foregroundColor: UserPreferences.shared.readingTheme.textColor, .paragraphStyle: p]))
        
        return fullAttr
    }

    private func calculateSentenceOffsets() {
        guard let s = renderStore else { return }; s.layoutManager.ensureLayout(for: s.contentStorage.documentRange); var o: [CGFloat] = []
        let totalLen = s.attributedString.length
        
        // 方案优化：行高基准直接采用正文字号，彻底避开大标题干扰
        let bodyFont = ReaderFontProvider.bodyFont(size: lastFontSize)
        self.estimatedLineHeight = bodyFont.lineHeight + lastLineSpacing
        
        for start in paragraphStarts { 
            if start < totalLen, let loc = s.contentStorage.location(s.contentStorage.documentRange.location, offsetBy: start), let f = s.layoutManager.textLayoutFragment(for: loc) { 
                o.append(f.layoutFragmentFrame.minY) 
            } else { 
                o.append(o.last ?? 0) 
            } 
        }
        sentenceYOffsets = o
    }

    private func updateLayoutFrames() {
        guard let s = renderStore else { return }
        var h1: CGFloat = 0
        s.layoutManager.enumerateTextLayoutFragments(from: s.contentStorage.documentRange.endLocation, options: [.reverse, .ensuresLayout]) { f in h1 = f.layoutFragmentFrame.maxY; return false }
        let m = (view.bounds.width - s.layoutWidth) / 2
        let topPadding = contentTopPadding
        
        if isInfiniteScrollEnabled {
            var currentY = topPadding
            var totalH = topPadding
            if let ps = prevRenderStore {
                var h0: CGFloat = 0
                ps.layoutManager.enumerateTextLayoutFragments(from: ps.contentStorage.documentRange.endLocation, options: [.reverse, .ensuresLayout]) { f in h0 = f.layoutFragmentFrame.maxY; return false }
                prevContentView.isHidden = false
                prevContentView.frame = CGRect(x: m, y: currentY, width: ps.layoutWidth, height: h0)
                currentY += h0 + chapterGap
                totalH += h0 + chapterGap
                lastPrevContentHeight = h0
                lastPrevHasContent = true
            } else {
                prevContentView.isHidden = true
                lastPrevContentHeight = 0
                lastPrevHasContent = false
            }
            currentContentView.frame = CGRect(x: m, y: currentY, width: s.layoutWidth, height: h1)
            totalH += h1
            if let ns = nextRenderStore {
                var h2: CGFloat = 0
                ns.layoutManager.enumerateTextLayoutFragments(from: ns.contentStorage.documentRange.endLocation, options: [.ensuresLayout]) { f in h2 = f.layoutFragmentFrame.maxY; return false }
                nextContentView.isHidden = false
                nextContentView.frame = CGRect(x: m, y: currentY + h1 + chapterGap, width: ns.layoutWidth, height: h2)
                totalH += h2 + chapterGap
            } else { nextContentView.isHidden = true }
            scrollView.contentSize = CGSize(width: view.bounds.width, height: totalH + ReaderConstants.Layout.extraSpacing)
        } else {
            // 非无限流：ContentSize 仅为当前章
            currentContentView.frame = CGRect(x: m, y: topPadding, width: s.layoutWidth, height: h1)
            // 关键优化：增加 100px 底部余量，确保最后一章节的末尾也能滚到探测点
            scrollView.contentSize = CGSize(width: view.bounds.width, height: topPadding + h1 + ReaderConstants.Layout.extraSpacing)
            
            // 预览内容放置在 100px 间距外
            if let ps = prevRenderStore {
                var h0: CGFloat = 0
                ps.layoutManager.enumerateTextLayoutFragments(from: ps.contentStorage.documentRange.endLocation, options: [.reverse, .ensuresLayout]) { f in h0 = f.layoutFragmentFrame.maxY; return false }
                prevContentView.isHidden = false
                prevContentView.frame = CGRect(x: m, y: topPadding - h0 - ReaderConstants.Layout.extraSpacing, width: ps.layoutWidth, height: h0)
            } else { prevContentView.isHidden = true }
            
            if let ns = nextRenderStore {
                var h2: CGFloat = 0
                ns.layoutManager.enumerateTextLayoutFragments(from: ns.contentStorage.documentRange.endLocation, options: [.ensuresLayout]) { f in h2 = f.layoutFragmentFrame.maxY; return false }
                nextContentView.isHidden = false
                nextContentView.frame = CGRect(x: m, y: topPadding + h1 + ReaderConstants.Layout.extraSpacing, width: ns.layoutWidth, height: h2)
            } else { nextContentView.isHidden = true }
            lastPrevHasContent = false
        }
    }

    func scrollViewDidScroll(_ s: UIScrollView) {
        if isUpdatingLayout { return }
        let rawOffset = s.contentOffset.y
        let y = s.contentOffset.y - contentTopPadding
        
        seamlessSwitchCoordinator.handleAutoSwitch(rawOffset: rawOffset)
        handleHoldSwitchIfNeeded(rawOffset: rawOffset)
        
        // 当关闭无限流时，应用视觉阻尼
        if !isInfiniteScrollEnabled {
            let inset = scrollView.adjustedContentInset
            let contentHeight = scrollView.contentSize.height
            let viewportHeight = scrollView.bounds.height
            let maxScrollY = max(-inset.top, contentHeight - viewportHeight + inset.bottom)
            let currentScale = scrollView.zoomScale
            
            if rawOffset < -inset.top {
                let diff = -inset.top - rawOffset
                let ty = (diff * dampingFactor) / currentScale
                currentContentView.transform = CGAffineTransform(scaleX: currentScale, y: currentScale).translatedBy(x: 0, y: ty)
            } else if rawOffset > maxScrollY {
                let diff = rawOffset - maxScrollY
                let ty = (-diff * dampingFactor) / currentScale
                currentContentView.transform = CGAffineTransform(scaleX: currentScale, y: currentScale).translatedBy(x: 0, y: ty)
            } else {
                // 正常区域，确保清除位移但保留缩放
                if currentContentView.transform.ty != 0 || currentContentView.transform.a != currentScale {
                    currentContentView.transform = CGAffineTransform(scaleX: currentScale, y: currentScale)
                }
            }
        } else {
            if currentContentView.transform != .identity { currentContentView.transform = .identity }
        }
        
        if isInfiniteScrollEnabled {
            if s.contentOffset.y > s.contentSize.height - s.bounds.height * ReaderConstants.Interaction.reachBottomFactor { onReachedBottom?() }
            if s.contentOffset.y < s.bounds.height * ReaderConstants.Interaction.reachTopFactor { onReachedTop?() }
        }
        
        // 实时同步进度 UI：通知外部容器刷新进度标签
        let idx = sentenceYOffsets.lastIndex(where: { $0 <= y + verticalDetectionOffset }) ?? 0
        if idx != lastReportedIndex { 
            lastReportedIndex = idx
            onVisibleIndexChanged?(idx) 
        } else {
            // 即使索引没变，如果是垂直模式，我们为了百分比准确，也需要触发 UI 刷新
            // 这里我们通过调用回调来触发容器的 updateProgressUI
            onVisibleIndexChanged?(idx)
        }
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        dragStartTime = Date().timeIntervalSince1970
        cancelSwitchHold()
        pendingSeamlessSwitch = 0 
        onInteractionChanged?(true)
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        onInteractionChanged?(false)
        
        if !isInfiniteScrollEnabled {
            if switchReady && pendingSwitchDirection != 0 && !isTransitioning && !isChapterSwitching {
                let direction = pendingSwitchDirection
                isTransitioning = true
                isChapterSwitching = true
                scrollView.isUserInteractionEnabled = false
                
                // 停止当前的滚动速度，防止回弹干扰转场
                scrollView.setContentOffset(scrollView.contentOffset, animated: false)
                
                UIView.animate(withDuration: ReaderConstants.Interaction.switchHintAnimation, animations: {
                    self.view.alpha = 0 
                }) { _ in
                    self.onChapterSwitched?(direction)
                    // 注意：这里的 alpha 恢复逻辑在 update 方法中处理
                }
                self.cancelSwitchHold()
                return
            }
            cancelSwitchHold()
            return
        }
        
        if !decelerate { executeSeamlessSwitchIfNeeded() }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        onInteractionChanged?(false)
        if !isInfiniteScrollEnabled {
            cancelSwitchHold()
            return
        }
        executeSeamlessSwitchIfNeeded()
    }
    
    private func executeSeamlessSwitchIfNeeded() {
        if pendingSeamlessSwitch != 0 {
            if isChapterSwitching { return }
            let dir = pendingSeamlessSwitch
            let y = scrollView.contentOffset.y
            
            // 判定逻辑：
            // 1. 如果已经停下来了，直接允许切换
            // 2. 如果还在滚动，只有当旧章节已经完全滚出视野，新章节占据主导时，才允许静默切换
            let safeToSwitch: Bool
            if !scrollView.isDragging && !scrollView.isDecelerating {
                safeToSwitch = true
            } else if dir == 1 {
                // 向下滚：当旧章节的底部已经滚出屏幕顶端，或者新章节已经占据了屏幕大部分
                safeToSwitch = y > currentContentView.frame.maxY
            } else {
                // 向上滚：当当前章节的顶部已经滚出屏幕底端
                safeToSwitch = y < currentContentView.frame.minY - scrollView.bounds.height
            }
            
            if safeToSwitch {
                pendingSeamlessSwitch = 0
                isChapterSwitching = true
                showSwitchResultHint(direction: dir)
                onChapterSwitched?(dir)
            }
        }
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        if isAutoScrolling {
            isAutoScrolling = false
            return
        }
        onInteractionChanged?(false)
    }

    func scrollToSentence(index: Int, animated: Bool) { guard index >= 0 && index < sentenceYOffsets.count else { return }; let y = max(0, sentenceYOffsets[index] + contentTopPadding); scrollView.setContentOffset(CGPoint(x: 0, y: min(y, max(0, scrollView.contentSize.height - scrollView.bounds.height))), animated: animated) }

    private func getYOffsetForCharOffset(_ o: Int) -> CGFloat? {
        guard let s = renderStore else { return nil }
        let totalLen = s.attributedString.length
        let clampedO = ReaderTextPositioning.clampCharOffset(o, totalLength: totalLen)
        
        s.layoutManager.ensureLayout(for: s.contentStorage.documentRange)
        
        if let loc = s.contentStorage.location(s.contentStorage.documentRange.location, offsetBy: clampedO),
           let f = s.layoutManager.textLayoutFragment(for: loc) {
            let fragMinY = f.layoutFragmentFrame.minY
            
            if #available(iOS 15.0, *) {
                let fragmentStart = s.contentStorage.offset(from: s.contentStorage.documentRange.location, to: f.rangeInElement.location)
                let offsetInFrag = clampedO - fragmentStart
                for line in f.textLineFragments {
                    if line.characterRange.location + line.characterRange.length > offsetInFrag {
                        let lineY = fragMinY + line.typographicBounds.minY
                        return lineY
                    }
                }
            }
            return fragMinY
        }
        return nil
    }

    func ensureSentenceVisible(index: Int) {
        // 如果是 TTS 正在播放，基于实时 sentenceOffset 计算精确字符偏移实现平滑跟随
        if let tts = TTSManager.shared.isPlaying ? TTSManager.shared : nil {
            let readerVC = (self.parent as? ReaderContainerViewController)
            let isCurrentChapter = tts.currentChapterIndex == readerVC?.currentChapterIndex
            let isNextChapter = tts.currentChapterIndex == (readerVC?.currentChapterIndex ?? -1) + 1
            
            if tts.isReadingChapterTitle && isCurrentChapter { return }
            
            // 确定参考视图和数据源
            let targetContentView: VerticalTextContentView
            let targetRenderStore: TextKit2RenderStore?
            let targetParagraphStarts: [Int]
            
            if isCurrentChapter {
                targetContentView = currentContentView
                targetRenderStore = renderStore
                targetParagraphStarts = paragraphStarts
            } else if isNextChapter && isInfiniteScrollEnabled && !nextContentView.isHidden {
                targetContentView = nextContentView
                targetRenderStore = nextRenderStore
                // 下一章的 paragraphStarts 由于尚未切换，我们只能基于字符查找
                targetParagraphStarts = [] 
            } else {
                return
            }

            guard let store = targetRenderStore else { return }

            let bodySentenceIndex = tts.hasChapterTitleInSentences ? (tts.currentSentenceIndex - 1) : tts.currentSentenceIndex
            
            // 计算字符偏移对应的 Y 坐标
            var yInTargetContent: CGFloat? = nil
            
            // 计算全局字符偏移
            if bodySentenceIndex >= 0 && isCurrentChapter && bodySentenceIndex < targetParagraphStarts.count {
                let charOffsetInChapter = targetParagraphStarts[bodySentenceIndex] + tts.currentSentenceOffset + paragraphIndentLength
                yInTargetContent = getYOffsetForCharOffset(charOffsetInChapter)
            } else if isNextChapter {
                // 如果是下一章，我们需要计算相对于下个章节内容的偏移
                // 注意：TTSManager 在下一章开始时会将 sentenceIndex 重置为 0
                let rawOffset = tts.currentSentenceOffset + paragraphIndentLength
                yInTargetContent = getYOffsetForCharOffsetInStore(store, offset: rawOffset)
            }

            if let yInContent = yInTargetContent {
                let absY = yInContent + targetContentView.frame.minY
                let curY = scrollView.contentOffset.y
                let vH = scrollView.bounds.height
                
                // 核心逻辑：计算当前正在读的行相对于可视区域顶部的偏移
                let currentReadingYRelativeToViewport = absY - (curY + contentTopPadding)
                
                // 策略：
                // 1. 如果是章节第一句且还没对齐，或者偏离非常大（超过2行），则强制对齐
                // 2. 如果是普通微调，维持 0.3 行的灵敏度
                let isFirstSentence = tts.currentSentenceIndex <= (tts.hasChapterTitleInSentences ? 1 : 0)
                let tuning = ReaderTextPositioning.isAutoScrollNeeded(
                    relativeOffset: currentReadingYRelativeToViewport,
                    estimatedLineHeight: estimatedLineHeight,
                    isFirstSentence: isFirstSentence,
                    viewportHeight: vH
                )
                if tuning.shouldScroll {
                    let targetY = max(0, absY - contentTopPadding)
                    isAutoScrolling = true
                    // 如果偏离巨大，说明是刚换章或者用户跳进度了，用非动画形式先跳过去，再由 sync 维持平滑
                    scrollView.setContentOffset(CGPoint(x: 0, y: min(targetY, max(0, scrollView.contentSize.height - scrollView.bounds.height))), animated: tuning.shouldAnimate)
                    if !tuning.shouldAnimate {
                        isAutoScrolling = false
                    }
                }
                return
            }
        }
    }

    private func getYOffsetForCharOffsetInStore(_ s: TextKit2RenderStore, offset: Int) -> CGFloat? {
        let totalLen = s.attributedString.length
        let clampedO = ReaderTextPositioning.clampCharOffset(offset, totalLength: totalLen)
        s.layoutManager.ensureLayout(for: s.contentStorage.documentRange)
        
        if let loc = s.contentStorage.location(s.contentStorage.documentRange.location, offsetBy: clampedO),
           let f = s.layoutManager.textLayoutFragment(for: loc) {
            let fragMinY = f.layoutFragmentFrame.minY
            if #available(iOS 15.0, *) {
                let fragmentStart = s.contentStorage.offset(from: s.contentStorage.documentRange.location, to: f.rangeInElement.location)
                let offsetInFrag = clampedO - fragmentStart
                for line in f.textLineFragments {
                    if line.characterRange.location + line.characterRange.length > offsetInFrag {
                        return fragMinY + line.typographicBounds.minY
                    }
                }
            }
            return fragMinY
        }
        return nil
    }

    func isSentenceVisible(index: Int) -> Bool {
        guard index >= 0 && index < sentenceYOffsets.count else { return true }
        let startY = sentenceYOffsets[index] + contentTopPadding
        let endY = (index + 1 < sentenceYOffsets.count) ? (sentenceYOffsets[index+1] + contentTopPadding) : scrollView.contentSize.height
        
        let cur = scrollView.contentOffset.y
        let vH = scrollView.bounds.height
        
        // 修正判定逻辑：只要段落的任意一部分在可见区域内，或者包含当前视口顶部，就认为可见
        // 允许 50pt 的缓冲，防止频繁重定位
        return (startY <= cur + vH + ReaderConstants.Interaction.visibleRangePadding) && (endY >= cur - ReaderConstants.Interaction.visibleRangePadding)
    }
    func scrollToTop(animated: Bool) { scrollView.setContentOffset(.zero, animated: animated) }
    func scrollToBottom(animated: Bool) {
        let y = max(0, scrollView.contentSize.height - scrollView.bounds.height)
        scrollView.setContentOffset(CGPoint(x: 0, y: y), animated: animated)
    }
    func scrollToChapterEnd(animated: Bool) {
        guard let s = renderStore else { return }
        scrollToCharOffset(s.attributedString.length, animated: animated, isEnd: true)
    }
    func scrollToProgress(_ pos: Double) {
        guard let s = renderStore else { return }
        let total = s.attributedString.length
        let offset = Int(pos * Double(total))
        scrollToCharOffset(offset, animated: false)
    }
    func getCurrentSentenceIndex() -> Int {
        guard !sentenceYOffsets.isEmpty else { return 0 }
        let y = scrollView.contentOffset.y - contentTopPadding
        let idx = sentenceYOffsets.lastIndex(where: { $0 <= y + verticalDetectionOffset }) ?? 0
        return max(0, idx)
    }
    func getCurrentCharOffset() -> Int {
        guard let s = renderStore, viewIfLoaded != nil else { return 0 }
        
        // 关键：确保排版已计算，否则 textLayoutFragment 可能返回 nil
        s.layoutManager.ensureLayout(for: s.contentStorage.documentRange)
        
        let detectionOffset = ReaderTextPositioning.lineDetectionOffset(fontSize: lastFontSize)
        let globalY = scrollView.contentOffset.y + contentTopPadding + detectionOffset
        let localY = globalY - currentContentView.frame.minY
        
        // 边界保护：如果在当前章节视图上方 50pt 以上，说明视觉中心还在上一章，返回 -1 标识不要重定位
        if localY < -ReaderConstants.Interaction.detectionNegativeClamp {
            return -1
        }
        
        // 边界保护：如果在当前章节视图下方，返回最后一个字符
        if localY > currentContentView.frame.height {
            return s.attributedString.length > 0 ? s.attributedString.length - 1 : 0
        }
        
        let point = CGPoint(
            x: horizontalMarginForDetection,
            y: max(0, localY) // 修正：虽然上面判断了 -50，但传入 point 最好是非负
        )
        
        var result: Int = 0
        if let f = s.layoutManager.textLayoutFragment(for: point) {
            if #available(iOS 15.0, *) {
                let relativeY = max(0, localY - f.layoutFragmentFrame.minY)
                if let line = f.textLineFragments.first(where: { $0.typographicBounds.maxY > relativeY + 0.001 }) {
                    let fragmentStart = s.contentStorage.offset(from: s.contentStorage.documentRange.location, to: f.rangeInElement.location)
                    let lineStart = line.characterRange.location
                    result = fragmentStart + lineStart
                }
            }
            if result == 0 {
                result = s.contentStorage.offset(from: s.contentStorage.documentRange.location, to: f.rangeInElement.location)
            }
        }
        return result
    }
    func scrollToCharOffset(_ o: Int, animated: Bool, isEnd: Bool = false) {
        if isEnd {
            let y = max(0, currentContentView.frame.maxY - scrollView.bounds.height)
            scrollView.setContentOffset(CGPoint(x: 0, y: y), animated: animated)
            return
        }
        
        if let yInContent = getYOffsetForCharOffset(o) {
            let absY = yInContent + currentContentView.frame.minY
            let vH = scrollView.bounds.height
            // 目标 Y 坐标计算：确保 yInContent 刚好位于 contentTopPadding 处 (safeAreaTop + 10)
            let targetY = max(0, absY - contentTopPadding)
            scrollView.setContentOffset(CGPoint(x: 0, y: min(targetY, max(0, scrollView.contentSize.height - vH))), animated: animated)
        } else {
            let index = paragraphStarts.lastIndex(where: { $0 <= o }) ?? 0
            scrollToSentence(index: index, animated: animated)
        }
    }

    func setHighlight(index: Int?, secondaryIndices: Set<Int>, isPlaying: Bool, highlightRange: NSRange?) {
        if lastHighlightIndex == index && lastSecondaryIndices == secondaryIndices && isPlaying == isPlayingHighlight { return }
        lastHighlightIndex = index
        lastSecondaryIndices = secondaryIndices
        currentContentView.update(renderStore: renderStore, highlightIndex: index, secondaryIndices: secondaryIndices, isPlaying: isPlaying, highlightRange: highlightRange, paragraphStarts: paragraphStarts, margin: lastMargin, forceRedraw: true)
    }
    
    private var isPlayingHighlight: Bool {
        return currentContentView.isPlayingHighlight
    }
    
    private func setupSwitchHint() {
        switchHintLabel.alpha = 0
        switchHintLabel.textAlignment = .center
        switchHintLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        switchHintLabel.textColor = .secondaryLabel
        switchHintLabel.backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.9)
        switchHintLabel.layer.cornerRadius = ReaderConstants.Highlight.switchHintCornerRadius
        switchHintLabel.layer.masksToBounds = true
        view.addSubview(switchHintLabel)
    }

    private func updateSwitchHint(text: String, isTop: Bool) {
        if switchHintLabel.text != "  \(text)  " {
            switchHintLabel.text = "  \(text)  "
            switchHintLabel.sizeToFit()
            let width = min(view.bounds.width - ReaderConstants.Interaction.switchHintHorizontalPadding, max(ReaderConstants.Interaction.switchHintWidthMin, switchHintLabel.bounds.width))
            let bottomSafe = max(0, view.safeAreaInsets.bottom)
            let newFrame = CGRect(
                x: (view.bounds.width - width) / 2,
                y: isTop ? (safeAreaTop + ReaderConstants.Interaction.switchHintTopPadding) : (view.bounds.height - bottomSafe - ReaderConstants.Interaction.switchHintBottomPadding),
                width: width,
                height: 24
            )
            if switchHintLabel.frame != newFrame {
                switchHintLabel.frame = newFrame
            }
        }
        
        if switchHintLabel.alpha == 0 {
            UIView.animate(withDuration: ReaderConstants.Interaction.switchHintAnimation) { self.switchHintLabel.alpha = 1 }
        }
    }

    private func hideSwitchHint() {
        guard switchHintLabel.alpha > 0 else { return }
        isShowingSwitchResultHint = false
        UIView.animate(withDuration: ReaderConstants.Interaction.switchHintAnimation) { self.switchHintLabel.alpha = 0 }
    }

    private func checkSeamlessSwitchAfterContentUpdate() {
        let rawOffset = scrollView.contentOffset.y
        seamlessSwitchCoordinator.handleContentUpdate(rawOffset: rawOffset)
        if pendingSeamlessSwitch != 0 { executeSeamlessSwitchIfNeeded() }
    }

    func handleHoldSwitchIfNeeded(rawOffset: CGFloat) {
        guard !isInfiniteScrollEnabled, scrollView.isDragging, !isChapterSwitching else {
            if isInfiniteScrollEnabled && !isShowingSwitchResultHint { hideSwitchHint() }
            return
        }
        
        let inset = scrollView.adjustedContentInset
        let contentHeight = scrollView.contentSize.height
        let viewportHeight = scrollView.bounds.height
        let maxScrollY = max(-inset.top, contentHeight - viewportHeight + inset.bottom)
        
        let topPullDistance = -(rawOffset + inset.top)
        let bottomPullDistance = rawOffset - maxScrollY

        if topPullDistance > 5 {
            if topPullDistance > threshold {
                if !switchReady { 
                    switchReady = true; pendingSwitchDirection = -1; hapticFeedback() 
                }
                updateSwitchHint(text: "松开切换上一章", isTop: true)
            } else {
                if switchReady { switchReady = false }
                updateSwitchHint(text: "下拉切换上一章", isTop: true)
            }
        } else if bottomPullDistance > 5 {
            if bottomPullDistance > threshold {
                if !switchReady { 
                    switchReady = true; pendingSwitchDirection = 1; hapticFeedback() 
                }
                updateSwitchHint(text: "松开切换下一章", isTop: false)
            } else {
                if switchReady { switchReady = false }
                updateSwitchHint(text: "上拉切换下一章", isTop: false)
            }
        } else {
            // 回到正常区域，必须清除所有状态
            cancelSwitchHold()
        }
    }
    
    private func hapticFeedback() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    func cancelSwitchHold() {
        switchWorkItem?.cancel()
        switchWorkItem = nil
        hintWorkItem?.cancel()
        hintWorkItem = nil
        pendingSwitchDirection = 0
        switchReady = false
        isShowingSwitchResultHint = false
        hideSwitchHint()
    }

    func applyScrollBehaviorIfNeeded() {
        if lastInfiniteSetting == isInfiniteScrollEnabled { return }
        lastInfiniteSetting = isInfiniteScrollEnabled
        scrollView.bounces = true
        if isInfiniteScrollEnabled {
            cancelSwitchHold()
        }
    }
    
    private func showSwitchResultHint(direction: Int) {
        hintWorkItem?.cancel()
        isShowingSwitchResultHint = true
        let isTop = direction < 0
        updateSwitchHint(text: direction > 0 ? "已切换下一章" : "已切换上一章", isTop: isTop)
        let work = DispatchWorkItem { [weak self] in
            self?.hideSwitchHint()
        }
        hintWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: work)
    }
}

class VerticalTextContentView: UIView {
    private var renderStore: TextKit2RenderStore?; private var highlightIndex: Int?; private var secondaryIndices: Set<Int> = []; private(set) var isPlayingHighlight: Bool = false; private var highlightRange: NSRange?; private var paragraphStarts: [Int] = []; private var margin: CGFloat = 20
    override init(frame: CGRect) { super.init(frame: frame); self.backgroundColor = .clear }
    required init?(coder: NSCoder) { fatalError() }
    func update(renderStore: TextKit2RenderStore?, highlightIndex: Int?, secondaryIndices: Set<Int>, isPlaying: Bool, highlightRange: NSRange?, paragraphStarts: [Int], margin: CGFloat, forceRedraw: Bool) {
        self.renderStore = renderStore; self.highlightIndex = highlightIndex; self.secondaryIndices = secondaryIndices; self.isPlayingHighlight = isPlaying; self.highlightRange = highlightRange; self.paragraphStarts = paragraphStarts; self.margin = margin
        if forceRedraw { setNeedsDisplay() }
    }
    override func draw(_ rect: CGRect) {
        guard let s = renderStore else { return }; let ctx = UIGraphicsGetCurrentContext()
        if isPlayingHighlight {
            ctx?.saveGState()
            if let range = highlightRange {
                drawHighlight(range: range, store: s, context: ctx, color: UIColor.systemBlue.withAlphaComponent(ReaderConstants.Highlight.primaryAlpha))
            } else {
                for i in ([highlightIndex].compactMap{$0} + Array(secondaryIndices)) {
                    guard i < paragraphStarts.count else { continue }
                    let start = paragraphStarts[i]
                    let end = (i + 1 < paragraphStarts.count) ? paragraphStarts[i + 1] : s.attributedString.length
                    let r = NSRange(location: start, length: max(0, end - start))
                    let color = (i == highlightIndex) ? UIColor.systemBlue.withAlphaComponent(ReaderConstants.Highlight.primaryAlpha) : UIColor.systemGreen.withAlphaComponent(ReaderConstants.Highlight.secondaryAlpha)
                    drawHighlight(range: r, store: s, context: ctx, color: color)
                }
            }
            ctx?.restoreGState()
        }
        ctx?.saveGState()
        guard let context = ctx else { return }
        let sL = s.layoutManager.textLayoutFragment(for: CGPoint(x: 0, y: rect.minY))?.rangeInElement.location ?? s.contentStorage.documentRange.location
        s.layoutManager.enumerateTextLayoutFragments(from: sL, options: [.ensuresLayout]) { f in
            if f.layoutFragmentFrame.minY > rect.maxY { return false }
            if f.layoutFragmentFrame.maxY >= rect.minY { f.draw(at: f.layoutFragmentFrame.origin, in: context) }
            return true
        }
        ctx?.restoreGState()
    }

    private func drawHighlight(range: NSRange, store: TextKit2RenderStore, context: CGContext?, color: UIColor) {
        guard let ctx = context else { return }
        ctx.setFillColor(color.cgColor)
        if let startLoc = store.contentStorage.location(store.contentStorage.documentRange.location, offsetBy: range.location) {
            store.layoutManager.enumerateTextLayoutFragments(from: startLoc, options: [.ensuresLayout]) { f in
                if store.contentStorage.offset(from: store.contentStorage.documentRange.location, to: f.rangeInElement.location) >= NSMaxRange(range) { return false }
                for line in f.textLineFragments {
                    let lr = line.typographicBounds.offsetBy(dx: f.layoutFragmentFrame.origin.x, dy: f.layoutFragmentFrame.origin.y)
                    ctx.addPath(UIBezierPath(roundedRect: lr.insetBy(dx: ReaderConstants.Pagination.highlightInsetX, dy: ReaderConstants.Pagination.highlightInsetY), cornerRadius: ReaderConstants.Highlight.cornerRadius).cgPath)
                    ctx.fillPath()
                }
                return true
            }
        }
    }
}
