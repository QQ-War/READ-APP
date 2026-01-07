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
    
    // 兼容旧接口与 TTS 高亮支持
    var onAddReplaceRule: ((String) -> Void)?
    var highlightIndex: Int? { didSet { setNeedsDisplay() } }
    var secondaryIndices: Set<Int> = [] { didSet { setNeedsDisplay() } }
    var isPlayingHighlight: Bool = false { didSet { setNeedsDisplay() } }
    var paragraphStarts: [Int] = []
    var chapterPrefixLen: Int = 0
    
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
        
        ctx.saveGState()
        
        // 1. 裁剪区域：只显示本页内容
        let clipRect = CGRect(x: 0, y: info.contentInset, width: bounds.width, height: info.actualContentHeight)
        ctx.clip(to: clipRect)
        
        // 2. 坐标变换：将本页内容映射到屏幕
        let ty = info.contentInset - info.yOffset
        ctx.translateBy(x: horizontalInset, y: ty)
        
        // 3. 绘制 TTS 高亮背景 (在文字底层)
        if isPlayingHighlight {
            ctx.saveGState()
            // 构造需要高亮的索引集合
            let allIndices = ([highlightIndex].compactMap { $0 } + Array(secondaryIndices))
            for i in allIndices {
                guard i < paragraphStarts.count else { continue }
                let start = paragraphStarts[i]
                let end = (i + 1 < paragraphStarts.count) ? paragraphStarts[i + 1] : s.attributedString.length
                let range = NSRange(location: start, length: max(0, end - start))
                
                // 仅当高亮范围与本页有交集时才绘制
                if NSIntersectionRange(range, info.range).length > 0 {
                    let color = (i == highlightIndex) ? UIColor.systemBlue.withAlphaComponent(0.12) : UIColor.systemGreen.withAlphaComponent(0.06)
                    ctx.setFillColor(color.cgColor)
                    
                    if let startLoc = s.contentStorage.location(s.contentStorage.documentRange.location, offsetBy: range.location) {
                        s.layoutManager.enumerateTextLayoutFragments(from: startLoc, options: [.ensuresLayout]) { f in
                            let fRange = s.contentStorage.offset(from: s.contentStorage.documentRange.location, to: f.rangeInElement.location)
                            if fRange >= range.location + range.length { return false }
                            
                            // 绘制高亮矩形
                            let frame = f.layoutFragmentFrame
                            ctx.fill(frame.insetBy(dx: -2, dy: -1))
                            return true
                        }
                    }
                }
            }
            ctx.restoreGState()
        }
        
        // 4. 绘制文字
        let startLoc = s.contentStorage.location(s.contentStorage.documentRange.location, offsetBy: info.range.location)!
        s.layoutManager.enumerateTextLayoutFragments(from: startLoc, options: [.ensuresLayout]) { fragment in
            let frame = fragment.layoutFragmentFrame
            if frame.minY >= info.yOffset + info.actualContentHeight { return false }
            fragment.draw(at: frame.origin, in: ctx)
            return true
        }
        
        ctx.restoreGState()
    }
}
