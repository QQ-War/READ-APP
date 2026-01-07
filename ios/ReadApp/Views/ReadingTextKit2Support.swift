import SwiftUI
import UIKit

final class TextKit2RenderStore {
    let contentStorage: NSTextContentStorage
    let layoutManager: NSTextLayoutManager
    let textContainer: NSTextContainer
    var attributedString: NSAttributedString
    var layoutWidth: CGFloat // Stored layout width
    
    init(attributedString: NSAttributedString, layoutWidth: CGFloat) {
        self.attributedString = attributedString
        self.layoutWidth = layoutWidth // Store layout width
        
        contentStorage = NSTextContentStorage()
        contentStorage.textStorage = NSTextStorage(attributedString: attributedString)
        
        layoutManager = NSTextLayoutManager()
        contentStorage.addTextLayoutManager(layoutManager)
        
        textContainer = NSTextContainer(size: CGSize(width: layoutWidth, height: 0))
        textContainer.lineFragmentPadding = 0
        layoutManager.textContainer = textContainer
    }
    
    func update(attributedString newAttributedString: NSAttributedString, layoutWidth newLayoutWidth: CGFloat) {
        self.attributedString = newAttributedString
        self.contentStorage.textStorage = NSTextStorage(attributedString: newAttributedString)
        self.layoutWidth = newLayoutWidth
        self.textContainer.size = CGSize(width: newLayoutWidth, height: 0)
        // Re-binding container to force internal layout invalidation
        self.layoutManager.textContainer = nil
        self.layoutManager.textContainer = self.textContainer
    }
}

struct TextKit2Paginator {
    
    struct PaginationResult {
        let pages: [PaginatedPage]
        let pageInfos: [TK2PageInfo]
        let reachedEnd: Bool
    }
    
