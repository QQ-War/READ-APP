import Foundation

final class ReaderSeamlessSwitchCoordinator {
    struct State {
        var isInfiniteScrollEnabled: () -> Bool
        var pendingDirection: () -> Int
        var setPendingDirection: (_ value: Int) -> Void
        var nextAvailable: () -> Bool
        var prevAvailable: () -> Bool
        var currentTopY: () -> CGFloat
        var currentBottomY: () -> CGFloat
        var contentHeight: () -> CGFloat
        var viewportHeight: () -> CGFloat
    }

    struct Params {
        var triggerPadding: CGFloat
        var triggerMin: CGFloat
    }

    private let state: State
    private let params: Params

    init(state: State, params: Params) {
        self.state = state
        self.params = params
    }

    func handleAutoSwitch(rawOffset: CGFloat) {
        guard state.isInfiniteScrollEnabled() else { return }
        if state.pendingDirection() != 0 { return }

        if state.nextAvailable() {
            let maxOffsetY = max(0, state.contentHeight() - state.viewportHeight())
            let triggerThreshold = max(params.triggerMin, params.triggerPadding)
            if rawOffset > maxOffsetY - triggerThreshold {
                state.setPendingDirection(1)
                return
            }
        }

        if state.prevAvailable() {
            if rawOffset + state.viewportHeight() < state.currentTopY() - params.triggerPadding {
                state.setPendingDirection(-1)
            }
        }
    }

    func handleContentUpdate(rawOffset: CGFloat) {
        guard state.isInfiniteScrollEnabled() else { return }
        if state.pendingDirection() != 0 { return }

        if state.nextAvailable() {
            if rawOffset > state.currentBottomY() + params.triggerPadding {
                state.setPendingDirection(1)
            }
        }

        if state.pendingDirection() == 0 && state.prevAvailable() {
            if rawOffset + state.viewportHeight() < state.currentTopY() - params.triggerPadding {
                state.setPendingDirection(-1)
            }
        }
    }
}
