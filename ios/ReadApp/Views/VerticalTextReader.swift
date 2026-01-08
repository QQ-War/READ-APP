import SwiftUI
import UIKit

// MARK: - SwiftUI 桥接组件
struct VerticalTextReader: UIViewControllerRepresentable {
    let sentences: [String]; let fontSize: CGFloat; let lineSpacing: CGFloat; let horizontalMargin: CGFloat; let highlightIndex: Int?; let secondaryIndices: Set<Int>; let isPlayingHighlight: Bool; let chapterUrl: String?
    let title: String?; let nextTitle: String?; let prevTitle: String?
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
        
        let changed = vc.update(sentences: sentences, nextSentences: nextChapterSentences, prevSentences: prevChapterSentences, title: title, nextTitle: nextTitle, prevTitle: prevTitle, fontSize: fontSize, lineSpacing: lineSpacing, margin: horizontalMargin, highlightIndex: highlightIndex, secondaryIndices: secondaryIndices, isPlaying: isPlayingHighlight)
        
        if forceScrollToTop {
            vc.scrollToTop(animated: false); DispatchQueue.main.async { onScrollFinished?() }
        } else if let sI = pendingScrollIndex {
            if changed { DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { vc.scrollToSentence(index: sI, animated: false) } } 
            else { vc.scrollToSentence(index: sI, animated: true) }; DispatchQueue.main.async { self.pendingScrollIndex = nil }
        } else if isPlayingHighlight, let hI = highlightIndex {
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
    private let dampingFactor: CGFloat = 0.12
    private let chapterGap: CGFloat = 80
    private var lastInfiniteSetting: Bool?

    var onVisibleIndexChanged: ((Int) -> Void)?; var onAddReplaceRule: ((String) -> Void)?; var onTapMenu: (() -> Void)?
    var onReachedBottom: (() -> Void)?; var onReachedTop: (() -> Void)?; var onChapterSwitched: ((Int) -> Void)?
    var onInteractionChanged: ((Bool) -> Void)?
    var safeAreaTop: CGFloat = 0; var chapterUrl: String?
    var isInfiniteScrollEnabled: Bool = true
    
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
        if !isUpdatingLayout { scrollView.frame = view.bounds; updateLayoutFrames() }
    }
    
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

