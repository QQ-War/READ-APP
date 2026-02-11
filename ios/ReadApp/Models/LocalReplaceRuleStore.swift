import Foundation

final class LocalReplaceRuleStore {
    static let shared = LocalReplaceRuleStore()
    private let userDefaultsKey = "replaceRules_v1"

    private init() {}

    func loadRules() -> [ReplaceRule] {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else { return [] }
        let decoder = JSONDecoder()
        return (try? decoder.decode([ReplaceRule].self, from: data)) ?? []
    }

    func saveRules(_ rules: [ReplaceRule]) {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(rules) else { return }
        UserDefaults.standard.set(data, forKey: userDefaultsKey)
    }
}
