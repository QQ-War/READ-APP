import UIKit

protocol HorizontalCollectionViewDelegate: AnyObject {
    func horizontalCollectionView(_ collectionView: HorizontalCollectionViewController, didUpdatePageIndex index: Int)
    func horizontalCollectionView(_ collectionView: HorizontalCollectionViewController, didTapMiddle: Bool)
    func horizontalCollectionView(_ collectionView: HorizontalCollectionViewController, didTapLeft: Bool)
    func horizontalCollectionView(_ collectionView: HorizontalCollectionViewController, didTapRight: Bool)
    func horizontalCollectionView(_ collectionView: HorizontalCollectionViewController, requestChapterSwitch offset: Int)
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
    
    var currentPageIndex: Int = 0
    
    private(set) lazy var collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        
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
    
    func update(pages: [PaginatedPage], pageInfos: [TK2PageInfo], renderStore: TextKit2RenderStore?, paragraphStarts: [Int], prefixLen: Int, sideMargin: CGFloat, topInset: CGFloat, anchorPageIndex: Int) {
        self.pages = pages
        self.pageInfos = pageInfos
        self.renderStore = renderStore
        self.paragraphStarts = paragraphStarts
        self.chapterPrefixLen = prefixLen
        self.sideMargin = sideMargin
        self.topInset = topInset
        self.currentPageIndex = anchorPageIndex
        
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
                topInset: topInset
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
        let page = Int(scrollView.contentOffset.x / scrollView.bounds.width)
        if page != currentPageIndex {
            currentPageIndex = page
            delegate?.horizontalCollectionView(self, didUpdatePageIndex: page)
        }
    }
    
    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        let page = Int(scrollView.contentOffset.x / scrollView.bounds.width)
        currentPageIndex = page
        delegate?.horizontalCollectionView(self, didUpdatePageIndex: page)
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
    
    func update(renderStore: TextKit2RenderStore?, pageIndex: Int, pageInfo: TK2PageInfo, paragraphStarts: [Int], prefixLen: Int, sideMargin: CGFloat, topInset: CGFloat) {
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
