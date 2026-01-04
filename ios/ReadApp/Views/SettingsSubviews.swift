import SwiftUI

struct AccountSettingsView: View {
    @StateObject private var preferences = UserPreferences.shared
    @EnvironmentObject var apiService: APIService
    @Environment(\.dismiss) var dismiss
    @State private var showLogoutAlert = false
    @State private var showChangePasswordSheet = false

    var body: some View {
        Form {
            Section(header: Text("用户信息")) {
                HStack {
                    Text("用户名")
                    Spacer()
                    Text(preferences.username)
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("局域网服务器")
                        Spacer()
                        Text(preferences.serverURL)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    if !preferences.publicServerURL.isEmpty {
                        HStack {
                            Text("公网服务器")
                                .font(.caption)
                            Spacer()
                            Text(preferences.publicServerURL)
                                .font(.caption2)
                                .foregroundColor(.green)
                                .lineLimit(1)
                        }
                    }
                }
            }
            
            Section {
                Button(action: { showChangePasswordSheet = true }) {
                    Label("修改密码", systemImage: "key.viewfinder")
                }
                
                Button(action: { showLogoutAlert = true }) {
                    HStack {
                        Spacer()
                        Text("退出登录")
                            .foregroundColor(.red)
                        Spacer()
                    }
                }
            }
        }
        .navigationTitle("账号管理")
        .ifAvailableHideTabBar()
        .sheet(isPresented: $showChangePasswordSheet) {
            ChangePasswordView().environmentObject(apiService)
        }
        .alert("退出登录", isPresented: $showLogoutAlert) {
            Button("取消", role: .cancel) { }
            Button("退出", role: .destructive) {
                preferences.logout()
            }
        } message: {
            Text("确定要退出登录吗？")
        }
    }
}

struct ReadingSettingsView: View {
    @EnvironmentObject var apiService: APIService
    @StateObject private var preferences = UserPreferences.shared

    var body: some View {
        Form {
            Section(header: Text("通用设置")) {
                Toggle("夜间模式", isOn: $preferences.isDarkMode)
            }
            
            Section(header: Text("显示设置")) {
                HStack {
                    Text("字体大小")
                    Spacer()
                    Text("\(Int(preferences.fontSize))")
                }
                Slider(value: $preferences.fontSize, in: 12...30, step: 1)

                HStack {
                    Text("行间距")
                    Spacer()
                    Text("\(Int(preferences.lineSpacing))")
                }
                Slider(value: $preferences.lineSpacing, in: 4...20, step: 2)
                
                HStack {
                    Text("页边距")
                    Spacer()
                    Text("\(Int(preferences.pageHorizontalMargin))")
                }
                Slider(value: $preferences.pageHorizontalMargin, in: 0...30, step: 2)
                
                Picker("阅读模式", selection: $preferences.readingMode) {
                    ForEach(ReadingMode.allCases) { mode in
                        Text(mode.localizedName).tag(mode)
                    }
                }
            }
            
            Section(header: Text("缓存管理")) {
                NavigationLink(destination: CacheManagementView().environmentObject(apiService)) {
                    Text("离线缓存管理")
                }
            }
        }
        .navigationTitle("阅读设置")
        .ifAvailableHideTabBar()
    }
}

