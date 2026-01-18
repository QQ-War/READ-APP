import Foundation
import SwiftUI

@MainActor
final class SourceStore: ObservableObject {
    @Published private(set) var availableSources: [BookSource] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let service: APIService

    init(service: APIService = APIService.shared) {
        self.service = service
    }

    func refreshSources() async {
        isLoading = true
        defer { isLoading = false }
        do {
            availableSources = try await service.fetchBookSources()
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
    }

    func toggleBookSource(id: String, isEnabled: Bool) async throws {
        try await service.toggleBookSource(id: id, isEnabled: isEnabled)
        if let idx = availableSources.firstIndex(where: { $0.bookSourceUrl == id }) {
            availableSources[idx].enabled = isEnabled
        }
    }
}
