import UIKit

extension ReaderContainerViewController {
    func pageViewController(_ pvc: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) {
        if !isInternalTransitioning {
            notifyUserInteractionStarted()
        }
    }

    func pageViewController(_ pvc: UIPageViewController, didFinishAnimating f: Bool, previousViewControllers p: [UIViewController], transitionCompleted completed: Bool) {
        guard let v = pvc.viewControllers?.first as? PageContentViewController else {
            isInternalTransitioning = false
            notifyUserInteractionEnded()
            return
        }
        guard completed else {
            isInternalTransitioning = false
            notifyUserInteractionEnded()
            return
        }

        if v.chapterOffset != 0 {
            completeDataDrift(offset: v.chapterOffset, targetPage: v.pageIndex, currentVC: v)
        } else {
            self.currentPageIndex = v.pageIndex
            self.onProgressChanged?(currentChapterIndex, Double(currentPageIndex) / Double(max(1, currentCache.pages.count)))
            updateProgressUI()
            self.isInternalTransitioning = false
            notifyUserInteractionEnded()
        }
    }

    func pageViewController(_ pvc: UIPageViewController, viewControllerBefore vc: UIViewController) -> UIViewController? {
        guard let c = vc as? PageContentViewController, !isInternalTransitioning else { return nil }
        if c.chapterOffset == 0 {
            if c.pageIndex > 0 { return createPageVC(at: c.pageIndex - 1, offset: 0) }
            if !prevCache.pages.isEmpty { return createPageVC(at: prevCache.pages.count - 1, offset: -1) }
            
            // 仿真模式：如果上一章缓存未就绪，但在开头向左滑，主动触发跳转
            if currentChapterIndex > 0 {
                DispatchQueue.main.async { [weak self] in
                    self?.handlePageTap(isNext: false)
                }
            }
        }
        return nil
    }

    func pageViewController(_ pvc: UIPageViewController, viewControllerAfter vc: UIViewController) -> UIViewController? {
        guard let c = vc as? PageContentViewController, !isInternalTransitioning else { return nil }
        if c.chapterOffset == 0 {
            if c.pageIndex < currentCache.pages.count - 1 { return createPageVC(at: c.pageIndex + 1, offset: 0) }
            if !nextCache.pages.isEmpty { return createPageVC(at: 0, offset: 1) }
            
            // 仿真模式：如果下一章缓存未就绪，但在末尾向右滑，主动触发跳转
            if currentChapterIndex < chapters.count - 1 {
                DispatchQueue.main.async { [weak self] in
                    self?.handlePageTap(isNext: true)
                }
            }
        }
        return nil
    }

    func updateHorizontalPage(to i: Int, animated: Bool) {
        let oldIndex = self.currentPageIndex
        let isNext = i > oldIndex
        let targetIndex = max(0, min(i, currentCache.pages.count - 1))

        if currentReadingMode == .newHorizontal {
            let mode = readerSettings.pageTurningMode
            let shouldAnimate = animated && mode != .none
            // 关键：统一使用 CollectionView 的滚动来触发动画
            self.currentPageIndex = targetIndex
            newHorizontalVC?.scrollToPageIndex(targetIndex, animated: shouldAnimate)
            
            self.onProgressChanged?(currentChapterIndex, Double(currentPageIndex) / Double(max(1, currentCache.pages.count)))
            updateProgressUI()
            return
        }
        
        guard let h = horizontalVC, !currentCache.pages.isEmpty else { return }
        let direction: UIPageViewController.NavigationDirection = isNext ? .forward : .reverse
        
        if animated && readerSettings.pageTurningMode != .simulation {
            // 如果不是仿真模式且需要动画，统一走自研转场引擎以支持 Cover/Fade 等效果
            performChapterTransition(isNext: isNext) { [weak self] in
                guard let self = self else { return }
                self.currentPageIndex = targetIndex
                h.setViewControllers([self.createPageVC(at: targetIndex, offset: 0)], direction: direction, animated: false, completion: nil)
                self.onProgressChanged?(self.currentChapterIndex, Double(self.currentPageIndex) / Double(max(1, self.currentCache.pages.count)))
                self.updateProgressUI()
            }
        } else {
            // 仿真模式或无动画，走原生路径
            currentPageIndex = targetIndex
            if animated { self.isAutoScrolling = true }
            h.setViewControllers([createPageVC(at: targetIndex, offset: 0)], direction: direction, animated: animated) { [weak self] finished in
                guard let self = self else { return }
                self.isInternalTransitioning = false
                self.isAutoScrolling = false
                self.notifyUserInteractionEnded()
            }
            if !animated {
                self.isInternalTransitioning = false
                self.isAutoScrolling = false
                self.notifyUserInteractionEnded()
            }
            updateProgressUI()
            self.onProgressChanged?(currentChapterIndex, Double(currentPageIndex) / Double(max(1, currentCache.pages.count)))
        }
    }

