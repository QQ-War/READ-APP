import Foundation

// MARK: - API Response
struct APIResponse<T: Codable>: Codable {
    let isSuccess: Bool
    let errorMsg: String?
    let data: T?
}

// MARK: - Chapter Content Response
struct ChapterContentResponse: Codable {
    let rules: [ReplaceRule]?
    let text: String
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

// MARK: - BookSource Page Info
struct BookSourcePageInfo: Codable {
    let page: Int
    let md5: String
}
