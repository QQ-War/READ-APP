import Foundation
import Combine

class SourceListViewModel: ObservableObject {
    @Published var sources: [BookSource] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    @MainActor
    func fetchSources() {
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                let fetchedSources = try await APIService.shared.fetchBookSources()
                self.sources = fetchedSources
            } catch {
                self.errorMessage = "加载书源失败: \(error.localizedDescription)"
            }
            isLoading = false
        }
    }
}
