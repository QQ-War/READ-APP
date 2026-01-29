import UIKit

final class ReaderTransitionCoordinator {
    struct State {
        var isTransitioning: () -> Bool
        var setTransitioning: (_ value: Bool) -> Void
        var transitionToken: () -> TimeInterval
        var setTransitionToken: (_ value: TimeInterval) -> Void
        var activeView: () -> UIView?
        var containerView: () -> UIView?
        var themeColor: () -> UIColor
    }

    struct Actions {
        var notifyInteractionEnd: () -> Void
    }

    private let state: State
    private let actions: Actions

    init(state: State, actions: Actions) {
        self.state = state
        self.actions = actions
    }

    func performTransition(mode: PageTurningMode, isNext: Bool, updates: @escaping () -> Void) {
        guard !state.isTransitioning() else { return }
        state.setTransitioning(true)
        state.setTransitionToken(Date().timeIntervalSince1970)
        let token = state.transitionToken()

        DispatchQueue.main.asyncAfter(deadline: .now() + ReaderConstants.Interaction.transitionGuardTimeout) { [weak self] in
            guard let self else { return }
            if self.state.isTransitioning(), self.state.transitionToken() == token {
                self.finalizeTransition()
            }
        }

        guard let containerView = state.containerView() ?? state.activeView(),
              let activeView = state.activeView() else {
            updates()
            finalizeTransition()
            return
        }

        if mode == .fade {
            performFade(containerView: containerView, activeView: activeView, updates: updates)
            return
        }

        let themeColor = state.themeColor()

        let oldSnapshot = activeView.snapshotView(afterScreenUpdates: false)
        oldSnapshot?.frame = activeView.frame
        oldSnapshot?.backgroundColor = themeColor
        if let snap = oldSnapshot { containerView.insertSubview(snap, aboveSubview: activeView) }

        updates()
        activeView.setNeedsLayout()
        activeView.layoutIfNeeded()

        if mode == .none {
            oldSnapshot?.removeFromSuperview()
            finalizeTransition()
            return
        }

        let newSnapshot = activeView.snapshotView(afterScreenUpdates: true)
        newSnapshot?.frame = activeView.frame
        newSnapshot?.backgroundColor = themeColor
        if let newSnap = newSnapshot, let oldSnap = oldSnapshot {
            containerView.insertSubview(newSnap, aboveSubview: oldSnap)
        }

        let width = activeView.bounds.width
        switch mode {
        case .scroll:
            newSnapshot?.transform = CGAffineTransform(translationX: isNext ? width : -width, y: 0)
            UIView.animate(withDuration: ReaderConstants.Animation.scrollTransitionDuration, delay: 0, options: .curveEaseInOut, animations: {
                oldSnapshot?.transform = CGAffineTransform(translationX: isNext ? -width : width, y: 0)
                newSnapshot?.transform = .identity
            }, completion: { _ in
                oldSnapshot?.removeFromSuperview()
                newSnapshot?.removeFromSuperview()
                self.finalizeTransition()
            })
        case .cover:
            newSnapshot?.transform = CGAffineTransform(translationX: isNext ? width : -width, y: 0)
            newSnapshot?.layer.shadowColor = UIColor.black.cgColor
            newSnapshot?.layer.shadowOpacity = ReaderConstants.Animation.coverShadowOpacity
            newSnapshot?.layer.shadowOffset = CGSize(width: isNext ? -ReaderConstants.Animation.coverShadowOffset : ReaderConstants.Animation.coverShadowOffset, height: 0)
            newSnapshot?.layer.shadowRadius = ReaderConstants.Animation.coverShadowRadius
            UIView.animate(withDuration: ReaderConstants.Animation.coverTransitionDuration, delay: 0, options: .curveEaseOut, animations: {
                newSnapshot?.transform = .identity
                oldSnapshot?.transform = CGAffineTransform(translationX: isNext ? -width * ReaderConstants.Animation.coverBackShiftFactor : width * ReaderConstants.Animation.coverBackShiftFactor, y: 0)
                oldSnapshot?.alpha = 0.7
            }, completion: { _ in
                oldSnapshot?.removeFromSuperview()
                newSnapshot?.removeFromSuperview()
                self.finalizeTransition()
            })
        case .fade, .simulation:
            newSnapshot?.alpha = 0
            UIView.animate(withDuration: ReaderConstants.Animation.fadeTransitionDuration, animations: {
                oldSnapshot?.alpha = 0
                newSnapshot?.alpha = 1
            }, completion: { _ in
                oldSnapshot?.removeFromSuperview()
                newSnapshot?.removeFromSuperview()
                self.finalizeTransition()
            })
        case .flip:
            newSnapshot?.isHidden = true
            UIView.transition(with: containerView, duration: ReaderConstants.Animation.modeTransitionDuration, options: isNext ? .transitionFlipFromRight : .transitionFlipFromLeft, animations: {
                oldSnapshot?.isHidden = true
                newSnapshot?.isHidden = false
            }) { _ in
                oldSnapshot?.removeFromSuperview()
                newSnapshot?.removeFromSuperview()
                self.finalizeTransition()
            }
        default:
            oldSnapshot?.removeFromSuperview()
            newSnapshot?.removeFromSuperview()
            finalizeTransition()
        }
    }

    private func performFade(containerView: UIView, activeView: UIView, updates: @escaping () -> Void) {
        let themeColor = state.themeColor()
        let oldSnapshot = activeView.snapshotView(afterScreenUpdates: false)
        oldSnapshot?.frame = activeView.frame
        oldSnapshot?.backgroundColor = themeColor
        if let snap = oldSnapshot { containerView.insertSubview(snap, aboveSubview: activeView) }

        updates()
        activeView.setNeedsLayout()
        activeView.layoutIfNeeded()

        let newSnapshot = activeView.snapshotView(afterScreenUpdates: true)
        newSnapshot?.frame = activeView.frame
        newSnapshot?.backgroundColor = themeColor
        if let newSnap = newSnapshot, let oldSnap = oldSnapshot {
            containerView.insertSubview(newSnap, aboveSubview: oldSnap)
        }

        newSnapshot?.alpha = 0
        UIView.animate(withDuration: ReaderConstants.Animation.fadeTransitionDuration, animations: {
            oldSnapshot?.alpha = 0
            newSnapshot?.alpha = 1
        }, completion: { _ in
            oldSnapshot?.removeFromSuperview()
            newSnapshot?.removeFromSuperview()
            self.finalizeTransition()
        })
    }

    private func finalizeTransition() {
        guard state.isTransitioning() else { return }
        state.setTransitioning(false)
        actions.notifyInteractionEnd()
    }
}
