import UIKit

protocol MangaReadable: AnyObject {
    var scrollView: UIScrollView { get }
    var onChapterSwitched: ((Int) -> Void)? { get set }
    var onToggleMenu: (() -> Void)? { get set }
    var onInteractionChanged: ((Bool) -> Void)? { get set }
    var onVisibleIndexChanged: ((Int) -> Void)? { get set }
    var safeAreaTop: CGFloat { get set }
    var threshold: CGFloat { get set }
    var dampingFactor: CGFloat { get set }
    var maxZoomScale: CGFloat { get set }
    var prefetchCount: Int { get set }
    var memoryCacheMB: Int { get set }
    var recentKeepCount: Int { get set }
    var isChapterZoomEnabled: Bool { get set }
    var progressFontSize: CGFloat { get set }
    var currentVisibleIndex: Int { get set }
    var pendingScrollIndex: Int? { get set }
    var bookUrl: String? { get set }
    var chapterIndex: Int { get set }
    var chapterUrl: String? { get set }
    var progressLabel: UILabel { get }
    func update(urls: [String])
    func updateNextChapterPrefetch(urls: [String])
    func scrollToIndex(_ index: Int, animated: Bool)
    func scrollToBottom(animated: Bool)
}

private final class MangaImageCell: UICollectionViewCell, UIScrollViewDelegate {
    static let reuseIdentifier = "MangaImageCell"

    private let zoomScrollView = UIScrollView()
    private let imageView = UIImageView()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let retryButton = UIButton(type: .system)

    private var retryHandler: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .clear

        zoomScrollView.minimumZoomScale = 1.0
        zoomScrollView.maximumZoomScale = 1.0
        zoomScrollView.delegate = self
        zoomScrollView.showsHorizontalScrollIndicator = false
        zoomScrollView.showsVerticalScrollIndicator = false
        zoomScrollView.bouncesZoom = true
        zoomScrollView.clipsToBounds = true
        zoomScrollView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(zoomScrollView)

        NSLayoutConstraint.activate([
            zoomScrollView.topAnchor.constraint(equalTo: contentView.topAnchor),
            zoomScrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            zoomScrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            zoomScrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.backgroundColor = UIColor.white.withAlphaComponent(0.05)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        zoomScrollView.addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: zoomScrollView.contentLayoutGuide.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: zoomScrollView.contentLayoutGuide.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: zoomScrollView.contentLayoutGuide.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: zoomScrollView.contentLayoutGuide.bottomAnchor),
            imageView.widthAnchor.constraint(equalTo: zoomScrollView.frameLayoutGuide.widthAnchor),
            imageView.heightAnchor.constraint(equalTo: zoomScrollView.frameLayoutGuide.heightAnchor)
        ])

        spinner.color = .white
        spinner.hidesWhenStopped = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])

        retryButton.setTitle("重试", for: .normal)
        retryButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        retryButton.setTitleColor(.white, for: .normal)
        retryButton.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.8)
        retryButton.layer.cornerRadius = 12
        retryButton.contentEdgeInsets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        retryButton.translatesAutoresizingMaskIntoConstraints = false
        retryButton.isHidden = true
        retryButton.layer.zPosition = 100
        retryButton.isExclusiveTouch = true
        contentView.addSubview(retryButton)
        NSLayoutConstraint.activate([
            retryButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            retryButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])

        retryButton.addTarget(self, action: #selector(handleRetryTapped), for: .touchUpInside)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.image = nil
        spinner.stopAnimating()
        retryButton.isHidden = true
        retryHandler = nil
        zoomScrollView.setZoomScale(1.0, animated: false)
        zoomScrollView.isScrollEnabled = false
    }

    func configure(image: UIImage?, isLoading: Bool, showRetry: Bool, allowZoom: Bool, maxZoom: CGFloat, onRetry: (() -> Void)?) {
        imageView.image = image
        if allowZoom {
            zoomScrollView.isScrollEnabled = zoomScrollView.zoomScale > 1.01
            zoomScrollView.panGestureRecognizer.isEnabled = zoomScrollView.zoomScale > 1.01
            zoomScrollView.maximumZoomScale = maxZoom
            zoomScrollView.minimumZoomScale = 1.0
            zoomScrollView.pinchGestureRecognizer?.isEnabled = true
        } else {
            zoomScrollView.setZoomScale(1.0, animated: false)
            zoomScrollView.maximumZoomScale = 1.0
            zoomScrollView.minimumZoomScale = 1.0
            zoomScrollView.isScrollEnabled = false
            zoomScrollView.panGestureRecognizer.isEnabled = false
            zoomScrollView.pinchGestureRecognizer?.isEnabled = false
        }
        if isLoading {
            spinner.startAnimating()
        } else {
            spinner.stopAnimating()
        }
        retryButton.isHidden = !showRetry
        retryHandler = onRetry
    }

    @objc private func handleRetryTapped() {
        retryHandler?()
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        let zoomed = scrollView.zoomScale > 1.01
        zoomScrollView.isScrollEnabled = zoomed
        zoomScrollView.panGestureRecognizer.isEnabled = zoomed
    }
}

