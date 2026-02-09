import Foundation

final class LocalRemoteRssSourceStore {
    static let shared = LocalRemoteRssSourceStore()
    private let userDefaultsKey = "remoteRssSources_v1"

    private init() {}

    func loadSources() -> [RssSource] {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else { return [] }
        let decoder = JSONDecoder()
        return (try? decoder.decode([RssSource].self, from: data)) ?? []
    }

    func saveSources(_ sources: [RssSource]) {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(sources) else { return }
        UserDefaults.standard.set(data, forKey: userDefaultsKey)
    }
}
