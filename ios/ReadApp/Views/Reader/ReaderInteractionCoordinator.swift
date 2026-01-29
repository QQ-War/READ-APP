import Foundation

final class ReaderInteractionCoordinator {
    struct State {
        var isTransitioning: () -> Bool
        var currentPageIndex: () -> Int
        var currentChapterIndex: () -> Int
        var totalChapters: () -> Int
        var pageCount: () -> Int
        var prevPageCount: () -> Int
        var hasPrevCache: () -> Bool
        var hasNextCache: () -> Bool
        var shouldAnimatePageTurn: () -> Bool
    }

    struct Actions {
        var notifyInteractionStart: () -> Void
        var notifyInteractionEnd: () -> Void
        var finalizeInteraction: () -> Void
        var updateHorizontalPage: (_ index: Int, _ animated: Bool) -> Void
        var animateToAdjacentChapter: (_ offset: Int, _ targetPage: Int, _ animated: Bool) -> Void
        var requestChapterSwitch: (_ targetChapterIndex: Int, _ startAtEnd: Bool) -> Void
    }

    private let state: State
    private let actions: Actions

    init(state: State, actions: Actions) {
        self.state = state
        self.actions = actions
    }

    func handlePageTap(isNext: Bool) {
        guard !state.isTransitioning() else {
            actions.finalizeInteraction()
            return
        }
        actions.notifyInteractionStart()
        let targetPage = isNext ? state.currentPageIndex() + 1 : state.currentPageIndex() - 1
        let offset = detectTargetChapterOffset(targetPage: targetPage, isNext: isNext)
        if offset == 0 {
            actions.updateHorizontalPage(targetPage, state.shouldAnimatePageTurn())
        } else {
            handleCrossChapter(offset: offset, animated: true)
        }
    }

    private func detectTargetChapterOffset(targetPage: Int, isNext: Bool) -> Int {
        if targetPage >= 0 && targetPage < state.pageCount() { return 0 }
        if isNext && state.currentChapterIndex() < state.totalChapters() - 1 { return 1 }
        if !isNext && state.currentChapterIndex() > 0 { return -1 }
        return 0
    }

    private func handleCrossChapter(offset: Int, animated: Bool) {
        let targetChapter = state.currentChapterIndex() + offset
        guard targetChapter >= 0 && targetChapter < state.totalChapters() else {
            actions.finalizeInteraction()
            return
        }
        if offset > 0 && state.hasNextCache() {
            actions.animateToAdjacentChapter(1, 0, animated)
        } else if offset < 0 && state.hasPrevCache() {
            actions.animateToAdjacentChapter(-1, max(0, state.prevPageCount() - 1), animated)
        } else {
            actions.requestChapterSwitch(targetChapter, offset < 0)
        }
    }
}
