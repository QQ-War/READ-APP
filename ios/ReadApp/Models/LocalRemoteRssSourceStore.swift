import Foundation

final class LocalRemoteRssSourceStore {
    static let shared = LocalRemoteRssSourceStore()
    private var userDefaultsKey: String {
        let accountId = UserPreferences.shared.currentAccountId ?? "default"
        return "remoteRssSources_v1_\(md5Hex(accountId))"
    }
    private let legacyKey = "remoteRssSources_v1"

    private init() {}

    func loadSources() -> [RssSource] {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey) {
            let decoder = JSONDecoder()
            return (try? decoder.decode([RssSource].self, from: data)) ?? []
        }
        if let legacyData = UserDefaults.standard.data(forKey: legacyKey) {
            let decoder = JSONDecoder()
            let sources = (try? decoder.decode([RssSource].self, from: legacyData)) ?? []
            if !sources.isEmpty {
                saveSources(sources)
            }
            return sources
        }
        return []
    }

    func saveSources(_ sources: [RssSource]) {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(sources) else { return }
        UserDefaults.standard.set(data, forKey: userDefaultsKey)
    }
}
