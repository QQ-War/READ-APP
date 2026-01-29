import UIKit

final class ReaderModeSwitchCoordinator {
    struct Context {
        let readerSettings: ReaderSettingsStore
        let currentReadingMode: () -> ReadingMode
        let setReadingMode: (_ mode: ReadingMode) -> Void
        let isMangaMode: Bool

        let verticalVC: () -> VerticalTextViewController?
        let newHorizontalVC: () -> HorizontalCollectionViewController?
        let horizontalVC: () -> UIPageViewController?

        let setVerticalVC: (_ vc: VerticalTextViewController?) -> Void
        let setNewHorizontalVC: (_ vc: HorizontalCollectionViewController?) -> Void
        let setHorizontalVC: (_ vc: UIPageViewController?) -> Void

        let removeView: (_ view: UIView?) -> Void

        let setupVerticalMode: () -> Void
        let setupNewHorizontalMode: () -> Void
        let setupHorizontalMode: () -> Void
        let setupMangaMode: () -> Void
        let updateNewHorizontalContent: () -> Void
        let updateVerticalAdjacent: () -> Void
        let updateProgressUI: () -> Void
    }

    func applyPreferredMode(context: Context) {
        if context.isMangaMode {
            context.removeView(context.verticalVC()?.view)
            context.setVerticalVC(nil)
            context.removeView(context.horizontalVC()?.view)
            context.setHorizontalVC(nil)
            context.removeView(context.newHorizontalVC()?.view)
            context.setNewHorizontalVC(nil)
            context.setupMangaMode()
            context.updateProgressUI()
            return
        }

        let modeToUse: ReadingMode
        if context.currentReadingMode() == .vertical {
            modeToUse = .vertical
        } else if context.readerSettings.pageTurningMode == .simulation {
            modeToUse = .horizontal
        } else {
            modeToUse = .newHorizontal
        }

        if context.currentReadingMode() != .vertical {
            context.setReadingMode(modeToUse)
        }

        if modeToUse == .vertical {
            if context.verticalVC() == nil {
                context.removeView(context.horizontalVC()?.view)
                context.setHorizontalVC(nil)
                context.removeView(context.newHorizontalVC()?.view)
                context.setNewHorizontalVC(nil)
                context.setupVerticalMode()
            } else {
                context.updateVerticalAdjacent()
            }
        } else if modeToUse == .newHorizontal {
            if context.newHorizontalVC() == nil {
                context.removeView(context.verticalVC()?.view)
                context.setVerticalVC(nil)
                context.removeView(context.horizontalVC()?.view)
                context.setHorizontalVC(nil)
                context.setupNewHorizontalMode()
            } else {
                context.removeView(context.horizontalVC()?.view)
                context.setHorizontalVC(nil)
                context.updateNewHorizontalContent()
            }
        } else {
            if context.horizontalVC() == nil {
                context.removeView(context.verticalVC()?.view)
                context.setVerticalVC(nil)
                context.removeView(context.newHorizontalVC()?.view)
                context.setNewHorizontalVC(nil)
                context.setupHorizontalMode()
            } else {
                context.removeView(context.newHorizontalVC()?.view)
                context.setNewHorizontalVC(nil)
            }
        }

        context.updateProgressUI()
    }
}
