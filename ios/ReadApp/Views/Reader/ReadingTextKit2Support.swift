import UIKit

enum ReaderConstants {
    enum Layout {
        static let safeAreaTopDefault: CGFloat = 47
        static let safeAreaBottomDefault: CGFloat = 34
        static let extraTopInset: CGFloat = 15
        static var extraBottomInset: CGFloat { UserPreferences.shared.readingBottomInset }
        static let sideMarginPadding: CGFloat = 8
        static let horizontalInset: CGFloat = 16
        static let safeBottomPadding: CGFloat = 8
        static let minUsableHeight: CGFloat = 100
        static let minLayoutWidth: CGFloat = 100
        static let minLayoutWidthFallback: CGFloat = 375
        static let extraSpacing: CGFloat = 100
        static var verticalContentInsetBottom: CGFloat { UserPreferences.shared.readingBottomInset }
        static let defaultMargin: CGFloat = 20
    }

    enum Interaction {
        static let chapterSwitchCooldown: TimeInterval = 1.0
        static let ttsSuppressDuration: TimeInterval = 0.5
        static let horizontalSwitchThreshold: CGFloat = 50
        static let switchRequestCooldown: TimeInterval = 1.0
        static let velocitySnapThreshold: CGFloat = 0.2
        static let longPressDuration: TimeInterval = 0.8
        static let switchHintAnimation: TimeInterval = 0.2
        static let switchHintWidthMin: CGFloat = 120
        static let switchHintHorizontalPadding: CGFloat = 40
        static let switchHintBottomPadding: CGFloat = 36
        static let switchHintTopPadding: CGFloat = 12
        static let pullThreshold: CGFloat = 5
        static let interactionStartSnapThreshold: CGFloat = 0.5
        static let progressDelayShort: TimeInterval = 0.05
        static let progressDelayNormal: TimeInterval = 0.1
        static let seamlessSwitchThreshold: CGFloat = 120
        static let dampingFactorDefault: CGFloat = 0.2
        static let textDampingFactor: CGFloat = 0.12
        static let mangaSwitchHoldDuration: TimeInterval = 0.6
        static let visibleRangePadding: CGFloat = 50
        static let detectionOffsetMin: CGFloat = 2.0
        static let detectionOffsetFactor: CGFloat = 0.2
        static let detectionNegativeClamp: CGFloat = 50
        static let seamlessTriggerMin: CGFloat = 40
        static let minHorizontalInset: CGFloat = 10
        static let minVerticalOffset: CGFloat = 2
        static let maxVerticalOffset: CGFloat = 12
        static let viewportTopMargin: CGFloat = 15
        static let chapterGap: CGFloat = 80
        static let estimatedLineHeight: CGFloat = 30
        static let lineSpacingFactor: CGFloat = 0.35
        static let lineThresholdFactor: CGFloat = 0.3
        static let firstSentenceThreshold: CGFloat = 2.0
        static let transitionGuardTimeout: TimeInterval = 1.0
        static let verticalThresholdDefault: CGFloat = 80
        static let autoSwitchSuppressDuration: TimeInterval = 0.6
        static let reachBottomFactor: CGFloat = 1.5
        static let reachTopFactor: CGFloat = 0.6
        static let tapZoneLeft: CGFloat = 0.3
        static let tapZoneRight: CGFloat = 0.7
    }

    enum Text {
        static let previewSnippetLength: Int = 120
        static let paragraphIndentLength: Int = 2
        static let paragraphSpacingFactor: CGFloat = 0.5
        static let chapterGroupSize: Int = 50
        static let chapterGroupSpacingFactor: CGFloat = 0.8
        static let titleParagraphSpacingFactor: CGFloat = 1.5
    }

    enum Highlight {
        static let primaryAlpha: CGFloat = 0.12
        static let secondaryAlpha: CGFloat = 0.06
        static let listPrimaryAlpha: CGFloat = 0.2
        static let cornerRadius: CGFloat = 4
        static let switchHintCornerRadius: CGFloat = 12
    }

    enum Pagination {
        static let targetYOffsetEpsilon: CGFloat = 2.0
        static let lineMaxYEpsilon: CGFloat = 0.01
        static let highlightInsetX: CGFloat = -2
        static let highlightInsetY: CGFloat = -1
    }

