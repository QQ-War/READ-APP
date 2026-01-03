import SwiftUI

struct TTSEngineListView: View {
    @EnvironmentObject var apiService: APIService
    @State private var ttsList: [HttpTTS] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    var body: some View {
        List {
            ForEach(ttsList) { tts in
                NavigationLink(destination: TTSEngineEditView(ttsToEdit: tts).environmentObject(apiService)) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tts.name)
                            .font(.headline)
                        Text(tts.url)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .onDelete(perform: deleteTTS)
        }
        .navigationTitle("TTS 引擎管理")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink(destination: TTSEngineEditView(ttsToEdit: nil).environmentObject(apiService)) {
                    Image(systemName: "plus")
                }
            }
        }
        .task {
            await loadTTSList()
        }
        .refreshable {
            await loadTTSList()
        }
        .alert("错误", isPresented: .constant(errorMessage != nil)) {
            Button("确定") { errorMessage = nil }
        } message: {
            if let error = errorMessage { Text(error) }
        }
    }
    
    private func loadTTSList() async {
        isLoading = true
        errorMessage = nil
        do {
            ttsList = try await apiService.fetchTTSList()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
    
    private func deleteTTS(at offsets: IndexSet) {
        let itemsToDelete = offsets.map { ttsList[$0] }
        
        Task {
            for item in itemsToDelete {
                do {
                    try await apiService.deleteTTS(id: item.id)
                } catch {
                    await MainActor.run {
                        errorMessage = "删除 \(item.name) 失败: \(error.localizedDescription)"
                    }
                }
            }
            await loadTTSList()
        }
    }
}
