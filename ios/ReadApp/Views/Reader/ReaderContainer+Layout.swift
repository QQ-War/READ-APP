import UIKit

extension ReaderContainerViewController {
    func reRenderCurrentContent(rawContentOverride: String? = nil, anchorOffset: Int = 0) {
        guard let builder = chapterBuilder else { return }
        let rawContent = rawContentOverride ?? currentCache.rawContent
        let chapterUrl = chapters.indices.contains(currentChapterIndex) ? chapters[currentChapterIndex].url : nil
        let title = chapters.indices.contains(currentChapterIndex) ? chapters[currentChapterIndex].title : ""
        if isMangaMode {
            currentCache = builder.buildMangaCache(rawContent: rawContent, chapterUrl: chapterUrl)
        } else {
            currentCache = builder.buildTextCache(
                rawContent: rawContent,
                title: title,
                layoutSpec: currentLayoutSpec,
                reuseStore: currentCache.renderStore,
                chapterUrl: chapterUrl,
                anchorOffset: anchorOffset
            )
        }

        // 核心同步：渲染后立即更新当前页码为锚点页码
        if currentReadingMode == .horizontal || currentReadingMode == .newHorizontal {
            let maxIndex = max(0, currentCache.pages.count - 1)
            self.currentPageIndex = min(max(0, currentCache.anchorPageIndex), maxIndex)
        }

        setupReaderMode()
        updateProgressUI()
    }

    func rebuildPaginationForLayout() {
        guard !isMangaMode, !currentCache.rawContent.isEmpty else { return }
        let offset = getCurrentReadingCharOffset()
        reRenderCurrentContent(anchorOffset: offset)
    }

    func updateProgressUI() {
        if isMangaMode {
            if let m = mangaVC {
                let s = m.scrollView
                let offset = s.contentOffset.y + s.contentInset.top
                let maxOffset = s.contentSize.height - s.bounds.height + s.contentInset.top
                if maxOffset > 0 {
                    let percent = Int(round(min(1.0, max(0.0, offset / maxOffset)) * 100))
                    m.progressLabel.text = "\(min(100, percent))%"
                } else {
                    m.progressLabel.text = "0%"
                }
                m.progressLabel.isHidden = false
            }
            return
        }
        
        view.bringSubviewToFront(progressLabel)
        if let theme = readerSettings?.readingTheme {
            progressLabel.textColor = theme.textColor
        } else {
            progressLabel.textColor = .white
        }
        
        if currentReadingMode == .horizontal || currentReadingMode == .newHorizontal {
            let pagesCount = currentCache.pages.count
            if pagesCount == 0 { 
                progressLabel.text = ""
                progressLabel.isHidden = true
                return 
            }
            let current = max(1, min(pagesCount, currentPageIndex + 1))
            progressLabel.text = "\(current)/\(pagesCount)"
            progressLabel.isHidden = false
        } else if currentReadingMode == .vertical {
            // 优化垂直模式：使用滚动偏移量计算百分比，比句子索引更准确
            if let v = verticalVC {
                let offset = v.scrollView.contentOffset.y + v.scrollView.contentInset.top
                let maxOffset = v.scrollView.contentSize.height - v.scrollView.bounds.height + v.scrollView.contentInset.top
                if maxOffset > 0 {
                    let percent = Int(round(min(1.0, max(0.0, offset / maxOffset)) * 100))
                    progressLabel.text = "\(percent)%"
                } else {
                    progressLabel.text = "0%"
                }
            }
            progressLabel.isHidden = false
        } else {
            progressLabel.text = ""
            progressLabel.isHidden = true
        }
    }

