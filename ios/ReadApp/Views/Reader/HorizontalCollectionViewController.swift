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
        return turningMode != .scroll && turningMode != .none
    }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        // 关键：扩大探测范围，确保邻近页面参与动画计算，即使它们在逻辑位置上不在当前 rect 内
        let expandedRect = rect.insetBy(dx: -rect.width, dy: 0)
        let attributes = super.layoutAttributesForElements(in: expandedRect)
        guard let cv = collectionView, turningMode != .scroll && turningMode != .none else { return attributes }

        let contentOffset = cv.contentOffset.x
        let width = cv.bounds.width
        guard width > 0 else { return attributes }

        attributes?.forEach { attr in
            let diff = attr.center.x - contentOffset - width / 2
            let progress = diff / width
            let absProgress = min(1.0, abs(progress))

            switch turningMode {
            case .fade:
                attr.alpha = 1.0 - absProgress
                attr.transform = .identity
                attr.zIndex = progress < 0 ? 1 : 0
            case .cover:
                if progress < 0 {
                    // 正在向左滑出的旧页面：保持在最上层，随手指滑动
                    attr.zIndex = 1
                    attr.alpha = 1.0
                    attr.transform = .identity
                } else {
                    // 准备从右侧露出的新页面：在下层，固定在视口原点不动
                    attr.zIndex = 0
                    attr.alpha = 1.0
                    let tx = -diff // 抵消 CollectionView 的位移，使其静止在下方
                    attr.transform = CGAffineTransform(translationX: tx, y: 0)
                }
            case .flip:
                attr.alpha = 1.0 - (absProgress * 0.5)
                attr.zIndex = progress < 0 ? 1 : 0
                var transform = CATransform3DIdentity
                transform.m34 = -1.0 / 1000.0
                let angle = progress * (.pi / 2)
                transform = CATransform3DRotate(transform, angle, 0, 1, 0)
                attr.transform3D = transform
            default:
                attr.alpha = 1.0
                attr.transform = .identity
            }
        }
        return attributes
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

    private var lastSwitchRequestTime: TimeInterval = 0
    private let switchRequestCooldown: TimeInterval = 1.0

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let offsetX = scrollView.contentOffset.x
        let width = scrollView.bounds.width
        let contentWidth = scrollView.contentSize.width
        
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