import SwiftUI
import UIKit

// MARK: - SwiftUI 桥接组件
struct VerticalTextReader: UIViewControllerRepresentable {
    let sentences: [String]
    let fontSize: CGFloat
    let lineSpacing: CGFloat
    let horizontalMargin: CGFloat
    let highlightIndex: Int?
    let secondaryIndices: Set<Int>
    let isPlayingHighlight: Bool
    let chapterUrl: String?
    @Binding var currentVisibleIndex: Int
    @Binding var pendingScrollIndex: Int?
    var forceScrollToTop: Bool = false
    var onScrollFinished: (() -> Void)? // 用于重置置顶标志
    var onAddReplaceRule: ((String) -> Void)?
    
    func makeUIViewController(context: Context) -> VerticalTextViewController {
        let vc = VerticalTextViewController()
        vc.onVisibleIndexChanged = { index in
            DispatchQueue.main.async {
                if currentVisibleIndex != index {
                    currentVisibleIndex = index
                }
            }
        }
        vc.onAddReplaceRule = onAddReplaceRule
        return vc
    }
    
    func updateUIViewController(_ vc: VerticalTextViewController, context: Context) {
        let isContentChanged = vc.update(
            sentences: sentences,
            fontSize: fontSize,
            lineSpacing: lineSpacing,
            margin: horizontalMargin,
            highlightIndex: highlightIndex,
            secondaryIndices: secondaryIndices,
            isPlaying: isPlayingHighlight,
            chapterUrl: chapterUrl
        )
        
        vc.onAddReplaceRule = onAddReplaceRule
        
        if forceScrollToTop {
            vc.scrollToTop(animated: false)
            DispatchQueue.main.async {
                onScrollFinished?()
            }
        } else if let scrollIndex = pendingScrollIndex {
            if isContentChanged {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    vc.scrollToSentence(index: scrollIndex, animated: false)
                }
            } else {
                vc.scrollToSentence(index: scrollIndex, animated: true)
            }
            DispatchQueue.main.async {
                self.pendingScrollIndex = nil
            }
        } else if isPlayingHighlight, let hIndex = highlightIndex {
            vc.ensureSentenceVisible(index: hIndex)
        }
    }
}

// MARK: - UIKit 控制器
class VerticalTextViewController: UIViewController, UIScrollViewDelegate {
    private let scrollView = UIScrollView()
    private let contentView = VerticalTextContentView()
    
    var onVisibleIndexChanged: ((Int) -> Void)?
    var onAddReplaceRule: ((String) -> Void)?
    
    private var renderStore: TextKit2RenderStore?
    private var currentSentences: [String] = []
    private var paragraphStarts: [Int] = []
    private var sentenceYOffsets: [CGFloat] = []
    private var lastReportedIndex: Int = -1
    private var isUpdatingLayout = false
    private var lastTTSSyncIndex: Int = -1
    
    // 缓存上次的高亮状态，用于避免滚动时重复绘制
    private var lastHighlightIndex: Int?
    private var lastSecondaryIndices: Set<Int> = []
    private var lastFontSize: CGFloat = 0
    private var lastLineSpacing: CGFloat = 0
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        
        scrollView.delegate = self
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.showsVerticalScrollIndicator = true
        scrollView.alwaysBounceVertical = true
        scrollView.delaysContentTouches = false 
        view.addSubview(scrollView)
        
