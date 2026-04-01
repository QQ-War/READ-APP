import Foundation
import SwiftUI

enum SourceCacheStore {
    private static var cacheURL: URL? {
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        let accountId = UserPreferences.shared.currentAccountId ?? "default"
        let safeId = md5Hex(accountId)
        return documentsURL.appendingPathComponent("sources_\(safeId).json")
    }

    private static var legacyCacheURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("sources.json")
    }

    static func load() -> [BookSource] {
        if let url = cacheURL, let data = try? Data(contentsOf: url) {
            return (try? JSONDecoder().decode([BookSource].self, from: data)) ?? []
        }
        // Fallback to legacy cache and migrate
        if let legacyURL = legacyCacheURL, let data = try? Data(contentsOf: legacyURL) {
            let decoded = (try? JSONDecoder().decode([BookSource].self, from: data)) ?? []
            if !decoded.isEmpty {
                save(decoded)
            }
            return decoded
        }
        return []
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
        
        NotificationCenter.default.addObserver(forName: .accountChanged, object: nil, queue: .main) { [weak self] _ in
            self?.availableSources = SourceCacheStore.load()
            Task { await self?.refreshSources() }
        }
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
