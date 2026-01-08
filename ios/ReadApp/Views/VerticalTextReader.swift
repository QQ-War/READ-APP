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
    var onReachedTop: (() -> Void)? // 触发预载
    var onChapterSwitched: ((Int) -> Void)? // 0: 本章, 1: 下一章
    var onInteractionChanged: ((Bool) -> Void)?
    
    func makeUIViewController(context: Context) -> VerticalTextViewController {
        let vc = VerticalTextViewController(); vc.onVisibleIndexChanged = { i in DispatchQueue.main.async { if currentVisibleIndex != i { currentVisibleIndex = i } } }; vc.onAddReplaceRule = onAddReplaceRule; vc.onTapMenu = onTapMenu; return vc
    }
    
    func updateUIViewController(_ vc: VerticalTextViewController, context: Context) {
        vc.onAddReplaceRule = onAddReplaceRule; vc.onTapMenu = onTapMenu; vc.safeAreaTop = safeAreaTop
        vc.onReachedBottom = onReachedBottom; vc.onChapterSwitched = onChapterSwitched
        vc.onReachedTop = onReachedTop
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
    private var lastAutoSwitchTime: TimeInterval = 0
    private let autoSwitchCooldown: TimeInterval = 0.6

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
        // 预处理句子，去除首尾空白以统一缩进控制
        let trimmedSentences = sentences.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let trimmedNextSentences = (nextSentences ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let trimmedPrevSentences = (prevSentences ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        
        let contentChanged = self.currentSentences != trimmedSentences || lastFontSize != fontSize || lastLineSpacing != lineSpacing
        let nextChanged = self.nextSentences != trimmedNextSentences
        let prevChanged = self.prevSentences != trimmedPrevSentences
        
        // 核心优化：检测是否发生了章节置换（即上一章的内容现在变成了本章内容）
        // 如果 sentences 等于旧的 nextSentences，说明发生了向下滑动切换
        let isChapterSwap = (trimmedSentences == self.nextSentences) && !trimmedSentences.isEmpty
        let isChapterSwapToPrev = (trimmedSentences == self.prevSentences) && !trimmedSentences.isEmpty
        let oldPrevHeightWithGap = lastPrevHasContent ? (lastPrevContentHeight + chapterGap) : 0
        
        if contentChanged || renderStore == nil {
            self.previousContentHeight = currentContentView.frame.height
            
            self.currentSentences = trimmedSentences; self.lastFontSize = fontSize; self.lastLineSpacing = lineSpacing; isUpdatingLayout = true
            
            // 重新计算 paragraphStarts，需要考虑标题的偏移
            let titleText = title != nil && !title!.isEmpty ? title! + "\n" : ""
            let titleLen = titleText.utf16.count
            var pS: [Int] = []; var cP = titleLen; for s in trimmedSentences { 
                pS.append(cP)
                cP += s.count + 2 + 1 // 2 为全角空格，1 为换行符
            }; paragraphStarts = pS
            
            let attr = createAttr(trimmedSentences, title: title, fontSize: fontSize, lineSpacing: lineSpacing)
            if let s = renderStore { s.update(attributedString: attr, layoutWidth: max(100, view.bounds.width - margin * 2)) } 
            else { renderStore = TextKit2RenderStore(attributedString: attr, layoutWidth: max(100, view.bounds.width - margin * 2)) }
            calculateSentenceOffsets(); isUpdatingLayout = false
            currentContentView.update(renderStore: renderStore, highlightIndex: highlightIndex, secondaryIndices: secondaryIndices, isPlaying: isPlaying, paragraphStarts: paragraphStarts, margin: margin, forceRedraw: true)
            updateLayoutFrames()
            
            // 执行无感置换
            if isChapterSwap {
                // 旧的 offset.y 肯定很大（因为它包含了 previousContentHeight）
                // 新的 offset.y 应该减去 previousContentHeight + 80 (间距)
                let adjustment = previousContentHeight + chapterGap
                // 只有当 adjustment 合理时才调整，防止跳变
                if adjustment > 0 {
                    let newY = max(0, scrollView.contentOffset.y - adjustment)
                    scrollView.setContentOffset(CGPoint(x: 0, y: newY), animated: false)
                }
            } else if isChapterSwapToPrev {
                let adjustment = oldPrevHeightWithGap
                if adjustment > 0 {
                    let newY = max(0, scrollView.contentOffset.y + adjustment)
                    scrollView.setContentOffset(CGPoint(x: 0, y: newY), animated: false)
                }
            }
            return true
        }
        
        if nextChanged {
            self.nextSentences = trimmedNextSentences
            if trimmedNextSentences.isEmpty {
                nextRenderStore = nil
                nextContentView.isHidden = true
                updateLayoutFrames()
            } else {
                let attr = createAttr(trimmedNextSentences, title: nextTitle, fontSize: fontSize, lineSpacing: lineSpacing)
                if let s = nextRenderStore { s.update(attributedString: attr, layoutWidth: max(100, view.bounds.width - margin * 2)) } 
                else { nextRenderStore = TextKit2RenderStore(attributedString: attr, layoutWidth: max(100, view.bounds.width - margin * 2)) }
                nextContentView.update(renderStore: nextRenderStore, highlightIndex: nil, secondaryIndices: [], isPlaying: false, paragraphStarts: [], margin: margin, forceRedraw: true)
                updateLayoutFrames()
            }
        }
        
        if prevChanged {
            self.prevSentences = trimmedPrevSentences
            if trimmedPrevSentences.isEmpty {
                prevRenderStore = nil
                prevContentView.isHidden = true
                updateLayoutFrames()
            } else {
                let attr = createAttr(trimmedPrevSentences, title: prevTitle, fontSize: fontSize, lineSpacing: lineSpacing)
                if let s = prevRenderStore { s.update(attributedString: attr, layoutWidth: max(100, view.bounds.width - margin * 2)) } 
                else { prevRenderStore = TextKit2RenderStore(attributedString: attr, layoutWidth: max(100, view.bounds.width - margin * 2)) }
                prevContentView.update(renderStore: prevRenderStore, highlightIndex: nil, secondaryIndices: [], isPlaying: false, paragraphStarts: [], margin: margin, forceRedraw: true)
                updateLayoutFrames()
            }
        }
        
        if lastHighlightIndex != highlightIndex || lastSecondaryIndices != secondaryIndices {
            lastHighlightIndex = highlightIndex; lastSecondaryIndices = secondaryIndices
            currentContentView.update(renderStore: renderStore, highlightIndex: highlightIndex, secondaryIndices: secondaryIndices, isPlaying: isPlaying, paragraphStarts: paragraphStarts, margin: margin, forceRedraw: true)
        }
        
        let newPrevHeightWithGap = lastPrevHasContent ? (lastPrevContentHeight + chapterGap) : 0
        if prevChanged && !isChapterSwapToPrev {
            let delta = newPrevHeightWithGap - oldPrevHeightWithGap
            if delta != 0 {
                scrollView.setContentOffset(CGPoint(x: 0, y: max(0, scrollView.contentOffset.y + delta)), animated: false)
            }
        }
        
        applyScrollBehaviorIfNeeded()
        return false
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
        // 移除 p.firstLineHeadIndent = fontSize * 1.5
        fullAttr.append(NSAttributedString(string: text, attributes: [.font: UIFont.systemFont(ofSize: fontSize), .foregroundColor: UIColor.label, .paragraphStyle: p]))
        
        return fullAttr
    }

    private func calculateSentenceOffsets() {
        guard let s = renderStore else { return }; s.layoutManager.ensureLayout(for: s.contentStorage.documentRange); var o: [CGFloat] = []
        for start in paragraphStarts { if let loc = s.contentStorage.location(s.contentStorage.documentRange.location, offsetBy: start), let f = s.layoutManager.textLayoutFragment(for: loc) { o.append(f.layoutFragmentFrame.minY) } else { o.append(o.last ?? 0) } }
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
        scrollView.contentSize = CGSize(width: view.bounds.width, height: totalH + 200)
    }

    func scrollViewDidScroll(_ s: UIScrollView) {
        if isUpdatingLayout { return }
        
        let rawOffset = s.contentOffset.y
        let contentInsetBottom = s.contentInset.bottom
        
        if !isInfiniteScrollEnabled {
            // 顶部阻尼：contentOffset.y < -contentInset.top 时触发
            let topInset: CGFloat = 0
            if rawOffset < topInset {
                let over = topInset - rawOffset
                s.contentOffset.y = topInset - over * dampingFactor
            }
            
            // 底部阻尼：contentOffset.y > adjustedContentHeight 时触发
            let adjustedContentHeight = max(0, s.contentSize.height - s.bounds.height + contentInsetBottom)
            if rawOffset > adjustedContentHeight {
                let over = rawOffset - adjustedContentHeight
                s.contentOffset.y = adjustedContentHeight + over * dampingFactor
            }
        }
        
        let y = s.contentOffset.y - (safeAreaTop + 10)
        
        if isInfiniteScrollEnabled {
            handleAutoSwitchIfNeeded(rawOffset: rawOffset)
        } else {
            handleHoldSwitchIfNeeded(rawOffset: rawOffset)
        }
        
        // 预载判定 (仅限无限流)
        if isInfiniteScrollEnabled {
            if s.contentOffset.y > s.contentSize.height - s.bounds.height * 1.3 {
                onReachedBottom?()
            }
            if s.contentOffset.y < s.bounds.height * 0.3 {
                onReachedTop?()
            }
        }
        
        // 进度汇报
        let idx = sentenceYOffsets.lastIndex(where: { $0 <= y + 5 }) ?? 0
        if idx != lastReportedIndex { lastReportedIndex = idx; onVisibleIndexChanged?(idx) }
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        cancelSwitchHold()
        onInteractionChanged?(true)
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if isInfiniteScrollEnabled {
            if !decelerate { onInteractionChanged?(false) }
            cancelSwitchHold()
            return
        }
        // 如果在切换就绪状态，延迟检查阻尼回弹后再决定是否切换
        if switchReady && pendingSwitchDirection != 0 {
            // 延迟一点时间让阻尼回弹完成
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                guard let self = self else { return }
                // 检查是否仍然在切换就绪状态
                if self.switchReady && self.pendingSwitchDirection != 0 {
                    // 触发章节切换
                    self.onChapterSwitched?(self.pendingSwitchDirection)
                }
                self.cancelSwitchHold()
            }
        } else {
            if !decelerate { onInteractionChanged?(false) }
            cancelSwitchHold()
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        cancelSwitchHold()
        onInteractionChanged?(false)
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
        guard let s = renderStore else { return 0 }; let f = s.layoutManager.textLayoutFragment(for: CGPoint(x: 10, y: scrollView.contentOffset.y - (safeAreaTop + 10) + 5))
        return f != nil ? s.contentStorage.offset(from: s.contentStorage.documentRange.location, to: f!.rangeInElement.location) : 0
    }
    func scrollToCharOffset(_ o: Int, animated: Bool) {
        guard let s = renderStore else { return }
        
        // 查找最接近的段落索引，防止直接使用 charOffset 定位到 fragment 中间
        let index = paragraphStarts.lastIndex(where: { $0 <= o }) ?? 0
        scrollToSentence(index: index, animated: animated)
    }
}

private extension VerticalTextViewController {
    func setupSwitchHint() {
        switchHintLabel.alpha = 0
        switchHintLabel.textAlignment = .center
        switchHintLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        switchHintLabel.textColor = .secondaryLabel
        switchHintLabel.backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.9)
        switchHintLabel.layer.cornerRadius = 12
        switchHintLabel.layer.masksToBounds = true
        view.addSubview(switchHintLabel)
    }

    func updateSwitchHint(text: String, isTop: Bool) {
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

    func hideSwitchHint() {
        guard switchHintLabel.alpha > 0 else { return }
        UIView.animate(withDuration: 0.2) { self.switchHintLabel.alpha = 0 }
    }

    func handleAutoSwitchIfNeeded(rawOffset: CGFloat) {
        if let _ = prevRenderStore, !prevContentView.isHidden {
            let triggerTop = currentContentView.frame.minY - 20
            if rawOffset < triggerTop {
                triggerAutoSwitch(direction: -1, isTop: true)
                return
            }
        }
        if let _ = nextRenderStore, !nextContentView.isHidden {
            let triggerBottom = nextContentView.frame.minY - 20
            if rawOffset > triggerBottom {
                triggerAutoSwitch(direction: 1, isTop: false)
            }
        }
    }

    func handleHoldSwitchIfNeeded(rawOffset: CGFloat) {
        let topThreshold: CGFloat = -80
        let topOver = topThreshold - rawOffset
        
        let contentInsetBottom = scrollView.contentInset.bottom
        let adjustedBottomThreshold = max(0, scrollView.contentSize.height - scrollView.bounds.height + contentInsetBottom)
        let bottomThreshold = adjustedBottomThreshold + 80
        let bottomOver = rawOffset - bottomThreshold
        
        if scrollView.isDragging {
            if topOver > 0 {
                switchReady = true
                pendingSwitchDirection = -1
                updateSwitchHint(text: "松手切换上一章", isTop: true)
                return
            }
            if bottomOver > 0 {
                switchReady = true
                pendingSwitchDirection = 1
                updateSwitchHint(text: "松手切换下一章", isTop: false)
                return
            }
        }
        
        if !scrollView.isDragging || (topOver <= 0 && bottomOver <= 0) {
            cancelSwitchHold()
        }
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
            scrollView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 100, right: 0)
        }
    }

    func triggerAutoSwitch(direction: Int, isTop: Bool) {
        let now = Date().timeIntervalSince1970
        guard now - lastAutoSwitchTime > autoSwitchCooldown else { return }
        lastAutoSwitchTime = now
        onChapterSwitched?(direction)
        let text = direction > 0 ? "已切换到下一章" : "已切换到上一章"
        updateSwitchHint(text: text, isTop: isTop)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.hideSwitchHint()
        }
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
                s.layoutManager.enumerateTextLayoutFragments(from: s.contentStorage.location(s.contentStorage.documentRange.location, offsetBy: r.location)!, options: [.ensuresLayout]) { f in
                    if s.contentStorage.offset(from: s.contentStorage.documentRange.location, to: f.rangeInElement.location) >= NSMaxRange(r) { return false }
                    for line in f.textLineFragments { 
                        // 这里 line.typographicBounds 已经相对于 fragment 的坐标了
                        let lr = line.typographicBounds.offsetBy(dx: f.layoutFragmentFrame.origin.x, dy: f.layoutFragmentFrame.origin.y)
                        ctx?.addPath(UIBezierPath(roundedRect: lr.insetBy(dx: -2, dy: -1), cornerRadius: 4).cgPath)
                        ctx?.fillPath() 
                    }
                    return true
                }
            }
            ctx?.restoreGState()
        }
        
        // 关键修复：绘图时不要受 View 坐标影响，LayoutManager 里的 frame 是相对于其布局容器的
        ctx?.saveGState()
        let sL = s.layoutManager.textLayoutFragment(for: CGPoint(x: 0, y: rect.minY))?.rangeInElement.location ?? s.contentStorage.documentRange.location
        s.layoutManager.enumerateTextLayoutFragments(from: sL, options: [.ensuresLayout]) { f in
            if f.layoutFragmentFrame.minY > rect.maxY { return false }
            if f.layoutFragmentFrame.maxY >= rect.minY { 
                f.draw(at: f.layoutFragmentFrame.origin, in: ctx!) 
            }
            return true
        }
        ctx?.restoreGState()
    }
}