    @objc private func handleTap() { onTapMenu?() }
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
            self.pendingSelectedText = txt
            if #available(iOS 16.0, *) {
                if let interaction = editMenuInteraction as? UIEditMenuInteraction {
                    let configuration = UIEditMenuConfiguration(identifier: nil, sourcePoint: g.location(in: view))
                    interaction.presentEditMenu(with: configuration)
                }
            } else {
                becomeFirstResponder()
                let menu = UIMenuController.shared
                menu.menuItems = [UIMenuItem(title: "添加净化规则", action: #selector(addToReplaceRule))]
                menu.showMenu(from: view, rect: CGRect(origin: g.location(in: view), size: .zero))
            }
        }
    }

    override var canBecomeFirstResponder: Bool { true }
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        return action == #selector(addToReplaceRule)
    }
    @objc private func addToReplaceRule() {
        if let t = pendingSelectedText { onAddReplaceRule?(t) }
    }

    @discardableResult
    func update(sentences: [String], nextSentences: [String]?, prevSentences: [String]?, title: String?, nextTitle: String?, prevTitle: String?, fontSize: CGFloat, lineSpacing: CGFloat, margin: CGFloat, highlightIndex: Int?, secondaryIndices: Set<Int>, isPlaying: Bool) -> Bool {
        self.lastMargin = margin
        let trimmedSentences = sentences.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let trimmedNextSentences = (nextSentences ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let trimmedPrevSentences = (prevSentences ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        
        let contentChanged = self.currentSentences != trimmedSentences || lastFontSize != fontSize || lastLineSpacing != lineSpacing
        let nextChanged = self.nextSentences != trimmedNextSentences
        let prevChanged = self.prevSentences != trimmedPrevSentences
        
        let isChapterSwap = (trimmedSentences == self.nextSentences) && !trimmedSentences.isEmpty
        let isChapterSwapToPrev = (trimmedSentences == self.prevSentences) && !trimmedSentences.isEmpty
        let oldPrevHeightWithGap = lastPrevHasContent ? (lastPrevContentHeight + chapterGap) : 0
        
        var layoutNeeded = false
        
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
            // 记录旧的 contentOffset 和关键视图的旧位置
            let oldOffset = scrollView.contentOffset.y
            let oldNextY = nextContentView.frame.minY
            let oldCurrY = currentContentView.frame.minY
            let wasPrevVisible = lastPrevHasContent
            let oldPrevHeightPlusGap = lastPrevHasContent ? (lastPrevContentHeight + chapterGap) : 0
            
            isUpdatingLayout = true
            updateLayoutFrames()
            
            if isChapterSwap {
                // 向下切章 (C -> N): 旧的 Next 变成了现在的 Current
                // 位移补偿：
                // 如果之前有 Prev 且现在由于数据轮转被丢弃了，那么新的 Current 坐标会减小
                // 具体的位移量就是被丢弃的那个 Prev 的高度 + Gap
                if wasPrevVisible {
                    scrollView.contentOffset.y = max(0, oldOffset - oldPrevHeightPlusGap)
                } else {
                    // 如果之前没有 Prev，现在由于 Current 变成了 Prev，
                    // 新的 Current (旧 Next) 其实在坐标系中的绝对位置并没有变
                    // 不需要调整 Offset
                }
            } else if isChapterSwapToPrev {
                // 向上切章 (C -> P): 旧的 Current 变成了现在的 Next
                // 位移补偿：
                // 此时由于上方插入了新的 Prev，所有旧内容都会被向下推
                // 位移量就是新的 Prev 的高度 + Gap
                let newPrevHeightPlusGap = lastPrevHasContent ? (lastPrevContentHeight + chapterGap) : 0
                scrollView.contentOffset.y = oldOffset + newPrevHeightPlusGap
            } else if prevChanged && !isChapterSwapToPrev {
                // 仅仅是静默加载/卸载了上一章，需要保持当前内容 (Current) 在屏幕上的位置不动
                let displacement = currentContentView.frame.minY - oldCurrY
                if displacement != 0 {
                    scrollView.contentOffset.y = oldOffset + displacement
                }
            }
            isUpdatingLayout = false
        }
        
        if lastHighlightIndex != highlightIndex || lastSecondaryIndices != secondaryIndices {
            lastHighlightIndex = highlightIndex; lastSecondaryIndices = secondaryIndices
            currentContentView.update(renderStore: renderStore, highlightIndex: highlightIndex, secondaryIndices: secondaryIndices, isPlaying: isPlaying, paragraphStarts: paragraphStarts, margin: margin, forceRedraw: true)
        }
        
        applyScrollBehaviorIfNeeded()
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
        
        let text = sents.map { "　　" + $0 }.joined(separator: "\n")
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
        let topPadding = safeAreaTop + 10
        
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
            ns.layoutManager.enumerateTextLayoutFragments(from: ns.contentStorage.documentRange.endLocation, options: [.reverse, .ensuresLayout]) { f in h2 = f.layoutFragmentFrame.maxY; return false }
            nextContentView.isHidden = false
            nextContentView.frame = CGRect(x: m, y: currentY + h1 + chapterGap, width: ns.layoutWidth, height: h2)
            totalH += h2 + chapterGap
        } else {
            nextContentView.isHidden = true
        }
        let extraBottom: CGFloat = isInfiniteScrollEnabled ? 200 : 40
        scrollView.contentSize = CGSize(width: view.bounds.width, height: totalH + extraBottom)
    }

    func scrollViewDidScroll(_ s: UIScrollView) {
        if isUpdatingLayout { return }
        let rawOffset = s.contentOffset.y
        let y = s.contentOffset.y - (safeAreaTop + 10)
        
        // 1. 无限滚动自动切换
        if isInfiniteScrollEnabled {
            handleAutoSwitchIfNeeded(rawOffset: rawOffset)
            executeSeamlessSwitchIfNeeded() // 尝试在滚动中自动切换
        }
        
        // 2. 边缘拉动切换
        let hasPrev = prevRenderStore != nil
        let hasNext = nextRenderStore != nil
        let maxScrollY = max(0, s.contentSize.height - s.bounds.height)
        
        if !isInfiniteScrollEnabled || (rawOffset < -10 && !hasPrev) || (rawOffset > maxScrollY + 10 && !hasNext) {
            handleHoldSwitchIfNeeded(rawOffset: rawOffset)
        } else {
            hideSwitchHint()
        }
        
        if isInfiniteScrollEnabled && s.contentOffset.y > s.contentSize.height - s.bounds.height * 2 {
            onReachedBottom?()
        }
        if isInfiniteScrollEnabled && s.contentOffset.y < s.bounds.height {
            onReachedTop?()
        }
        
        let idx = sentenceYOffsets.lastIndex(where: { $0 <= y + 5 }) ?? 0
        if idx != lastReportedIndex { lastReportedIndex = idx; onVisibleIndexChanged?(idx) }
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        cancelSwitchHold()
        pendingSeamlessSwitch = 0 // 新的拖拽开始，重置自动切换标记
        onInteractionChanged?(true)
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        // 无限流模式：检查是否有待执行的无缝切换
        if isInfiniteScrollEnabled {
            if !decelerate { 
                onInteractionChanged?(false) 
                executeSeamlessSwitchIfNeeded()
            }
            return
        }
        
        // 非无限流模式：执行松手切换逻辑
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
        if isInfiniteScrollEnabled {
            executeSeamlessSwitchIfNeeded()
        }
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
                onChapterSwitched?(dir)
            }
        }
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        onInteractionChanged?(false)
    }

    func scrollToSentence(index: Int, animated: Bool) { guard index >= 0 && index < sentenceYOffsets.count else { return }; let y = max(0, sentenceYOffsets[index] + safeAreaTop + 10); scrollView.setContentOffset(CGPoint(x: 0, y: min(y, max(0, scrollView.contentSize.height - scrollView.bounds.height))), animated: animated) }
    func ensureSentenceVisible(index: Int) {
        guard !scrollView.isDragging && !scrollView.isDecelerating, index >= 0 && index < sentenceYOffsets.count, index != lastTTSSyncIndex else { return }
        let y = sentenceYOffsets[index] + safeAreaTop + 10; let cur = scrollView.contentOffset.y; let vH = scrollView.bounds.height
        if y < cur + 50 || y > cur + vH - 150 { lastTTSSyncIndex = index; scrollView.setContentOffset(CGPoint(x: 0, y: max(0, y - vH / 3)), animated: true) }
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
        let y = scrollView.contentOffset.y - (safeAreaTop + 10)
        let idx = sentenceYOffsets.lastIndex(where: { $0 <= y + 5 }) ?? 0
        return max(0, idx)
    }
    func getCurrentCharOffset() -> Int {
        guard let s = renderStore, viewIfLoaded != nil else { return 0 }
        let point = CGPoint(x: 10, y: scrollView.contentOffset.y - (safeAreaTop + 10) + 5)
        if let f = s.layoutManager.textLayoutFragment(for: point) {
            return s.contentStorage.offset(from: s.contentStorage.documentRange.location, to: f.rangeInElement.location)
        }
        return 0
    }
    func scrollToCharOffset(_ o: Int, animated: Bool) {
        let index = paragraphStarts.lastIndex(where: { $0 <= o }) ?? 0
        scrollToSentence(index: index, animated: animated)
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
        switchHintLabel.text = "  \(text)  "
        switchHintLabel.sizeToFit()
        let width = min(view.bounds.width - 40, max(120, switchHintLabel.bounds.width))
        let bottomSafe = max(0, view.safeAreaInsets.bottom)
        switchHintLabel.frame = CGRect(
            x: (view.bounds.width - width) / 2,
            y: isTop ? (safeAreaTop + 12) : (view.bounds.height - bottomSafe - 36),
            width: width,
            height: 24
        )
        if switchHintLabel.alpha == 0 {
            UIView.animate(withDuration: 0.2) { self.switchHintLabel.alpha = 1 }
        }
    }

    private func hideSwitchHint() {
        guard switchHintLabel.alpha > 0 else { return }
        UIView.animate(withDuration: 0.2) { self.switchHintLabel.alpha = 0 }
    }

    private func handleAutoSwitchIfNeeded(rawOffset: CGFloat) {
        if pendingSeamlessSwitch != 0 { return }
        
        // 只有当旧章节已经完全滚出视野，且接缝处在屏幕上方一定距离外时，才标记切换
        // 这样可以确保切换时，用户眼中只有新章节的内容，增加稳定性
        
        if let _ = nextRenderStore {
            // 当前章节底部坐标
            let currentBottomY = currentContentView.frame.maxY
            // 如果滚动位置已经超过当前章节底部 100 像素（即接缝已在屏幕上方 100px 处）
            if rawOffset > currentBottomY + 100 {
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

    func handleHoldSwitchIfNeeded(rawOffset: CGFloat) {
        let threshold: CGFloat = 60 // 降低阈值，更敏感
        let topThreshold: CGFloat = -threshold
        
        let actualMaxScrollY = max(0, scrollView.contentSize.height - scrollView.bounds.height)
        let bottomThreshold = actualMaxScrollY + threshold
        
        if rawOffset < -5 {
            if rawOffset < topThreshold {
                if !switchReady {
                    switchReady = true; pendingSwitchDirection = -1
                    hapticFeedback()
                }
                updateSwitchHint(text: "松开切换上一章", isTop: true)
            } else {
                switchReady = false; pendingSwitchDirection = -1
                updateSwitchHint(text: "继续下拉切换上一章", isTop: true)
            }
        } else if rawOffset > actualMaxScrollY + 5 {
            if rawOffset > bottomThreshold {
                if !switchReady {
                    switchReady = true; pendingSwitchDirection = 1
                    hapticFeedback()
                }
                updateSwitchHint(text: "松开切换下一章", isTop: false)
            } else {
                switchReady = false; pendingSwitchDirection = 1
                updateSwitchHint(text: "继续上拉切换下一章", isTop: false)
            }
        } else {
            if !scrollView.isDragging && !switchReady {
                cancelSwitchHold()
            }
        }
    }
    
    private func hapticFeedback() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    func cancelSwitchHold() {
        switchWorkItem?.cancel()
        switchWorkItem = nil
        pendingSwitchDirection = 0
        switchReady = false
        hideSwitchHint()
    }

    func applyScrollBehaviorIfNeeded() {
        if lastInfiniteSetting == isInfiniteScrollEnabled { return }
        lastInfiniteSetting = isInfiniteScrollEnabled
        if isInfiniteScrollEnabled {
            scrollView.contentInset = .zero
            cancelSwitchHold()
        } else {
            // 给底部留一点弹跳空间即可，不需要 100 这么大
            scrollView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 20, right: 0)
        }
    }
}

class VerticalTextContentView: UIView {
    private var renderStore: TextKit2RenderStore?; private var highlightIndex: Int?; private var secondaryIndices: Set<Int> = []; private var isPlayingHighlight: Bool = false; private var paragraphStarts: [Int] = []; private var margin: CGFloat = 20
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
    private var pendingSwitchDirection: Int = 0
    private var switchReady = false
    private var switchWorkItem: DispatchWorkItem?
    private let switchHoldDuration: TimeInterval = 0.6
    private let dampingFactor: CGFloat = 0.2
    
    var onChapterSwitched: ((Int) -> Void)?
    var onToggleMenu: (() -> Void)?
    var onInteractionChanged: ((Bool) -> Void)?
    var safeAreaTop: CGFloat = 0
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
        scrollView.frame = view.bounds
        scrollView.contentInset = UIEdgeInsets(top: safeAreaTop, left: 0, bottom: 100, right: 0)
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
        switchHintLabel.text = "  \(text)  "
        switchHintLabel.sizeToFit()
        let width = min(view.bounds.width - 40, max(120, switchHintLabel.bounds.width))
        let bottomSafe = max(0, view.safeAreaInsets.bottom)
        switchHintLabel.frame = CGRect(
            x: (view.bounds.width - width) / 2,
            y: isTop ? (safeAreaTop + 12) : (view.bounds.height - bottomSafe - 36),
            width: width, height: 24
        )
        if switchHintLabel.alpha == 0 { UIView.animate(withDuration: 0.2) { self.switchHintLabel.alpha = 1 } }
    }

    private func hideSwitchHint() {
        guard switchHintLabel.alpha > 0 else { return }
        UIView.animate(withDuration: 0.2) { self.switchHintLabel.alpha = 0 }
    }

    private func handleHoldSwitchIfNeeded(rawOffset: CGFloat) {
        let threshold: CGFloat = 60
        let topThreshold: CGFloat = -safeAreaTop - threshold
        
        let actualMaxScrollY = max(-safeAreaTop, stackView.frame.height - scrollView.bounds.height)
        let bottomThreshold = actualMaxScrollY + threshold
        
        if rawOffset < -safeAreaTop - 5 {
            if rawOffset < topThreshold {
                if !switchReady {
                    switchReady = true; pendingSwitchDirection = -1
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                }
                updateSwitchHint(text: "松开切换上一章", isTop: true)
            } else {
                switchReady = false; pendingSwitchDirection = -1
                updateSwitchHint(text: "继续下拉切换上一章", isTop: true)
            }
        } else if rawOffset > actualMaxScrollY + 5 {
            if rawOffset > bottomThreshold {
                if !switchReady {
                    switchReady = true; pendingSwitchDirection = 1
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                }
                updateSwitchHint(text: "松开切换下一章", isTop: false)
            } else {
                switchReady = false; pendingSwitchDirection = 1
                updateSwitchHint(text: "继续上拉切换下一章", isTop: false)
            }
        } else {
            if !scrollView.isDragging && !switchReady {
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

@available(iOS 16.0, *)
extension VerticalTextViewController: UIEditMenuInteractionDelegate {
    func editMenuInteraction(_ interaction: UIEditMenuInteraction, menuFor configuration: UIEditMenuConfiguration, suggestedActions: [UIMenuElement]) -> UIMenu? {
        let addAction = UIAction(title: "添加净化规则") { [weak self] _ in
            if let t = self?.pendingSelectedText { self?.onAddReplaceRule?(t) }
        }
        return UIMenu(children: [addAction] + suggestedActions)
    }
}
