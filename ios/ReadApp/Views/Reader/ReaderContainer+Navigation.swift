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
            let shouldAnimate = readerSettings.pageTurningMode != .none
            updateHorizontalPage(to: t, animated: shouldAnimate)
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
        
        // 安全锁：1.0s 后强制释放，防止动画回调丢失导致的逻辑死锁
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.isInternalTransitioning = false
            self?.notifyUserInteractionEnded()
        }
        
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
            return
        }
        
        // 1. 截取旧视图快照 (Old Snapshot)
        let oldSnapshot = horizontalView.snapshotView(afterScreenUpdates: false)
        oldSnapshot?.frame = horizontalView.frame
        oldSnapshot?.backgroundColor = themeColor
        
        if let snap = oldSnapshot { containerView.insertSubview(snap, aboveSubview: horizontalView) }
        
        // 2. 执行内容更新，并强制触发布局
        updates()
        horizontalView.setNeedsLayout()
        horizontalView.layoutIfNeeded()
        
        if mode == .none {
            oldSnapshot?.removeFromSuperview()
            return
        }

        // 3. 截取新视图快照 (New Snapshot)，用于实现平滑转场，避免 CollectionView 异步重绘闪烁
        let newSnapshot = horizontalView.snapshotView(afterScreenUpdates: true)
        newSnapshot?.frame = horizontalView.frame
        newSnapshot?.backgroundColor = themeColor
        if let newSnap = newSnapshot { containerView.insertSubview(newSnap, aboveSubview: oldSnapshot!) }
        
        // 4. 执行动画 (在快照之间进行)
        let width = horizontalView.bounds.width
        switch mode {
        case .scroll:
            newSnapshot?.transform = CGAffineTransform(translationX: isNext ? width : -width, y: 0)
            UIView.animate(withDuration: 0.35, delay: 0, options: .curveEaseInOut, animations: {
                oldSnapshot?.transform = CGAffineTransform(translationX: isNext ? -width : width, y: 0)
                newSnapshot?.transform = .identity
            }, completion: { _ in
                oldSnapshot?.removeFromSuperview()
                newSnapshot?.removeFromSuperview()
            })
            
        case .cover:
            // 覆盖模式：新快照从侧边滑入覆盖旧快照
            newSnapshot?.transform = CGAffineTransform(translationX: isNext ? width : -width, y: 0)
            newSnapshot?.layer.shadowColor = UIColor.black.cgColor
            newSnapshot?.layer.shadowOpacity = 0.4
            newSnapshot?.layer.shadowOffset = CGSize(width: isNext ? -4 : 4, height: 0)
            newSnapshot?.layer.shadowRadius = 10
            
            UIView.animate(withDuration: 0.45, delay: 0, options: .curveEaseOut, animations: {
                newSnapshot?.transform = .identity
                oldSnapshot?.transform = CGAffineTransform(translationX: isNext ? -width * 0.3 : width * 0.3, y: 0)
                oldSnapshot?.alpha = 0.7
            }, completion: { _ in
                oldSnapshot?.removeFromSuperview()
                newSnapshot?.removeFromSuperview()
            })
            
        case .fade, .simulation: 
            newSnapshot?.alpha = 0
            UIView.animate(withDuration: 0.35, animations: {
                oldSnapshot?.alpha = 0
                newSnapshot?.alpha = 1
            }, completion: { _ in
                oldSnapshot?.removeFromSuperview()
                newSnapshot?.removeFromSuperview()
            })
            
        case .flip:
            newSnapshot?.isHidden = true
            UIView.transition(with: containerView, duration: 0.5, options: isNext ? .transitionFlipFromRight : .transitionFlipFromLeft, animations: {
                oldSnapshot?.isHidden = true
                newSnapshot?.isHidden = false
            }) { _ in
                oldSnapshot?.removeFromSuperview()
                newSnapshot?.removeFromSuperview()
            }
            
        default:
            oldSnapshot?.removeFromSuperview()
            newSnapshot?.removeFromSuperview()
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