enum VerticalReaderTask { case scrollToTop; case scrollToIndex(Int) }

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
        // 设置 contentInset 让阻尼效果生效
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
        // 保持 contentInset 一致，底部使用固定100pt作为阻尼空间
        scrollView.contentInset = UIEdgeInsets(top: safeAreaTop, left: 0, bottom: 100, right: 0)
        // 初始 offset 设置为负值，触发顶部阻尼
        if scrollView.contentOffset.y > -100 {
            scrollView.contentOffset = CGPoint(x: 0, y: -100)
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
                        iv.heightAnchor.constraint(equalTo: iv.widthAnchor, multiplier: img.size.height / img.size.width).isActive = true
                    }
                }
            }
        }
    }

    func scrollViewDidScroll(_ s: UIScrollView) {
        let rawOffset = s.contentOffset.y
        let topEdge: CGFloat = -safeAreaTop
        let bottomEdge = max(-safeAreaTop, s.contentSize.height - s.bounds.height + 40)
        
        if rawOffset < topEdge {
            s.contentOffset.y = topEdge + (rawOffset - topEdge) * dampingFactor
        } else if rawOffset > bottomEdge {
            s.contentOffset.y = bottomEdge + (rawOffset - bottomEdge) * dampingFactor
        }
        
        handleHoldSwitchIfNeeded(rawOffset: s.contentOffset.y)
    }
    
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        cancelSwitchHold()
        onInteractionChanged?(true)
    }
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if switchReady && pendingSwitchDirection != 0 {
            // 延迟检查阻尼回弹
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                guard let self = self else { return }
                if self.switchReady && self.pendingSwitchDirection != 0 {
                    self.onChapterSwitched?(self.pendingSwitchDirection)
                }
                self.cancelSwitchHold()
            }
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
        let topThreshold: CGFloat = -safeAreaTop - 80
        let topOver = topThreshold - rawOffset
        let bottomInset: CGFloat = 100
        let adjustedBottomThreshold = max(-safeAreaTop, scrollView.contentSize.height - scrollView.bounds.height + bottomInset)
        let bottomThreshold = adjustedBottomThreshold + 80
        let bottomOver = rawOffset - bottomThreshold

        if scrollView.isDragging {
            if topOver > 0 {
                beginSwitchHold(direction: -1, isTop: true)
                return
            }
            if bottomOver > 0 {
                beginSwitchHold(direction: 1, isTop: false)
                return
            }
        }
        
        if !scrollView.isDragging {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self = self else { return }
                if self.switchReady && self.pendingSwitchDirection != 0 {
                    self.onChapterSwitched?(self.pendingSwitchDirection)
                }
                self.cancelSwitchHold()
            }
        } else if topOver <= 0 && bottomOver <= 0 {
            cancelSwitchHold()
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
