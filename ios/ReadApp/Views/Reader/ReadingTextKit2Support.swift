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
        let anchorPageIndex: Int // 锚点所在的页索引
    }
    
    /// 标准分页：从头开始
    static func paginate(renderStore: TextKit2RenderStore, pageSize: CGSize, paragraphStarts: [Int], prefixLen: Int, topInset: CGFloat, bottomInset: CGFloat) -> PaginationResult {
        return paginateFromAnchor(anchorOffset: 0, renderStore: renderStore, pageSize: pageSize, paragraphStarts: paragraphStarts, prefixLen: prefixLen, topInset: topInset, bottomInset: bottomInset)
    }

    /// 锚点分页：从指定偏移量开始双向切片
    static func paginateFromAnchor(anchorOffset: Int, renderStore: TextKit2RenderStore, pageSize: CGSize, paragraphStarts: [Int], prefixLen: Int, topInset: CGFloat, bottomInset: CGFloat) -> PaginationResult {
        let lm = renderStore.layoutManager
        let storage = renderStore.contentStorage
        lm.ensureLayout(for: storage.documentRange)
        
        let safeBottomPadding: CGFloat = 8.0
        let usableHeight = max(100, pageSize.height - topInset - bottomInset - safeBottomPadding)
        let totalTextLen = storage.attributedString?.length ?? 0
        
        // 1. 定位锚点行
        var effectiveAnchorOffset = max(0, min(anchorOffset, totalTextLen))
        var anchorY: CGFloat = 0
        if let loc = storage.location(storage.documentRange.location, offsetBy: effectiveAnchorOffset),
           let f = lm.textLayoutFragment(for: loc) {
            anchorY = f.layoutFragmentFrame.minY
            if #available(iOS 15.0, *) {
                let offsetInFrag = effectiveAnchorOffset - storage.offset(from: storage.documentRange.location, to: f.rangeInElement.location)
                if let line = f.textLineFragments.first(where: { $0.characterRange.location + $0.characterRange.length > offsetInFrag }) {
                    anchorY += line.typographicBounds.minY
                    // 修正：同步 effectiveAnchorOffset 到该行开头，确保切片严丝合缝
                    effectiveAnchorOffset = storage.offset(from: storage.documentRange.location, to: f.rangeInElement.location) + line.characterRange.location
                }
            }
        }

        // 2. 向后切片 (Forward)
        var forwardPages: [PaginatedPage] = []
        var forwardInfos: [TK2PageInfo] = []
        var currentY = anchorY
        var currentOffset = effectiveAnchorOffset
        
        while currentOffset < totalTextLen {
            let page = sliceNextPage(fromOffset: currentOffset, fromY: currentY, usableHeight: usableHeight, storage: storage, lm: lm, paragraphStarts: paragraphStarts, pageSize: pageSize, topInset: topInset)
            forwardPages.append(page.0)
            forwardInfos.append(page.1)
            currentOffset = page.0.globalRange.location + page.0.globalRange.length
            currentY = page.1.yOffset + page.1.actualContentHeight
            if currentY >= lm.usageBoundsForTextContainer.height { break }
        }
        
        // 3. 向前切片 (Backward)
        var backwardPages: [PaginatedPage] = []
        var backwardInfos: [TK2PageInfo] = []
        currentY = anchorY
        currentOffset = effectiveAnchorOffset
        
        while currentOffset > 0 {
            // 向上寻找一屏高度的内容
            let targetY = max(0, currentY - usableHeight)
            // 探测目标位置的 Fragment
            guard let f = lm.textLayoutFragment(for: CGPoint(x: 0, y: targetY)) else { break }
            
            var pageStartY = f.layoutFragmentFrame.minY
            var pageStartOffset = storage.offset(from: storage.documentRange.location, to: f.rangeInElement.location)
            
            if #available(iOS 15.0, *) {
                let relativeY = targetY - f.layoutFragmentFrame.minY
                if let line = f.textLineFragments.first(where: { $0.typographicBounds.maxY > relativeY + 0.01 }) {
                    pageStartY += line.typographicBounds.minY
                    pageStartOffset += line.characterRange.location
                }
            }
            
            // 如果计算出的起始位置没变（说明已经到头或陷入死循环），强制跳出
            if pageStartOffset >= currentOffset {
                if targetY <= 0 {
                    pageStartOffset = 0
                    pageStartY = 0
                } else { break }
            }
            
            let pageRange = NSRange(location: pageStartOffset, length: currentOffset - pageStartOffset)
            let startSentenceIdx = paragraphStarts.lastIndex(where: { $0 <= pageStartOffset }) ?? 0
            
            backwardPages.insert(PaginatedPage(globalRange: pageRange, startSentenceIndex: startSentenceIdx), at: 0)
            backwardInfos.insert(TK2PageInfo(range: pageRange, yOffset: pageStartY, pageHeight: pageSize.height, actualContentHeight: currentY - pageStartY, startSentenceIndex: startSentenceIdx, contentInset: topInset), at: 0)
            
            currentOffset = pageStartOffset
            currentY = pageStartY
            if currentY <= 0 { break }
        }
        
        return PaginationResult(
            pages: backwardPages + forwardPages,
            pageInfos: backwardInfos + forwardInfos,
            anchorPageIndex: backwardPages.count
        )
    }
    
    private static func sliceNextPage(fromOffset: Int, fromY: CGFloat, usableHeight: CGFloat, storage: NSTextContentStorage, lm: NSTextLayoutManager, paragraphStarts: [Int], pageSize: CGSize, topInset: CGFloat) -> (PaginatedPage, TK2PageInfo) {
        let totalTextLen = storage.attributedString?.length ?? 0
        let startSentenceIdx = paragraphStarts.lastIndex(where: { $0 <= fromOffset }) ?? 0
        let targetY = fromY + usableHeight
        
        guard let endFragment = lm.textLayoutFragment(for: CGPoint(x: 0, y: targetY - 2.0)) else {
            // 到底了
            let endOffset = totalTextLen
            let range = NSRange(location: fromOffset, length: endOffset - fromOffset)
            let info = TK2PageInfo(range: range, yOffset: fromY, pageHeight: pageSize.height, actualContentHeight: max(10, lm.usageBoundsForTextContainer.height - fromY), startSentenceIndex: startSentenceIdx, contentInset: topInset)
            return (PaginatedPage(globalRange: range, startSentenceIndex: startSentenceIdx), info)
        }
        
        var pageEndOffset = totalTextLen
        var nextPageStartY = lm.usageBoundsForTextContainer.height
        
        if endFragment.layoutFragmentFrame.maxY > targetY {
            let fragmentStartOffset = storage.offset(from: storage.documentRange.location, to: endFragment.rangeInElement.location)
            var lastLineEndOffset: Int?
            var lastLineMaxY: CGFloat?
            
            if #available(iOS 15.0, *) {
                for line in endFragment.textLineFragments {
                    let lineMaxY = endFragment.layoutFragmentFrame.minY + line.typographicBounds.maxY
                    // 核心修复：只考虑在本页范围内且在起始点之后的行
                    if lineMaxY <= targetY + 0.01 {
                        if lineMaxY > fromY + 0.01 {
                            lastLineEndOffset = fragmentStartOffset + line.characterRange.upperBound
                            lastLineMaxY = lineMaxY
                        }
                    } else { break }
                }
            }
            
            if let end = lastLineEndOffset, end > fromOffset {
                pageEndOffset = end
                nextPageStartY = lastLineMaxY ?? endFragment.layoutFragmentFrame.minY
            } else if fragmentStartOffset > fromOffset {
                pageEndOffset = fragmentStartOffset
                nextPageStartY = endFragment.layoutFragmentFrame.minY
            } else {
                pageEndOffset = storage.offset(from: storage.documentRange.location, to: endFragment.rangeInElement.endLocation)
                nextPageStartY = endFragment.layoutFragmentFrame.maxY
            }
        } else {
            pageEndOffset = storage.offset(from: storage.documentRange.location, to: endFragment.rangeInElement.endLocation)
            nextPageStartY = endFragment.layoutFragmentFrame.maxY
        }
        
        let range = NSRange(location: fromOffset, length: max(1, pageEndOffset - fromOffset))
        let info = TK2PageInfo(range: range, yOffset: fromY, pageHeight: pageSize.height, actualContentHeight: nextPageStartY - fromY, startSentenceIndex: startSentenceIdx, contentInset: topInset)
        return (PaginatedPage(globalRange: range, startSentenceIndex: startSentenceIdx), info)
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
class ReadContent2View: UIView, UIGestureRecognizerDelegate {
    static let debugLogTopFragments = false
    private var lastLoggedPageIndex: Int?
    var pageIndex: Int?
    var onVisibleFragments: ((Int, [String]) -> Void)?
    var renderStore: TextKit2RenderStore?
    var pageInfo: TK2PageInfo? {
        didSet {
            guard let info = pageInfo else { return }
            let viewportY = info.yOffset - info.contentInset
            self.bounds.origin = CGPoint(x: 0, y: viewportY)
            setNeedsDisplay()
        }
    }
    
