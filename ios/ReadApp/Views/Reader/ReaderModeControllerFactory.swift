import UIKit

enum ReaderModeControllerFactory {
    static func makeNewHorizontalController(owner: ReaderContainerViewController) -> HorizontalCollectionViewController {
        let vc = HorizontalCollectionViewController()
        vc.delegate = owner
        vc.onAddReplaceRule = { [weak owner] text in
            owner?.onAddReplaceRuleWithText?(text)
        }
        vc.onImageTapped = { [weak owner] url in
            owner?.presentImagePreview(url: url)
        }
        return vc
    }

    static func makeHorizontalController(owner: ReaderContainerViewController, turningMode: PageTurningMode) -> UIPageViewController {
        let h = UIPageViewController(
            transitionStyle: turningMode == .simulation ? .pageCurl : .scroll,
            navigationOrientation: .horizontal,
            options: nil
        )
        h.dataSource = owner
        h.delegate = owner

        for view in h.view.subviews {
            if let scrollView = view as? UIScrollView {
                scrollView.delegate = owner
            }
        }
        for recognizer in h.gestureRecognizers where recognizer is UITapGestureRecognizer {
            recognizer.isEnabled = false
        }
        return h
    }

    static func makeVerticalController(owner: ReaderContainerViewController, settings: ReaderSettingsStore, threshold: CGFloat) -> VerticalTextViewController {
        let v = VerticalTextViewController()
        v.onVisibleIndexChanged = { [weak owner] idx in
            guard let owner = owner else { return }
            let count = max(1, owner.currentCache.contentSentences.count)
            owner.onProgressChanged?(owner.currentChapterIndex, Double(idx) / Double(count))
            owner.updateProgressUI()
        }
        v.onAddReplaceRule = { [weak owner] text in owner?.onAddReplaceRuleWithText?(text) }
        v.onTapMenu = { [weak owner] in owner?.safeToggleMenu() }
        v.isInfiniteScrollEnabled = settings.isInfiniteScrollEnabled
        v.onReachedBottom = { [weak owner] in
            guard let owner = owner else { return }
            owner.prefetchNextChapterOnly(index: owner.currentChapterIndex)
        }
        v.onReachedTop = { [weak owner] in
            guard let owner = owner else { return }
            owner.prefetchPrevChapterOnly(index: owner.currentChapterIndex)
        }
        v.onChapterSwitched = { [weak owner] offset in
            guard let owner = owner else { return }
            let now = Date().timeIntervalSince1970
            guard now - owner.lastChapterSwitchTime > owner.chapterSwitchCooldown else { return }
            owner.lastChapterSwitchTime = now
            owner.requestChapterSwitch(offset: offset, preferSeamless: owner.readerSettings.isInfiniteScrollEnabled, startAtEnd: offset < 0)
        }
        v.onInteractionChanged = { [weak owner] interacting in
            guard let owner = owner else { return }
            if interacting {
                owner.notifyUserInteractionStarted()
            } else {
                owner.notifyUserInteractionEnded()
            }
        }
        v.threshold = threshold
        v.seamlessSwitchThreshold = settings.infiniteScrollSwitchThreshold
        v.dampingFactor = settings.verticalDampingFactor
        v.onImageTapped = { [weak owner] url in
            owner?.presentImagePreview(url: url)
        }
        return v
    }

    static func makeMangaController(owner: ReaderContainerViewController, settings: ReaderSettingsStore, threshold: CGFloat) -> (UIViewController & MangaReadable) {
        let vc: (UIViewController & MangaReadable)
        switch settings.mangaReaderMode {
        case .legacy:
            vc = MangaLegacyReaderViewController()
        case .collection:
            vc = MangaReaderViewController()
        }
        vc.safeAreaTop = owner.safeAreaTop
        vc.onToggleMenu = { [weak owner] in owner?.safeToggleMenu() }
        vc.onInteractionChanged = { [weak owner] interacting in
            guard let owner = owner else { return }
            if interacting {
                owner.notifyUserInteractionStarted()
            } else {
                owner.notifyUserInteractionEnded()
            }
        }
        vc.onVisibleIndexChanged = { [weak owner] idx in
            guard let owner = owner else { return }
            let total = Double(max(1, owner.currentCache.contentSentences.count))
            owner.onProgressChanged?(owner.currentChapterIndex, Double(idx) / total)
            owner.updateProgressUI()
        }
        vc.onChapterSwitched = { [weak owner] offset in
            guard let owner = owner else { return }
            let now = Date().timeIntervalSince1970
            guard now - owner.lastChapterSwitchTime > owner.chapterSwitchCooldown else { return }
            owner.lastChapterSwitchTime = now
            owner.requestChapterSwitch(offset: offset, preferSeamless: false, startAtEnd: offset < 0)
        }
        vc.threshold = threshold
        vc.dampingFactor = settings.verticalDampingFactor
        vc.maxZoomScale = settings.mangaMaxZoom
        vc.prefetchCount = settings.mangaPrefetchCount
        vc.memoryCacheMB = settings.mangaMemoryCacheMB
        vc.recentKeepCount = settings.mangaRecentKeepCount
        vc.progressFontSize = settings.progressFontSize
        return vc
    }
}