        scrollView.addSubview(contentView)
        
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        scrollView.addGestureRecognizer(tap)
        
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        scrollView.addGestureRecognizer(longPress)
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if !isUpdatingLayout {
            scrollView.frame = view.bounds
            updateContentViewFrame()
        }
    }
    
    @objc private func handleTap() {
        NotificationCenter.default.post(name: NSNotification.Name("ReaderToggleControls"), object: nil)
    }
    
    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, let store = renderStore else { return }
        let point = gesture.location(in: contentView)
        if let fragment = store.layoutManager.textLayoutFragment(for: point),
           let textElement = fragment.textElement,
           let nsRange = TextKit2Paginator.rangeFromTextRange(textElement.elementRange, in: store.contentStorage) {
            let text = (store.attributedString.string as NSString).substring(with: nsRange)
            becomeFirstResponder()
            let menu = UIMenuController.shared
            self.pendingSelectedText = text
            menu.showMenu(from: contentView, rect: CGRect(origin: point, size: .zero))
        }
    }
    
    private var pendingSelectedText: String?
    override var canBecomeFirstResponder: Bool { true }
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        return action == #selector(addToReplaceRule)
    }
    @objc func addToReplaceRule() {
        if let text = pendingSelectedText { onAddReplaceRule?(text) }
    }
    
    @discardableResult
    func update(
        sentences: [String],
        fontSize: CGFloat,
        lineSpacing: CGFloat,
        margin: CGFloat,
        highlightIndex: Int?,
        secondaryIndices: Set<Int>,
        isPlaying: Bool,
        chapterUrl: String?
    ) -> Bool {
        // 关键：检查内容是否真正变化
        let contentChanged = self.currentSentences != sentences || lastFontSize != fontSize || lastLineSpacing != lineSpacing
        let highlightChanged = lastHighlightIndex != highlightIndex || lastSecondaryIndices != secondaryIndices
        
        if contentChanged || renderStore == nil {
            self.currentSentences = sentences
            self.lastFontSize = fontSize
            self.lastLineSpacing = lineSpacing
            isUpdatingLayout = true
            
            let fullText = sentences.joined(separator: "\n")
            var starts: [Int] = []
            var currentPos = 0
            for s in sentences {
                starts.append(currentPos)
                currentPos += s.count + 1 
            }
            self.paragraphStarts = starts
            
            let attrString = createAttributedString(fullText, fontSize: fontSize, lineSpacing: lineSpacing)
            if let store = renderStore {
                store.update(attributedString: attrString, layoutWidth: view.bounds.width - margin * 2)
            } else {
                renderStore = TextKit2RenderStore(attributedString: attrString, layoutWidth: view.bounds.width - margin * 2)
            }
            
            calculateSentenceOffsets()
            updateContentViewFrame()
            
            lastHighlightIndex = highlightIndex
            lastSecondaryIndices = secondaryIndices
            contentView.update(renderStore: renderStore, highlightIndex: highlightIndex, secondaryIndices: secondaryIndices, isPlaying: isPlaying, paragraphStarts: paragraphStarts, margin: margin, forceRedraw: true)
            
            isUpdatingLayout = false
            return true
        } else if highlightChanged {
            lastHighlightIndex = highlightIndex
            lastSecondaryIndices = secondaryIndices
            contentView.update(renderStore: renderStore, highlightIndex: highlightIndex, secondaryIndices: secondaryIndices, isPlaying: isPlaying, paragraphStarts: paragraphStarts, margin: margin, forceRedraw: true)
        }
        
        return false
    }
    
    private func createAttributedString(_ text: String, fontSize: CGFloat, lineSpacing: CGFloat) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = lineSpacing
        paragraphStyle.paragraphSpacing = lineSpacing * 0.8
        paragraphStyle.alignment = .justified
        
        return NSAttributedString(string: text, attributes: [
            .font: UIFont.systemFont(ofSize: fontSize),
            .foregroundColor: UIColor.label,
            .paragraphStyle: paragraphStyle
        ])
    }
    
    private func calculateSentenceOffsets() {
        guard let store = renderStore else { return }
        let lm = store.layoutManager
        let cs = store.contentStorage
        lm.ensureLayout(for: cs.documentRange)
        
        var offsets: [CGFloat] = []
        for start in paragraphStarts {
            if let loc = cs.location(cs.documentRange.location, offsetBy: start),
               let fragment = lm.textLayoutFragment(for: loc) {
                offsets.append(fragment.layoutFragmentFrame.minY)
            } else {
                offsets.append(offsets.last ?? 0)
            }
        }
        self.sentenceYOffsets = offsets
    }
    
    private func updateContentViewFrame() {
        guard let store = renderStore else { return }
        let docRange = store.contentStorage.documentRange
        store.layoutManager.ensureLayout(for: docRange)
        
        var totalHeight: CGFloat = 0
        store.layoutManager.enumerateTextLayoutFragments(from: docRange.endLocation, options: [.reverse, .ensuresLayout]) { fragment in
            totalHeight = fragment.layoutFragmentFrame.maxY
            return false
        }
        
        let m = (view.bounds.width - store.layoutWidth) / 2
        contentView.frame = CGRect(x: m, y: 40, width: store.layoutWidth, height: totalHeight)
        scrollView.contentSize = CGSize(width: view.bounds.width, height: totalHeight + 150)
    }
    
    func scrollToSentence(index: Int, animated: Bool) {
        guard index >= 0 && index < sentenceYOffsets.count else { return }
        let targetY = max(0, sentenceYOffsets[index] + 40)
        let maxScroll = max(0, scrollView.contentSize.height - scrollView.bounds.height)
        scrollView.setContentOffset(CGPoint(x: 0, y: min(targetY, maxScroll)), animated: animated)
    }
    
    func ensureSentenceVisible(index: Int) {
        guard index >= 0 && index < sentenceYOffsets.count else { return }
        guard index != lastTTSSyncIndex else { return }
        let targetY = sentenceYOffsets[index] + 40
        let currentOffset = scrollView.contentOffset.y
        let viewportHeight = scrollView.bounds.height
        if targetY < currentOffset + 50 || targetY > currentOffset + viewportHeight - 150 {
            lastTTSSyncIndex = index
            scrollView.setContentOffset(CGPoint(x: 0, y: max(0, targetY - 100)), animated: true)
        }
    }
    
    func scrollToTop(animated: Bool) {
        scrollView.setContentOffset(.zero, animated: animated)
    }
    
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !isUpdatingLayout else { return }
        let y = scrollView.contentOffset.y - 40
        let index = sentenceYOffsets.lastIndex(where: { $0 <= y + 5 }) ?? 0
        if index != lastReportedIndex {
            lastReportedIndex = index
            onVisibleIndexChanged?(index)
        }
    }
}