    var horizontalInset: CGFloat = 16
    var onTapLocation: ((ReaderTapLocation) -> Void)?
    
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
        tap.delegate = self
        addGestureRecognizer(tap)
        
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress))
        longPress.minimumPressDuration = 0.8
        longPress.delegate = self
        addGestureRecognizer(longPress)
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
    
    @objc private func handleTap(_ g: UITapGestureRecognizer) {
        let x = g.location(in: self).x
        if x < bounds.width * 0.3 { onTapLocation?(.left) }
        else if x > bounds.width * 0.7 { onTapLocation?(.right) }
        else { onTapLocation?(.middle) }
    }
    
    @objc private func handleLongPress(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began, let store = renderStore else { return }
        let pointInContent = g.location(in: self)
        
        if let f = store.layoutManager.textLayoutFragment(for: pointInContent),
           let te = f.textElement, let range = te.elementRange,
           let r = TextKit2Paginator.rangeFromTextRange(range, in: store.contentStorage) {
            let txt = (store.attributedString.string as NSString).substring(with: r)
            onAddReplaceRule?(txt)
        }
    }

    override var canBecomeFirstResponder: Bool { true }
    
    override func draw(_ rect: CGRect) {
        guard let s = renderStore, let info = pageInfo else { return }
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        
        ctx.saveGState()
        
        let clipRect = CGRect(x: 0, y: info.yOffset, width: bounds.width, height: info.actualContentHeight)
        ctx.clip(to: clipRect)
        
        ctx.translateBy(x: horizontalInset, y: 0)
        logVisibleFragmentsIfNeeded(info: info, store: s)
        
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
                            let fRangeStart = s.contentStorage.offset(from: s.contentStorage.documentRange.location, to: f.rangeInElement.location)
                            if fRangeStart >= range.location + range.length { return false }
                            
                            let frame = f.layoutFragmentFrame
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
        
        guard let startLoc = s.contentStorage.location(s.contentStorage.documentRange.location, offsetBy: info.range.location) else { return }
        s.layoutManager.enumerateTextLayoutFragments(from: startLoc, options: [.ensuresLayout]) { fragment in
            let frame = fragment.layoutFragmentFrame
            if frame.minY >= info.yOffset + info.actualContentHeight { return false }
            fragment.draw(at: frame.origin, in: ctx)
            return true
        }
        
        ctx.restoreGState()
    }

    private func logVisibleFragmentsIfNeeded(info: TK2PageInfo, store: TextKit2RenderStore) {
        guard let pageIdx = pageIndex else { return }
        if lastLoggedPageIndex == pageIdx { return }
        lastLoggedPageIndex = pageIdx
        
        // 核心修复：基于 info.range 获取片段，解决日志误导问题
        let snippetLen = min(120, info.range.length)
        guard snippetLen > 0 else { return }
        let raw = (store.attributedString.string as NSString).substring(with: NSRange(location: info.range.location, length: snippetLen))
        let cleaned = sanitizedPreviewText(raw, limit: 120)
        
        if Self.debugLogTopFragments {
            LogManager.shared.log("ReadContent2View content page=\(pageIdx): \(cleaned)", category: "TTS")
        }
        onVisibleFragments?(pageIdx, [cleaned])
    }

    private func sanitizedPreviewText(_ text: String, limit: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ")
        guard trimmed.count > limit else { return trimmed }
        let endIndex = trimmed.index(trimmed.startIndex, offsetBy: limit)
        return String(trimmed[..<endIndex]) + "…"
    }
}

