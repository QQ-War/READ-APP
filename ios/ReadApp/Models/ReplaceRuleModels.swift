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

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case groupname
        case group
        case pattern
        case replacement
        case scope
        case scopeTitle
        case scopeContent
        case excludeScope
        case isEnabled
        case isRegex
        case timeoutMillisecond
        case ruleorder
        case order
    }

    init(
        id: String?,
        name: String,
        groupname: String?,
        pattern: String,
        replacement: String,
        scope: String?,
        scopeTitle: Bool?,
        scopeContent: Bool?,
        excludeScope: String?,
        isEnabled: Bool?,
        isRegex: Bool?,
        timeoutMillisecond: Int64?,
        ruleorder: Int?
    ) {
        self.id = id
        self.name = name
        self.groupname = groupname
        self.pattern = pattern
        self.replacement = replacement
        self.scope = scope
        self.scopeTitle = scopeTitle
        self.scopeContent = scopeContent
        self.excludeScope = excludeScope
        self.isEnabled = isEnabled
        self.isRegex = isRegex
        self.timeoutMillisecond = timeoutMillisecond
        self.ruleorder = ruleorder
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let idString = try? container.decode(String.self, forKey: .id) {
            id = idString
        } else if let idInt = try? container.decode(Int64.self, forKey: .id) {
            id = String(idInt)
        } else {
            id = nil
        }
        name = try container.decode(String.self, forKey: .name)
        groupname = try container.decodeIfPresent(String.self, forKey: .groupname) ?? container.decodeIfPresent(String.self, forKey: .group)
        pattern = try container.decode(String.self, forKey: .pattern)
        replacement = try container.decode(String.self, forKey: .replacement)
        scope = try container.decodeIfPresent(String.self, forKey: .scope)
        scopeTitle = try container.decodeIfPresent(Bool.self, forKey: .scopeTitle)
        scopeContent = try container.decodeIfPresent(Bool.self, forKey: .scopeContent)
        excludeScope = try container.decodeIfPresent(String.self, forKey: .excludeScope)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled)
        isRegex = try container.decodeIfPresent(Bool.self, forKey: .isRegex)
        timeoutMillisecond = try container.decodeIfPresent(Int64.self, forKey: .timeoutMillisecond)
        ruleorder = try container.decodeIfPresent(Int.self, forKey: .ruleorder) ?? container.decodeIfPresent(Int.self, forKey: .order)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(groupname, forKey: .groupname)
        try container.encodeIfPresent(groupname, forKey: .group)
        try container.encode(pattern, forKey: .pattern)
        try container.encode(replacement, forKey: .replacement)
        try container.encodeIfPresent(scope, forKey: .scope)
        try container.encodeIfPresent(scopeTitle, forKey: .scopeTitle)
        try container.encodeIfPresent(scopeContent, forKey: .scopeContent)
        try container.encodeIfPresent(excludeScope, forKey: .excludeScope)
        try container.encodeIfPresent(isEnabled, forKey: .isEnabled)
        try container.encodeIfPresent(isRegex, forKey: .isRegex)
        try container.encodeIfPresent(timeoutMillisecond, forKey: .timeoutMillisecond)
        try container.encodeIfPresent(ruleorder, forKey: .ruleorder)
        try container.encodeIfPresent(ruleorder, forKey: .order)
    }

    // A computed property for Identifiable conformance that is stable.
    var identifiableId: String {
        id ?? UUID().uuidString
    }
}