// MARK: - Change Password View
struct ChangePasswordView: View {
    @EnvironmentObject var apiService: APIService
    @Environment(\.dismiss) var dismiss
    @State private var oldPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showSuccess = false

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("安全信息")) {
                    SecureField("当前密码", text: $oldPassword)
                    SecureField("新密码", text: $newPassword)
                    SecureField("确认新密码", text: $confirmPassword)
                }
                
                Section {
                    Button(action: changePassword) {
                        HStack {
                            Spacer()
                            if isLoading {
                                ProgressView().padding(.trailing, 8)
                            }
                            Text("确认修改")
                            Spacer()
                        }
                    }
                    .disabled(oldPassword.isEmpty || newPassword.isEmpty || newPassword != confirmPassword || isLoading)
                }
            }
            .navigationTitle("修改密码")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
            }
            .alert("结果", isPresented: $showSuccess) {
                Button("确定") { dismiss() }
            } message: {
                Text("密码修改成功")
            }
            .alert("错误", isPresented: .constant(errorMessage != nil)) {
                Button("确定") { errorMessage = nil }
            } message: {
                if let error = errorMessage { Text(error) }
            }
        }
    }

    private func changePassword() {
        isLoading = true
        Task {
            do {
                try await apiService.changePassword(oldPassword: oldPassword, newPassword: newPassword)
                await MainActor.run {
                    isLoading = false
                    showSuccess = true
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

struct TTSSettingsView: View {
    @EnvironmentObject var apiService: APIService
    @StateObject private var preferences = UserPreferences.shared
    @State private var ttsSummary = ""

    var body: some View {
        Form {
            Section(header: Text("引擎管理")) {
                NavigationLink(destination: TTSEngineListView().environmentObject(apiService)) {
                    Label("TTS 引擎管理", systemImage: "waveform.path.ecg")
                }
                
                NavigationLink(destination: TTSSelectionView().environmentObject(apiService)) {
                    HStack {
                        Text("当前使用引擎")
                            .foregroundColor(.primary)
                        Spacer()
                        if preferences.useSystemTTS {
                            Text("系统内置")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        } else {
                            if preferences.selectedTTSId.isEmpty && preferences.narrationTTSId.isEmpty {
                                Text("未选择")
                                    .foregroundColor(.orange)
                                    .font(.caption)
                            } else {
                                Text(ttsSummary.isEmpty ? "已选择" : ttsSummary)
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }

            Section(header: Text("播放设置")) {
                HStack {
                    Text("语速")
                    Spacer()
                    Text("\(Int(preferences.speechRate))%")
                }
                Slider(value: $preferences.speechRate, in: 50...300, step: 5)
                
                Text("语速范围 50%-300% (100% 为正常语速)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Stepper(value: $preferences.ttsPreloadCount, in: 0...50) {
                    HStack {
                        Text("预载段数")
                        Spacer()
                        Text("\(preferences.ttsPreloadCount) 段")
                            .foregroundColor(.secondary)
                    }
                }
                Text("提前下载接下来的音频段，减少等待时间（建议 10-20 段）")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Toggle("TTS 时锁定翻页", isOn: $preferences.lockPageOnTTS)
            }
        }
        .navigationTitle("听书设置")
        .ifAvailableHideTabBar()
        .task {
            await loadTTSName()
        }
        .onChange(of: preferences.selectedTTSId) { _ in Task { await loadTTSName() } }
        .onChange(of: preferences.narrationTTSId) { _ in Task { await loadTTSName() } }
        .onChange(of: preferences.dialogueTTSId) { _ in Task { await loadTTSName() } }
    }
    
    private func loadTTSName() async {
        if preferences.useSystemTTS {
            ttsSummary = "系统内置"
            return
        }
        
        let narratorId = preferences.narrationTTSId.isEmpty ? preferences.selectedTTSId : preferences.narrationTTSId
        let dialogueId = preferences.dialogueTTSId.isEmpty ? narratorId : preferences.dialogueTTSId

        guard !narratorId.isEmpty else {
            ttsSummary = ""
            return
        }

        do {
            let ttsList = try await apiService.fetchTTSList()

            func name(for id: String) -> String? {
                ttsList.first(where: { $0.id == id })?.name
            }

            var parts: [String] = []
            let narratorName = name(for: narratorId)
            if let narratorName {
                parts.append("旁白: \(narratorName)")
            }

            if let dialogueName = name(for: dialogueId), dialogueName != narratorName {
                parts.append("对白: \(dialogueName)")
            }

            if !preferences.speakerTTSMapping.isEmpty {
                parts.append("发言者 \(preferences.speakerTTSMapping.count) 个")
            }

            ttsSummary = parts.joined(separator: " / " )
        } catch {
            print("加载 TTS 名称失败: \(error)")
        }
    }
}

struct ContentSettingsView: View {
    @EnvironmentObject var apiService: APIService
    @StateObject private var preferences = UserPreferences.shared

    var body: some View {
        Form {
            Section(header: Text("搜索设置")) {
                Toggle("书架搜索包含书源", isOn: $preferences.searchSourcesFromBookshelf)
                
                if preferences.searchSourcesFromBookshelf {
                    NavigationLink(destination: PreferredSourcesView().environmentObject(apiService)) {
                        HStack {
                            Text("指定搜索源")
                            Spacer()
                            Text(preferences.preferredSearchSourceUrls.isEmpty ? "全部启用源" : "已选 \(preferences.preferredSearchSourceUrls.count) 个")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
                }
            }

            Section(header: Text("内容净化")) {
                NavigationLink(destination: ReplaceRuleListView()) {
                    Text("净化规则管理")
                }
            }
            
            Section(header: Text("书架设置")) {
                Toggle("最近阅读排序", isOn: $preferences.bookshelfSortByRecent)
                Text("开启后按最后阅读时间排序，关闭则按加入书架时间排序")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("内容设置")
        .ifAvailableHideTabBar()
    }
}

struct DebugSettingsView: View {
    @EnvironmentObject var apiService: APIService
    @StateObject private var preferences = UserPreferences.shared
    @State private var showShareSheet = false
    @State private var logFileURL: URL?
    @State private var showClearLogsAlert = false
    @State private var showClearCacheAlert = false
    @State private var showLogViewer = false

    var body: some View {
        Form {
            Section(header: Text("调试选项")) {
                Toggle("详细日志模式", isOn: $preferences.isVerboseLoggingEnabled)
                Text("开启后将记录更详细的内容解析与图片加载过程")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Section(header: Text("日志")) {
                HStack {
                    Text("日志记录")
                    Spacer()
                    Text("\(LogManager.shared.getLogCount()) 条")
                        .foregroundColor(.secondary)
                }

                Button(action: { showLogViewer = true }) {
                    HStack {
                        Image(systemName: "list.bullet.rectangle.portrait")
                        Text("查看日志")
                        Spacer()
                    }
                    .foregroundColor(.blue)
                }

                Button(action: exportLogs) {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text("导出日志")
                        Spacer()
                    }
                    .foregroundColor(.blue)
                }

                Button(action: { showClearLogsAlert = true }) {
                    HStack {
                        Image(systemName: "trash")
                        Text("清空日志")
                        Spacer()
                    }
                    .foregroundColor(.red)
                }
            }
            
            Section(header: Text("存储")) {
                Button(action: { showClearCacheAlert = true }) {
                    HStack {
                        Image(systemName: "trash.circle")
                        Text("清除本地缓存")
                        Spacer()
                    }
                    .foregroundColor(.orange)
                }
            }
        }
        .navigationTitle("调试工具")
        .ifAvailableHideTabBar()
        .sheet(isPresented: $showLogViewer) {
            LogView()
        }
        .alert("清空日志", isPresented: $showClearLogsAlert) {
            Button("取消", role: .cancel) { }
            Button("清空", role: .destructive) {
                LogManager.shared.clearLogs()
            }
        } message: {
            Text("确定要清空所有日志吗？")
        }
        .alert("清除本地缓存", isPresented: $showClearCacheAlert) {
            Button("取消", role: .cancel) { }
            Button("清除", role: .destructive) {
                apiService.clearLocalCache()
            }
        } message: {
            Text("确定要清除所有本地章节内容缓存吗？")
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = logFileURL {
                ShareSheet(items: [url])
            }
        }
    }
    
    private func exportLogs() {
        if let url = LogManager.shared.exportLogs() {
            self.logFileURL = url
            // 给一丁点时间让 URL 状态同步
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.showShareSheet = true
            }
        }
    }
}

struct PreferredSourcesView: View {
    @EnvironmentObject var apiService: APIService
    @StateObject private var preferences = UserPreferences.shared
    @State private var filterText = ""
    
    var filteredSources: [BookSource] {
        let enabled = apiService.availableSources.filter { $0.enabled }
        if filterText.isEmpty {
            return enabled
        } else {
            return enabled.filter { $0.bookSourceName.localizedCaseInsensitiveContains(filterText) }
        }
    }
    
    var body: some View {
        List {
            Section(header: Text("全局开关")) {
                Toggle("搜索书架时包含全网书源", isOn: $preferences.searchSourcesFromBookshelf)
            }
            
            Section(header: Text("指定搜索源"), footer: Text("未选择任何书源时，将默认搜索所有已启用的书源。")) {
                if filterText.isEmpty {
                    Button(preferences.preferredSearchSourceUrls.isEmpty ? "✓ 全部启用源" : "全部启用源") {
                        preferences.preferredSearchSourceUrls = []
                    }
                }
                
                ForEach(filteredSources) { source in
                    Button(action: { togglePreferredSource(source.bookSourceUrl) }) {
                        HStack {
                            Text(source.bookSourceName)
                                .foregroundColor(.primary)
                            Spacer()
                            if preferences.preferredSearchSourceUrls.contains(source.bookSourceUrl) {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("指定搜索源")
        .searchable(text: $filterText, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索书源名称")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("清空全部") {
                    preferences.preferredSearchSourceUrls = []
                }
                .disabled(preferences.preferredSearchSourceUrls.isEmpty)
            }
        }
        .ifAvailableHideTabBar()
        .task {
            if apiService.availableSources.isEmpty {
                _ = try? await apiService.fetchBookSources()
            }
        }
    }
    
    private func togglePreferredSource(_ url: String) {
        if preferences.preferredSearchSourceUrls.contains(url) {
            preferences.preferredSearchSourceUrls.removeAll { $0 == url }
        } else {
            preferences.preferredSearchSourceUrls.append(url)
        }
    }
}

