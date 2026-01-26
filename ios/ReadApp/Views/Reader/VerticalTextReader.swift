import SwiftUI
import UIKit

// MARK: - SwiftUI 桥接组件
struct VerticalTextReader: UIViewControllerRepresentable {
    let sentences: [String]; let fontSize: CGFloat; let lineSpacing: CGFloat; let horizontalMargin: CGFloat; let highlightIndex: Int?; let secondaryIndices: Set<Int>; let isPlayingHighlight: Bool; let chapterUrl: String?
    let title: String?; let nextTitle: String?; let prevTitle: String?
    let verticalThreshold: CGFloat
    let verticalDampingFactor: CGFloat
    @Binding var currentVisibleIndex: Int; @Binding var pendingScrollIndex: Int?
    var forceScrollToTop: Bool = false; var onScrollFinished: (() -> Void)?; var onAddReplaceRule: ((String) -> Void)?; var onTapMenu: (() -> Void)?
    var safeAreaTop: CGFloat = 0
    
    // 无限流扩展
    var nextChapterSentences: [String]?
    var prevChapterSentences: [String]?
    var onReachedBottom: (() -> Void)? // 触发预载
    var onReachedTop: (() -> Void)? // 触发上一章预载
    var onChapterSwitched: ((Int) -> Void)? // 0: 本章, 1: 下一章
    var onInteractionChanged: ((Bool) -> Void)?
    
    func makeUIViewController(context: Context) -> VerticalTextViewController {
        let vc = VerticalTextViewController(); vc.onVisibleIndexChanged = { i in DispatchQueue.main.async { if currentVisibleIndex != i { currentVisibleIndex = i } } }; vc.onAddReplaceRule = onAddReplaceRule; vc.onTapMenu = onTapMenu; return vc
    }
    
