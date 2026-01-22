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
            if !animated || mode == .none {
                self.currentPageIndex = targetIndex
                newHorizontalVC?.scrollToPageIndex(targetIndex, animated: false)
                self.isInternalTransitioning = false
                self.onProgressChanged?(currentChapterIndex, Double(currentPageIndex) / Double(max(1, currentCache.pages.count)))
                updateProgressUI()
                return
            }
            
            performChapterTransition(isNext: isNext) { [weak self] in
                guard let self = self else { return }
                self.currentPageIndex = targetIndex
                self.newHorizontalVC?.scrollToPageIndex(targetIndex, animated: false)
                self.onProgressChanged?(self.currentChapterIndex, Double(self.currentPageIndex) / Double(max(1, self.currentCache.pages.count)))
                self.updateProgressUI()
            }
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
            }
            if !animated {
                self.isInternalTransitioning = false
                self.isAutoScrolling = false
            }
            updateProgressUI()
            self.onProgressChanged?(currentChapterIndex, Double(currentPageIndex) / Double(max(1, currentCache.pages.count)))
        }
    }

    func animateToAdjacentChapter(offset: Int, targetPage: Int) {
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
            }
        }
    }

    func handlePageTap(isNext: Bool) {
        guard !isInternalTransitioning else {
            finalizeUserInteraction()
            return
        }
        notifyUserInteractionStarted()
        let t = isNext ? currentPageIndex + 1 : currentPageIndex - 1
        var didChangeWithinChapter = false
        if t >= 0 && t < currentCache.pages.count {
            updateHorizontalPage(to: t, animated: true)
            didChangeWithinChapter = true
        } else {
            let targetChapter = isNext ? currentChapterIndex + 1 : currentChapterIndex - 1
            guard targetChapter >= 0 && targetChapter < chapters.count else {
                finalizeUserInteraction()
                return
            }

            if isNext, !nextCache.pages.isEmpty {
                animateToAdjacentChapter(offset: 1, targetPage: 0)
                didChangeWithinChapter = true
            } else if !isNext, !prevCache.pages.isEmpty {
                animateToAdjacentChapter(offset: -1, targetPage: prevCache.pages.count - 1)
                didChangeWithinChapter = true
            } else {
                isInternalTransitioning = true 
                requestChapterSwitch(to: targetChapter, startAtEnd: !isNext)
            }
        }
        if didChangeWithinChapter {
            notifyUserInteractionEnded()
        }
    }

    func performChapterTransition(isNext: Bool, updates: @escaping () -> Void) {
        let mode = readerSettings.pageTurningMode
        
        guard !isInternalTransitioning else { return }
        isInternalTransitioning = true
        
        let containerView = view!
        let themeColor = readerSettings.readingTheme.backgroundColor
        
        let activeView: UIView?
        if currentReadingMode == .newHorizontal {
            activeView = newHorizontalVC?.view
        } else if currentReadingMode == .horizontal {
            activeView = horizontalVC?.view
        } else if currentReadingMode == .vertical {
            activeView = verticalVC?.view
        } else {
            activeView = mangaVC?.view
        }
        
        guard let horizontalView = activeView else {
            updates()
            self.isInternalTransitioning = false
            return
        }
        
        // 1. 截取当前视图快照
        let snapshot = horizontalView.snapshotView(afterScreenUpdates: false)
        snapshot?.frame = horizontalView.frame
        snapshot?.backgroundColor = themeColor
        
        // 2. 执行内容更新
        updates()
        
        if mode == .none {
            self.isInternalTransitioning = false
            self.notifyUserInteractionEnded()
            return
        }
        
        // 3. 执行动画
        switch mode {
        case .scroll:
            if let snap = snapshot { containerView.insertSubview(snap, aboveSubview: horizontalView) }
            let width = horizontalView.bounds.width
            horizontalView.transform = CGAffineTransform(translationX: isNext ? width : -width, y: 0)
            UIView.animate(withDuration: 0.35, delay: 0, options: .curveEaseInOut, animations: {
                snapshot?.transform = CGAffineTransform(translationX: isNext ? -width : width, y: 0)
                horizontalView.transform = .identity
            }, completion: { _ in
                snapshot?.removeFromSuperview()
                self.isInternalTransitioning = false
                self.notifyUserInteractionEnded()
            })
            
        case .cover:
            // 覆盖翻页：旧快照在下，新视图在上。新视图强设背景色消除重影
            if let snap = snapshot { containerView.insertSubview(snap, belowSubview: horizontalView) }
            let width = horizontalView.bounds.width
            horizontalView.transform = CGAffineTransform(translationX: isNext ? width : -width, y: 0)
            horizontalView.alpha = 1.0 
            horizontalView.backgroundColor = themeColor 
            
            horizontalView.layer.shadowColor = UIColor.black.cgColor
            horizontalView.layer.shadowOpacity = 0.4 // 增加阴影深度，提升层级感
            horizontalView.layer.shadowOffset = CGSize(width: isNext ? -4 : 4, height: 0)
            horizontalView.layer.shadowRadius = 10
            
            UIView.animate(withDuration: 0.45, delay: 0, options: .curveEaseOut, animations: {
                horizontalView.transform = .identity
                snapshot?.transform = CGAffineTransform(translationX: isNext ? -width * 0.3 : width * 0.3, y: 0)
                snapshot?.alpha = 0.7 // 旧页面适当变暗
            }, completion: { _ in
                snapshot?.removeFromSuperview()
                horizontalView.layer.shadowOpacity = 0
                self.isInternalTransitioning = false
                self.notifyUserInteractionEnded()
            })
            
        case .fade, .simulation: 
            if let snap = snapshot { containerView.insertSubview(snap, aboveSubview: horizontalView) }
            horizontalView.alpha = 0
            UIView.animate(withDuration: 0.35, animations: {
                snapshot?.alpha = 0
                horizontalView.alpha = 1
            }, completion: { _ in
                snapshot?.removeFromSuperview()
                self.isInternalTransitioning = false
                self.notifyUserInteractionEnded()
            })
            
        case .flip:
            UIView.transition(with: horizontalView, duration: 0.5, options: isNext ? .transitionFlipFromRight : .transitionFlipFromLeft, animations: nil) { _ in
                self.isInternalTransitioning = false
                self.notifyUserInteractionEnded()
            }
            
        default:
            self.isInternalTransitioning = false
            self.notifyUserInteractionEnded()
        }
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
