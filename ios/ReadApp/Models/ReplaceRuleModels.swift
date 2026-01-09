import Foundation

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
