import Foundation

final class LocalTTSEngineStore {
    static let shared = LocalTTSEngineStore()
    private var userDefaultsKey: String {
        let accountId = UserPreferences.shared.currentAccountId ?? "default"
        return "ttsEngines_v1_\(md5Hex(accountId))"
    }
    private let legacyKey = "ttsEngines_v1"

    private init() {}

    func loadEngines() -> [HttpTTS] {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey) {
            let decoder = JSONDecoder()
            return (try? decoder.decode([HttpTTS].self, from: data)) ?? []
        }
        // Fallback to legacy key and migrate
        if let legacyData = UserDefaults.standard.data(forKey: legacyKey) {
            let decoder = JSONDecoder()
            let engines = (try? decoder.decode([HttpTTS].self, from: legacyData)) ?? []
            if !engines.isEmpty {
                saveEngines(engines)
            }
            return engines
        }
        return []
    }

    func saveEngines(_ engines: [HttpTTS]) {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(engines) else { return }
        UserDefaults.standard.set(data, forKey: userDefaultsKey)
    }
}