    enum ProgressLabel {
        static let trailing: CGFloat = 12
        static let bottom: CGFloat = 4
    }

    enum Animation {
        static let flipPerspective: CGFloat = -1.0 / 1000.0
        static let flipMaxAngle: CGFloat = .pi / 2
        static let fadeCutoff: CGFloat = 0.6
        static let maxTransformAbsProgress: CGFloat = 1.0
        static let fadeZIndexBack: Int = 5
        static let fadeZIndexFront: Int = 10
        static let coverZIndexFront: Int = 100
        static let flipZIndexMax: CGFloat = 1000.0
        static let modeTransitionDuration: TimeInterval = 0.5
        static let shouldAnimateViewportThreshold: CGFloat = 0.5
        static let scrollTransitionDuration: TimeInterval = 0.35
        static let coverTransitionDuration: TimeInterval = 0.45
        static let fadeTransitionDuration: TimeInterval = 0.35
        static let coverShadowOpacity: Float = 0.4
        static let coverShadowRadius: CGFloat = 10
        static let coverShadowOffset: CGFloat = 4
        static let coverBackShiftFactor: CGFloat = 0.3
    }

    enum Controls {
        static let barSpacing: CGFloat = 16
        static let rowSpacing: CGFloat = 12
        static let rowLabelSpacing: CGFloat = 4
        static let horizontalPadding: CGFloat = 20
        static let secondaryHorizontalPadding: CGFloat = 25
        static let controlVerticalPadding: CGFloat = 10
        static let controlShadowOpacity: Double = 0.1
        static let controlShadowRadius: CGFloat = 5
        static let controlShadowYOffset: CGFloat = -2
        static let timerButtonHorizontalPadding: CGFloat = 10
        static let timerButtonVerticalPadding: CGFloat = 5
        static let timerButtonCornerRadius: CGFloat = 12
        static let ttsMainButtonSize: CGFloat = 56
        static let ttsRowVerticalPadding: CGFloat = 8
        static let iconButtonWidth: CGFloat = 44
        static let iconLabelSize: CGFloat = 10
        static let chapterButtonWidthPortrait: CGFloat = 85
        static let chapterButtonHeightLandscape: CGFloat = 50
        static let chapterButtonHeightPortrait: CGFloat = 64
        static let chapterButtonCornerLandscape: CGFloat = 25
        static let chapterButtonCornerPortrait: CGFloat = 16
        static let controlBarHorizontalPaddingLandscape: CGFloat = 15
        static let controlBarHorizontalPaddingPortrait: CGFloat = 10
    }

    enum Audio {
        static let viewSpacing: CGFloat = 16
        static let headerSpacing: CGFloat = 8
        static let backgroundBlurRadius: CGFloat = 20
        static let backgroundOpacity: Double = 0.25
        static let coverSize: CGFloat = 220
        static let coverCornerRadius: CGFloat = 20
        static let coverShadowRadius: CGFloat = 8
        static let buttonSpacing: CGFloat = 24
        static let playButtonSize: CGFloat = 48
        static let speedButtonHorizontalPadding: CGFloat = 10
        static let speedButtonVerticalPadding: CGFloat = 6
        static let speedButtonCornerRadius: CGFloat = 8
        static let speedButtonSpacing: CGFloat = 12
        static let progressIntervalSeconds: Double = 0.5
    }

    enum UI {
        static let overlayCornerRadius: CGFloat = 10
        static let topBarButtonSize: CGFloat = 24
        static let topBarSecondaryButtonSize: CGFloat = 22
        static let topBarButtonPadding: CGFloat = 12
        static let topBarHorizontalPadding: CGFloat = 16
        static let topBarBottomPadding: CGFloat = 10
        static let topBarSpacing: CGFloat = 12
        static let formRowSpacing: CGFloat = 8
        static let formSectionPaddingVertical: CGFloat = 4
        static let formHeaderSpacing: CGFloat = 10
        static let selectionHeaderSpacing: CGFloat = 2
        static let selectionNoticeTopPadding: CGFloat = 8
        static let selectionButtonCornerRadius: CGFloat = 10
    }

