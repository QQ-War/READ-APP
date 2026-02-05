import SwiftUI

struct AccountSettingsView: View {
    @StateObject private var preferences = UserPreferences.shared
    @Environment(\.dismiss) var dismiss
    @State private var showLogoutAlert = false
    @State private var showChangePasswordSheet = false

    var body: some View {
        Form {
            Section(header: GlassySectionHeader(title: "用户信息")) {
                HStack {
                    Text("用户名")
                    Spacer()
                    Text(preferences.username)
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("服务端类型")
                        Spacer()
                        Text(preferences.apiBackend.displayName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
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
        .glassyListStyle()
        .sheet(isPresented: $showChangePasswordSheet) {
            ChangePasswordView()
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
    @StateObject private var preferences = UserPreferences.shared

    var body: some View {
        List {
            Section(header: GlassySectionHeader(title: "基础显示")) {
                Picker("阅读主题", selection: $preferences.readingTheme) {
                    ForEach(ReadingTheme.allCases) { theme in
                        Text(theme.localizedName).tag(theme)
                    }
                }
                
                HStack {
                    Text("字号")
                    Slider(value: $preferences.fontSize, in: 12...30, step: 1)
                    Text("\(Int(preferences.fontSize))").font(.caption).monospacedDigit().frame(width: 25, alignment: .trailing)
                }

                HStack {
                    Text("行距")
                    Slider(value: $preferences.lineSpacing, in: 4...20, step: 2)
                    Text("\(Int(preferences.lineSpacing))").font(.caption).monospacedDigit().frame(width: 25, alignment: .trailing)
                }
                
                HStack {
                    Text("边距")
                    Slider(value: $preferences.pageHorizontalMargin, in: 0...50, step: 2)
                    Text("\(Int(preferences.pageHorizontalMargin))").font(.caption).monospacedDigit().frame(width: 25, alignment: .trailing)
                }

                HStack {
                    Text("进度字号")
                    Slider(value: $preferences.progressFontSize, in: 8...20, step: 1)
                    Text("\(Int(preferences.progressFontSize))").font(.caption).monospacedDigit().frame(width: 25, alignment: .trailing)
                }

                HStack {
                    Text("底部留白")
                    Slider(value: $preferences.readingBottomInset, in: 0...120, step: 4)
                    Text("\(Int(preferences.readingBottomInset))").font(.caption).monospacedDigit().frame(width: 35, alignment: .trailing)
                }
                
                Picker("阅读模式", selection: $preferences.readingMode) {
                    ForEach(ReadingMode.allCases.filter { $0 != .newHorizontal }) { mode in
                        Text(mode.localizedName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section(header: GlassySectionHeader(title: "左右翻页设置")) {
                Picker("翻页方式", selection: $preferences.pageTurningMode) {
                    ForEach(PageTurningMode.allCases) { mode in
                        Text(mode.localizedName).tag(mode)
                    }
                }
            }

            Section(header: GlassySectionHeader(title: "上下滚动设置")) {
                Toggle("开启无限滚动", isOn: $preferences.isInfiniteScrollEnabled)

                HStack {
                    Text("无缝切章阈值")
                    Slider(value: $preferences.infiniteScrollSwitchThreshold, in: 40...300, step: 10)
                    Text("\(Int(preferences.infiniteScrollSwitchThreshold))").font(.caption).monospacedDigit().frame(width: 35, alignment: .trailing)
                }
                
                HStack {
                    Text("切章拉伸距离")
                    Slider(value: $preferences.verticalThreshold, in: 50...500, step: 10)
                    Text("\(Int(preferences.verticalThreshold))").font(.caption).monospacedDigit().frame(width: 35, alignment: .trailing)
                }
                
                HStack {
                    Text("滚动阻尼系数")
                    Slider(value: $preferences.verticalDampingFactor, in: 0...0.5, step: 0.01)
                    Text(String(format: "%.2f", preferences.verticalDampingFactor)).font(.caption).monospacedDigit().frame(width: 35, alignment: .trailing)
                }
            }

            Section(header: GlassySectionHeader(title: "显示与性能"), footer: Text("降低静态阅读时的刷新率可显著延长 ProMotion 设备的续航。关闭动态颜色可进一步减轻 GPU 渲染压力。")) {
                HStack {
                    Text("静态刷新率")
                    Slider(value: Binding(get: { Double(preferences.staticRefreshRate) }, set: { preferences.staticRefreshRate = Float($0) }), in: 10...60, step: 10)
                    Text("\(Int(preferences.staticRefreshRate))Hz").font(.caption).monospacedDigit().frame(width: 45, alignment: .trailing)
                }

                Toggle("进度条动态颜色", isOn: $preferences.isProgressDynamicColorEnabled)
            }

            Section(header: GlassySectionHeader(title: "漫画设置")) {
                HStack {
                    Text("漫画最大缩放")
                    Slider(value: $preferences.mangaMaxZoom, in: 1...10, step: 0.5)
                    Text(String(format: "%.1f", preferences.mangaMaxZoom)).font(.caption).monospacedDigit().frame(width: 30, alignment: .trailing)
                }

                Picker("渲染引擎", selection: $preferences.mangaReaderMode) {
                    ForEach(MangaReaderMode.allCases) { mode in
                        Text(mode.localizedName).tag(mode)
                    }
                }
            }
        }
        .navigationTitle("阅读设置")
        .onAppear {
            if preferences.readingMode == .newHorizontal {
                preferences.readingMode = .horizontal
            }
        }
        .ifAvailableHideTabBar()
        .glassyListStyle()
    }
}

// MARK: - Change Password View
struct ChangePasswordView: View {
    @Environment(\.dismiss) var dismiss
    @State private var oldPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var errorSheet: SelectableMessage?
    @State private var showSuccess = false

    var body: some View {
        NavigationView {
            Form {
                Section(header: GlassySectionHeader(title: "安全信息")) {
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
            .glassyListStyle()
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
            .sheet(item: $errorSheet) { sheet in
                SelectableMessageSheet(title: sheet.title, message: sheet.message) {
                    errorMessage = nil
                    errorSheet = nil
                }
            }
        }
        .onChange(of: errorMessage) { newValue in
            guard let message = newValue, !message.isEmpty else { return }
            errorSheet = SelectableMessage(title: "错误", message: message)
        }
    }

    private func changePassword() {
        isLoading = true
        Task {
            do {
                try await APIService.shared.changePassword(oldPassword: oldPassword, newPassword: newPassword)
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
    @StateObject private var preferences = UserPreferences.shared
    @State private var ttsSummary = ""

    var body: some View {
        Form {
            Section(header: GlassySectionHeader(title: "引擎管理")) {
                NavigationLink(destination: TTSEngineListView()) {
                    Label("TTS 引擎管理", systemImage: "waveform.path.ecg")
                }
                
                NavigationLink(destination: TTSSelectionView()) {
                    Label {
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
                                    MarqueeText(
                                        text: ttsSummary.isEmpty ? "已选择" : ttsSummary,
                                        font: .caption,
                                        color: .secondary
                                    )
                                    .frame(maxWidth: .infinity)
                                }
                            }
                        }
                    } icon: {
                        Image(systemName: "waveform")
                    }
                }
            }

            Section(header: GlassySectionHeader(title: "播放设置")) {
                HStack {
                    Text("语速")
                    Slider(value: $preferences.speechRate, in: 50...300, step: 5)
                    Text("\(Int(preferences.speechRate))%").font(.caption).monospacedDigit().frame(width: 45, alignment: .trailing)
                }

                Stepper(value: $preferences.ttsPreloadCount, in: 0...50) {
                    HStack {
                        Text("预载段数")
                        Spacer()
                        Text("\(preferences.ttsPreloadCount) 段")
                            .foregroundColor(.secondary)
                    }
                }
                
                Toggle("TTS 时锁定翻页", isOn: $preferences.lockPageOnTTS)

                HStack {
                    Text("跟随缓冲")
                    Slider(value: $preferences.ttsFollowCooldown, in: 0...6, step: 0.5)
                    Text(String(format: "%.1f s", preferences.ttsFollowCooldown)).font(.caption).monospacedDigit().frame(width: 40, alignment: .trailing)
                }

                HStack {
                    Text("分句限制")
                    let chunkLimitBinding = Binding(
                        get: { Double(preferences.ttsSentenceChunkLimit) },
                        set: { preferences.ttsSentenceChunkLimit = Int($0) }
                    )
                    Slider(value: chunkLimitBinding, in: 300...1000, step: 50)
                    Text("\(preferences.ttsSentenceChunkLimit)").font(.caption).monospacedDigit().frame(width: 40, alignment: .trailing)
                }
            }
        }
        .navigationTitle("听书设置")
        .ifAvailableHideTabBar()
        .glassyListStyle()
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
            let ttsList = try await APIService.shared.fetchTTSList()

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
    @StateObject private var preferences = UserPreferences.shared

    var body: some View {
        List {
            Section(header: GlassySectionHeader(title: "搜索设置")) {
                Toggle("书架搜索包含书源", isOn: $preferences.searchSourcesFromBookshelf)
                
                if preferences.searchSourcesFromBookshelf {
                    NavigationLink(destination: PreferredSourcesView()) {
                        Label {
                            HStack {
                                Text("指定搜索源")
                                Spacer()
                                Text(preferences.preferredSearchSourceUrls.isEmpty ? "全部启用源" : "已选 \(preferences.preferredSearchSourceUrls.count) 个")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                        } icon: {
                            Image(systemName: "magnifyingglass")
                        }
                    }
                }
            }

            Section(header: GlassySectionHeader(title: "漫画图片")) {
                Toggle("启用反爬适配", isOn: $preferences.isMangaAntiScrapingEnabled)
                NavigationLink(destination: MangaAntiScrapingSitesView()) {
                    Label {
                        HStack {
                            Text("支持站点")
                            Spacer()
                            let enabledCount = preferences.mangaAntiScrapingEnabledSites.count
                            let totalCount = MangaAntiScrapingService.profiles.count
                            Text(enabledCount >= totalCount ? "已全部启用" : "\(enabledCount)/\(totalCount)")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    } icon: {
                        Image(systemName: "shield.lefthalf.filled")
                    }
                }
                Text("仅针对支持站点追加 Referer/请求头，其他站点仍按书源规则处理")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Section(header: GlassySectionHeader(title: "内容净化")) {
                NavigationLink(destination: ReplaceRuleListView()) {
                    Label("净化规则管理", systemImage: "broom")
                }
            }
            
            Section(header: GlassySectionHeader(title: "书架设置")) {
                Toggle("最近阅读排序", isOn: $preferences.bookshelfSortByRecent)
                Text("开启后按最后阅读时间排序，关闭则按加入书架时间排序")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("内容设置")
        .ifAvailableHideTabBar()
        .glassyListStyle()
    }
}

struct MangaAntiScrapingSitesView: View {
    @StateObject private var preferences = UserPreferences.shared
    private let profiles = MangaAntiScrapingService.profiles

    var body: some View {
        List {
            Section {
                ForEach(profiles) { profile in
                    Toggle(isOn: binding(for: profile.key)) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(profile.name)
                            if !profile.hostSuffixes.isEmpty {
                                Text(profile.hostSuffixes.joined(separator: ", "))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            } footer: {
                Text("站点匹配按域名后缀判断，仅影响图片请求头设置。")
            }
        }
        .navigationTitle("反爬站点")
        .ifAvailableHideTabBar()
        .glassyListStyle()
    }

    private func binding(for key: String) -> Binding<Bool> {
        Binding(
            get: { preferences.mangaAntiScrapingEnabledSites.contains(key) },
            set: { isOn in
                var current = preferences.mangaAntiScrapingEnabledSites
                if isOn {
                    current.insert(key)
                } else {
                    current.remove(key)
                }
                preferences.mangaAntiScrapingEnabledSites = current
            }
        )
    }
}

// MARK: - Helper for URL sharing
struct URLIdentifier: Identifiable {
    let id = UUID()
    let url: URL
}

struct DebugSettingsView: View {
    @StateObject private var preferences = UserPreferences.shared
    @State private var logURLToShare: URLIdentifier? = nil
    @State private var showClearLogsAlert = false
    @State private var showClearCacheAlert = false
    @State private var showLogViewer = false

    var body: some View {
        List {
            Section(header: GlassySectionHeader(title: "调试选项")) {
                Toggle("详细日志模式", isOn: $preferences.isVerboseLoggingEnabled)
                Text("开启后将记录更详细的内容解析与图片加载过程")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Section(header: GlassySectionHeader(title: "日志")) {
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
            
            Section(header: GlassySectionHeader(title: "存储")) {
                Button(action: { showClearCacheAlert = true }) {
                    HStack {
                        Image(systemName: "memorychip")
                        VStack(alignment: .leading, spacing: 2) {
                            Text("清除内存缓存")
                            Text("仅清理运行内存，不影响离线下载内容")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            }
                        Spacer()
                    }
                    .foregroundColor(.orange)
                }
            }
        }
        .navigationTitle("调试工具")
        .ifAvailableHideTabBar()
        .glassyListStyle()
        .sheet(isPresented: $showLogViewer) {
            LogView()
        }
        .sheet(item: $logURLToShare) { ident in
            ActivityView(activityItems: [ident.url])
        }
        .alert("清空日志", isPresented: $showClearLogsAlert) {
            Button("取消", role: .cancel) { }
            Button("清空", role: .destructive) { LogManager.shared.clearLogs() }
        }
        .alert("清除内存缓存", isPresented: $showClearCacheAlert) {
            Button("取消", role: .cancel) { }
            Button("清除", role: .destructive) { APIService.shared.clearLocalCache() }
        }
    }
    private func exportLogs() {
        if let url = LogManager.shared.exportLogs() {
            self.logURLToShare = URLIdentifier(url: url)
        }
    }
}
struct PreferredSourcesView: View {
    @EnvironmentObject var sourceStore: SourceStore
    @StateObject private var preferences = UserPreferences.shared
    @State private var filterText = ""
    
    var filteredSources: [BookSource] {
        let enabled = sourceStore.availableSources.filter { $0.enabled }
        if filterText.isEmpty {
            return enabled
        } else {
            return enabled.filter { $0.bookSourceName.localizedCaseInsensitiveContains(filterText) }
        }
    }
    
    var body: some View {
        List {
            Section(header: GlassySectionHeader(title: "全局开关")) {
                Toggle("搜索书架时包含全网书源", isOn: $preferences.searchSourcesFromBookshelf)
            }
            
            Section(header: GlassySectionHeader(title: "指定搜索源"), footer: Text("未选择任何书源时，将默认搜索所有已启用的书源。")) {
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
                .glassyToolbarButton()
            }
        }
        .ifAvailableHideTabBar()
        .glassyListStyle()
        .task {
            if sourceStore.availableSources.isEmpty {
                await sourceStore.refreshSources()
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
