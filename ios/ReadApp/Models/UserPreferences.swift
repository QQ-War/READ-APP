import Foundation
import SwiftUI
import CryptoKit
import CryptoKit

extension Notification.Name {
    static let accountChanged = Notification.Name("com.readapp.accountChanged")
}

class UserPreferences: ObservableObject {
    static let shared = UserPreferences()
    private static let progressQueueKey = DispatchSpecificKey<Void>()
    private let progressQueue: DispatchQueue = {
        let queue = DispatchQueue(label: "com.readapp.userprefs.progress", qos: .utility)
        queue.setSpecific(key: UserPreferences.progressQueueKey, value: ())
        return queue
    }()
    private var ttsProgressCache: [String: (Int, Int, Int)] = [:]
    private var ttsProgressFlushWorkItem: DispatchWorkItem?
    
    private static func sanitizeRefreshRate(_ value: Float, fallback: Float, min minValue: Float, max maxValue: Float) -> Float {
        guard value.isFinite else { return fallback }
        return max(minValue, min(maxValue, value))
    }

    @Published var apiBackend: ApiBackend {
        didSet {
            UserDefaults.standard.set(apiBackend.rawValue, forKey: "apiBackend")
            updateCurrentAccount { $0.apiBackend = apiBackend }
        }
    }

    @Published var serverURL: String {
        didSet {
            UserDefaults.standard.set(serverURL, forKey: "serverURL")
            updateCurrentAccount { $0.serverURL = serverURL }
        }
    }

    @Published var publicServerURL: String {
        didSet {
            UserDefaults.standard.set(publicServerURL, forKey: "publicServerURL")
            updateCurrentAccount { $0.publicServerURL = publicServerURL }
        }
    }

    struct UserAccount: Codable, Identifiable, Equatable {
        var id: String
        var username: String
        var serverURL: String
        var publicServerURL: String
        var apiBackend: ApiBackend
        
        // 账号/服务器相关的设置
        var selectedTTSId: String?
        var narrationTTSId: String?
        var dialogueTTSId: String?
        var speakerTTSMapping: [String: String]?
        var preferredSearchSourceUrls: [String]?
        
        var displayName: String {
            if username.isEmpty {
                return serverURL
            }
            return "\(username) (\(serverURL))"
        }
    }

    @Published var accounts: [UserAccount] {
        didSet {
            if let data = try? JSONEncoder().encode(accounts) {
                UserDefaults.standard.set(data, forKey: "userAccounts")
            }
        }
    }

    private func updateCurrentAccount(_ transform: (inout UserAccount) -> Void) {
        guard let id = currentAccountId,
              let index = accounts.firstIndex(where: { $0.id == id }) else { return }
        var account = accounts[index]
        transform(&account)
        accounts[index] = account
    }

    @Published var currentAccountId: String? {
        didSet {
            UserDefaults.standard.set(currentAccountId, forKey: "currentAccountId")
        }
    }

    @Published var accessToken: String {
        didSet {
            let accountKey = currentAccountId ?? "accessToken"
            KeychainHelper.shared.save(accessToken, service: "com.readapp.ios", account: accountKey)
        }
    }

    @Published var username: String {
        didSet {
            UserDefaults.standard.set(username, forKey: "username")
            updateCurrentAccount { $0.username = username }
        }
    }

    @Published var isLoggedIn: Bool {
        didSet {
            UserDefaults.standard.set(isLoggedIn, forKey: "isLoggedIn")
        }
    }

    @Published var fontSize: CGFloat {
        didSet {
            UserDefaults.standard.set(fontSize, forKey: "fontSize")
        }
    }

    @Published var progressFontSize: CGFloat {
        didSet {
            UserDefaults.standard.set(progressFontSize, forKey: "progressFontSize")
        }
    }

    @Published var readingBottomInset: CGFloat {
        didSet {
            UserDefaults.standard.set(readingBottomInset, forKey: "readingBottomInset")
        }
    }

    @Published var readingFontName: String {
        didSet {
            UserDefaults.standard.set(readingFontName, forKey: "readingFontName")
        }
    }

    @Published var lineSpacing: CGFloat {
        didSet {
            UserDefaults.standard.set(lineSpacing, forKey: "lineSpacing")
        }
    }

    @Published var speechRate: Double {
        didSet {
            UserDefaults.standard.set(speechRate, forKey: "speechRate")
        }
    }

    /// 旁白使用的 TTS 引擎 ID（默认回落到 selectedTTSId）
    @Published var narrationTTSId: String {
        didSet {
            UserDefaults.standard.set(narrationTTSId, forKey: "narrationTTSId")
            updateCurrentAccount { $0.narrationTTSId = narrationTTSId }
        }
    }

