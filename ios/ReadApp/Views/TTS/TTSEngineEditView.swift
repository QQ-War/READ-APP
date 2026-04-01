import SwiftUI
import AVFoundation

struct TTSEngineEditView: View {
    @Environment(\.dismiss) var dismiss
    
    let ttsToEdit: HttpTTS?
    
    @State private var name: String
    @State private var url: String
    @State private var contentType: String
    @State private var concurrentRate: String
    @State private var loginUrl: String
    @State private var header: String
    
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var errorSheet: SelectableMessage?
    @State private var testText: String = "这是一段 TTS 试听文本。"
    @State private var isTesting = false
    @State private var isPreviewPlaying = false
    @State private var previewPlayer: AVAudioPlayer?
    @State private var previewToken: Int = 0
    
    var isEditing: Bool { ttsToEdit != nil }
    
    // 使用自定义构造函数来确保 State 变量被正确初始化为传入的值
    init(ttsToEdit: HttpTTS?) {
        self.ttsToEdit = ttsToEdit
        _name = State(initialValue: ttsToEdit?.name ?? "")
        _url = State(initialValue: ttsToEdit?.url ?? "")
        _contentType = State(initialValue: ttsToEdit?.contentType ?? "audio/mpeg")
        _concurrentRate = State(initialValue: ttsToEdit?.concurrentRate ?? "1")
        _loginUrl = State(initialValue: ttsToEdit?.loginUrl ?? "")
        _header = State(initialValue: ttsToEdit?.header ?? "")
    }
    
    var body: some View {
        Form {
            Section(header: GlassySectionHeader(title: "基本信息")) {
                HStack {
                    Text("名称")
                    TextField("引擎名称", text: $name)
                        .multilineTextAlignment(.trailing)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("接口 URL")
                    TextEditor(text: $url)
                        .frame(minHeight: 120)
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundColor(.blue)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                        )
                }
            }
            
            Section(header: GlassySectionHeader(title: "高级配置"), footer: Text("Header 请使用标准 JSON 格式，例如 {\"User-Agent\": \"...\"}")) {
                HStack {
                    Text("Content Type")
                    TextField("audio/mpeg", text: $contentType)
                        .multilineTextAlignment(.trailing)
                }
                HStack {
                    Text("并发频率")
                    TextField("1", text: $concurrentRate)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.numberPad)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("登录 URL (可选)")
                    TextField("https://...", text: $loginUrl)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("自定义 Header (JSON)")
                    TextEditor(text: $header)
                        .frame(height: 100)
                        .font(.system(.body, design: .monospaced))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                        )
                }
            }
            
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("试听文本")
                    TextEditor(text: $testText)
                        .frame(minHeight: 80)
                        .font(.system(.body))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                        )
                    Button(action: togglePreviewPlayback) {
                        HStack {
                            Spacer()
                            if isTesting {
                                ProgressView()
                            } else {
                                Text(isPreviewPlaying ? "停止试听" : "试听当前引擎")
                            }
                            Spacer()
                        }
                    }
                    .disabled(isLoading || isTesting)
                }

                Button(action: saveTTS) {
                    if isLoading {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    } else {
                        Text(isEditing ? "保存修改" : "立即添加")
                            .frame(maxWidth: .infinity)
                            .font(.headline)
                    }
                }
                .disabled(name.isEmpty || url.isEmpty || isLoading)
                
                if isEditing {
                    Button(role: .destructive, action: deleteTTS) {
                        Text("删除此引擎")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(isLoading)
                }
            }
        }
        .navigationTitle(isEditing ? "编辑引擎" : "新增引擎")
        .navigationBarTitleDisplayMode(.inline)
        .ifAvailableHideTabBar()
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
        .onDisappear {
            stopPreviewPlayback()
        }
    }
    
    private func saveTTS() {
        isLoading = true
        errorMessage = nil
        
        // 构建模型
        let tts = HttpTTS(
            id: ttsToEdit?.id ?? UUID().uuidString,
            userid: ttsToEdit?.userid,
            name: name,
            url: url,
            contentType: contentType,
            concurrentRate: concurrentRate,
            loginUrl: loginUrl,
            loginUi: ttsToEdit?.loginUi,
            header: header,
            enabledCookieJar: ttsToEdit?.enabledCookieJar,
            loginCheckJs: ttsToEdit?.loginCheckJs,
            lastUpdateTime: Int64(Date().timeIntervalSince1970 * 1000)
        )
        
        Task {
            do {
                try await APIService.shared.saveTTS(tts: tts)
                await MainActor.run {
                    isLoading = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    private func deleteTTS() {
        guard let id = ttsToEdit?.id else { return }
        isLoading = true
        Task {
            do {
                try await APIService.shared.deleteTTS(id: id)
                await MainActor.run {
                    isLoading = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func togglePreviewPlayback() {
        if isPreviewPlaying {
            stopPreviewPlayback()
        } else {
            startPreviewPlayback()
        }
    }

    private func startPreviewPlayback() {
        guard let id = ttsToEdit?.id, !id.isEmpty else {
            errorMessage = "请先保存引擎后再试听"
            return
        }
        let text = testText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            errorMessage = "试听文本不能为空"
            return
        }
        isTesting = true
        errorMessage = nil
        let token = previewToken + 1
        previewToken = token

        Task {
            do {
                let data = try await fetchPreviewAudioData(ttsId: id, text: text)
                await MainActor.run {
                    do {
                        stopPreviewPlayback()
                        let player = try AVAudioPlayer(data: data)
                        player.prepareToPlay()
                        guard player.play() else {
                            throw NSError(domain: "TTSEngineEditView", code: -1, userInfo: [NSLocalizedDescriptionKey: "试听播放失败"])
                        }
                        previewPlayer = player
                        isPreviewPlaying = true
                        isTesting = false
                        let duration = player.duration
                        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.2) {
                            guard previewToken == token, !(previewPlayer?.isPlaying ?? false) else { return }
                            isPreviewPlaying = false
                        }
                    } catch {
                        isTesting = false
                        isPreviewPlaying = false
                        errorMessage = error.localizedDescription
                    }
                }
            } catch {
                await MainActor.run {
                    isTesting = false
                    isPreviewPlaying = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func fetchPreviewAudioData(ttsId: String, text: String) async throws -> Data {
        let speechRate = UserPreferences.shared.speechRate
        if APIClient.shared.backend == .reader {
            return try await APIService.shared.fetchReaderTtsAudio(ttsId: ttsId, text: text, speechRate: speechRate)
        }
        guard let url = APIService.shared.buildTTSAudioURL(ttsId: ttsId, text: text, speechRate: speechRate) else {
            throw NSError(domain: "TTSEngineEditView", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法构建试听请求"])
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw NSError(domain: "TTSEngineEditView", code: (response as? HTTPURLResponse)?.statusCode ?? 500, userInfo: [NSLocalizedDescriptionKey: "试听请求失败"])
        }
        let contentType = http.value(forHTTPHeaderField: "Content-Type") ?? ""
        guard contentType.contains("audio") else {
            if (try? AVAudioPlayer(data: data)) != nil { return data }
            throw NSError(domain: "TTSEngineEditView", code: -1, userInfo: [NSLocalizedDescriptionKey: "试听返回非音频数据"])
        }
        return data
    }

    private func stopPreviewPlayback() {
        previewToken += 1
        previewPlayer?.stop()
        previewPlayer = nil
        isPreviewPlaying = false
        isTesting = false
    }
}
