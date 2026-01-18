import SwiftUI

struct TTSEngineListView: View {
    @State private var ttsList: [HttpTTS] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    @State private var showingURLImportDialog = false
    @State private var importURL = ""
    @State private var showingFilePicker = false

    var body: some View {
        List {
            ForEach(ttsList) { tts in
                NavigationLink(destination: TTSEngineEditView(ttsToEdit: tts)) {
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
        .ifAvailableHideTabBar()
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    NavigationLink(destination: TTSEngineEditView(ttsToEdit: nil)) {
                        Label("新建引擎", systemImage: "pencil.and.outline")
                    }
                    Button(action: { showingFilePicker = true }) {
                        Label("本地导入", systemImage: "folder")
                    }
                    Button(action: { showingURLImportDialog = true }) {
                        Label("网络导入", systemImage: "link")
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingFilePicker) {
            DocumentPicker { url in
                Task {
                    if let content = try? String(contentsOf: url) {
                        try? await APIService.shared.saveTTSBatch(jsonContent: content)
                        await loadTTSList()
                    }
                }
            }
        }
        .alert("网络导入", isPresented: $showingURLImportDialog) {
            TextField("输入引擎 URL", text: $importURL)
                .autocapitalization(.none)
            Button("导入") {
                Task { await importFromURL() }
            }
            Button("取消", role: .cancel) { importURL = "" }
        } message: {
            Text("请输入合法的 TTS 引擎 JSON 地址")
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
    
    private func importFromURL() async {
        guard let url = URL(string: importURL) else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let content = String(data: data, encoding: .utf8) {
                try await APIService.shared.saveTTSBatch(jsonContent: content)
                await loadTTSList()
            }
        } catch {
            await MainActor.run {
                errorMessage = "导入失败: \(error.localizedDescription)"
            }
        }
        importURL = ""
    }
    
    private func loadTTSList() async {
        isLoading = true
        errorMessage = nil
        do {
            ttsList = try await APIService.shared.fetchTTSList()
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
                    try await APIService.shared.deleteTTS(id: item.id)
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
