import Foundation
import AVFoundation
import MediaPlayer
import UIKit

class TTSManager: NSObject, ObservableObject {
    static let shared = TTSManager()
    private let logger = LogManager.shared
    
    @Published var isPlaying = false
    @Published var isPaused = false
    @Published var isReady = false
    @Published var currentSentenceIndex = 0
    @Published var totalSentences = 0
    @Published var isLoading = false
    @Published var isReadingChapterTitle = false
    @Published var preloadedIndices: Set<Int> = []
    @Published var currentSentenceDuration: TimeInterval = 0
    @Published var currentSentenceOffset: Int = 0
    @Published var currentCharOffset: Int = 0  // 直接使用传入的 charOffset，不做二次计算
    var currentBaseSentenceIndex: Int = 0
    var hasChapterTitleInSentences = false
    
    private var audioPlayer: AVAudioPlayer?
    private let speechSynthesizer = AVSpeechSynthesizer()
    private enum PlaybackEngine {
        case none
        case httpAudio
        case systemSpeech
    }
    private var activePlaybackEngine: PlaybackEngine = .none
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
    var replaceRules: [ReplaceRule]?
    
    // Preload Cache
    private var audioCache: [Int: Data] = [: ]
    private var preloadQueue: [Int] = []
    private var isPreloading = false
    private let maxPreloadRetries = 3
    private let maxConcurrentDownloads = 6
    private let preloadStateQueue = DispatchQueue(label: "com.readapp.tts.preloadStateQueue")
    private var fallbackIndices: Set<Int> = []
    
    // Next Chapter Preload
    private var nextChapterSentences: [String] = []
    private var nextChapterCache: [Int: Data] = [: ]
    private var nextChapterFallbackIndices: Set<Int> = []
    
    private var allowChapterTitlePlayback = true
    private var offsetTimer: Timer?
    private var playbackStartOffset: Int = 0

    private func refreshStatusFlags() {
        let title = chapters.indices.contains(currentChapterIndex) ? chapters[currentChapterIndex].title : ""
        let hasTitle = allowChapterTitlePlayback && !sentences.isEmpty && sentences[0] == title
        self.hasChapterTitleInSentences = hasTitle
        self.isReadingChapterTitle = hasTitle && currentSentenceIndex == 0
    }
    
    // 后台保活
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var keepAlivePlayer: AVAudioPlayer?
    private var keepAliveWorkItem: DispatchWorkItem?
    private var isWaitingForHTTPAudio = false
    private var isAppInBackground = UIApplication.shared.applicationState != .active
    private let keepAliveDelay: TimeInterval = 0.6

    // MARK: - 预载状态封装
    private func cachedAudio(for index: Int) -> Data? {
        preloadStateQueue.sync { audioCache[index] }
    }

    private func cacheAudio(_ data: Data, for index: Int) {
        preloadStateQueue.sync { audioCache[index] = data }
    }

    private func removeCachedAudio(for index: Int) {
        preloadStateQueue.sync { _ = audioCache.removeValue(forKey: index) }
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

    private func isFallbackIndex(_ index: Int) -> Bool {
        preloadStateQueue.sync { fallbackIndices.contains(index) }
    }

    private func markFallbackIndex(_ index: Int) {
        preloadStateQueue.sync { fallbackIndices.insert(index) }
    }

    private func clearFallbackIndices() {
        preloadStateQueue.sync { fallbackIndices.removeAll() }
    }

    private func isNextChapterFallbackIndex(_ index: Int) -> Bool {
        preloadStateQueue.sync { nextChapterFallbackIndices.contains(index) }
    }

    private func markNextChapterFallbackIndex(_ index: Int) {
        preloadStateQueue.sync { nextChapterFallbackIndices.insert(index) }
    }

    private func clearNextChapterFallbackIndices() {
        preloadStateQueue.sync { nextChapterFallbackIndices.removeAll() }
    }

    private func moveNextChapterFallbackToCurrent() {
        preloadStateQueue.sync {
            fallbackIndices = nextChapterFallbackIndices
            nextChapterFallbackIndices.removeAll()
        }
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
            logger.log("音频会话配置完成", category: "TTS")
        } catch {
            logger.log("音频会话设置失败: \(error.localizedDescription)", category: "TTS错误")
        }
    }

