import SwiftUI
import UIKit

// MARK: - SwiftUI 桥接组件
struct VerticalTextReader: UIViewControllerRepresentable {
    let sentences: [String]; let fontSize: CGFloat; let lineSpacing: CGFloat; let horizontalMargin: CGFloat; let highlightIndex: Int?; let secondaryIndices: Set<Int>; let isPlayingHighlight: Bool; let chapterUrl: String?
    let title: String?; let nextTitle: String?; let prevTitle: String?
    let verticalThreshold: CGFloat
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
    private var editMenuInteraction: Any?
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
    private let dampingFactor: CGFloat = 0.12
    private let chapterGap: CGFloat = 80
    private var lastInfiniteSetting: Bool?

    var onVisibleIndexChanged: ((Int) -> Void)?; var onAddReplaceRule: ((String) -> Void)?; var onTapMenu: (() -> Void)?
    var onReachedBottom: (() -> Void)?; var onReachedTop: (() -> Void)?; var onChapterSwitched: ((Int) -> Void)?
    var onInteractionChanged: ((Bool) -> Void)?
    var safeAreaTop: CGFloat = 0; var chapterUrl: String?
    private struct CharDetectionConfig {
        static let minHorizontalInset: CGFloat = 10
        static let minVerticalOffset: CGFloat = 2 // 从 5 调低到 2，提高精度
        static let maxVerticalOffset: CGFloat = 12 // 从 18 调低到 12
    }
    private let viewportTopMargin: CGFloat = 10
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
    private var lastReportedIndex: Int = -1; private var isUpdatingLayout = false; private var lastTTSSyncIndex: Int = -1
    
    private var lastHighlightIndex: Int?; private var lastSecondaryIndices: Set<Int> = []; private var lastFontSize: CGFloat = 0; private var lastLineSpacing: CGFloat = 0; private var lastMargin: CGFloat = 20
    
    // 无感置换状态记录
    private var previousContentHeight: CGFloat = 0
    private var lastPrevContentHeight: CGFloat = 0
    private var lastPrevHasContent = false
    private var pendingSelectedText: String?
    
    // 无限流无缝切换标记 (0: 无, 1: 下一章, -1: 上一章)
    private var pendingSeamlessSwitch: Int = 0

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
        
