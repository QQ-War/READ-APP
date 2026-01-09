import Foundation

@MainActor
final class RssSourcesViewModel: ObservableObject {
    @Published private(set) var sources: [RssSource] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var canEdit = true
    @Published var pendingToggles: Set<String> = []

    private let service: RssService

    init(service: RssService = RssService(client: APIClient.shared)) {
        self.service = service
        Task {
            await refresh()
        }
    }

    func refresh() async {
        isLoading = true
        errorMessage = nil
        do {
            let response = try await service.fetchRssSources()
            sources = response.sources
            canEdit = response.can
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func toggle(source: RssSource, enable: Bool) async {
        guard canEdit else { return }
        guard !pendingToggles.contains(source.id) else { return }

        pendingToggles.insert(source.id)
        defer { pendingToggles.remove(source.id) }

        do {
            try await service.toggleSource(id: source.id, isEnabled: enable)
            if let index = sources.firstIndex(where: { $0.id == source.id }) {
                sources[index].enabled = enable
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