// MARK: - Manga Reader Controller
class MangaReaderViewController: UIViewController, UICollectionViewDelegate, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, UICollectionViewDataSourcePrefetching, UIScrollViewDelegate, UIGestureRecognizerDelegate, MangaReadable {
    private let zoomScrollView = UIScrollView()
    private let collectionView: UICollectionView
    private var contentTapGesture: UITapGestureRecognizer?
    private let switchHintLabel = UILabel()
    private var lastViewSize: CGSize = .zero
    private var pendingSwitchDirection: Int = 0
    private var switchReady = false
    private var switchWorkItem: DispatchWorkItem?
    private let switchHoldDuration: TimeInterval = ReaderConstants.Interaction.mangaSwitchHoldDuration
    var dampingFactor: CGFloat = ReaderConstants.Interaction.dampingFactorDefault

    var onChapterSwitched: ((Int) -> Void)?
    var onToggleMenu: (() -> Void)?
    var onInteractionChanged: ((Bool) -> Void)?
    var onVisibleIndexChanged: ((Int) -> Void)?
    var safeAreaTop: CGFloat = 0
    var threshold: CGFloat = 80
    var maxZoomScale: CGFloat = 3.0 {
        didSet {
            zoomScrollView.maximumZoomScale = maxZoomScale
        }
    }
    var prefetchCount: Int = 6
    var memoryCacheMB: Int = 120 {
        didSet { updateCacheLimits() }
    }
    var recentKeepCount: Int = 24
    var isChapterZoomEnabled: Bool = true {
        didSet { updateChapterZoomBehavior() }
    }
    var progressFontSize: CGFloat = 12 {
        didSet {
            progressLabel.font = .monospacedDigitSystemFont(ofSize: progressFontSize, weight: .regular)
        }
    }
    var currentVisibleIndex: Int = 0
    var pendingScrollIndex: Int?
    var bookUrl: String?
    var chapterIndex: Int = 0
    var chapterUrl: String?
    private var imageUrls: [String] = []
    private var loadingTasks: [Int: Task<Void, Never>] = [:]
    private var imageAspectRatios: [CGFloat?] = []
    private var estimatedHeights: [CGFloat?] = []
    private var imageStates: [ImageLoadState] = []
    private let imageCache = NSCache<NSString, UIImage>()
    private let prefetchDataCache = NSCache<NSString, NSData>()
    private var prefetchTasks: [String: Task<Void, Never>] = [:]
    private var nextChapterPrefetchUrls: [String] = []
    private var pendingLayoutInvalidation: DispatchWorkItem?
    private var lastPrefetchTime: TimeInterval = 0
    private let prefetchCooldown: TimeInterval = 0.35
    private var recentImageOrder: [String] = []
    private var recentImageMap: [String: UIImage] = [:]
    private var minLoadIndex: Int = 0
    private lazy var zoomPanGesture = UIPanGestureRecognizer(target: self, action: #selector(handleZoomPan(_:)))

    private enum ImageLoadState {
        case idle
        case loading
        case loaded
        case failed
    }

    private lazy var progressOverlayView: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.layer.compositingFilter = "exclusionBlendMode"
        view.layer.shouldRasterize = true
        view.layer.rasterizationScale = UIScreen.main.scale
        return view
    }()

    let progressLabel = UILabel()

    var scrollView: UIScrollView { collectionView }

    init() {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        self.collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        zoomScrollView.minimumZoomScale = 1.0
        zoomScrollView.maximumZoomScale = maxZoomScale
        zoomScrollView.delegate = self
        zoomScrollView.showsHorizontalScrollIndicator = false
        zoomScrollView.showsVerticalScrollIndicator = false
        zoomScrollView.bouncesZoom = true
        zoomScrollView.backgroundColor = .clear
        zoomScrollView.contentInsetAdjustmentBehavior = .never
        zoomScrollView.panGestureRecognizer.isEnabled = false
        zoomPanGesture.cancelsTouchesInView = false
        zoomPanGesture.delegate = self
        zoomScrollView.addGestureRecognizer(zoomPanGesture)

        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.prefetchDataSource = self
        collectionView.alwaysBounceVertical = true
        collectionView.delaysContentTouches = false
        collectionView.backgroundColor = .clear
        collectionView.contentInsetAdjustmentBehavior = .never
        // keep collectionView pan for vertical scroll; horizontal pan handled by custom zoomPanGesture
        collectionView.register(MangaImageCell.self, forCellWithReuseIdentifier: MangaImageCell.reuseIdentifier)
        collectionView.contentInset = UIEdgeInsets(top: safeAreaTop, left: 0, bottom: ReaderConstants.Layout.verticalContentInsetBottom, right: 0)
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        setupSwitchHint()
        setupProgressLabel()

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tap.cancelsTouchesInView = false
        contentTapGesture = tap
        zoomScrollView.addGestureRecognizer(tap)

        updateCacheLimits()
        updateChapterZoomBehavior()
    }

