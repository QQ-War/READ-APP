import UIKit

extension ReaderContainerViewController {
    func prefetchAdjacentChapters(index: Int) {
        guard let builder = chapterBuilder else { return }
        prefetchCoordinator.prefetchAdjacent(
            book: book,
            chapters: chapters,
            index: index,
            contentType: isMangaMode ? 2 : 0,
            layoutSpec: currentLayoutSpec,
            builder: builder,
            nextCache: nextCache,
            prevCache: prevCache,
            isMangaMode: isMangaMode,
            onNextCache: { [weak self] (cache: ChapterCache) in
                guard let self = self else { return }
                Task { @MainActor in
                    guard self.currentChapterIndex == index else { return }
                    self.nextCache = cache
                    self.updateVerticalAdjacent()
                    if self.isMangaMode {
                        self.prefetchedMangaNextIndex = index + 1
                        self.prefetchedMangaNextContent = cache.rawContent
                        self.preparePrebuiltNextMangaVC(index: index + 1, cache: cache)
                    }
                }
            },
            onPrevCache: { [weak self] (cache: ChapterCache) in
                guard let self = self else { return }
                Task { @MainActor in
                    guard self.currentChapterIndex == index else { return }
                    self.prevCache = cache
                    self.updateVerticalAdjacent()
                }
            },
            onResetNext: { [weak self] in
                guard let self = self else { return }
                Task { @MainActor in self.resetMangaPrefetchedContent() }
            },
            onResetPrev: { [weak self] in
                guard let self = self else { return }
                Task { @MainActor in self.prevCache = .empty }
            }
        )
    }

    func prefetchNextChapterOnly(index: Int) {
        guard let builder = chapterBuilder else { return }
        prefetchCoordinator.prefetchNextOnly(
            book: book,
            chapters: chapters,
            index: index,
            contentType: 0,
            layoutSpec: currentLayoutSpec,
            builder: builder,
            nextCache: nextCache,
            isMangaMode: isMangaMode,
            onNextCache: { [weak self] (cache: ChapterCache) in
                guard let self = self else { return }
                Task { @MainActor in
                    guard self.currentChapterIndex == index else { return }
                    self.nextCache = cache
                    self.updateVerticalAdjacent()
                }
            },
            onResetNext: { [weak self] in
                guard let self = self else { return }
                Task { @MainActor in self.nextCache = .empty }
            }
        )
    }

    func prefetchPrevChapterOnly(index: Int) {
        guard let builder = chapterBuilder else { return }
        prefetchCoordinator.prefetchPrevOnly(
            book: book,
            chapters: chapters,
            index: index,
            contentType: 0,
            layoutSpec: currentLayoutSpec,
            builder: builder,
            prevCache: prevCache,
            isMangaMode: isMangaMode,
            onPrevCache: { [weak self] (cache: ChapterCache) in
                guard let self = self else { return }
                Task { @MainActor in
                    guard self.currentChapterIndex == index else { return }
                    self.prevCache = cache
                    self.updateVerticalAdjacent()
                }
            },
            onResetPrev: { [weak self] in
                guard let self = self else { return }
                Task { @MainActor in self.prevCache = .empty }
            }
        )
    }

    func resetMangaPrefetchedContent() {
        nextCache = .empty
        prefetchedMangaNextIndex = nil
        prefetchedMangaNextContent = nil
        prebuiltNextMangaVC?.view.removeFromSuperview()
        prebuiltNextMangaVC?.removeFromParent()
        prebuiltNextMangaVC = nil
        prebuiltNextIndex = nil
    }

    func consumePrefetchedMangaContent(for index: Int) -> String? {
        guard prefetchedMangaNextIndex == index else { return nil }
        let content = prefetchedMangaNextContent
        prefetchedMangaNextIndex = nil
        prefetchedMangaNextContent = nil
        return content
    }

    func preparePrebuiltNextMangaVC(index: Int, cache: ChapterCache) {
        guard isMangaMode else { return }

        // 如果已经预制过了，且索引一致，跳过
        if prebuiltNextIndex == index && prebuiltNextMangaVC != nil { return }

        let vc = MangaReaderViewController()
        vc.safeAreaTop = safeAreaTop
        vc.onToggleMenu = { [weak self] in self?.safeToggleMenu() }
        vc.onInteractionChanged = { [weak self] interacting in
            guard let self = self else { return }
            if interacting { self.notifyUserInteractionStarted() } else { self.notifyUserInteractionEnded() }
        }
        vc.onVisibleIndexChanged = { [weak self] idx in
            guard let self = self else { return }
            let total = Double(max(1, self.currentCache.contentSentences.count))
            self.onProgressChanged?(self.currentChapterIndex, Double(idx) / total)
        }
        vc.onChapterSwitched = { [weak self] offset in
            guard let self = self else { return }
            let now = Date().timeIntervalSince1970
            guard now - self.lastChapterSwitchTime > self.chapterSwitchCooldown else { return }
            let target = self.currentChapterIndex + offset
            guard target >= 0 && target < self.chapters.count else { return }
            self.lastChapterSwitchTime = now
            self.jumpToChapter(target, startAtEnd: offset < 0)
        }
        vc.threshold = verticalThreshold
        vc.dampingFactor = readerSettings.verticalDampingFactor
        vc.maxZoomScale = readerSettings.mangaMaxZoom

        // 设置元数据并触发图片同步加载
        vc.bookUrl = book.bookUrl
        vc.chapterIndex = chapters.indices.contains(index) ? chapters[index].index : index
        vc.chapterUrl = chapters.indices.contains(index) ? chapters[index].url : nil

        // 关键：给预制视图一个初始尺寸，使其能完成布局
        vc.view.frame = view.bounds
        vc.update(urls: cache.contentSentences)

        self.prebuiltNextMangaVC = vc
        self.prebuiltNextIndex = index
    }
}
