import Foundation

// MARK: - API Response
struct APIResponse<T: Codable>: Codable {
    let isSuccess: Bool
    let errorMsg: String?
    let data: T?
}

// MARK: - Book Model
struct Book: Codable, Identifiable {
    // 使用持久的备用ID，避免在没有 bookUrl 时因 UUID 变化导致列表状态丢失
    private let fallbackId = UUID().uuidString

    var id: String { bookUrl ?? fallbackId }
    let name: String?
    let author: String?
    let bookUrl: String?
    let origin: String?
    let originName: String?
    let coverUrl: String?
    let intro: String?
    let durChapterTitle: String?
    let durChapterIndex: Int?
    let durChapterPos: Double?
    let totalChapterNum: Int?
    let latestChapterTitle: String?
    let kind: String?
    let type: Int?
    let durChapterTime: Int64?  // 最后阅读时间（时间戳）

    enum CodingKeys: String, CodingKey {
        case name
        case author
        case bookUrl
        case origin
        case originName
        case coverUrl
        case intro
        case durChapterTitle
        case durChapterIndex
        case durChapterPos
        case totalChapterNum
        case latestChapterTitle
        case kind
        case type
        case durChapterTime
    }
    
    var displayCoverUrl: String? {
        if let url = coverUrl, !url.isEmpty {
            // 如果是相对路径，拼接完整URL
            if url.hasPrefix("baseurl/") {
                return APIService.shared.baseURL.replacingOccurrences(of: "/api/\(APIService.apiVersion)", with: "") + "/" + url
            }
            return url
        }
        return nil
    }
}

// MARK: - Chapter Model
struct BookChapter: Codable, Identifiable {
    var id: String { url }
    let title: String
    let url: String
    let index: Int
    let isVolume: Bool?
    let isPay: Bool?
}

// MARK: - Chapter Content Response
struct ChapterContentResponse: Codable {
    let rules: [ReplaceRule]?
    let text: String
}

// MARK: - Replace Rule Model
struct ReplaceRule: Codable, Identifiable, Equatable {
    let id: String?
    let name: String
    let groupname: String?
    let pattern: String
    let replacement: String
    let scope: String?
    let scopeTitle: Bool?
    let scopeContent: Bool?
    let excludeScope: String?
    let isEnabled: Bool?
    let isRegex: Bool?
    let timeoutMillisecond: Int64?
    let ruleorder: Int?

    // A computed property for Identifiable conformance that is stable.
    var identifiableId: String {
        id ?? UUID().uuidString
    }
}

// MARK: - Replace Rule Page Info
struct ReplaceRulePageInfo: Codable {
    let page: Int
    let md5: String
}

// MARK: - Book Import Response
struct BookImportResponse: Codable {
    let books: Book
    let chapters: [BookChapter]
}

// MARK: - HttpTTS Model
struct HttpTTS: Codable, Identifiable {
    let id: String
    let userid: String?
    let name: String
    let url: String
    let contentType: String?
    let concurrentRate: String?
    let loginUrl: String?
    let loginUi: String?
    let header: String?
    let enabledCookieJar: Bool?
    let loginCheckJs: String?
    let lastUpdateTime: Int64?
}

// MARK: - Login Response Model
struct LoginResponse: Codable {
    let accessToken: String
}

// MARK: - User Info Model
struct UserInfo: Codable {
    let username: String?
    let phone: String?
    let email: String?
}

// MARK: - User Preferences
enum ReadingMode: String, CaseIterable, Identifiable {
    case vertical = "Vertical"
    case horizontal = "Horizontal"

    var id: String { self.rawValue }
    var localizedName: String {
        switch self {
        case .vertical: return "上下滚动"
        case .horizontal: return "左右翻页"
        }
    }
}

class UserPreferences: ObservableObject {
    static let shared = UserPreferences()
    
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
    
    @Published var bookshelfSortByRecent: Bool {
        didSet {
            UserDefaults.standard.set(bookshelfSortByRecent, forKey: "bookshelfSortByRecent")
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
    
    // TTS进度记录：bookUrl -> (chapterIndex, sentenceIndex)
    private var ttsProgress: [String: (Int, Int)] {
        get {
            if let data = UserDefaults.standard.data(forKey: "ttsProgress"),
               let dict = try? JSONDecoder().decode([String: [Int]].self, from: data) {
                return dict.mapValues { ($0[0], $0[1]) }
            }
            return [:]
        }
        set {
            let dict = newValue.mapValues { [$0.0, $0.1] }
            if let data = try? JSONEncoder().encode(dict) {
                UserDefaults.standard.set(data, forKey: "ttsProgress")
            }
        }
    }
    
    func saveTTSProgress(bookUrl: String, chapterIndex: Int, sentenceIndex: Int) {
        var progress = ttsProgress
        progress[bookUrl] = (chapterIndex, sentenceIndex)
        ttsProgress = progress
    }
    
    func getTTSProgress(bookUrl: String) -> (chapterIndex: Int, sentenceIndex: Int)? {
        return ttsProgress[bookUrl]
    }
    
    private init() {
        // 初始化所有属性
        let savedFontSize = CGFloat(UserDefaults.standard.float(forKey: "fontSize"))
        self.fontSize = savedFontSize == 0 ? 18 : savedFontSize
        
        let savedLineSpacing = CGFloat(UserDefaults.standard.float(forKey: "lineSpacing"))
        self.lineSpacing = savedLineSpacing == 0 ? 8 : savedLineSpacing
        
        let savedSpeechRate = UserDefaults.standard.double(forKey: "speechRate")
        self.speechRate = savedSpeechRate == 0 ? 10.0 : savedSpeechRate
        
        self.serverURL = UserDefaults.standard.string(forKey: "serverURL") ?? ""
        self.publicServerURL = UserDefaults.standard.string(forKey: "publicServerURL") ?? ""
        self.accessToken = UserDefaults.standard.string(forKey: "accessToken") ?? ""
        self.username = UserDefaults.standard.string(forKey: "username") ?? ""
        self.isLoggedIn = UserDefaults.standard.bool(forKey: "isLoggedIn")
        self.selectedTTSId = UserDefaults.standard.string(forKey: "selectedTTSId") ?? ""
        self.narrationTTSId = UserDefaults.standard.string(forKey: "narrationTTSId") ?? ""
        self.dialogueTTSId = UserDefaults.standard.string(forKey: "dialogueTTSId") ?? ""

        if let mappingData = UserDefaults.standard.data(forKey: "speakerTTSMapping"),
           let mapping = try? JSONDecoder().decode([String: String].self, from: mappingData) {
            self.speakerTTSMapping = mapping
        } else {
            self.speakerTTSMapping = [:]
        }
        self.bookshelfSortByRecent = UserDefaults.standard.bool(forKey: "bookshelfSortByRecent")

        let savedPreloadCount = UserDefaults.standard.integer(forKey: "ttsPreloadCount")
        self.ttsPreloadCount = savedPreloadCount == 0 ? 10 : savedPreloadCount

        if let savedReadingModeString = UserDefaults.standard.string(forKey: "readingMode"),
           let savedReadingMode = ReadingMode(rawValue: savedReadingModeString) {
            self.readingMode = savedReadingMode
        } else {
            self.readingMode = .vertical // Default value
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