    deinit {
        loadingTasks.values.forEach { $0.cancel() }
        loadingTasks.removeAll()
    }

    private func setupProgressLabel() {
        view.addSubview(progressOverlayView)
        progressOverlayView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            progressOverlayView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            progressOverlayView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -4),
            progressOverlayView.widthAnchor.constraint(greaterThanOrEqualToConstant: 40),
            progressOverlayView.heightAnchor.constraint(equalToConstant: 20)
        ])

        progressLabel.font = .monospacedDigitSystemFont(ofSize: progressFontSize, weight: .regular)
        progressLabel.textColor = .white
        progressLabel.backgroundColor = .clear
        progressOverlayView.addSubview(progressLabel)
        progressLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            progressLabel.trailingAnchor.constraint(equalTo: progressOverlayView.trailingAnchor),
            progressLabel.bottomAnchor.constraint(equalTo: progressOverlayView.bottomAnchor)
        ])
    }

    override func viewDidLayoutSubviews() {
        let oldContentHeight = collectionView.contentSize.height
        let oldOffset = collectionView.contentOffset.y + collectionView.contentInset.top

        super.viewDidLayoutSubviews()

        if view.bounds.size != lastViewSize {
            let wasAtBottom = oldContentHeight > 0 && oldOffset >= (oldContentHeight - collectionView.bounds.height - 10)
            let relativeProgress = oldContentHeight > 0 ? (oldOffset / oldContentHeight) : 0

            lastViewSize = view.bounds.size
            if isChapterZoomEnabled {
                zoomScrollView.frame = view.bounds
                collectionView.frame = zoomScrollView.bounds
            } else {
                collectionView.frame = view.bounds
            }
            collectionView.contentInset = UIEdgeInsets(top: safeAreaTop, left: 0, bottom: ReaderConstants.Layout.verticalContentInsetBottom, right: 0)
            collectionView.collectionViewLayout.invalidateLayout()

            if oldContentHeight > 0 {
                view.layoutIfNeeded()
                if wasAtBottom {
                    scrollToBottom(animated: false)
                } else {
                    let newTargetY = (collectionView.contentSize.height * relativeProgress) - collectionView.contentInset.top
                    collectionView.setContentOffset(CGPoint(x: 0, y: newTargetY), animated: false)
                }
            }
        }
    }

    @objc private func handleTap() { onToggleMenu?() }

    func update(urls: [String]) {
        guard urls != self.imageUrls else { return }

        loadingTasks.values.forEach { $0.cancel() }
        loadingTasks.removeAll()

        self.imageUrls = urls
        self.imageAspectRatios = Array(repeating: nil, count: urls.count)
        self.estimatedHeights = Array(repeating: 300, count: urls.count)
        self.imageStates = Array(repeating: .idle, count: urls.count)
        self.minLoadIndex = max(0, pendingScrollIndex ?? 0)
        imageCache.removeAllObjects()
        prefetchDataCache.removeAllObjects()
        recentImageOrder.removeAll()
        recentImageMap.removeAll()
        pendingLayoutInvalidation?.cancel()
        pendingLayoutInvalidation = nil

        if urls.isEmpty {
            LogManager.shared.log("漫画图片列表为空", category: "漫画调试")
        }

        collectionView.reloadData()
    }

    func updateNextChapterPrefetch(urls: [String]) {
        nextChapterPrefetchUrls = urls
    }

    private func sanitizedUrl(_ url: String) -> String {
        url.replacingOccurrences(of: "__IMG__", with: "").trimmingCharacters(in: .whitespaces)
    }

    private func cacheKey(for url: String) -> NSString {
        NSString(string: sanitizedUrl(url))
    }

    private func updateCacheLimits() {
        let bytes = max(0, memoryCacheMB) * 1024 * 1024
        imageCache.totalCostLimit = bytes
        prefetchDataCache.totalCostLimit = bytes / 2
    }

    private func estimatedCost(for image: UIImage) -> Int {
        let width = Int(image.size.width * image.scale)
        let height = Int(image.size.height * image.scale)
        return max(1, width * height * 4)
    }

    private func keepRecentImage(key: String, image: UIImage) {
        if recentKeepCount <= 0 { return }
        recentImageMap[key] = image
        recentImageOrder.removeAll { $0 == key }
        recentImageOrder.append(key)
        if recentImageOrder.count > recentKeepCount {
            let overflow = recentImageOrder.count - recentKeepCount
            for _ in 0..<overflow {
                if let removeKey = recentImageOrder.first {
                    recentImageOrder.removeFirst()
                    recentImageMap.removeValue(forKey: removeKey)
                }
            }
        }
    }

    private func startLoadImage(index: Int, force: Bool = false) {
        guard index >= 0, index < imageUrls.count, index < imageStates.count else { return }
        if !force && index < minLoadIndex { return }
        if imageStates[index] == .loading { return }

        imageStates[index] = .loading
        DispatchQueue.main.async {
            self.collectionView.reloadItems(at: [IndexPath(item: index, section: 0)])
        }
        let urlStr = imageUrls[index]
        let expectedToken = urlStr
        let cacheKey = cacheKey(for: urlStr)

        let task = Task {
            if let cachedImage = imageCache.object(forKey: cacheKey) {
                let decoded = MangaImageService.shared.decodeImage(cachedImage)
                await MainActor.run {
                    guard index < self.imageStates.count,
                          index < self.imageUrls.count,
                          self.imageUrls[index] == expectedToken else { return }
                    let cost = self.estimatedCost(for: decoded)
                    self.imageCache.setObject(decoded, forKey: cacheKey, cost: cost)
                    self.keepRecentImage(key: cacheKey as String, image: decoded)
                    let ratio = decoded.size.height / max(decoded.size.width, 1)
                    self.imageAspectRatios[index] = ratio
                    let width = max(1, self.collectionView.bounds.width)
                    let newHeight = width * ratio
                    let oldHeight = self.estimatedHeights.indices.contains(index) ? (self.estimatedHeights[index] ?? newHeight) : newHeight
                    if self.estimatedHeights.indices.contains(index) { self.estimatedHeights[index] = newHeight }
                    self.imageStates[index] = .loaded
                    if abs(newHeight - oldHeight) > 12 {
                        self.scheduleLayoutInvalidation()
                    }
                    self.collectionView.reloadItems(at: [IndexPath(item: index, section: 0)])
                    if self.pendingScrollIndex == index {
                        self.scrollToIndex(index, animated: false)
                    }
                }
                return
            }
            let cleanUrl = sanitizedUrl(urlStr)
            guard let resolved = MangaImageService.shared.resolveImageURL(cleanUrl) else {
                await MainActor.run {
                    guard index < self.imageStates.count,
                          index < self.imageUrls.count,
                          self.imageUrls[index] == expectedToken else { return }
                    self.imageStates[index] = .failed
                    self.collectionView.reloadItems(at: [IndexPath(item: index, section: 0)])
                }
                return
            }

            let absolute = resolved.absoluteString

            if let cachedData = prefetchDataCache.object(forKey: cacheKey) as Data?,
               let cachedImage = UIImage(data: cachedData) {
                let decoded = MangaImageService.shared.decodeImage(cachedImage)
                await MainActor.run {
                    guard index < self.imageStates.count,
                          index < self.imageUrls.count,
                          self.imageUrls[index] == expectedToken else { return }
                    let cost = self.estimatedCost(for: decoded)
                    self.imageCache.setObject(decoded, forKey: cacheKey, cost: cost)
                    self.keepRecentImage(key: cacheKey as String, image: decoded)
                    let ratio = decoded.size.height / max(decoded.size.width, 1)
                    self.imageAspectRatios[index] = ratio
                    let width = max(1, self.collectionView.bounds.width)
                    let newHeight = width * ratio
                    let oldHeight = self.estimatedHeights.indices.contains(index) ? (self.estimatedHeights[index] ?? newHeight) : newHeight
                    if self.estimatedHeights.indices.contains(index) { self.estimatedHeights[index] = newHeight }
                    self.imageStates[index] = .loaded
                    if abs(newHeight - oldHeight) > 12 {
                        self.scheduleLayoutInvalidation()
                    }
                    self.collectionView.reloadItems(at: [IndexPath(item: index, section: 0)])
                    if self.pendingScrollIndex == index {
                        self.scrollToIndex(index, animated: false)
                    }
                }
                return
            }

            if let b = bookUrl,
               let cachedData = LocalCacheManager.shared.loadMangaImage(bookUrl: b, chapterIndex: chapterIndex, imageURL: absolute),
               let cachedImage = UIImage(data: cachedData) {
                let decoded = MangaImageService.shared.decodeImage(cachedImage)
                await MainActor.run {
                    guard index < self.imageStates.count,
                          index < self.imageUrls.count,
                          self.imageUrls[index] == expectedToken else { return }
                    let cost = self.estimatedCost(for: decoded)
                    self.imageCache.setObject(decoded, forKey: cacheKey, cost: cost)
                    self.keepRecentImage(key: cacheKey as String, image: decoded)
                    let ratio = decoded.size.height / max(decoded.size.width, 1)
                    self.imageAspectRatios[index] = ratio
                    let width = max(1, self.collectionView.bounds.width)
                    let newHeight = width * ratio
                    let oldHeight = self.estimatedHeights.indices.contains(index) ? (self.estimatedHeights[index] ?? newHeight) : newHeight
                    if self.estimatedHeights.indices.contains(index) { self.estimatedHeights[index] = newHeight }
                    self.imageStates[index] = .loaded
                    if abs(newHeight - oldHeight) > 12 {
                        self.scheduleLayoutInvalidation()
                    }
                    self.collectionView.reloadItems(at: [IndexPath(item: index, section: 0)])
                    if self.pendingScrollIndex == index {
                        self.scrollToIndex(index, animated: false)
                    }
                }
                return
            }

            await MangaImageService.shared.acquireDownloadPermit()
            defer { MangaImageService.shared.releaseDownloadPermit() }

            if Task.isCancelled { return }

            if let data = await MangaImageService.shared.fetchImageData(for: resolved, referer: chapterUrl),
               let image = UIImage(data: data) {
                if let b = bookUrl, UserPreferences.shared.isMangaAutoCacheEnabled {
                    LocalCacheManager.shared.saveMangaImage(bookUrl: b, chapterIndex: chapterIndex, imageURL: absolute, data: data)
                }
                let decoded = MangaImageService.shared.decodeImage(image)
                await MainActor.run {
                    if Task.isCancelled { return }
                    guard index < self.imageStates.count,
                          index < self.imageUrls.count,
                          self.imageUrls[index] == expectedToken else { return }
                    let cost = self.estimatedCost(for: decoded)
                    self.imageCache.setObject(decoded, forKey: cacheKey, cost: cost)
                    self.keepRecentImage(key: cacheKey as String, image: decoded)
                    let ratio = decoded.size.height / max(decoded.size.width, 1)
                    self.imageAspectRatios[index] = ratio
                    let width = max(1, self.collectionView.bounds.width)
                    let newHeight = width * ratio
                    let oldHeight = self.estimatedHeights.indices.contains(index) ? (self.estimatedHeights[index] ?? newHeight) : newHeight
                    if self.estimatedHeights.indices.contains(index) { self.estimatedHeights[index] = newHeight }
                    self.imageStates[index] = .loaded
                    if abs(newHeight - oldHeight) > 12 {
                        self.scheduleLayoutInvalidation()
                    }
                    self.collectionView.reloadItems(at: [IndexPath(item: index, section: 0)])
                    if self.pendingScrollIndex == index {
                        self.scrollToIndex(index, animated: false)
                    }
                }
            } else {
                await MainActor.run {
                    if Task.isCancelled { return }
                    guard index < self.imageStates.count,
                          index < self.imageUrls.count,
                          self.imageUrls[index] == expectedToken else { return }
                    self.imageStates[index] = .failed
                    self.collectionView.reloadItems(at: [IndexPath(item: index, section: 0)])
                }
                LogManager.shared.log("漫画图片加载失败: \(absolute)", category: "漫画调试")
            }
        }

        loadingTasks[index] = task
    }

    private func prefetchAround(index: Int) {
        guard prefetchCount > 0 else { return }
        guard !imageUrls.isEmpty else { return }
        let start = min(imageUrls.count - 1, index + 1)
        let end = min(imageUrls.count - 1, index + prefetchCount)
        if start > end { return }
        let effectiveStart = max(start, minLoadIndex)
        if effectiveStart > end { return }
        let threshold = min(5, prefetchCount)
        var buffered = 0
        for idx in effectiveStart...end {
            if idx < imageStates.count {
                let state = imageStates[idx]
                if state == .loading || state == .loaded {
                    buffered += 1
                }
            }
        }
        if buffered >= threshold { return }
        for idx in effectiveStart...end {
            if idx < imageStates.count, imageStates[idx] == .idle {
                startLoadImage(index: idx)
                buffered += 1
                if buffered >= prefetchCount { break }
            }
        }
    }

    private func prefetchNextChapterIfNeeded(currentIndex: Int) {
        guard prefetchCount > 0 else { return }
        guard !nextChapterPrefetchUrls.isEmpty else { return }
        let remaining = (imageUrls.count - 1) - currentIndex
        if remaining > prefetchCount { return }
        let limit = min(prefetchCount, nextChapterPrefetchUrls.count)
        let threshold = min(5, prefetchCount)
        var buffered = 0
        for i in 0..<limit {
            let urlStr = nextChapterPrefetchUrls[i]
            let clean = sanitizedUrl(urlStr)
            let key = NSString(string: clean)
            if prefetchDataCache.object(forKey: key) != nil || prefetchTasks[clean] != nil {
                buffered += 1
            }
        }
        if buffered >= threshold { return }
        for i in 0..<limit {
            let urlStr = nextChapterPrefetchUrls[i]
            let clean = sanitizedUrl(urlStr)
            let key = NSString(string: clean)
            if prefetchDataCache.object(forKey: key) != nil || prefetchTasks[clean] != nil { continue }
            prefetchNextChapterImage(urlStr: urlStr)
            buffered += 1
            if buffered >= prefetchCount { break }
        }
    }

    private func prefetchNextChapterImage(urlStr: String) {
        let cleanUrl = sanitizedUrl(urlStr)
        guard let resolved = MangaImageService.shared.resolveImageURL(cleanUrl) else { return }
        let absolute = resolved.absoluteString
        let key = NSString(string: cleanUrl)

        if prefetchDataCache.object(forKey: key) != nil { return }
        if prefetchTasks[cleanUrl] != nil { return }
        if let b = bookUrl,
           LocalCacheManager.shared.loadMangaImage(bookUrl: b, chapterIndex: chapterIndex + 1, imageURL: absolute) != nil {
            return
        }

        let task = Task {
            await MangaImageService.shared.acquireDownloadPermit()
            defer { MangaImageService.shared.releaseDownloadPermit() }
            if Task.isCancelled { return }
            if let data = await MangaImageService.shared.fetchImageData(for: resolved, referer: chapterUrl) {
                prefetchDataCache.setObject(data as NSData, forKey: key, cost: data.count)
                if let image = UIImage(data: data) {
                    let decoded = MangaImageService.shared.decodeImage(image)
                    let cost = self.estimatedCost(for: decoded)
                    self.imageCache.setObject(decoded, forKey: self.cacheKey(for: cleanUrl), cost: cost)
                }
                if let b = bookUrl, UserPreferences.shared.isMangaAutoCacheEnabled {
                    LocalCacheManager.shared.saveMangaImage(bookUrl: b, chapterIndex: chapterIndex + 1, imageURL: absolute, data: data)
                }
            }
            await MainActor.run {
                self.prefetchTasks[cleanUrl] = nil
            }
        }
        prefetchTasks[cleanUrl] = task
    }

    private func scheduleLayoutInvalidation() {
        pendingLayoutInvalidation?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.collectionView.collectionViewLayout.invalidateLayout()
        }
        pendingLayoutInvalidation = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    func scrollToIndex(_ index: Int, animated: Bool = false) {
        pendingScrollIndex = index
        guard index >= 0, index < imageUrls.count else { return }
        
        // 如果 CollectionView 还没准备好，先退出，靠 pendingScrollIndex 在后续 load 完成后触发
        if collectionView.numberOfItems(inSection: 0) <= index {
            return
        }

        let indexPath = IndexPath(item: index, section: 0)
        collectionView.layoutIfNeeded()
        if let attr = collectionView.layoutAttributesForItem(at: indexPath) {
            let targetY = attr.frame.minY - collectionView.contentInset.top
            collectionView.setContentOffset(CGPoint(x: 0, y: targetY), animated: animated)
            pendingScrollIndex = nil
        } else {
            collectionView.scrollToItem(at: indexPath, at: .top, animated: animated)
            // scrollToItem 之后可能需要更新 pendingScrollIndex 状态
            // 但因为 scrollToItem 是异步的，我们暂时保留 pendingScrollIndex 直到下一次 visibleIndex 更新
        }
    }

    func scrollToBottom(animated: Bool = false) {
        view.layoutIfNeeded()
        let bottomOffset = CGPoint(x: 0, y: max(-collectionView.contentInset.top, collectionView.contentSize.height - collectionView.bounds.height + collectionView.contentInset.bottom))
        collectionView.setContentOffset(bottomOffset, animated: animated)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView !== collectionView { return }
        let rawOffset = scrollView.contentOffset.y
        if scrollView.isDragging {
            handleHoldSwitchIfNeeded(rawOffset: rawOffset)
        }

        let contentHeight = collectionView.contentSize.height
        let currentScale = isChapterZoomEnabled ? zoomScrollView.zoomScale : 1.0

        let pullThreshold = ReaderConstants.Interaction.pullThreshold
        let topPull = -safeAreaTop - rawOffset
        let bottomPull = rawOffset - (contentHeight - collectionView.bounds.height)

        if topPull > 0 {
            let ty = (topPull * dampingFactor) / max(currentScale, 1.0)
            collectionView.transform = CGAffineTransform(scaleX: currentScale, y: currentScale).translatedBy(x: 0, y: ty)
        } else if bottomPull > 0 {
            let ty = (-bottomPull * dampingFactor) / max(currentScale, 1.0)
            collectionView.transform = CGAffineTransform(scaleX: currentScale, y: currentScale).translatedBy(x: 0, y: ty)
        } else if collectionView.transform.ty != 0 || collectionView.transform.a != currentScale {
            collectionView.transform = CGAffineTransform(scaleX: currentScale, y: currentScale)
        }

        let offset = rawOffset + safeAreaTop
        let maxOffset = contentHeight - collectionView.bounds.height
        if maxOffset > 0 {
            progressLabel.text = ReaderProgressFormatter.percentProgressText(offset: offset, maxOffset: maxOffset)
        } else {
            progressLabel.text = "0%"
        }

        updateVisibleIndex()
    }

    private func updateVisibleIndex() {
        let visible = collectionView.indexPathsForVisibleItems
        guard !visible.isEmpty else { return }
        let sorted = visible.compactMap { indexPath -> (Int, CGFloat)? in
            guard let attr = collectionView.layoutAttributesForItem(at: indexPath) else { return nil }
            return (indexPath.item, attr.frame.minY)
        }.sorted { $0.1 < $1.1 }
        if let first = sorted.first {
            if currentVisibleIndex != first.0 {
                currentVisibleIndex = first.0
                onVisibleIndexChanged?(first.0)
                if currentVisibleIndex < minLoadIndex {
                    minLoadIndex = currentVisibleIndex
                }
                let now = Date().timeIntervalSince1970
                if now - lastPrefetchTime > prefetchCooldown {
                    lastPrefetchTime = now
                    prefetchAround(index: first.0)
                    prefetchNextChapterIfNeeded(currentIndex: first.0)
                }
            }
        }
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        if scrollView !== collectionView { return }
        cancelSwitchHold()
        onInteractionChanged?(true)
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if scrollView !== collectionView { return }
        if switchReady && pendingSwitchDirection != 0 {
            let direction = pendingSwitchDirection
            onChapterSwitched?(direction)
            cancelSwitchHold()
        } else {
            if !decelerate { onInteractionChanged?(false) }
            cancelSwitchHold()
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        if scrollView !== collectionView { return }
        cancelSwitchHold()
        onInteractionChanged?(false)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        if scrollView === zoomScrollView, isChapterZoomEnabled { return collectionView }
        return nil
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        if scrollView !== zoomScrollView || !isChapterZoomEnabled { return }
        let zoomed = scrollView.zoomScale > 1.01
        zoomPanGesture.isEnabled = zoomed
    }

    @objc private func handleZoomPan(_ gesture: UIPanGestureRecognizer) {
        guard isChapterZoomEnabled, zoomScrollView.zoomScale > 1.01 else { return }
        let translation = gesture.translation(in: zoomScrollView)
        let currentX = zoomScrollView.contentOffset.x
        let targetX = currentX - translation.x
        let maxX = max(0, zoomScrollView.contentSize.width - zoomScrollView.bounds.width)
        let clampedX = min(max(targetX, 0), maxX)
        zoomScrollView.setContentOffset(CGPoint(x: clampedX, y: zoomScrollView.contentOffset.y), animated: false)
        gesture.setTranslation(.zero, in: zoomScrollView)
    }

    // MARK: - UIGestureRecognizerDelegate
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === zoomPanGesture {
            if !isChapterZoomEnabled { return false }
            if zoomScrollView.zoomScale <= 1.01 { return false }
            let velocity = zoomPanGesture.velocity(in: zoomScrollView)
            return abs(velocity.x) > abs(velocity.y)
        }
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === zoomPanGesture || otherGestureRecognizer === zoomPanGesture {
            if otherGestureRecognizer === collectionView.panGestureRecognizer || gestureRecognizer === collectionView.panGestureRecognizer {
                return zoomScrollView.zoomScale > 1.01
            }
        }
        return false
    }

    private func updateChapterZoomBehavior() {
        guard isViewLoaded else { return }
        if isChapterZoomEnabled {
            if zoomScrollView.superview !== view {
                view.addSubview(zoomScrollView)
            }
            if collectionView.superview !== zoomScrollView {
                collectionView.removeFromSuperview()
                zoomScrollView.addSubview(collectionView)
            }
            zoomScrollView.maximumZoomScale = maxZoomScale
            zoomScrollView.minimumZoomScale = 1.0
            zoomScrollView.pinchGestureRecognizer?.isEnabled = true
            zoomScrollView.isUserInteractionEnabled = true
            if let tap = contentTapGesture, tap.view !== zoomScrollView {
                tap.view?.removeGestureRecognizer(tap)
                zoomScrollView.addGestureRecognizer(tap)
            }
        } else {
            if collectionView.superview !== view {
                collectionView.removeFromSuperview()
                view.addSubview(collectionView)
            }
            if zoomScrollView.superview === view {
                zoomScrollView.removeFromSuperview()
            }
            zoomScrollView.pinchGestureRecognizer?.isEnabled = false
            zoomScrollView.setZoomScale(1.0, animated: false)
            zoomScrollView.maximumZoomScale = 1.0
            zoomScrollView.minimumZoomScale = 1.0
            zoomPanGesture.isEnabled = false
            zoomScrollView.isUserInteractionEnabled = false
            if let tap = contentTapGesture, tap.view !== collectionView {
                tap.view?.removeGestureRecognizer(tap)
                collectionView.addGestureRecognizer(tap)
            }
        }
        view.bringSubviewToFront(progressOverlayView)
        view.bringSubviewToFront(switchHintLabel)
        view.setNeedsLayout()
        collectionView.reloadData()
    }


    private func setupSwitchHint() {
        switchHintLabel.alpha = 0
        switchHintLabel.textAlignment = .center
        switchHintLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        switchHintLabel.textColor = .white
        switchHintLabel.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        switchHintLabel.layer.cornerRadius = ReaderConstants.Highlight.switchHintCornerRadius
        switchHintLabel.layer.masksToBounds = true
        view.addSubview(switchHintLabel)
    }

    private func updateSwitchHint(text: String, isTop: Bool) {
        if switchHintLabel.text != "  \(text)  " {
            switchHintLabel.text = "  \(text)  "
            switchHintLabel.sizeToFit()
            let width = min(view.bounds.width - ReaderConstants.Interaction.switchHintHorizontalPadding, max(ReaderConstants.Interaction.switchHintWidthMin, switchHintLabel.bounds.width))
            let bottomSafe = max(0, view.safeAreaInsets.bottom)
            let newFrame = CGRect(
                x: (view.bounds.width - width) / 2,
                y: isTop ? (safeAreaTop + ReaderConstants.Interaction.switchHintTopPadding) : (view.bounds.height - bottomSafe - ReaderConstants.Interaction.switchHintBottomPadding),
                width: width, height: 24
            )
            if switchHintLabel.frame != newFrame {
                switchHintLabel.frame = newFrame
            }
        }
        if switchHintLabel.alpha == 0 {
            UIView.animate(withDuration: ReaderConstants.Interaction.switchHintAnimation) { self.switchHintLabel.alpha = 1 }
        }
    }

    private func hideSwitchHint() {
        guard switchHintLabel.alpha > 0 else { return }
        UIView.animate(withDuration: ReaderConstants.Interaction.switchHintAnimation) { self.switchHintLabel.alpha = 0 }
    }

    private func handleHoldSwitchIfNeeded(rawOffset: CGFloat) {
        let inset = collectionView.adjustedContentInset
        let contentHeight = collectionView.contentSize.height
        let viewportHeight = collectionView.bounds.height
        let maxScrollY = max(-inset.top, contentHeight - viewportHeight + inset.bottom)
        
        let topPullDistance = -(rawOffset + inset.top)
        let bottomPullDistance = rawOffset - maxScrollY

        if topPullDistance > 5 {
            if topPullDistance > threshold {
                if !switchReady {
                    switchReady = true
                    pendingSwitchDirection = -1
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                }
                updateSwitchHint(text: "松开切换上一章", isTop: true)
            } else {
                if switchReady { switchReady = false }
                updateSwitchHint(text: "下拉切换上一章", isTop: true)
            }
        } else if bottomPullDistance > 5 {
            if bottomPullDistance > threshold {
                if !switchReady {
                    switchReady = true
                    pendingSwitchDirection = 1
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                }
                updateSwitchHint(text: "松开切换下一章", isTop: false)
            } else {
                if switchReady { switchReady = false }
                updateSwitchHint(text: "上拉切换下一章", isTop: false)
            }
        } else {
            cancelSwitchHold()
        }
    }

    private func beginSwitchHold(direction: Int, isTop: Bool) {
        if pendingSwitchDirection == direction, switchWorkItem != nil { return }
        cancelSwitchHold()
        pendingSwitchDirection = direction
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, self.collectionView.isDragging else { return }
            self.switchReady = true
            self.updateSwitchHint(text: direction > 0 ? "松手切换下一章" : "松手切换上一章", isTop: isTop)
        }
        switchWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + switchHoldDuration, execute: work)
    }

    private func cancelSwitchHold() {
        switchWorkItem?.cancel()
        switchWorkItem = nil
        pendingSwitchDirection = 0
        switchReady = false
        hideSwitchHint()
    }

    // MARK: - UICollectionViewDataSource
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        imageUrls.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: MangaImageCell.reuseIdentifier, for: indexPath) as? MangaImageCell else {
            return UICollectionViewCell()
        }

        let index = indexPath.item
        let key = cacheKey(for: imageUrls[index])
        let cachedImage = imageCache.object(forKey: key) ?? recentImageMap[key as String]
        let state = imageStates.indices.contains(index) ? imageStates[index] : .idle
        let isLoading = (state == .loading)
        let showRetry = (state == .failed)

        cell.configure(
            image: cachedImage,
            isLoading: isLoading,
            showRetry: showRetry,
            allowZoom: !isChapterZoomEnabled,
            maxZoom: maxZoomScale
        ) { [weak self] in
            self?.startLoadImage(index: index, force: true)
        }

        if cachedImage == nil && state == .idle {
            startLoadImage(index: index)
        }

        return cell
    }

    // MARK: - UICollectionViewDataSourcePrefetching
    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        for indexPath in indexPaths {
            startLoadImage(index: indexPath.item)
        }
    }

    func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
        let visible = Set(collectionView.indexPathsForVisibleItems.map { $0.item })
        for indexPath in indexPaths {
            let idx = indexPath.item
            guard idx < imageStates.count else { continue }
            if visible.contains(idx) { continue }
            if imageStates[idx] == .loading, let task = loadingTasks[idx] {
                task.cancel()
                loadingTasks[idx] = nil
                imageStates[idx] = .idle
            }
        }
    }

    // MARK: - UICollectionViewDelegateFlowLayout
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let width = max(1, collectionView.bounds.width)
        if estimatedHeights.indices.contains(indexPath.item), let height = estimatedHeights[indexPath.item] {
            return CGSize(width: width, height: height)
        }
        if imageAspectRatios.indices.contains(indexPath.item), let ratio = imageAspectRatios[indexPath.item] {
            return CGSize(width: width, height: width * ratio)
        }
        return CGSize(width: width, height: 300)
    }
}