    static func paginate(
        renderStore: TextKit2RenderStore,
        pageSize: CGSize,
        paragraphStarts: [Int],
        prefixLen: Int,
        topInset: CGFloat,
        bottomInset: CGFloat,
        maxPages: Int = Int.max,
        startOffset: Int = 0
    ) -> PaginationResult {
        let layoutManager = renderStore.layoutManager
        let contentStorage = renderStore.contentStorage
        let documentRange = contentStorage.documentRange
        
        guard !documentRange.isEmpty, pageSize.width > 1, pageSize.height > 1 else {
            return PaginationResult(pages: [], pageInfos: [], reachedEnd: true)
        }

        layoutManager.ensureLayout(for: documentRange)

        var pages: [PaginatedPage] = []
        var pageInfos: [TK2PageInfo] = []
        var pageCount = 0
        let pageContentHeight = max(1, pageSize.height - topInset - bottomInset)
        
        var currentContentLocation: NSTextLocation = documentRange.location
        if startOffset > 0, let startLoc = contentStorage.location(documentRange.location, offsetBy: startOffset) {
            currentContentLocation = startLoc
        }
        
        // Helper to find the visual top Y of the line containing a specific location
        func findLineTopY(at location: NSTextLocation) -> CGFloat? {
            guard let fragment = layoutManager.textLayoutFragment(for: location) else { return nil }
            let fragFrame = fragment.layoutFragmentFrame
            let offsetInFrag = contentStorage.offset(from: fragment.rangeInElement.location, to: location)
            
            // If location is at start of fragment, return fragment minY (or first line minY)
            if offsetInFrag == 0 {
                if let firstLine = fragment.textLineFragments.first {
                    return firstLine.typographicBounds.minY + fragFrame.minY
                }
                return fragFrame.minY
            }
            
            // Otherwise find the specific line
            for line in fragment.textLineFragments {
                let lineRange = line.characterRange
                if offsetInFrag < lineRange.upperBound {
                    return line.typographicBounds.minY + fragFrame.minY
                }
            }
            // Fallback to fragment bottom if not found (shouldn't happen for valid loc)
            return fragFrame.maxY
        }
        
        // Helper to find the end location of the line containing (or after) the given location
        func nextLineEndLocation(from location: NSTextLocation) -> NSTextLocation? {
            guard let fragment = layoutManager.textLayoutFragment(for: location) else { return nil }
            let fragStart = contentStorage.offset(from: documentRange.location, to: fragment.rangeInElement.location)
            let offsetInFrag = contentStorage.offset(from: fragment.rangeInElement.location, to: location)
            
            for line in fragment.textLineFragments {
                let lineEnd = line.characterRange.upperBound
                if lineEnd > offsetInFrag {
                    let globalEnd = fragStart + lineEnd
                    return contentStorage.location(documentRange.location, offsetBy: globalEnd)
                }
            }
            return fragment.rangeInElement.endLocation
        }

        while pageCount < maxPages {
            let remainingOffset = layoutManager.offset(from: currentContentLocation, to: documentRange.endLocation)
            guard remainingOffset > 0 else { break }
            
            // 1. Determine the start Y for this page based on the current content location
            // This ensures we align exactly to the top of the next line, ignoring previous page's bottom gaps.
            let rawPageStartY = findLineTopY(at: currentContentLocation) ?? 0
            let pixel = max(1.0 / UIScreen.main.scale, 0.5)
            let pageStartY = floor(rawPageStartY / pixel) * pixel
            
            let pageRect = CGRect(x: 0, y: pageStartY, width: pageSize.width, height: pageContentHeight)
            let lineEdgeInset: CGFloat = 0
            let lineEdgeSlack: CGFloat = 0
            
            var pageFragmentMaxY: CGFloat?
            var pageEndLocation: NSTextLocation = currentContentLocation
            
            layoutManager.enumerateTextLayoutFragments(from: currentContentLocation, options: [.ensuresLayout, .ensuresExtraLineFragment]) { fragment in
                let fragmentFrame = fragment.layoutFragmentFrame
                let fragmentRange = TextKit2Paginator.rangeFromTextRange(fragment.rangeInElement, in: contentStorage)
                
                if fragmentFrame.minY >= pageRect.maxY { return false }
                
                // If fragment is completely above (shouldn't happen with correct startY), skip
                if fragmentFrame.maxY <= pageStartY { return true }

                if pageFragmentMaxY == nil { pageFragmentMaxY = max(pageStartY, fragmentFrame.minY) }
                
                if fragmentFrame.maxY <= pageRect.maxY {
                    // Fragment fits entirely
                    pageFragmentMaxY = fragmentFrame.maxY
                    if let fragmentRange = fragmentRange,
                       let loc = contentStorage.location(documentRange.location, offsetBy: NSMaxRange(fragmentRange)) {
                        pageEndLocation = loc
                    } else {
                        pageEndLocation = fragment.rangeInElement.endLocation
                    }
                    return true
                } else {
                    // Fragment splits across page boundary
                    let currentStartOffset = contentStorage.offset(from: documentRange.location, to: currentContentLocation)
                    var foundVisibleLine = false
                    
                    for line in fragment.textLineFragments {
                        let lineRange = line.characterRange
                        // Calculate global offset for this line end
                        let lineEndGlobalOffset: Int
                        if let fragmentRange = fragmentRange {
                             lineEndGlobalOffset = fragmentRange.location + lineRange.upperBound
                        } else {
                             // Fallback approximation (unsafe but rare)
                             lineEndGlobalOffset = currentStartOffset + lineRange.upperBound
                        }
                        
                        // Skip lines before our start point
                        if lineEndGlobalOffset <= currentStartOffset { continue }

                        let lineFrame = line.typographicBounds.offsetBy(dx: fragmentFrame.origin.x, dy: fragmentFrame.origin.y)

                        if lineFrame.maxY <= pageRect.maxY - lineEdgeInset + lineEdgeSlack {
                            if let loc = contentStorage.location(documentRange.location, offsetBy: lineEndGlobalOffset) {
                                pageEndLocation = loc
                                pageFragmentMaxY = lineFrame.maxY
                                foundVisibleLine = true
                            }
                        } else {
                            break
                        }
                    }
                    
                    // If no lines fit (e.g. huge line or top of page), force at least one line if it's the first item
                    if !foundVisibleLine {
                         // Find the first line that effectively starts after our current location
                         if let firstLine = fragment.textLineFragments.first(where: { line in
                            let endOff = (fragmentRange?.location ?? 0) + line.characterRange.upperBound
                            return endOff > currentStartOffset
                         }) {
                             // If this is the VERY first line of the page and it doesn't fit, we must include it to avoid infinite loop
                             // Check if we haven't advanced pageEndLocation yet
                             let isAtPageStart = contentStorage.offset(from: currentContentLocation, to: pageEndLocation) == 0
                             
                             if isAtPageStart {
                                let endOffset = firstLine.characterRange.upperBound
                                let globalEndOffset = (fragmentRange?.location ?? 0) + endOffset
                                pageEndLocation = contentStorage.location(documentRange.location, offsetBy: globalEndOffset) ?? pageEndLocation
                                let lineFrame = firstLine.typographicBounds.offsetBy(dx: fragmentFrame.origin.x, dy: fragmentFrame.origin.y)
                                pageFragmentMaxY = lineFrame.maxY
                             }
                         }
                    }
                    return false
                }
            }
            
            let startOffset = contentStorage.offset(from: documentRange.location, to: currentContentLocation)
            var endOffset = contentStorage.offset(from: documentRange.location, to: pageEndLocation)
            
            // Failsafe: Ensure progress
            if endOffset <= startOffset {
                if let forced = nextLineEndLocation(from: currentContentLocation) {
                    pageEndLocation = forced
                    endOffset = contentStorage.offset(from: documentRange.location, to: pageEndLocation)
                } else if let forced = layoutManager.location(currentContentLocation, offsetBy: 1) {
                    pageEndLocation = forced
                    endOffset = contentStorage.offset(from: documentRange.location, to: pageEndLocation)
                } else {
                    break
                }
            }

            let pageRange = NSRange(location: startOffset, length: endOffset - startOffset)
            let actualContentHeight = (pageFragmentMaxY ?? (pageStartY + pageContentHeight)) - pageStartY
            let adjustedLocation = max(0, pageRange.location - prefixLen)
            let startIdx = paragraphStarts.lastIndex(where: { $0 <= adjustedLocation }) ?? 0
            
            pages.append(PaginatedPage(globalRange: pageRange, startSentenceIndex: startIdx))
            pageInfos.append(TK2PageInfo(range: pageRange, yOffset: pageStartY, pageHeight: pageContentHeight, actualContentHeight: actualContentHeight, startSentenceIndex: startIdx, contentInset: topInset))
            
            pageCount += 1
            currentContentLocation = pageEndLocation
        }

        let reachedEnd = layoutManager.offset(from: currentContentLocation, to: documentRange.endLocation) == 0
        return PaginationResult(pages: pages, pageInfos: pageInfos, reachedEnd: reachedEnd)
    }

