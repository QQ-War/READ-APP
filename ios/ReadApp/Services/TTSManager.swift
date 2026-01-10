import Foundation
import AVFoundation
import MediaPlayer
import UIKit

class TTSManager: NSObject, ObservableObject {
    static let shared = TTSManager()
    private let logger = LogManager.shared
    
    @Published var isPlaying = false
    @Published var isPaused = false
    @Published var currentSentenceIndex = 0
    @Published var totalSentences = 0
    @Published var isLoading = false
    @Published var preloadedIndices: Set<Int> = []
    @Published var currentSentenceDuration: TimeInterval = 0
    @Published var currentSentenceOffset: Int = 0
    var currentBaseSentenceIndex: Int = 0
    
    private var audioPlayer: AVAudioPlayer?
    private let speechSynthesizer = AVSpeechSynthesizer()
    private var sentences: [String] = []
    var currentChapterIndex: Int = 0
    private var chapters: [BookChapter] = []
    var bookUrl: String = ""
    private var bookSourceUrl: String?
    private var bookTitle: String = ""
    private var bookCoverUrl: String?
    private var coverArtwork: MPMediaItemArtwork?
    private var onChapterChange: ((Int) -> Void)?
    private var textProcessor: ((String) -> String)?
    
    // Preload Cache
    private var audioCache: [Int: Data] = [:]
    private var preloadQueue: [Int] = []
    private var isPreloading = false
    private let maxPreloadRetries = 3
    private let maxConcurrentDownloads = 6
    private let preloadStateQueue = DispatchQueue(label: "com.readapp.tts.preloadStateQueue")
    
    // Next Chapter Preload
    private var nextChapterSentences: [String] = []
    private var nextChapterCache: [Int: Data] = [:]
    
    private var isReadingChapterTitle = false
    private var allowChapterTitlePlayback = true
    private var offsetTimer: Timer?
    
    // 后台保活
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var keepAlivePlayer: AVAudioPlayer?

    // MARK: - 预载状态封装
    private func cachedAudio(for index: Int) -> Data? {
        preloadStateQueue.sync { audioCache[index] }
    }

    private func cacheAudio(_ data: Data, for index: Int) {
        preloadStateQueue.sync { audioCache[index] = data }
    }

    private func removeCachedAudio(for index: Int) {
        preloadStateQueue.sync { audioCache.removeValue(forKey: index) }
    }

    private func clearAudioCache() {
        preloadStateQueue.sync { audioCache.removeAll() }
    }

    private func cachedNextChapterAudio(for index: Int) -> Data? {
        preloadStateQueue.sync { nextChapterCache[index] }
    }

    private func cacheNextChapterAudio(_ data: Data, for index: Int) {
        preloadStateQueue.sync { nextChapterCache[index] = data }
    }

    private func clearNextChapterCache() {
        preloadStateQueue.sync { nextChapterCache.removeAll() }
    }

    private func moveNextChapterCacheToCurrent() -> Set<Int> {
        preloadStateQueue.sync {
            let keys = Set(nextChapterCache.keys)
            audioCache = nextChapterCache
            nextChapterCache.removeAll()
            return keys
        }
    }

    private func updatePreloadQueue(_ indices: [Int]) {
        preloadStateQueue.sync { preloadQueue = indices }
    }

    private func dequeuePreloadQueue() -> [Int] {
        preloadStateQueue.sync {
            let indices = preloadQueue
            preloadQueue.removeAll()
            return indices
        }
    }

    private func hasPendingPreloadQueue() -> Bool {
        preloadStateQueue.sync { !preloadQueue.isEmpty }
    }

    private func setIsPreloading(_ value: Bool) {
        preloadStateQueue.sync { isPreloading = value }
    }

    private func getIsPreloading() -> Bool {
        preloadStateQueue.sync { isPreloading }
    }