    /// 默认对话使用的 TTS 引擎 ID（默认回落到 selectedTTSId）
    @Published var dialogueTTSId: String {
        didSet {
            UserDefaults.standard.set(dialogueTTSId, forKey: "dialogueTTSId")
            updateCurrentAccount { $0.dialogueTTSId = dialogueTTSId }
        }
    }

    /// 发言人名称 -> TTS ID
    @Published var speakerTTSMapping: [String: String] {
        didSet {
            if let data = try? JSONEncoder().encode(speakerTTSMapping) {
                UserDefaults.standard.set(data, forKey: "speakerTTSMapping")
            }
            updateCurrentAccount { $0.speakerTTSMapping = speakerTTSMapping }
        }
    }

    /// 发言触发词正则（匹配引号外上下文）
    @Published var speakerTriggerRegexes: [String] {
        didSet {
            if let data = try? JSONEncoder().encode(speakerTriggerRegexes) {
                UserDefaults.standard.set(data, forKey: "speakerTriggerRegexes")
            }
        }
    }

    @Published var selectedTTSId: String {
        didSet {
            UserDefaults.standard.set(selectedTTSId, forKey: "selectedTTSId")
            updateCurrentAccount { $0.selectedTTSId = selectedTTSId }
        }
    }

    @Published var useSystemTTS: Bool {
        didSet {
            UserDefaults.standard.set(useSystemTTS, forKey: "useSystemTTS")
        }
    }

    @Published var systemVoiceId: String {
        didSet {
            UserDefaults.standard.set(systemVoiceId, forKey: "systemVoiceId")
        }
    }

    @Published var bookshelfSortByRecent: Bool {
        didSet {
            UserDefaults.standard.set(bookshelfSortByRecent, forKey: "bookshelfSortByRecent")
        }
    }

    @Published var searchSourcesFromBookshelf: Bool {
        didSet {
            UserDefaults.standard.set(searchSourcesFromBookshelf, forKey: "searchSourcesFromBookshelf")
        }
    }

    @Published var preferredSearchSourceUrls: [String] {
        didSet {
            UserDefaults.standard.set(preferredSearchSourceUrls, forKey: "preferredSearchSourceUrls")
            updateCurrentAccount { $0.preferredSearchSourceUrls = preferredSearchSourceUrls }
        }
    }

    @Published var ttsPreloadCount: Int {
        didSet {
            UserDefaults.standard.set(ttsPreloadCount, forKey: "ttsPreloadCount")
        }
    }

    @Published var readingMode: ReadingMode {
        didSet {
            UserDefaults.standard.set(readingMode.rawValue, forKey: "readingMode")
        }
    }

    @Published var mangaReaderMode: MangaReaderMode {
        didSet {
            UserDefaults.standard.set(mangaReaderMode.rawValue, forKey: "mangaReaderMode")
        }
    }

    @Published var pageHorizontalMargin: CGFloat {
        didSet {
            UserDefaults.standard.set(pageHorizontalMargin, forKey: "pageHorizontalMargin")
        }
    }

    @Published var pageInterSpacing: CGFloat {
        didSet {
            UserDefaults.standard.set(pageInterSpacing, forKey: "pageInterSpacing")
        }
    }

    @Published var pageTurningMode: PageTurningMode {
        didSet {
            UserDefaults.standard.set(pageTurningMode.rawValue, forKey: "pageTurningMode")
        }
    }

    @Published var readingTheme: ReadingTheme {
        didSet {
            UserDefaults.standard.set(readingTheme.rawValue, forKey: "readingTheme")
            updateInterfaceStyle()
        }
    }

