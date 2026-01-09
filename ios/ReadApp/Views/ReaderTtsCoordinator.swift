import Combine
import Foundation

final class ReaderTtsCoordinator {
    private weak var reader: ReaderContainerViewController?
    private let ttsManager: TTSManager
    private var cancellables: Set<AnyCancellable> = []

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
    }
}
