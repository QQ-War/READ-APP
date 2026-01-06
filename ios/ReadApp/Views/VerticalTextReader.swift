import SwiftUI
import UIKit

// MARK: - SwiftUI 桥接组件
struct VerticalTextReader: UIViewControllerRepresentable {
    let sentences: [String]; let fontSize: CGFloat; let lineSpacing: CGFloat; let horizontalMargin: CGFloat; let highlightIndex: Int?; let secondaryIndices: Set<Int>; let isPlayingHighlight: Bool; let chapterUrl: String?
    @Binding var currentVisibleIndex: Int; @Binding var pendingScrollIndex: Int?
    var forceScrollToTop: Bool = false; var onScrollFinished: (() -> Void)? ; var onAddReplaceRule: ((String) -> Void)? ; var onTapMenu: (() -> Void)?
    var safeAreaTop: CGFloat = 0 // 传入安全区
    
    func makeUIViewController(context: Context) -> VerticalTextViewController {
        let vc = VerticalTextViewController(); vc.onVisibleIndexChanged = { i in DispatchQueue.main.async { if currentVisibleIndex != i { currentVisibleIndex = i } } }; vc.onAddReplaceRule = onAddReplaceRule; vc.onTapMenu = onTapMenu; return vc
    }
    
    func updateUIViewController(_ vc: VerticalTextViewController, context: Context) {
        vc.onAddReplaceRule = onAddReplaceRule; vc.onTapMenu = onTapMenu; vc.safeAreaTop = safeAreaTop
        let changed = vc.update(sentences: sentences, fontSize: fontSize, lineSpacing: lineSpacing, margin: horizontalMargin, highlightIndex: highlightIndex, secondaryIndices: secondaryIndices, isPlaying: isPlayingHighlight)
        if forceScrollToTop { vc.scrollToTop(animated: false); DispatchQueue.main.async { onScrollFinished?() } }
        else if let sI = pendingScrollIndex { if changed { DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { vc.scrollToSentence(index: sI, animated: false) } } else { vc.scrollToSentence(index: sI, animated: true) }; DispatchQueue.main.async { self.pendingScrollIndex = nil } }
        else if isPlayingHighlight, let hI = highlightIndex { vc.ensureSentenceVisible(index: hI) }
    }
}

// MARK: - UIKit 控制器
class VerticalTextViewController: UIViewController, UIScrollViewDelegate {
    let scrollView = UIScrollView(); private let contentView = VerticalTextContentView()
    var onVisibleIndexChanged: ((Int) -> Void)?; var onAddReplaceRule: ((String) -> Void)?; var onTapMenu: (() -> Void)?; var chapterUrl: String?
    var safeAreaTop: CGFloat = 0 
    private var renderStore: TextKit2RenderStore?; private var currentSentences: [String] = []; private var paragraphStarts: [Int] = []; private var sentenceYOffsets: [CGFloat] = []
    private var lastReportedIndex: Int = -1; private var isUpdatingLayout = false; private var lastTTSSyncIndex: Int = -1; private var pendingTask: VerticalReaderTask?
    private var lastHighlightIndex: Int?; private var lastSecondaryIndices: Set<Int> = []; private var lastFontSize: CGFloat = 0; private var lastLineSpacing: CGFloat = 0; private var lastMargin: CGFloat = 20
    