        if #available(iOS 16.0, *) {
            let interaction = UIEditMenuInteraction(delegate: self)
            view.addInteraction(interaction)
            editMenuInteraction = interaction
        }
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
            currentContentView.update(renderStore: renderStore, highlightIndex: highlightIndex, secondaryIndices: secondaryIndices, isPlaying: isPlaying, paragraphStarts: paragraphStarts, margin: margin, forceRedraw: true)
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
                nextContentView.update(renderStore: nextRenderStore, highlightIndex: nil, secondaryIndices: [], isPlaying: false, paragraphStarts: [], margin: margin, forceRedraw: true)
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
                prevContentView.update(renderStore: prevRenderStore, highlightIndex: nil, secondaryIndices: [], isPlaying: false, paragraphStarts: [], margin: margin, forceRedraw: true)
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
                    if wasPrevVisible { scrollView.contentOffset.y = max(0, oldOffset - oldPrevHeightPlusGap) }
                } else if isChapterSwapToPrev {
                    let newPrevHeightPlusGap = lastPrevHasContent ? (lastPrevContentHeight + chapterGap) : 0
                    scrollView.contentOffset.y = oldOffset + newPrevHeightPlusGap
                } else if prevChanged && !isChapterSwapToPrev {
                    let displacement = currentContentView.frame.minY - oldCurrY
                    if displacement != 0 { scrollView.contentOffset.y = oldOffset + displacement }
                }
            }
            isUpdatingLayout = false

        }

        if lastHighlightIndex != highlightIndex || lastSecondaryIndices != secondaryIndices {
            lastHighlightIndex = highlightIndex; lastSecondaryIndices = secondaryIndices
            currentContentView.update(renderStore: renderStore, highlightIndex: highlightIndex, secondaryIndices: secondaryIndices, isPlaying: isPlaying, paragraphStarts: paragraphStarts, margin: margin, forceRedraw: true)
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
                .font: UIFont.systemFont(ofSize: fontSize + 8, weight: .bold),
                .foregroundColor: UIColor.label,
                .paragraphStyle: p
            ]))
        }
        
        let text = sents.map { String(repeating: "　", count: paragraphIndentLength) + $0 }.joined(separator: "\n")
        let p = NSMutableParagraphStyle()
        p.lineSpacing = lineSpacing
        p.alignment = .justified
        fullAttr.append(NSAttributedString(string: text, attributes: [.font: UIFont.systemFont(ofSize: fontSize), .foregroundColor: UIColor.label, .paragraphStyle: p]))
        
        return fullAttr
    }

    private func calculateSentenceOffsets() {
        guard let s = renderStore else { return }; s.layoutManager.ensureLayout(for: s.contentStorage.documentRange); var o: [CGFloat] = []
        let totalLen = s.attributedString.length
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
            scrollView.contentSize = CGSize(width: view.bounds.width, height: topPadding + h1)
            
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
        
        if isInfiniteScrollEnabled {
            if s.contentOffset.y > s.contentSize.height - s.bounds.height * 1.5 { onReachedBottom?() }
            if s.contentOffset.y < s.bounds.height * 0.6 { onReachedTop?() }
        }
        
        let idx = sentenceYOffsets.lastIndex(where: { $0 <= y + verticalDetectionOffset }) ?? 0
        if idx != lastReportedIndex { lastReportedIndex = idx; onVisibleIndexChanged?(idx) }
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
        onInteractionChanged?(false)
    }

    func scrollToSentence(index: Int, animated: Bool) { guard index >= 0 && index < sentenceYOffsets.count else { return }; let y = max(0, sentenceYOffsets[index] + contentTopPadding); scrollView.setContentOffset(CGPoint(x: 0, y: min(y, max(0, scrollView.contentSize.height - scrollView.bounds.height))), animated: animated) }
    func ensureSentenceVisible(index: Int) {
        guard !scrollView.isDragging && !scrollView.isDecelerating, index >= 0 && index < sentenceYOffsets.count, index != lastTTSSyncIndex else { return }
        let y = sentenceYOffsets[index] + contentTopPadding; let cur = scrollView.contentOffset.y; let vH = scrollView.bounds.height
        if y > cur + vH - 150 {
            lastTTSSyncIndex = index
            scrollView.setContentOffset(CGPoint(x: 0, y: max(0, y - contentTopPadding)), animated: true)
        }
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
        
        // 避障偏移：根据字体大小动态计算，确保只读出至少显示了一大半的行
        let detectionOffset = lastFontSize * 0.8
        
        // 计算探测点在全局坐标系中的 Y 坐标
        let globalY = scrollView.contentOffset.y + safeAreaTop + detectionOffset
        
        // 将全局坐标转换为当前章节视图 (currentContentView) 的局部坐标
        // 在无限流模式下，currentContentView.frame.minY 可能不为 0（取决于前面是否有上一章）
        let localY = globalY - currentContentView.frame.minY
        
        let point = CGPoint(
            x: horizontalMarginForDetection,
            y: localY
        )
        
        if let f = s.layoutManager.textLayoutFragment(for: point) {
            if #available(iOS 15.0, *) {
                // 查找视觉上位于 localY 处的具体行
                let relativeY = localY - f.layoutFragmentFrame.minY
                if let line = f.textLineFragments.first(where: { $0.typographicBounds.maxY > relativeY + 0.01 }) {
                    let fragmentStart = s.contentStorage.offset(from: s.contentStorage.documentRange.location, to: f.rangeInElement.location)
                    let lineStart = line.characterRange.location
                    let result = fragmentStart + lineStart
                    LogManager.shared.log("Vertical getCurrentCharOffset: localY=\(localY), fragMinY=\(f.layoutFragmentFrame.minY), result=\(result)", category: "TTS")
                    return result
                }
            }
            let result = s.contentStorage.offset(from: s.contentStorage.documentRange.location, to: f.rangeInElement.location)
            return result
        }
        return 0
    }
    func scrollToCharOffset(_ o: Int, animated: Bool) {
        let index = paragraphStarts.lastIndex(where: { $0 <= o }) ?? 0
        scrollToSentence(index: index, animated: animated)
    }

    func setHighlight(index: Int?, secondaryIndices: Set<Int>, isPlaying: Bool) {
        if lastHighlightIndex == index && lastSecondaryIndices == secondaryIndices && isPlaying == isPlayingHighlight { return }
        lastHighlightIndex = index
        lastSecondaryIndices = secondaryIndices
        currentContentView.update(renderStore: renderStore, highlightIndex: index, secondaryIndices: secondaryIndices, isPlaying: isPlaying, paragraphStarts: paragraphStarts, margin: lastMargin, forceRedraw: true)
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
    private var renderStore: TextKit2RenderStore?; private var highlightIndex: Int?; private var secondaryIndices: Set<Int> = []; private(set) var isPlayingHighlight: Bool = false; private var paragraphStarts: [Int] = []; private var margin: CGFloat = 20
    override init(frame: CGRect) { super.init(frame: frame); self.backgroundColor = .clear }
    required init?(coder: NSCoder) { fatalError() }
    func update(renderStore: TextKit2RenderStore?, highlightIndex: Int?, secondaryIndices: Set<Int>, isPlaying: Bool, paragraphStarts: [Int], margin: CGFloat, forceRedraw: Bool) {
        self.renderStore = renderStore; self.highlightIndex = highlightIndex; self.secondaryIndices = secondaryIndices; self.isPlayingHighlight = isPlaying; self.paragraphStarts = paragraphStarts; self.margin = margin
        if forceRedraw { setNeedsDisplay() }
    }
    override func draw(_ rect: CGRect) {
        guard let s = renderStore else { return }; let ctx = UIGraphicsGetCurrentContext()
        if isPlayingHighlight {
            ctx?.saveGState()
            for i in ([highlightIndex].compactMap{$0} + Array(secondaryIndices)) {
                guard i < paragraphStarts.count else { continue }
                let start = paragraphStarts[i], end = (i + 1 < paragraphStarts.count) ? paragraphStarts[i + 1] : s.attributedString.length, r = NSRange(location: start, length: max(0, end - start))
                ctx?.setFillColor(((i == highlightIndex) ? UIColor.systemBlue.withAlphaComponent(0.12) : UIColor.systemGreen.withAlphaComponent(0.06)).cgColor)
                
                if let startLoc = s.contentStorage.location(s.contentStorage.documentRange.location, offsetBy: r.location) {
                    s.layoutManager.enumerateTextLayoutFragments(from: startLoc, options: [.ensuresLayout]) { f in
                        if s.contentStorage.offset(from: s.contentStorage.documentRange.location, to: f.rangeInElement.location) >= NSMaxRange(r) { return false }
                        for line in f.textLineFragments { 
                            let lr = line.typographicBounds.offsetBy(dx: f.layoutFragmentFrame.origin.x, dy: f.layoutFragmentFrame.origin.y)
                            ctx?.addPath(UIBezierPath(roundedRect: lr.insetBy(dx: -2, dy: -1), cornerRadius: 4).cgPath)
                            ctx?.fillPath() 
                        }
                        return true
                    }
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
    private let dampingFactor: CGFloat = 0.2
    
    var onChapterSwitched: ((Int) -> Void)?
    var onToggleMenu: (() -> Void)?
    var onInteractionChanged: ((Bool) -> Void)?
    var safeAreaTop: CGFloat = 0
    var threshold: CGFloat = 80
    private var imageUrls: [String] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        scrollView.delegate = self
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.alwaysBounceVertical = true
        scrollView.contentInset = UIEdgeInsets(top: safeAreaTop, left: 0, bottom: 100, right: 0)
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
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        scrollView.addGestureRecognizer(tap)
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if view.bounds.size != lastViewSize {
            lastViewSize = view.bounds.size
            scrollView.frame = view.bounds
            scrollView.contentInset = UIEdgeInsets(top: safeAreaTop, left: 0, bottom: 100, right: 0)
        }
    }
    
    @objc private func handleTap() { onToggleMenu?() }

    func update(urls: [String]) {
        guard urls != self.imageUrls else { return }
        self.imageUrls = urls
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for urlStr in urls {
            let iv = UIImageView()
            iv.contentMode = .scaleAspectFit
            iv.clipsToBounds = true
            stackView.addArrangedSubview(iv)
            let url = urlStr.replacingOccurrences(of: "__IMG__", with: "").trimmingCharacters(in: .whitespaces)
            Task {
                if let u = URL(string: url), let (data, _) = try? await URLSession.shared.data(from: u), let img = UIImage(data: data) {
                    await MainActor.run {
                        iv.image = img
                        if img.size.width > 0 {
                            iv.heightAnchor.constraint(equalTo: iv.widthAnchor, multiplier: img.size.height / img.size.width).isActive = true
                        }
                    }
                }
            }
        }
    }

    func scrollViewDidScroll(_ s: UIScrollView) {
        let rawOffset = s.contentOffset.y
        handleHoldSwitchIfNeeded(rawOffset: rawOffset)
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

