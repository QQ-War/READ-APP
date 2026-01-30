import UIKit

private final class MangaZoomScrollView: UIScrollView {
    weak var linkedCollectionPan: UIPanGestureRecognizer?

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === panGestureRecognizer {
            let velocity = panGestureRecognizer.velocity(in: self)
            return abs(velocity.x) > abs(velocity.y)
        }
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === panGestureRecognizer || otherGestureRecognizer === panGestureRecognizer {
            if otherGestureRecognizer === linkedCollectionPan || gestureRecognizer === linkedCollectionPan {
                return true
            }
        }
        return false
    }
}

private final class MangaImageCell: UICollectionViewCell {
    static let reuseIdentifier = "MangaImageCell"

    private let imageView = UIImageView()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let retryButton = UIButton(type: .system)

    private var retryHandler: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .clear

        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.backgroundColor = UIColor.white.withAlphaComponent(0.05)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
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
    }

    func configure(image: UIImage?, isLoading: Bool, showRetry: Bool, onRetry: (() -> Void)?) {
        imageView.image = image
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
}

// MARK: - Manga Reader Controller
class MangaReaderViewController: UIViewController, UICollectionViewDelegate, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, UICollectionViewDataSourcePrefetching, UIScrollViewDelegate {
    private let zoomScrollView = MangaZoomScrollView()
    private let collectionView: UICollectionView
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
    private var imageStates: [ImageLoadState] = []
    private let imageCache = NSCache<NSString, UIImage>()

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
        view.addSubview(zoomScrollView)

        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.prefetchDataSource = self
        collectionView.alwaysBounceVertical = true
        collectionView.delaysContentTouches = false
        collectionView.backgroundColor = .clear
        zoomScrollView.linkedCollectionPan = collectionView.panGestureRecognizer
        collectionView.register(MangaImageCell.self, forCellWithReuseIdentifier: MangaImageCell.reuseIdentifier)
        collectionView.contentInset = UIEdgeInsets(top: safeAreaTop, left: 0, bottom: ReaderConstants.Layout.verticalContentInsetBottom, right: 0)
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        zoomScrollView.addSubview(collectionView)

        setupSwitchHint()
        setupProgressLabel()

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tap.cancelsTouchesInView = false
        zoomScrollView.addGestureRecognizer(tap)
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
            zoomScrollView.frame = view.bounds
            collectionView.frame = zoomScrollView.bounds
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
        self.imageStates = Array(repeating: .idle, count: urls.count)
        imageCache.removeAllObjects()

        if urls.isEmpty {
            LogManager.shared.log("漫画图片列表为空", category: "漫画调试")
        }

