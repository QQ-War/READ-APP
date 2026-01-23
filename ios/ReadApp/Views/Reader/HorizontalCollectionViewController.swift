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
            let absProgress = min(1.0, abs(progress))

            switch turningMode {
            case .fade:
                attr.alpha = 1.0 - absProgress
                attr.zIndex = progress < 0 ? 10 : 5
                attr.transform = CGAffineTransform(translationX: -diff, y: 0)
                
            case .cover:
                if progress <= 0 {
                    attr.zIndex = 100
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
                if absProgress > 0.6 {
                    attr.alpha = 0
                    return attr
                }
                let current = Int(round(contentOffset / width))
                if abs(attr.indexPath.item - current) > 1 {
                    attr.alpha = 0
                    return attr
                }
                attr.alpha = 1.0 - (absProgress * 0.6)
                attr.zIndex = Int((1.0 - absProgress) * 1000.0)
                
                var transform = CATransform3DIdentity
                transform.m34 = -1.0 / 1000.0
                let angle = progress * (.pi / 2)
                
                // 先平移抵消位移，再以左右边缘作为旋转轴进行翻页
                let w = attr.size.width
                let pivot = progress > 0 ? -w / 2 : w / 2
                transform = CATransform3DTranslate(transform, -diff, 0, 0)
                transform = CATransform3DTranslate(transform, pivot, 0, 0)
                transform = CATransform3DRotate(transform, angle, 0, 1, 0)
                transform = CATransform3DTranslate(transform, -pivot, 0, 0)
                attr.transform3D = transform
                
            case .none:
                attr.alpha = absProgress < 0.1 ? 1.0 : 0
                attr.transform = CGAffineTransform(translationX: -diff, y: 0)
                
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
    
    weak var delegate: HorizontalCollectionViewDelegate?
    
    var pages: [PaginatedPage] = []
    var pageInfos: [TK2PageInfo] = []
    var renderStore: TextKit2RenderStore?
    var paragraphStarts: [Int] = []
    var chapterPrefixLen: Int = 0
    var sideMargin: CGFloat = 20
    var topInset: CGFloat = 0
    var themeBackgroundColor: UIColor = .white
    var turningMode: PageTurningMode = .scroll
    
    var currentPageIndex: Int = 0
    
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
        perspective.m34 = -1.0 / 1000.0
        collectionView.layer.sublayerTransform = perspective
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    func update(pages: [PaginatedPage], pageInfos: [TK2PageInfo], renderStore: TextKit2RenderStore?, paragraphStarts: [Int], prefixLen: Int, sideMargin: CGFloat, topInset: CGFloat, anchorPageIndex: Int, backgroundColor: UIColor, turningMode: PageTurningMode) {
        self.pages = pages
        self.pageInfos = pageInfos
        self.renderStore = renderStore
        self.paragraphStarts = paragraphStarts
        self.chapterPrefixLen = prefixLen
        self.sideMargin = sideMargin
        self.topInset = topInset
        self.currentPageIndex = anchorPageIndex
        self.themeBackgroundColor = backgroundColor
        self.turningMode = turningMode
        
        if let layout = collectionView.collectionViewLayout as? AnimatedPageLayout {
            layout.turningMode = turningMode
        }
        
        // 优化：非平滑滚动模式下关闭系统分页，改用自定义吸附，以支持更精细的动画控制
        collectionView.isPagingEnabled = (turningMode == .scroll)
        collectionView.decelerationRate = (turningMode == .scroll) ? .normal : .fast
        
        view.backgroundColor = backgroundColor
        collectionView.backgroundColor = backgroundColor
        collectionView.reloadData()
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.scrollToPageIndex(anchorPageIndex, animated: false)
        }
    }
    
    func scrollToPageIndex(_ index: Int, animated: Bool) {
        guard index >= 0 && index < pages.count else { return }
        currentPageIndex = index
        let indexPath = IndexPath(item: index, section: 0)
        collectionView.scrollToItem(at: indexPath, at: .centeredHorizontally, animated: animated)
    }
    
    // MARK: - UICollectionViewDataSource
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return pages.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "ReaderPageCell", for: indexPath) as! ReaderPageCell
        
        if indexPath.item < pageInfos.count {
            let info = pageInfos[indexPath.item]
            cell.update(
                renderStore: renderStore,
                pageIndex: indexPath.item,
                pageInfo: info,
                paragraphStarts: paragraphStarts,
                prefixLen: chapterPrefixLen,
                sideMargin: sideMargin,
                topInset: topInset,
                backgroundColor: themeBackgroundColor
            )
        }
        
        cell.onTapLocation = { [weak self] location in
            guard let self = self else { return }
            switch location {
            case .middle: self.delegate?.horizontalCollectionView(self, didTapMiddle: true)
            case .left: self.delegate?.horizontalCollectionView(self, didTapLeft: true)
            case .right: self.delegate?.horizontalCollectionView(self, didTapRight: true)
            }
        }
        
        return cell
    }
    
    // MARK: - UICollectionViewDelegateFlowLayout
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        return collectionView.bounds.size
    }
    
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        let width = scrollView.bounds.width
        guard width > 0 else { return }
        let page = Int(round(scrollView.contentOffset.x / width))
        if page >= 0 && page < pages.count {
            currentPageIndex = page
            delegate?.horizontalCollectionView(self, didUpdatePageIndex: page)
        }
    }
    
    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        let width = scrollView.bounds.width
        guard width > 0 else { return }
        let page = Int(round(scrollView.contentOffset.x / width))
        if page >= 0 && page < pages.count {
            currentPageIndex = page
            delegate?.horizontalCollectionView(self, didUpdatePageIndex: page)
        }
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            let width = scrollView.bounds.width
            guard width > 0 else { return }
            let page = Int(round(scrollView.contentOffset.x / width))
            if page >= 0 && page < pages.count {
                currentPageIndex = page
                delegate?.horizontalCollectionView(self, didUpdatePageIndex: page)
            }
        }
    }

    func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        // 只有在关闭系统分页时才手动计算吸附位置
        guard !collectionView.isPagingEnabled else { return }
        
        let width = scrollView.bounds.width
        guard width > 0 else { return }
        
        let currentX = scrollView.contentOffset.x
        let estimatedPage = currentX / width
        
        var targetPage: Int
        if abs(velocity.x) > 0.2 {
            targetPage = velocity.x > 0 ? Int(ceil(estimatedPage)) : Int(floor(estimatedPage))
        } else {
            targetPage = Int(round(estimatedPage))
        }
        
        targetPage = max(0, min(pages.count - 1, targetPage))
        targetContentOffset.pointee = CGPoint(x: CGFloat(targetPage) * width, y: 0)
    }

    private var lastSwitchRequestTime: TimeInterval = 0
    private let switchRequestCooldown: TimeInterval = 1.0

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let offsetX = scrollView.contentOffset.x
        let width = scrollView.bounds.width
        let contentWidth = scrollView.contentSize.width
        if turningMode == .flip, let layout = collectionView.collectionViewLayout as? AnimatedPageLayout {
            layout.invalidateLayout()
        }
        
        let now = Date().timeIntervalSince1970
        guard now - lastSwitchRequestTime > switchRequestCooldown else { return }

        // 检测向后翻页（超出末尾）
        if offsetX > contentWidth - width + 50 {
            lastSwitchRequestTime = now
            delegate?.horizontalCollectionView(self, requestChapterSwitch: 1)
        }
        // 检测向前翻页（超出开头）
        else if offsetX < -50 {
            lastSwitchRequestTime = now
            delegate?.horizontalCollectionView(self, requestChapterSwitch: -1)
        }
    }
}

class ReaderPageCell: UICollectionViewCell {
    private let contentView2 = ReadContent2View(frame: .zero)
    
    var onTapLocation: ((ReaderTapLocation) -> Void)?
    
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
}

class PageContentViewController: UIViewController { var pageIndex: Int; var chapterOffset: Int; init(pageIndex: Int, chapterOffset: Int) { self.pageIndex = pageIndex; self.chapterOffset = chapterOffset; super.init(nibName: nil, bundle: nil) }; required init?(coder: NSCoder) { fatalError() } }
