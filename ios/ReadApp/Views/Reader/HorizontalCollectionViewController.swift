import UIKit

protocol HorizontalCollectionViewDelegate: AnyObject {
    func horizontalCollectionView(_ collectionView: HorizontalCollectionViewController, didUpdatePageIndex index: Int)
    func horizontalCollectionView(_ collectionView: HorizontalCollectionViewController, didTapMiddle: Bool)
    func horizontalCollectionView(_ collectionView: HorizontalCollectionViewController, didTapLeft: Bool)
    func horizontalCollectionView(_ collectionView: HorizontalCollectionViewController, didTapRight: Bool)
    func horizontalCollectionView(_ collectionView: HorizontalCollectionViewController, requestChapterSwitch offset: Int)
}

class AnimatedPageLayout: UICollectionViewFlowLayout {
    var turningMode: PageTurningMode = .scroll

    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        return true 
    }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        let expandedRect = CGRect(x: rect.minX - rect.width, y: rect.minY, width: rect.width * 3, height: rect.height)
        guard let attributes = super.layoutAttributesForElements(in: expandedRect),
              let cv = collectionView else { return nil }

        let contentOffset = cv.contentOffset.x
        let width = cv.bounds.width
        guard width > 0 else { return attributes }

        return attributes.compactMap { $0.copy() as? UICollectionViewLayoutAttributes }.map { attr in
            let diff = attr.center.x - contentOffset - width / 2
            let progress = diff / width
        let absProgress = min(ReaderConstants.Animation.maxTransformAbsProgress, abs(progress))

            switch turningMode {
            case .fade:
                attr.alpha = 1.0 - absProgress
                attr.zIndex = progress < 0 ? ReaderConstants.Animation.fadeZIndexFront : ReaderConstants.Animation.fadeZIndexBack
                attr.transform = CGAffineTransform(translationX: -diff, y: 0)
                
            case .cover:
                if progress <= 0 {
                    attr.zIndex = ReaderConstants.Animation.coverZIndexFront
                    attr.alpha = 1.0
                    attr.transform = .identity
                } else if progress < 1.0 {
                    attr.zIndex = 0
                    attr.alpha = 1.0
                    attr.transform = CGAffineTransform(translationX: -diff, y: 0)
                } else {
                    attr.alpha = 0
                }
                
            case .flip:
                if absProgress > ReaderConstants.Animation.fadeCutoff {
                    attr.alpha = 0
                    return attr
                }
                let current = Int(round(contentOffset / width))
                if abs(attr.indexPath.item - current) > 1 {
                    attr.alpha = 0
                    return attr
                }
                attr.alpha = 1.0 - (absProgress * ReaderConstants.Animation.fadeCutoff)
                attr.zIndex = Int((1.0 - absProgress) * ReaderConstants.Animation.flipZIndexMax)
                
                var transform = CATransform3DIdentity
                transform.m34 = ReaderConstants.Animation.flipPerspective
                let angle = progress * ReaderConstants.Animation.flipMaxAngle
                
                // 先平移抵消位移，再以左右边缘作为旋转轴进行翻页
                let w = attr.size.width
                let pivot = progress > 0 ? -w / 2 : w / 2
                transform = CATransform3DTranslate(transform, -diff, 0, 0)
                transform = CATransform3DTranslate(transform, pivot, 0, 0)
                transform = CATransform3DRotate(transform, angle, 0, 1, 0)
                transform = CATransform3DTranslate(transform, -pivot, 0, 0)
                attr.transform3D = transform
                
            case .none:
                attr.alpha = 1.0
                attr.transform = .identity
                attr.zIndex = 0
                
            default: // .scroll
                attr.alpha = 1.0
                attr.transform = .identity
                attr.zIndex = 0
            }
            return attr
        }
    }
}

class HorizontalCollectionViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    
    struct CompositePage {
        enum Source {
            case previous
            case current
            case next
        }
        let source: Source
        let pageIndex: Int
        let pageInfo: TK2PageInfo?
        let renderStore: TextKit2RenderStore?
        let paragraphStarts: [Int]
        let prefixLen: Int
    }

    weak var delegate: HorizontalCollectionViewDelegate?
    var onImageTapped: ((URL) -> Void)?
    var onAddReplaceRule: ((String) -> Void)?
    var onInteractionChanged: ((Bool) -> Void)?
    
    private var compositePages: [CompositePage] = []
    private var hasPrevEdge: Bool = false
    private var hasNextEdge: Bool = false

    var sideMargin: CGFloat = ReaderConstants.Layout.defaultMargin
    var topInset: CGFloat = 0
    var themeBackgroundColor: UIColor = .white
    var turningMode: PageTurningMode = .scroll
    
    var currentPageIndex: Int = 0
    private var highlightIndex: Int?
    private var secondaryIndices: Set<Int> = []
    private var isPlayingHighlight: Bool = false
    private var highlightRange: NSRange?
    
    private(set) lazy var collectionView: UICollectionView = {
        let layout = AnimatedPageLayout()
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        layout.turningMode = self.turningMode
        
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.isPagingEnabled = true
        cv.backgroundColor = .clear
        cv.showsHorizontalScrollIndicator = false
        cv.dataSource = self
        cv.delegate = self
        cv.register(ReaderPageCell.self, forCellWithReuseIdentifier: "ReaderPageCell")
        return cv
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.addSubview(collectionView)
        var perspective = CATransform3DIdentity
        perspective.m34 = ReaderConstants.Animation.flipPerspective
        collectionView.layer.sublayerTransform = perspective
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    func update(
        pages: [PaginatedPage],
        pageInfos: [TK2PageInfo],
        renderStore: TextKit2RenderStore?,
        paragraphStarts: [Int],
        prefixLen: Int,
        sideMargin: CGFloat,
        topInset: CGFloat,
        anchorPageIndex: Int,
        backgroundColor: UIColor,
        turningMode: PageTurningMode,
        prevEdge: (TK2PageInfo, TextKit2RenderStore)? = nil,
        nextEdge: (TK2PageInfo, TextKit2RenderStore)? = nil
    ) {
        self.sideMargin = sideMargin
        self.topInset = topInset
        self.themeBackgroundColor = backgroundColor
        self.turningMode = turningMode
        
        var newComposite: [CompositePage] = []
        hasPrevEdge = prevEdge != nil
        if let prev = prevEdge {
            newComposite.append(CompositePage(source: .previous, pageIndex: 9999, pageInfo: prev.0, renderStore: prev.1, paragraphStarts: [], prefixLen: 0))
        }
        
        for (idx, info) in pageInfos.enumerated() {
            newComposite.append(CompositePage(source: .current, pageIndex: idx, pageInfo: info, renderStore: renderStore, paragraphStarts: paragraphStarts, prefixLen: prefixLen))
        }
        
        hasNextEdge = nextEdge != nil
        if let next = nextEdge {
            newComposite.append(CompositePage(source: .next, pageIndex: 0, pageInfo: next.0, renderStore: next.1, paragraphStarts: [], prefixLen: 0))
        }
        
        self.compositePages = newComposite
        self.currentPageIndex = anchorPageIndex
        
        if let layout = collectionView.collectionViewLayout as? AnimatedPageLayout {
            layout.turningMode = turningMode
        }
        
        collectionView.isPagingEnabled = (turningMode == .scroll || turningMode == .none)
        collectionView.decelerationRate = (turningMode == .scroll || turningMode == .none) ? .normal : .fast
        
        view.backgroundColor = backgroundColor
        collectionView.backgroundColor = backgroundColor
        collectionView.reloadData()
        collectionView.layoutIfNeeded()
        
        let targetCompositeIndex = hasPrevEdge ? (anchorPageIndex + 1) : anchorPageIndex
        scrollToCompositeIndex(targetCompositeIndex, animated: false)
    }

    func updateHighlight(index: Int?, secondary: Set<Int>, isPlaying: Bool, highlightRange: NSRange?) {
        if highlightIndex == index && secondaryIndices == secondary && isPlayingHighlight == isPlaying && self.highlightRange == highlightRange {
            return
        }
        highlightIndex = index
        secondaryIndices = secondary
        isPlayingHighlight = isPlaying
        self.highlightRange = highlightRange
        for cell in collectionView.visibleCells {
            guard let readerCell = cell as? ReaderPageCell else { continue }
            readerCell.updateHighlight(index: index, secondary: secondary, isPlaying: isPlaying, highlightRange: highlightRange)
        }
    }
    
    private func scrollToCompositeIndex(_ index: Int, animated: Bool) {
        guard index >= 0 && index < compositePages.count else { return }
        let width = collectionView.bounds.width
        if width > 0 {
            let targetX = CGFloat(index) * width
            collectionView.setContentOffset(CGPoint(x: targetX, y: 0), animated: animated)
        } else {
            let indexPath = IndexPath(item: index, section: 0)
            collectionView.scrollToItem(at: indexPath, at: .centeredHorizontally, animated: animated)
        }
        if !animated {
            collectionView.collectionViewLayout.invalidateLayout()
            collectionView.layoutIfNeeded()
        }
    }

    func scrollToPageIndex(_ index: Int, animated: Bool) {
        let compositeIdx = hasPrevEdge ? (index + 1) : index
        currentPageIndex = index
        scrollToCompositeIndex(compositeIdx, animated: animated)
    }
    
    func resetScrollState() {
        collectionView.setContentOffset(collectionView.contentOffset, animated: false)
        collectionView.isUserInteractionEnabled = false
        collectionView.isUserInteractionEnabled = true
    }
    
    // MARK: - UICollectionViewDataSource
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return compositePages.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "ReaderPageCell", for: indexPath) as! ReaderPageCell
        let comp = compositePages[indexPath.item]
        
        if let info = comp.pageInfo {
            cell.update(
                renderStore: comp.renderStore,
                pageIndex: comp.pageIndex,
                pageInfo: info,
                paragraphStarts: comp.paragraphStarts,
                prefixLen: comp.prefixLen,
                sideMargin: sideMargin,
                topInset: topInset,
                backgroundColor: themeBackgroundColor
            )
        }
        
        if comp.source == .current {
            cell.updateHighlight(index: highlightIndex, secondary: secondaryIndices, isPlaying: isPlayingHighlight, highlightRange: highlightRange)
        } else {
            cell.updateHighlight(index: nil, secondary: [], isPlaying: false, highlightRange: nil)
        }
        
        cell.onTapLocation = { [weak self] location in
            guard let self = self else { return }
            switch location {
            case .middle: self.delegate?.horizontalCollectionView(self, didTapMiddle: true)
            case .left: self.delegate?.horizontalCollectionView(self, didTapLeft: true)
            case .right: self.delegate?.horizontalCollectionView(self, didTapRight: true)
            }
        }
        cell.onImageTapped = { [weak self] url in
            self?.onImageTapped?(url)
        }
        cell.onAddReplaceRule = { [weak self] text in
            self?.onAddReplaceRule?(text)
        }
        
        return cell
    }
    
    // MARK: - UICollectionViewDelegateFlowLayout
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        return collectionView.bounds.size
    }
    
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        onInteractionChanged?(true)
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        onInteractionChanged?(false)
        syncCurrentPageAfterScroll(scrollView)
    }
    
    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        syncCurrentPageAfterScroll(scrollView)
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            onInteractionChanged?(false)
            syncCurrentPageAfterScroll(scrollView)
        }
    }
    
    private func syncCurrentPageAfterScroll(_ scrollView: UIScrollView) {
        let width = scrollView.bounds.width
        guard width > 0 else { return }
        let compositeIdx = Int(round(scrollView.contentOffset.x / width))
        guard compositeIdx >= 0 && compositeIdx < compositePages.count else { return }
        
        let comp = compositePages[compositeIdx]
        if comp.source == .current {
            currentPageIndex = comp.pageIndex
            delegate?.horizontalCollectionView(self, didUpdatePageIndex: comp.pageIndex)
        } else if comp.source == .previous {
            delegate?.horizontalCollectionView(self, requestChapterSwitch: -1)
        } else if comp.source == .next {
            delegate?.horizontalCollectionView(self, requestChapterSwitch: 1)
        }
    }

    func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        guard !collectionView.isPagingEnabled else { return }
        
        let width = scrollView.bounds.width
        guard width > 0 else { return }
        
        let currentX = scrollView.contentOffset.x
        let estimatedPage = currentX / width
        
        var targetPage: Int
        if abs(velocity.x) > ReaderConstants.Interaction.velocitySnapThreshold {
            targetPage = velocity.x > 0 ? Int(ceil(estimatedPage)) : Int(floor(estimatedPage))
        } else {
            targetPage = Int(round(estimatedPage))
        }
        
        targetPage = max(0, min(compositePages.count - 1, targetPage))
        scrollToCompositeIndex(targetPage, animated: true)
        targetContentOffset.pointee = scrollView.contentOffset
    }

    private var lastSwitchRequestTime: TimeInterval = 0
    private let switchRequestCooldown: TimeInterval = ReaderConstants.Interaction.switchRequestCooldown

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        // 有复合页时，由复合页落点触发切章，避免双触发
        if hasPrevEdge || hasNextEdge { return }
        let offsetX = scrollView.contentOffset.x
        let width = scrollView.bounds.width
        let contentWidth = scrollView.contentSize.width
        if turningMode == .flip, let layout = collectionView.collectionViewLayout as? AnimatedPageLayout {
            layout.invalidateLayout()
        }
        
        let now = Date().timeIntervalSince1970
        guard now - lastSwitchRequestTime > switchRequestCooldown else { return }
        
        let switchOffset = detectChapterSwitchOffset(offsetX: offsetX, width: width, contentWidth: contentWidth)
        if switchOffset != 0 {
            lastSwitchRequestTime = now
            delegate?.horizontalCollectionView(self, requestChapterSwitch: switchOffset)
        }
    }
    
    private func detectChapterSwitchOffset(offsetX: CGFloat, width: CGFloat, contentWidth: CGFloat) -> Int {
        let threshold = ReaderConstants.Interaction.horizontalSwitchThreshold
        if offsetX > contentWidth - width + threshold {
            return 1
        } else if offsetX < -threshold {
            return -1
        }
        return 0
    }
}