class VerticalTextContentView: UIView {
    private var renderStore: TextKit2RenderStore?
    private var highlightIndex: Int?
    private var secondaryIndices: Set<Int> = []
    private var isPlayingHighlight: Bool = false
    private var paragraphStarts: [Int] = []
    private var margin: CGFloat = 20
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        self.backgroundColor = .clear
    }
    required init?(coder: NSCoder) { fatalError() }
    
    func update(renderStore: TextKit2RenderStore?, highlightIndex: Int?, secondaryIndices: Set<Int>, isPlaying: Bool, paragraphStarts: [Int], margin: CGFloat, forceRedraw: Bool) {
        self.renderStore = renderStore
        self.highlightIndex = highlightIndex
        self.secondaryIndices = secondaryIndices
        self.isPlayingHighlight = isPlaying
        self.paragraphStarts = paragraphStarts
        self.margin = margin
        if forceRedraw { setNeedsDisplay() }
    }
    
    override func draw(_ rect: CGRect) {
        guard let store = renderStore else { return }
        let context = UIGraphicsGetCurrentContext()
        
        if isPlayingHighlight {
            context?.saveGState()
            let highlightIndices = ([highlightIndex].compactMap { $0 }) + Array(secondaryIndices)
            for index in highlightIndices {
                guard index < paragraphStarts.count else { continue }
                let start = paragraphStarts[index]
                let end = (index + 1 < paragraphStarts.count) ? paragraphStarts[index + 1] : store.attributedString.length
                let range = NSRange(location: start, length: max(0, end - start))
                let color = (index == highlightIndex) ? UIColor.systemBlue.withAlphaComponent(0.15) : UIColor.systemGreen.withAlphaComponent(0.08)
                context?.setFillColor(color.cgColor)
                
                let startLoc = store.contentStorage.location(store.contentStorage.documentRange.location, offsetBy: range.location)!
                store.layoutManager.enumerateTextLayoutFragments(from: startLoc, options: [.ensuresLayout]) { fragment in
                    let fFrame = fragment.layoutFragmentFrame
                    let fOffset = store.contentStorage.offset(from: store.contentStorage.documentRange.location, to: fragment.rangeInElement.location)
                    if fOffset >= NSMaxRange(range) { return false }
                    // 高亮背景稍微拓宽
                    let highlightRect = CGRect(x: -20, y: fFrame.minY, width: bounds.width + 40, height: fFrame.height)
                    context?.fill(highlightRect)
                    return true
                }
            }
            context?.restoreGState()
        }
        
        // 优化：从 rect.minY 附近的 location 开始枚举，而不是从文档开头
        let startPoint = CGPoint(x: 0, y: rect.minY)
        let startLocation = store.layoutManager.textLayoutFragment(for: startPoint)?.rangeInElement.location ?? store.contentStorage.documentRange.location
        
        store.layoutManager.enumerateTextLayoutFragments(from: startLocation, options: [.ensuresLayout]) { fragment in
            let frame = fragment.layoutFragmentFrame
            if frame.minY > rect.maxY { return false }
            if frame.maxY < rect.minY { return true }
            fragment.draw(at: frame.origin, in: context!)
            return true
        }
    }
}
