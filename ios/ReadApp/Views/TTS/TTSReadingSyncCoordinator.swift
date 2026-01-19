import Combine
import Foundation
import UIKit

final class TTSReadingSyncCoordinator {
    private weak var reader: ReaderContainerViewController?
    private let ttsManager: TTSManager
    private var cancellables: Set<AnyCancellable> = []
    private var interactionWorkItem: DispatchWorkItem?
    private let syncTrigger = PassthroughSubject<Void, Never>()

    init(reader: ReaderContainerViewController, ttsManager: TTSManager) {
        self.reader = reader
        self.ttsManager = ttsManager
    }

    func start() {
        syncTrigger
            .debounce(for: .milliseconds(120), scheduler: RunLoop.main)
            .sink { [weak self] in
                self?.reader?.syncTTSState()
            }
            .store(in: &cancellables)

        ttsManager.$currentSentenceIndex
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.syncTrigger.send(())
            }
            .store(in: &cancellables)

        ttsManager.$isPlaying
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.syncTrigger.send(())
            }
            .store(in: &cancellables)

        ttsManager.$currentSentenceOffset
            .removeDuplicates()
            .throttle(for: .milliseconds(100), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] _ in
                self?.syncTrigger.send(())
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.syncTrigger.send(())
            }
            .store(in: &cancellables)
    }

    func stop() {
        cancellables.removeAll()
        interactionWorkItem?.cancel()
        interactionWorkItem = nil
    }

    func userInteractionStarted() {
        interactionWorkItem?.cancel()
        interactionWorkItem = nil
    }

    func scheduleCatchUp(delay: TimeInterval) {
        interactionWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self, let reader = self.reader else { return }
            reader.handleUserScrollCatchUp()
            reader.finalizeUserInteraction()
        }
        interactionWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }
}
