import UIKit

// MARK: - Manga Reader Controller (Legacy)
class MangaLegacyReaderViewController: UIViewController, UIScrollViewDelegate, MangaReadable {
    let scrollView = UIScrollView()
    let stackView = UIStackView()
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
    var maxZoomScale: CGFloat = 3.0
    var prefetchCount: Int = 0
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
    
    private lazy var progressOverlayView: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        // 关键：回归到您认为有效的 exclusionBlendMode
        view.layer.compositingFilter = "exclusionBlendMode"
        view.layer.shouldRasterize = true
        view.layer.rasterizationScale = UIScreen.main.scale
        return view
    }()
    
    let progressLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        scrollView.delegate = self
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.alwaysBounceVertical = true
        scrollView.delaysContentTouches = false
        scrollView.contentInset = UIEdgeInsets(top: safeAreaTop, left: 0, bottom: ReaderConstants.Layout.verticalContentInsetBottom, right: 0)
        scrollView.maximumZoomScale = maxZoomScale
        scrollView.minimumZoomScale = 1.0
        view.addSubview(scrollView)
        
        stackView.axis = .vertical
        stackView.spacing = 0
        stackView.alignment = .fill
        scrollView.addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stackView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])
        
        setupSwitchHint()
        setupProgressLabel()
        
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        scrollView.addGestureRecognizer(tap)
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
        let oldContentHeight = scrollView.contentSize.height
        let oldOffset = scrollView.contentOffset.y + safeAreaTop
        
        super.viewDidLayoutSubviews()
        
        if view.bounds.size != lastViewSize {
            let wasAtBottom = oldContentHeight > 0 && oldOffset >= (oldContentHeight - scrollView.bounds.height - 10)
            let relativeProgress = oldContentHeight > 0 ? (oldOffset / oldContentHeight) : 0
            
            lastViewSize = view.bounds.size
            scrollView.frame = view.bounds
            scrollView.contentInset = UIEdgeInsets(top: safeAreaTop, left: 0, bottom: ReaderConstants.Layout.verticalContentInsetBottom, right: 0)
            
            // 旋转后恢复位置
            if oldContentHeight > 0 {
                self.view.layoutIfNeeded()
                if wasAtBottom {
                    self.scrollToBottom(animated: false)
                } else {
                    let newTargetY = (scrollView.contentSize.height * relativeProgress) - safeAreaTop
                    scrollView.setContentOffset(CGPoint(x: 0, y: newTargetY), animated: false)
                }
            }
        }
    }
    
    @objc private func handleTap() { onToggleMenu?() }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return stackView
    }

    func update(urls: [String]) {
        guard urls != self.imageUrls else { return }
        
        // 1. 取消正在进行的任务，防止旧任务操作已移除的视图
        loadingTasks.values.forEach { $0.cancel() }
        loadingTasks.removeAll()
        
        self.imageUrls = urls

        if urls.isEmpty {
            LogManager.shared.log("漫画图片列表为空", category: "漫画调试")
        }

        func startLoadImage(
            urlStr: String,
            imageView: UIImageView,
            placeholderConstraint: NSLayoutConstraint,
            retryButton: UIButton,
            spinner: UIActivityIndicatorView,
            index: Int
        ) {
            let task = Task {
                await MainActor.run {
                    retryButton.isHidden = true
                    spinner.startAnimating()
                }
                
                let cleanUrl = urlStr.replacingOccurrences(of: "__IMG__", with: "").trimmingCharacters(in: .whitespaces)
                guard let resolved = MangaImageService.shared.resolveImageURL(cleanUrl) else {
                    await MainActor.run {
                        spinner.stopAnimating()
                        retryButton.isHidden = false
                        retryButton.superview?.bringSubviewToFront(retryButton)
                    }
                    LogManager.shared.log("漫画图片URL解析失败: \(cleanUrl)", category: "漫画调试")
                    return
                }
                
                let absolute = resolved.absoluteString
                
                // 并发排队期间持续显示进度环
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
                        guard imageView.superview != nil else { return }
                        spinner.stopAnimating()
                        retryButton.isHidden = true
                        imageView.image = image
                        let ratio = image.size.height / image.size.width
                        placeholderConstraint.isActive = false
                        imageView.heightAnchor.constraint(equalTo: imageView.widthAnchor, multiplier: ratio).isActive = true
                        if self.pendingScrollIndex == index {
                            self.scrollToIndex(index, animated: false)
                        }
                    }
                } else {
                    await MainActor.run {
                        if Task.isCancelled { return }
                        spinner.stopAnimating()
                        retryButton.isHidden = false
                        retryButton.superview?.bringSubviewToFront(retryButton)
                    }
                    LogManager.shared.log("漫画图片加载失败: \(absolute)", category: "漫画调试")
                }
            }
            loadingTasks[index] = task
        }

        // 2. 清理旧视图
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        
        for (index, urlStr) in urls.enumerated() {
            let container = UIView()
            container.backgroundColor = .clear
            container.translatesAutoresizingMaskIntoConstraints = false

            let iv = UIImageView()
            iv.contentMode = .scaleAspectFit
            iv.clipsToBounds = true
            iv.backgroundColor = UIColor.white.withAlphaComponent(0.05)
            iv.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(iv)
            NSLayoutConstraint.activate([
                iv.topAnchor.constraint(equalTo: container.topAnchor),
                iv.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                iv.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                iv.bottomAnchor.constraint(equalTo: container.bottomAnchor)
            ])
            stackView.addArrangedSubview(container)
            let placeholderConstraint = iv.heightAnchor.constraint(equalToConstant: 300)
            placeholderConstraint.priority = .defaultHigh
            placeholderConstraint.isActive = true

            // 添加进度环
            let spinner = UIActivityIndicatorView(style: .medium)
            spinner.color = .white
            spinner.hidesWhenStopped = true
            spinner.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(spinner)
            NSLayoutConstraint.activate([
                spinner.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                spinner.centerYAnchor.constraint(equalTo: container.centerYAnchor)
            ])

            let retryButton = UIButton(type: .system)
            retryButton.setTitle("重试", for: .normal)
            retryButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
            retryButton.setTitleColor(.white, for: .normal)
            // 强化视觉：使用系统蓝色背景，增加辨识度
            retryButton.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.8)
            retryButton.layer.cornerRadius = 12
            retryButton.contentEdgeInsets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
            retryButton.isHidden = true
            retryButton.translatesAutoresizingMaskIntoConstraints = false
            retryButton.layer.zPosition = 100
            retryButton.isExclusiveTouch = true
            container.addSubview(retryButton)
            NSLayoutConstraint.activate([
                retryButton.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                retryButton.centerYAnchor.constraint(equalTo: container.centerYAnchor)
            ])
            
            let urlStr2 = urlStr.replacingOccurrences(of: "__IMG__", with: "").trimmingCharacters(in: .whitespaces)
            let resolvedForCache = MangaImageService.shared.resolveImageURL(urlStr2)
            let absoluteForCache = resolvedForCache?.absoluteString
            if resolvedForCache == nil {
                spinner.stopAnimating()
                retryButton.isHidden = false
                retryButton.superview?.bringSubviewToFront(retryButton)
                LogManager.shared.log("漫画图片URL解析失败: \(urlStr2)", category: "漫画调试")
                continue
            }
            
            // 尝试同步加载本地缓存
            if let b = bookUrl, let abs = absoluteForCache,
               let cachedData = LocalCacheManager.shared.loadMangaImage(bookUrl: b, chapterIndex: chapterIndex, imageURL: abs),
               let image = UIImage(data: cachedData) {
                iv.image = image
                let ratio = image.size.height / image.size.width
                placeholderConstraint.isActive = false
                iv.heightAnchor.constraint(equalTo: iv.widthAnchor, multiplier: ratio).isActive = true
                if self.pendingScrollIndex == index {
                    self.scrollToIndex(index, animated: false)
                }
                retryButton.isHidden = true
                spinner.stopAnimating()
                continue
            }
            
            retryButton.addAction(UIAction { [weak self, weak iv, weak placeholderConstraint, weak retryButton, weak spinner] _ in
                guard let self, let iv, let placeholderConstraint, let retryButton, let spinner else { return }
                startLoadImage(urlStr: urlStr, imageView: iv, placeholderConstraint: placeholderConstraint, retryButton: retryButton, spinner: spinner, index: index)
            }, for: .touchUpInside)

            // 异步加载
            startLoadImage(urlStr: urlStr, imageView: iv, placeholderConstraint: placeholderConstraint, retryButton: retryButton, spinner: spinner, index: index)
        }
    }

    func updateNextChapterPrefetch(urls: [String]) {
        // Legacy mode does not prefetch next chapter images.
    }

    func scrollToIndex(_ index: Int, animated: Bool = false) {
        self.pendingScrollIndex = index
        guard index >= 0, index < stackView.arrangedSubviews.count else { return }
        
        let targetView = stackView.arrangedSubviews[index]
        // 只有当高度大于 0 时才认为布局完成
        if targetView.frame.height > 0 {
            self.view.layoutIfNeeded()
            let targetY = targetView.frame.origin.y - safeAreaTop
            scrollView.setContentOffset(CGPoint(x: 0, y: targetY), animated: animated)
            self.pendingScrollIndex = nil // 完成后清除
        }
    }
    
    func scrollToBottom(animated: Bool = false) {
        self.view.layoutIfNeeded()
        let bottomOffset = CGPoint(x: 0, y: max(-safeAreaTop, scrollView.contentSize.height - scrollView.bounds.height))
        scrollView.setContentOffset(bottomOffset, animated: animated)
    }

    func scrollViewDidScroll(_ s: UIScrollView) {
        let rawOffset = s.contentOffset.y
        if s.isDragging {
            handleHoldSwitchIfNeeded(rawOffset: rawOffset)
        }
        
        let actualMaxScrollY = max(-safeAreaTop, stackView.frame.height - scrollView.bounds.height)
        let currentScale = s.zoomScale
        
        // 按 Y 轴比例计算平滑进度
        let offset = rawOffset + safeAreaTop
        let maxOffset = stackView.frame.height - s.bounds.height
        if maxOffset > 0 {
            progressLabel.text = ReaderProgressFormatter.percentProgressText(offset: offset, maxOffset: maxOffset)
        } else {
            progressLabel.text = "0%"
        }
        
        if rawOffset < -safeAreaTop {
            let diff = -safeAreaTop - rawOffset
            let ty = (diff * dampingFactor) / currentScale
            stackView.transform = CGAffineTransform(scaleX: currentScale, y: currentScale).translatedBy(x: 0, y: ty)
        } else if rawOffset > actualMaxScrollY {
            let diff = rawOffset - actualMaxScrollY
            let ty = (-diff * dampingFactor) / currentScale
            stackView.transform = CGAffineTransform(scaleX: currentScale, y: currentScale).translatedBy(x: 0, y: ty)
        } else {
            // 正常区域，确保清除位移但保留缩放
            if stackView.transform.ty != 0 || stackView.transform.a != currentScale {
                stackView.transform = CGAffineTransform(scaleX: currentScale, y: currentScale)
            }
        }
        
        // 计算当前可见的图片索引
        let visibleY = rawOffset + safeAreaTop
        var found = false
        for (index, view) in stackView.arrangedSubviews.enumerated() {
            if view.frame.maxY > visibleY {
                if currentVisibleIndex != index {
                    currentVisibleIndex = index
                    onVisibleIndexChanged?(index)
                }
                found = true
                break
            }
        }
        if !found && !stackView.arrangedSubviews.isEmpty {
            let lastIdx = stackView.arrangedSubviews.count - 1
            if currentVisibleIndex != lastIdx {
                currentVisibleIndex = lastIdx
                onVisibleIndexChanged?(lastIdx)
            }
        }
    }
    
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        cancelSwitchHold()
        onInteractionChanged?(true)
    }
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if switchReady && pendingSwitchDirection != 0 {
            let direction = pendingSwitchDirection
            self.onChapterSwitched?(direction)
            self.cancelSwitchHold()
        } else {
            if !decelerate { onInteractionChanged?(false) }
            cancelSwitchHold()
        }
    }
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        cancelSwitchHold()
        onInteractionChanged?(false)
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
        if switchHintLabel.alpha == 0 { UIView.animate(withDuration: ReaderConstants.Interaction.switchHintAnimation) { self.switchHintLabel.alpha = 1 } }
    }

    private func hideSwitchHint() {
        guard switchHintLabel.alpha > 0 else { return }
        UIView.animate(withDuration: ReaderConstants.Interaction.switchHintAnimation) { self.switchHintLabel.alpha = 0 }
    }

    private func handleHoldSwitchIfNeeded(rawOffset: CGFloat) {
        let actualMaxScrollY = max(0, scrollView.contentSize.height - scrollView.bounds.height)
        let topPullDistance = max(0, -rawOffset)
        let bottomPullDistance = max(0, rawOffset - actualMaxScrollY)

        if topPullDistance > ReaderConstants.Interaction.pullThreshold {
            if topPullDistance > threshold {
                if !switchReady {
                    switchReady = true; pendingSwitchDirection = -1
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
                    switchReady = true; pendingSwitchDirection = 1
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                }
                updateSwitchHint(text: "松开切换下一章", isTop: false)
            } else {
                if switchReady { switchReady = false }
                updateSwitchHint(text: "上拉切换下一章", isTop: false)
            }
        } else {
            // 回到正常区域
            cancelSwitchHold()
        }
    }

    private func beginSwitchHold(direction: Int, isTop: Bool) {
        if pendingSwitchDirection == direction, switchWorkItem != nil { return }
        cancelSwitchHold()
        pendingSwitchDirection = direction
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, self.scrollView.isDragging else { return }
            self.switchReady = true
            self.updateSwitchHint(text: direction > 0 ? "松手切换下一章" : "松手切换上一章", isTop: isTop)
        }
        switchWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + switchHoldDuration, execute: work)
    }

    private func cancelSwitchHold() {
        switchWorkItem?.cancel(); switchWorkItem = nil
        pendingSwitchDirection = 0; switchReady = false; hideSwitchHint()
    }
}