    func updateUIViewController(_ vc: VerticalTextViewController, context: Context) {
        vc.onAddReplaceRule = onAddReplaceRule; vc.onTapMenu = onTapMenu; vc.safeAreaTop = safeAreaTop
        vc.onReachedBottom = onReachedBottom; vc.onReachedTop = onReachedTop; vc.onChapterSwitched = onChapterSwitched
        vc.onInteractionChanged = onInteractionChanged
        vc.threshold = verticalThreshold
        vc.dampingFactor = verticalDampingFactor
        
        let changed = vc.update(sentences: sentences, nextSentences: nextChapterSentences, prevSentences: prevChapterSentences, title: title, nextTitle: nextTitle, prevTitle: prevTitle, fontSize: fontSize, lineSpacing: lineSpacing, margin: horizontalMargin, highlightIndex: highlightIndex, secondaryIndices: secondaryIndices, isPlaying: isPlayingHighlight)
        
        if forceScrollToTop {
            vc.scrollToTop(animated: false); DispatchQueue.main.async { onScrollFinished?() }
        } else if let sI = pendingScrollIndex {
            if changed { DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { vc.scrollToSentence(index: sI, animated: false) } } 
            else { vc.scrollToSentence(index: sI, animated: true) }; DispatchQueue.main.async { self.pendingScrollIndex = nil }
        } else if isPlayingHighlight, let hI = highlightIndex {
            // 这里不再调用整体 update 而是确保可见
            vc.ensureSentenceVisible(index: hI)
        }
    }
}

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
    private var suppressAutoSwitchUntil: TimeInterval = 0
    private var dragStartTime: TimeInterval = 0
    var dampingFactor: CGFloat = 0.12
    private let chapterGap: CGFloat = 80
    private var lastInfiniteSetting: Bool?

    var onVisibleIndexChanged: ((Int) -> Void)?; var onAddReplaceRule: ((String) -> Void)?; var onTapMenu: (() -> Void)?
    var onReachedBottom: (() -> Void)?; var onReachedTop: (() -> Void)?; var onChapterSwitched: ((Int) -> Void)?
    var onInteractionChanged: ((Bool) -> Void)?
    var safeAreaTop: CGFloat = 0; var chapterUrl: String?
    private struct CharDetectionConfig {
        static let minHorizontalInset: CGFloat = 10
        static let minVerticalOffset: CGFloat = 2 
        static let maxVerticalOffset: CGFloat = 12
    }
    private let viewportTopMargin: CGFloat = 15 // 统一调整为 15，与水平模式对齐
    private var contentTopPadding: CGFloat { safeAreaTop + viewportTopMargin }
    private var horizontalMarginForDetection: CGFloat {
        max(CharDetectionConfig.minHorizontalInset, lastMargin)
    }
    private var verticalDetectionOffset: CGFloat {
        let spacingDriven = lastLineSpacing > 0 ? lastLineSpacing * 0.35 : CharDetectionConfig.minVerticalOffset
        return min(CharDetectionConfig.maxVerticalOffset, max(CharDetectionConfig.minVerticalOffset, spacingDriven))
    }
    var threshold: CGFloat = 80
    var seamlessSwitchThreshold: CGFloat = 120
    
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
    private var estimatedLineHeight: CGFloat = 30 // 新增：估算行高用于滚动时机判定

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
        
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tap.delegate = self
        scrollView.addGestureRecognizer(tap)
        
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress))
        longPress.minimumPressDuration = 0.8
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

    @objc private func handleTap() {
        pendingSeamlessSwitch = 0
        suppressAutoSwitchUntil = Date().timeIntervalSince1970 + 0.6
        cancelSwitchHold()
        onTapMenu?()
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
    func update(sentences: [String], nextSentences: [String]?, prevSentences: [String]?, title: String?, nextTitle: String?, prevTitle: String?, fontSize: CGFloat, lineSpacing: CGFloat, margin: CGFloat, highlightIndex: Int?, secondaryIndices: Set<Int>, isPlaying: Bool) -> Bool {
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
        
        if contentChanged || renderStore == nil {
            self.previousContentHeight = currentContentView.frame.height
            self.currentSentences = trimmedSentences; self.lastFontSize = fontSize; self.lastLineSpacing = lineSpacing; isUpdatingLayout = true
            
            let titleText = title != nil && !title!.isEmpty ? title! + "\n" : ""
            let titleLen = titleText.utf16.count
            var pS: [Int] = []; var cP = titleLen
            for (idx, s) in trimmedSentences.enumerated() { 
                pS.append(cP)
                cP += (s.utf16.count + 2) 
                if idx < trimmedSentences.count - 1 { cP += 1 } 
            }; paragraphStarts = pS
            
            let attr = createAttr(trimmedSentences, title: title, fontSize: fontSize, lineSpacing: lineSpacing)
            if let s = renderStore { s.update(attributedString: attr, layoutWidth: max(100, (viewIfLoaded?.bounds.width ?? 375) - margin * 2)) } 
            else { renderStore = TextKit2RenderStore(attributedString: attr, layoutWidth: max(100, (viewIfLoaded?.bounds.width ?? 375) - margin * 2)) }
            calculateSentenceOffsets(); isUpdatingLayout = false
            currentContentView.update(renderStore: renderStore, highlightIndex: highlightIndex, secondaryIndices: secondaryIndices, isPlaying: isPlaying, highlightRange: nil, paragraphStarts: paragraphStarts, margin: margin, forceRedraw: true)
            layoutNeeded = true
        }
        
        if nextChanged {
            self.nextSentences = trimmedNextSentences
            if trimmedNextSentences.isEmpty {
                nextRenderStore = nil
                nextContentView.isHidden = true
            } else {
                let attr = createAttr(trimmedNextSentences, title: nextTitle, fontSize: fontSize, lineSpacing: lineSpacing)
                if let s = nextRenderStore { s.update(attributedString: attr, layoutWidth: max(100, view.bounds.width - margin * 2)) } 
                else { nextRenderStore = TextKit2RenderStore(attributedString: attr, layoutWidth: max(100, view.bounds.width - margin * 2)) }
                nextContentView.update(renderStore: nextRenderStore, highlightIndex: nil, secondaryIndices: [], isPlaying: false, highlightRange: nil, paragraphStarts: [], margin: margin, forceRedraw: true)
            }
            layoutNeeded = true
        }
        
        if prevChanged {
            self.prevSentences = trimmedPrevSentences
            if trimmedPrevSentences.isEmpty {
                prevRenderStore = nil
                prevContentView.isHidden = true
            } else {
                let attr = createAttr(trimmedPrevSentences, title: prevTitle, fontSize: fontSize, lineSpacing: lineSpacing)
                if let s = prevRenderStore { s.update(attributedString: attr, layoutWidth: max(100, view.bounds.width - margin * 2)) } 
                else { prevRenderStore = TextKit2RenderStore(attributedString: attr, layoutWidth: max(100, view.bounds.width - margin * 2)) }
                prevContentView.update(renderStore: prevRenderStore, highlightIndex: nil, secondaryIndices: [], isPlaying: false, highlightRange: nil, paragraphStarts: [], margin: margin, forceRedraw: true)
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
            p.paragraphSpacing = fontSize * 1.5
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
            scrollView.contentSize = CGSize(width: view.bounds.width, height: totalH + 100)
        } else {
            // 非无限流：ContentSize 仅为当前章
            currentContentView.frame = CGRect(x: m, y: topPadding, width: s.layoutWidth, height: h1)
            // 关键优化：增加 100px 底部余量，确保最后一章节的末尾也能滚到探测点
            scrollView.contentSize = CGSize(width: view.bounds.width, height: topPadding + h1 + 100)
            
            // 预览内容放置在 100px 间距外
            if let ps = prevRenderStore {
                var h0: CGFloat = 0
                ps.layoutManager.enumerateTextLayoutFragments(from: ps.contentStorage.documentRange.endLocation, options: [.reverse, .ensuresLayout]) { f in h0 = f.layoutFragmentFrame.maxY; return false }
                prevContentView.isHidden = false
                prevContentView.frame = CGRect(x: m, y: topPadding - h0 - 100, width: ps.layoutWidth, height: h0)
            } else { prevContentView.isHidden = true }
            
            if let ns = nextRenderStore {
                var h2: CGFloat = 0
                ns.layoutManager.enumerateTextLayoutFragments(from: ns.contentStorage.documentRange.endLocation, options: [.ensuresLayout]) { f in h2 = f.layoutFragmentFrame.maxY; return false }
                nextContentView.isHidden = false
                nextContentView.frame = CGRect(x: m, y: topPadding + h1 + 100, width: ns.layoutWidth, height: h2)
            } else { nextContentView.isHidden = true }
            lastPrevHasContent = false
        }
    }

    func scrollViewDidScroll(_ s: UIScrollView) {
        if isUpdatingLayout { return }
        let rawOffset = s.contentOffset.y
        let y = s.contentOffset.y - contentTopPadding
        
        if isInfiniteScrollEnabled { handleAutoSwitchIfNeeded(rawOffset: rawOffset) }
        handleHoldSwitchIfNeeded(rawOffset: rawOffset)
        
        // 当关闭无限流时，应用视觉阻尼
        if !isInfiniteScrollEnabled {
            let actualMaxScrollY = max(-safeAreaTop, scrollView.contentSize.height - scrollView.bounds.height)
            let currentScale = scrollView.zoomScale
            
            if rawOffset < -safeAreaTop {
                let diff = -safeAreaTop - rawOffset
                let ty = (diff * dampingFactor) / currentScale
                currentContentView.transform = CGAffineTransform(scaleX: currentScale, y: currentScale).translatedBy(x: 0, y: ty)
            } else if rawOffset > actualMaxScrollY {
                let diff = rawOffset - actualMaxScrollY
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
            if s.contentOffset.y > s.contentSize.height - s.bounds.height * 1.5 { onReachedBottom?() }
            if s.contentOffset.y < s.bounds.height * 0.6 { onReachedTop?() }
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
            if switchReady && pendingSwitchDirection != 0 && !isTransitioning {
                let direction = pendingSwitchDirection
                isTransitioning = true
                scrollView.isUserInteractionEnabled = false
                
                // 停止当前的滚动速度，防止回弹干扰转场
                scrollView.setContentOffset(scrollView.contentOffset, animated: false)
                
                UIView.animate(withDuration: 0.2, animations: { 
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
        let clampedO = max(0, min(o, totalLen > 0 ? totalLen - 1 : 0))
        
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
                let threshold = isFirstSentence ? 2.0 : (estimatedLineHeight * 0.3)
                
                if abs(currentReadingYRelativeToViewport) > threshold {
                    let targetY = max(0, absY - contentTopPadding)
                    isAutoScrolling = true
                    // 如果偏离巨大，说明是刚换章或者用户跳进度了，用非动画形式先跳过去，再由 sync 维持平滑
                    let shouldAnimate = abs(currentReadingYRelativeToViewport) < vH * 0.5
                    scrollView.setContentOffset(CGPoint(x: 0, y: min(targetY, max(0, scrollView.contentSize.height - scrollView.bounds.height))), animated: shouldAnimate)
                    if !shouldAnimate {
                        isAutoScrolling = false
                    }
                }
                return
            }
        }
    }

    private func getYOffsetForCharOffsetInStore(_ s: TextKit2RenderStore, offset: Int) -> CGFloat? {
        let totalLen = s.attributedString.length
        let clampedO = max(0, min(offset, totalLen > 0 ? totalLen - 1 : 0))
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
        return (startY <= cur + vH + 50) && (endY >= cur - 50)
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
        
        let detectionOffset = max(2.0, lastFontSize * 0.2)
        let globalY = scrollView.contentOffset.y + contentTopPadding + detectionOffset
        let localY = globalY - currentContentView.frame.minY
        
        // 边界保护：如果在当前章节视图上方 50pt 以上，说明视觉中心还在上一章，返回 -1 标识不要重定位
        if localY < -50 {
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
        switchHintLabel.layer.cornerRadius = 12
        switchHintLabel.layer.masksToBounds = true
        view.addSubview(switchHintLabel)
    }

    private func updateSwitchHint(text: String, isTop: Bool) {
        if switchHintLabel.text != "  \(text)  " {
            switchHintLabel.text = "  \(text)  "
            switchHintLabel.sizeToFit()
            let width = min(view.bounds.width - 40, max(120, switchHintLabel.bounds.width))
            let bottomSafe = max(0, view.safeAreaInsets.bottom)
            let newFrame = CGRect(
                x: (view.bounds.width - width) / 2,
                y: isTop ? (safeAreaTop + 12) : (view.bounds.height - bottomSafe - 36),
                width: width,
                height: 24
            )
            if switchHintLabel.frame != newFrame {
                switchHintLabel.frame = newFrame
            }
        }
        
        if switchHintLabel.alpha == 0 {
            UIView.animate(withDuration: 0.2) { self.switchHintLabel.alpha = 1 }
        }
    }

    private func hideSwitchHint() {
        guard switchHintLabel.alpha > 0 else { return }
        isShowingSwitchResultHint = false
        UIView.animate(withDuration: 0.2) { self.switchHintLabel.alpha = 0 }
    }

    private func handleAutoSwitchIfNeeded(rawOffset: CGFloat) {
        if Date().timeIntervalSince1970 < suppressAutoSwitchUntil { return }
        if pendingSeamlessSwitch != 0 { return }
        
        // 只有当旧章节已经完全滚出视野，且接缝处在屏幕上方一定距离外时，才标记切换
        // 这样可以确保切换时，用户眼中只有新章节的内容，增加稳定性
        
        if let _ = nextRenderStore {
            let maxOffsetY = max(0, scrollView.contentSize.height - scrollView.bounds.height)
            let triggerThreshold = max(40, seamlessSwitchThreshold)
            if rawOffset > maxOffsetY - triggerThreshold {
                pendingSeamlessSwitch = 1
                return
            }
        }
        
        if let _ = prevRenderStore {
            // 当前章节顶部坐标
            let currentTopY = currentContentView.frame.minY
            // 如果当前章节顶部已经滚出屏幕下方 100 像素
            if rawOffset + scrollView.bounds.height < currentTopY - 100 {
                pendingSeamlessSwitch = -1
            }
        }
    }

    private func checkSeamlessSwitchAfterContentUpdate() {
        guard isInfiniteScrollEnabled, pendingSeamlessSwitch == 0 else { return }
        let rawOffset = scrollView.contentOffset.y

        if nextRenderStore != nil {
            let currentBottomY = currentContentView.frame.maxY
            if rawOffset > currentBottomY + 100 {
                pendingSeamlessSwitch = 1
            }
        }

        if pendingSeamlessSwitch == 0, prevRenderStore != nil {
            let currentTopY = currentContentView.frame.minY
            if rawOffset + scrollView.bounds.height < currentTopY - 100 {
                pendingSeamlessSwitch = -1
            }
        }

        if pendingSeamlessSwitch != 0 {
            executeSeamlessSwitchIfNeeded()
        }
    }

    func handleHoldSwitchIfNeeded(rawOffset: CGFloat) {
        guard !isInfiniteScrollEnabled, scrollView.isDragging else {
            if isInfiniteScrollEnabled && !isShowingSwitchResultHint { hideSwitchHint() }
            return
        }
        
        let actualMaxScrollY = max(0, scrollView.contentSize.height - scrollView.bounds.height)

        if rawOffset < -5 {
            let pullDistance = -rawOffset
            if pullDistance > threshold {
                if !switchReady { 
                    switchReady = true; pendingSwitchDirection = -1; hapticFeedback() 
                }
                updateSwitchHint(text: "松开切换上一章", isTop: true)
            } else {
                // 如果已经 Ready，只要不缩回 10pt 以内就保持 Ready，增加稳定性
                if pullDistance < 10 { switchReady = false }
                if !switchReady {
                    updateSwitchHint(text: "下拉切换上一章", isTop: true)
                } else {
                    updateSwitchHint(text: "松开切换上一章", isTop: true)
                }
            }
        } else if rawOffset > actualMaxScrollY + 5 {
            let pullDistance = rawOffset - actualMaxScrollY
            if pullDistance > threshold {
                if !switchReady { 
                    switchReady = true; pendingSwitchDirection = 1; hapticFeedback() 
                }
                updateSwitchHint(text: "松开切换下一章", isTop: false)
            } else {
                if pullDistance < 10 { switchReady = false }
                if !switchReady {
                    updateSwitchHint(text: "上拉切换下一章", isTop: false)
                } else {
                    updateSwitchHint(text: "松开切换下一章", isTop: false)
                }
            }
        } else {
            if !switchReady && rawOffset > -2 && rawOffset < actualMaxScrollY + 2 { hideSwitchHint() }
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
                drawHighlight(range: range, store: s, context: ctx, color: UIColor.systemBlue.withAlphaComponent(0.12))
            } else {
                for i in ([highlightIndex].compactMap{$0} + Array(secondaryIndices)) {
                    guard i < paragraphStarts.count else { continue }
                    let start = paragraphStarts[i]
                    let end = (i + 1 < paragraphStarts.count) ? paragraphStarts[i + 1] : s.attributedString.length
                    let r = NSRange(location: start, length: max(0, end - start))
                    let color = (i == highlightIndex) ? UIColor.systemBlue.withAlphaComponent(0.12) : UIColor.systemGreen.withAlphaComponent(0.06)
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
                    ctx.addPath(UIBezierPath(roundedRect: lr.insetBy(dx: -2, dy: -1), cornerRadius: 4).cgPath)
                    ctx.fillPath()
                }
                return true
            }
        }
    }
}

// MARK: - Manga Reader Controller
class MangaReaderViewController: UIViewController, UIScrollViewDelegate {
    let scrollView = UIScrollView()
    let stackView = UIStackView()
    private let switchHintLabel = UILabel()
    private var lastViewSize: CGSize = .zero
    private var pendingSwitchDirection: Int = 0
    private var switchReady = false
    private var switchWorkItem: DispatchWorkItem?
    private let switchHoldDuration: TimeInterval = 0.6
    var dampingFactor: CGFloat = 0.2
    
    var onChapterSwitched: ((Int) -> Void)?
    var onToggleMenu: (() -> Void)?
    var onInteractionChanged: ((Bool) -> Void)?
    var onVisibleIndexChanged: ((Int) -> Void)?
    var safeAreaTop: CGFloat = 0
    var threshold: CGFloat = 80
    var maxZoomScale: CGFloat = 3.0
    var progressFontSize: CGFloat = 12 {
        didSet {
            progressLabel.font = .monospacedDigitSystemFont(ofSize: progressFontSize, weight: .regular)
        }
    }
    var currentVisibleIndex: Int = 0
    var pendingScrollIndex: Int?
    var bookUrl: String?
    var chapterIndex: Int = 0
    var chapterUrl: String?
    private var imageUrls: [String] = []
    
    private lazy var progressOverlayView: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        // 关键：回归到您认为有效的 exclusionBlendMode
        view.layer.compositingFilter = "exclusionBlendMode"
        view.layer.shouldRasterize = true
        view.layer.rasterizationScale = UIScreen.main.scale
        return view
    }()
    
    let progressLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        scrollView.delegate = self
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.alwaysBounceVertical = true
        scrollView.contentInset = UIEdgeInsets(top: safeAreaTop, left: 0, bottom: 100, right: 0)
        scrollView.maximumZoomScale = maxZoomScale
        scrollView.minimumZoomScale = 1.0
        view.addSubview(scrollView)
        
        stackView.axis = .vertical
        stackView.spacing = 0
        stackView.alignment = .fill
        scrollView.addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stackView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])
        
        setupSwitchHint()
        setupProgressLabel()
        
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        scrollView.addGestureRecognizer(tap)
    }
    
    private func setupProgressLabel() {
        view.addSubview(progressOverlayView)
        progressOverlayView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            progressOverlayView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            progressOverlayView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -4),
            progressOverlayView.widthAnchor.constraint(greaterThanOrEqualToConstant: 40),
            progressOverlayView.heightAnchor.constraint(equalToConstant: 20)
        ])
        
        progressLabel.font = .monospacedDigitSystemFont(ofSize: progressFontSize, weight: .regular)
        progressLabel.textColor = .white
        progressLabel.backgroundColor = .clear
        progressOverlayView.addSubview(progressLabel)
        progressLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            progressLabel.trailingAnchor.constraint(equalTo: progressOverlayView.trailingAnchor),
            progressLabel.bottomAnchor.constraint(equalTo: progressOverlayView.bottomAnchor)
        ])
    }
    
    override func viewDidLayoutSubviews() {
        let oldContentHeight = scrollView.contentSize.height
        let oldOffset = scrollView.contentOffset.y + safeAreaTop
        
        super.viewDidLayoutSubviews()
        
        if view.bounds.size != lastViewSize {
            let wasAtBottom = oldContentHeight > 0 && oldOffset >= (oldContentHeight - scrollView.bounds.height - 10)
            let relativeProgress = oldContentHeight > 0 ? (oldOffset / oldContentHeight) : 0
            
            lastViewSize = view.bounds.size
            scrollView.frame = view.bounds
            scrollView.contentInset = UIEdgeInsets(top: safeAreaTop, left: 0, bottom: 100, right: 0)
            
            // 旋转后恢复位置
            if oldContentHeight > 0 {
                self.view.layoutIfNeeded()
                if wasAtBottom {
                    self.scrollToBottom(animated: false)
                } else {
                    let newTargetY = (scrollView.contentSize.height * relativeProgress) - safeAreaTop
                    scrollView.setContentOffset(CGPoint(x: 0, y: newTargetY), animated: false)
                }
            }
        }
    }
    
    @objc private func handleTap() { onToggleMenu?() }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return stackView
    }

    func update(urls: [String]) {
        guard urls != self.imageUrls else { return }
        self.imageUrls = urls
        
        // 关键优化：先收集现有视图以便复用或平滑过渡（可选），这里简单处理为先准备好所有图片
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        
        for (index, urlStr) in urls.enumerated() {
            let iv = UIImageView()
            iv.contentMode = .scaleAspectFit
            iv.clipsToBounds = true
            iv.backgroundColor = UIColor.white.withAlphaComponent(0.05)
            stackView.addArrangedSubview(iv)
            
            let urlStr2 = urlStr.replacingOccurrences(of: "__IMG__", with: "").trimmingCharacters(in: .whitespaces)
            guard let resolved = MangaImageService.shared.resolveImageURL(urlStr2) else { continue }
            let absolute = resolved.absoluteString
            
            // 尝试同步加载本地缓存，减少闪烁
            if let b = bookUrl,
               let cachedData = LocalCacheManager.shared.loadMangaImage(bookUrl: b, chapterIndex: chapterIndex, imageURL: absolute),
               let image = UIImage(data: cachedData) {
                iv.image = image
                let ratio = image.size.height / image.size.width
                iv.heightAnchor.constraint(equalTo: iv.widthAnchor, multiplier: ratio).isActive = true
                if self.pendingScrollIndex == index {
                    self.scrollToIndex(index, animated: false)
                }
                continue
            }
            
            // 缓存未命中，异步下载
            Task {
                if let data = await MangaImageService.shared.fetchImageData(for: resolved, referer: chapterUrl), let image = UIImage(data: data) {
                    if let b = bookUrl, UserPreferences.shared.isMangaAutoCacheEnabled {
                        LocalCacheManager.shared.saveMangaImage(bookUrl: b, chapterIndex: chapterIndex, imageURL: absolute, data: data)
                    }
                    await MainActor.run {
                        // 确保视图没被复用或删除
                        guard iv.superview == self.stackView else { return }
                        iv.image = image
                        let ratio = image.size.height / image.size.width
                        // 移除可能存在的占位高度（如果有的话，目前是靠 intrinsic size 或 0）
                        iv.heightAnchor.constraint(equalTo: iv.widthAnchor, multiplier: ratio).isActive = true
                        if self.pendingScrollIndex == index {
                            self.scrollToIndex(index, animated: false)
                        }
                    }
                }
            }
        }
    }

    func scrollToIndex(_ index: Int, animated: Bool = false) {
        self.pendingScrollIndex = index
        guard index >= 0, index < stackView.arrangedSubviews.count else { return }
        
        let targetView = stackView.arrangedSubviews[index]
        // 只有当高度大于 0 时才认为布局完成
        if targetView.frame.height > 0 {
            self.view.layoutIfNeeded()
            let targetY = targetView.frame.origin.y - safeAreaTop
            scrollView.setContentOffset(CGPoint(x: 0, y: targetY), animated: animated)
            self.pendingScrollIndex = nil // 完成后清除
        }
    }
    
    func scrollToBottom(animated: Bool = false) {
        self.view.layoutIfNeeded()
        let bottomOffset = CGPoint(x: 0, y: max(-safeAreaTop, scrollView.contentSize.height - scrollView.bounds.height))
        scrollView.setContentOffset(bottomOffset, animated: animated)
    }

    func scrollViewDidScroll(_ s: UIScrollView) {
        let rawOffset = s.contentOffset.y
        handleHoldSwitchIfNeeded(rawOffset: rawOffset)
        
        let actualMaxScrollY = max(-safeAreaTop, stackView.frame.height - scrollView.bounds.height)
        let currentScale = s.zoomScale
        
        // 按 Y 轴比例计算平滑进度
        let offset = rawOffset + safeAreaTop
        let maxOffset = stackView.frame.height - s.bounds.height
        if maxOffset > 0 {
            let percent = Int(round(min(1.0, max(0.0, offset / maxOffset)) * 100))
            progressLabel.text = "\(min(100, percent))%"
        } else {
            progressLabel.text = "0%"
        }
        
        if rawOffset < -safeAreaTop {
            let diff = -safeAreaTop - rawOffset
            let ty = (diff * dampingFactor) / currentScale
            stackView.transform = CGAffineTransform(scaleX: currentScale, y: currentScale).translatedBy(x: 0, y: ty)
        } else if rawOffset > actualMaxScrollY {
            let diff = rawOffset - actualMaxScrollY
            let ty = (-diff * dampingFactor) / currentScale
            stackView.transform = CGAffineTransform(scaleX: currentScale, y: currentScale).translatedBy(x: 0, y: ty)
        } else {
            // 正常区域，确保清除位移但保留缩放
            if stackView.transform.ty != 0 || stackView.transform.a != currentScale {
                stackView.transform = CGAffineTransform(scaleX: currentScale, y: currentScale)
            }
        }
        
        // 计算当前可见的图片索引
        let visibleY = rawOffset + safeAreaTop
        var found = false
        for (index, view) in stackView.arrangedSubviews.enumerated() {
            if view.frame.maxY > visibleY {
                if currentVisibleIndex != index {
                    currentVisibleIndex = index
                    onVisibleIndexChanged?(index)
                }
                found = true
                break
            }
        }
        if !found && !stackView.arrangedSubviews.isEmpty {
            let lastIdx = stackView.arrangedSubviews.count - 1
            if currentVisibleIndex != lastIdx {
                currentVisibleIndex = lastIdx
                onVisibleIndexChanged?(lastIdx)
            }
        }
    }
    
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        cancelSwitchHold()
        onInteractionChanged?(true)
    }
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if switchReady && pendingSwitchDirection != 0 {
            let direction = pendingSwitchDirection
            self.onChapterSwitched?(direction)
            self.cancelSwitchHold()
        } else {
            if !decelerate { onInteractionChanged?(false) }
            cancelSwitchHold()
        }
    }
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        cancelSwitchHold()
        onInteractionChanged?(false)
    }

    private func setupSwitchHint() {
        switchHintLabel.alpha = 0
        switchHintLabel.textAlignment = .center
        switchHintLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        switchHintLabel.textColor = .white
        switchHintLabel.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        switchHintLabel.layer.cornerRadius = 12
        switchHintLabel.layer.masksToBounds = true
        view.addSubview(switchHintLabel)
    }

    private func updateSwitchHint(text: String, isTop: Bool) {
        if switchHintLabel.text != "  \(text)  " {
            switchHintLabel.text = "  \(text)  "
            switchHintLabel.sizeToFit()
            let width = min(view.bounds.width - 40, max(120, switchHintLabel.bounds.width))
            let bottomSafe = max(0, view.safeAreaInsets.bottom)
            let newFrame = CGRect(
                x: (view.bounds.width - width) / 2,
                y: isTop ? (safeAreaTop + 12) : (view.bounds.height - bottomSafe - 36),
                width: width, height: 24
            )
            if switchHintLabel.frame != newFrame {
                switchHintLabel.frame = newFrame
            }
        }
        if switchHintLabel.alpha == 0 { UIView.animate(withDuration: 0.2) { self.switchHintLabel.alpha = 1 } }
    }

    private func hideSwitchHint() {
        guard switchHintLabel.alpha > 0 else { return }
        UIView.animate(withDuration: 0.2) { self.switchHintLabel.alpha = 0 }
    }

    private func handleHoldSwitchIfNeeded(rawOffset: CGFloat) {
        let topThreshold: CGFloat = -safeAreaTop - threshold
        
        let actualMaxScrollY = max(-safeAreaTop, stackView.frame.height - scrollView.bounds.height)
        let bottomThreshold = actualMaxScrollY + threshold
        
        if rawOffset < -safeAreaTop - 10 {
            if rawOffset < topThreshold {
                if !switchReady {
                    switchReady = true; pendingSwitchDirection = -1
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                }
                updateSwitchHint(text: "松开切换上一章", isTop: true)
            } else {
                if rawOffset > -safeAreaTop - 15 { switchReady = false }
                if !switchReady {
                    updateSwitchHint(text: "继续下拉切换上一章", isTop: true)
                } else {
                    updateSwitchHint(text: "松开切换上一章", isTop: true)
                }
            }
        } else if rawOffset > actualMaxScrollY + 10 {
            if rawOffset > bottomThreshold {
                if !switchReady {
                    switchReady = true; pendingSwitchDirection = 1
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                }
                updateSwitchHint(text: "松开切换下一章", isTop: false)
            } else {
                if rawOffset < actualMaxScrollY + 15 { switchReady = false }
                if !switchReady {
                    updateSwitchHint(text: "继续上拉切换下一章", isTop: false)
                } else {
                    updateSwitchHint(text: "松开切换下一章", isTop: false)
                }
            }
        } else {
            if !scrollView.isDragging && rawOffset >= -safeAreaTop - 5 && rawOffset <= actualMaxScrollY + 5 {
                cancelSwitchHold()
            }
        }
    }

    private func beginSwitchHold(direction: Int, isTop: Bool) {
        if pendingSwitchDirection == direction, switchWorkItem != nil { return }
        cancelSwitchHold()
        pendingSwitchDirection = direction
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, self.scrollView.isDragging else { return }
            self.switchReady = true
            self.updateSwitchHint(text: direction > 0 ? "松手切换下一章" : "松手切换上一章", isTop: isTop)
        }
        switchWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + switchHoldDuration, execute: work)
    }

    private func cancelSwitchHold() {
        switchWorkItem?.cancel(); switchWorkItem = nil
        pendingSwitchDirection = 0; switchReady = false; hideSwitchHint()
    }
}
