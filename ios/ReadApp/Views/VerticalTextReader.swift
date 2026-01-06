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
    
    func makeUIViewController(context: Context) -> VerticalTextViewController {
        let vc = VerticalTextViewController()
        vc.onVisibleIndexChanged = { index in
            if currentVisibleIndex != index {
                currentVisibleIndex = index
            }
        }
        return vc
    }
    
    func updateUIViewController(_ vc: VerticalTextViewController, context: Context) {
        vc.update(
            sentences: sentences,
            fontSize: fontSize,
            lineSpacing: lineSpacing,
            margin: horizontalMargin,
            highlightIndex: highlightIndex,
            secondaryIndices: secondaryIndices,
            isPlaying: isPlayingHighlight,
            chapterUrl: chapterUrl
        )
        
        if let scrollIndex = pendingScrollIndex {
            vc.scrollToSentence(index: scrollIndex, animated: true)
            DispatchQueue.main.async {
                self.pendingScrollIndex = nil
            }
        }
    }
}

// MARK: - UIKit 控制器
class VerticalTextViewController: UIViewController, UIScrollViewDelegate {
    private let scrollView = UIScrollView()
    private let contentView = VerticalTextContentView()
    
    var onVisibleIndexChanged: ((Int) -> Void)?
    
    private var renderStore: TextKit2RenderStore?
    private var sentences: [String] = []
    private var paragraphStarts: [Int] = []
    private var sentenceYOffsets: [CGFloat] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        
        scrollView.delegate = self
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.showsVerticalScrollIndicator = true
        view.addSubview(scrollView)
        
        scrollView.addSubview(contentView)
        
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        scrollView.addGestureRecognizer(tap)
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        scrollView.frame = view.bounds
        updateContentViewFrame()
    }
    
    @objc private func handleTap() {
        // 通知外部展示/隐藏菜单（通过响应链或通知）
        NotificationCenter.default.post(name: NSNotification.Name("ReaderToggleControls"), object: nil)
    }
    
    func update(
        sentences: [String],
        fontSize: CGFloat,
        lineSpacing: CGFloat,
        margin: CGFloat,
        highlightIndex: Int?,
        secondaryIndices: Set<Int>,
        isPlaying: Bool,
        chapterUrl: String?
    ) {
        let isNewContent = self.sentences != sentences
        self.sentences = sentences
        
        if isNewContent || renderStore == nil {
            let fullText = sentences.joined(separator: "\n")
            var starts: [Int] = []
            var currentPos = 0
            for s in sentences {
                starts.append(currentPos)
                currentPos += s.count + 1 // +1 for \n
            }
            self.paragraphStarts = starts
            
            let attrString = createAttributedString(fullText, fontSize: fontSize, lineSpacing: lineSpacing)
            if let store = renderStore {
                store.update(attributedString: attrString, layoutWidth: view.bounds.width - margin * 2)
            } else {
                renderStore = TextKit2RenderStore(attributedString: attrString, layoutWidth: view.bounds.width - margin * 2)
            }
            
            // 计算每个段落的 Y 偏移以供快速跳转和进度追踪
            calculateSentenceOffsets(margin: margin)
            updateContentViewFrame()
        }
        
        contentView.update(
            renderStore: renderStore,
            highlightIndex: highlightIndex,
            secondaryIndices: secondaryIndices,
            isPlaying: isPlaying,
            paragraphStarts: paragraphStarts,
            margin: margin
        )
    }
    
    private func createAttributedString(_ text: String, fontSize: CGFloat, lineSpacing: CGFloat) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = lineSpacing
        paragraphStyle.paragraphSpacing = lineSpacing * 1.5
        
        return NSAttributedString(string: text, attributes: [
            .font: UIFont.systemFont(ofSize: fontSize),
            .foregroundColor: UIColor.label,
            .paragraphStyle: paragraphStyle
        ])
    }
    
    private func calculateSentenceOffsets(margin: CGFloat) {
        guard let store = renderStore else { return }
        let lm = store.layoutManager
        let cs = store.contentStorage
        
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
        
        // 获取最后一行的位置来确定内容总高度
        var totalHeight: CGFloat = 0
        store.layoutManager.enumerateTextLayoutFragments(from: docRange.endLocation, options: [.reverse, .ensuresLayout]) { fragment in
            totalHeight = fragment.layoutFragmentFrame.maxY
            return false
        }
        
        let margin = contentView.margin
        contentView.frame = CGRect(x: margin, y: 40, width: view.bounds.width - margin * 2, height: totalHeight)
        scrollView.contentSize = CGSize(width: view.bounds.width, height: totalHeight + 100)
    }
    
    func scrollToSentence(index: Int, animated: Bool) {
        guard index >= 0 && index < sentenceYOffsets.count else { return }
        let y = sentenceYOffsets[index] + 40 // +40 matching content offset
        scrollView.setContentOffset(CGPoint(x: 0, y: y), animated: animated)
    }
    
    // MARK: - UIScrollViewDelegate
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let y = scrollView.contentOffset.y - 40
        // 使用二分查找快速确定当前可见段落索引
        let index = sentenceYOffsets.lastIndex(where: { $0 <= y + 10 }) ?? 0
        onVisibleIndexChanged?(index)
    }
}

