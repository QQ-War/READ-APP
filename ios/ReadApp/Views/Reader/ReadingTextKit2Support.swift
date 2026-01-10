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
            // 修正：精确获取当前页面的起始字符偏移量，而不仅仅是 LayoutFragment 的起始位置
            var startOffset = attributedStringLength(storage)
            if let f = lm.textLayoutFragment(for: CGPoint(x: 0, y: currentY)) {
                if #available(iOS 15.0, *) {
                    // 修正逻辑：查找视觉上位于 currentY 处的具体行 (Line Fragment)
                    // 而不是简单地取 Fragment 的第一行 (它可能在上一页)
                    let relativeY = currentY - f.layoutFragmentFrame.minY
                    // 使用 0.01 的容差处理浮点数边界
                    if let line = f.textLineFragments.first(where: { $0.typographicBounds.maxY > relativeY + 0.01 }) {
                        let fragmentStart = storage.offset(from: storage.documentRange.location, to: f.rangeInElement.location)
                        let lineStart = line.characterRange.location // relative to element
                        startOffset = fragmentStart + lineStart
                    } else {
                        // Fallback
                        startOffset = storage.offset(from: storage.documentRange.location, to: f.rangeInElement.location)
                    }
                } else {
                    startOffset = storage.offset(from: storage.documentRange.location, to: f.rangeInElement.location)
                }
            }
            
            if startOffset >= attributedStringLength(storage) { break }
            
            let startSentenceIdx = paragraphStarts.lastIndex(where: { $0 <= startOffset }) ?? 0
            
            // 查找本页理论结束位置附近的 Fragment
            let targetY = currentY + usableHeight
            // 往回一点点探测，获取位于底部的那个 Fragment
            guard let endFragment = lm.textLayoutFragment(for: CGPoint(x: 0, y: targetY - 5.0)) else {
                // 如果探测不到，说明可能已经到底或者传入的 targetY 已经越界
                if let fallback = lm.textLayoutFragment(for: CGPoint(x: 0, y: targetY)) {
                    let endOffset = storage.offset(from: storage.documentRange.location, to: fallback.rangeInElement.endLocation)
                    let pageRange = NSRange(location: startOffset, length: max(1, endOffset - startOffset))
                    pages.append(PaginatedPage(globalRange: pageRange, startSentenceIndex: startSentenceIdx))
                    pageInfos.append(TK2PageInfo(range: pageRange, yOffset: currentY, pageHeight: pageSize.height, actualContentHeight: fallback.layoutFragmentFrame.maxY - currentY, startSentenceIndex: startSentenceIdx, contentInset: topInset))
                    currentY = fallback.layoutFragmentFrame.maxY
                    if currentY >= lm.usageBoundsForTextContainer.height { break }
                    continue
                } else if currentY < lm.usageBoundsForTextContainer.height {
                    let endOffset = attributedStringLength(storage)
                    let pageRange = NSRange(location: startOffset, length: max(1, endOffset - startOffset))
                    let actualContentHeight = max(0, lm.usageBoundsForTextContainer.height - currentY)
                    pages.append(PaginatedPage(globalRange: pageRange, startSentenceIndex: startSentenceIdx))
                    pageInfos.append(TK2PageInfo(
                        range: pageRange,
                        yOffset: currentY,
                        pageHeight: pageSize.height,
                        actualContentHeight: actualContentHeight,
                        startSentenceIndex: startSentenceIdx,
                        contentInset: topInset
                    ))
                }
                break
            }
            
            var pageEndOffset: Int = 0
            var nextPageStartY: CGFloat = 0
            
            // 核心判定：防截断逻辑
            // 如果该段落的底部超出了本页可用高度，尝试按行切分
            if endFragment.layoutFragmentFrame.maxY > targetY {
                let fragmentStartOffset = storage.offset(from: storage.documentRange.location, to: endFragment.rangeInElement.location)
                var lastLineEndOffset: Int?
                var lastLineMaxY: CGFloat?
                
                for line in endFragment.textLineFragments {
                    let lineFrame = line.typographicBounds.offsetBy(dx: endFragment.layoutFragmentFrame.origin.x, dy: endFragment.layoutFragmentFrame.origin.y)
                    if lineFrame.maxY <= targetY {
                        lastLineEndOffset = fragmentStartOffset + line.characterRange.upperBound
                        lastLineMaxY = lineFrame.maxY
                    } else {
                        break
                    }
                }
                
                // Case 1: 找到可容纳的行 -> 按行切分，允许段落跨页
                if let end = lastLineEndOffset, end > startOffset {
                    pageEndOffset = end
                    nextPageStartY = lastLineMaxY ?? endFragment.layoutFragmentFrame.minY
                }
                // Case 2: 本页没有一行能容纳 -> 推到下一页
                else if fragmentStartOffset > startOffset {
                    pageEndOffset = fragmentStartOffset
                    nextPageStartY = endFragment.layoutFragmentFrame.minY
                }
                // Case 3: 这一行是本页第一行（超大字号占满整页） -> 只能强行放入
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
class ReadContent2View: UIView, UIGestureRecognizerDelegate {
    static let debugLogTopFragments = false
    private var lastLoggedPageIndex: Int?
    var pageIndex: Int?
    var onVisibleFragments: ((Int, [String]) -> Void)?
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
    var editMenuInteraction: Any?
    var pendingSelectedText: String?
    
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
        tap.delegate = self
        addGestureRecognizer(tap)
        
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress))
        longPress.delegate = self
        addGestureRecognizer(longPress)
        
        if #available(iOS 16.0, *) {
            let interaction = UIEditMenuInteraction(delegate: self)
            addInteraction(interaction)
            editMenuInteraction = interaction
        }
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
            self.pendingSelectedText = txt
            if #available(iOS 16.0, *) {
                if let interaction = editMenuInteraction as? UIEditMenuInteraction {
                    let configuration = UIEditMenuConfiguration(identifier: nil, sourcePoint: pointInContent)
                    interaction.presentEditMenu(with: configuration)
                }
            } else {
                becomeFirstResponder()
                let menu = UIMenuController.shared
                menu.menuItems = [UIMenuItem(title: "添加净化规则", action: #selector(addToReplaceRule))]
                menu.showMenu(from: self, rect: CGRect(origin: pointInContent, size: .zero))
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
    
    override func draw(_ rect: CGRect) {
        guard let s = renderStore, let info = pageInfo else { return }
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        
        ctx.saveGState()
        
        // 增加裁剪区域，防止文字或高亮溢出到 topInset 或 bottomInset 之外
        let clipRect = CGRect(x: 0, y: info.yOffset, width: bounds.width, height: info.actualContentHeight)
        ctx.clip(to: clipRect)
        
        ctx.translateBy(x: horizontalInset, y: 0)
        logVisibleFragmentsIfNeeded(info: info, store: s)
        
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
                            
                            let frame = f.layoutFragmentFrame
                            // 修正判断条件
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
        guard let startLoc = s.contentStorage.location(s.contentStorage.documentRange.location, offsetBy: info.range.location) else { return }
        s.layoutManager.enumerateTextLayoutFragments(from: startLoc, options: [.ensuresLayout]) { fragment in
            let frame = fragment.layoutFragmentFrame
            if frame.minY >= info.yOffset + info.actualContentHeight { return false }
            
            // 核心修复：处理跨页段落的缩进异常
            // 如果这个 fragment 的起始位置不是段落的物理起始位置 (paragraphStarts)，说明它是被切分的，需要移除首行缩进
            let fragmentOffset = s.contentStorage.offset(from: s.contentStorage.documentRange.location, to: fragment.rangeInElement.location)
            let isParagraphStart = self.paragraphStarts.contains(fragmentOffset)
            
            fragment.draw(at: frame.origin, in: ctx)
            return true
        }
        
        ctx.restoreGState()
    }

    private func logVisibleFragmentsIfNeeded(info: TK2PageInfo, store: TextKit2RenderStore) {
        guard let pageIdx = pageIndex else { return }
        if lastLoggedPageIndex == pageIdx { return }
        lastLoggedPageIndex = pageIdx
        guard let startLoc = store.contentStorage.location(store.contentStorage.documentRange.location, offsetBy: info.range.location) else { return }
        var lines: [String] = []
        store.layoutManager.enumerateTextLayoutFragments(from: startLoc, options: [.ensuresLayout]) { fragment in
            let fragmentStart = store.contentStorage.offset(from: store.contentStorage.documentRange.location, to: fragment.rangeInElement.location)
            let fragmentEnd = store.contentStorage.offset(from: store.contentStorage.documentRange.location, to: fragment.rangeInElement.endLocation)
            let length = fragmentEnd - fragmentStart
            guard fragmentStart + length <= store.attributedString.length else { return false }
            let raw = (store.attributedString.string as NSString).substring(with: NSRange(location: fragmentStart, length: length))
            let cleaned = sanitizedPreviewText(raw, limit: 120)
            if !cleaned.isEmpty {
                lines.append(cleaned)
            }
            return lines.count < 2
        }
        if !lines.isEmpty && Self.debugLogTopFragments {
            LogManager.shared.log("ReadContent2View top fragments page=\(pageIdx): \(lines.joined(separator: " | "))", category: "TTS")
        }
        onVisibleFragments?(pageIdx, lines)
    }

    private func sanitizedPreviewText(_ text: String, limit: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ")
        guard trimmed.count > limit else { return trimmed }
        let endIndex = trimmed.index(trimmed.startIndex, offsetBy: limit)
        return String(trimmed[..<endIndex]) + "…"
    }
}

@available(iOS 16.0, *)
extension ReadContent2View: UIEditMenuInteractionDelegate {
    func editMenuInteraction(_ interaction: UIEditMenuInteraction, menuFor configuration: UIEditMenuConfiguration, suggestedActions: [UIMenuElement]) -> UIMenu? {
        let addAction = UIAction(title: "添加净化规则") { [weak self] _ in
            if let t = self?.pendingSelectedText { self?.onAddReplaceRule?(t) }
        }
        return UIMenu(children: [addAction] + suggestedActions)
    }
}
