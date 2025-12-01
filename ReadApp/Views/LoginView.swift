import SwiftUI

struct LoginView: View {
    @EnvironmentObject var apiService: APIService
    @StateObject private var preferences = UserPreferences.shared
    @State private var username = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showServerSettings = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Spacer()
                
                // Logo 或应用名称
                Image(systemName: "book.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.blue)
                
                Text("ReadApp")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Spacer()
                
                // 服务器地址显示
                if !preferences.serverURL.isEmpty {
                    HStack {
                        Text("服务器:")
                            .foregroundColor(.secondary)
                        Text(preferences.serverURL)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Button(action: { showServerSettings = true }) {
                            Image(systemName: "gear")
                                .foregroundColor(.blue)
                        }
                    }
                    .padding(.horizontal)
                }
                
                // 登录表单
                VStack(spacing: 16) {
                    TextField("用户名", text: $username)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .disabled(isLoading)
                    
                    SecureField("密码", text: $password)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .disabled(isLoading)
                    
                    if let errorMessage = errorMessage {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                    
                    Button(action: handleLogin) {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                        } else {
                            Text("登录")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                        }
                    }
                    .background(canLogin ? Color.blue : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .disabled(!canLogin || isLoading)
                }
                .padding(.horizontal, 30)
                
                // 服务器设置按钮
                if preferences.serverURL.isEmpty {
                    Button(action: { showServerSettings = true }) {
                        HStack {
                            Image(systemName: "server.rack")
                            Text("设置服务器地址")
                        }
                        .foregroundColor(.blue)
                    }
                    .padding(.top, 10)
                }
                
                Spacer()
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showServerSettings) {
                ServerSettingsView()
            }
        }
    }
    
    private var canLogin: Bool {
        !username.isEmpty && !password.isEmpty && !preferences.serverURL.isEmpty
    }
    
    private func handleLogin() {
        guard canLogin else { return }
        
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                let accessToken = try await apiService.login(username: username, password: password)
                
                await MainActor.run {
                    preferences.accessToken = accessToken
                    preferences.username = username
                    preferences.isLoggedIn = true
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
}

// MARK: - 服务器设置视图
struct ServerSettingsView: View {
    @StateObject private var preferences = UserPreferences.shared
    @Environment(\.dismiss) var dismiss
    @State private var testingConnection = false
    @State private var testResult: String?
    @State private var testSuccess: Bool = false
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("局域网服务器配置")) {
                    TextField("局域网服务器地址", text: $preferences.serverURL)
                        .autocapitalization(.none)
                        .keyboardType(.URL)
                        .disableAutocorrection(true)
                    
                    Text("示例: http://192.168.1.100:8080")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section(header: Text("公网服务器配置（可选）")) {
                    TextField("公网服务器地址", text: $preferences.publicServerURL)
                        .autocapitalization(.none)
                        .keyboardType(.URL)
                        .disableAutocorrection(true)
                    
                    Text("示例: https://yourdomain.com:8080")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("当局域网服务器无法连接时自动使用公网服务器")
                        .font(.caption)
                        .foregroundColor(.green)
                }
                
                Section {
                    Text("⚠️ 重要提示")
                        .font(.caption)
                        .fontWeight(.semibold)
                    Text("必须填写 http:// 或 https:// 前缀")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                
                Section(header: Text("连接测试")) {
                    Button(action: testConnection) {
                        HStack {
                            if testingConnection {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                                Text("测试中...")
                            } else {
                                Image(systemName: "network")
                                Text("测试连接")
                            }
                            Spacer()
                        }
                    }
                    .disabled(preferences.serverURL.isEmpty || testingConnection)
                    
                    if let result = testResult {
                        HStack {
                            Image(systemName: testSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(testSuccess ? .green : .red)
                            Text(result)
                                .font(.caption)
                                .foregroundColor(testSuccess ? .green : .red)
                        }
                    }
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("⚠️ 连接失败？请检查：")
                            .font(.caption)
                            .fontWeight(.semibold)
                        Text("1. 服务器地址格式: http://IP:端口")
                            .font(.caption)
                        Text("2. 设备与服务器在同一网络")
                            .font(.caption)
                        Text("3. 服务器已启动并监听正确端口")
                            .font(.caption)
                        Text("4. 防火墙未阻止连接")
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                }
            }
            .navigationTitle("服务器设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                    .disabled(preferences.serverURL.isEmpty)
                }
            }
        }
    }
    
    private func testConnection() {
        testingConnection = true
        testResult = nil
        
        Task {
            do {
                let serverURL = preferences.serverURL
                let testURL = "\(serverURL)/api/\(APIService.apiVersion)/login?username=test&password=test&model=test"
                
                LogManager.shared.log("测试连接: \(testURL)", category: "连接测试")
                
                guard let url = URL(string: testURL) else {
                    await MainActor.run {
                        testResult = "服务器地址格式错误"
                        testSuccess = false
                        testingConnection = false
                    }
                    return
                }
                
                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                request.timeoutInterval = 10
                
                let (data, response) = try await URLSession.shared.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    await MainActor.run {
                        testResult = "无效的响应"
                        testSuccess = false
                        testingConnection = false
                    }
                    return
                }
                
                LogManager.shared.log("连接测试响应码: \(httpResponse.statusCode)", category: "连接测试")
                
                if httpResponse.statusCode == 200 || httpResponse.statusCode == 401 {
                    // 200 或 401 都说明服务器可以访问（401 是因为测试账号密码不对，但服务器是通的）
                    await MainActor.run {
                        testResult = "✓ 连接成功！服务器可访问"
                        testSuccess = true
                        testingConnection = false
                    }
                } else {
                    let responseText = String(data: data, encoding: .utf8) ?? ""
                    await MainActor.run {
                        testResult = "服务器返回错误 (状态码: \(httpResponse.statusCode))"
                        testSuccess = false
                        testingConnection = false
                    }
                    LogManager.shared.log("连接测试失败: \(responseText)", category: "连接测试")
                }
            } catch {
                let errorMessage: String
                if let nsError = error as NSError?, nsError.domain == NSURLErrorDomain {
                    switch nsError.code {
                    case NSURLErrorTimedOut:
                        errorMessage = "连接超时 - 请检查服务器地址和网络"
                    case NSURLErrorCannotConnectToHost:
                        errorMessage = "无法连接到服务器 - 请检查地址和端口"
                    case NSURLErrorNotConnectedToInternet:
                        errorMessage = "设备未连接到网络"
                    default:
                        errorMessage = "连接失败: \(error.localizedDescription)"
                    }
                } else {
                    errorMessage = "连接失败: \(error.localizedDescription)"
                }
                
                LogManager.shared.log("连接测试失败: \(errorMessage)", category: "连接测试")
                
                await MainActor.run {
                    testResult = errorMessage
                    testSuccess = false
                    testingConnection = false
                }
            }
        }
    }
}