    func updateVerticalAdjacent(secondaryIndices: Set<Int> = []) {
        guard let v = verticalVC, readerSettings != nil, ttsManager != nil else { return }
        v.isInfiniteScrollEnabled = readerSettings.isInfiniteScrollEnabled
        v.seamlessSwitchThreshold = readerSettings.infiniteScrollSwitchThreshold
        let title = chapters.indices.contains(currentChapterIndex) ? chapters[currentChapterIndex].title : ""
        let nextTitle = (currentChapterIndex + 1 < chapters.count) ? chapters[currentChapterIndex + 1].title : nil
        let prevTitle = (currentChapterIndex - 1 >= 0) ? chapters[currentChapterIndex - 1].title : nil

        // 始终尝试传递预加载内容。
        let nextSentences = nextCache.contentSentences.isEmpty ? nil : nextCache.contentSentences
        let prevSentences = prevCache.contentSentences.isEmpty ? nil : prevCache.contentSentences

        var highlightIdx = ttsManager.isPlaying ? ttsManager.currentSentenceIndex : nil
        var finalSecondaryIndices = secondaryIndices

        // 处理标题偏移导致的索引对齐问题
        if let hIdx = highlightIdx, ttsManager.hasChapterTitleInSentences {
            if ttsManager.isReadingChapterTitle {
                highlightIdx = nil // 正在读标题时不显示正文高亮
            } else {
                highlightIdx = hIdx - 1
            }
            finalSecondaryIndices = Set(secondaryIndices.compactMap { $0 > 0 ? ($0 - 1) : nil })
        }

        // 统一边距：使用与水平模式一致的 currentLayoutSpec.sideMargin
        let unifiedMargin = currentLayoutSpec.sideMargin
        v.update(
            sentences: currentCache.contentSentences,
            nextSentences: nextSentences,
            prevSentences: prevSentences,
            title: title,
            nextTitle: nextTitle,
            prevTitle: prevTitle,
            fontSize: readerSettings.fontSize,
            lineSpacing: readerSettings.lineSpacing,
            margin: unifiedMargin,
            highlightIndex: highlightIdx,
            secondaryIndices: finalSecondaryIndices,
            isPlaying: ttsManager.isPlaying,
            renderStore: currentCache.renderStore,
            paragraphStarts: currentCache.paragraphStarts,
            nextRenderStore: nextCache.renderStore,
            nextParagraphStarts: nextCache.paragraphStarts,
            prevRenderStore: prevCache.renderStore,
            prevParagraphStarts: prevCache.paragraphStarts
        )
        updateProgressUI()
    }

    func setupReaderMode() {
        if isMangaMode {
            verticalVC?.view.removeFromSuperview(); verticalVC = nil
            horizontalVC?.view.removeFromSuperview(); horizontalVC = nil
            newHorizontalVC?.view.removeFromSuperview(); newHorizontalVC = nil
            setupMangaMode()
            return
        }

        mangaVC?.view.removeFromSuperview(); mangaVC?.removeFromParent(); mangaVC = nil

        // 核心引擎路由：只有仿真翻页允许使用旧版 UIPageViewController
        let modeToUse: ReadingMode
        if currentReadingMode == .vertical {
            modeToUse = .vertical
        } else if readerSettings.pageTurningMode == .simulation {
            modeToUse = .horizontal
        } else {
            modeToUse = .newHorizontal
        }
        
        // 关键修复：同步状态变量，否则 handlePageTap 会找不到 VC
        if currentReadingMode != .vertical {
            self.currentReadingMode = modeToUse
        }

        if modeToUse == .vertical {
            if verticalVC == nil {
                horizontalVC?.view.removeFromSuperview(); horizontalVC = nil
                newHorizontalVC?.view.removeFromSuperview(); newHorizontalVC = nil
                setupVerticalMode()
            } else {
                updateVerticalAdjacent()
            }
        } else if modeToUse == .newHorizontal {
            if newHorizontalVC == nil {
                verticalVC?.view.removeFromSuperview(); verticalVC = nil
                horizontalVC?.view.removeFromSuperview(); horizontalVC = nil
                setupNewHorizontalMode()
            } else {
                horizontalVC?.view.removeFromSuperview(); horizontalVC = nil
                updateNewHorizontalContent()
            }
        } else {
            if horizontalVC == nil {
                verticalVC?.view.removeFromSuperview(); verticalVC = nil
                newHorizontalVC?.view.removeFromSuperview(); newHorizontalVC = nil
                setupHorizontalMode()
            } else {
                newHorizontalVC?.view.removeFromSuperview(); newHorizontalVC = nil
            }
        }
        updateProgressUI()
    }