// MARK: - 渲染视图
class VerticalTextContentView: UIView {
    private(set) var margin: CGFloat = 20
    private var renderStore: TextKit2RenderStore?
    private var highlightIndex: Int?
    private var secondaryIndices: Set<Int> = []
    private var isPlayingHighlight: Bool = false
    private var paragraphStarts: [Int] = []
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        self.backgroundColor = .clear
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    func update(
        renderStore: TextKit2RenderStore?,
        highlightIndex: Int?,
        secondaryIndices: Set<Int>,
        isPlaying: Bool,
        paragraphStarts: [Int],
        margin: CGFloat
    ) {
        self.renderStore = renderStore
        self.highlightIndex = highlightIndex
        self.secondaryIndices = secondaryIndices
        self.isPlayingHighlight = isPlaying
        self.paragraphStarts = paragraphStarts
        self.margin = margin
        setNeedsDisplay()
    }
    
    override func draw(_ rect: CGRect) {
        guard let store = renderStore else { return }
        let context = UIGraphicsGetCurrentContext()
        
        // 1. 渲染高亮背景
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
                
                let startLoc = store.contentStorage.location(store.contentStorage.documentRange.location, offsetBy: range.location)
                store.layoutManager.enumerateTextLayoutFragments(from: startLoc, options: [.ensuresLayout]) { fragment in
                    let fFrame = fragment.layoutFragmentFrame
                    let fRangeLocation = store.contentStorage.offset(from: store.contentStorage.documentRange.location, to: fragment.rangeInElement.location)
                    
                    if fRangeLocation >= NSMaxRange(range) { return false }
                    
                    // 简化处理：垂直模式下对整个段落的 Fragment 进行着色
                    let highlightRect = CGRect(x: -margin, y: fFrame.minY, width: bounds.width + margin * 2, height: fFrame.height)
                    context?.fill(highlightRect)
                    return true
                }
            }
            context?.restoreGState()
        }
        
        // 2. 绘制文本
        // 只绘制当前可见区域的内容 (rect 参数提供了当前需要重绘的范围)
        let visibleRange = store.contentStorage.documentRange
        store.layoutManager.enumerateTextLayoutFragments(from: visibleRange.location, options: [.ensuresLayout]) { fragment in
            let frame = fragment.layoutFragmentFrame
            // 脏矩形裁剪，只绘制相交的部分
            if frame.intersects(rect) {
                fragment.draw(at: frame.origin, in: context!)
            }
            return frame.minY < rect.maxY
        }
    }
}
