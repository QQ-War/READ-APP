import Foundation
import Combine

class SourceListViewModel: ObservableObject {
    // Source List State
    @Published var sources: [BookSource] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    // Global Search State
    @Published var searchText: String = ""
    @Published var searchResults: [Book] = []
    @Published var isSearching: Bool = false
    
    private var cancellables = Set<AnyCancellable>()
    
    private var cacheURL: URL? {
        guard let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        return url.appendingPathComponent("sources.json")
    }

    init() {
        Task { @MainActor in
            self.fetchSources()
        }

        $searchText
            .debounce(for: .milliseconds(800), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] searchText in
                guard let self else { return }
                if searchText.isEmpty {
                    self.searchResults = []
                    self.isSearching = false
                } else {
                    Task { @MainActor in
                        self.performGlobalSearch()
                    }
                }
            }
            .store(in: &cancellables)
    }

    @MainActor
    private func loadFromCache() {
        guard let url = cacheURL, let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        if let cachedSources = try? decoder.decode([BookSource].self, from: data) {
            self.sources = cachedSources
        }
    }

    private func saveToCache() {
        guard let url = cacheURL else { return }
        let encoder = JSONEncoder()
        DispatchQueue.global(qos: .background).async {
            if let data = try? encoder.encode(self.sources) {
                try? data.write(to: url)
            }
        }
    }

    @MainActor
    func fetchSources() {
        loadFromCache()
        
        if sources.isEmpty {
            isLoading = true
        }
        errorMessage = nil
        
        Task {
            do {
                let fetchedSources = try await APIService.shared.fetchBookSources()
                if self.sources != fetchedSources {
                    self.sources = fetchedSources
                    saveToCache()
                }
            } catch {
                if self.sources.isEmpty {
                    self.errorMessage = "加载书源失败: \(error.localizedDescription)"
                }
            }
            isLoading = false
        }
    }
    
    @MainActor
    func performGlobalSearch() {
        let enabledSources = sources.filter { $0.enabled }
        guard !searchText.isEmpty, !enabledSources.isEmpty else {
            self.searchResults = []
            return
        }
        
        isSearching = true
        searchResults = []
        
        Task {
            await withTaskGroup(of: (String, [Book]).self) { group in
                for source in enabledSources {
                    group.addTask {
                        do {
                            let books = try await APIService.shared.searchBook(keyword: self.searchText, bookSourceUrl: source.bookSourceUrl)
                            return (source.bookSourceName, books)
                        } catch {
                            // Return empty array on failure for this source
                            return (source.bookSourceName, [])
                        }
                    }
                }
                
                for await (sourceName, books) in group {
                    let booksWithSource = books.map { book -> Book in
                        var mutableBook = book
                        mutableBook.sourceDisplayName = sourceName
                        mutableBook.origin = source.bookSourceUrl
                        mutableBook.originName = source.bookSourceName
                        return mutableBook
                    }
                    await MainActor.run {
                        self.searchResults.append(contentsOf: booksWithSource)
                    }
                }
            }
            
            await MainActor.run {
                isSearching = false
            }
        }
    }

    @MainActor
    func deleteSource(source: BookSource) {
        Task {
            do {
                try await APIService.shared.deleteBookSource(id: source.bookSourceUrl)
                if let index = sources.firstIndex(where: { $0.id == source.id }) {
                    sources.remove(at: index)
                    saveToCache()
                }
            } catch {
                self.errorMessage = "删除失败: \(error.localizedDescription)"
            }
        }
    }
    
    @MainActor
    func toggleSource(source: BookSource) {
        guard let index = sources.firstIndex(where: { $0.id == source.id }) else { return }
        let newState = !sources[index].enabled
        
        let originalSource = sources[index]
        
        // Optimistic update
        sources[index].enabled = newState
        
        Task {
            do {
                try await APIService.shared.toggleBookSource(id: source.bookSourceUrl, isEnabled: newState)
                saveToCache() // Save on success
            }
            catch {
                // Revert on failure
                if let idx = sources.firstIndex(where: { $0.id == source.id }) {
                    sources[idx] = originalSource // Revert to original object
                }
                self.errorMessage = "操作失败: \(error.localizedDescription)"
            }
        }
    }
}