    private func updateInterfaceStyle() {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            for window in windowScene.windows {
                window.overrideUserInterfaceStyle = readingTheme.interfaceStyle
            }
        }
    }

    @Published var lockPageOnTTS: Bool {
        didSet {
            UserDefaults.standard.set(lockPageOnTTS, forKey: "lockPageOnTTS")
        }
    }

    @Published var ttsSentenceChunkLimit: Int {
        didSet {
            UserDefaults.standard.set(ttsSentenceChunkLimit, forKey: "ttsSentenceChunkLimit")
        }
    }

    /// 手动标记为漫画的书籍 URL 集合
    @Published var manualMangaUrls: Set<String> {
        didSet {
            let array = Array(manualMangaUrls)
            UserDefaults.standard.set(array, forKey: "manualMangaUrls")
        }
    }

    /// 是否开启详细日志（用于调试漫画等问题）
    @Published var isVerboseLoggingEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isVerboseLoggingEnabled, forKey: "isVerboseLoggingEnabled")
        }
    }

    @Published var isInfiniteScrollEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isInfiniteScrollEnabled, forKey: "isInfiniteScrollEnabled")
        }
    }

    @Published var verticalThreshold: CGFloat {
        didSet {
            UserDefaults.standard.set(verticalThreshold, forKey: "verticalThreshold")
        }
    }

    @Published var verticalDampingFactor: CGFloat {
        didSet {
            UserDefaults.standard.set(verticalDampingFactor, forKey: "verticalDampingFactor")
        }
    }

    @Published var mangaMaxZoom: CGFloat {
        didSet {
            UserDefaults.standard.set(mangaMaxZoom, forKey: "mangaMaxZoom")
        }
    }

    @Published var mangaChapterZoomEnabled: Bool {
        didSet {
            UserDefaults.standard.set(mangaChapterZoomEnabled, forKey: "mangaChapterZoomEnabled")
        }
    }

    @Published var infiniteScrollSwitchThreshold: CGFloat {
        didSet {
            UserDefaults.standard.set(infiniteScrollSwitchThreshold, forKey: "infiniteScrollSwitchThreshold")
        }
    }

    @Published var ttsFollowCooldown: TimeInterval {
        didSet {
            UserDefaults.standard.set(ttsFollowCooldown, forKey: "ttsFollowCooldown")
        }
    }

    /// 是否强制使用服务器代理加载漫画图片
    @Published var forceMangaProxy: Bool {
        didSet {
            UserDefaults.standard.set(forceMangaProxy, forKey: "forceMangaProxy")
        }
    }

    /// 是否开启漫画图片反爬适配
    @Published var isMangaAntiScrapingEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isMangaAntiScrapingEnabled, forKey: "isMangaAntiScrapingEnabled")
        }
    }

    /// 启用的反爬站点列表
    @Published var mangaAntiScrapingEnabledSites: Set<String> {
        didSet {
            UserDefaults.standard.set(Array(mangaAntiScrapingEnabledSites), forKey: "mangaAntiScrapingEnabledSites")
        }
    }

    /// 是否开启文字书籍自动离线缓存
    @Published var isTextAutoCacheEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isTextAutoCacheEnabled, forKey: "isTextAutoCacheEnabled")
        }
    }

    /// 是否开启漫画图片自动离线缓存
    @Published var isMangaAutoCacheEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isMangaAutoCacheEnabled, forKey: "isMangaAutoCacheEnabled")
        }
    }

    /// 是否开启漫画后台预加载（提升翻页流畅度）
    @Published var isMangaPreloadEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isMangaPreloadEnabled, forKey: "isMangaPreloadEnabled")
        }
    }

    /// 漫画图片预加载数量（当前章节向前加载多少张）
    @Published var mangaPrefetchCount: Int {
        didSet {
            UserDefaults.standard.set(mangaPrefetchCount, forKey: "mangaPrefetchCount")
        }
    }

    /// 漫画图片内存缓存上限（MB）
    @Published var mangaMemoryCacheMB: Int {
        didSet {
            UserDefaults.standard.set(mangaMemoryCacheMB, forKey: "mangaMemoryCacheMB")
        }
    }

    /// 漫画图片最近保留数量（内存）
    @Published var mangaRecentKeepCount: Int {
        didSet {
            UserDefaults.standard.set(mangaRecentKeepCount, forKey: "mangaRecentKeepCount")
        }
    }

    /// 漫画图片并发下载数量
    @Published var mangaImageMaxConcurrent: Int {
        didSet {
            UserDefaults.standard.set(mangaImageMaxConcurrent, forKey: "mangaImageMaxConcurrent")
        }
    }

    /// 漫画图片请求超时（秒）
    @Published var mangaImageTimeout: TimeInterval {
        didSet {
            UserDefaults.standard.set(mangaImageTimeout, forKey: "mangaImageTimeout")
        }
    }

    /// 静态阅读时的刷新率限制 (iOS 15+ ProMotion)
    @Published var staticRefreshRate: Float {
        didSet {
            let safeMax = Self.sanitizeRefreshRate(staticRefreshRateMax, fallback: 30, min: 10, max: 60)
            let clamped = Self.sanitizeRefreshRate(staticRefreshRate, fallback: min(30, safeMax), min: 10, max: safeMax)
            if clamped != staticRefreshRate {
                staticRefreshRate = clamped
                return
            }
            UserDefaults.standard.set(staticRefreshRate, forKey: "staticRefreshRate")
            DisplayRateManager.shared.refresh()
        }
    }

    /// 静态阅读时的刷新率上限 (iOS 15+ ProMotion)
    @Published var staticRefreshRateMax: Float {
        didSet {
            let clamped = Self.sanitizeRefreshRate(staticRefreshRateMax, fallback: 30, min: 10, max: 60)
            if clamped != staticRefreshRateMax {
                staticRefreshRateMax = clamped
                return
            }
            if staticRefreshRate > staticRefreshRateMax {
                staticRefreshRate = staticRefreshRateMax
            }
            UserDefaults.standard.set(staticRefreshRateMax, forKey: "staticRefreshRateMax")
            DisplayRateManager.shared.refresh()
        }
    }

    /// 是否开启进度条动态颜色 (exclusionBlendMode)
    @Published var isProgressDynamicColorEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isProgressDynamicColorEnabled, forKey: "isProgressDynamicColorEnabled")
        }
    }

    /// 是否开启液态玻璃效果背景
    @Published var isLiquidGlassEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isLiquidGlassEnabled, forKey: "isLiquidGlassEnabled")
        }
    }

    /// 液态玻璃材质不透明度 (0.0 - 1.0)
    @Published var liquidGlassOpacity: Double {
        didSet {
            UserDefaults.standard.set(liquidGlassOpacity, forKey: "liquidGlassOpacity")
        }
    }

    /// 设置项顺序
    @Published var settingsOrder: [String] {
        didSet {
            UserDefaults.standard.set(settingsOrder, forKey: "settingsOrder")
        }
    }

    // TTS进度记录：bookUrl -> (chapterIndex, sentenceIndex, sentenceOffset)
    private static func decodeTTSProgress(from data: Data?) -> [String: (Int, Int, Int)] {
        guard let data,
              let dict = try? JSONDecoder().decode([String: [Int]].self, from: data) else {
            return [:]
        }
        return dict.mapValues {
            if $0.count >= 3 { return ($0[0], $0[1], $0[2]) }
            if $0.count >= 2 { return ($0[0], $0[1], 0) }
            return ($0.first ?? 0, 0, 0)
        }
    }

    private func flushTTSProgressLocked() {
        ttsProgressFlushWorkItem?.cancel()
        ttsProgressFlushWorkItem = nil
        let dict = ttsProgressCache.mapValues { [$0.0, $0.1, $0.2] }
        if let data = try? JSONEncoder().encode(dict) {
            UserDefaults.standard.set(data, forKey: "ttsProgress")
        }
    }

    private func scheduleTTSProgressFlushLocked(delay: TimeInterval = 1.5) {
        ttsProgressFlushWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.flushTTSProgressLocked()
        }
        ttsProgressFlushWorkItem = workItem
        progressQueue.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func syncOnProgressQueue(_ block: () -> Void) {
        if DispatchQueue.getSpecific(key: Self.progressQueueKey) != nil {
            block()
        } else {
            progressQueue.sync(execute: block)
        }
    }

    // 阅读进度记录：bookUrl -> (chapterIndex, pageIndex, bodyCharIndex, timestamp)
    private var readingProgress: [String: (Int, Int, Int, Int)] {
        get {
            if let data = UserDefaults.standard.data(forKey: "readingProgress"),
               let dict = try? JSONDecoder().decode([String: [Int]].self, from: data) {
                return dict.mapValues {
                    if $0.count >= 4 {
                        return ($0[0], $0[1], $0[2], $0[3])
                    } else if $0.count >= 3 {
                        return ($0[0], $0[1], $0[2], 0)
                    }
                    return ($0.first ?? 0, 0, $0.count > 1 ? $0[1] : 0, 0)
                }
            }
            return [:]
        }
        set {
            let dict = newValue.mapValues { [$0.0, $0.1, $0.2, $0.3] }
            if let data = try? JSONEncoder().encode(dict) {
                UserDefaults.standard.set(data, forKey: "readingProgress")
            }
        }
    }

    func saveTTSProgress(bookUrl: String, chapterIndex: Int, sentenceIndex: Int, sentenceOffset: Int = 0) {
        guard !bookUrl.isEmpty else { return }
        progressQueue.async {
            self.ttsProgressCache[bookUrl] = (chapterIndex, sentenceIndex, sentenceOffset)
            self.scheduleTTSProgressFlushLocked()
        }
    }

    func flushTTSProgressNow() {
        syncOnProgressQueue {
            flushTTSProgressLocked()
        }
    }

    func getTTSProgress(bookUrl: String) -> (chapterIndex: Int, sentenceIndex: Int, sentenceOffset: Int)? {
        progressQueue.sync { ttsProgressCache[bookUrl] }
    }

    func saveReadingProgress(bookUrl: String, chapterIndex: Int, pageIndex: Int, bodyCharIndex: Int) {
        var progress = readingProgress
        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        progress[bookUrl] = (chapterIndex, pageIndex, bodyCharIndex, timestamp)
        readingProgress = progress
    }

    func getReadingProgress(bookUrl: String) -> (chapterIndex: Int, pageIndex: Int, bodyCharIndex: Int, timestamp: Int)? {
        return readingProgress[bookUrl]
    }

    private init() {
        // 初始化所有属性
        let savedFontSize = CGFloat(UserDefaults.standard.float(forKey: "fontSize"))
        self.fontSize = savedFontSize == 0 ? 18 : savedFontSize

        let savedProgressFontSize = CGFloat(UserDefaults.standard.float(forKey: "progressFontSize"))
        self.progressFontSize = savedProgressFontSize == 0 ? 12 : savedProgressFontSize

        let savedBottomInset = CGFloat(UserDefaults.standard.float(forKey: "readingBottomInset"))
        self.readingBottomInset = savedBottomInset == 0 ? 40 : savedBottomInset

        self.readingFontName = UserDefaults.standard.string(forKey: "readingFontName") ?? ""

        let savedLineSpacing = CGFloat(UserDefaults.standard.float(forKey: "lineSpacing"))
        self.lineSpacing = savedLineSpacing == 0 ? 8 : savedLineSpacing

        let savedMargin = CGFloat(UserDefaults.standard.float(forKey: "pageHorizontalMargin"))
        self.pageHorizontalMargin = savedMargin == 0 ? 6 : savedMargin

        let savedInterSpacing = CGFloat(UserDefaults.standard.float(forKey: "pageInterSpacing"))
        self.pageInterSpacing = savedInterSpacing == 0 ? 12 : savedInterSpacing

        self.lockPageOnTTS = UserDefaults.standard.bool(forKey: "lockPageOnTTS")

        let savedManualMangaUrls = UserDefaults.standard.stringArray(forKey: "manualMangaUrls") ?? []
        self.manualMangaUrls = Set(savedManualMangaUrls)

        self.isVerboseLoggingEnabled = UserDefaults.standard.bool(forKey: "isVerboseLoggingEnabled")
        self.isInfiniteScrollEnabled = UserDefaults.standard.object(forKey: "isInfiniteScrollEnabled") as? Bool ?? true
        let savedVerticalThreshold = CGFloat(UserDefaults.standard.float(forKey: "verticalThreshold"))
        self.verticalThreshold = savedVerticalThreshold == 0 ? 80 : savedVerticalThreshold
        let savedVerticalDampingFactor = CGFloat(UserDefaults.standard.float(forKey: "verticalDampingFactor"))
        self.verticalDampingFactor = savedVerticalDampingFactor == 0 ? 0.15 : savedVerticalDampingFactor
        let savedMangaMaxZoom = CGFloat(UserDefaults.standard.float(forKey: "mangaMaxZoom"))
        self.mangaMaxZoom = savedMangaMaxZoom == 0 ? 3.0 : savedMangaMaxZoom
        self.mangaChapterZoomEnabled = UserDefaults.standard.object(forKey: "mangaChapterZoomEnabled") as? Bool ?? true
        let savedInfiniteSwitchThreshold = CGFloat(UserDefaults.standard.float(forKey: "infiniteScrollSwitchThreshold"))
        self.infiniteScrollSwitchThreshold = savedInfiniteSwitchThreshold == 0 ? 120 : savedInfiniteSwitchThreshold
        let savedTtsFollowCooldown = UserDefaults.standard.double(forKey: "ttsFollowCooldown")
        self.ttsFollowCooldown = savedTtsFollowCooldown == 0 ? 3.0 : savedTtsFollowCooldown
        self.forceMangaProxy = UserDefaults.standard.bool(forKey: "forceMangaProxy")
        self.isMangaAntiScrapingEnabled = UserDefaults.standard.object(forKey: "isMangaAntiScrapingEnabled") as? Bool ?? true
        let savedAntiScrapingSites = UserDefaults.standard.stringArray(forKey: "mangaAntiScrapingEnabledSites")
        if let savedAntiScrapingSites, !savedAntiScrapingSites.isEmpty {
            self.mangaAntiScrapingEnabledSites = Set(savedAntiScrapingSites)
        } else {
            self.mangaAntiScrapingEnabledSites = Set(MangaAntiScrapingService.profileKeys)
        }
        self.isTextAutoCacheEnabled = UserDefaults.standard.object(forKey: "isTextAutoCacheEnabled") as? Bool ?? true
        self.isMangaAutoCacheEnabled = UserDefaults.standard.object(forKey: "isMangaAutoCacheEnabled") as? Bool ?? true
        self.isMangaPreloadEnabled = UserDefaults.standard.object(forKey: "isMangaPreloadEnabled") as? Bool ?? true
        let savedPrefetchCount = UserDefaults.standard.integer(forKey: "mangaPrefetchCount")
        self.mangaPrefetchCount = savedPrefetchCount == 0 ? 6 : max(0, savedPrefetchCount)
        let savedMemoryCacheMB = UserDefaults.standard.integer(forKey: "mangaMemoryCacheMB")
        self.mangaMemoryCacheMB = savedMemoryCacheMB == 0 ? 120 : max(20, savedMemoryCacheMB)
        let savedRecentKeepCount = UserDefaults.standard.integer(forKey: "mangaRecentKeepCount")
        self.mangaRecentKeepCount = savedRecentKeepCount == 0 ? 24 : max(0, savedRecentKeepCount)
        let savedMangaConcurrent = UserDefaults.standard.integer(forKey: "mangaImageMaxConcurrent")
        self.mangaImageMaxConcurrent = savedMangaConcurrent == 0 ? 2 : max(1, savedMangaConcurrent)
        let savedMangaTimeout = UserDefaults.standard.double(forKey: "mangaImageTimeout")
        self.mangaImageTimeout = savedMangaTimeout == 0 ? 30 : max(5, savedMangaTimeout)

        let savedRefreshRate = UserDefaults.standard.float(forKey: "staticRefreshRate")
        let savedRefreshRateMax = UserDefaults.standard.float(forKey: "staticRefreshRateMax")
        let initialStaticRefreshRateMax: Float = savedRefreshRateMax == 0
            ? 30
            : Self.sanitizeRefreshRate(savedRefreshRateMax, fallback: 30, min: 10, max: 60)
        self.staticRefreshRateMax = initialStaticRefreshRateMax
        let defaultStaticRate: Float = min(30, initialStaticRefreshRateMax)
        self.staticRefreshRate = savedRefreshRate == 0
            ? defaultStaticRate
            : Self.sanitizeRefreshRate(savedRefreshRate, fallback: defaultStaticRate, min: 10, max: initialStaticRefreshRateMax)

        self.isProgressDynamicColorEnabled = UserDefaults.standard.object(forKey: "isProgressDynamicColorEnabled") as? Bool ?? true
        self.isLiquidGlassEnabled = UserDefaults.standard.bool(forKey: "isLiquidGlassEnabled")
        
        let savedLiquidOpacity = UserDefaults.standard.double(forKey: "liquidGlassOpacity")
        self.liquidGlassOpacity = (savedLiquidOpacity == 0) ? 0.8 : savedLiquidOpacity

        let defaultOrder = ["display", "reading", "cache", "tts", "content", "rss"]
        let savedOrder = UserDefaults.standard.stringArray(forKey: "settingsOrder") ?? defaultOrder
        // 过滤掉不再存在的项，并追加新增的项
        var finalOrder = savedOrder.filter { key in SettingItem(rawValue: key) != nil }
        let allItems = SettingItem.allCases.map { $0.rawValue }
        for item in allItems {
            if !finalOrder.contains(item) {
                finalOrder.append(item)
            }
        }
        self.settingsOrder = finalOrder

        let savedChunk = UserDefaults.standard.integer(forKey: "ttsSentenceChunkLimit")
        self.ttsSentenceChunkLimit = savedChunk == 0 ? 600 : savedChunk

        let savedSpeechRate = UserDefaults.standard.double(forKey: "speechRate")
        self.speechRate = savedSpeechRate == 0 ? 100.0 : savedSpeechRate

        let accountsValue: [UserAccount]
        if let accountsData = UserDefaults.standard.data(forKey: "userAccounts"),
           let savedAccounts = try? JSONDecoder().decode([UserAccount].self, from: accountsData) {
            accountsValue = savedAccounts
        } else {
            accountsValue = []
        }
        let currentAccountIdValue = UserDefaults.standard.string(forKey: "currentAccountId")

        let rawServerURL = UserDefaults.standard.string(forKey: "serverURL") ?? ""
        let rawPublicURL = UserDefaults.standard.string(forKey: "publicServerURL") ?? ""
        let savedBackendRaw = UserDefaults.standard.string(forKey: "apiBackend")
        let detectedBackend = ApiBackendResolver.detect(from: rawServerURL)
        let apiBackendValue = (savedBackendRaw.flatMap { ApiBackend(rawValue: $0) }) ?? detectedBackend
        let serverURLValue = ApiBackendResolver.stripApiBasePath(rawServerURL)
        let publicServerURLValue = ApiBackendResolver.stripApiBasePath(rawPublicURL)

        let accountKey = currentAccountIdValue ?? "accessToken"
        let accessTokenValue = KeychainHelper.shared.read(service: "com.readapp.ios", account: accountKey) ?? UserDefaults.standard.string(forKey: "accessToken") ?? ""
        let usernameValue = UserDefaults.standard.string(forKey: "username") ?? ""
        let isLoggedInValue = UserDefaults.standard.bool(forKey: "isLoggedIn")

        let selectedTTSIdValue = UserDefaults.standard.string(forKey: "selectedTTSId") ?? ""
        let useSystemTTSValue = UserDefaults.standard.bool(forKey: "useSystemTTS")
        let systemVoiceIdValue = UserDefaults.standard.string(forKey: "systemVoiceId") ?? ""
        let narrationTTSIdValue = UserDefaults.standard.string(forKey: "narrationTTSId") ?? ""
        let dialogueTTSIdValue = UserDefaults.standard.string(forKey: "dialogueTTSId") ?? ""

        let speakerTTSMappingValue: [String: String]
        if let mappingData = UserDefaults.standard.data(forKey: "speakerTTSMapping"),
           let mapping = try? JSONDecoder().decode([String: String].self, from: mappingData) {
            speakerTTSMappingValue = mapping
        } else {
            speakerTTSMappingValue = [:]
        }
        let speakerTriggerRegexesValue: [String]
        if let regexData = UserDefaults.standard.data(forKey: "speakerTriggerRegexes"),
           let regexes = try? JSONDecoder().decode([String].self, from: regexData),
           !regexes.isEmpty {
            speakerTriggerRegexesValue = regexes
        } else {
            speakerTriggerRegexesValue = Self.defaultSpeakerTriggerRegexes
        }
        let bookshelfSortByRecentValue = UserDefaults.standard.bool(forKey: "bookshelfSortByRecent")
        let searchSourcesFromBookshelfValue = UserDefaults.standard.bool(forKey: "searchSourcesFromBookshelf")
        let preferredSearchSourceUrlsValue = UserDefaults.standard.stringArray(forKey: "preferredSearchSourceUrls") ?? []

        let needsBootstrapAccount = accountsValue.isEmpty && isLoggedInValue && !serverURLValue.isEmpty

        self.accounts = accountsValue
        self.currentAccountId = currentAccountIdValue
        self.apiBackend = apiBackendValue
        self.serverURL = serverURLValue
        self.publicServerURL = publicServerURLValue
        self.accessToken = accessTokenValue
        self.username = usernameValue
        self.isLoggedIn = isLoggedInValue
        self.selectedTTSId = selectedTTSIdValue
        self.useSystemTTS = useSystemTTSValue
        self.systemVoiceId = systemVoiceIdValue
        self.narrationTTSId = narrationTTSIdValue
        self.dialogueTTSId = dialogueTTSIdValue
        self.speakerTTSMapping = speakerTTSMappingValue
        self.speakerTriggerRegexes = speakerTriggerRegexesValue
        self.bookshelfSortByRecent = bookshelfSortByRecentValue
        self.searchSourcesFromBookshelf = searchSourcesFromBookshelfValue
        self.preferredSearchSourceUrls = preferredSearchSourceUrlsValue

        if needsBootstrapAccount {
            let defaultId = "\(serverURLValue):\(usernameValue)"
            let defaultAccount = UserAccount(
                id: defaultId,
                username: usernameValue,
                serverURL: serverURLValue,
                publicServerURL: publicServerURLValue,
                apiBackend: apiBackendValue,
                selectedTTSId: selectedTTSIdValue,
                narrationTTSId: narrationTTSIdValue,
                dialogueTTSId: dialogueTTSIdValue,
                speakerTTSMapping: speakerTTSMappingValue,
                preferredSearchSourceUrls: preferredSearchSourceUrlsValue
            )
            self.accounts = [defaultAccount]
            self.currentAccountId = defaultId
            if !accessTokenValue.isEmpty {
                KeychainHelper.shared.save(accessTokenValue, service: "com.readapp.ios", account: defaultId)
            }
        }

        let savedPreloadCount = UserDefaults.standard.integer(forKey: "ttsPreloadCount")
        self.ttsPreloadCount = savedPreloadCount == 0 ? 10 : savedPreloadCount

        let initialTurningMode: PageTurningMode
        if let savedTurningModeString = UserDefaults.standard.string(forKey: "pageTurningMode"),
           let savedTurningMode = PageTurningMode(rawValue: savedTurningModeString) {
            initialTurningMode = savedTurningMode
        } else {
            initialTurningMode = .simulation
        }
        self.pageTurningMode = initialTurningMode

        if let savedReadingModeString = UserDefaults.standard.string(forKey: "readingMode"),
           let savedReadingMode = ReadingMode(rawValue: savedReadingModeString) {
            // 路由修正：如果当前是仿真翻页，强制使用旧版水平模式
            if initialTurningMode == .simulation && savedReadingMode == .newHorizontal {
                self.readingMode = .horizontal
            } else {
                self.readingMode = savedReadingMode
            }
        } else {
            self.readingMode = .vertical
        }

        if let savedMangaModeString = UserDefaults.standard.string(forKey: "mangaReaderMode"),
           let savedMangaMode = MangaReaderMode(rawValue: savedMangaModeString) {
            self.mangaReaderMode = savedMangaMode
        } else {
            self.mangaReaderMode = .collection
        }

        if let savedThemeRaw = UserDefaults.standard.string(forKey: "readingTheme"),
           let savedTheme = ReadingTheme(rawValue: savedThemeRaw) {
            self.readingTheme = savedTheme
        } else {
            self.readingTheme = .system
        }
        
        updateInterfaceStyle()

        // 兼容旧版：如果没有单独设置旁白/对话 TTS，则使用原有的 selectedTTSId
        if narrationTTSId.isEmpty { narrationTTSId = selectedTTSId }
        if dialogueTTSId.isEmpty { dialogueTTSId = selectedTTSId }
        self.ttsProgressCache = Self.decodeTTSProgress(from: UserDefaults.standard.data(forKey: "ttsProgress"))
    }

    func logout() {
        if let id = currentAccountId {
            accounts.removeAll(where: { $0.id == id })
            KeychainHelper.shared.delete(service: "com.readapp.ios", account: id)
        }
        
        if let nextAccount = accounts.first {
            switchAccount(to: nextAccount.id)
        } else {
            accessToken = ""
            KeychainHelper.shared.delete(service: "com.readapp.ios", account: "accessToken")
            username = ""
            isLoggedIn = false
            currentAccountId = nil
            serverURL = ""
            publicServerURL = ""
        }
    }

    func switchAccount(to id: String) {
        guard let account = accounts.first(where: { $0.id == id }) else { return }
        currentAccountId = id
        username = account.username
        serverURL = account.serverURL
        publicServerURL = account.publicServerURL
        apiBackend = account.apiBackend
        accessToken = KeychainHelper.shared.read(service: "com.readapp.ios", account: id) ?? ""
        isLoggedIn = !accessToken.isEmpty
        
        // 同步账号相关的设置项
        self.selectedTTSId = account.selectedTTSId ?? ""
        self.narrationTTSId = account.narrationTTSId ?? ""
        self.dialogueTTSId = account.dialogueTTSId ?? ""
        self.speakerTTSMapping = account.speakerTTSMapping ?? [:]
        self.preferredSearchSourceUrls = account.preferredSearchSourceUrls ?? []
        
        NotificationCenter.default.post(name: .accountChanged, object: nil)
    }

    func addAccount(account: UserAccount, token: String) {
        if let existingIndex = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[existingIndex] = account
        } else {
            accounts.append(account)
        }
        KeychainHelper.shared.save(token, service: "com.readapp.ios", account: account.id)
        switchAccount(to: account.id)
    }

}

