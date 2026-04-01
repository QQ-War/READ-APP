import Foundation

final class LocalReplaceRuleStore {
    static let shared = LocalReplaceRuleStore()
    private var userDefaultsKey: String {
        let accountId = UserPreferences.shared.currentAccountId ?? "default"
        return "replaceRules_v1_\(md5Hex(accountId))"
    }
    private let legacyKey = "replaceRules_v1"

    private init() {}

    func loadRules() -> [ReplaceRule] {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey) {
            let decoder = JSONDecoder()
            return (try? decoder.decode([ReplaceRule].self, from: data)) ?? []
        }
        // Fallback to legacy key and migrate
        if let legacyData = UserDefaults.standard.data(forKey: legacyKey) {
            let decoder = JSONDecoder()
            let rules = (try? decoder.decode([ReplaceRule].self, from: legacyData)) ?? []
            if !rules.isEmpty {
                saveRules(rules)
            }
            return rules
        }
        return []
    }

    func saveRules(_ rules: [ReplaceRule]) {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(rules) else { return }
        UserDefaults.standard.set(data, forKey: userDefaultsKey)
    }
}