    func setupNewHorizontalMode() {
        let vc = HorizontalCollectionViewController()
        vc.delegate = self
        addChild(vc)
        view.insertSubview(vc.view, at: 0)
        vc.view.frame = view.bounds
        vc.didMove(toParent: self)
        self.newHorizontalVC = vc
        updateNewHorizontalContent()
        updateProgressUI()
    }

    func updateNewHorizontalContent() {
        newHorizontalVC?.update(
            pages: currentCache.pages,
            pageInfos: currentCache.pageInfos ?? [],
            renderStore: currentCache.renderStore,
            paragraphStarts: currentCache.paragraphStarts,
            prefixLen: currentCache.chapterPrefixLen,
            sideMargin: currentLayoutSpec.sideMargin,
            topInset: currentLayoutSpec.topInset,
            anchorPageIndex: currentPageIndex,
            backgroundColor: readerSettings.readingTheme.backgroundColor,
            turningMode: readerSettings.pageTurningMode
        )
        updateProgressUI()
    }

    func setupHorizontalMode() {
        let h = UIPageViewController(transitionStyle: readerSettings.pageTurningMode == .simulation ? .pageCurl : .scroll, navigationOrientation: .horizontal, options: nil)
        h.dataSource = self; h.delegate = self; addChild(h); view.insertSubview(h.view, at: 0); h.didMove(toParent: self)

        // 监听内部滚动视图以检测用户交互
        for view in h.view.subviews {
            if let scrollView = view as? UIScrollView {
                scrollView.delegate = self
            }
        }

        for recognizer in h.gestureRecognizers where recognizer is UITapGestureRecognizer {
            recognizer.isEnabled = false
        }
        self.horizontalVC = h; updateHorizontalPage(to: currentPageIndex, animated: false)
        updateProgressUI()
    }

    func setupVerticalMode() {
        guard readerSettings != nil, ttsManager != nil else {
            // 如果依赖尚未注入，推迟初始化
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.setupVerticalMode() }
            return
        }

        let v = VerticalTextViewController()
        v.onVisibleIndexChanged = { [weak self] idx in
            guard let self = self else { return }
            let count = max(1, self.currentCache.contentSentences.count)
            self.onProgressChanged?(self.currentChapterIndex, Double(idx) / Double(count))
            self.updateProgressUI()
        }
        v.onAddReplaceRule = { [weak self] text in self?.onAddReplaceRuleWithText?(text) }; v.onTapMenu = { [weak self] in self?.safeToggleMenu() }
        v.isInfiniteScrollEnabled = readerSettings.isInfiniteScrollEnabled
        v.onReachedBottom = { [weak self] in
            guard let self = self else { return }
            self.prefetchNextChapterOnly(index: self.currentChapterIndex)
        }
        v.onReachedTop = { [weak self] in
            guard let self = self else { return }
            self.prefetchPrevChapterOnly(index: self.currentChapterIndex)
        }
        v.onChapterSwitched = { [weak self] offset in
            guard let self = self else { return }
            let now = Date().timeIntervalSince1970
            guard now - self.lastChapterSwitchTime > self.chapterSwitchCooldown else { return }
            self.lastChapterSwitchTime = now
            self.requestChapterSwitch(offset: offset, preferSeamless: self.readerSettings.isInfiniteScrollEnabled, startAtEnd: offset < 0)
        }
        v.onInteractionChanged = { [weak self] interacting in
            guard let self = self else { return }
            if interacting {
                self.notifyUserInteractionStarted()
            } else {
                self.notifyUserInteractionEnded()
            }
        }
        v.threshold = verticalThreshold
        v.seamlessSwitchThreshold = readerSettings.infiniteScrollSwitchThreshold
        v.dampingFactor = readerSettings.verticalDampingFactor
        self.verticalVC = v
        addChild(v); view.insertSubview(v.view, at: 0); v.view.frame = view.bounds; v.didMove(toParent: self); v.safeAreaTop = safeAreaTop

