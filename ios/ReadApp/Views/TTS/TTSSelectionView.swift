import SwiftUI
import AVFoundation

struct TTSSelectionView: View {
    @StateObject private var preferences = UserPreferences.shared
    @Environment(\.dismiss) var dismiss

    @State private var ttsList: [HttpTTS] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var errorSheet: SelectableMessage?
    @State private var speakerMappings: [String: String] = [:]
    @State private var newSpeakerName = ""
    @State private var newSpeakerTTSId: String?
    
    var body: some View {
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
                    .glassyButtonStyle()
                }
                .padding()
            } else {
                List {
                    systemTTSSection
                    if !preferences.useSystemTTS {
                        narrationTTSSection
                        dialogueTTSSection
                        speakerMappingSection
                    }
                }
                .glassyListStyle()
            }
        }
        .navigationTitle("TTS 引擎")
        .ifAvailableHideTabBar()
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink(destination: TTSEngineListView()) {
                    Text("管理")
                }
                .glassyToolbarButton()
            }
            ToolbarItem(placement: .navigationBarLeading) {
                Button("刷新") {
                    Task {
                        await loadTTSList()
                    }
                }
                .glassyToolbarButton()
            }
        }
        .task {
            await loadTTSList()
        }
        .onAppear {
            speakerMappings = preferences.speakerTTSMapping
        }
        .sheet(item: $errorSheet) { sheet in
            SelectableMessageSheet(title: sheet.title, message: sheet.message) {
                errorMessage = nil
                errorSheet = nil
            }
        }
        .onChange(of: errorMessage) { newValue in
            guard let message = newValue, !message.isEmpty else { return }
            errorSheet = SelectableMessage(title: "错误", message: message)
        }
    }
    
    @MainActor
    private func loadTTSList() async {
        isLoading = true
        errorMessage = nil
        let cached = LocalTTSEngineStore.shared.loadEngines()
        if !cached.isEmpty {
            ttsList = cached
        }
        do {
            ttsList = try await APIService.shared.fetchTTSList()
            
            // 如果还没选择 TTS 引擎，尝试获取默认的
            if preferences.selectedTTSId.isEmpty && !ttsList.isEmpty {
                // 尝试获取后端默认 TTS
                if let defaultTTS = try? await APIService.shared.fetchDefaultTTS(), !defaultTTS.isEmpty {
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

    private func addSpeakerMapping() {
        let name = newSpeakerName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        // Add with the default narration voice, user can change it from the list.
        let defaultId = preferences.narrationTTSId
        speakerMappings[name] = defaultId
        preferences.speakerTTSMapping = speakerMappings
        newSpeakerName = ""
    }

    private func updateMapping(for speaker: String, ttsId: String) {
        speakerMappings[speaker] = ttsId
        preferences.speakerTTSMapping = speakerMappings
    }
    
    private func deleteSpeakerMapping(at offsets: IndexSet) {
        let speakersToDelete = offsets.map { speakerMappings.sorted(by: { $0.key < $1.key })[$0].key }
        for speaker in speakersToDelete {
            speakerMappings.removeValue(forKey: speaker)
        }
        preferences.speakerTTSMapping = speakerMappings
    }
}

private extension TTSSelectionView {
    var systemTTSSection: some View {
        Section {
            Toggle("使用系统内置 TTS", isOn: $preferences.useSystemTTS)

            if preferences.useSystemTTS {
                Picker("系统语音", selection: $preferences.systemVoiceId) {
                    Text("默认").tag("")
                    ForEach(AVSpeechSynthesisVoice.speechVoices(), id: \.identifier) { voice in
                        if voice.language.contains("zh") || voice.language.contains("en") {
                            Text("\(voice.name) (\(voice.language))").tag(voice.identifier)
                        }
                    }
                }
            }
        } header: {
            Text("通用设置")
        } footer: {
            Text("系统内置 TTS 支持离线使用，且响应速度更快。")
        }
    }

    var narrationTTSSection: some View {
        Section {
            HStack {
                Text("旁白 TTS")
                Spacer()
                Menu {
                    Picker("", selection: $preferences.narrationTTSId) {
                        ForEach(ttsList, id: \.identity) { tts in
                            Text(tts.name).tag(tts.id)
                        }
                    }
                } label: {
                    let currentName = ttsList.first(where: { $0.id == preferences.narrationTTSId })?.name ?? "未选择"
                    MarqueeText(text: currentName, font: .body, color: .secondary)
                        .frame(maxWidth: 150)
                }
            }
        } header: {
            Text("旁白 TTS")
        } footer: {
            Text("章节名和旁白将使用此 TTS")
                .foregroundColor(.secondary)
        }
    }

    var dialogueTTSSection: some View {
        Section {
            HStack {
                Text("对话 TTS")
                Spacer()
                Menu {
                    Picker("", selection: $preferences.dialogueTTSId) {
                        ForEach(ttsList, id: \.identity) { tts in
                            Text(tts.name).tag(tts.id)
                        }
                    }
                } label: {
                    let currentName = ttsList.first(where: { $0.id == preferences.dialogueTTSId })?.name ?? "未选择"
                    MarqueeText(text: currentName, font: .body, color: .secondary)
                        .frame(maxWidth: 150)
                }
            }
        } header: {
            Text("默认对话 TTS")
        } footer: {
            Text("当句子包含引号时默认使用此 TTS。未选择则回落到旁白 TTS")
                .foregroundColor(.secondary)
        }
    }

    var speakerMappingSection: some View {
        Section {
            speakerMappingList
            speakerMappingEditor
        } header: {
            Text("发言人和 TTS 对应")
        } footer: {
            Text("对话句子会优先匹配上方绑定的发言人 TTS；未匹配时使用默认对话 TTS。")
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    var speakerMappingList: some View {
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
                        Picker("", selection: Binding(
                            get: { ttsId },
                            set: { newId in
                                updateMapping(for: speaker, ttsId: newId)
                            }
                        )) {
                            ForEach(ttsList, id: \.identity) { tts in
                                Text(tts.name).tag(tts.id)
                            }
                        }
                    } label: {
                        let currentName = ttsList.first(where: { $0.id == ttsId })?.name ?? "未选择"
                        MarqueeText(text: currentName, font: .body, color: .secondary)
                            .frame(maxWidth: 150)
                    }
                }
            }
            .onDelete(perform: deleteSpeakerMapping)
        }
    }

    var speakerMappingEditor: some View {
        HStack {
            TextField("新增发言人", text: $newSpeakerName)
            Button("添加") {
                addSpeakerMapping()
            }
            .disabled(newSpeakerName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }
}
