import SwiftUI
import AVFoundation

final class AudioReadingViewModel: ObservableObject {
    @Published var chapters: [BookChapter] = []
    @Published var currentIndex: Int = 0
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isPlaying = false
    @Published var progress: Double = 0
    @Published var duration: Double = 0
    @Published var playbackRate: Double = 1.0

    private var timeObserver: Any?
    private var player: AVPlayer?
    private let book: Book
    private var currentAudioURL: URL?

    init(book: Book) {
        self.book = book
        self.currentIndex = book.durChapterIndex ?? 0
        setupAudioSession()
    }

    deinit {
        cleanupPlayer()
    }

    var currentTitle: String {
        chapters.indices.contains(currentIndex) ? chapters[currentIndex].title : "正在加载..."
    }

    func loadChapters() {
        Task { @MainActor in
            isLoading = true
            errorMessage = nil
        }
        Task {
            do {
                let list = try await APIService.shared.fetchChapterList(bookUrl: book.bookUrl ?? "", bookSourceUrl: book.origin)
                await MainActor.run {
                    self.chapters = list
                    if self.currentIndex >= list.count { self.currentIndex = max(0, list.count - 1) }
                }
                await loadChapter(at: currentIndex, autoPlay: false)
            } catch {
                await MainActor.run {
                    self.errorMessage = "获取目录失败: \(error.localizedDescription)"
                }
            }
            await MainActor.run { self.isLoading = false }
        }
    }

    func loadChapter(at index: Int, autoPlay: Bool) async {
        await MainActor.run { isLoading = true }
        defer { Task { @MainActor in self.isLoading = false } }
        do {
            let realIndex = chapters.indices.contains(index) ? chapters[index].index : index
            let content = try await APIService.shared.fetchChapterContent(
                bookUrl: book.bookUrl ?? "",
                bookSourceUrl: book.origin,
                index: realIndex,
                contentType: 1,
                cachePolicy: .standard
            )
            if let url = extractAudioURL(from: content) {
                await MainActor.run {
                    self.currentIndex = index
                    self.preparePlayer(url: url)
                    if autoPlay { self.play() }
                }
            } else {
                await MainActor.run {
                    self.errorMessage = "未找到音频地址"
                }
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "加载音频失败: \(error.localizedDescription)"
            }
        }
    }

    func playPause() {
        if isPlaying { pause() } else { play() }
    }

    func play() {
        player?.play()
        player?.rate = Float(playbackRate)
        isPlaying = true
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func setSpeed(_ rate: Double) {
        playbackRate = rate
        if isPlaying {
            player?.rate = Float(rate)
        }
    }

    func nextChapter() {
        let next = min(currentIndex + 1, max(0, chapters.count - 1))
        if next != currentIndex {
            Task { await loadChapter(at: next, autoPlay: true) }
        }
    }

    func previousChapter() {
        let prev = max(0, currentIndex - 1)
        if prev != currentIndex {
            Task { await loadChapter(at: prev, autoPlay: true) }
        }
    }

    func seek(to value: Double) {
        guard let player = player, duration > 0 else { return }
        let time = CMTime(seconds: value * duration, preferredTimescale: 600)
        player.seek(to: time)
    }

    private func setupAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.allowAirPlay])
        try? session.setActive(true)
    }

    private func preparePlayer(url: URL) {
        if currentAudioURL == url { return }
        cleanupPlayer()
        currentAudioURL = url
        let item = AVPlayerItem(url: url)
        let p = AVPlayer(playerItem: item)
        player = p
        observeTime(player: p)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerDidFinish),
            name: .AVPlayerItemDidPlayToEndTime,
            object: item
        )
    }

    @objc private func playerDidFinish() {
        isPlaying = false
    }

    private func observeTime(player: AVPlayer) {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            let current = CMTimeGetSeconds(time)
            let total = CMTimeGetSeconds(player.currentItem?.duration ?? .zero)
            self.duration = total.isFinite ? total : 0
            if self.duration > 0 {
                self.progress = max(0, min(1, current / self.duration))
            } else {
                self.progress = 0
            }
        }
    }

    private func cleanupPlayer() {
        if let observer = timeObserver, let player = player {
            player.removeTimeObserver(observer)
        }
        timeObserver = nil
        player?.pause()
        player = nil
        NotificationCenter.default.removeObserver(self)
        isPlaying = false
        progress = 0
        duration = 0
    }

    private func extractAudioURL(from content: String) -> URL? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), url.scheme?.hasPrefix("http") == true {
            return url
        }
        let pattern = "(https?:\\/\\/[^\\s\\\"'<>]+)"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []),
           let match = regex.firstMatch(in: content, options: [], range: NSRange(location: 0, length: (content as NSString).length)) {
            let urlString = (content as NSString).substring(with: match.range)
            return URL(string: urlString)
        }
        return nil
    }
}

