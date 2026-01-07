import UIKit

// MARK: - TextKit 2 渲染存储
class TextKit2RenderStore {
    let contentStorage = NSTextContentStorage()
    let layoutManager = NSTextLayoutManager()
    let textContainer = NSTextContainer(size: .zero)
    var attributedString: NSAttributedString = NSAttributedString()
    var layoutWidth: CGFloat = 0
    
    init(attributedString: NSAttributedString, layoutWidth: CGFloat) {
        self.attributedString = attributedString
        self.layoutWidth = layoutWidth
        setup()
    }
    
    private func setup() {
        contentStorage.addTextLayoutManager(layoutManager)
        textContainer.widthTracksTextView = false
        textContainer.heightTracksTextView = false
        textContainer.lineFragmentPadding = 0 
        layoutManager.textContainer = textContainer
        update(attributedString: attributedString, layoutWidth: layoutWidth)
    }
    
    func update(attributedString: NSAttributedString, layoutWidth: CGFloat) {
        self.attributedString = attributedString
        self.layoutWidth = layoutWidth
        contentStorage.attributedString = attributedString
        textContainer.size = CGSize(width: layoutWidth, height: .greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: contentStorage.documentRange)
    }
}

// MARK: - 分页引擎
struct TextKit2Paginator {
    struct PaginationResult {
        let pages: [PaginatedPage]
        let pageInfos: [TK2PageInfo]
    }
    
    static func paginate(renderStore: TextKit2RenderStore, pageSize: CGSize, paragraphStarts: [Int], prefixLen: Int, topInset: CGFloat, bottomInset: CGFloat) -> PaginationResult {
        let lm = renderStore.layoutManager
        let storage = renderStore.contentStorage
        lm.ensureLayout(for: storage.documentRange)
        
        var pages: [PaginatedPage] = []
        var pageInfos: [TK2PageInfo] = []
        
        // 关键：计算真正的可用高度
        let usableHeight = pageSize.height - topInset - bottomInset
        var currentY: CGFloat = 0
        
        // 确保布局完成
        lm.ensureLayout(for: storage.documentRange)
        
        while true {
            let rangeStartLocation = lm.textLayoutFragment(for: CGPoint(x: 0, y: currentY))?.rangeInElement.location ?? storage.documentRange.endLocation
            let startOffset = storage.offset(from: storage.documentRange.location, to: rangeStartLocation)
            
            if startOffset >= attributedStringLength(storage) { break }
            
            let startSentenceIdx = paragraphStarts.lastIndex(where: { $0 <= startOffset }) ?? 0
            
            // 找到本页结束位置：通过在 Y 轴上步进
            let targetY = currentY + usableHeight
            let endFragment = lm.textLayoutFragment(for: CGPoint(x: 0, y: targetY - 0.1))
            let endLocation = endFragment?.rangeInElement.endLocation ?? storage.documentRange.endLocation
            let endOffset = storage.offset(from: storage.documentRange.location, to: endLocation)
            
            let pageRange = NSRange(location: startOffset, length: max(1, endOffset - startOffset))
            
            pages.append(PaginatedPage(globalRange: pageRange, startSentenceIndex: startSentenceIdx))
            pageInfos.append(TK2PageInfo(
                range: pageRange,
                yOffset: currentY,
                pageHeight: pageSize.height,
                actualContentHeight: usableHeight,
                startSentenceIndex: startSentenceIdx,
                contentInset: topInset
            ))
            
            // 逻辑步进：下一页的起点必须是 endFragment 的位置
            currentY = endFragment?.layoutFragmentFrame.maxY ?? (currentY + usableHeight)
            
            if currentY >= lm.usageBoundsForTextContainer.height { break }
        }
        
        return PaginationResult(pages: pages, pageInfos: pageInfos)
    }
    
    private static func attributedStringLength(_ storage: NSTextContentStorage) -> Int {
        return storage.attributedString?.length ?? 0
    }
    
    static func rangeFromTextRange(_ textRange: NSTextRange, in storage: NSTextContentStorage) -> NSRange? {
        let start = storage.offset(from: storage.documentRange.location, to: textRange.location)
        let end = storage.offset(from: storage.documentRange.location, to: textRange.endLocation)
        return NSRange(location: start, length: end - start)
    }
}

// MARK: - 渲染视图
class ReadContent2View: UIView {
    var renderStore: TextKit2RenderStore?
    var pageInfo: TK2PageInfo? { didSet { setNeedsDisplay() } }
    var horizontalInset: CGFloat = 16
    var onTapLocation: ((ReaderTapLocation) -> Void)?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        self.backgroundColor = .clear
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    @objc private func handleTap(_ g: UITapGestureRecognizer) {
        let x = g.location(in: self).x
        if x < bounds.width * 0.3 { onTapLocation?(.left) }
        else if x > bounds.width * 0.7 { onTapLocation?(.right) }
        else { onTapLocation?(.middle) }
    }
    
    override func draw(_ rect: CGRect) {
        guard let s = renderStore, let info = pageInfo else { return }
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        
        // 关键修复：渲染位移必须完全抵消分页时的 yOffset，并叠加 contentInset
        ctx.saveGState()
        
        // 我们只在 contentInset 指定的区域内绘制
        let clipRect = CGRect(x: 0, y: info.contentInset, width: bounds.width, height: info.actualContentHeight)
        ctx.clip(to: clipRect)
        
        // 这里的数学逻辑：
        // 1. 文字在 RenderStore 的纵向坐标是全局的。
        // 2. 我们要把属于本页的文字（从 info.yOffset 开始）挪到屏幕的 info.contentInset 位置。
        let ty = info.contentInset - info.yOffset
        ctx.translateBy(x: horizontalInset, y: ty)
        
        let startLoc = s.contentStorage.location(s.contentStorage.documentRange.location, offsetBy: info.range.location)!
        s.layoutManager.enumerateTextLayoutFragments(from: startLoc, options: [.ensuresLayout]) { fragment in
            let frame = fragment.layoutFragmentFrame
            // 如果已经画过了本页范围，停止
            if frame.minY >= info.yOffset + info.actualContentHeight { return false }
            fragment.draw(at: frame.origin, in: ctx)
            return true
        }
        
        ctx.restoreGState()
    }
}