        collectionView.reloadData()
    }

    private func sanitizedUrl(_ url: String) -> String {
        url.replacingOccurrences(of: "__IMG__", with: "").trimmingCharacters(in: .whitespaces)
    }

    private func cacheKey(for url: String) -> NSString {
        NSString(string: sanitizedUrl(url))
    }

    private func startLoadImage(index: Int) {
        guard index >= 0, index < imageUrls.count, index < imageStates.count else { return }
        if imageStates[index] == .loading { return }

        imageStates[index] = .loading
        DispatchQueue.main.async {
            self.collectionView.reloadItems(at: [IndexPath(item: index, section: 0)])
        }
        let urlStr = imageUrls[index]
        let expectedToken = urlStr
        let cacheKey = cacheKey(for: urlStr)

        let task = Task {
            let cleanUrl = sanitizedUrl(urlStr)
            guard let resolved = MangaImageService.shared.resolveImageURL(cleanUrl) else {
                await MainActor.run {
                    guard index < self.imageStates.count,
                          index < self.imageUrls.count,
                          self.imageUrls[index] == expectedToken else { return }
                    self.imageStates[index] = .failed
                    self.collectionView.reloadItems(at: [IndexPath(item: index, section: 0)])
                }
                LogManager.shared.log("漫画图片URL解析失败: \(cleanUrl)", category: "漫画调试")
                return
            }

            let absolute = resolved.absoluteString

            if let b = bookUrl,
               let cachedData = LocalCacheManager.shared.loadMangaImage(bookUrl: b, chapterIndex: chapterIndex, imageURL: absolute),
               let cachedImage = UIImage(data: cachedData) {
                await MainActor.run {
                    guard index < self.imageStates.count,
                          index < self.imageUrls.count,
                          self.imageUrls[index] == expectedToken else { return }
                    self.imageCache.setObject(cachedImage, forKey: cacheKey)
                    self.imageAspectRatios[index] = cachedImage.size.height / max(cachedImage.size.width, 1)
                    self.imageStates[index] = .loaded
                    self.collectionView.collectionViewLayout.invalidateLayout()
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
                await MainActor.run {
                    if Task.isCancelled { return }
                    guard index < self.imageStates.count,
                          index < self.imageUrls.count,
                          self.imageUrls[index] == expectedToken else { return }
                    self.imageCache.setObject(image, forKey: cacheKey)
                    self.imageAspectRatios[index] = image.size.height / max(image.size.width, 1)
                    self.imageStates[index] = .loaded
                    self.collectionView.collectionViewLayout.invalidateLayout()
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

    func scrollToIndex(_ index: Int, animated: Bool = false) {
        pendingScrollIndex = index
        guard index >= 0, index < imageUrls.count else { return }
        let indexPath = IndexPath(item: index, section: 0)
        collectionView.layoutIfNeeded()
        if let attr = collectionView.layoutAttributesForItem(at: indexPath) {
            let targetY = attr.frame.minY - collectionView.contentInset.top
            collectionView.setContentOffset(CGPoint(x: 0, y: targetY), animated: animated)
            pendingScrollIndex = nil
        } else {
            collectionView.scrollToItem(at: indexPath, at: .top, animated: animated)
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
        let actualMaxScrollY = max(-collectionView.contentInset.top, contentHeight - collectionView.bounds.height + collectionView.contentInset.bottom)
        let currentScale = zoomScrollView.zoomScale

        let offset = rawOffset + collectionView.contentInset.top
        let maxOffset = max(0, contentHeight - collectionView.bounds.height)
        if maxOffset > 0 {
            progressLabel.text = ReaderProgressFormatter.percentProgressText(offset: offset, maxOffset: maxOffset)
        } else {
            progressLabel.text = "0%"
        }

        if rawOffset < -collectionView.contentInset.top {
            let diff = -collectionView.contentInset.top - rawOffset
            let ty = (diff * dampingFactor) / max(currentScale, 1.0)
            collectionView.transform = CGAffineTransform(scaleX: currentScale, y: currentScale).translatedBy(x: 0, y: ty)
        } else if rawOffset > actualMaxScrollY {
            let diff = rawOffset - actualMaxScrollY
            let ty = (-diff * dampingFactor) / max(currentScale, 1.0)
            collectionView.transform = CGAffineTransform(scaleX: currentScale, y: currentScale).translatedBy(x: 0, y: ty)
        } else if collectionView.transform.ty != 0 || collectionView.transform.a != currentScale {
            collectionView.transform = CGAffineTransform(scaleX: currentScale, y: currentScale)
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
        if scrollView === zoomScrollView { return collectionView }
        return nil
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        if scrollView !== zoomScrollView { return }
        let zoomed = scrollView.zoomScale > 1.01
        zoomScrollView.panGestureRecognizer.isEnabled = zoomed
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
        let actualMaxScrollY = max(0, collectionView.contentSize.height - collectionView.bounds.height + collectionView.contentInset.bottom)
        let topPullDistance = max(0, -rawOffset - collectionView.contentInset.top)
        let bottomPullDistance = max(0, rawOffset - actualMaxScrollY)

        if topPullDistance > ReaderConstants.Interaction.pullThreshold {
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
        } else if bottomPullDistance > ReaderConstants.Interaction.pullThreshold {
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
        let cachedImage = imageCache.object(forKey: cacheKey(for: imageUrls[index]))
        let state = imageStates.indices.contains(index) ? imageStates[index] : .idle
        let isLoading = (state == .loading)
        let showRetry = (state == .failed)

        cell.configure(image: cachedImage, isLoading: isLoading, showRetry: showRetry) { [weak self] in
            self?.startLoadImage(index: index)
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
        if imageAspectRatios.indices.contains(indexPath.item), let ratio = imageAspectRatios[indexPath.item] {
            return CGSize(width: width, height: width * ratio)
        }
        return CGSize(width: width, height: 300)
    }
}