private extension UserPreferences {
    static let defaultSpeakerTriggerRegexes: [String] = [
        "笑着说",
        "笑道",
        "哭道",
        "怒道",
        "说道",
        "说",
        "道",
        "问",
        "答",
        "喊"
    ]
}

func md5Hex(_ input: String) -> String {
    let inputData = Data(input.utf8)
    let hashed = Insecure.MD5.hash(data: inputData)
    return hashed.map { String(format: "%02hhx", $0) }.joined()
}

enum SettingItem: String, CaseIterable, Identifiable {
    case display = "display"
    case reading = "reading"
    case cache = "cache"
    case tts = "tts"
    case content = "content"
    case rss = "rss"
    
    var id: String { self.rawValue }
    
    var title: String {
        switch self {
        case .display: return "显示与美化"
        case .reading: return "阅读设置"
        case .cache: return "缓存与下载管理"
        case .tts: return "听书设置"
        case .content: return "内容与净化"
        case .rss: return "订阅源管理"
        }
    }
    
    var systemImage: String {
        switch self {
        case .display: return "paintpalette"
        case .reading: return "book.pages"
        case .cache: return "archivebox"
        case .tts: return "speaker.wave.2"
        case .content: return "shield.checkered"
        case .rss: return "newspaper.fill"
        }
    }
}
