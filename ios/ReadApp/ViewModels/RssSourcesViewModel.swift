import Foundation

@MainActor
final class RssSourcesViewModel: ObservableObject {
    @Published private(set) var remoteSources: [RssSource] = []
    @Published private(set) var customSources: [RssSource] = LocalRssSourceStore.shared.loadSources()
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var canEdit = true
    @Published var pendingToggles: Set<String> = []

    private let service: RssService
    private let localStore = LocalRssSourceStore.shared

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
            remoteSources = response.sources
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
            if let index = remoteSources.firstIndex(where: { $0.id == source.id }) {
                remoteSources[index].enabled = enable
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addOrUpdateCustomSource(_ source: RssSource) {
        var updated = customSources
        if let index = updated.firstIndex(where: { $0.sourceUrl == source.sourceUrl }) {
            updated[index] = source
        } else {
            updated.append(source)
        }
        saveCustomSources(updated)
    }

    func deleteCustomSource(_ source: RssSource) {
        var updated = customSources
        updated.removeAll { $0.sourceUrl == source.sourceUrl }
        saveCustomSources(updated)
    }

    func toggleCustomSource(_ source: RssSource, enable: Bool) {
        var updated = customSources
        if let index = updated.firstIndex(where: { $0.sourceUrl == source.sourceUrl }) {
            updated[index].enabled = enable
            saveCustomSources(updated)
        }
    }

    func importCustomSources(from data: Data) throws -> [RssSource] {
        let decoder = JSONDecoder()
        let decoded: [RssSource]
        if let list = try? decoder.decode([RssSource].self, from: data) {
            decoded = list
        } else {
            decoded = [try decoder.decode(RssSource.self, from: data)]
        }
        var added: [RssSource] = []
        for source in decoded {
            if let normalized = normalizeCustomSource(source) {
                addOrUpdateCustomSource(normalized)
                added.append(normalized)
            }
        }
        return added
    }

    private func normalizeCustomSource(_ source: RssSource) -> RssSource? {
        let trimmedUrl = source.sourceUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUrl.isEmpty else { return nil }
        return RssSource(
            sourceUrl: trimmedUrl,
            sourceName: source.sourceName,
            sourceIcon: source.sourceIcon,
            sourceGroup: source.sourceGroup,
            loginUrl: source.loginUrl,
            loginUi: source.loginUi,
            variableComment: source.variableComment,
            enabled: true
        )
    }

    private func saveCustomSources(_ sources: [RssSource]) {
        localStore.saveSources(sources)
        customSources = sources
    }
}
