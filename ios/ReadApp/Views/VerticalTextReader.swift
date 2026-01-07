import SwiftUI
import UIKit

// MARK: - SwiftUI 桥接组件
struct VerticalTextReader: UIViewControllerRepresentable {
    let sentences: [String]; let fontSize: CGFloat; let lineSpacing: CGFloat; let horizontalMargin: CGFloat; let highlightIndex: Int?; let secondaryIndices: Set<Int>; let isPlayingHighlight: Bool; let chapterUrl: String?
    @Binding var currentVisibleIndex: Int; @Binding var pendingScrollIndex: Int?
    var forceScrollToTop: Bool = false; var onScrollFinished: (() -> Void)?; var onAddReplaceRule: ((String) -> Void)?; var onTapMenu: (() -> Void)?
    var safeAreaTop: CGFloat = 0
    
    // 无限流扩展
    var nextChapterSentences: [String]?
    var onReachedBottom: (() -> Void)? // 触发预载
    var onChapterSwitched: ((Int) -> Void)? // 0: 本章, 1: 下一章
    
    func makeUIViewController(context: Context) -> VerticalTextViewController {
        let vc = VerticalTextViewController(); vc.onVisibleIndexChanged = { i in DispatchQueue.main.async { if currentVisibleIndex != i { currentVisibleIndex = i } } }; vc.onAddReplaceRule = onAddReplaceRule; vc.onTapMenu = onTapMenu; return vc
    }
    