        let title = chapters.indices.contains(currentChapterIndex) ? chapters[currentChapterIndex].title : ""
        let nextTitle = (currentChapterIndex + 1 < chapters.count) ? chapters[currentChapterIndex + 1].title : nil
        let prevTitle = (currentChapterIndex - 1 >= 0) ? chapters[currentChapterIndex - 1].title : nil
        let nextSentences = readerSettings.isInfiniteScrollEnabled ? (nextCache.contentSentences.isEmpty ? nil : nextCache.contentSentences) : nil
        let prevSentences = readerSettings.isInfiniteScrollEnabled ? (prevCache.contentSentences.isEmpty ? nil : prevCache.contentSentences) : nil
        v.update(
            sentences: currentCache.contentSentences,
            nextSentences: nextSentences,
            prevSentences: prevSentences,
            title: title,
            nextTitle: nextTitle,
            prevTitle: prevTitle,
            fontSize: readerSettings.fontSize,
            lineSpacing: readerSettings.lineSpacing,
            margin: currentLayoutSpec.sideMargin,
            highlightIndex: ttsManager.isPlaying ? ttsManager.currentSentenceIndex : nil,
            secondaryIndices: [],
            isPlaying: ttsManager.isPlaying,
            renderStore: currentCache.renderStore,
            paragraphStarts: currentCache.paragraphStarts,
            nextRenderStore: nextCache.renderStore,
            nextParagraphStarts: nextCache.paragraphStarts,
            prevRenderStore: prevCache.renderStore,
            prevParagraphStarts: prevCache.paragraphStarts
        )
        updateProgressUI()
    }

    func setupMangaMode() {
        // 尝试使用预制视图实现"立等可取"
        if let prebuilt = prebuiltNextMangaVC, prebuiltNextIndex == currentChapterIndex {
            mangaVC?.view.removeFromSuperview()
            mangaVC?.removeFromParent()

            mangaVC = prebuilt
            guard let mangaVC = mangaVC else { return }
            addChild(mangaVC)
            view.insertSubview(mangaVC.view, at: 0)
            mangaVC.view.frame = view.bounds
            mangaVC.didMove(toParent: self)

            // 清空预制标记
            prebuiltNextMangaVC = nil
            prebuiltNextIndex = nil
            updateProgressUI()
            return
        }

        if mangaVC == nil {
            let vc = MangaReaderViewController()
            vc.safeAreaTop = safeAreaTop
            vc.onToggleMenu = { [weak self] in self?.safeToggleMenu() }
            vc.onInteractionChanged = { [weak self] interacting in
                guard let self = self else { return }
                if interacting {
                    self.notifyUserInteractionStarted()
                } else {
                    self.notifyUserInteractionEnded()
                }
            }
            vc.onVisibleIndexChanged = { [weak self] idx in
                guard let self = self else { return }
                let total = Double(max(1, self.currentCache.contentSentences.count))
                self.onProgressChanged?(self.currentChapterIndex, Double(idx) / total)
                self.updateProgressUI()
            }
            vc.onChapterSwitched = { [weak self] offset in
                guard let self = self else { return }
                let now = Date().timeIntervalSince1970
                guard now - self.lastChapterSwitchTime > self.chapterSwitchCooldown else { return }
                self.lastChapterSwitchTime = now
                self.requestChapterSwitch(offset: offset, preferSeamless: false, startAtEnd: offset < 0)
            }
            vc.threshold = verticalThreshold
            vc.dampingFactor = readerSettings.verticalDampingFactor
            vc.maxZoomScale = readerSettings.mangaMaxZoom
            vc.progressFontSize = readerSettings.progressFontSize
            addChild(vc); view.insertSubview(vc.view, at: 0); vc.view.frame = view.bounds; vc.didMove(toParent: self)
            self.mangaVC = vc
        }
        mangaVC?.bookUrl = book.bookUrl
        mangaVC?.chapterIndex = chapters.indices.contains(currentChapterIndex) ? chapters[currentChapterIndex].index : currentChapterIndex
        mangaVC?.chapterUrl = chapters.indices.contains(currentChapterIndex) ? chapters[currentChapterIndex].url : nil
        mangaVC?.update(urls: currentCache.contentSentences)
        updateProgressUI()
    }
}