    static func rangeFromTextRange(_ textRange: NSTextRange?, in content: NSTextContentStorage) -> NSRange? {
        guard let textRange = textRange else { return nil }
        let location = content.offset(from: content.documentRange.location, to: textRange.location)
        let length = content.offset(from: textRange.location, to: textRange.endLocation)
        return NSRange(location: location, length: length)
    }
}

class ReadContent2View: UIView {
    var renderStore: TextKit2RenderStore?
    var pageInfo: TK2PageInfo?
    var onTapLocation: ((ReaderTapLocation) -> Void)?
    var onAddReplaceRule: ((String) -> Void)?
    var highlightIndex: Int?
    var secondaryIndices: Set<Int> = []
    var isPlayingHighlight: Bool = false
    var paragraphStarts: [Int] = []
    var chapterPrefixLen: Int = 0
    var horizontalInset: CGFloat = 0
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        self.backgroundColor = .clear
        self.clipsToBounds = true
        
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        self.addGestureRecognizer(tap)
        
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        self.addGestureRecognizer(longPress)
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    override func draw(_ rect: CGRect) {
        guard let store = renderStore, let info = pageInfo else { return }
        
        let context = UIGraphicsGetCurrentContext()
        context?.saveGState()
        
        // Translate context to start drawing from the current page's yOffset with insets
        context?.translateBy(x: horizontalInset, y: -(info.yOffset - info.contentInset))
        
        // Clip to content area (exclude top/bottom insets) to avoid edge bleed
        let contentClip = CGRect(
            x: 0,
            y: info.contentInset,
            width: max(0, bounds.width - horizontalInset * 2),
            height: info.pageHeight
        )
        context?.clip(to: contentClip)
        
        let startLoc = store.contentStorage.location(store.contentStorage.documentRange.location, offsetBy: info.range.location)
        
        let contentStorage = store.contentStorage
        let pageStartOffset = info.range.location
        let pageEndOffset = NSMaxRange(info.range)
        var shouldStop = false
        
        // 渲染背景高亮
        if isPlayingHighlight {
            context?.saveGState()
            
            // 准备高亮范围映射
            func getRangeForSentence(_ index: Int) -> NSRange? {
                guard index >= 0 && index < paragraphStarts.count else { return nil }
                let start = paragraphStarts[index] + chapterPrefixLen
                let end = (index + 1 < paragraphStarts.count) ? (paragraphStarts[index + 1] + chapterPrefixLen) : store.attributedString.length
                return NSRange(location: start, length: end - start)
            }
            
            let highlightIndices = ([highlightIndex].compactMap { $0 }) + Array(secondaryIndices)
            
            for index in highlightIndices {
                guard let sRange = getRangeForSentence(index) else { continue }
                let intersection = NSIntersectionRange(sRange, info.range)
                if intersection.length <= 0 { continue }
                
                let color = (index == highlightIndex) ? UIColor.systemBlue.withAlphaComponent(0.2) : UIColor.systemGreen.withAlphaComponent(0.12)
                context?.setFillColor(color.cgColor)
                
                // 找到相交行的矩形区域
                store.layoutManager.enumerateTextLayoutFragments(from: store.contentStorage.location(store.contentStorage.documentRange.location, offsetBy: intersection.location), options: [.ensuresLayout]) { fragment in
                    let fFrame = fragment.layoutFragmentFrame
                    guard let fRange = TextKit2Paginator.rangeFromTextRange(fragment.rangeInElement, in: store.contentStorage) else { return true }
                    
                    if fRange.location >= NSMaxRange(intersection) { return false }
                    
                    for line in fragment.textLineFragments {
                        let lStart = fRange.location + line.characterRange.location
                        let lEnd = fRange.location + line.characterRange.upperBound
                        
                        let lInter = NSIntersectionRange(NSRange(location: lStart, length: lEnd - lStart), intersection)
                        if lInter.length > 0 {
                            // 计算行内具体字符的 X 偏移（简化处理：整行高亮，因为阅读器通常是按段落/句子请求音频）
                            let lineFrame = line.typographicBounds.offsetBy(dx: fFrame.origin.x, dy: fFrame.origin.y)
                            let contentWidth = max(0, bounds.width - horizontalInset * 2)
                            let bleed: CGFloat = 2
                            let highlightRect = CGRect(x: -bleed, y: lineFrame.minY, width: contentWidth + bleed * 2, height: lineFrame.height)
                            context?.fill(highlightRect)
                        }
                    }
                    return true
                }
            }
            context?.restoreGState()
        }
        
        store.layoutManager.enumerateTextLayoutFragments(from: startLoc, options: [.ensuresLayout]) { fragment in
            if shouldStop { return false }
            let frame = fragment.layoutFragmentFrame
            
            if frame.minY >= info.yOffset + info.pageHeight { return false }
            
            guard let fragmentRange = TextKit2Paginator.rangeFromTextRange(fragment.rangeInElement, in: contentStorage) else {
                if frame.maxY > info.yOffset {
                    fragment.draw(at: frame.origin, in: context!)
                }
                return true
            }
            
            let fragmentStart = fragmentRange.location
            let fragmentEnd = NSMaxRange(fragmentRange)
            
            if fragmentEnd <= pageStartOffset { return true }
            if fragmentStart >= pageEndOffset { return false }
            
            for line in fragment.textLineFragments {
                let lineStart = fragmentStart + line.characterRange.location
                let lineEnd = fragmentStart + line.characterRange.upperBound
                
                if lineEnd <= pageStartOffset { continue }
                if lineStart >= pageEndOffset {
                    shouldStop = true
                    break
                }
                
                let lineFrame = line.typographicBounds.offsetBy(dx: frame.origin.x, dy: frame.origin.y)
                if lineFrame.maxY <= info.yOffset { continue }
                if lineFrame.minY >= info.yOffset + info.pageHeight {
                    shouldStop = true
                    break
                }
                let contentWidth = max(0, bounds.width - horizontalInset * 2)
                let bleed: CGFloat = 2
                let lineDrawRect = CGRect(x: -bleed, y: lineFrame.minY, width: contentWidth + bleed * 2, height: lineFrame.height)
                context?.saveGState()
                context?.clip(to: lineDrawRect)
                fragment.draw(at: frame.origin, in: context!)
                context?.restoreGState()
            }
            
            return !shouldStop
        }
        
        context?.restoreGState()
    }
    
    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let x = gesture.location(in: self).x
        let w = bounds.width
        if x < w / 3 { onTapLocation?(.left) }
        else if x > w * 2 / 3 { onTapLocation?(.right) }
        else { onTapLocation?(.middle) }
    }
    
    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, let store = renderStore, let info = pageInfo else { return }
        let point = gesture.location(in: self)
        let adjustedPoint = CGPoint(x: point.x, y: point.y + info.yOffset - info.contentInset)
        
        if let fragment = store.layoutManager.textLayoutFragment(for: adjustedPoint),
           let textElement = fragment.textElement,
           let nsRange = TextKit2Paginator.rangeFromTextRange(textElement.elementRange, in: store.contentStorage) {
            let text = (store.attributedString.string as NSString).substring(with: nsRange)
            becomeFirstResponder()
            let menu = UIMenuController.shared
            menu.showMenu(from: self, rect: CGRect(origin: point, size: .zero))
            self.pendingSelectedText = text
        }
    }
    
    private var pendingSelectedText: String? { didSet { if pendingSelectedText == nil { becomeFirstResponder() } } }
    
    override var canBecomeFirstResponder: Bool { true }
    
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        return action == #selector(addToReplaceRule)
    }
    
    @objc func addToReplaceRule() {
        if let text = pendingSelectedText { onAddReplaceRule?(text) }
    }
}
