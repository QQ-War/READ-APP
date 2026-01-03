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
    @Published var preloadedIndices: Set<Int> = []  // Indices of successfully preloaded sentences
    @Published var currentSentenceDuration: TimeInterval = 0
    var currentBaseSentenceIndex: Int = 0
    
    private var audioPlayer: AVAudioPlayer?
    private let speechSynthesizer = AVSpeechSynthesizer()
    private var sentences: [String] = []
    var currentChapterIndex: Int = 0  // 鍏紑缁橰eadingView浣跨敤
    private var chapters: [BookChapter] = []
    var bookUrl: String = ""  // 鍏紑缁橰eadingView浣跨敤
    private var bookSourceUrl: String?
    private var bookTitle: String = ""
    private var bookCoverUrl: String?
    private var coverArtwork: MPMediaItemArtwork?
    private var onChapterChange: ((Int) -> Void)?
    private var currentSentenceObserver: Any?
    
    // Preload Cache
    private var audioCache: [Int: Data] = [:]  // Index -> audio data (index -1 for chapter title, 0~n for main text paragraphs)
    private var preloadQueue: [Int] = []       // Queue of indices waiting for preload
    private var isPreloading = false           // Whether a preload task is currently executing
    private let maxPreloadRetries = 3          // Maximum retry attempts
    private let maxConcurrentDownloads = 6     // Maximum concurrent downloads
    private let preloadStateQueue = DispatchQueue(label: "com.readapp.tts.preloadStateQueue")
    
    // Next Chapter Preload
    private var nextChapterSentences: [String] = []  // 涓嬩竴绔犵殑娈佃惤
    private var nextChapterCache: [Int: Data] = [:]  // 涓嬩竴绔犵殑闊抽缂撳瓨锛堢储寮?1涓虹珷鑺傚悕锛?
    
    // 绔犺妭鍚嶆湕璇?
    private var isReadingChapterTitle = false  // 鏄惁姝ｅ湪鏈楄绔犺妭鍚?
    private var allowChapterTitlePlayback = true
    
    // 鍚庡彴淇濇椿
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var keepAlivePlayer: AVAudioPlayer?

    // MARK: - 棰勮浇鐘舵€佸皝瑁咃紙涓茶闃熷垪闃茬珵鎬侊級
    private func cachedAudio(for index: Int) -> Data? {
        preloadStateQueue.sync { audioCache[index] }
    }

    private func cacheAudio(_ data: Data, for index: Int) {
        preloadStateQueue.sync { audioCache[index] = data }
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

        if (try? AVAudioPlayer(data: data)) != nil {
            return true
        }

        return data.count >= 2000
    }
    
    private override init() {
        super.init()
        logger.log("TTSManager 鍒濆鍖?", category: "TTS")
        speechSynthesizer.delegate = self
        setupAudioSession()
        setupRemoteCommands()
        setupNotifications()
    }
    
    // MARK: - 閰嶇疆闊抽浼氳瘽
    private func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            logger.log("閰嶇疆闊抽浼氳瘽 - Category: playback, Mode: default", category: "TTS")
            
            // 浣跨敤鏇寸畝鍗曠殑閰嶇疆锛屽厛璁剧疆category
            try audioSession.setCategory(.playback, options: [])
            
            // 鐒跺悗婵€娲讳細璇?
            try audioSession.setActive(true)
            
            logger.log("闊抽浼氳瘽閰嶇疆鎴愬姛", category: "TTS")
        } catch {
            logger.log("闊抽浼氳瘽璁剧疆澶辫触: \(error.localizedDescription)", category: "TTS閿欒")
            logger.log("閿欒璇︽儏: \(error)", category: "TTS閿欒")
        }
    }
    
    // MARK: - 璁剧疆杩滅▼鎺у埗
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
    
    // MARK: - 璁剧疆閫氱煡鐩戝惉
    private func setupNotifications() {
        // 鐩戝惉闊抽涓柇
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioInterruption),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
        
        // 鐩戝惉璺敱鍙樻洿锛堝鑰虫満鎷斿嚭锛?
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance()
        )
    }
    
    // MARK: - 澶勭悊闊抽涓柇
    @objc private func handleAudioInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        switch type {
        case .began:
            // 涓柇寮€濮嬶紙濡傛潵鐢点€侀椆閽熺瓑锛?
            logger.log("馃敂 闊抽涓柇寮€濮?", category: "TTS")
            if isPlaying && !isPaused {
                pause()
                logger.log("宸叉殏鍋滄挱鏀?", category: "TTS")
            }
            
        case .ended:
            // 涓柇缁撴潫
            guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else {
                logger.log("馃敂 闊抽涓柇缁撴潫锛堟棤鎭㈠閫夐」锛?", category: "TTS")
                return
            }
            
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if options.contains(.shouldResume) {
                // 绯荤粺寤鸿鎭㈠鎾斁
                logger.log("馃敂 闊抽涓柇缁撴潫锛岃嚜鍔ㄦ仮澶嶆挱鏀?", category: "TTS")
                
                // 閲嶆柊婵€娲婚煶棰戜細璇?
                do {
                    try AVAudioSession.sharedInstance().setActive(true)
                    logger.log("闊抽浼氳瘽閲嶆柊婵€娲?", category: "TTS")
                } catch {
                    logger.log("鉂?閲嶆柊婵€娲婚煶棰戜細璇濆け璐? \(error)", category: "TTS閿欒")
                }
                
                // 寤惰繜涓€鐐规仮澶嶏紝纭繚闊抽浼氳瘽绋冲畾
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    guard let self = self else { return }
                    if self.isPlaying && self.isPaused {
                        self.resume()
                        self.logger.log("鉁?鎾斁宸叉仮澶?", category: "TTS")
                    }
                }
            } else {
                logger.log("馃敂 闊抽涓柇缁撴潫锛堜笉寤鸿鑷姩鎭㈠锛?", category: "TTS")
            }
            
        @unknown default:
            logger.log("鈿狅笍 鏈煡鐨勯煶棰戜腑鏂被鍨?", category: "TTS")
        }
    }
    
    // MARK: - 澶勭悊闊抽璺敱鍙樻洿
    @objc private func handleRouteChange(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }
        
        switch reason {
        case .oldDeviceUnavailable:
            // 闊抽杈撳嚭璁惧鏂紑锛堝鑰虫満鎷斿嚭锛?
            logger.log("馃帶 闊抽璁惧鏂紑锛屾殏鍋滄挱鏀?", category: "TTS")
            if isPlaying && !isPaused {
                pause()
            }
            
        case .newDeviceAvailable:
            // 鏂扮殑闊抽杈撳嚭璁惧杩炴帴
            logger.log("馃帶 鏂伴煶棰戣澶囪繛鎺?", category: "TTS")
            
        default:
            logger.log("馃帶 闊抽璺敱鍙樻洿: \(reason.rawValue)", category: "TTS")
        }
    }
    
    // MARK: - 鏇存柊閿佸睆淇℃伅
    private func updateNowPlayingInfo(chapterTitle: String) {
        var nowPlayingInfo = [String: Any]()
        nowPlayingInfo[MPMediaItemPropertyTitle] = chapterTitle
        nowPlayingInfo[MPMediaItemPropertyArtist] = bookTitle
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = 0
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying && !isPaused ? 1.0 : 0.0
        
        if totalSentences > 0 {
            nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = Double(totalSentences)
            nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = Double(currentSentenceIndex)
        }
        
        // 娣诲姞灏侀潰鍥剧墖
        if let artwork = coverArtwork {
            nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
        }
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
    
    // MARK: - 鍔犺浇灏侀潰鍥剧墖
    private func loadCoverArtwork() {
        guard let coverUrlString = bookCoverUrl, !coverUrlString.isEmpty else {
            logger.log("鏈彁渚涘皝闈RL", category: "TTS")
            return
        }
        
        // 濡傛灉宸叉湁缂撳瓨锛岃烦杩?
        if coverArtwork != nil {
            return
        }
        
        guard let url = URL(string: coverUrlString) else {
            logger.log("灏侀潰URL鏃犳晥: \(coverUrlString)", category: "TTS閿欒")
            return
        }
        
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                
                if let image = UIImage(data: data) {
                    await MainActor.run {
                        // 鍒涘缓 MPMediaItemArtwork
                        let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in
                            return image
                        }
                        self.coverArtwork = artwork
                        
                        // 鏇存柊閿佸睆淇℃伅
                        if self.currentChapterIndex < self.chapters.count {
                            self.updateNowPlayingInfo(chapterTitle: self.chapters[self.currentChapterIndex].title)
                        }
                        
                        self.logger.log("鉁?灏侀潰鍔犺浇鎴愬姛", category: "TTS")
                    }
                } else {
                    logger.log("灏侀潰鍥剧墖瑙ｇ爜澶辫触", category: "TTS閿欒")
                }
            } catch {
                logger.log("灏侀潰涓嬭浇澶辫触: \(error.localizedDescription)", category: "TTS閿欒")
            }
        }
    }
    
    // MARK: - 寮€濮嬫湕璇?
    func startReading(text: String, chapters: [BookChapter], currentIndex: Int, bookUrl: String, bookSourceUrl: String?, bookTitle: String, coverUrl: String?, onChapterChange: @escaping (Int) -> Void, startAtSentenceIndex: Int? = nil, shouldSpeakChapterTitle: Bool = true) {
        logger.log("寮€濮嬫湕璇?- 涔﹀悕: \(bookTitle), 绔犺妭: \(currentIndex)/\(chapters.count)", category: "TTS")
        logger.log("鍐呭闀垮害: \(text.count) 瀛楃", category: "TTS")
        
        self.chapters = chapters
        self.currentChapterIndex = currentIndex
        self.bookUrl = bookUrl
        self.bookSourceUrl = bookSourceUrl
        self.bookTitle = bookTitle
        self.bookCoverUrl = coverUrl
        self.onChapterChange = onChapterChange
        self.allowChapterTitlePlayback = shouldSpeakChapterTitle
        
        // 鍔犺浇灏侀潰鍥剧墖
        loadCoverArtwork()
        
        // 寮€濮嬪悗鍙颁换鍔?
        beginBackgroundTask()
        
        // 娓呯┖缂撳瓨鍜岄杞界姸鎬?
        clearAudioCache()
        preloadedIndices.removeAll()
        updatePreloadQueue([])
        setIsPreloading(false)
        clearNextChapterCache()
        nextChapterSentences.removeAll()
        
        // 鍒嗗彞
        sentences = splitTextIntoSentences(text)
        totalSentences = sentences.count
        
        // 浼樺厛浣跨敤澶栭儴浼犲叆鐨勮捣濮嬬储寮曪紝鍏舵鏄湰鍦扮紦瀛橈紝鏈€鍚庢槸0
        if let externalIndex = startAtSentenceIndex, externalIndex < sentences.count {
            currentSentenceIndex = externalIndex
            logger.log("浠庢湇鍔″櫒鎭㈠TTS杩涘害 - 绔犺妭: \(currentIndex), 娈佃惤: \(currentSentenceIndex)", category: "TTS")
        } else if let progress = UserPreferences.shared.getTTSProgress(bookUrl: bookUrl),
                  progress.chapterIndex == currentIndex && progress.sentenceIndex < sentences.count {
            currentSentenceIndex = progress.sentenceIndex
            logger.log("浠庢湰鍦版仮澶峊TS杩涘害 - 绔犺妭: \(currentIndex), 娈佃惤: \(currentSentenceIndex)", category: "TTS")
        } else {
            currentSentenceIndex = 0
        }
        
        logger.log("鍒嗗彞瀹屾垚 - 鍏?\(totalSentences) 鍙? 浠庣 \(currentSentenceIndex + 1) 鍙ュ紑濮?", category: "TTS")
        
        // 鏇存柊閿佸睆淇℃伅
        if currentIndex < chapters.count {
            updateNowPlayingInfo(chapterTitle: chapters[currentIndex].title)
        }
        
        isPlaying = true
        isPaused = false
        
        // 濡傛灉浠庡ご寮€濮嬫挱鏀撅紝鍏堟湕璇荤珷鑺傚悕
        if currentSentenceIndex == 0 && allowChapterTitlePlayback {
            speakChapterTitle()
        } else {
            speakNextSentence()
        }
    }
    
    // MARK: - 涓婁竴娈?
    func previousSentence() {
        if currentSentenceIndex > 0 {
            currentSentenceIndex -= 1
            audioPlayer?.stop()
            audioPlayer = nil
            
            // 淇濆瓨杩涘害
            UserPreferences.shared.saveTTSProgress(bookUrl: bookUrl, chapterIndex: currentChapterIndex, sentenceIndex: currentSentenceIndex)
            
            if isPlaying {
                speakNextSentence()
            }
        }
    }
    
    // MARK: - 涓嬩竴娈?
    func nextSentence() {
        if currentSentenceIndex < sentences.count - 1 {
            currentSentenceIndex += 1
            audioPlayer?.stop()
            audioPlayer = nil
            
            // 淇濆瓨杩涘害
            UserPreferences.shared.saveTTSProgress(bookUrl: bookUrl, chapterIndex: currentChapterIndex, sentenceIndex: currentSentenceIndex)
            
            if isPlaying {
                speakNextSentence()
            }
        }
    }
    
    // MARK: - 鍒ゆ柇鏄惁涓虹函鏍囩偣鎴栫┖鐧?
    private func isPunctuationOnly(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return true
        }
        
        // 瀹氫箟鏍囩偣绗﹀彿闆嗗悎
        let punctuationSet = CharacterSet.punctuationCharacters
            .union(.symbols)
            .union(.whitespacesAndNewlines)
        
        // 妫€鏌ユ槸鍚︽墍鏈夊瓧绗﹂兘鏄爣鐐广€佺鍙锋垨绌虹櫧
        for scalar in trimmed.unicodeScalars {
            if !punctuationSet.contains(scalar) {
                return false
            }
        }
        
        return true
    }
    
    // MARK: - 婵€杩涗繚娲?(Silent Audio)
    private func createSilentAudioUrl() -> URL? {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory
        let fileUrl = tempDir.appendingPathComponent("silent_keep_alive.wav")
        
        if fileManager.fileExists(atPath: fileUrl.path) {
            return fileUrl
        }
        
        // 44.1 kHz, 1 channel, 16-bit PCM
        let sampleRate: Double = 44100.0
        let duration: Double = 1.0
        let frameCount = Int(sampleRate * duration)
        
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false
        ]
        
        do {
            let audioFile = try AVAudioFile(forWriting: fileUrl, settings: settings)
            if let format = AVAudioFormat(settings: settings),
               let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) {
                buffer.frameLength = AVAudioFrameCount(frameCount)
                // buffer 榛樿涓洪潤闊?0)
                try audioFile.write(from: buffer)
            }
            return fileUrl
        } catch {
            logger.log("鍒涘缓闈欓煶鏂囦欢澶辫触: \(error)", category: "TTS閿欒")
            return nil
        }
    }
    
    private func startKeepAlive() {
        guard keepAlivePlayer == nil || !keepAlivePlayer!.isPlaying else { return }
        
        logger.log("馃洝锔?鍚姩婵€杩涗繚娲?闈欓煶鎾斁)", category: "TTS")
        
        if let url = createSilentAudioUrl() {
            do {
                keepAlivePlayer = try AVAudioPlayer(contentsOf: url)
                keepAlivePlayer?.numberOfLoops = -1 // 鏃犻檺寰幆
                keepAlivePlayer?.volume = 0.0 // 闈欓煶
                keepAlivePlayer?.prepareToPlay()
                keepAlivePlayer?.play()
            } catch {
                logger.log("鉂?鍚姩淇濇椿澶辫触: \(error)", category: "TTS閿欒")
            }
        }
    }
    
    private func stopKeepAlive() {
        if keepAlivePlayer != nil {
            logger.log("馃洃 鍋滄婵€杩涗繚娲?", category: "TTS")
            keepAlivePlayer?.stop()
            keepAlivePlayer = nil
        }
    }

    // MARK: - 寮€濮嬪悗鍙颁换鍔?
    private func beginBackgroundTask() {
        endBackgroundTask()  // 鍏堢粨鏉熶箣鍓嶇殑浠诲姟
        
        // 鍚姩闈欓煶淇濇椿
        startKeepAlive()
        
        backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.logger.log("鈿狅笍 鍚庡彴浠诲姟鍗冲皢杩囨湡", category: "TTS")
            self?.endBackgroundTask()
        }
        
        if backgroundTask != .invalid {
            logger.log("鉁?鍚庡彴浠诲姟宸插紑濮? \(backgroundTask.rawValue)", category: "TTS")
        }
    }
    
    // MARK: - 缁撴潫鍚庡彴浠诲姟
    private func endBackgroundTask() {
        if backgroundTask != .invalid {
            logger.log("缁撴潫鍚庡彴浠诲姟: \(backgroundTask.rawValue)", category: "TTS")
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }
    
    // MARK: - 杩囨护SVG鏍囩
    private func removeSVGTags(_ text: String) -> String {
        var result = text
        
        // 绉婚櫎SVG鏍囩锛堝寘鎷琛孲VG锛?
        let svgPattern = "<svg[^>]*>.*?</svg>"
        if let svgRegex = try? NSRegularExpression(pattern: svgPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            let range = NSRange(location: 0, length: result.utf16.count)
            result = svgRegex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
        }
        
        // 鍙Щ闄ゅ父瑙佺殑HTML鏍囩锛屼繚鐣欐枃鏈唴瀹?
        // 鍏堢Щ闄mg鏍囩
        let imgPattern = "<img[^>]*>"
        if let imgRegex = try? NSRegularExpression(pattern: imgPattern, options: [.caseInsensitive]) {
            let range = NSRange(location: 0, length: result.utf16.count)
            result = imgRegex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
        }
        
        // 绉婚櫎鍏朵粬鏍囩浣嗕繚鐣欏唴瀹?
        let htmlPattern = "<[^>]+>"
        if let htmlRegex = try? NSRegularExpression(pattern: htmlPattern, options: []) {
            let range = NSRange(location: 0, length: result.utf16.count)
            result = htmlRegex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
        }
        
        // 娓呯悊HTML瀹炰綋
        result = result.replacingOccurrences(of: "&nbsp;", with: " ")
        result = result.replacingOccurrences(of: "&lt;", with: "<")
        result = result.replacingOccurrences(of: "&gt;", with: ">")
        result = result.replacingOccurrences(of: "&amp;", with: "&")
        result = result.replacingOccurrences(of: "&quot;", with: "\"")
        
        logger.log("鍘熷鏂囨湰闀垮害: \(text.count), 杩囨护鍚? \(result.count)", category: "TTS")
        return result
    }
    
    // MARK: - 鏅鸿兘鍒嗘锛堜紭鍖栫増锛?
    private func splitTextIntoSentences(_ text: String) -> [String] {
        // 鍏堣繃婊VG鍜孒TML鏍囩
        let filtered = removeSVGTags(text)
        
        // 鎸夋崲琛岀鍒嗗壊锛屼繚鎸佸師鏂囧垎娈?
        let paragraphs = filtered.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }  // 绉婚櫎姣忔鐨勫墠鍚庣┖鐧?
            .filter { !$0.isEmpty }  // 杩囨护绌烘钀?
        
        return paragraphs
    }

    // MARK: - TTS 閫夋嫨閫昏緫
    private func resolvedNarrationTTSId() -> String {
        let prefs = UserPreferences.shared
        if !prefs.narrationTTSId.isEmpty { return prefs.narrationTTSId }
        return prefs.selectedTTSId
    }

    private func resolvedDialogueTTSId() -> String {
        let prefs = UserPreferences.shared
        if !prefs.dialogueTTSId.isEmpty { return prefs.dialogueTTSId }
        return resolvedNarrationTTSId()
    }

    private func isDialogueSentence(_ sentence: String) -> Bool {
        // 绮楃暐鍒ゆ柇锛氬寘鍚腑鏂?鑻辨枃寮曞彿鏃惰涓烘槸瀵硅瘽
        return sentence.contains("“") || sentence.contains("”") || sentence.contains("\"")
    }

    private func extractSpeaker(from sentence: String) -> String? {
        // 鍖归厤鈥滃紶涓夛細鈥濇垨鈥滃紶涓夎锛氣€濈瓑鏍煎紡
        let pattern = "^\\s*([\\p{Han}A-Za-z0-9_路]{1,12})[\\s銆€]*[锛?锛?]?\\s*[\"鈥淽"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(location: 0, length: sentence.utf16.count)
        if let match = regex.firstMatch(in: sentence, options: [], range: range),
           let nameRange = Range(match.range(at: 1), in: sentence) {
            let name = sentence[nameRange].trimmingCharacters(in: .whitespaces)
            return name
        }
        return nil
    }

    private func ttsId(for sentence: String, isChapterTitle: Bool = false) -> String? {
        let prefs = UserPreferences.shared

        if isChapterTitle {
            let narrationId = resolvedNarrationTTSId()
            return narrationId.isEmpty ? nil : narrationId
        }

        var targetId = resolvedNarrationTTSId()

        if isDialogueSentence(sentence) {
            let speakerName = extractSpeaker(from: sentence)
            if let speaker = speakerName,
               let mappedId = prefs.speakerTTSMapping[speaker] ?? prefs.speakerTTSMapping[speaker.replacingOccurrences(of: " ", with: "")] {
                targetId = mappedId
            } else {
                targetId = resolvedDialogueTTSId()
            }
        }

        if targetId.isEmpty { targetId = prefs.selectedTTSId }
        return targetId.isEmpty ? nil : targetId
    }

    private func buildAudioURL(for sentence: String, isChapterTitle: Bool = false) -> URL? {
        guard let ttsId = ttsId(for: sentence, isChapterTitle: isChapterTitle) else { return nil }
        let speechRate = UserPreferences.shared.speechRate
        return APIService.shared.buildTTSAudioURL(ttsId: ttsId, text: sentence, speechRate: speechRate)
    }
    
    // MARK: - 鏈楄绔犺妭鍚?
    private func speakChapterTitle() {
        guard currentChapterIndex < chapters.count else {
            speakNextSentence()
            return
        }
        
        let chapterTitle = chapters[currentChapterIndex].title
        logger.log("寮€濮嬫湕璇荤珷鑺傚悕: \(chapterTitle)", category: "TTS")
        
        isReadingChapterTitle = true
        
        // 绯荤粺 TTS 鍒ゆ柇
        if UserPreferences.shared.useSystemTTS {
            speakWithSystemTTS(text: chapterTitle)
            return
        }
        
        guard let audioURL = buildAudioURL(for: chapterTitle, isChapterTitle: true) else {
            logger.log("鏈€夋嫨 TTS 寮曟搸锛岃烦杩囩珷鑺傚悕鏈楄", category: "TTS")
            isReadingChapterTitle = false
            speakNextSentence()
            return
        }

        // 妫€鏌ユ槸鍚︽湁棰勮浇鐨勭珷鑺傚悕缂撳瓨锛堜娇鐢ㄧ储寮?1琛ㄧず绔犺妭鍚嶏級
        if let cachedTitleData = cachedAudio(for: -1) {
            logger.log("鉁?浣跨敤棰勮浇鐨勭珷鑺傚悕闊抽", category: "TTS")
            playAudioWithData(data: cachedTitleData)
            // 鍦ㄧ珷鑺傚悕寮€濮嬫挱鏀炬椂灏卞惎鍔ㄩ杞斤紝閬垮厤闃诲
            logger.log("绔犺妭鍚嶆挱鏀句腑锛屽悓鏃跺惎鍔ㄥ唴瀹归杞?", category: "TTS")
            startPreloading()
            return
        }
        
        // 鎾斁闊抽
        Task {
            do {
                let (data, response) = try await URLSession.shared.data(from: audioURL)

                await MainActor.run {
                    // 妫€鏌TTP鍝嶅簲
                    if validateAudioData(data, response: response) {
                        playAudioWithData(data: data)
                        // 鍦ㄧ珷鑺傚悕寮€濮嬫挱鏀炬椂灏卞惎鍔ㄩ杞斤紝閬垮厤闃诲
                        logger.log("绔犺妭鍚嶆挱鏀句腑锛屽悓鏃跺惎鍔ㄥ唴瀹归杞?", category: "TTS")
                        startPreloading()
                    } else {
                        logger.log("绔犺妭鍚嶉煶棰戞棤鏁堬紝璺宠繃", category: "TTS")
                        isReadingChapterTitle = false
                        speakNextSentence()
                    }
                }
            } catch {
                logger.log("绔犺妭鍚嶉煶棰戜笅杞藉け璐? \(error)", category: "TTS閿欒")
                await MainActor.run {
                    isReadingChapterTitle = false
                    speakNextSentence()
                }
            }
        }
    }
    
    // MARK: - 鏈楄涓嬩竴鍙?
    private func speakNextSentence() {
        guard isPlaying else {
            logger.log("TTS 已停止，跳过后续朗读", category: "TTS")
            return
        }
        guard currentSentenceIndex < sentences.count else {
            logger.log("褰撳墠绔犺妭鏈楄瀹屾垚锛屽噯澶囦笅涓€绔?", category: "TTS")
            // 褰撳墠绔犺妭璇诲畬锛岃嚜鍔ㄨ涓嬩竴绔?
            nextChapter()
            return
        }
        
        let sentence = sentences[currentSentenceIndex]
        
        // 璺宠繃绾爣鐐规垨绌虹櫧
        if isPunctuationOnly(sentence) {
            logger.log("鈴笍 璺宠繃绾爣鐐?绌虹櫧娈佃惤 [\(currentSentenceIndex + 1)/\(totalSentences)]: \(sentence)", category: "TTS")
            currentSentenceIndex += 1
            speakNextSentence()
            return
        }
        
        // 淇濆瓨杩涘害
        UserPreferences.shared.saveTTSProgress(bookUrl: bookUrl, chapterIndex: currentChapterIndex, sentenceIndex: currentSentenceIndex)

        // 绯荤粺 TTS 鍒ゆ柇
        if UserPreferences.shared.useSystemTTS {
            speakWithSystemTTS(text: sentence)
            return
        }

        // 鎻愬墠鍑嗗鍚庣画娈佃惤锛屽敖閲忔秷闄ゅ彞闂寸┖妗?
        startPreloading()

        guard let audioURL = buildAudioURL(for: sentence) else {
            logger.log("鏈€夋嫨 TTS 寮曟搸锛屽仠姝㈡挱鏀?", category: "TTS閿欒")
            stop()
            return
        }

        let speechRate = UserPreferences.shared.speechRate

        logger.log("鏈楄鍙ュ瓙 \(currentSentenceIndex + 1)/\(totalSentences) - 璇€? \(speechRate)", category: "TTS")
        logger.log("鍙ュ瓙鍐呭: \(sentence.prefix(50))...", category: "TTS")

        // 鎾斁闊抽
        playAudio(url: audioURL)
        
        // 鏇存柊閿佸睆淇℃伅
        if currentChapterIndex < chapters.count {
            updateNowPlayingInfo(chapterTitle: chapters[currentChapterIndex].title)
        }
    }
    
    // MARK: - 绯荤粺 TTS 鏈楄
    private func speakWithSystemTTS(text: String) {
        isLoading = false
        stopKeepAlive()
        
        let utterance = AVSpeechUtterance(string: text)
        
        // 璇煶璁剧疆
        if !UserPreferences.shared.systemVoiceId.isEmpty {
            utterance.voice = AVSpeechSynthesisVoice(identifier: UserPreferences.shared.systemVoiceId)
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        }
        
        // 璇€熻缃?
        // App 100 -> 绯荤粺 0.5 (Default)
        let rate = Float(UserPreferences.shared.speechRate / 200.0)
        utterance.rate = max(AVSpeechUtteranceMinimumSpeechRate, min(AVSpeechUtteranceMaximumSpeechRate, rate))
        
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        
        speechSynthesizer.speak(utterance)
        
        if currentChapterIndex < chapters.count {
            updateNowPlayingInfo(chapterTitle: chapters[currentChapterIndex].title)
        }
    }
    
    // MARK: - 鎾斁闊抽
    private func playAudio(url: URL) {
        isLoading = true
        
        logger.log("TTS 闊抽 URL: \(url.absoluteString)", category: "TTS")
        
        // 妫€鏌ョ紦瀛?
        if let cachedData = cachedAudio(for: currentSentenceIndex) {
            logger.log("鉁?浣跨敤缂撳瓨闊抽 - 绱㈠紩: \(currentSentenceIndex)", category: "TTS")
            playAudioWithData(data: cachedData)
            // 瑙﹀彂涓嬩竴鎵归杞?
            startPreloading()
            return
        }
        
        // 涓嬭浇闊抽鏁版嵁骞朵娇鐢?AVAudioPlayer 鎾斁
        Task {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                logger.log("鉁?URL鍙闂紝鏁版嵁澶у皬: \(data.count) 瀛楄妭", category: "TTS")

                let contentType = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? "unknown"
                logger.log("Content-Type: \(contentType)", category: "TTS")

                // 妫€鏌ユ暟鎹槸鍚︿负鏈夋晥闊抽
                if !validateAudioData(data, response: response) {
                    logger.log("鉂?鏁版嵁鏃犳晥鎴栬В鐮佸け璐ワ紝澶у皬: \(data.count) 瀛楄妭", category: "TTS閿欒")
                    if data.count < 2000, let text = String(data: data, encoding: .utf8) {
                        logger.log("杩斿洖鍐呭: \(text.prefix(500))", category: "TTS閿欒")
                    }
                    await MainActor.run {
                        isLoading = false
                        logger.log("鈿狅笍 闊抽鏃犳晥锛屽皾璇曚笅涓€娈?", category: "TTS")
                        currentSentenceIndex += 1
                        speakNextSentence()
                    }
                    return
                }
                
                // 鍦ㄤ富绾跨▼鍒涘缓骞舵挱鏀鹃煶棰?
                await MainActor.run {
                    playAudioWithData(data: data)
                    // 瑙﹀彂棰勮浇
                    startPreloading()
                }
            } catch {
                logger.log("鉂?缃戠粶閿欒: \(error.localizedDescription)", category: "TTS閿欒")
                await MainActor.run {
                    isLoading = false
                    logger.log("鈿狅笍 缃戠粶閿欒锛屽皾璇曚笅涓€娈?", category: "TTS")
                    currentSentenceIndex += 1
                    speakNextSentence()
                }
            }
        }
    }
    
    // MARK: - 寮€濮嬮杞?
    private func startPreloading() {
        let preloadCount = UserPreferences.shared.ttsPreloadCount
        
        // 棰勮浇褰撳墠绔犺妭鐨勬钀?
        if preloadCount > 0 {
            let startIndex = currentSentenceIndex + 1
            let endIndex = min(startIndex + preloadCount, sentences.count)
            
            // 璁＄畻闇€瑕侀杞界殑绱㈠紩 (鏈紦瀛樹笖涓嶅湪闃熷垪涓?
            // 娉ㄦ剰锛氳繖閲岀畝鍖栦负鍙鏌ョ紦瀛橈紝姣忔閮藉埛鏂伴槦鍒椾互纭繚椤哄簭浼樺厛
            let neededIndices = (startIndex..<endIndex).filter {
                cachedAudio(for: $0) == nil
            }

            if !neededIndices.isEmpty {
                // 鏇存柊闃熷垪锛氳鐩栦负褰撳墠鏈€闇€瑕佺殑
                updatePreloadQueue(neededIndices)
                // 鍚姩闃熷垪澶勭悊
                processPreloadQueue()
            } else {
                // 褰撳墠娈佃惤閮絆K浜嗭紝妫€鏌ヤ笅涓€绔?
                checkAndPreloadNextChapter()
            }
        } else {
            checkAndPreloadNextChapter()
        }
    }
    
    // MARK: - 澶勭悊棰勮浇闃熷垪 (骞跺彂涓嬭浇 + 椤哄簭浼樺厛)
    private func processPreloadQueue() {
        guard !getIsPreloading() else { return }

        setIsPreloading(true)

        Task { [weak self] in
            guard let self = self else { return }

            await withTaskGroup(of: Void.self) { group in
                var activeDownloads = 0
                let queue = self.dequeuePreloadQueue()
                var queueIndex = 0

                while queueIndex < queue.count || activeDownloads > 0 {
                    // 妫€鏌ユ槸鍚﹁鍋滄
                    if !self.getIsPreloading() {
                        group.cancelAll()
                        break
                    }

                    // 鍚姩鏂扮殑涓嬭浇浠诲姟锛堝湪骞跺彂闄愬埗鍐咃級
                    while activeDownloads < self.maxConcurrentDownloads && queueIndex < queue.count {
                        let index = queue[queueIndex]
                        queueIndex += 1

                        // 璺宠繃宸茬紦瀛樼殑
                        if self.cachedAudio(for: index) != nil {
                            continue
                        }

                        activeDownloads += 1

                        group.addTask { [weak self] in
                            guard let self = self else { return }
                            await self.downloadAudioWithRetry(at: index)
                        }
                    }

                    // 绛夊緟鑷冲皯涓€涓换鍔″畬鎴?
                    if activeDownloads > 0 {
                        await group.next()
                        activeDownloads -= 1
                    }
                }
            }

            self.setIsPreloading(false)

            // 闃熷垪绌轰簡锛屾鏌ヤ笅涓€绔犳垨澶勭悊鏂板姞鍏ョ殑浠诲姟
            if self.hasPendingPreloadQueue() {
                self.processPreloadQueue()
            } else {
                await MainActor.run {
                    self.checkAndPreloadNextChapter()
                }
            }
        }
    }
    
    // MARK: - 甯﹂噸璇曠殑涓嬭浇
    private func downloadAudioWithRetry(at index: Int) async {
        for attempt in 0...maxPreloadRetries {
            // 妫€鏌ユ槸鍚﹁繕闇€瑕佷笅杞?(鍙兘鐢ㄦ埛宸茬粡鍒囪蛋浜?
            if !getIsPreloading() { return }
            
            let success = await downloadAudio(at: index)
            if success {
                return
            }
            
            if attempt < maxPreloadRetries {
                logger.log("鈿狅笍 棰勮浇閲嶈瘯 \(attempt + 1)/\(maxPreloadRetries) - 绱㈠紩: \(index)", category: "TTS")
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 澶辫触寤惰繜 1s
            }
        }
        logger.log("鉂?棰勮浇鏈€缁堝け璐?- 绱㈠紩: \(index)", category: "TTS閿欒")
    }
    
    // MARK: - 鍗曚釜涓嬭浇瀹炵幇
    private func downloadAudio(at index: Int) async -> Bool {
        guard index < sentences.count else { return false }
        let sentence = sentences[index]
        
        // 璺宠繃绾爣鐐?
        if isPunctuationOnly(sentence) {
            _ = await MainActor.run {
                preloadedIndices.insert(index)
            }
            return true
        }
        
        guard let url = buildAudioURL(for: sentence) else { return false }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            return await MainActor.run {
                // 妫€鏌TTP鍝嶅簲
                if validateAudioData(data, response: response) {
                    cacheAudio(data, for: index)
                    preloadedIndices.insert(index)
                    logger.log("鉁?椤哄簭棰勮浇鎴愬姛 - 绱㈠紩: \(index), 澶у皬: \(data.count)", category: "TTS")
                    return true
                } else {
                    return false
                }
            }
        } catch {
            logger.log("棰勮浇缃戠粶閿欒: \(error)", category: "TTS閿欒")
            return false
        }
    }
    
    private func playAudioWithData(data: Data) {
        do {
            // 鎾斁姝ｅ紡闊抽鍓嶏紝鍋滄闈欓煶淇濇椿
            stopKeepAlive()
            
            // 浣跨敤 AVAudioPlayer 鎾斁涓嬭浇鐨勬暟鎹?
            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.delegate = self
            audioPlayer?.volume = 1.0
            audioPlayer?.prepareToPlay() // 棰勮В鐮侊紝鍑忓皯鎾斁鍓嶇殑绛夊緟
            
            logger.log("鍒涘缓 AVAudioPlayer 鎴愬姛", category: "TTS")
            logger.log("闊抽鏃堕暱: \(audioPlayer?.duration ?? 0) 绉?", category: "TTS")
            logger.log("闊抽鏍煎紡: \(audioPlayer?.format.description ?? "unknown")", category: "TTS")
            
            let success = audioPlayer?.play() ?? false
            if success {
                logger.log("鉁?闊抽寮€濮嬫挱鏀?", category: "TTS")
                isLoading = false
                currentSentenceDuration = audioPlayer?.duration ?? 0
                // 寤堕暱鍚庡彴浠诲姟
                beginBackgroundTask()
            } else {
                logger.log("鉂?闊抽鎾斁澶辫触锛岃烦杩囧綋鍓嶆钀?", category: "TTS閿欒")
                isLoading = false
                // 閿欒鎭㈠锛氳烦鍒颁笅涓€娈?
                currentSentenceIndex += 1
                speakNextSentence()
            }
        } catch {
            logger.log("鉂?鍒涘缓 AVAudioPlayer 澶辫触: \(error.localizedDescription)", category: "TTS閿欒")
            logger.log("閿欒璇︽儏: \(error)", category: "TTS閿欒")
            isLoading = false
            // 閿欒鎭㈠锛氳烦鍒颁笅涓€娈?
            logger.log("鈿狅笍 闊抽瑙ｇ爜澶辫触锛屽皾璇曚笅涓€娈?", category: "TTS")
            currentSentenceIndex += 1
            speakNextSentence()
        }
    }
    
    
    // MARK: - 鏆傚仠
    func pause() {
        logger.log("鏀跺埌鏆傚仠鍛戒护 - isPlaying: \(isPlaying), isPaused: \(isPaused)", category: "TTS")
        
        if isPlaying && !isPaused {
            isPaused = true
            
            if UserPreferences.shared.useSystemTTS {
                speechSynthesizer.pauseSpeaking(at: .immediate)
            } else if let player = audioPlayer {
                player.pause()
            }
            
            logger.log("鉁?TTS 鏆傚仠", category: "TTS")
            
            // 鏆傚仠鏃跺惎鍔ㄤ繚娲伙紝闃叉 App 琚寕璧?
            startKeepAlive()
            
            updatePlaybackRate()
        } else if isPaused {
            logger.log("TTS 宸茬粡澶勪簬鏆傚仠鐘舵€?", category: "TTS")
        } else {
            logger.log("TTS 鏈湪鎾斁锛屾棤娉曟殏鍋?", category: "TTS")
        }
    }
    
    // MARK: - 缁х画
    func resume() {
        logger.log("鏀跺埌鎭㈠鍛戒护 - isPlaying: \(isPlaying), isPaused: \(isPaused)", category: "TTS")
        
        if isPlaying && isPaused {
            isPaused = false
            
            if UserPreferences.shared.useSystemTTS {
                if speechSynthesizer.isPaused {
                    speechSynthesizer.continueSpeaking()
                } else {
                    speakNextSentence()
                }
            } else if let player = audioPlayer {
                player.play()
            } else {
                speakNextSentence()
            }
            
            logger.log("鉁?TTS 鎭㈠鎾斁", category: "TTS")
            updatePlaybackRate()
        } else if !isPlaying {
            // 濡傛灉宸茬粡鍋滄锛岄噸鏂板紑濮?
            logger.log("TTS 鏈湪鎾斁锛岄噸鏂板紑濮?", category: "TTS")
            isPlaying = true
            isPaused = false
            speakNextSentence()
        } else {
            // isPlaying = true 浣?isPaused = false锛屽凡缁忓湪鎾斁涓?
            logger.log("TTS 宸茬粡鍦ㄦ挱鏀句腑", category: "TTS")
        }
    }
    
    // MARK: - 妫€鏌ュ綋鍓嶇珷鑺傛槸鍚﹂杞藉畬鎴愶紝骞堕杞戒笅涓€绔?
    private func checkAndPreloadNextChapter(force: Bool = false) {
        // 濡傛灉鏄郴缁?TTS锛屼笉闇€瑕侀杞介煶棰?
        if UserPreferences.shared.useSystemTTS {
            return
        }
        
        // 濡傛灉宸茬粡鍦ㄩ杞戒笅涓€绔狅紝璺宠繃
        guard nextChapterSentences.isEmpty else {
            return
        }
        
        guard currentChapterIndex < chapters.count - 1 else {
            return
        }
        
        // 绔犺妭鍒囨崲鍚庡己鍒堕杞戒笅涓€绔狅紝閬垮厤鍒囨崲鏃跺崱椤?
        if force {
            logger.log("绔犺妭鍒囨崲鍚庣珛鍗抽杞戒笅涓€绔?", category: "TTS")
            preloadNextChapter()
            return
        }

        // 璁＄畻杩涘害鐧惧垎姣?
        let progress = Double(currentSentenceIndex) / Double(max(sentences.count, 1))

        // 褰撴挱鏀惧埌绔犺妭鐨?50% 鏃讹紝寮€濮嬮杞戒笅涓€绔?
        // 鎴栬€呭墿浣欐钀藉皯浜庣敤鎴疯缃殑棰勮浇娈垫暟鏃朵篃寮€濮嬮杞斤紙纭繚璺ㄧ珷鑺備繚鎸侀璇绘暟閲忥級
        let remainingSentences = sentences.count - currentSentenceIndex
        let preloadCount = UserPreferences.shared.ttsPreloadCount

        if progress >= 0.5 || (preloadCount > 0 && remainingSentences <= preloadCount) {
            logger.log("馃摉 鎾斁杩涘害 \(Int(progress * 100))%锛屽墿浣?\(remainingSentences) 娈碉紝瑙﹀彂棰勮浇涓嬩竴绔?", category: "TTS")
            preloadNextChapter()
        }
    }

    // MARK: - 棰勮浇涓嬩竴绔?
    private func preloadNextChapter() {
        // 绯荤粺 TTS 涓嶉渶瑕侀杞介煶棰?
        if UserPreferences.shared.useSystemTTS { return }
        
        // 濡傛灉宸茬粡鍦ㄩ杞戒笅涓€绔犳垨宸叉湁涓嬩竴绔犳暟鎹紝璺宠繃
        guard nextChapterSentences.isEmpty else { return }
        guard currentChapterIndex < chapters.count - 1 else { return }
        
        let nextChapterIndex = currentChapterIndex + 1
        logger.log("寮€濮嬮杞戒笅涓€绔? \(nextChapterIndex)", category: "TTS")
        
        // 棰勮浇涓嬩竴绔犵殑绔犺妭鍚?
        preloadNextChapterTitle(chapterIndex: nextChapterIndex)
        
        Task {
            do {
                let content = try await APIService.shared.fetchChapterContent(
                    bookUrl: bookUrl,
                    bookSourceUrl: bookSourceUrl,
                    index: nextChapterIndex
                )
                
                await MainActor.run {
                    // 鍒嗘
                    nextChapterSentences = splitTextIntoSentences(content)
                    logger.log("涓嬩竴绔犲垎娈靛畬鎴愶紝鍏?\(nextChapterSentences.count) 娈?", category: "TTS")
                    
                    // 棰勮浇涓嬩竴绔犵殑鍓嶅嚑涓钀斤紙鏍规嵁鐢ㄦ埛鐨勯杞借缃級
                    let userPreloadCount = UserPreferences.shared.ttsPreloadCount
                    let preloadCount = min(max(userPreloadCount, 3), nextChapterSentences.count)  // 鑷冲皯3娈碉紝鏈€澶氬埌鐢ㄦ埛璁剧疆鐨勫€?
                    logger.log("寮€濮嬮杞戒笅涓€绔犵殑鍓?\(preloadCount) 娈甸煶棰?", category: "TTS")
                    
                    for i in 0..<preloadCount {
                        preloadNextChapterAudio(at: i)
                    }
                }
            } catch {
                logger.log("棰勮浇涓嬩竴绔犲け璐? \(error)", category: "TTS閿欒")
            }
        }
    }
    
    // MARK: - 棰勮浇涓嬩竴绔犵殑绔犺妭鍚?
    private func preloadNextChapterTitle(chapterIndex: Int) {
        if UserPreferences.shared.useSystemTTS { return }
        guard chapterIndex < chapters.count else { return }
        guard nextChapterCache[-1] == nil else { return }
        
        let chapterTitle = chapters[chapterIndex].title
        logger.log("棰勮浇涓嬩竴绔犵珷鑺傚悕: \(chapterTitle)", category: "TTS")

        guard let audioURL = buildAudioURL(for: chapterTitle, isChapterTitle: true) else { return }
        
        Task {
            do {
                let (data, response) = try await URLSession.shared.data(from: audioURL)

                await MainActor.run {
                    if validateAudioData(data, response: response) {
                        cacheNextChapterAudio(data, for: -1)
                        logger.log("鉁?涓嬩竴绔犵珷鑺傚悕棰勮浇鎴愬姛锛屽ぇ灏? \(data.count) 瀛楄妭", category: "TTS")
                    } else {
                        logger.log("鈿狅笍 涓嬩竴绔犵珷鑺傚悕棰勮浇澶辫触锛屾暟鎹牸寮忔垨浣撶Н寮傚父 (澶у皬: \(data.count) 瀛楄妭)", category: "TTS")
                    }
                }
            } catch {
                logger.log("涓嬩竴绔犵珷鑺傚悕棰勮浇澶辫触: \(error)", category: "TTS閿欒")
            }
        }
    }
    
    // MARK: - 棰勮浇涓嬩竴绔犵殑闊抽
    private func preloadNextChapterAudio(at index: Int) {
        if UserPreferences.shared.useSystemTTS { return }
        guard index < nextChapterSentences.count else { return }
        guard cachedNextChapterAudio(for: index) == nil else { return }
        
        let sentence = nextChapterSentences[index]
        guard let url = buildAudioURL(for: sentence) else { return }
        
        logger.log("棰勮浇涓嬩竴绔犻煶棰?- 绱㈠紩: \(index)", category: "TTS")
        
        Task {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                
                let contentType = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? "unknown"

                await MainActor.run {
                    if validateAudioData(data, response: response) {
                        cacheNextChapterAudio(data, for: index)
                        logger.log("鉁?涓嬩竴绔犻杞芥垚鍔?- 绱㈠紩: \(index), 澶у皬: \(data.count) 瀛楄妭, Content-Type: \(contentType)", category: "TTS")
                    } else {
                        logger.log("鈿狅笍 涓嬩竴绔犻杞介煶棰戞棤鏁堬紝Content-Type: \(contentType), 澶у皬: \(data.count) 瀛楄妭", category: "TTS")
                    }
                }
            } catch {
                logger.log("涓嬩竴绔犻杞藉け璐?- 绱㈠紩: \(index), 閿欒: \(error)", category: "TTS閿欒")
            }
        }
    }
    
    // MARK: - 鍋滄
    func stop() {
        // 在停止前保存最后一次进度
        saveCurrentProgress()
        
        stopKeepAlive()
        audioPlayer?.stop()
        audioPlayer = nil
        
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        
        isPlaying = false
        isPaused = false
        currentSentenceIndex = 0
        currentBaseSentenceIndex = 0
        sentences = []
        isLoading = false
        // 娓呯悊缂撳瓨
        clearAudioCache()
        updatePreloadQueue([])
        setIsPreloading(false)
        clearNextChapterCache()
        nextChapterSentences.removeAll()
        coverArtwork = nil  // 娓呯悊灏侀潰缂撳瓨
        // 缁撴潫鍚庡彴浠诲姟
        endBackgroundTask()
        logger.log("TTS 鍋滄", category: "TTS")
    }
    
    private func saveCurrentProgress() {
        guard !bookUrl.isEmpty, isPlaying else { return }
        
        let chapterIdx = currentChapterIndex
        let sentenceIdx = currentSentenceIndex + currentBaseSentenceIndex
        
        // 1. 本地保存
        UserPreferences.shared.saveTTSProgress(bookUrl: bookUrl, chapterIndex: chapterIdx, sentenceIndex: sentenceIdx)
        
        // 2. 远程同步
        Task {
            // 计算字符偏移量
            let pStarts = sentences.enumerated().map { (idx, _) in
                sentences[0..<idx].reduce(0) { $0 + $1.utf16.count + 1 }
            }
            let bodyIndex = pStarts.indices.contains(currentSentenceIndex) ? pStarts[currentSentenceIndex] : 0
            
            // 计算比例
            let totalLen = sentences.reduce(0) { $0 + $1.utf16.count + 1 }
            let pos = totalLen > 0 ? Double(bodyIndex) / Double(totalLen) : 0.0
            
            let title = chapterIdx < chapters.count ? chapters[chapterIdx].title : nil
            
            // 保存到 UserPreferences 的通用阅读进度
            UserPreferences.shared.saveReadingProgress(bookUrl: bookUrl, chapterIndex: chapterIdx, pageIndex: 0, bodyCharIndex: bodyIndex)
            
            // 发送到服务器
            try? await APIService.shared.saveBookProgress(bookUrl: bookUrl, index: chapterIdx, pos: pos, title: title)
            logger.log("鉁?TTS 鍋滄鏃跺凡鑷姩鍚屾杩涘害", category: "TTS")
        }
    }
    
    // MARK: - 涓嬩竴绔?
    func nextChapter() {
        guard currentChapterIndex < chapters.count - 1 else { return }
        currentChapterIndex += 1
        onChapterChange?(currentChapterIndex)
        loadAndReadChapter()
    }
    
    // MARK: - 涓婁竴绔?
    func previousChapter() {
        guard currentChapterIndex > 0 else { return }
        currentChapterIndex -= 1
        onChapterChange?(currentChapterIndex)
        loadAndReadChapter()
    }
    
    // MARK: - 鍔犺浇骞舵湕璇荤珷鑺?
    private func loadAndReadChapter() {
        // 鍋滄褰撳墠鎾斁
        audioPlayer?.stop()
        audioPlayer = nil
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }

        // 妫€鏌ユ槸鍚︽湁棰勮浇鐨媪涓€绔犳暟鎹?
        if !nextChapterSentences.isEmpty {
            logger.log("浣跨敤宸查杞界殑涓嬩竴绔犳暟鎹?", category: "TTS")
            
            // 鍋滄褰撳墠鎾斁
            audioPlayer?.stop()
            audioPlayer = nil
            
            // 浣跨敤棰勮浇鐨勬暟鎹?
            sentences = nextChapterSentences
            totalSentences = sentences.count
            currentSentenceIndex = 0

            // 灏嗕笅涓€绔犵殑缂撳瓨绉诲姩鍒板綋鍓嶇珷鑺傦紙鍖呮嫭绔犺妭鍚嶇储寮?1鍜屾鏂囨钀斤級
            preloadedIndices = moveNextChapterCacheToCurrent()

            // 娓呯┖涓嬩竴绔犵紦瀛?
            nextChapterSentences.removeAll()
            
            isPlaying = true
            isPaused = false
            isLoading = false
            
            if currentChapterIndex < chapters.count {
                updateNowPlayingInfo(chapterTitle: chapters[currentChapterIndex].title)
            }
            
            // 绔犺妭鍒囨崲鍚庢彁鍓嶅噯澶囦笅涓€绔狅紝閬垮厤绔犺妭琛旀帴绛夊緟
            checkAndPreloadNextChapter(force: true)

            // 鍏堟湕璇荤珷鑺傚悕
            allowChapterTitlePlayback = !chapters[currentChapterIndex].title.isEmpty
            if allowChapterTitlePlayback {
                speakChapterTitle()
            } else {
                speakNextSentence()
            }
            
            return
        }
        
        // 娌℃湁棰勮浇鏁版嵁锛屼粠缂撳瓨鎴栫綉缁滃姞杞?
        logger.log("鈿狅笍 涓嬩竴绔犳湭棰勮浇瀹屾垚锛屽皾璇曚粠缂撳瓨鎴栫綉缁滃姞杞?", category: "TTS")
        
        // 鍋滄褰撳墠鎾斁
        audioPlayer?.stop()
        audioPlayer = nil
        
        Task {
            do {
                let startTime = Date()
                let content = try await APIService.shared.fetchChapterContent(
                    bookUrl: bookUrl,
                    bookSourceUrl: bookSourceUrl,
                    index: currentChapterIndex
                )
                let loadTime = Date().timeIntervalSince(startTime)
                
                await MainActor.run {
                    if loadTime < 0.1 {
                        logger.log("鉁?浠庣紦瀛樺姞杞界珷鑺傚唴瀹癸紝鑰楁椂: \(Int(loadTime * 1000))ms", category: "TTS")
                    } else {
                        logger.log("鈴?浠庣綉缁滃姞杞界珷鑺傚唴瀹癸紝鑰楁椂: \(String(format: "%.2f", loadTime))s", category: "TTS")
                    }
                    
                    sentences = splitTextIntoSentences(content)
                    totalSentences = sentences.count
                    currentSentenceIndex = 0

                    // 娓呯┖褰撳墠绔犺妭鐨勭紦瀛?
                    clearAudioCache()
                    updatePreloadQueue([])
                    setIsPreloading(false)
                    preloadedIndices.removeAll()
                    
                    isPlaying = true
                    isPaused = false
                    
                    if currentChapterIndex < chapters.count {
                        updateNowPlayingInfo(chapterTitle: chapters[currentChapterIndex].title)
                    }
                    
                    // 绔犺妭鍒囨崲鍚庢彁鍓嶅噯澶囦笅涓€绔狅紝閬垮厤绔犺妭琛旀帴绛夊緟
                    checkAndPreloadNextChapter(force: true)

                    // 鍏堟湕璇荤珷鑺傚悕
                    allowChapterTitlePlayback = !chapters[currentChapterIndex].title.isEmpty
                    if allowChapterTitlePlayback {
                        speakChapterTitle()
                    } else {
                        speakNextSentence()
                    }
                }
            } catch {
                logger.log("鍔犺浇绔犺妭澶辫触: \(error)", category: "TTS閿欒")
            }
        }
    }
    
    // MARK: - 鏇存柊鎾斁閫熺巼
    private func updatePlaybackRate() {
        var nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [String: Any]()
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying && !isPaused ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        endBackgroundTask()
        logger.log("TTSManager 閿€姣?", category: "TTS")
    }
}