    private func validateAudioData(_ data: Data, response: URLResponse) -> Bool {
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            return false
        }
        let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "unknown"
        guard contentType.contains("audio") else { return false }
        if (try? AVAudioPlayer(data: data)) != nil { return true }
        return data.count >= 2000
    }
    
    private override init() {
        super.init()
        logger.log("TTSManager 初始化", category: "TTS")
        speechSynthesizer.delegate = self
        setupAudioSession()
        setupRemoteCommands()
        setupNotifications()
    }
    
    private func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            logger.log("配置音频会话 - Category: playback, Mode: default", category: "TTS")
            try audioSession.setCategory(.playback, options: [])
            try audioSession.setActive(true)
            logger.log("音频会话配置成功", category: "TTS")
        } catch {
            logger.log("音频会话设置失败: \(error.localizedDescription)", category: "TTS错误")
        }
    }
    
    private func setupRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.resume()
            return .success
        }
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            self?.nextChapter()
            return .success
        }
        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            self?.previousChapter()
            return .success
        }
    }
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleAudioInterruption), name: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance())
        NotificationCenter.default.addObserver(self, selector: #selector(handleRouteChange), name: AVAudioSession.routeChangeNotification, object: AVAudioSession.sharedInstance())
    }
    
    @objc private func handleAudioInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        
        switch type {
        case .began:
            logger.log("音频中断开始", category: "TTS")
            if isPlaying && !isPaused { pause() }
        case .ended:
            guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else { return }
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if options.contains(.shouldResume) {
                logger.log("音频中断结束，尝试恢复播放", category: "TTS")
                try? AVAudioSession.sharedInstance().setActive(true)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    if self?.isPlaying == true && self?.isPaused == true { self?.resume() }
                }
            }
        @unknown default: break
        }
    }
    
    @objc private func handleRouteChange(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }
        if reason == .oldDeviceUnavailable {
            logger.log("音频设备断开，暂停播放", category: "TTS")
            if isPlaying && !isPaused { pause() }
        }
    }
    
    private func updateNowPlayingInfo(chapterTitle: String) {
        var nowPlayingInfo = [String: Any]()
        nowPlayingInfo[MPMediaItemPropertyTitle] = chapterTitle
        nowPlayingInfo[MPMediaItemPropertyArtist] = bookTitle
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = Double(currentSentenceIndex)
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying && !isPaused ? 1.0 : 0.0
        if totalSentences > 0 { nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = Double(totalSentences) }
        if let artwork = coverArtwork { nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
    
    private func loadCoverArtwork() {
        guard let coverUrlString = bookCoverUrl, !coverUrlString.isEmpty, coverArtwork == nil else { return }
        guard let url = URL(string: coverUrlString) else { return }
        Task {
            if let (data, _) = try? await URLSession.shared.data(from: url), let image = UIImage(data: data) {
                await MainActor.run {
                    self.coverArtwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                    if self.currentChapterIndex < self.chapters.count {
                        self.updateNowPlayingInfo(chapterTitle: self.chapters[self.currentChapterIndex].title)
                    }
                }
            }
        }
    }
    
    func startReading(text: String, chapters: [BookChapter], currentIndex: Int, bookUrl: String, bookSourceUrl: String?, bookTitle: String, coverUrl: String?, onChapterChange: @escaping (Int) -> Void, processedSentences: [String]? = nil, textProcessor: ((String) -> String)? = nil, startAtSentenceIndex: Int? = nil, startAtSentenceOffset: Int? = nil, shouldSpeakChapterTitle: Bool = true) {
        self.chapters = chapters
        self.currentChapterIndex = currentIndex
        self.bookUrl = bookUrl
        self.bookSourceUrl = bookSourceUrl
        self.bookTitle = bookTitle
        self.bookCoverUrl = coverUrl
        self.onChapterChange = onChapterChange
        self.textProcessor = textProcessor
        self.allowChapterTitlePlayback = shouldSpeakChapterTitle
        
        loadCoverArtwork()
        beginBackgroundTask()
        clearAudioCache()
        preloadedIndices.removeAll()
        updatePreloadQueue([])
        setIsPreloading(false)
        clearNextChapterCache()
        nextChapterSentences.removeAll()
        
        if let ps = processedSentences {
            sentences = ps
        } else {
            sentences = splitTextIntoSentences(text)
        }
        
        // 索引统一：将标题作为 sentences[0]
        if shouldSpeakChapterTitle && currentIndex < chapters.count {
            let title = chapters[currentIndex].title
            if !sentences.contains(title) {
                sentences.insert(title, at: 0)
                isReadingChapterTitle = true
            }
        }
        
        totalSentences = sentences.count
        currentSentenceOffset = 0
        
        if let externalIndex = startAtSentenceIndex, externalIndex < sentences.count {
            currentSentenceIndex = externalIndex
            if let offset = startAtSentenceOffset {
                currentSentenceOffset = min(max(0, offset), sentences[externalIndex].utf16.count)
            }
        } else if let progress = UserPreferences.shared.getTTSProgress(bookUrl: bookUrl),
                   progress.chapterIndex == currentIndex && progress.sentenceIndex < sentences.count {
            currentSentenceIndex = progress.sentenceIndex
            currentSentenceOffset = min(max(0, progress.sentenceOffset), sentences[currentSentenceIndex].utf16.count)
        } else {
            currentSentenceIndex = 0
            currentSentenceOffset = 0
        }
        
        logger.log("开始朗读: \(bookTitle), 章节索引: \(currentIndex), 起始段落: \(currentSentenceIndex)", category: "TTS")
        
        if currentIndex < chapters.count { updateNowPlayingInfo(chapterTitle: chapters[currentIndex].title) }
        isPlaying = true
        isPaused = false
        
        speakNextSentence()
    }

    
    func previousSentence() {
        if currentSentenceIndex > 0 {
            currentSentenceIndex -= 1
            audioPlayer?.stop()
            audioPlayer = nil
            currentSentenceOffset = 0
            UserPreferences.shared.saveTTSProgress(bookUrl: bookUrl, chapterIndex: currentChapterIndex, sentenceIndex: currentSentenceIndex, sentenceOffset: currentSentenceOffset)
            if isPlaying { speakNextSentence() }
        }
    }
    
    func nextSentence() {
        if currentSentenceIndex < sentences.count - 1 {
            currentSentenceIndex += 1
            audioPlayer?.stop()
            audioPlayer = nil
            currentSentenceOffset = 0
            UserPreferences.shared.saveTTSProgress(bookUrl: bookUrl, chapterIndex: currentChapterIndex, sentenceIndex: currentSentenceIndex, sentenceOffset: currentSentenceOffset)
            if isPlaying { speakNextSentence() }
        }
    }
    
    private func isPunctuationOnly(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        let punctuationSet = CharacterSet.punctuationCharacters.union(.symbols).union(.whitespacesAndNewlines)
        for scalar in trimmed.unicodeScalars { if !punctuationSet.contains(scalar) { return false } }
        return true
    }
    
    private func createSilentAudioUrl() -> URL? {
        let fileUrl = FileManager.default.temporaryDirectory.appendingPathComponent("silent_keep_alive.wav")
        if FileManager.default.fileExists(atPath: fileUrl.path) { return fileUrl }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false
        ]
        do {
            let audioFile = try AVAudioFile(forWriting: fileUrl, settings: settings)
            if let format = AVAudioFormat(settings: settings), let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44100) {
                buffer.frameLength = 44100
                try audioFile.write(from: buffer)
            }
            return fileUrl
        } catch { return nil }
    }
    
    private func startKeepAlive() {
        guard keepAlivePlayer == nil || !keepAlivePlayer!.isPlaying else { return }
        if let url = createSilentAudioUrl() {
            keepAlivePlayer = try? AVAudioPlayer(contentsOf: url)
            keepAlivePlayer?.numberOfLoops = -1
            keepAlivePlayer?.volume = 0.0
            keepAlivePlayer?.play()
        }
    }
    
    private func stopKeepAlive() {
        keepAlivePlayer?.stop()
        keepAlivePlayer = nil
    }

    private func beginBackgroundTask() {
        endBackgroundTask()
        startKeepAlive()
        backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in self?.endBackgroundTask() }
    }
    
    private func endBackgroundTask() {
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }
    
    private func removeSVGTags(_ text: String) -> String {
        var result = text
        let svgPattern = #"<svg[^>]*>.*?</svg>"#
        if let regex = try? NSRegularExpression(pattern: svgPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            result = regex.stringByReplacingMatches(in: result, options: [], range: NSRange(location: 0, length: result.utf16.count), withTemplate: "")
        }
        let imgPattern = "<img[^>]*>"
        if let regex = try? NSRegularExpression(pattern: imgPattern, options: [.caseInsensitive]) {
            result = regex.stringByReplacingMatches(in: result, options: [], range: NSRange(location: 0, length: result.utf16.count), withTemplate: "")
        }
        result = result.replacingOccurrences(of: #"__IMG__[^\s\n]+"#, with: "", options: .regularExpression)
        let htmlPattern = "<[^>]+>"
        if let regex = try? NSRegularExpression(pattern: htmlPattern, options: []) {
            result = regex.stringByReplacingMatches(in: result, options: [], range: NSRange(location: 0, length: result.utf16.count), withTemplate: "")
        }
        result = result.replacingOccurrences(of: "&nbsp;", with: " ").replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&quot;", with: "\"")
        return result
    }
    
    private func splitTextIntoSentences(_ text: String) -> [String] {
        let processed = textProcessor?(text) ?? removeSVGTags(text)
        return processed
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func ttsId(for sentence: String, isChapterTitle: Bool = false) -> String? {
        let prefs = UserPreferences.shared
        var targetId = isChapterTitle ? (prefs.narrationTTSId.isEmpty ? prefs.selectedTTSId : prefs.narrationTTSId) : (prefs.narrationTTSId.isEmpty ? prefs.selectedTTSId : prefs.narrationTTSId)
        if !isChapterTitle && (sentence.contains("“") || sentence.contains("”") || sentence.contains("\"")) {
            targetId = prefs.dialogueTTSId.isEmpty ? targetId : prefs.dialogueTTSId
        }
        return targetId.isEmpty ? nil : targetId
    }

    private func speakChapterTitle() {
        guard currentChapterIndex < chapters.count else { speakNextSentence(); return }
        let title = chapters[currentChapterIndex].title
        isReadingChapterTitle = true
        if UserPreferences.shared.useSystemTTS {
            speakWithSystemTTS(text: title)
            return
        }
        if let cachedData = cachedAudio(for: -1) {
            playAudioWithData(data: cachedData)
            startPreloading()
            return
        }
        startPreloading()
        Task {
                if let data = await fetchAudioData(for: title, isChapterTitle: true) {
                    await MainActor.run {
                        cacheAudio(data, for: -1)
                        playAudioWithData(data: data)
                        startPreloading()
                        if currentChapterIndex < chapters.count {
                            updateNowPlayingInfo(chapterTitle: chapters[currentChapterIndex].title)
                        }
                    }
                } else {
                await MainActor.run {
                    isReadingChapterTitle = false
                    speakNextSentence()
                }
            }
        }
    }
    
    private func speakNextSentence() {
        guard isPlaying else { return }
        stopOffsetTimer()
        if currentSentenceIndex >= sentences.count { nextChapter(); return }
        let sentence = sentences[currentSentenceIndex]
        if isPunctuationOnly(sentence) { currentSentenceIndex += 1; speakNextSentence(); return }
        
        // 更新是否正在读标题的状态
        if currentSentenceIndex == 0 && chapters.indices.contains(currentChapterIndex) && sentence == chapters[currentChapterIndex].title {
            isReadingChapterTitle = true
        } else {
            isReadingChapterTitle = false
        }
        
        UserPreferences.shared.saveTTSProgress(bookUrl: bookUrl, chapterIndex: currentChapterIndex, sentenceIndex: currentSentenceIndex, sentenceOffset: currentSentenceOffset)
        let sentenceToSpeak: String
        if currentSentenceOffset > 0 {
            let idx = String.Index(utf16Offset: min(currentSentenceOffset, sentence.utf16.count), in: sentence)
            sentenceToSpeak = String(sentence[idx...])
        } else {
            sentenceToSpeak = sentence
        }
        // 注意：不在这里重置 currentSentenceOffset，由播放器开始后通过 Timer 或 Delegate 更新
        
        if sentenceToSpeak.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            currentSentenceIndex += 1
            currentSentenceOffset = 0
            speakNextSentence()
            return
        }
        if UserPreferences.shared.useSystemTTS { speakWithSystemTTS(text: sentenceToSpeak); return }
        startPreloading()
        
        let targetIdx = isReadingChapterTitle ? -1 : currentSentenceIndex
        if let cachedData = cachedAudio(for: targetIdx) {
            playAudioWithData(data: cachedData); return
        }

        Task {
                if let data = await fetchAudioData(for: sentenceToSpeak, isChapterTitle: isReadingChapterTitle) {
                    await MainActor.run {
                        cacheAudio(data, for: targetIdx)
                        playAudioWithData(data: data)
                        startPreloading()
                        if currentChapterIndex < chapters.count {
                            updateNowPlayingInfo(chapterTitle: chapters[currentChapterIndex].title)
                        }
                    }
            } else {
                await MainActor.run { stop() }
            }
        }
    }

    func updateReadingPosition(to position: ReadingPosition, restartIfPlaying: Bool = true) {
        guard position.chapterIndex == currentChapterIndex, !sentences.isEmpty else { return }
        let targetIndex = max(0, min(position.sentenceIndex, sentences.count - 1))
        currentSentenceIndex = targetIndex
        let sentenceLength = sentences[targetIndex].utf16.count
        currentSentenceOffset = max(0, min(position.sentenceOffset, sentenceLength))
        UserPreferences.shared.saveTTSProgress(bookUrl: bookUrl, chapterIndex: currentChapterIndex, sentenceIndex: currentSentenceIndex, sentenceOffset: currentSentenceOffset)
        guard restartIfPlaying && isPlaying else { return }
        audioPlayer?.stop()
        audioPlayer = nil
        if UserPreferences.shared.useSystemTTS {
            if speechSynthesizer.isSpeaking { speechSynthesizer.stopSpeaking(at: .immediate) }
        }
        speakNextSentence()
    }
    
    private func speakWithSystemTTS(text: String) {
        isLoading = false
        stopKeepAlive()
        let utterance = AVSpeechUtterance(string: text)
        if !UserPreferences.shared.systemVoiceId.isEmpty {
            utterance.voice = AVSpeechSynthesisVoice(identifier: UserPreferences.shared.systemVoiceId)
        }
        let rate = Float(UserPreferences.shared.speechRate / 200.0)
        utterance.rate = max(AVSpeechUtteranceMinimumSpeechRate, min(AVSpeechUtteranceMaximumSpeechRate, rate))
        speechSynthesizer.speak(utterance)
    }
    
    private func startPreloading() {
        let count = UserPreferences.shared.ttsPreloadCount
        if count > 0 {
            let needed = (currentSentenceIndex+1..<min(currentSentenceIndex+1+count, sentences.count)).filter { cachedAudio(for: $0) == nil }
            if !needed.isEmpty { updatePreloadQueue(needed); processPreloadQueue() } else { checkAndPreloadNextChapter() }
        } else { checkAndPreloadNextChapter() }
    }
    
    private func processPreloadQueue() {
        guard !getIsPreloading() else { return }
        setIsPreloading(true)
        Task {
            await withTaskGroup(of: Void.self) {
                group in
                let queue = self.dequeuePreloadQueue()
                var active = 0
                var idx = 0
                while idx < queue.count || active > 0 {
                    if !self.getIsPreloading() { group.cancelAll(); break }
                    while active < self.maxConcurrentDownloads && idx < queue.count {
                        let i = queue[idx]; idx += 1
                        if self.cachedAudio(for: i) != nil { continue }
                        active += 1
                        group.addTask { await self.downloadAudioWithRetry(at: i) }
                    }
                    if active > 0 { await group.next(); active -= 1 }
                }
            }
            setIsPreloading(false)
            if hasPendingPreloadQueue() { processPreloadQueue() } else { await MainActor.run { self.checkAndPreloadNextChapter() } }
        }
    }
    
    private func downloadAudioWithRetry(at index: Int) async {
        for _ in 0...maxPreloadRetries {
            if !getIsPreloading() { return }
            if await downloadAudio(at: index) { return }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }
    
    private func downloadAudio(at index: Int) async -> Bool {
        guard index < sentences.count else { return false }
        let sentence = sentences[index]
        if isPunctuationOnly(sentence) {
            await MainActor.run { preloadedIndices.insert(index) }
            return true
        }
        guard let data = await fetchAudioData(for: sentence, isChapterTitle: false) else { return false }
        await MainActor.run {
            cacheAudio(data, for: index)
            preloadedIndices.insert(index)
        }
        return true
    }

    private func fetchAudioData(for sentence: String, isChapterTitle: Bool) async -> Data? {
        guard let id = ttsId(for: sentence, isChapterTitle: isChapterTitle) else { return nil }
        let speechRate = UserPreferences.shared.speechRate
        if APIClient.shared.backend == .reader {
            do {
                return try await APIService.shared.fetchReaderTtsAudio(ttsId: id, text: sentence, speechRate: speechRate)
            } catch {
                logger.log("Reader TTS 请求失败: \(error.localizedDescription)", category: "TTS")
                return nil
            }
        }
        guard let url = APIService.shared.buildTTSAudioURL(ttsId: id, text: sentence, speechRate: speechRate) else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard validateAudioData(data, response: response) else { return nil }
            return data
        } catch {
            logger.log("TTS音频下载失败: \(error.localizedDescription)", category: "TTS")
            return nil
        }
    }
    
    private func playAudioWithData(data: Data) {
        do {
            stopKeepAlive()
            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.delegate = self
            audioPlayer?.volume = 1.0
            if audioPlayer?.play() == true {
                isLoading = false
                currentSentenceDuration = audioPlayer?.duration ?? 0
                startOffsetTimer()
                beginBackgroundTask()
            } else {
                isLoading = false; currentSentenceIndex += 1; currentSentenceOffset = 0; speakNextSentence()
            }
        } catch {
            isLoading = false; currentSentenceIndex += 1; currentSentenceOffset = 0; speakNextSentence()
        }
    }
    
    private func startOffsetTimer() {
        stopOffsetTimer()
        guard !UserPreferences.shared.useSystemTTS else { return }
        offsetTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            guard let self = self, let player = self.audioPlayer, player.isPlaying, player.duration > 0 else { return }
            let progress = player.currentTime / player.duration
            let sentenceLen = self.sentences.indices.contains(self.currentSentenceIndex) ? self.sentences[self.currentSentenceIndex].utf16.count : 0
            let newOffset = Int(Double(sentenceLen) * progress)
            if abs(newOffset - self.currentSentenceOffset) > 2 {
                DispatchQueue.main.async { self.currentSentenceOffset = newOffset }
            }
        }
    }
    
    private func stopOffsetTimer() {
        offsetTimer?.invalidate()
        offsetTimer = nil
    }
    
    func pause() {
        if isPlaying && !isPaused {
            isPaused = true
            stopOffsetTimer()
            if UserPreferences.shared.useSystemTTS { speechSynthesizer.pauseSpeaking(at: .immediate) }
            else { audioPlayer?.pause() }
            startKeepAlive()
            updatePlaybackRate()
        }
    }
    
    func resume() {
        if isPlaying && isPaused {
            isPaused = false
            if UserPreferences.shared.useSystemTTS {
                if speechSynthesizer.isPaused { speechSynthesizer.continueSpeaking() }
                else { speakNextSentence() }
            } else {
                if let player = audioPlayer { 
                    player.play()
                    startOffsetTimer()
                }
                else { speakNextSentence() }
            }
            updatePlaybackRate()
        } else if !isPlaying {
            isPlaying = true; isPaused = false; speakNextSentence()
        }
    }
    
    private func checkAndPreloadNextChapter(force: Bool = false) {
        if UserPreferences.shared.useSystemTTS || !nextChapterSentences.isEmpty || currentChapterIndex >= chapters.count - 1 { return }
        let progress = Double(currentSentenceIndex) / Double(max(sentences.count, 1))
        let remaining = sentences.count - currentSentenceIndex
        if force || progress >= 0.5 || (remaining <= UserPreferences.shared.ttsPreloadCount) { preloadNextChapter() }
    }

    private func preloadNextChapter() {
        if UserPreferences.shared.useSystemTTS || !nextChapterSentences.isEmpty || currentChapterIndex >= chapters.count - 1 { return }
        let nextIdx = currentChapterIndex + 1
        preloadNextChapterTitle(chapterIndex: nextIdx)
        Task {
            if let content = try? await APIService.shared.fetchChapterContent(bookUrl: bookUrl, bookSourceUrl: bookSourceUrl, index: nextIdx) {
                await MainActor.run {
                    nextChapterSentences = splitTextIntoSentences(content)
                    let count = min(max(UserPreferences.shared.ttsPreloadCount, 3), nextChapterSentences.count)
                    for i in 0..<count { preloadNextChapterAudio(at: i) }
                }
            }
        }
    }
    
    private func preloadNextChapterTitle(chapterIndex: Int) {
        if UserPreferences.shared.useSystemTTS || chapterIndex >= chapters.count || nextChapterCache[-1] != nil { return }
        let title = chapters[chapterIndex].title
        guard let url = buildAudioURL(for: title, isChapterTitle: true) else { return }
        Task {
            if let (data, response) = try? await URLSession.shared.data(from: url), validateAudioData(data, response: response) {
                await MainActor.run { cacheNextChapterAudio(data, for: -1) }
            }
        }
    }
    
    private func preloadNextChapterAudio(at index: Int) {
        if UserPreferences.shared.useSystemTTS || index >= nextChapterSentences.count || cachedNextChapterAudio(for: index) != nil { return }
        let sentence = nextChapterSentences[index]
        guard let url = buildAudioURL(for: sentence) else { return }
        Task {
            if let (data, response) = try? await URLSession.shared.data(from: url), validateAudioData(data, response: response) {
                await MainActor.run { cacheNextChapterAudio(data, for: index) }
            }
        }
    }
    
    func stop() {
        saveCurrentProgress()
        stopKeepAlive()
        audioPlayer?.stop()
        audioPlayer = nil
        if speechSynthesizer.isSpeaking { speechSynthesizer.stopSpeaking(at: .immediate) }
        isPlaying = false; isPaused = false; currentSentenceIndex = 0; currentBaseSentenceIndex = 0; sentences = []
        currentSentenceOffset = 0
        isLoading = false; clearAudioCache(); updatePreloadQueue([]); setIsPreloading(false); clearNextChapterCache(); nextChapterSentences.removeAll()
        coverArtwork = nil; endBackgroundTask()
        logger.log("TTS 停止", category: "TTS")
    }
    
    func nextChapter() {
        guard currentChapterIndex < chapters.count - 1 else { return }
        currentChapterIndex += 1
        onChapterChange?(currentChapterIndex)
        loadAndReadChapter()
    }
    
    func previousChapter() {
        guard currentChapterIndex > 0 else { return }
        currentChapterIndex -= 1
        onChapterChange?(currentChapterIndex)
        loadAndReadChapter()
    }
    
    private func loadAndReadChapter() {
        audioPlayer?.stop(); audioPlayer = nil
        if speechSynthesizer.isSpeaking { speechSynthesizer.stopSpeaking(at: .immediate) }
        if !nextChapterSentences.isEmpty {
            sentences = nextChapterSentences; totalSentences = sentences.count; currentSentenceIndex = 0; currentSentenceOffset = 0
            preloadedIndices = moveNextChapterCacheToCurrent()
            nextChapterSentences.removeAll()
            isPlaying = true; isPaused = false; isLoading = false
            if currentChapterIndex < chapters.count { updateNowPlayingInfo(chapterTitle: chapters[currentChapterIndex].title) }
            checkAndPreloadNextChapter(force: true)
            allowChapterTitlePlayback = !chapters[currentChapterIndex].title.isEmpty
            if allowChapterTitlePlayback { speakChapterTitle() } else { speakNextSentence() }
            return
        }
        Task {
            if let content = try? await APIService.shared.fetchChapterContent(bookUrl: bookUrl, bookSourceUrl: bookSourceUrl, index: currentChapterIndex) {
                await MainActor.run {
                    sentences = splitTextIntoSentences(content); totalSentences = sentences.count; currentSentenceIndex = 0; currentSentenceOffset = 0
                    clearAudioCache(); updatePreloadQueue([]); setIsPreloading(false); preloadedIndices.removeAll()
                    isPlaying = true; isPaused = false
                    if currentChapterIndex < chapters.count { updateNowPlayingInfo(chapterTitle: chapters[currentChapterIndex].title) }
                    checkAndPreloadNextChapter(force: true)
                    allowChapterTitlePlayback = !chapters[currentChapterIndex].title.isEmpty
                    if allowChapterTitlePlayback { speakChapterTitle() } else { speakNextSentence() }
                }
            }
        }
    }
    
    private func updatePlaybackRate() {
        var nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [String: Any]()
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying && !isPaused ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
    
    private func saveCurrentProgress() {
        guard !bookUrl.isEmpty, isPlaying else { return }
        let snapshotBookUrl = self.bookUrl
        let snapshotChapterIdx = self.currentChapterIndex
        let snapshotSentences = self.sentences
        let snapshotSentenceIdx = self.currentSentenceIndex
        let snapshotBaseIdx = self.currentBaseSentenceIndex
        let snapshotOffset = self.currentSentenceOffset
        let snapshotTitle = snapshotChapterIdx < chapters.count ? chapters[snapshotChapterIdx].title : nil
        let absoluteSentenceIdx = snapshotSentenceIdx + snapshotBaseIdx
        UserPreferences.shared.saveTTSProgress(bookUrl: snapshotBookUrl, chapterIndex: snapshotChapterIdx, sentenceIndex: absoluteSentenceIdx, sentenceOffset: snapshotOffset)
        Task {
            guard !snapshotSentences.isEmpty else { return }
            var bodyIndex = 0
            for i in 0..<min(snapshotSentenceIdx, snapshotSentences.count) { bodyIndex += snapshotSentences[i].utf16.count + 1 }
            if snapshotSentenceIdx < snapshotSentences.count {
                let maxOffset = snapshotSentences[snapshotSentenceIdx].utf16.count
                bodyIndex += min(max(0, snapshotOffset), maxOffset)
            }
            let totalLen = snapshotSentences.reduce(0) { $0 + $1.utf16.count + 1 }
            let pos = totalLen > 0 ? Double(bodyIndex) / Double(totalLen) : 0.0
            UserPreferences.shared.saveReadingProgress(bookUrl: snapshotBookUrl, chapterIndex: snapshotChapterIdx, pageIndex: 0, bodyCharIndex: bodyIndex)
            try? await APIService.shared.saveBookProgress(bookUrl: snapshotBookUrl, index: snapshotChapterIdx, pos: pos, title: snapshotTitle)
            logger.log("TTS 进度快照已保存: \(snapshotBookUrl), 章节: \(snapshotChapterIdx), 比例: \(pos)", category: "TTS")
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        endBackgroundTask()
    }
}

extension TTSManager: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            guard self.isPlaying else { return }
            self.startKeepAlive()
            self.currentSentenceIndex += 1; self.currentSentenceOffset = 0; self.speakNextSentence()
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.currentSentenceOffset = characterRange.location
        }
    }
}

extension TTSManager: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            guard self.isPlaying else { return }
            self.stopOffsetTimer()
            self.startKeepAlive()
            self.currentSentenceIndex += 1; self.currentSentenceOffset = 0; self.speakNextSentence()
        }
    }
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        DispatchQueue.main.async {
            self.currentSentenceIndex += 1
            self.speakNextSentence()
        }
    }
}
