import Foundation

@MainActor
final class RssSourcesViewModel: ObservableObject {
    @Published private(set) var remoteSources: [RssSource] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var canEdit = true
    @Published var pendingToggles: Set<String> = []
    @Published var isRemoteOperationInProgress = false

    private let service: APIService
    private let remoteStore = LocalRemoteRssSourceStore.shared

    init(service: APIService = APIService.shared) {
        self.service = service
        self.remoteSources = remoteStore.loadSources()
        Task {
            await refresh()
        }
    }

    var canModifyRemoteSources: Bool {
        return canEdit && service.canModifyRemoteRssSources
    }

    func refresh() async {
        isLoading = true
        errorMessage = nil
        do {
            let response = try await service.fetchRssSources()
            remoteSources = response.sources
            canEdit = response.can
            remoteStore.saveSources(response.sources)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func saveRemoteSource(_ source: RssSource, remoteId: String? = nil) async {
        guard canEdit else { return }
        isRemoteOperationInProgress = true
        defer { isRemoteOperationInProgress = false }
        errorMessage = nil
        do {
            try await service.saveRssSource(source, remoteId: remoteId)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteRemoteSource(_ source: RssSource) async {
        guard canEdit else { return }
        isRemoteOperationInProgress = true
        defer { isRemoteOperationInProgress = false }
        errorMessage = nil
        do {
            try await service.deleteRssSource(id: source.id)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggle(source: RssSource, enable: Bool) async {
        guard canEdit else { return }
        guard !pendingToggles.contains(source.id) else { return }

        pendingToggles.insert(source.id)
        defer { pendingToggles.remove(source.id) }

        do {
            try await service.toggleRssSource(id: source.id, isEnabled: enable)
            if let index = remoteSources.firstIndex(where: { $0.id == source.id }) {
                remoteSources[index].enabled = enable
                remoteStore.saveSources(remoteSources)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func importCustomSources(from data: Data) async throws -> [RssSource] {
        let decoder = JSONDecoder()
        let decoded: [RssSource]
        if let list = try? decoder.decode([RssSource].self, from: data) {
            decoded = list
        } else {
            decoded = [try decoder.decode(RssSource.self, from: data)]
        }
        
        var added: [RssSource] = []
        for source in decoded {
            if let normalized = normalizeSource(source) {
                try await service.saveRssSource(normalized)
                added.append(normalized)
            }
        }
        await refresh()
        return added
    }

    private func normalizeSource(_ source: RssSource) -> RssSource? {
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
}