class ReaderPageCell: UICollectionViewCell {
    private let contentView2 = ReadContent2View(frame: .zero)
    
    var onTapLocation: ((ReaderTapLocation) -> Void)?
    var onImageTapped: ((URL) -> Void)?
    var onAddReplaceRule: ((String) -> Void)?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.isDoubleSided = false
        contentView.layer.isDoubleSided = false
        contentView.clipsToBounds = true
        contentView.addSubview(contentView2)
        contentView2.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            contentView2.topAnchor.constraint(equalTo: contentView.topAnchor),
            contentView2.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            contentView2.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            contentView2.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
        
        contentView2.onTapLocation = { [weak self] loc in
            self?.onTapLocation?(loc)
        }
        contentView2.onImageTapped = { [weak self] url in
            self?.onImageTapped?(url)
        }
        contentView2.onAddReplaceRule = { [weak self] text in
            self?.onAddReplaceRule?(text)
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func update(renderStore: TextKit2RenderStore?, pageIndex: Int, pageInfo: TK2PageInfo, paragraphStarts: [Int], prefixLen: Int, sideMargin: CGFloat, topInset: CGFloat, backgroundColor: UIColor) {
        contentView2.backgroundColor = backgroundColor
        contentView2.renderStore = renderStore
        contentView2.pageIndex = pageIndex
        contentView2.pageInfo = pageInfo
        contentView2.paragraphStarts = paragraphStarts
        contentView2.chapterPrefixLen = prefixLen
        contentView2.horizontalInset = sideMargin
        contentView2.setNeedsDisplay()
    }

    func updateHighlight(index: Int?, secondary: Set<Int>, isPlaying: Bool, highlightRange: NSRange?) {
        contentView2.highlightIndex = index
        contentView2.secondaryIndices = secondary
        contentView2.isPlayingHighlight = isPlaying
        contentView2.highlightRange = highlightRange
    }
}

class PageContentViewController: UIViewController { var pageIndex: Int; var chapterOffset: Int; init(pageIndex: Int, chapterOffset: Int) { self.pageIndex = pageIndex; self.chapterOffset = chapterOffset; super.init(nibName: nil, bundle: nil) }; required init?(coder: NSCoder) { fatalError() } }
