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
        }
        return nil
    }

    func pageViewController(_ pvc: UIPageViewController, viewControllerAfter vc: UIViewController) -> UIViewController? {
        guard let c = vc as? PageContentViewController, !isInternalTransitioning else { return nil }
        if c.chapterOffset == 0 {
            if c.pageIndex < currentCache.pages.count - 1 { return createPageVC(at: c.pageIndex + 1, offset: 0) }
            if !nextCache.pages.isEmpty { return createPageVC(at: 0, offset: 1) }
        }
        return nil
    }

    func updateHorizontalPage(to i: Int, animated: Bool) {
        if currentReadingMode == .newHorizontal {
            let oldIndex = self.currentPageIndex
            self.currentPageIndex = i
            
            let mode = readerSettings.pageTurningMode
            if !animated || mode == .none {
                newHorizontalVC?.scrollToPageIndex(i, animated: false)
                self.isInternalTransitioning = false
                self.onProgressChanged?(currentChapterIndex, Double(currentPageIndex) / Double(max(1, currentCache.pages.count)))
                updateProgressUI()
                return
            }
            
            if mode == .cover, let horizontalView = newHorizontalVC?.view {
                // ... (原有 cover 代码保持不变)
                isInternalTransitioning = true
                let width = horizontalView.bounds.width
                let isNext = i > oldIndex
                let snapshot = horizontalView.snapshotView(afterScreenUpdates: false)
                snapshot?.frame = horizontalView.frame
                if let snap = snapshot { view.insertSubview(snap, aboveSubview: horizontalView) }
                newHorizontalVC?.scrollToPageIndex(i, animated: false)
                horizontalView.transform = CGAffineTransform(translationX: isNext ? width : -width, y: 0)
                UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseOut, animations: {
                    horizontalView.transform = .identity
                    snapshot?.transform = CGAffineTransform(translationX: isNext ? -width * 0.2 : width * 0.2, y: 0)
                    snapshot?.alpha = 0.8
                }, completion: { _ in
                    snapshot?.removeFromSuperview()
                    self.isInternalTransitioning = false
                    self.onProgressChanged?(self.currentChapterIndex, Double(self.currentPageIndex) / Double(max(1, self.currentCache.pages.count)))
                    self.updateProgressUI()
                })
                return
            }
            
            if mode == .fade, let horizontalView = newHorizontalVC?.view {
                isInternalTransitioning = true
                let snapshot = horizontalView.snapshotView(afterScreenUpdates: false)
                snapshot?.frame = horizontalView.frame
                if let snap = snapshot { view.insertSubview(snap, aboveSubview: horizontalView) }
                
                newHorizontalVC?.scrollToPageIndex(i, animated: false)
                horizontalView.alpha = 0
                
                UIView.animate(withDuration: 0.35, animations: {
                    snapshot?.alpha = 0
                    horizontalView.alpha = 1
                }, completion: { _ in
                    snapshot?.removeFromSuperview()
                    self.isInternalTransitioning = false
                    self.onProgressChanged?(self.currentChapterIndex, Double(self.currentPageIndex) / Double(max(1, self.currentCache.pages.count)))
                    self.updateProgressUI()
                })
                return
            }
            
            if mode == .flip, let horizontalView = newHorizontalVC?.view {
                isInternalTransitioning = true
                let isNext = i > oldIndex
                UIView.transition(with: horizontalView, duration: 0.5, options: isNext ? .transitionFlipFromRight : .transitionFlipFromLeft, animations: {
                    self.newHorizontalVC?.scrollToPageIndex(i, animated: false)
                }, completion: { _ in
                    self.isInternalTransitioning = false
                    self.onProgressChanged?(self.currentChapterIndex, Double(self.currentPageIndex) / Double(max(1, self.currentCache.pages.count)))
                    self.updateProgressUI()
                })
                return
            }
            
            // 默认滑动动画
            newHorizontalVC?.scrollToPageIndex(i, animated: animated)
            self.onProgressChanged?(currentChapterIndex, Double(currentPageIndex) / Double(max(1, currentCache.pages.count)))
            updateProgressUI()
            return
        }
        guard let h = horizontalVC, !currentCache.pages.isEmpty else { return }
        let targetIndex = max(0, min(i, currentCache.pages.count - 1))
        let direction: UIPageViewController.NavigationDirection = targetIndex >= currentPageIndex ? .forward : .reverse
        currentPageIndex = targetIndex
        
        if animated {
            self.isAutoScrolling = true
        }
        
        h.setViewControllers([createPageVC(at: targetIndex, offset: 0)], direction: direction, animated: animated) { [weak self] finished in
            guard let self = self else { return }
            if animated {
                self.isInternalTransitioning = false
            }
            self.isAutoScrolling = false
        }
        if !animated {
            self.isInternalTransitioning = false
            self.isAutoScrolling = false
        }
        updateProgressUI()
        self.onProgressChanged?(currentChapterIndex, Double(currentPageIndex) / Double(max(1, currentCache.pages.count)))
    }

    func animateToAdjacentChapter(offset: Int, targetPage: Int) {
        if currentReadingMode == .newHorizontal {
            performChapterTransitionSlide(isNext: offset > 0) { [weak self] in
                self?.completeDataDrift(offset: offset, targetPage: targetPage, currentVC: nil)
            }
            return
        }
        guard let h = horizontalVC, !isInternalTransitioning else { return }
        isInternalTransitioning = true
        self.isAutoScrolling = true
        let vc = createPageVC(at: targetPage, offset: offset)
        let direction: UIPageViewController.NavigationDirection = offset > 0 ? .forward : .reverse

        h.setViewControllers([vc], direction: direction, animated: true) { [weak self] completed in
            guard completed, let self = self else { return }
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
            isInternalTransitioning = true
            updateHorizontalPage(to: t, animated: true)
            didChangeWithinChapter = true
        } else {
            let targetChapter = isNext ? currentChapterIndex + 1 : currentChapterIndex - 1
            guard targetChapter >= 0 && targetChapter < chapters.count else {
                finalizeUserInteraction()
                return
            }

            isInternalTransitioning = true // 锁定，防止重复点击导致跳章
            if isNext, !nextCache.pages.isEmpty {
                animateToAdjacentChapter(offset: 1, targetPage: 0)
                didChangeWithinChapter = true
            } else if !isNext, !prevCache.pages.isEmpty {
                animateToAdjacentChapter(offset: -1, targetPage: prevCache.pages.count - 1)
                didChangeWithinChapter = true
            } else {
                requestChapterSwitch(to: targetChapter, startAtEnd: !isNext)
            }
        }
        if didChangeWithinChapter {
            notifyUserInteractionEnded()
        }
    }

    func performChapterTransitionSlide(isNext: Bool, updates: @escaping () -> Void) {
        guard currentReadingMode == .newHorizontal, let horizontalView = newHorizontalVC?.view else {
            updates()
            return
        }
        
        isInternalTransitioning = true
        
        // 1. 截取当前视图快照
        let snapshot = horizontalView.snapshotView(afterScreenUpdates: false)
        snapshot?.frame = horizontalView.frame
        if let snap = snapshot {
            view.insertSubview(snap, aboveSubview: horizontalView)
        }
        
        // 2. 更新内容（静默 reloadData 并重置位置）
        updates()
        
        // 3. 准备新视图动画初始位置
        let width = horizontalView.bounds.width
        horizontalView.transform = CGAffineTransform(translationX: isNext ? width : -width, y: 0)
        
        // 4. 执行平滑滑动动画
        UIView.animate(withDuration: 0.35, delay: 0, options: .curveEaseInOut, animations: {
            snapshot?.transform = CGAffineTransform(translationX: isNext ? -width : width, y: 0)
            horizontalView.transform = .identity
        }, completion: { _ in
            snapshot?.removeFromSuperview()
            self.isInternalTransitioning = false
            self.notifyUserInteractionEnded()
        })
    }

    func performChapterTransitionFade(_ updates: @escaping () -> Void) {
        guard (currentReadingMode == .horizontal || currentReadingMode == .newHorizontal), !isMangaMode else {
            updates()
            return
        }
        isInternalTransitioning = true
        let overlay = UIView(frame: view.bounds)
        overlay.backgroundColor = readerSettings.readingTheme.backgroundColor
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.alpha = 0
        view.addSubview(overlay)
        UIView.animate(withDuration: 0.12, animations: {
            overlay.alpha = 1
        }, completion: { _ in
            updates()
            UIView.animate(withDuration: 0.18, animations: {
                overlay.alpha = 0
            }, completion: { _ in
                overlay.removeFromSuperview()
            })
        })
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