    private func activateAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, options: [])
            try audioSession.setActive(true)
        } catch {
            logger.log("音频会话激活失败: \(error.localizedDescription)", category: "TTS错误")
        }
    }

    private func deactivateAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            logger.log("音频会话关闭失败: \(error.localizedDescription)", category: "TTS错误")
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
        NotificationCenter.default.addObserver(self, selector: #selector(handleAppDidEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleAppDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
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

    @objc private func handleAppDidEnterBackground() {
        isAppInBackground = true
        guard isPlaying else { return }
        saveCurrentProgress()
        UserPreferences.shared.flushTTSProgressNow()
        stopOffsetTimer()
        beginBackgroundTask()
        scheduleKeepAliveIfNeeded()
    }

    @objc private func handleAppDidBecomeActive() {
        isAppInBackground = false
        cancelKeepAliveSchedule()
        stopKeepAlive()
        endBackgroundTask()
        if activePlaybackEngine == .httpAudio, audioPlayer?.isPlaying == true, isPlaying, !isPaused {
            startOffsetTimer()
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
    
    func startReading(text: String, chapters: [BookChapter], currentIndex: Int, bookUrl: String, bookSourceUrl: String?, bookTitle: String, coverUrl: String?, onChapterChange: @escaping (Int) -> Void, processedSentences: [String]? = nil, textProcessor: ((String) -> String)? = nil, replaceRules: [ReplaceRule]? = nil, startAtSentenceIndex: Int? = nil, startAtSentenceOffset: Int? = nil, shouldSpeakChapterTitle: Bool = true) {
        self.chapters = chapters
        self.currentChapterIndex = currentIndex
        self.bookUrl = bookUrl
        self.bookSourceUrl = bookSourceUrl
        self.bookTitle = bookTitle
        self.bookCoverUrl = coverUrl
        self.onChapterChange = onChapterChange
        self.textProcessor = textProcessor
        self.replaceRules = replaceRules
        self.allowChapterTitlePlayback = shouldSpeakChapterTitle
        
        loadCoverArtwork()
        beginBackgroundTask()
        clearAudioCache()
        preloadedIndices.removeAll()
        updatePreloadQueue([])
        setIsPreloading(false)
        clearFallbackIndices()
        isReady = false
        clearNextChapterCache()
        nextChapterSentences.removeAll()
        clearNextChapterFallbackIndices()
        
        if let ps = processedSentences {
            sentences = ps
        } else {
            sentences = splitTextIntoSentences(text)
        }
        
        // 索引统一：只要允许播放标题，标题就强制占领 Index 0
        if shouldSpeakChapterTitle && currentIndex < chapters.count {
            let title = chapters[currentIndex].title
            if sentences.first != title {
                sentences.insert(title, at: 0)
            }
            isReadingChapterTitle = true
            hasChapterTitleInSentences = true
        } else {
            hasChapterTitleInSentences = false
            isReadingChapterTitle = false
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
        
        logger.log("开始朗读: \(bookTitle), 章节索引: \(currentIndex), 起始段落: \(currentSentenceIndex), 句内偏移: \(currentSentenceOffset)", category: "TTS")
        
        if currentIndex < chapters.count { updateNowPlayingInfo(chapterTitle: chapters[currentIndex].title) }
        isPlaying = true
        isPaused = false
        activateAudioSession()
        
        refreshStatusFlags()
        isReady = true
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
        if trimmed == ReadingTextProcessor.imagePlaceholder { return true }
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
        guard UIApplication.shared.applicationState != .active else { return }
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

    private func cancelKeepAliveSchedule() {
        keepAliveWorkItem?.cancel()
        keepAliveWorkItem = nil
    }

    private func scheduleKeepAliveIfNeeded() {
        cancelKeepAliveSchedule()
        guard isAppInBackground, isPlaying, !isPaused, isWaitingForHTTPAudio else { return }
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.isAppInBackground, self.isPlaying, !self.isPaused, self.isWaitingForHTTPAudio else { return }
            self.startKeepAlive()
        }
        keepAliveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + keepAliveDelay, execute: workItem)
    }

    private func beginBackgroundTask() {
        guard UIApplication.shared.applicationState != .active else { return }
        endBackgroundTask()
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
    
    private func sanitizedPreviewText(_ text: String, limit: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ")
        guard trimmed.count > limit else { return trimmed }
        let endIndex = trimmed.index(trimmed.startIndex, offsetBy: limit)
        return String(trimmed[..<endIndex]) + "…"
    }

    private func splitTextIntoSentences(_ text: String) -> [String] {
        let chunkLimit = UserPreferences.shared.ttsSentenceChunkLimit
        return ReadingTextProcessor.splitSentences(text, rules: self.replaceRules, chunkLimit: chunkLimit)
    }

    private func ttsId(for sentence: String, isChapterTitle: Bool = false) -> String? {
        let prefs = UserPreferences.shared
        var targetId = isChapterTitle ? (prefs.narrationTTSId.isEmpty ? prefs.selectedTTSId : prefs.narrationTTSId) : (prefs.narrationTTSId.isEmpty ? prefs.selectedTTSId : prefs.narrationTTSId)
        if !isChapterTitle && (sentence.contains("“") || sentence.contains("”") || sentence.contains("\"")) {
            targetId = prefs.dialogueTTSId.isEmpty ? targetId : prefs.dialogueTTSId
        }
        return targetId.isEmpty ? nil : targetId
    }

    private func speakNextSentence() {
        guard isPlaying else { return }
        stopOffsetTimer()
        isWaitingForHTTPAudio = false
        cancelKeepAliveSchedule()
        if currentSentenceIndex >= sentences.count { nextChapter(); return }
        let sentence = sentences[currentSentenceIndex]
        if isPunctuationOnly(sentence) { currentSentenceIndex += 1; speakNextSentence(); return }
        
        refreshStatusFlags()
        
        UserPreferences.shared.saveTTSProgress(bookUrl: bookUrl, chapterIndex: currentChapterIndex, sentenceIndex: currentSentenceIndex, sentenceOffset: currentSentenceOffset)
        let sentenceToSpeak: String
        if currentSentenceOffset > 0 {
            let idx = String.Index(utf16Offset: min(currentSentenceOffset, sentence.utf16.count), in: sentence)
            sentenceToSpeak = String(sentence[idx...])
        } else {
            sentenceToSpeak = sentence
        }
        logger.log("TTS play snapshot - chapter=\(currentChapterIndex) sentenceIdx=\(currentSentenceIndex) sentenceOffset=\(currentSentenceOffset) text=\(sanitizedPreviewText(sentenceToSpeak, limit: 120))", category: "TTS")
        
        if sentenceToSpeak.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            currentSentenceIndex += 1
            currentSentenceOffset = 0
            speakNextSentence()
            return
        }
        if UserPreferences.shared.useSystemTTS {
            speakWithSystemTTS(text: sentenceToSpeak)
            return
        }
        startPreloading()
        
        let targetIdx = currentSentenceIndex
        if let cachedData = cachedAudio(for: targetIdx) {
            isWaitingForHTTPAudio = false
            cancelKeepAliveSchedule()
            playAudioWithData(data: cachedData); return
        }
        if isFallbackIndex(targetIdx) {
            isWaitingForHTTPAudio = false
            cancelKeepAliveSchedule()
            speakWithSystemTTS(text: sentenceToSpeak)
            return
        }

        isWaitingForHTTPAudio = true
        scheduleKeepAliveIfNeeded()
        Task {
            if let data = await fetchAudioData(for: sentenceToSpeak, isChapterTitle: isReadingChapterTitle) {
                await MainActor.run {
                    self.isWaitingForHTTPAudio = false
                    self.cancelKeepAliveSchedule()
                    cacheAudio(data, for: targetIdx)
                    playAudioWithData(data: data)
                    startPreloading()
                    if currentChapterIndex < chapters.count {
                        updateNowPlayingInfo(chapterTitle: chapters[currentChapterIndex].title)
                    }
                }
            } else {
                markFallbackIndex(targetIdx)
                await MainActor.run {
                    self.isWaitingForHTTPAudio = false
                    self.cancelKeepAliveSchedule()
                    speakWithSystemTTS(text: sentenceToSpeak)
                }
            }
        }
    }
    
    private func speakWithSystemTTS(text: String) {
        isLoading = false
        isWaitingForHTTPAudio = false
        cancelKeepAliveSchedule()
        stopKeepAlive()
        stopHTTPPlaybackIfNeeded()
        playbackStartOffset = currentSentenceOffset
        activePlaybackEngine = .systemSpeech
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = preferredSystemVoice(for: text)
        let rate = Float(UserPreferences.shared.speechRate / 200.0)
        utterance.rate = max(AVSpeechUtteranceMinimumSpeechRate, min(AVSpeechUtteranceMaximumSpeechRate, rate))
        speechSynthesizer.speak(utterance)
    }

    private func stopHTTPPlaybackIfNeeded() {
        if let player = audioPlayer, player.isPlaying {
            player.stop()
        }
        audioPlayer = nil
        if activePlaybackEngine == .httpAudio {
            activePlaybackEngine = .none
        }
    }

    private func preferredSystemVoice(for text: String) -> AVSpeechSynthesisVoice? {
        let selectedId = UserPreferences.shared.systemVoiceId
        if !selectedId.isEmpty, let selected = AVSpeechSynthesisVoice(identifier: selectedId) {
            if textHasChinese(text), !selected.language.contains("zh") {
                return fallbackChineseVoice() ?? selected
            }
            return selected
        }
        if textHasChinese(text) {
            return fallbackChineseVoice()
        }
        return nil
    }

    private func fallbackChineseVoice() -> AVSpeechSynthesisVoice? {
        if let voice = AVSpeechSynthesisVoice(language: "zh-CN") { return voice }
        return AVSpeechSynthesisVoice.speechVoices().first { $0.language.contains("zh") }
    }

    private func textHasChinese(_ text: String) -> Bool {
        return text.range(of: "[\\u4e00-\\u9fff]", options: .regularExpression) != nil
    }
    
    private func startPreloading() {
        let count = UserPreferences.shared.ttsPreloadCount
        if count > 0 {
            let needed = (currentSentenceIndex+1..<min(currentSentenceIndex+1+count, sentences.count)).filter { cachedAudio(for: $0) == nil && !isFallbackIndex($0) }
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
                        if self.cachedAudio(for: i) != nil || self.isFallbackIndex(i) { continue }
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
        markFallbackIndex(index)
    }
    
    private func downloadAudio(at index: Int) async -> Bool {
        guard index < sentences.count else { return false }
        let sentence = sentences[index]
        if isPunctuationOnly(sentence) {
            _ = await MainActor.run { preloadedIndices.insert(index) }
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
            if speechSynthesizer.isSpeaking {
                speechSynthesizer.stopSpeaking(at: .immediate)
            }
            playbackStartOffset = currentSentenceOffset
            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.delegate = self
            audioPlayer?.volume = 1.0
            if audioPlayer?.play() == true {
                activePlaybackEngine = .httpAudio
                isWaitingForHTTPAudio = false
                cancelKeepAliveSchedule()
                stopKeepAlive()
                isLoading = false
                currentSentenceDuration = audioPlayer?.duration ?? 0
                startOffsetTimer()
                beginBackgroundTask()
            } else {
                isWaitingForHTTPAudio = false
                cancelKeepAliveSchedule()
                isLoading = false; currentSentenceIndex += 1; currentSentenceOffset = 0; speakNextSentence()
            }
        } catch {
            isWaitingForHTTPAudio = false
            cancelKeepAliveSchedule()
            isLoading = false; currentSentenceIndex += 1; currentSentenceOffset = 0; speakNextSentence()
        }
    }
    
    private func startOffsetTimer() {
        stopOffsetTimer()
        guard !isAppInBackground else { return }
        guard !UserPreferences.shared.useSystemTTS else { return }
        offsetTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            guard let self = self, let player = self.audioPlayer, player.isPlaying, player.duration > 0 else { return }
            guard !self.isAppInBackground else { return }
            let progress = player.currentTime / player.duration
            let sentenceLen = self.sentences.indices.contains(self.currentSentenceIndex) ? self.sentences[self.currentSentenceIndex].utf16.count : 0
            let remainingLen = max(0, sentenceLen - self.playbackStartOffset)
            let newOffset = self.playbackStartOffset + Int(Double(remainingLen) * progress)
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
            isWaitingForHTTPAudio = false
            cancelKeepAliveSchedule()
            stopOffsetTimer()
            if speechSynthesizer.isSpeaking || speechSynthesizer.isPaused {
                speechSynthesizer.pauseSpeaking(at: .immediate)
                activePlaybackEngine = .systemSpeech
            } else if let player = audioPlayer, player.isPlaying {
                player.pause()
                activePlaybackEngine = .httpAudio
            }
            stopKeepAlive()
            deactivateAudioSession()
            updatePlaybackRate()
        }
    }
    
    func resume() {
        if isPlaying && isPaused {
            isPaused = false
            activateAudioSession()
            if speechSynthesizer.isPaused {
                speechSynthesizer.continueSpeaking()
                activePlaybackEngine = .systemSpeech
            } else if activePlaybackEngine == .httpAudio, let player = audioPlayer {
                player.play()
                startOffsetTimer()
            } else {
                speakNextSentence()
            }
            updatePlaybackRate()
        } else if !isPlaying {
            isPlaying = true; isPaused = false
            activateAudioSession()
            speakNextSentence()
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
        let title = chapters[nextIdx].title
        
        Task {
            if let content = try? await APIService.shared.fetchChapterContent(bookUrl: bookUrl, bookSourceUrl: bookSourceUrl, index: nextIdx) {
                await MainActor.run {
                    var s = splitTextIntoSentences(content)
                    // 预加载时也执行相同的索引对齐逻辑
                    if !title.isEmpty {
                        if s.first != title {
                            s.insert(title, at: 0)
                        }
                    }
                    self.nextChapterSentences = s
                    
                    let count = min(max(UserPreferences.shared.ttsPreloadCount, 3), nextChapterSentences.count)
                    // 从 0 开始预加载（包含标题）
                    for i in 0..<count { preloadNextChapterAudio(at: i) }
                }
            }
        }
    }
    
    private func preloadNextChapterAudio(at index: Int) {
        if UserPreferences.shared.useSystemTTS || index >= nextChapterSentences.count || cachedNextChapterAudio(for: index) != nil || isNextChapterFallbackIndex(index) { return }
        let sentence = nextChapterSentences[index]
        Task {
            if let data = await fetchAudioData(for: sentence, isChapterTitle: false) {
                await MainActor.run { cacheNextChapterAudio(data, for: index) }
            } else {
                markNextChapterFallbackIndex(index)
            }
        }
    }
    
    func stop() {
        saveCurrentProgress()
        UserPreferences.shared.flushTTSProgressNow()
        isWaitingForHTTPAudio = false
        cancelKeepAliveSchedule()
        stopKeepAlive()
        audioPlayer?.stop()
        audioPlayer = nil
        if speechSynthesizer.isSpeaking || speechSynthesizer.isPaused {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        activePlaybackEngine = .none
        isPlaying = false; isPaused = false; isReady = false; currentSentenceIndex = 0; currentBaseSentenceIndex = 0; sentences = []
        currentSentenceOffset = 0
        isLoading = false; clearAudioCache(); updatePreloadQueue([]); setIsPreloading(false); clearNextChapterCache(); nextChapterSentences.removeAll()
        clearFallbackIndices(); clearNextChapterFallbackIndices()
        coverArtwork = nil; endBackgroundTask()
        deactivateAudioSession()
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
    
    func updateReadingPosition(to position: ReadingPosition, restartIfPlaying: Bool = true) {
        guard position.chapterIndex == currentChapterIndex, !sentences.isEmpty else { return }
        
        isReady = false
        // 使用通用的校准逻辑：如果 Index 0 是标题，正文进度需加 1
        var targetIndex = position.sentenceIndex
        let title = chapters.indices.contains(currentChapterIndex) ? chapters[currentChapterIndex].title : ""
        if allowChapterTitlePlayback && !sentences.isEmpty && sentences[0] == title {
            targetIndex += 1
        }
        
        targetIndex = max(0, min(targetIndex, sentences.count - 1))
        currentSentenceIndex = targetIndex
        let sentenceLength = sentences[targetIndex].utf16.count
        currentSentenceOffset = max(0, min(position.sentenceOffset, sentenceLength))
        currentCharOffset = position.charOffset
        
        UserPreferences.shared.saveTTSProgress(bookUrl: bookUrl, chapterIndex: currentChapterIndex, sentenceIndex: currentSentenceIndex, sentenceOffset: currentSentenceOffset)
        
        refreshStatusFlags()
        isReady = true
        
        guard restartIfPlaying && isPlaying else { return }
        audioPlayer?.stop()
        audioPlayer = nil
        if speechSynthesizer.isSpeaking || speechSynthesizer.isPaused { speechSynthesizer.stopSpeaking(at: .immediate) }
        speakNextSentence()
    }
    
    private func loadAndReadChapter() {
        audioPlayer?.stop(); audioPlayer = nil
        if speechSynthesizer.isSpeaking || speechSynthesizer.isPaused { speechSynthesizer.stopSpeaking(at: .immediate) }
        
        // 跨章时立即更新标题播放权限
        let title = chapters.indices.contains(currentChapterIndex) ? chapters[currentChapterIndex].title : ""
        self.allowChapterTitlePlayback = !title.isEmpty
        
        let processChapterContent: (String) -> Void = { [weak self] content in
            guard let self = self else { return }
            self.clearFallbackIndices()
            self.sentences = self.splitTextIntoSentences(content)
            self.currentSentenceIndex = 0
            self.currentSentenceOffset = 0
            
            if self.allowChapterTitlePlayback {
                if self.sentences.first != title {
                    self.sentences.insert(title, at: 0)
                }
            }
            
            self.refreshStatusFlags()
            self.totalSentences = self.sentences.count
            self.isPlaying = true
            self.isPaused = false
            self.isLoading = false
            
            if self.currentChapterIndex < self.chapters.count {
                self.updateNowPlayingInfo(chapterTitle: self.chapters[self.currentChapterIndex].title)
            }
            self.checkAndPreloadNextChapter(force: true)
            self.speakNextSentence()
        }

        if !nextChapterSentences.isEmpty {
            let s = nextChapterSentences
            preloadedIndices = moveNextChapterCacheToCurrent()
            moveNextChapterFallbackToCurrent()
            nextChapterSentences.removeAll()
            
            self.sentences = s
            self.currentSentenceIndex = 0
            self.currentSentenceOffset = 0
            
            // 确保标志位根据新章节内容校准
            self.refreshStatusFlags()
            
            self.totalSentences = self.sentences.count
            self.isPlaying = true
            self.isPaused = false
            self.isLoading = false
            
            if self.currentChapterIndex < self.chapters.count {
                self.updateNowPlayingInfo(chapterTitle: self.chapters[self.currentChapterIndex].title)
            }
            self.checkAndPreloadNextChapter(force: true)
            self.speakNextSentence()
            return
        }
        
        Task {
            if let content = try? await APIService.shared.fetchChapterContent(bookUrl: bookUrl, bookSourceUrl: bookSourceUrl, index: currentChapterIndex) {
                await MainActor.run {
                    processChapterContent(content)
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
        UserPreferences.shared.flushTTSProgressNow()
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
        UserPreferences.shared.flushTTSProgressNow()
        cancelKeepAliveSchedule()
        endBackgroundTask()
    }
}

extension TTSManager: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            guard self.isPlaying else { return }
            self.currentSentenceIndex += 1; self.currentSentenceOffset = 0; self.speakNextSentence()
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            let utteranceLength = max(0, utterance.speechString.utf16.count)
            let absoluteOffset = self.playbackStartOffset + characterRange.location
            let maxOffset = self.playbackStartOffset + utteranceLength
            self.currentSentenceOffset = min(max(self.playbackStartOffset, absoluteOffset), maxOffset)
        }
    }
}

extension TTSManager: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            guard self.isPlaying else { return }
            self.stopOffsetTimer()
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
