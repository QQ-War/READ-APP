import SwiftUI

struct TTSEngineEditView: View {
    @EnvironmentObject var apiService: APIService
    @Environment(\.dismiss) var dismiss
    
    let ttsToEdit: HttpTTS?
    
    @State private var name: String = ""
    @State private var url: String = ""
    @State private var contentType: String = "audio/mpeg"
    @State private var concurrentRate: String = "1"
    @State private var loginUrl: String = ""
    @State private var header: String = ""
    
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    var isEditing: Bool { ttsToEdit != nil }
    
    var body: some View {
        Form {
            Section(header: Text("基本信息")) {
                TextField("引擎名称", text: $name)
                TextField("接口 URL", text: $url)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
            }
            
            Section(header: Text("高级配置"), footer: Text("JSON 格式的 Header 或其他配置项")) {
                TextField("Content Type", text: $contentType)
                TextField("并发频率", text: $concurrentRate)
                TextField("登录 URL", text: $loginUrl)
                TextEditor(text: $header)
                    .frame(height: 100)
                    .font(.system(.body, design: .monospaced))
            }
            
            Section {
                Button(action: saveTTS) {
                    if isLoading {
                        ProgressView().progressViewStyle(CircularProgressViewStyle())
                    } else {
                        Text(isEditing ? "保存修改" : "添加引擎")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(name.isEmpty || url.isEmpty || isLoading)
            }
        }
        .navigationTitle(isEditing ? "编辑引擎" : "新增引擎")
        .ifAvailableHideTabBar()
        .onAppear(perform: loadInitialData)
        .alert("错误", isPresented: .constant(errorMessage != nil)) {
            Button("确定") { errorMessage = nil }
        } message: {
            if let error = errorMessage { Text(error) }
        }
    }
    
    private func loadInitialData() {
        if let tts = ttsToEdit {
            name = tts.name
            url = tts.url
            contentType = tts.contentType ?? "audio/mpeg"
            concurrentRate = tts.concurrentRate ?? "1"
            loginUrl = tts.loginUrl ?? ""
            header = tts.header ?? ""
        }
    }
    
    private func saveTTS() {
        isLoading = true
        errorMessage = nil
        
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
                try await apiService.saveTTS(tts: tts)
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
}
