import Foundation

final class LocalTTSEngineStore {
    static let shared = LocalTTSEngineStore()
    private let userDefaultsKey = "ttsEngines_v1"

    private init() {}

    func loadEngines() -> [HttpTTS] {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else { return [] }
        let decoder = JSONDecoder()
        return (try? decoder.decode([HttpTTS].self, from: data)) ?? []
    }

    func saveEngines(_ engines: [HttpTTS]) {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(engines) else { return }
        UserDefaults.standard.set(data, forKey: userDefaultsKey)
    }
}