    func updateUIViewController(_ vc: VerticalTextViewController, context: Context) {
        vc.onAddReplaceRule = onAddReplaceRule; vc.onTapMenu = onTapMenu; vc.safeAreaTop = safeAreaTop
        vc.onReachedBottom = onReachedBottom; vc.onChapterSwitched = onChapterSwitched
        
        let changed = vc.update(sentences: sentences, nextSentences: nextChapterSentences, fontSize: fontSize, lineSpacing: lineSpacing, margin: horizontalMargin, highlightIndex: highlightIndex, secondaryIndices: secondaryIndices, isPlaying: isPlayingHighlight)
        
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
class VerticalTextViewController: UIViewController, UIScrollViewDelegate {
    let scrollView = UIScrollView()
    private let currentContentView = VerticalTextContentView()
    private let nextContentView = VerticalTextContentView() // 下一章拼接视图
    
    var onVisibleIndexChanged: ((Int) -> Void)?; var onAddReplaceRule: ((String) -> Void)?; var onTapMenu: (() -> Void)?
    var onReachedBottom: (() -> Void)?; var onChapterSwitched: ((Int) -> Void)?
    var safeAreaTop: CGFloat = 0; var chapterUrl: String?
    
    private var renderStore: TextKit2RenderStore?; private var nextRenderStore: TextKit2RenderStore?
    private var currentSentences: [String] = []; private var nextSentences: [String] = []
    private var paragraphStarts: [Int] = []; private var sentenceYOffsets: [CGFloat] = []
    private var lastReportedIndex: Int = -1; private var isUpdatingLayout = false; private var lastTTSSyncIndex: Int = -1
    
    private var lastHighlightIndex: Int?; private var lastSecondaryIndices: Set<Int> = []; private var lastFontSize: CGFloat = 0; private var lastLineSpacing: CGFloat = 0; private var lastMargin: CGFloat = 20
    
    // 无感置换状态记录
    private var previousContentHeight: CGFloat = 0
    
    override func viewDidLoad() {
        super.viewDidLoad()
        scrollView.delegate = self; scrollView.contentInsetAdjustmentBehavior = .never; scrollView.showsVerticalScrollIndicator = true; scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView); scrollView.addSubview(currentContentView); scrollView.addSubview(nextContentView)
        scrollView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))
        scrollView.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress)))
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if !isUpdatingLayout { scrollView.frame = view.bounds; updateLayoutFrames() }
    }
    
    @objc private func handleTap() { onTapMenu?() }
    @objc private func handleLongPress(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began else { return }
        let p = g.location(in: scrollView)
        let s = p.y < nextContentView.frame.minY ? renderStore : nextRenderStore
        let cv = p.y < nextContentView.frame.minY ? currentContentView : nextContentView
        guard let store = s else { return }
        let pointInContent = g.location(in: cv)
        // 修复可选值解包
        if let f = store.layoutManager.textLayoutFragment(for: pointInContent), let te = f.textElement, let range = te.elementRange, let r = TextKit2Paginator.rangeFromTextRange(range, in: store.contentStorage) {
            let txt = (store.attributedString.string as NSString).substring(with: r)
            becomeFirstResponder(); self.pendingSelectedText = txt; UIMenuController.shared.showMenu(from: cv, rect: CGRect(origin: pointInContent, size: .zero))
        }
    }
    
    private var pendingSelectedText: String?; override var canBecomeFirstResponder: Bool { true }
    override func canPerformAction(_ a: Selector, withSender s: Any?) -> Bool { return a == #selector(addToReplaceRule) }
    @objc func addToReplaceRule() { if let t = pendingSelectedText { onAddReplaceRule?(t) } }

    @discardableResult
    func update(sentences: [String], nextSentences: [String]?, fontSize: CGFloat, lineSpacing: CGFloat, margin: CGFloat, highlightIndex: Int?, secondaryIndices: Set<Int>, isPlaying: Bool) -> Bool {
        self.lastMargin = margin
        // 预处理句子，去除首尾空白以统一缩进控制
        let trimmedSentences = sentences.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let trimmedNextSentences = (nextSentences ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        
        let contentChanged = self.currentSentences != trimmedSentences || lastFontSize != fontSize || lastLineSpacing != lineSpacing
        let nextChanged = self.nextSentences != trimmedNextSentences
        
        // 核心优化：检测是否发生了章节置换（即上一章的内容现在变成了本章内容）
        // 如果 sentences 等于旧的 nextSentences，说明发生了向下滑动切换
        let isChapterSwap = (trimmedSentences == self.nextSentences) && !trimmedSentences.isEmpty
        
        if contentChanged || renderStore == nil {
            self.previousContentHeight = currentContentView.frame.height
            
            self.currentSentences = trimmedSentences; self.lastFontSize = fontSize; self.lastLineSpacing = lineSpacing; isUpdatingLayout = true
            var pS: [Int] = []; var cP = 0; for s in trimmedSentences { pS.append(cP); cP += s.count + 1 }; paragraphStarts = pS
            let attr = createAttr(trimmedSentences, fontSize: fontSize, lineSpacing: lineSpacing)
            if let s = renderStore { s.update(attributedString: attr, layoutWidth: max(100, view.bounds.width - margin * 2)) } 
            else { renderStore = TextKit2RenderStore(attributedString: attr, layoutWidth: max(100, view.bounds.width - margin * 2)) }
            calculateSentenceOffsets(); isUpdatingLayout = false
            currentContentView.update(renderStore: renderStore, highlightIndex: highlightIndex, secondaryIndices: secondaryIndices, isPlaying: isPlaying, paragraphStarts: paragraphStarts, margin: margin, forceRedraw: true)
            updateLayoutFrames()
            
            // 执行无感置换
            if isChapterSwap {
                // 旧的 offset.y 肯定很大（因为它包含了 previousContentHeight）
                // 新的 offset.y 应该减去 previousContentHeight + 80 (间距)
                let adjustment = previousContentHeight + 80
                // 只有当 adjustment 合理时才调整，防止跳变
                if adjustment > 0 {
                    let newY = max(0, scrollView.contentOffset.y - adjustment)
                    scrollView.setContentOffset(CGPoint(x: 0, y: newY), animated: false)
                }
            }
            return true
        }
        
        if nextChanged {
            self.nextSentences = trimmedNextSentences
            let attr = createAttr(trimmedNextSentences, fontSize: fontSize, lineSpacing: lineSpacing)
            if let s = nextRenderStore { s.update(attributedString: attr, layoutWidth: max(100, view.bounds.width - margin * 2)) } 
            else { nextRenderStore = TextKit2RenderStore(attributedString: attr, layoutWidth: max(100, view.bounds.width - margin * 2)) }
            nextContentView.update(renderStore: nextRenderStore, highlightIndex: nil, secondaryIndices: [], isPlaying: false, paragraphStarts: [], margin: margin, forceRedraw: true)
            updateLayoutFrames()
        }
        
        if lastHighlightIndex != highlightIndex || lastSecondaryIndices != secondaryIndices {
            lastHighlightIndex = highlightIndex; lastSecondaryIndices = secondaryIndices
            currentContentView.update(renderStore: renderStore, highlightIndex: highlightIndex, secondaryIndices: secondaryIndices, isPlaying: isPlaying, paragraphStarts: paragraphStarts, margin: margin, forceRedraw: true)
        }
        return false
    }

    private func createAttr(_ sents: [String], fontSize: CGFloat, lineSpacing: CGFloat) -> NSAttributedString {
        let text = sents.joined(separator: "\n")
        let p = NSMutableParagraphStyle()
        p.lineSpacing = lineSpacing
        p.alignment = .justified
        p.firstLineHeadIndent = fontSize * 1.5
        return NSAttributedString(string: text, attributes: [.font: UIFont.systemFont(ofSize: fontSize), .foregroundColor: UIColor.label, .paragraphStyle: p])
    }

    private func calculateSentenceOffsets() {
        guard let s = renderStore else { return }; s.layoutManager.ensureLayout(for: s.contentStorage.documentRange); var o: [CGFloat] = []
        for start in paragraphStarts { if let loc = s.contentStorage.location(s.contentStorage.documentRange.location, offsetBy: start), let f = s.layoutManager.textLayoutFragment(for: loc) { o.append(f.layoutFragmentFrame.minY) } else { o.append(o.last ?? 0) } }
        sentenceYOffsets = o
    }

    private func updateLayoutFrames() {
        guard let s = renderStore else { return }
        var h1: CGFloat = 0; s.layoutManager.enumerateTextLayoutFragments(from: s.contentStorage.documentRange.endLocation, options: [.reverse, .ensuresLayout]) { f in h1 = f.layoutFragmentFrame.maxY; return false }
        let m = (view.bounds.width - s.layoutWidth) / 2
        let topPadding = safeAreaTop + 10
        currentContentView.frame = CGRect(x: m, y: topPadding, width: s.layoutWidth, height: h1)
        
        var totalH = h1 + topPadding
        if let ns = nextRenderStore {
            var h2: CGFloat = 0; ns.layoutManager.enumerateTextLayoutFragments(from: ns.contentStorage.documentRange.endLocation, options: [.reverse, .ensuresLayout]) { f in h2 = f.layoutFragmentFrame.maxY; return false }
            nextContentView.isHidden = false
            nextContentView.frame = CGRect(x: m, y: h1 + topPadding + 80, width: ns.layoutWidth, height: h2) // 80 为章节间距
            totalH += h2 + 100
        } else {
            nextContentView.isHidden = true
        }
        scrollView.contentSize = CGSize(width: view.bounds.width, height: totalH + 200)
    }

    func scrollViewDidScroll(_ s: UIScrollView) {
        if isUpdatingLayout { return }
        let y = s.contentOffset.y - (safeAreaTop + 10)
        
        // 1. 章节切换判定 (无限流核心)
        if y > currentContentView.frame.height + 40 {
            onChapterSwitched?(1) // 滚入下一章
        }
        
        // 2. 预载判定
        if s.contentOffset.y > s.contentSize.height - s.bounds.height * 2 {
            onReachedBottom?()
        }
        
        // 3. 进度汇报
        let idx = sentenceYOffsets.lastIndex(where: { $0 <= y + 5 }) ?? 0
        if idx != lastReportedIndex { lastReportedIndex = idx; onVisibleIndexChanged?(idx) }
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
    func getCurrentCharOffset() -> Int {
        guard let s = renderStore else { return 0 }; let f = s.layoutManager.textLayoutFragment(for: CGPoint(x: 10, y: scrollView.contentOffset.y - (safeAreaTop + 10) + 5))
        return f != nil ? s.contentStorage.offset(from: s.contentStorage.documentRange.location, to: f!.rangeInElement.location) : 0
    }
    func scrollToCharOffset(_ o: Int, animated: Bool) {
        guard let s = renderStore, let loc = s.contentStorage.location(s.contentStorage.documentRange.location, offsetBy: o), let f = s.layoutManager.textLayoutFragment(for: loc) else { return }
        let y = f.layoutFragmentFrame.minY + safeAreaTop + 10; scrollView.setContentOffset(CGPoint(x: 0, y: min(y, max(0, scrollView.contentSize.height - scrollView.bounds.height))), animated: animated)
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
                    for line in f.textLineFragments { let lr = line.typographicBounds.offsetBy(dx: f.layoutFragmentFrame.origin.x, dy: f.layoutFragmentFrame.origin.y); ctx?.addPath(UIBezierPath(roundedRect: lr.insetBy(dx: -2, dy: -1), cornerRadius: 4).cgPath); ctx?.fillPath() }
                    return true
                }
            }
            ctx?.restoreGState()
        }
        let sL = s.layoutManager.textLayoutFragment(for: CGPoint(x: 0, y: rect.minY))?.rangeInElement.location ?? s.contentStorage.documentRange.location
        s.layoutManager.enumerateTextLayoutFragments(from: sL, options: [.ensuresLayout]) { f in
            if f.layoutFragmentFrame.minY > rect.maxY { return false }; if f.layoutFragmentFrame.maxY >= rect.minY { f.draw(at: f.layoutFragmentFrame.origin, in: ctx!) }; return true
        }
    }
}

enum VerticalReaderTask { case scrollToTop; case scrollToIndex(Int) }