// MARK: - AVSpeechSynthesizerDelegate
extension TTSManager: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            guard self.isPlaying else {
                self.logger.log("绯荤粺 TTS 宸插仠姝㈢晠璇?", category: "TTS")
                return
            }
            self.logger.log("绯荤粺 TTS 鏈楄瀹屾垚", category: "TTS")
            
            // 鎾斁闂撮殭鍚姩淇濇椿
            self.startKeepAlive()

            if self.isReadingChapterTitle {
                self.isReadingChapterTitle = false
                self.speakNextSentence()
                return
            }

            self.currentSentenceIndex += 1
            self.speakNextSentence()
        }
    }
}

// MARK: - AVAudioPlayerDelegate
extension TTSManager: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        // AVAudioPlayer 鐨勫洖璋冪嚎绋嬩笉淇濊瘉鍦ㄤ富绾跨▼锛岀粺涓€鍒囨崲鍒颁富绾跨▼鏇存柊鐘舵€?
        DispatchQueue.main.async {
            guard self.isPlaying else {
                self.logger.log("TTS 宸插仠姝㈡挱鏀?", category: "TTS")
                return
            }
            self.logger.log("闊抽鎾斁瀹屾垚 - 鎴愬姛: \(flag)", category: "TTS")

            // 鎾斁闂撮殭鍚姩淇濇椿
            self.startKeepAlive()

            // 濡傛灉姝ｅ湪鏈楄绔犺妭鍚嶏紝鎾斁瀹屽悗寮€濮嬫湕璇诲唴瀹?
            if self.isReadingChapterTitle {
                self.isReadingChapterTitle = false
                self.speakNextSentence()
                return
            }

            if flag {
                // 鎾斁涓嬩竴鍙?
                self.currentSentenceIndex += 1
                self.speakNextSentence()
            } else {
                self.logger.log("闊抽鎾斁澶辫触锛岃烦杩?", category: "TTS閿欒")
                self.currentSentenceIndex += 1
                self.speakNextSentence()
            }
        }
    }
    
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        if let error = error {
            logger.log("鉂?闊抽瑙ｇ爜閿欒: \(error.localizedDescription)", category: "TTS閿欒")
        }
        // 璺宠繃杩欎竴鍙?
        currentSentenceIndex += 1
        speakNextSentence()
    }
}



