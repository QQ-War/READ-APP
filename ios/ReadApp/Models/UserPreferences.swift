import SwiftUI

class UserPreferences: ObservableObject {
    static let shared = UserPreferences()

    @Published var apiBackend: ApiBackend {
        didSet {
            UserDefaults.standard.set(apiBackend.rawValue, forKey: "apiBackend")
        }
    }

    @Published var serverURL: String {
        didSet {
            UserDefaults.standard.set(serverURL, forKey: "serverURL")
        }
    }

    @Published var publicServerURL: String {
        didSet {
            UserDefaults.standard.set(publicServerURL, forKey: "publicServerURL")
        }
    }

    @Published var accessToken: String {
        didSet {
            UserDefaults.standard.set(accessToken, forKey: "accessToken")
        }
    }

    @Published var username: String {
        didSet {
            UserDefaults.standard.set(username, forKey: "username")
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
        }
    }

    /// 默认对话使用的 TTS 引擎 ID（默认回落到 selectedTTSId）
    @Published var dialogueTTSId: String {
        didSet {
            UserDefaults.standard.set(dialogueTTSId, forKey: "dialogueTTSId")
        }
    }

    /// 发言人名称 -> TTS ID
    @Published var speakerTTSMapping: [String: String] {
        didSet {
            if let data = try? JSONEncoder().encode(speakerTTSMapping) {
                UserDefaults.standard.set(data, forKey: "speakerTTSMapping")
            }
        }
    }

    @Published var selectedTTSId: String {
        didSet {
            UserDefaults.standard.set(selectedTTSId, forKey: "selectedTTSId")
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

    @Published var darkMode: DarkModeConfig {
        didSet {
            UserDefaults.standard.set(darkMode.rawValue, forKey: "darkMode")
        }
    }

    @Published var lockPageOnTTS: Bool {
        didSet {
            UserDefaults.standard.set(lockPageOnTTS, forKey: "lockPageOnTTS")
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

    /// 是否强制使用服务器代理加载漫画图片
    @Published var forceMangaProxy: Bool {
        didSet {
            UserDefaults.standard.set(forceMangaProxy, forKey: "forceMangaProxy")
        }
    }

    // TTS进度记录：bookUrl -> (chapterIndex, sentenceIndex, sentenceOffset)
    private var ttsProgress: [String: (Int, Int, Int)] {
        get {
            if let data = UserDefaults.standard.data(forKey: "ttsProgress"),
               let dict = try? JSONDecoder().decode([String: [Int]].self, from: data) {
                return dict.mapValues {
                    if $0.count >= 3 { return ($0[0], $0[1], $0[2]) }
                    if $0.count >= 2 { return ($0[0], $0[1], 0) }
                    return ($0.first ?? 0, 0, 0)
                }
            }
            return [:]
        }
        set {
            let dict = newValue.mapValues { [$0.0, $0.1, $0.2] }
            if let data = try? JSONEncoder().encode(dict) {
                UserDefaults.standard.set(data, forKey: "ttsProgress")
            }
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
        var progress = ttsProgress
        progress[bookUrl] = (chapterIndex, sentenceIndex, sentenceOffset)
        ttsProgress = progress
    }

    func getTTSProgress(bookUrl: String) -> (chapterIndex: Int, sentenceIndex: Int, sentenceOffset: Int)? {
        return ttsProgress[bookUrl]
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
        self.forceMangaProxy = UserDefaults.standard.bool(forKey: "forceMangaProxy")

        let savedSpeechRate = UserDefaults.standard.double(forKey: "speechRate")
        self.speechRate = savedSpeechRate == 0 ? 100.0 : savedSpeechRate

        let rawServerURL = UserDefaults.standard.string(forKey: "serverURL") ?? ""
        let rawPublicURL = UserDefaults.standard.string(forKey: "publicServerURL") ?? ""
        let savedBackendRaw = UserDefaults.standard.string(forKey: "apiBackend")
        let detectedBackend = ApiBackendResolver.detect(from: rawServerURL)
        if let savedBackendRaw, let savedBackend = ApiBackend(rawValue: savedBackendRaw) {
            self.apiBackend = savedBackend
        } else {
            self.apiBackend = detectedBackend
        }
        self.serverURL = ApiBackendResolver.stripApiBasePath(rawServerURL)
        self.publicServerURL = ApiBackendResolver.stripApiBasePath(rawPublicURL)
        self.accessToken = UserDefaults.standard.string(forKey: "accessToken") ?? ""
        self.username = UserDefaults.standard.string(forKey: "username") ?? ""
        self.isLoggedIn = UserDefaults.standard.bool(forKey: "isLoggedIn")
        self.selectedTTSId = UserDefaults.standard.string(forKey: "selectedTTSId") ?? ""
        self.useSystemTTS = UserDefaults.standard.bool(forKey: "useSystemTTS")
        self.systemVoiceId = UserDefaults.standard.string(forKey: "systemVoiceId") ?? ""
        self.narrationTTSId = UserDefaults.standard.string(forKey: "narrationTTSId") ?? ""
        self.dialogueTTSId = UserDefaults.standard.string(forKey: "dialogueTTSId") ?? ""

        if let mappingData = UserDefaults.standard.data(forKey: "speakerTTSMapping"),
           let mapping = try? JSONDecoder().decode([String: String].self, from: mappingData) {
            self.speakerTTSMapping = mapping
        } else {
            self.speakerTTSMapping = [:]
        }
        self.bookshelfSortByRecent = UserDefaults.standard.bool(forKey: "bookshelfSortByRecent")
        self.searchSourcesFromBookshelf = UserDefaults.standard.bool(forKey: "searchSourcesFromBookshelf")
        self.preferredSearchSourceUrls = UserDefaults.standard.stringArray(forKey: "preferredSearchSourceUrls") ?? []

        let savedPreloadCount = UserDefaults.standard.integer(forKey: "ttsPreloadCount")
        self.ttsPreloadCount = savedPreloadCount == 0 ? 10 : savedPreloadCount

        if let savedReadingModeString = UserDefaults.standard.string(forKey: "readingMode"),
           let savedReadingMode = ReadingMode(rawValue: savedReadingModeString) {
            self.readingMode = savedReadingMode
        } else {
            self.readingMode = .vertical
        }

        if let savedTurningModeString = UserDefaults.standard.string(forKey: "pageTurningMode"),
           let savedTurningMode = PageTurningMode(rawValue: savedTurningModeString) {
            self.pageTurningMode = savedTurningMode
        } else {
            self.pageTurningMode = .simulation
        }

        if let savedDarkModeString = UserDefaults.standard.string(forKey: "darkMode"),
           let savedDarkMode = DarkModeConfig(rawValue: savedDarkModeString) {
            self.darkMode = savedDarkMode
        } else {
            self.darkMode = .system
        }

        // 兼容旧版：如果没有单独设置旁白/对话 TTS，则使用原有的 selectedTTSId
        if narrationTTSId.isEmpty { narrationTTSId = selectedTTSId }
        if dialogueTTSId.isEmpty { dialogueTTSId = selectedTTSId }
    }

    func logout() {
        accessToken = ""
        username = ""
        isLoggedIn = false
    }
}