    func animateToAdjacentChapter(offset: Int, targetPage: Int, animated: Bool = true) {
        let isNext = offset > 0
        if currentReadingMode == .newHorizontal || (currentReadingMode == .horizontal && readerSettings.pageTurningMode != .simulation) {
            performChapterTransition(isNext: isNext) { [weak self] in
                self?.completeDataDrift(offset: offset, targetPage: targetPage, currentVC: nil)
            }
            return
        }
        
        // 仿真模式的原生跨章
        guard let h = horizontalVC, !isInternalTransitioning else { return }
        isInternalTransitioning = true
        self.isAutoScrolling = true
        let vc = createPageVC(at: targetPage, offset: offset)
        let direction: UIPageViewController.NavigationDirection = isNext ? .forward : .reverse

        h.setViewControllers([vc], direction: direction, animated: true) { [weak self] completed in
            guard let self = self else { return }
            // 无论动画是否完全 completed（有时会被中断），只要视图已经切换，就执行数据漂移
            Task { @MainActor in
                let currentVC = h.viewControllers?.first as? PageContentViewController
                self.completeDataDrift(offset: offset, targetPage: targetPage, currentVC: currentVC)
                self.notifyUserInteractionEnded()
            }
        }
    }

    func handlePageTap(isNext: Bool) {
        interactionCoordinator.handlePageTap(isNext: isNext)
    }

    func performChapterTransition(isNext: Bool, updates: @escaping () -> Void) {
        pageTransitionCoordinator.performTransition(mode: readerSettings.pageTurningMode, isNext: isNext, updates: updates)
    }

    func performChapterTransitionFade(_ updates: @escaping () -> Void) {
        performChapterTransition(isNext: true, updates: updates)
    }
}

private extension ReaderContainerViewController {
    func completeDataDrift(offset: Int, targetPage: Int, currentVC: PageContentViewController?) {
        self.isInternalTransitioning = true
        if offset > 0 {
            prevCache = currentCache
            currentCache = nextCache
            nextCache = .empty
        } else {
            nextCache = currentCache
            currentCache = prevCache
            prevCache = .empty
        }

        self.currentChapterIndex += offset
        self.lastReportedChapterIndex = self.currentChapterIndex
        self.currentPageIndex = targetPage
        self.onChapterIndexChanged?(self.currentChapterIndex)

        if currentReadingMode == .newHorizontal {
            updateNewHorizontalContent()
        } else if let v = currentVC {
            v.chapterOffset = 0
            if let rv = v.view.subviews.first as? ReadContent2View {
                rv.renderStore = self.currentCache.renderStore
                rv.paragraphStarts = self.currentCache.paragraphStarts
                rv.chapterPrefixLen = self.currentCache.chapterPrefixLen
            }
        }

        self.onProgressChanged?(currentChapterIndex, Double(currentPageIndex) / Double(max(1, currentCache.pages.count)))
        updateProgressUI()
        prefetchAdjacentChapters(index: currentChapterIndex)
        self.isInternalTransitioning = false
    }

    func createPageVC(at i: Int, offset: Int) -> PageContentViewController {
        let vc = PageContentViewController(pageIndex: i, chapterOffset: offset)
        vc.view.backgroundColor = readerSettings.readingTheme.backgroundColor
        vc.view.isOpaque = true
        let pV = ReadContent2View(frame: .zero)
        let cache = offset == 0 ? currentCache : (offset > 0 ? nextCache : prevCache)
        let aS = cache.renderStore
        let aI = cache.pageInfos ?? []
        let aPS = offset == 0 ? currentCache.paragraphStarts : []

        pV.renderStore = aS
        pV.pageIndex = i
        pV.onVisibleFragments = { [weak self] pageIdx, lines in
            guard let self = self else { return }
            let displayPage = self.horizontalPageIndexForDisplay()
            if pageIdx == displayPage {
                self.latestVisibleFragmentLines = lines
            }
        }
        if i < aI.count {
            let info = aI[i]
            pV.pageInfo = TK2PageInfo(range: info.range, yOffset: info.yOffset, pageHeight: info.pageHeight, actualContentHeight: info.actualContentHeight, startSentenceIndex: info.startSentenceIndex, contentInset: currentLayoutSpec.topInset)
        }
        pV.onTapLocation = { [weak self] loc in if loc == .middle { self?.safeToggleMenu() } else { self?.handlePageTap(isNext: loc == .right) } }
        pV.onImageTapped = { [weak self] url in
            self?.presentImagePreview(url: url)
        }
        pV.onAddReplaceRule = { [weak self] text in self?.onAddReplaceRuleWithText?(text) }
        pV.horizontalInset = currentLayoutSpec.sideMargin
        pV.paragraphStarts = aPS
        pV.chapterPrefixLen = offset == 0 ? currentCache.chapterPrefixLen : 0

        vc.view.addSubview(pV)
        pV.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            pV.topAnchor.constraint(equalTo: vc.view.topAnchor),
            pV.bottomAnchor.constraint(equalTo: vc.view.bottomAnchor),
            pV.leadingAnchor.constraint(equalTo: vc.view.leadingAnchor),
            pV.trailingAnchor.constraint(equalTo: vc.view.trailingAnchor)
        ])
        return vc
    }
}
