import UIKit

enum ReaderModeSwitchContextBuilder {
    static func makeContext(owner: ReaderContainerViewController) -> ReaderModeSwitchCoordinator.Context {
        ReaderModeSwitchCoordinator.Context(
            readerSettings: owner.readerSettings,
            currentReadingMode: { [weak owner] in owner?.currentReadingMode ?? .vertical },
            setReadingMode: { [weak owner] mode in owner?.currentReadingMode = mode },
            isMangaMode: owner.isMangaMode,
            verticalVC: { [weak owner] in owner?.verticalVC },
            newHorizontalVC: { [weak owner] in owner?.newHorizontalVC },
            horizontalVC: { [weak owner] in owner?.horizontalVC },
            setVerticalVC: { [weak owner] vc in owner?.verticalVC = vc },
            setNewHorizontalVC: { [weak owner] vc in owner?.newHorizontalVC = vc },
            setHorizontalVC: { [weak owner] vc in owner?.horizontalVC = vc },
            removeView: { view in view?.removeFromSuperview() },
            setupVerticalMode: { [weak owner] in owner?.setupVerticalMode() },
            setupNewHorizontalMode: { [weak owner] in owner?.setupNewHorizontalMode() },
            setupHorizontalMode: { [weak owner] in owner?.setupHorizontalMode() },
            setupMangaMode: { [weak owner] in owner?.setupMangaMode() },
            updateNewHorizontalContent: { [weak owner] in owner?.updateNewHorizontalContent() },
            updateVerticalAdjacent: { [weak owner] in owner?.updateVerticalAdjacent() },
            updateProgressUI: { [weak owner] in owner?.updateProgressUI() }
        )
    }
}
