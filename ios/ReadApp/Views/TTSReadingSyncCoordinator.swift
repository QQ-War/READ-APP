import Combine
import Foundation

final class TTSReadingSyncCoordinator {
    private weak var reader: ReaderContainerViewController?
    private let ttsManager: TTSManager
    private var cancellables: Set<AnyCancellable> = []
    private var interactionWorkItem: DispatchWorkItem?
    private let catchUpDelay: TimeInterval = 1.5

    init(reader: ReaderContainerViewController, ttsManager: TTSManager) {
        self.reader = reader
        self.ttsManager = ttsManager
    }

    func start() {
        ttsManager.$currentSentenceIndex
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.reader?.syncTTSState()
            }
            .store(in: &cancellables)

        ttsManager.$isPlaying
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.reader?.syncTTSState()
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

    func scheduleCatchUp() {
        interactionWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self, let reader = self.reader else { return }
            reader.completePendingTTSPositionSync()
            reader.finalizeUserInteraction()
            reader.syncTTSState()
        }
        interactionWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + catchUpDelay, execute: workItem)
    }
}