struct AudioReadingView: View {
    let book: Book
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var bookshelfStore: BookshelfStore
    @StateObject private var viewModel: AudioReadingViewModel
    @State private var errorSheet: SelectableMessage?

    init(book: Book) {
        self.book = book
        _viewModel = StateObject(wrappedValue: AudioReadingViewModel(book: book))
    }

    var body: some View {
        NavigationView {
            ZStack {
                if let coverUrl = book.displayCoverUrl {
                    CachedRemoteImage(urlString: coverUrl) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Color.black.opacity(0.1)
                    }
                    .blur(radius: 20)
                    .opacity(0.25)
                    .ignoresSafeArea()
                }

                VStack(spacing: 16) {
                    VStack(spacing: 8) {
                        Text(book.name ?? "音频书籍")
                            .font(.headline)
                            .lineLimit(1)
                        Text(viewModel.currentTitle)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    if let coverUrl = book.displayCoverUrl {
                        CachedRemoteImage(urlString: coverUrl) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Color.gray.opacity(0.3)
                        }
                        .frame(width: 220, height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .shadow(radius: 8)
                    }

                    Slider(value: Binding(
                        get: { viewModel.progress },
                        set: { viewModel.seek(to: $0) }
                    ))

                    HStack(spacing: 24) {
                        Button(action: viewModel.previousChapter) {
                            Image(systemName: "backward.fill").font(.title2)
                        }
                        Button(action: viewModel.playPause) {
                            Image(systemName: viewModel.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 48))
                        }
                        Button(action: viewModel.nextChapter) {
                            Image(systemName: "forward.fill").font(.title2)
                        }
                    }
                    .padding(.vertical, 8)

                    HStack(spacing: 12) {
                        ForEach([0.8, 1.0, 1.25, 1.5, 2.0], id: \.self) { rate in
                            Button(action: { viewModel.setSpeed(rate) }) {
                                Text(String(format: "%.2gx", rate))
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(viewModel.playbackRate == rate ? Color.blue.opacity(0.2) : Color.gray.opacity(0.15))
                                    .cornerRadius(8)
                            }
                        }
                    }

                    Spacer()
                }
                .padding()
            }
            .navigationTitle("音频播放")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left")
                    }
                }
            }
            .overlay {
                if viewModel.isLoading {
                    ProgressView().padding().background(.ultraThinMaterial).cornerRadius(10)
                }
            }
        }
        .onAppear {
            viewModel.loadChapters()
        }
        .onChange(of: viewModel.currentIndex) { newValue in
            let pos = viewModel.progress
            bookshelfStore.updateProgress(bookUrl: book.bookUrl ?? "", index: newValue, pos: pos, title: viewModel.currentTitle)
        }
        .onChange(of: viewModel.errorMessage) { newValue in
            guard let message = newValue, !message.isEmpty else { return }
            errorSheet = SelectableMessage(title: "错误", message: message)
        }
        .sheet(item: $errorSheet) { sheet in
            SelectableMessageSheet(title: sheet.title, message: sheet.message) {
                viewModel.errorMessage = nil
                errorSheet = nil
            }
        }
    }
}
