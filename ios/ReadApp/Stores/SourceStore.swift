import Foundation
import SwiftUI

enum SourceCacheStore {
    private static var cacheURL: URL? {
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        return documentsURL.appendingPathComponent("sources.json")
    }

    static func load() -> [BookSource] {
        guard let url = cacheURL, let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([BookSource].self, from: data)) ?? []
    }

    static func save(_ sources: [BookSource]) {
        guard let url = cacheURL else { return }
        let encoder = JSONEncoder()
        DispatchQueue.global(qos: .background).async {
            guard let data = try? encoder.encode(sources) else { return }
            try? data.write(to: url)
        }
    }
}

@MainActor
final class SourceStore: ObservableObject {
    @Published private(set) var availableSources: [BookSource] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let service: APIService

    init(service: APIService = APIService.shared) {
        self.service = service
        self.availableSources = SourceCacheStore.load()
    }

    func refreshSources() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let fetched = try await service.fetchBookSources()
            availableSources = fetched
            SourceCacheStore.save(fetched)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveBookSource(jsonContent: String) async throws {
        try await service.saveBookSource(jsonContent: jsonContent)
        await refreshSources()
    }

    func deleteBookSource(id: String) async throws {
        try await service.deleteBookSource(id: id)
        availableSources.removeAll { $0.bookSourceUrl == id }
        SourceCacheStore.save(availableSources)
    }

    func toggleBookSource(id: String, isEnabled: Bool) async throws {
        try await service.toggleBookSource(id: id, isEnabled: isEnabled)
        if let idx = availableSources.firstIndex(where: { $0.bookSourceUrl == id }) {
            availableSources[idx].enabled = isEnabled
            SourceCacheStore.save(availableSources)
        }
    }
}
