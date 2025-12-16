import SwiftUI

struct TTSSelectionView: View {
    @EnvironmentObject var apiService: APIService
    @StateObject private var preferences = UserPreferences.shared
    @Environment(\.dismiss) var dismiss

    @State private var ttsList: [HttpTTS] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var speakerMappings: [String: String] = [:]
    @State private var newSpeakerName = ""
    @State private var newSpeakerTTSId: String?
    
    var body: some View {
        NavigationView {
            Group {
                if isLoading {
                    ProgressView("加载中...")
                } else if ttsList.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "speaker.slash.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        
                        Text("暂无 TTS 引擎")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        Text("请在后台添加 TTS 引擎配置")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        
                        Button("重新加载") {
                            Task {
                                await loadTTSList()
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding()
                } else {
                    List {
                        Section {
                            ForEach(ttsList) { tts in
                                TTSRow(
                                    tts: tts,
                                    isSelected: preferences.narrationTTSId == tts.id
                                ) {
                                    preferences.narrationTTSId = tts.id
                                    if preferences.selectedTTSId.isEmpty { preferences.selectedTTSId = tts.id }
                                }
                            }
                        } header: {
                            Text("旁白 TTS")
                        } footer: {
                            Text("章节名和旁白将使用此 TTS")
                                .foregroundColor(.secondary)
                        }

                        Section {
                            ForEach(ttsList) { tts in
                                TTSRow(
                                    tts: tts,
                                    isSelected: preferences.dialogueTTSId == tts.id
                                ) {
                                    preferences.dialogueTTSId = tts.id
                                    if preferences.selectedTTSId.isEmpty { preferences.selectedTTSId = tts.id }
                                }
                            }
                        } header: {
                            Text("默认对话 TTS")
                        } footer: {
                            Text("当句子包含引号时默认使用此 TTS。未选择则回落到旁白 TTS")
                                .foregroundColor(.secondary)
                        }

                        Section {
                            if speakerMappings.isEmpty {
                                Text("为特定发言人绑定 TTS，格式匹配“张三：\"...”或“张三说：\"...”开头的句子。")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.vertical, 4)
                            } else {
                                ForEach(speakerMappings.sorted(by: { $0.key < $1.key }), id: \.key) { speaker, ttsId in
                                    HStack {
                                        Text(speaker)
                                        Spacer()
                                        Menu {
                                            ForEach(ttsList) { tts in
                                                Button(tts.name) {
                                                    updateMapping(for: speaker, ttsId: tts.id)
                                                }
                                            }

                                            Divider()

                                            Button("删除", role: .destructive) {
                                                speakerMappings.removeValue(forKey: speaker)
                                                preferences.speakerTTSMapping = speakerMappings
                                            }
                                        } label: {
                                            Text(ttsName(for: ttsId))
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                            }

                            HStack {
                                TextField("新增发言人", text: $newSpeakerName)

                                Menu {
                                    ForEach(ttsList) { tts in
                                        Button(tts.name) {
                                            newSpeakerTTSId = tts.id
                                        }
                                    }
                                } label: {
                                    Text(newSpeakerLabel)
                                        .foregroundColor(.secondary)
                                }

                                Button("添加") {
                                    addSpeakerMapping()
                                }
                                .disabled(newSpeakerName.trimmingCharacters(in: .whitespaces).isEmpty || newSpeakerTTSId == nil)
                            }
                        } header: {
                            Text("发言人和 TTS 对应")
                        } footer: {
                            Text("对话句子会优先匹配上方绑定的发言人 TTS；未匹配时使用默认对话 TTS。")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("TTS 引擎")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("刷新") {
                        Task {
                            await loadTTSList()
                        }
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
            .task {
                await loadTTSList()
            }
            .onAppear {
                speakerMappings = preferences.speakerTTSMapping
            }
            .alert("错误", isPresented: .constant(errorMessage != nil)) {
                Button("确定") {
                    errorMessage = nil
                }
            } message: {
                if let error = errorMessage {
                    Text(error)
                }
            }
        }
    }
    
    private func loadTTSList() async {
        isLoading = true
        errorMessage = nil
        
        do {
            ttsList = try await apiService.fetchTTSList()
            
            // 如果还没选择 TTS 引擎，尝试获取默认的
            if preferences.selectedTTSId.isEmpty && !ttsList.isEmpty {
                // 尝试获取后端默认 TTS
                if let defaultTTS = try? await apiService.fetchDefaultTTS(), !defaultTTS.isEmpty {
                    // 查找匹配的 TTS 引擎
                    if let tts = ttsList.first(where: { $0.url == defaultTTS || $0.name == defaultTTS }) {
                        preferences.selectedTTSId = tts.id
                    } else {
                        // 如果找不到，使用第一个
                        preferences.selectedTTSId = ttsList[0].id
                    }
                } else {
                    // 使用第一个
                    preferences.selectedTTSId = ttsList[0].id
                }
            }

            if preferences.narrationTTSId.isEmpty { preferences.narrationTTSId = preferences.selectedTTSId }
            if preferences.dialogueTTSId.isEmpty { preferences.dialogueTTSId = preferences.selectedTTSId }
            speakerMappings = preferences.speakerTTSMapping
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private var newSpeakerLabel: String {
        if let ttsId = newSpeakerTTSId {
            return ttsName(for: ttsId)
        }
        return "选择 TTS"
    }

    private func ttsName(for id: String) -> String {
        ttsList.first(where: { $0.id == id })?.name ?? "未选择"
    }

    private func addSpeakerMapping() {
        let name = newSpeakerName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let ttsId = newSpeakerTTSId else { return }
        speakerMappings[name] = ttsId
        preferences.speakerTTSMapping = speakerMappings
        newSpeakerName = ""
        newSpeakerTTSId = nil
    }

    private func updateMapping(for speaker: String, ttsId: String) {
        speakerMappings[speaker] = ttsId
        preferences.speakerTTSMapping = speakerMappings
    }
}

struct TTSRow: View {
    let tts: HttpTTS
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tts.name)
                        .font(.headline)
                        .foregroundColor(isSelected ? .blue : .primary)
                    
                    if let contentType = tts.contentType {
                        Text(contentType)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                        .font(.title3)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