    enum List {
        static let groupSpacing: CGFloat = 8
        static let groupHorizontalPadding: CGFloat = 12
        static let groupVerticalPadding: CGFloat = 6
        static let groupCornerRadius: CGFloat = 16
        static let toolbarSpacing: CGFloat = 4
        static let inlineImagePadding: CGFloat = 4
        static let textVerticalPadding: CGFloat = 6
        static let textHorizontalPadding: CGFloat = 8
        static let textCornerRadius: CGFloat = 4
        static let scrollToHighlightDelay: TimeInterval = 0.3
    }

    enum Manga {
        static let placeholderSpacing: CGFloat = 8
        static let placeholderCornerRadius: CGFloat = 8
        static let placeholderTextSize: CGFloat = 8
        static let placeholderMinHeight: CGFloat = 200
    }

    enum RefreshRate {
        static let minStatic: Float = 10
        static let maxStatic: Float = 30
        static let prefStatic: Float = 30
        
        static let minInteraction: Float = 30
        static let maxInteraction: Float = 60
        static let prefInteraction: Float = 60
    }
}

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
        attachInlineImageHandlers()
    }

    private func attachInlineImageHandlers() {
        let range = NSRange(location: 0, length: attributedString.length)
        attributedString.enumerateAttribute(.attachment, in: range, options: []) { value, _, _ in
            if let attachment = value as? InlineImageAttachment {
                attachment.onImageLoaded = { [weak self] in
                    guard let self else { return }
                    self.layoutManager.invalidateLayout(for: self.contentStorage.documentRange)
                    self.layoutManager.ensureLayout(for: self.contentStorage.documentRange)
                }
            }
        }
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
        
        let safeBottomPadding: CGFloat = ReaderConstants.Layout.safeBottomPadding
        let usableHeight = max(ReaderConstants.Layout.minUsableHeight, pageSize.height - topInset - bottomInset - safeBottomPadding)
        let totalTextLen = storage.attributedString?.length ?? 0
        
        // 1. 定位锚点行
        var effectiveAnchorOffset = max(0, min(anchorOffset, totalTextLen))
        if totalTextLen > 0 && effectiveAnchorOffset == totalTextLen {
            effectiveAnchorOffset = totalTextLen - 1
        }
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
        
        guard let endFragment = lm.textLayoutFragment(for: CGPoint(x: 0, y: targetY - ReaderConstants.Pagination.targetYOffsetEpsilon)) else {
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
                    if lineMaxY <= targetY + ReaderConstants.Pagination.lineMaxYEpsilon {
                        if lineMaxY > fromY + ReaderConstants.Pagination.lineMaxYEpsilon {
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
    
    var horizontalInset: CGFloat = ReaderConstants.Layout.horizontalInset
    var onTapLocation: ((ReaderTapLocation) -> Void)?
    var onImageTapped: ((URL) -> Void)?
    
    var onAddReplaceRule: ((String) -> Void)?
    var highlightIndex: Int? { didSet { setNeedsDisplay() } }
    var secondaryIndices: Set<Int> = [] { didSet { setNeedsDisplay() } }
    var isPlayingHighlight: Bool = false { didSet { setNeedsDisplay() } }
    var highlightRange: NSRange? { didSet { setNeedsDisplay() } }
    var paragraphStarts: [Int] = []
    var chapterPrefixLen: Int = 0
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        self.backgroundColor = UserPreferences.shared.readingTheme.backgroundColor
        self.isOpaque = true
        NotificationCenter.default.addObserver(self, selector: #selector(handleInlineImageLoaded), name: InlineImageAttachment.didLoadNotification, object: nil)
        
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tap.delegate = self
        addGestureRecognizer(tap)
        
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress))
        longPress.minimumPressDuration = ReaderConstants.Interaction.longPressDuration
        longPress.delegate = self
        addGestureRecognizer(longPress)
    }
    
    required init?(coder: NSCoder) { fatalError() }

    deinit {
        NotificationCenter.default.removeObserver(self, name: InlineImageAttachment.didLoadNotification, object: nil)
    }
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
    
    @objc private func handleTap(_ g: UITapGestureRecognizer) {
        let point = g.location(in: self)
        if let store = renderStore {
            let adjusted = CGPoint(x: point.x - horizontalInset, y: point.y)
            if let url = InlineImageHitTester.imageURL(at: adjusted, in: store) {
                onImageTapped?(url)
                return
            }
        }
        let x = point.x
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

    @objc private func handleInlineImageLoaded() {
        setNeedsDisplay()
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
            if let range = highlightRange {
                drawHighlight(range: range, store: s, info: info, context: ctx, color: UIColor.systemBlue.withAlphaComponent(ReaderConstants.Highlight.primaryAlpha))
            } else {
                let allIndices = ([highlightIndex].compactMap { $0 } + Array(secondaryIndices))
                for i in allIndices {
                    guard i < paragraphStarts.count else { continue }
                    let start = paragraphStarts[i]
                    let end = (i + 1 < paragraphStarts.count) ? paragraphStarts[i + 1] : s.attributedString.length
                    let range = NSRange(location: start, length: max(0, end - start))
                    let color = (i == highlightIndex) ? UIColor.systemBlue.withAlphaComponent(ReaderConstants.Highlight.primaryAlpha) : UIColor.systemGreen.withAlphaComponent(ReaderConstants.Highlight.secondaryAlpha)
                    drawHighlight(range: range, store: s, info: info, context: ctx, color: color)
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
        let snippetLen = min(ReaderConstants.Text.previewSnippetLength, info.range.length)
        guard snippetLen > 0 else { return }
        let raw = (store.attributedString.string as NSString).substring(with: NSRange(location: info.range.location, length: snippetLen))
        let cleaned = sanitizedPreviewText(raw, limit: ReaderConstants.Text.previewSnippetLength)
        
        onVisibleFragments?(pageIdx, [cleaned])
    }

    private func drawHighlight(range: NSRange, store: TextKit2RenderStore, info: TK2PageInfo, context: CGContext, color: UIColor) {
        guard NSIntersectionRange(range, info.range).length > 0 else { return }
        context.setFillColor(color.cgColor)
        if let startLoc = store.contentStorage.location(store.contentStorage.documentRange.location, offsetBy: range.location) {
            store.layoutManager.enumerateTextLayoutFragments(from: startLoc, options: [.ensuresLayout]) { f in
                let fRangeStart = store.contentStorage.offset(from: store.contentStorage.documentRange.location, to: f.rangeInElement.location)
                if fRangeStart >= range.location + range.length { return false }
                let frame = f.layoutFragmentFrame
                if frame.maxY > info.yOffset && frame.minY < info.yOffset + info.actualContentHeight {
                    context.fill(frame.insetBy(dx: ReaderConstants.Pagination.highlightInsetX, dy: ReaderConstants.Pagination.highlightInsetY))
                }
                return true
            }
        }
    }

    private func sanitizedPreviewText(_ text: String, limit: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ")
        guard trimmed.count > limit else { return trimmed }
        let endIndex = trimmed.index(trimmed.startIndex, offsetBy: limit)
        return String(trimmed[..<endIndex]) + "…"
    }
}

enum InlineImageHitTester {
    static func imageURL(at point: CGPoint, in store: TextKit2RenderStore) -> URL? {
        let lm = store.layoutManager
        guard let fragment = lm.textLayoutFragment(for: point) else { return nil }
        let fragmentOrigin = fragment.layoutFragmentFrame.origin
        for line in fragment.textLineFragments {
            let rect = line.typographicBounds.offsetBy(dx: fragmentOrigin.x, dy: fragmentOrigin.y)
            if rect.contains(point) {
                let fragmentStart = store.contentStorage.offset(from: store.contentStorage.documentRange.location, to: fragment.rangeInElement.location)
                let lineRange = NSRange(location: fragmentStart + line.characterRange.location, length: line.characterRange.length)
                var found: URL?
                store.attributedString.enumerateAttribute(.attachment, in: lineRange, options: []) { value, _, stop in
                    if let attachment = value as? InlineImageAttachment {
                        found = attachment.imageURL
                        stop.pointee = true
                    }
                }
                return found
            }
        }
        return nil
    }
}
