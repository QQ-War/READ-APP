import Foundation

final class LocalRssSourceStore {
    static let shared = LocalRssSourceStore()
    private let userDefaultsKey = "customRssSources_v1"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {}

    func loadSources() -> [RssSource] {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else { return [] }
        return (try? decoder.decode([RssSource].self, from: data)) ?? []
    }

    func saveSources(_ sources: [RssSource]) {
        guard let data = try? encoder.encode(sources) else { return }
        UserDefaults.standard.set(data, forKey: userDefaultsKey)
    }
}
