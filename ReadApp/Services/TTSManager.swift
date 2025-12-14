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
    @Published var preloadedIndices: Set<Int> = []  // 已预载成功的段落索引
    
    private var audioPlayer: AVAudioPlayer?
    private var sentences: [String] = []
    var currentChapterIndex: Int = 0  // 公开给ReadingView使用
    private var chapters: [BookChapter] = []
    var bookUrl: String = ""  // 公开给ReadingView使用
    private var bookSourceUrl: String?
    private var bookTitle: String = ""
    private var bookCoverUrl: String?
    private var coverArtwork: MPMediaItemArtwork?
    private var onChapterChange: ((Int) -> Void)?
    private var currentSentenceObserver: Any?
    
    // 预载缓存
    private var audioCache: [Int: Data] = [:]  // 索引 -> 音频数据（索引-1为章节名，0~n为正文段落）
    private var preloadQueue: [Int] = []       // 等待预载的队列
    private var isPreloading = false           // 是否正在执行预载任务
    private let maxPreloadRetries = 3          // 最大重试次数
    private let maxConcurrentDownloads = 6     // 最大并发下载数
    private let preloadStateQueue = DispatchQueue(label: "com.readapp.tts.preloadStateQueue")
    
    // 下一章预载
    private var nextChapterSentences: [String] = []  // 下一章的段落
    private var nextChapterCache: [Int: Data] = [:]  // 下一章的音频缓存（索引-1为章节名）
    
    // 章节名朗读
    private var isReadingChapterTitle = false  // 是否正在朗读章节名
    
    // 后台保活
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var keepAlivePlayer: AVAudioPlayer?

    // MARK: - 预载状态封装（串行队列防竞态）
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
        logger.log("TTSManager 初始化", category: "TTS")
        setupAudioSession()
        setupRemoteCommands()
        setupNotifications()
    }
    
    // MARK: - 配置音频会话
    private func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            logger.log("配置音频会话 - Category: playback, Mode: default", category: "TTS")
            
            // 使用更简单的配置，先设置category
            try audioSession.setCategory(.playback, options: [])
            
            // 然后激活会话
            try audioSession.setActive(true)
            
            logger.log("音频会话配置成功", category: "TTS")
        } catch {
            logger.log("音频会话设置失败: \(error.localizedDescription)", category: "TTS错误")
            logger.log("错误详情: \(error)", category: "TTS错误")
        }
    }
    
    // MARK: - 设置远程控制
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
    
    // MARK: - 设置通知监听
    private func setupNotifications() {
        // 监听音频中断
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioInterruption),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
        
        // 监听路由变更（如耳机拔出）
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance()
        )
    }
    
    // MARK: - 处理音频中断
    @objc private func handleAudioInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        switch type {
        case .began:
            // 中断开始（如来电、闹钟等）
            logger.log("🔔 音频中断开始", category: "TTS")
            if isPlaying && !isPaused {
                pause()
                logger.log("已暂停播放", category: "TTS")
            }
            
        case .ended:
            // 中断结束
            guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else {
                logger.log("🔔 音频中断结束（无恢复选项）", category: "TTS")
                return
            }
            
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if options.contains(.shouldResume) {
                // 系统建议恢复播放
                logger.log("🔔 音频中断结束，自动恢复播放", category: "TTS")
                
                // 重新激活音频会话
                do {
                    try AVAudioSession.sharedInstance().setActive(true)
                    logger.log("音频会话重新激活", category: "TTS")
                } catch {
                    logger.log("❌ 重新激活音频会话失败: \(error)", category: "TTS错误")
                }
                
                // 延迟一点恢复，确保音频会话稳定
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    guard let self = self else { return }
                    if self.isPlaying && self.isPaused {
                        self.resume()
                        self.logger.log("✅ 播放已恢复", category: "TTS")
                    }
                }
            } else {
                logger.log("🔔 音频中断结束（不建议自动恢复）", category: "TTS")
            }
            
        @unknown default:
            logger.log("⚠️ 未知的音频中断类型", category: "TTS")
        }
    }
    
    // MARK: - 处理音频路由变更
    @objc private func handleRouteChange(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }
        
        switch reason {
        case .oldDeviceUnavailable:
            // 音频输出设备断开（如耳机拔出）
            logger.log("🎧 音频设备断开，暂停播放", category: "TTS")
            if isPlaying && !isPaused {
                pause()
            }
            
        case .newDeviceAvailable:
            // 新的音频输出设备连接
            logger.log("🎧 新音频设备连接", category: "TTS")
            
        default:
            logger.log("🎧 音频路由变更: \(reason.rawValue)", category: "TTS")
        }
    }
    
    // MARK: - 更新锁屏信息
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
        
        // 添加封面图片
        if let artwork = coverArtwork {
            nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
        }
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
    
    // MARK: - 加载封面图片
    private func loadCoverArtwork() {
        guard let coverUrlString = bookCoverUrl, !coverUrlString.isEmpty else {
            logger.log("未提供封面URL", category: "TTS")
            return
        }
        
        // 如果已有缓存，跳过
        if coverArtwork != nil {
            return
        }
        
        guard let url = URL(string: coverUrlString) else {
            logger.log("封面URL无效: \(coverUrlString)", category: "TTS错误")
            return
        }
        
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                
                if let image = UIImage(data: data) {
                    await MainActor.run {
                        // 创建 MPMediaItemArtwork
                        let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in
                            return image
                        }
                        self.coverArtwork = artwork
                        
                        // 更新锁屏信息
                        if self.currentChapterIndex < self.chapters.count {
                            self.updateNowPlayingInfo(chapterTitle: self.chapters[self.currentChapterIndex].title)
                        }
                        
                        self.logger.log("✅ 封面加载成功", category: "TTS")
                    }
                } else {
                    logger.log("封面图片解码失败", category: "TTS错误")
                }
            } catch {
                logger.log("封面下载失败: \(error.localizedDescription)", category: "TTS错误")
            }
        }
    }
    
    // MARK: - 开始朗读
    func startReading(text: String, chapters: [BookChapter], currentIndex: Int, bookUrl: String, bookSourceUrl: String?, bookTitle: String, coverUrl: String?, onChapterChange: @escaping (Int) -> Void, resumeFromProgress: Bool = true) {
        logger.log("开始朗读 - 书名: \(bookTitle), 章节: \(currentIndex)/\(chapters.count)", category: "TTS")
        logger.log("内容长度: \(text.count) 字符", category: "TTS")
        
        self.chapters = chapters
        self.currentChapterIndex = currentIndex
        self.bookUrl = bookUrl
        self.bookSourceUrl = bookSourceUrl
        self.bookTitle = bookTitle
        self.bookCoverUrl = coverUrl
        self.onChapterChange = onChapterChange
        
        // 加载封面图片
        loadCoverArtwork()
        
        // 开始后台任务
        beginBackgroundTask()
        
        // 清空缓存和预载状态
        clearAudioCache()
        preloadedIndices.removeAll()
        updatePreloadQueue([])
        setIsPreloading(false)
        clearNextChapterCache()
        nextChapterSentences.removeAll()
        
        // 分句
        sentences = splitTextIntoSentences(text)
        totalSentences = sentences.count
        
        // 尝试恢复进度
        if resumeFromProgress, let progress = UserPreferences.shared.getTTSProgress(bookUrl: bookUrl) {
            if progress.chapterIndex == currentIndex && progress.sentenceIndex < sentences.count {
                currentSentenceIndex = progress.sentenceIndex
                logger.log("恢复TTS进度 - 章节: \(currentIndex), 段落: \(currentSentenceIndex)", category: "TTS")
            } else {
                currentSentenceIndex = 0
            }
        } else {
            currentSentenceIndex = 0
        }
        
        logger.log("分句完成 - 共 \(totalSentences) 句, 从第 \(currentSentenceIndex + 1) 句开始", category: "TTS")
        
        // 更新锁屏信息
        if currentIndex < chapters.count {
            updateNowPlayingInfo(chapterTitle: chapters[currentIndex].title)
        }
        
        isPlaying = true
        isPaused = false
        
        // 如果从头开始播放，先朗读章节名
        if currentSentenceIndex == 0 {
            speakChapterTitle()
        } else {
            speakNextSentence()
        }
    }
    
    // MARK: - 上一段
    func previousSentence() {
        if currentSentenceIndex > 0 {
            currentSentenceIndex -= 1
            audioPlayer?.stop()
            audioPlayer = nil
            
            // 保存进度
            UserPreferences.shared.saveTTSProgress(bookUrl: bookUrl, chapterIndex: currentChapterIndex, sentenceIndex: currentSentenceIndex)
            
            if isPlaying {
                speakNextSentence()
            }
        }
    }
    
    // MARK: - 下一段
    func nextSentence() {
        if currentSentenceIndex < sentences.count - 1 {
            currentSentenceIndex += 1
            audioPlayer?.stop()
            audioPlayer = nil
            
            // 保存进度
            UserPreferences.shared.saveTTSProgress(bookUrl: bookUrl, chapterIndex: currentChapterIndex, sentenceIndex: currentSentenceIndex)
            
            if isPlaying {
                speakNextSentence()
            }
        }
    }
    
    // MARK: - 判断是否为纯标点或空白
    private func isPunctuationOnly(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return true
        }
        
        // 定义标点符号集合
        let punctuationSet = CharacterSet.punctuationCharacters
            .union(.symbols)
            .union(.whitespacesAndNewlines)
        
        // 检查是否所有字符都是标点、符号或空白
        for scalar in trimmed.unicodeScalars {
            if !punctuationSet.contains(scalar) {
                return false
            }
        }
        
        return true
    }
    
    // MARK: - 激进保活 (Silent Audio)
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
                // buffer 默认为静音(0)
                try audioFile.write(from: buffer)
            }
            return fileUrl
        } catch {
            logger.log("创建静音文件失败: \(error)", category: "TTS错误")
            return nil
        }
    }
    
    private func startKeepAlive() {
        guard keepAlivePlayer == nil || !keepAlivePlayer!.isPlaying else { return }
        
        logger.log("🛡️ 启动激进保活(静音播放)", category: "TTS")
        
        if let url = createSilentAudioUrl() {
            do {
                keepAlivePlayer = try AVAudioPlayer(contentsOf: url)
                keepAlivePlayer?.numberOfLoops = -1 // 无限循环
                keepAlivePlayer?.volume = 0.0 // 静音
                keepAlivePlayer?.prepareToPlay()
                keepAlivePlayer?.play()
            } catch {
                logger.log("❌ 启动保活失败: \(error)", category: "TTS错误")
            }
        }
    }
    
    private func stopKeepAlive() {
        if keepAlivePlayer != nil {
            logger.log("🛑 停止激进保活", category: "TTS")
            keepAlivePlayer?.stop()
            keepAlivePlayer = nil
        }
    }

    // MARK: - 开始后台任务
    private func beginBackgroundTask() {
        endBackgroundTask()  // 先结束之前的任务
        
        // 启动静音保活
        startKeepAlive()
        
        backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.logger.log("⚠️ 后台任务即将过期", category: "TTS")
            self?.endBackgroundTask()
        }
        
        if backgroundTask != .invalid {
            logger.log("✅ 后台任务已开始: \(backgroundTask.rawValue)", category: "TTS")
        }
    }
    
    // MARK: - 结束后台任务
    private func endBackgroundTask() {
        if backgroundTask != .invalid {
            logger.log("结束后台任务: \(backgroundTask.rawValue)", category: "TTS")
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }
    
    // MARK: - 过滤SVG标签
    private func removeSVGTags(_ text: String) -> String {
        var result = text
        
        // 移除SVG标签（包括多行SVG）
        let svgPattern = "<svg[^>]*>.*?</svg>"
        if let svgRegex = try? NSRegularExpression(pattern: svgPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            let range = NSRange(location: 0, length: result.utf16.count)
            result = svgRegex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
        }
        
        // 只移除常见的HTML标签，保留文本内容
        // 先移除img标签
        let imgPattern = "<img[^>]*>"
        if let imgRegex = try? NSRegularExpression(pattern: imgPattern, options: [.caseInsensitive]) {
            let range = NSRange(location: 0, length: result.utf16.count)
            result = imgRegex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
        }
        
        // 移除其他标签但保留内容
        let htmlPattern = "<[^>]+>"
        if let htmlRegex = try? NSRegularExpression(pattern: htmlPattern, options: []) {
            let range = NSRange(location: 0, length: result.utf16.count)
            result = htmlRegex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
        }
        
        // 清理HTML实体
        result = result.replacingOccurrences(of: "&nbsp;", with: " ")
        result = result.replacingOccurrences(of: "&lt;", with: "<")
        result = result.replacingOccurrences(of: "&gt;", with: ">")
        result = result.replacingOccurrences(of: "&amp;", with: "&")
        result = result.replacingOccurrences(of: "&quot;", with: "\"")
        
        logger.log("原始文本长度: \(text.count), 过滤后: \(result.count)", category: "TTS")
        return result
    }
    
    // MARK: - 智能分段（优化版）
    private func splitTextIntoSentences(_ text: String) -> [String] {
        // 先过滤SVG和HTML标签
        let filtered = removeSVGTags(text)
        
        // 按换行符分割，保持原文分段
        let paragraphs = filtered.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }  // 移除每段的前后空白
            .filter { !$0.isEmpty }  // 过滤空段落
        
        return paragraphs
    }
    
    // MARK: - 朗读章节名
    private func speakChapterTitle() {
        guard currentChapterIndex < chapters.count else {
            speakNextSentence()
            return
        }
        
        let chapterTitle = chapters[currentChapterIndex].title
        logger.log("开始朗读章节名: \(chapterTitle)", category: "TTS")
        
        isReadingChapterTitle = true
        
        // 检查是否选择了 TTS 引擎
        let ttsId = UserPreferences.shared.selectedTTSId
        if ttsId.isEmpty {
            logger.log("未选择 TTS 引擎，跳过章节名朗读", category: "TTS")
            isReadingChapterTitle = false
            speakNextSentence()
            return
        }
        
        // 检查是否有预载的章节名缓存（使用索引-1表示章节名）
        if let cachedTitleData = cachedAudio(for: -1) {
            logger.log("✅ 使用预载的章节名音频", category: "TTS")
            playAudioWithData(data: cachedTitleData)
            // 在章节名开始播放时就启动预载，避免阻塞
            logger.log("章节名播放中，同时启动内容预载", category: "TTS")
            startPreloading()
            return
        }
        
        let speechRate = UserPreferences.shared.speechRate
        
        // 构建 TTS 音频 URL
        guard let audioURL = APIService.shared.buildTTSAudioURL(
            ttsId: ttsId,
            text: chapterTitle,
            speechRate: speechRate
        ) else {
            logger.log("构建章节名音频 URL 失败", category: "TTS错误")
            isReadingChapterTitle = false
            speakNextSentence()
            return
        }
        
        // 播放音频
        Task {
            do {
                let (data, response) = try await URLSession.shared.data(from: audioURL)

                await MainActor.run {
                    // 检查HTTP响应
                    if validateAudioData(data, response: response) {
                        playAudioWithData(data: data)
                        // 在章节名开始播放时就启动预载，避免阻塞
                        logger.log("章节名播放中，同时启动内容预载", category: "TTS")
                        startPreloading()
                    } else {
                        logger.log("章节名音频无效，跳过", category: "TTS")
                        isReadingChapterTitle = false
                        speakNextSentence()
                    }
                }
            } catch {
                logger.log("章节名音频下载失败: \(error)", category: "TTS错误")
                await MainActor.run {
                    isReadingChapterTitle = false
                    speakNextSentence()
                }
            }
        }
    }
    
    // MARK: - 朗读下一句
    private func speakNextSentence() {
        guard currentSentenceIndex < sentences.count else {
            logger.log("当前章节朗读完成，准备下一章", category: "TTS")
            // 当前章节读完，自动读下一章
            nextChapter()
            return
        }
        
        let sentence = sentences[currentSentenceIndex]
        
        // 跳过纯标点或空白
        if isPunctuationOnly(sentence) {
            logger.log("⏭️ 跳过纯标点/空白段落 [\(currentSentenceIndex + 1)/\(totalSentences)]: \(sentence)", category: "TTS")
            currentSentenceIndex += 1
            speakNextSentence()
            return
        }
        
        // 保存进度
        UserPreferences.shared.saveTTSProgress(bookUrl: bookUrl, chapterIndex: currentChapterIndex, sentenceIndex: currentSentenceIndex)
        
        // 检查是否选择了 TTS 引擎
        let ttsId = UserPreferences.shared.selectedTTSId
        if ttsId.isEmpty {
            logger.log("未选择 TTS 引擎，停止播放", category: "TTS错误")
            stop()
            return
        }
        
        let speechRate = UserPreferences.shared.speechRate
        
        logger.log("朗读句子 \(currentSentenceIndex + 1)/\(totalSentences) - 语速: \(speechRate)", category: "TTS")
        logger.log("句子内容: \(sentence.prefix(50))...", category: "TTS")
        
        // 构建 TTS 音频 URL
        guard let audioURL = APIService.shared.buildTTSAudioURL(
            ttsId: ttsId,
            text: sentence,
            speechRate: speechRate
        ) else {
            logger.log("构建音频 URL 失败", category: "TTS错误")
            currentSentenceIndex += 1
            speakNextSentence()
            return
        }
        
        // 播放音频
        playAudio(url: audioURL)
        
        // 更新锁屏信息
        if currentChapterIndex < chapters.count {
            updateNowPlayingInfo(chapterTitle: chapters[currentChapterIndex].title)
        }
    }
    
    // MARK: - 播放音频
    private func playAudio(url: URL) {
        isLoading = true
        
        logger.log("TTS 音频 URL: \(url.absoluteString)", category: "TTS")
        
        // 检查缓存
        if let cachedData = cachedAudio(for: currentSentenceIndex) {
            logger.log("✅ 使用缓存音频 - 索引: \(currentSentenceIndex)", category: "TTS")
            playAudioWithData(data: cachedData)
            // 触发下一批预载
            startPreloading()
            return
        }
        
        // 下载音频数据并使用 AVAudioPlayer 播放
        Task {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                logger.log("✅ URL可访问，数据大小: \(data.count) 字节", category: "TTS")

                let contentType = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? "unknown"
                logger.log("Content-Type: \(contentType)", category: "TTS")

                // 检查数据是否为有效音频
                if !validateAudioData(data, response: response) {
                    logger.log("❌ 数据无效或解码失败，大小: \(data.count) 字节", category: "TTS错误")
                    if data.count < 2000, let text = String(data: data, encoding: .utf8) {
                        logger.log("返回内容: \(text.prefix(500))", category: "TTS错误")
                    }
                    await MainActor.run {
                        isLoading = false
                        logger.log("⚠️ 音频无效，尝试下一段", category: "TTS")
                        currentSentenceIndex += 1
                        speakNextSentence()
                    }
                    return
                }
                
                // 在主线程创建并播放音频
                await MainActor.run {
                    playAudioWithData(data: data)
                    // 触发预载
                    startPreloading()
                }
            } catch {
                logger.log("❌ 网络错误: \(error.localizedDescription)", category: "TTS错误")
                await MainActor.run {
                    isLoading = false
                    logger.log("⚠️ 网络错误，尝试下一段", category: "TTS")
                    currentSentenceIndex += 1
                    speakNextSentence()
                }
            }
        }
    }
    
    // MARK: - 开始预载
    private func startPreloading() {
        let preloadCount = UserPreferences.shared.ttsPreloadCount
        
        // 预载当前章节的段落
        if preloadCount > 0 {
            let startIndex = currentSentenceIndex + 1
            let endIndex = min(startIndex + preloadCount, sentences.count)
            
            // 计算需要预载的索引 (未缓存且不在队列中)
            // 注意：这里简化为只检查缓存，每次都刷新队列以确保顺序优先
            let neededIndices = (startIndex..<endIndex).filter { index in
                cachedAudio(for: index) == nil
            }

            if !neededIndices.isEmpty {
                // 更新队列：覆盖为当前最需要的
                updatePreloadQueue(neededIndices)
                // 启动队列处理
                processPreloadQueue()
            } else {
                // 当前段落都OK了，检查下一章
                checkAndPreloadNextChapter()
            }
        } else {
            checkAndPreloadNextChapter()
        }
    }
    
    // MARK: - 处理预载队列 (并发下载 + 顺序优先)
    private func processPreloadQueue() {
        guard !getIsPreloading() else { return }

        setIsPreloading(true)

        Task { [weak self] in
            guard let self = self else { return }

            await withTaskGroup(of: Void.self) { group in
                var activeDownloads = 0
                var queue = self.dequeuePreloadQueue()
                var queueIndex = 0

                while queueIndex < queue.count || activeDownloads > 0 {
                    // 检查是否被停止
                    if !self.getIsPreloading() {
                        group.cancelAll()
                        break
                    }

                    // 启动新的下载任务（在并发限制内）
                    while activeDownloads < self.maxConcurrentDownloads && queueIndex < queue.count {
                        let index = queue[queueIndex]
                        queueIndex += 1

                        // 跳过已缓存的
                        if self.cachedAudio(for: index) != nil {
                            continue
                        }

                        activeDownloads += 1

                        group.addTask { [weak self] in
                            guard let self = self else { return }
                            await self.downloadAudioWithRetry(at: index)
                        }
                    }

                    // 等待至少一个任务完成
                    if activeDownloads > 0 {
                        await group.next()
                        activeDownloads -= 1
                    }
                }
            }

            self.setIsPreloading(false)

            // 队列空了，检查下一章或处理新加入的任务
            if self.hasPendingPreloadQueue() {
                self.processPreloadQueue()
            } else {
                await MainActor.run {
                    self.checkAndPreloadNextChapter()
                }
            }
        }
    }
    
    // MARK: - 带重试的下载
    private func downloadAudioWithRetry(at index: Int) async {
        for attempt in 0...maxPreloadRetries {
            // 检查是否还需要下载 (可能用户已经切走了)
            if !getIsPreloading() { return }
            
            let success = await downloadAudio(at: index)
            if success {
                return
            }
            
            if attempt < maxPreloadRetries {
                logger.log("⚠️ 预载重试 \(attempt + 1)/\(maxPreloadRetries) - 索引: \(index)", category: "TTS")
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 失败延迟 1s
            }
        }
        logger.log("❌ 预载最终失败 - 索引: \(index)", category: "TTS错误")
    }
    
    // MARK: - 单个下载实现
    private func downloadAudio(at index: Int) async -> Bool {
        guard index < sentences.count else { return false }
        let sentence = sentences[index]
        
        // 跳过纯标点
        if isPunctuationOnly(sentence) {
            await MainActor.run {
                preloadedIndices.insert(index)
            }
            return true
        }
        
        let speechRate = UserPreferences.shared.speechRate
        guard let encodedText = sentence.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return false }
        
        let urlString = "\(UserPreferences.shared.serverURL)/api/\(APIService.apiVersion)/tts?accessToken=\(UserPreferences.shared.accessToken)&id=\(UserPreferences.shared.selectedTTSId)&speakText=\(encodedText)&speechRate=\(speechRate)"
        
        guard let url = URL(string: urlString) else { return false }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            return await MainActor.run {
                // 检查HTTP响应
                if validateAudioData(data, response: response) {
                    cacheAudio(data, for: index)
                    preloadedIndices.insert(index)
                    logger.log("✅ 顺序预载成功 - 索引: \(index), 大小: \(data.count)", category: "TTS")
                    return true
                } else {
                    return false
                }
            }
        } catch {
            logger.log("预载网络错误: \(error)", category: "TTS错误")
            return false
        }
    }
    
    private func playAudioWithData(data: Data) {
        do {
            // 播放正式音频前，停止静音保活
            stopKeepAlive()
            
            // 使用 AVAudioPlayer 播放下载的数据
            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.delegate = self
            audioPlayer?.volume = 1.0
            
            logger.log("创建 AVAudioPlayer 成功", category: "TTS")
            logger.log("音频时长: \(audioPlayer?.duration ?? 0) 秒", category: "TTS")
            logger.log("音频格式: \(audioPlayer?.format.description ?? "unknown")", category: "TTS")
            
            let success = audioPlayer?.play() ?? false
            if success {
                logger.log("✅ 音频开始播放", category: "TTS")
                isLoading = false
                // 延长后台任务
                beginBackgroundTask()
            } else {
                logger.log("❌ 音频播放失败，跳过当前段落", category: "TTS错误")
                isLoading = false
                // 错误恢复：跳到下一段
                currentSentenceIndex += 1
                speakNextSentence()
            }
        } catch {
            logger.log("❌ 创建 AVAudioPlayer 失败: \(error.localizedDescription)", category: "TTS错误")
            logger.log("错误详情: \(error)", category: "TTS错误")
            isLoading = false
            // 错误恢复：跳到下一段
            logger.log("⚠️ 音频解码失败，尝试下一段", category: "TTS")
            currentSentenceIndex += 1
            speakNextSentence()
        }
    }
    
    
    // MARK: - 暂停
    func pause() {
        logger.log("收到暂停命令 - isPlaying: \(isPlaying), isPaused: \(isPaused), audioPlayer: \(audioPlayer != nil)", category: "TTS")
        
        if isPlaying && !isPaused {
            if let player = audioPlayer {
                player.pause()
                isPaused = true
                logger.log("✅ TTS 暂停", category: "TTS")
                
                // 暂停时启动保活，防止 App 被挂起
                startKeepAlive()
                
                updatePlaybackRate()
            } else {
                logger.log("⚠️ audioPlayer 不存在，无法暂停", category: "TTS")
            }
        } else if isPaused {
            logger.log("TTS 已经处于暂停状态", category: "TTS")
        } else {
            logger.log("TTS 未在播放，无法暂停", category: "TTS")
        }
    }
    
    // MARK: - 继续
    func resume() {
        logger.log("收到恢复命令 - isPlaying: \(isPlaying), isPaused: \(isPaused), audioPlayer: \(audioPlayer != nil)", category: "TTS")
        
        if isPlaying && isPaused {
            // 检查 audioPlayer 是否存在
            if let player = audioPlayer {
                player.play()
                isPaused = false
                logger.log("✅ TTS 恢复播放", category: "TTS")
                updatePlaybackRate()
            } else {
                // audioPlayer 不存在，重新播放当前句子
                logger.log("⚠️ audioPlayer 不存在，重新播放当前句子", category: "TTS")
                isPaused = false
                speakNextSentence()
            }
        } else if !isPlaying {
            // 如果已经停止，重新开始
            logger.log("TTS 未在播放，重新开始", category: "TTS")
            isPlaying = true
            isPaused = false
            speakNextSentence()
        } else {
            // isPlaying = true 但 isPaused = false，已经在播放中
            logger.log("TTS 已经在播放中", category: "TTS")
        }
    }
    
    // MARK: - 检查当前章节是否预载完成，并预载下一章
    private func checkAndPreloadNextChapter(force: Bool = false) {
        // 如果已经在预载下一章，跳过
        guard nextChapterSentences.isEmpty else {
            return
        }
        
        guard currentChapterIndex < chapters.count - 1 else {
            return
        }
        
        // 章节切换后强制预载下一章，避免切换时卡顿
        if force {
            logger.log("章节切换后立即预载下一章", category: "TTS")
            preloadNextChapter()
            return
        }

        // 计算进度百分比
        let progress = Double(currentSentenceIndex) / Double(max(sentences.count, 1))

        // 当播放到章节的 50% 时，开始预载下一章
        // 或者剩余段落少于用户设置的预载段数时也开始预载（确保跨章节保持预读数量）
        let remainingSentences = sentences.count - currentSentenceIndex
        let preloadCount = UserPreferences.shared.ttsPreloadCount

        if progress >= 0.5 || (preloadCount > 0 && remainingSentences <= preloadCount) {
            logger.log("📖 播放进度 \(Int(progress * 100))%，剩余 \(remainingSentences) 段，触发预载下一章", category: "TTS")
            preloadNextChapter()
        }
    }

    // MARK: - 预载下一章
    private func preloadNextChapter() {
        // 如果已经在预载下一章或已有下一章数据，跳过
        guard nextChapterSentences.isEmpty else { return }
        guard currentChapterIndex < chapters.count - 1 else { return }
        
        let nextChapterIndex = currentChapterIndex + 1
        logger.log("开始预载下一章: \(nextChapterIndex)", category: "TTS")
        
        // 预载下一章的章节名
        preloadNextChapterTitle(chapterIndex: nextChapterIndex)
        
        Task {
            do {
                let content = try await APIService.shared.fetchChapterContent(
                    bookUrl: bookUrl,
                    bookSourceUrl: bookSourceUrl,
                    index: nextChapterIndex
                )
                
                await MainActor.run {
                    // 分段
                    nextChapterSentences = splitTextIntoSentences(content)
                    logger.log("下一章分段完成，共 \(nextChapterSentences.count) 段", category: "TTS")
                    
                    // 预载下一章的前几个段落（根据用户的预载设置）
                    let userPreloadCount = UserPreferences.shared.ttsPreloadCount
                    let preloadCount = min(max(userPreloadCount, 3), nextChapterSentences.count)  // 至少3段，最多到用户设置的值
                    logger.log("开始预载下一章的前 \(preloadCount) 段音频", category: "TTS")
                    
                    for i in 0..<preloadCount {
                        preloadNextChapterAudio(at: i)
                    }
                }
            } catch {
                logger.log("预载下一章失败: \(error)", category: "TTS错误")
            }
        }
    }
    
    // MARK: - 预载下一章的章节名
    private func preloadNextChapterTitle(chapterIndex: Int) {
        guard chapterIndex < chapters.count else { return }
        guard nextChapterCache[-1] == nil else { return }
        
        let chapterTitle = chapters[chapterIndex].title
        let speechRate = UserPreferences.shared.speechRate
        let ttsId = UserPreferences.shared.selectedTTSId
        
        guard !ttsId.isEmpty else { return }
        
        logger.log("预载下一章章节名: \(chapterTitle)", category: "TTS")
        
        // 构建 TTS 音频 URL
        guard let audioURL = APIService.shared.buildTTSAudioURL(
            ttsId: ttsId,
            text: chapterTitle,
            speechRate: speechRate
        ) else {
            logger.log("构建下一章章节名音频 URL 失败", category: "TTS错误")
            return
        }
        
        Task {
            do {
                let (data, response) = try await URLSession.shared.data(from: audioURL)

                await MainActor.run {
                    if validateAudioData(data, response: response) {
                        cacheNextChapterAudio(data, for: -1)
                        logger.log("✅ 下一章章节名预载成功，大小: \(data.count) 字节", category: "TTS")
                    } else {
                        logger.log("⚠️ 下一章章节名预载失败，数据格式或体积异常 (大小: \(data.count) 字节)", category: "TTS")
                    }
                }
            } catch {
                logger.log("下一章章节名预载失败: \(error)", category: "TTS错误")
            }
        }
    }
    
    // MARK: - 预载下一章的音频
    private func preloadNextChapterAudio(at index: Int) {
        guard index < nextChapterSentences.count else { return }
        guard cachedNextChapterAudio(for: index) == nil else { return }
        
        let sentence = nextChapterSentences[index]
        let speechRate = UserPreferences.shared.speechRate
        let ttsId = UserPreferences.shared.selectedTTSId
        
        guard !ttsId.isEmpty else { return }
        guard let encodedText = sentence.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return }
        
        let urlString = "\(UserPreferences.shared.serverURL)/api/\(APIService.apiVersion)/tts?accessToken=\(UserPreferences.shared.accessToken)&id=\(ttsId)&speakText=\(encodedText)&speechRate=\(speechRate)"
        
        guard let url = URL(string: urlString) else { return }
        
        logger.log("预载下一章音频 - 索引: \(index)", category: "TTS")
        
        Task {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                
                let contentType = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? "unknown"

                await MainActor.run {
                    if validateAudioData(data, response: response) {
                        cacheNextChapterAudio(data, for: index)
                        logger.log("✅ 下一章预载成功 - 索引: \(index), 大小: \(data.count) 字节, Content-Type: \(contentType)", category: "TTS")
                    } else {
                        logger.log("⚠️ 下一章预载音频无效，Content-Type: \(contentType), 大小: \(data.count) 字节", category: "TTS")
                    }
                }
            } catch {
                logger.log("下一章预载失败 - 索引: \(index), 错误: \(error)", category: "TTS错误")
            }
        }
    }
    
    // MARK: - 停止
    func stop() {
        stopKeepAlive()
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        isPaused = false
        currentSentenceIndex = 0
        sentences = []
        isLoading = false
        // 清理缓存
        clearAudioCache()
        updatePreloadQueue([])
        setIsPreloading(false)
        clearNextChapterCache()
        nextChapterSentences.removeAll()
        coverArtwork = nil  // 清理封面缓存
        // 结束后台任务
        endBackgroundTask()
        logger.log("TTS 停止", category: "TTS")
    }
    
    // MARK: - 下一章
    func nextChapter() {
        guard currentChapterIndex < chapters.count - 1 else { return }
        currentChapterIndex += 1
        onChapterChange?(currentChapterIndex)
        loadAndReadChapter()
    }
    
    // MARK: - 上一章
    func previousChapter() {
        guard currentChapterIndex > 0 else { return }
        currentChapterIndex -= 1
        onChapterChange?(currentChapterIndex)
        loadAndReadChapter()
    }
    
    // MARK: - 加载并朗读章节
    private func loadAndReadChapter() {
        // 检查是否有预载的下一章数据
        if !nextChapterSentences.isEmpty {
            logger.log("使用已预载的下一章数据", category: "TTS")
            
            // 停止当前播放
            audioPlayer?.stop()
            audioPlayer = nil
            
            // 使用预载的数据
            sentences = nextChapterSentences
            totalSentences = sentences.count
            currentSentenceIndex = 0

            // 将下一章的缓存移动到当前章节（包括章节名索引-1和正文段落）
            preloadedIndices = moveNextChapterCacheToCurrent()

            // 清空下一章缓存
            nextChapterSentences.removeAll()
            
            isPlaying = true
            isPaused = false
            isLoading = false
            
            if currentChapterIndex < chapters.count {
                updateNowPlayingInfo(chapterTitle: chapters[currentChapterIndex].title)
            }
            
            // 章节切换后提前准备下一章，避免章节衔接等待
            checkAndPreloadNextChapter(force: true)

            // 先朗读章节名
            speakChapterTitle()
            
            return
        }
        
        // 没有预载数据，从缓存或网络加载
        logger.log("⚠️ 下一章未预载完成，尝试从缓存或网络加载", category: "TTS")
        
        // 停止当前播放
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
                        logger.log("✅ 从缓存加载章节内容，耗时: \(Int(loadTime * 1000))ms", category: "TTS")
                    } else {
                        logger.log("⏳ 从网络加载章节内容，耗时: \(String(format: "%.2f", loadTime))s", category: "TTS")
                    }
                    
                    sentences = splitTextIntoSentences(content)
                    totalSentences = sentences.count
                    currentSentenceIndex = 0

                    // 清空当前章节的缓存
                    clearAudioCache()
                    updatePreloadQueue([])
                    setIsPreloading(false)
                    preloadedIndices.removeAll()
                    
                    isPlaying = true
                    isPaused = false
                    
                    if currentChapterIndex < chapters.count {
                        updateNowPlayingInfo(chapterTitle: chapters[currentChapterIndex].title)
                    }
                    
                    // 章节切换后提前准备下一章，避免章节衔接等待
                    checkAndPreloadNextChapter(force: true)

                    // 先朗读章节名
                    speakChapterTitle()
                }
            } catch {
                logger.log("加载章节失败: \(error)", category: "TTS错误")
            }
        }
    }
    
    // MARK: - 更新播放速率
    private func updatePlaybackRate() {
        var nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [String: Any]()
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying && !isPaused ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        endBackgroundTask()
        logger.log("TTSManager 销毁", category: "TTS")
    }
}

// MARK: - AVAudioPlayerDelegate
extension TTSManager: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        // AVAudioPlayer 的回调线程不保证在主线程，统一切换到主线程更新状态
        DispatchQueue.main.async {
            self.logger.log("音频播放完成 - 成功: \(flag)", category: "TTS")

            // 播放间隙启动保活
            self.startKeepAlive()

            // 如果正在朗读章节名，播放完后开始朗读内容
            if self.isReadingChapterTitle {
                self.isReadingChapterTitle = false
                self.speakNextSentence()
                return
            }

            if flag {
                // 播放下一句
                self.currentSentenceIndex += 1
                self.speakNextSentence()
            } else {
                self.logger.log("音频播放失败，跳过", category: "TTS错误")
                self.currentSentenceIndex += 1
                self.speakNextSentence()
            }
        }
    }
    
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        if let error = error {
            logger.log("❌ 音频解码错误: \(error.localizedDescription)", category: "TTS错误")
        }
        // 跳过这一句
        currentSentenceIndex += 1
        speakNextSentence()
    }
}
