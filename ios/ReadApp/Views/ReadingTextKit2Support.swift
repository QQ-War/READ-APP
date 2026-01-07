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
        
        // 关键优化：给可用高度留出 8pt 的呼吸空间，防止底行文字紧贴边缘
        let safeBottomPadding: CGFloat = 8.0
        let usableHeight = max(100, pageSize.height - topInset - bottomInset - safeBottomPadding)
        var currentY: CGFloat = 0
        
        lm.ensureLayout(for: storage.documentRange)
        
        while true {
            let rangeStartLocation = lm.textLayoutFragment(for: CGPoint(x: 0, y: currentY))?.rangeInElement.location ?? storage.documentRange.endLocation
            let startOffset = storage.offset(from: storage.documentRange.location, to: rangeStartLocation)
            
            if startOffset >= attributedStringLength(storage) { break }
            
            let startSentenceIdx = paragraphStarts.lastIndex(where: { $0 <= startOffset }) ?? 0
            
            // 查找本页理论结束位置附近的 Fragment
            let targetY = currentY + usableHeight
            // 往回一点点探测，获取位于底部的那个 Fragment
            guard let endFragment = lm.textLayoutFragment(for: CGPoint(x: 0, y: targetY - 5.0)) else {
                // 如果探测不到，说明可能已经到底或者空白，尝试直接用 targetY
                 if let fallback = lm.textLayoutFragment(for: CGPoint(x: 0, y: targetY)) {
                     // 找到了（虽然不太可能，因为 -5 都没找到）
                     let endOffset = storage.offset(from: storage.documentRange.location, to: fallback.rangeInElement.endLocation)
                     let pageRange = NSRange(location: startOffset, length: max(1, endOffset - startOffset))
                     pages.append(PaginatedPage(globalRange: pageRange, startSentenceIndex: startSentenceIdx))
                     pageInfos.append(TK2PageInfo(range: pageRange, yOffset: currentY, pageHeight: pageSize.height, actualContentHeight: fallback.layoutFragmentFrame.maxY - currentY, startSentenceIndex: startSentenceIdx, contentInset: topInset))
                     currentY = fallback.layoutFragmentFrame.maxY
                     if currentY >= lm.usageBoundsForTextContainer.height { break }
                     continue
                 } else {
                     // 真的没内容了
                     break
                 }
            }
            
            var pageEndOffset: Int = 0
            var nextPageStartY: CGFloat = 0
            
            // 核心判定：防截断逻辑
            // 如果该行的底部超出了本页可用高度
            if endFragment.layoutFragmentFrame.maxY > targetY {
                let fragmentStartOffset = storage.offset(from: storage.documentRange.location, to: endFragment.rangeInElement.location)
                
                // Case 1: 这一行不是本页的第一行 -> 把它推到下一页
                if fragmentStartOffset > startOffset {
                    pageEndOffset = fragmentStartOffset
                    nextPageStartY = endFragment.layoutFragmentFrame.minY
                } 
                // Case 2: 这一行是本页第一行（超大字号占满整页） -> 只能强行放入
                else {
                    pageEndOffset = storage.offset(from: storage.documentRange.location, to: endFragment.rangeInElement.endLocation)
                    nextPageStartY = endFragment.layoutFragmentFrame.maxY
                }
            } else {
                // Case 3: 完全在界内 -> 正常包含
                pageEndOffset = storage.offset(from: storage.documentRange.location, to: endFragment.rangeInElement.endLocation)
                nextPageStartY = endFragment.layoutFragmentFrame.maxY
            }
            
            let pageRange = NSRange(location: startOffset, length: pageEndOffset - startOffset)
            
            // 记录分页信息
            pages.append(PaginatedPage(globalRange: pageRange, startSentenceIndex: startSentenceIdx))
            pageInfos.append(TK2PageInfo(
                range: pageRange,
                yOffset: currentY,
                pageHeight: pageSize.height,
                actualContentHeight: nextPageStartY - currentY, // 记录真实的排版高度
                startSentenceIndex: startSentenceIdx,
                contentInset: topInset
            ))
            
            // 步进
            currentY = nextPageStartY
            
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

// MARK: - 渲染视图 (视口对齐版)
class ReadContent2View: UIView {
    var renderStore: TextKit2RenderStore?
    var pageInfo: TK2PageInfo? {
        didSet {
            guard let info = pageInfo else { return }
            // 核心逻辑修改：直接移动 View 的视口 (Bounds) 去找文字
            // 让 Bounds 的原点 y 对应 (文字起始y - 顶部留白)
            // 这样，yOffset 处的文字就会正好绘制在 topInset 处
            let viewportY = info.yOffset - info.contentInset
            self.bounds.origin = CGPoint(x: 0, y: viewportY)
            setNeedsDisplay()
        }
    }
    
    var horizontalInset: CGFloat = 16
    var onTapLocation: ((ReaderTapLocation) -> Void)?
    
    // 兼容属性
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
        
        // 1. 无需 translate，直接偏移 horizontalInset 即可
        // 因为 bounds.origin.y 已经被设为了 (yOffset - topInset)
        // 所以原始坐标 yOffset 会自动对应屏幕坐标 topInset
        ctx.translateBy(x: horizontalInset, y: 0)
        
        // 2. 绘制 TTS 高亮
        if isPlayingHighlight {
            ctx.saveGState()
            let allIndices = ([highlightIndex].compactMap { $0 } + Array(secondaryIndices))
            for i in allIndices {
                guard i < paragraphStarts.count else { continue }
                let start = paragraphStarts[i]
                let end = (i + 1 < paragraphStarts.count) ? paragraphStarts[i + 1] : s.attributedString.length
                let range = NSRange(location: start, length: max(0, end - start))
                
                if NSIntersectionRange(range, info.range).length > 0 {
                    let color = (i == highlightIndex) ? UIColor.systemBlue.withAlphaComponent(0.12) : UIColor.systemGreen.withAlphaComponent(0.06)
                    ctx.setFillColor(color.cgColor)
                    
                    if let startLoc = s.contentStorage.location(s.contentStorage.documentRange.location, offsetBy: range.location) {
                        s.layoutManager.enumerateTextLayoutFragments(from: startLoc, options: [.ensuresLayout]) { f in
                            let fRange = s.contentStorage.offset(from: s.contentStorage.documentRange.location, to: f.rangeInElement.location)
                            if fRange >= range.location + range.length { return false }
                            
                            // 直接绘制原始 Frame
                            let frame = f.layoutFragmentFrame
                            // 简单的裁剪判断：只画在当前页范围内的
                            if frame.maxY > info.yOffset && frame.minY < info.yOffset + info.actualContentHeight {
                                ctx.fill(frame.insetBy(dx: -2, dy: -1))
                            }
                            return true
                        }
                    }
                }
            }
            ctx.restoreGState()
        }
        
        // 3. 绘制文字 (直接使用原始坐标)
        let startLoc = s.contentStorage.location(s.contentStorage.documentRange.location, offsetBy: info.range.location)!
        s.layoutManager.enumerateTextLayoutFragments(from: startLoc, options: [.ensuresLayout]) { fragment in
            let frame = fragment.layoutFragmentFrame
            // 只要 Fragment 的一部分在可视范围内就绘制
            // 这里的 yOffset 对应 bounds.origin.y + topInset
            if frame.minY >= info.yOffset + info.actualContentHeight + info.contentInset { return false }
            
            fragment.draw(at: frame.origin, in: ctx)
            return true
        }
        
        ctx.restoreGState()
    }
}