    override func viewDidLoad() {
        super.viewDidLoad()
        scrollView.delegate = self; scrollView.contentInsetAdjustmentBehavior = .never; scrollView.showsVerticalScrollIndicator = true; scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView); scrollView.addSubview(contentView)
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap)); scrollView.addGestureRecognizer(tap)
        let lp = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress)); scrollView.addGestureRecognizer(lp)
    }
    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); if !isUpdatingLayout { scrollView.frame = view.bounds; updateContentViewFrame() } }
    @objc private func handleTap() { onTapMenu?() }
    @objc private func handleLongPress(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began, let s = renderStore else { return }
        let p = g.location(in: contentView)
        if let f = s.layoutManager.textLayoutFragment(for: p), let te = f.textElement, let r = TextKit2Paginator.rangeFromTextRange(te.elementRange, in: s.contentStorage) {
            let txt = (s.attributedString.string as NSString).substring(with: r)
            becomeFirstResponder(); self.pendingSelectedText = txt; UIMenuController.shared.showMenu(from: contentView, rect: CGRect(origin: p, size: .zero))
        }
    }
    private var pendingSelectedText: String?; override var canBecomeFirstResponder: Bool { true }
    override func canPerformAction(_ a: Selector, withSender s: Any?) -> Bool { return a == #selector(addToReplaceRule) }
    @objc func addToReplaceRule() { if let t = pendingSelectedText { onAddReplaceRule?(t) } }
    
    @discardableResult
    func update(sentences: [String], fontSize: CGFloat, lineSpacing: CGFloat, margin: CGFloat, highlightIndex: Int?, secondaryIndices: Set<Int>, isPlaying: Bool) -> Bool {
        self.lastMargin = margin
        if currentSentences != sentences || lastFontSize != fontSize || lastLineSpacing != lineSpacing || renderStore == nil {
            currentSentences = sentences; lastFontSize = fontSize; lastLineSpacing = lineSpacing; isUpdatingLayout = true
            var pS: [Int] = []; var cP = 0; for s in sentences { pS.append(cP); cP += s.count + 1 }; paragraphStarts = pS
            let attr = NSAttributedString(string: sentences.joined(separator: "\n"), attributes: [.font: UIFont.systemFont(ofSize: fontSize), .foregroundColor: UIColor.label, .paragraphStyle: { let p = NSMutableParagraphStyle(); p.lineSpacing = lineSpacing; p.alignment = .justified; return p }() ])
            if let s = renderStore { s.update(attributedString: attr, layoutWidth: max(100, view.bounds.width - margin * 2)) } 
            else { renderStore = TextKit2RenderStore(attributedString: attr, layoutWidth: max(100, view.bounds.width - margin * 2)) }
            renderStore?.textContainer.lineFragmentPadding = 8
            calculateSentenceOffsets(); updateContentViewFrame(); isUpdatingLayout = false; executePendingTask()
            contentView.update(renderStore: renderStore, highlightIndex: highlightIndex, secondaryIndices: secondaryIndices, isPlaying: isPlaying, paragraphStarts: paragraphStarts, margin: margin, forceRedraw: true)
            return true
        } else if lastHighlightIndex != highlightIndex || lastSecondaryIndices != secondaryIndices {
            lastHighlightIndex = highlightIndex; lastSecondaryIndices = secondaryIndices
            contentView.update(renderStore: renderStore, highlightIndex: highlightIndex, secondaryIndices: secondaryIndices, isPlaying: isPlaying, paragraphStarts: paragraphStarts, margin: margin, forceRedraw: true)
        }
        return false
    }
    private func calculateSentenceOffsets() {
        guard let s = renderStore else { return }; s.layoutManager.ensureLayout(for: s.contentStorage.documentRange); var o: [CGFloat] = []
        for start in paragraphStarts { if let loc = s.contentStorage.location(s.contentStorage.documentRange.location, offsetBy: start), let f = s.layoutManager.textLayoutFragment(for: loc) { o.append(f.layoutFragmentFrame.minY) } else { o.append(o.last ?? 0) } }
        sentenceYOffsets = o
    }
    private func updateContentViewFrame() {
        guard let s = renderStore else { return }; var h: CGFloat = 0; s.layoutManager.enumerateTextLayoutFragments(from: s.contentStorage.documentRange.endLocation, options: [.reverse, .ensuresLayout]) { f in h = f.layoutFragmentFrame.maxY; return false }
        let m = (view.bounds.width - s.layoutWidth) / 2
        contentView.frame = CGRect(x: m, y: safeAreaTop + 10, width: s.layoutWidth, height: h); scrollView.contentSize = CGSize(width: view.bounds.width, height: h + safeAreaTop + 120)
    }
    private func executePendingTask() {
        guard let t = pendingTask, !isUpdatingLayout else { return }
        switch t { case .scrollToTop: scrollToTop(animated: false); case .scrollToIndex(let i): scrollToSentence(index: i, animated: false) }; pendingTask = nil
    }
    func setPendingTask(_ t: VerticalReaderTask) { pendingTask = t; if !isUpdatingLayout { executePendingTask() } }
    func scrollToSentence(index: Int, animated: Bool) { guard index >= 0 && index < sentenceYOffsets.count else { return }; let y = max(0, sentenceYOffsets[index] + safeAreaTop + 10); scrollView.setContentOffset(CGPoint(x: 0, y: min(y, max(0, scrollView.contentSize.height - scrollView.bounds.height))), animated: animated) }
    func ensureSentenceVisible(index: Int) {
        guard !scrollView.isDragging && !scrollView.isDecelerating, index >= 0 && index < sentenceYOffsets.count, index != lastTTSSyncIndex else { return }
        let y = sentenceYOffsets[index] + safeAreaTop + 10; let cur = scrollView.contentOffset.y; let vH = scrollView.bounds.height
        if y < cur + 50 || y > cur + vH - 150 { lastTTSSyncIndex = index; scrollView.setContentOffset(CGPoint(x: 0, y: max(0, y - vH / 3)), animated: true) }
    }
    func scrollToTop(animated: Bool) { scrollView.setContentOffset(.zero, animated: animated) }
    func getCurrentCharOffset() -> Int {
        guard let s = renderStore else { return 0 }; let topY = scrollView.contentOffset.y - (safeAreaTop + 10) + 5
        if let f = s.layoutManager.textLayoutFragment(for: CGPoint(x: 10, y: topY)) { return s.contentStorage.offset(from: s.contentStorage.documentRange.location, to: f.rangeInElement.location) }; return 0
    }
    func scrollToCharOffset(_ o: Int, animated: Bool) {
        guard let s = renderStore, let loc = s.contentStorage.location(s.contentStorage.documentRange.location, offsetBy: o), let f = s.layoutManager.textLayoutFragment(for: loc) else { return }
        let y = f.layoutFragmentFrame.minY + safeAreaTop + 10; scrollView.setContentOffset(CGPoint(x: 0, y: min(y, max(0, scrollView.contentSize.height - scrollView.bounds.height))), animated: animated)
    }
    func scrollViewDidScroll(_ s: UIScrollView) { if !isUpdatingLayout { let idx = sentenceYOffsets.lastIndex(where: { $0 <= s.contentOffset.y - (safeAreaTop + 10) + 5 }) ?? 0; if idx != lastReportedIndex { lastReportedIndex = idx; onVisibleIndexChanged?(idx) } } }
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