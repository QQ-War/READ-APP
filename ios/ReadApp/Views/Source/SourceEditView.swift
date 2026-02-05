import SwiftUI

struct SourceEditView: View {
    @Environment(\.dismiss) var dismiss
    
    // If provided, we are editing an existing source
    var sourceId: String?
    
    @State private var jsonContent: String = ""
    @State private var structuredSource: FullBookSource = FullBookSource()
    @State private var editMode: EditViewMode = .structured
    
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showSuccessMessage = false
    @State private var showDeleteConfirmation = false

    private var isEditing: Bool { sourceId != nil }
    
    enum EditViewMode {
        case structured, raw
    }
    
    var body: some View {
        VStack(spacing: 0) {
            Picker("编辑模式", selection: $editMode) {
                Text("结构化").tag(EditViewMode.structured)
                Text("源码 (JSON)").tag(EditViewMode.raw)
            }
            .pickerStyle(.segmented)
            .padding()
            .background(Color(.systemGroupedBackground))
            
            if isLoading {
                Spacer()
                ProgressView("正在加载...")
                Spacer()
            } else {
                if editMode == .structured {
                    structuredForm
                } else {
                    rawEditor
                }
            }
            
            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding()
            }
        }
        .navigationTitle(sourceId == nil ? "新建书源" : "编辑书源")
        .navigationBarTitleDisplayMode(.inline)
        .ifAvailableHideTabBar()
        .glassyListStyle()
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("保存") {
                    saveSource()
                }
                .disabled(isLoading)
                .glassyToolbarButton()
            }
        }
        .onAppear {
            if let id = sourceId, jsonContent.isEmpty {
                loadSourceDetail(id: id)
            }
        }
        .alert("保存成功", isPresented: $showSuccessMessage) {
            Button("确定", role: .cancel) { }
        }
        .alert("确定删除吗？", isPresented: $showDeleteConfirmation) {
            Button("取消", role: .cancel) { }
            Button("确定删除", role: .destructive) {
                deleteSource()
            }
        } message: {
            Text("删除书源后无法恢复，确定要继续吗？")
        }
        .onChange(of: editMode) { newValue in
            if newValue == .raw {
                syncToRaw()
            } else {
                syncToStructured()
            }
        }
    }
    
    private var structuredForm: some View {
        Form {
            Section(header: GlassySectionHeader(title: "基本信息")) {
                TextField("书源名称", text: $structuredSource.bookSourceName)
                TextField("书源分组", text: Binding(
                    get: { structuredSource.bookSourceGroup ?? "" },
                    set: { structuredSource.bookSourceGroup = $0.isEmpty ? nil : $0 }
                ))
                TextField("书源地址 (URL)", text: $structuredSource.bookSourceUrl)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                
                Picker("书源类型", selection: $structuredSource.bookSourceType) {
                    Text("文本").tag(0)
                    Text("音频").tag(1)
                    Text("图片").tag(2)
                }
            }
            
            Section(header: GlassySectionHeader(title: "网络配置")) {
                TextField("并发频率", text: Binding(
                    get: { structuredSource.concurrentRate ?? "" },
                    set: { structuredSource.concurrentRate = $0.isEmpty ? nil : $0 }
                ))
                TextField("自定义 Header", text: Binding(
                    get: { structuredSource.header ?? "" },
                    set: { structuredSource.header = $0.isEmpty ? nil : $0 }
                ))
                Toggle("启用 CookieJar", isOn: Binding(
                    get: { structuredSource.enabledCookieJar ?? false },
                    set: { structuredSource.enabledCookieJar = $0 }
                ))
            }
            
            Section(header: GlassySectionHeader(title: "搜索配置")) {
                TextField("搜索地址", text: Binding(
                    get: { structuredSource.searchUrl ?? "" },
                    set: { structuredSource.searchUrl = $0.isEmpty ? nil : $0 }
                ))
                
                NavigationLink("搜索规则详情") {
                    SearchRuleView(rule: $structuredSource.ruleSearch)
                }
            }
            
            Section(header: GlassySectionHeader(title: "详情页与目录规则")) {
                NavigationLink("详情页规则") {
                    BookInfoRuleView(rule: $structuredSource.ruleBookInfo)
                }
                NavigationLink("目录页规则") {
                    TocRuleView(rule: $structuredSource.ruleToc)
                }
            }
            
            Section(header: GlassySectionHeader(title: "正文规则")) {
                NavigationLink("正文页规则") {
                    ContentRuleView(rule: $structuredSource.ruleContent)
                }
            }
            
            Section(header: GlassySectionHeader(title: "其他")) {
                Toggle("启用此书源", isOn: $structuredSource.enabled)
                Toggle("启用发现", isOn: $structuredSource.enabledExplore)
                TextField("书源注释", text: Binding(
                    get: { structuredSource.bookSourceComment ?? "" },
                    set: { structuredSource.bookSourceComment = $0.isEmpty ? nil : $0 }
                ))
            }
            
            if isEditing {
                Section {
                    Button(role: .destructive, action: { showDeleteConfirmation = true }) {
                        HStack {
                            Spacer()
                            Text("删除此书源")
                            Spacer()
                        }
                    }
                }
            }
        }
    }
    
    private var rawEditor: some View {
        VStack {
            TextEditor(text: $jsonContent)
                .font(.system(.body, design: .monospaced))
                .padding(4)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2)))
                .padding()
            
            Text("提示：直接编辑 JSON 源码可能会破坏结构，请谨慎操作。")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.bottom)
        }
    }
    
    private func deleteSource() {
        guard let id = sourceId else { return }
        isLoading = true
        Task {
            do {
                try await APIService.shared.deleteBookSource(id: id)
                await MainActor.run {
                    isLoading = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "删除失败: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }
    
    private func loadSourceDetail(id: String) {
        isLoading = true
        Task {
            do {
                let json = try await APIService.shared.getBookSourceDetail(id: id)
                await MainActor.run {
                    self.jsonContent = json
                    syncToStructured()
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "加载失败: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }
    
    private func syncToRaw() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(structuredSource),
           let json = String(data: data, encoding: .utf8) {
            self.jsonContent = json
        }
    }
    
    private func syncToStructured() {
        guard let data = jsonContent.data(using: .utf8) else { return }
        if let decoded = try? JSONDecoder().decode(FullBookSource.self, from: data) {
            self.structuredSource = decoded
        }
    }
    
    private func saveSource() {
        isLoading = true
        errorMessage = nil
        
        // 最终保存前根据当前模式同步数据
        if editMode == .structured {
            syncToRaw()
        } else {
            syncToStructured()
        }
        
        Task {
            do {
                try await APIService.shared.saveBookSource(jsonContent: jsonContent)
                await MainActor.run {
                    self.isLoading = false
                    self.showSuccessMessage = true
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "保存失败: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }
}

// MARK: - Sub-Rule Views

struct SearchRuleView: View {
    @Binding var rule: SearchRule?
    
    var body: some View {
        Form {
            Section(header: GlassySectionHeader(title: "列表规则")) {
                TextField("列表规则 (bookList)", text: Binding(get: { rule?.bookList ?? "" }, set: { ensureRule(); rule?.bookList = $0 }))
            }
            Section(header: GlassySectionHeader(title: "字段规则")) {
                TextField("书名 (name)", text: Binding(get: { rule?.name ?? "" }, set: { ensureRule(); rule?.name = $0 }))
                TextField("作者 (author)", text: Binding(get: { rule?.author ?? "" }, set: { ensureRule(); rule?.author = $0 }))
                TextField("简介 (intro)", text: Binding(get: { rule?.intro ?? "" }, set: { ensureRule(); rule?.intro = $0 }))
                TextField("书籍 URL (bookUrl)", text: Binding(get: { rule?.bookUrl ?? "" }, set: { ensureRule(); rule?.bookUrl = $0 }))
                TextField("封面 URL (coverUrl)", text: Binding(get: { rule?.coverUrl ?? "" }, set: { ensureRule(); rule?.coverUrl = $0 }))
            }
        }
        .navigationTitle("搜索规则")
    }
    
    @discardableResult
    private func ensureRule() -> SearchRule {
        if rule == nil { rule = SearchRule() }
        return rule!
    }
}

struct BookInfoRuleView: View {
    @Binding var rule: BookInfoRule?
    
    var body: some View {
        Form {
            Section(header: GlassySectionHeader(title: "详情页字段")) {
                TextField("书名", text: Binding(get: { rule?.name ?? "" }, set: { ensureRule(); rule?.name = $0 }))
                TextField("作者", text: Binding(get: { rule?.author ?? "" }, set: { ensureRule(); rule?.author = $0 }))
                TextField("简介", text: Binding(get: { rule?.intro ?? "" }, set: { ensureRule(); rule?.intro = $0 }))
                TextField("封面 URL", text: Binding(get: { rule?.coverUrl ?? "" }, set: { ensureRule(); rule?.coverUrl = $0 }))
                TextField("目录 URL (tocUrl)", text: Binding(get: { rule?.tocUrl ?? "" }, set: { ensureRule(); rule?.tocUrl = $0 }))
            }
        }
        .navigationTitle("详情页规则")
    }
    
    @discardableResult
    private func ensureRule() -> BookInfoRule {
        if rule == nil { rule = BookInfoRule() }
        return rule!
    }
}

struct TocRuleView: View {
    @Binding var rule: TocRule?
    
    var body: some View {
        Form {
            Section(header: GlassySectionHeader(title: "目录列表")) {
                TextField("章节列表 (chapterList)", text: Binding(get: { rule?.chapterList ?? "" }, set: { ensureRule(); rule?.chapterList = $0 }))
            }
            Section(header: GlassySectionHeader(title: "章节详情")) {
                TextField("章节名称 (chapterName)", text: Binding(get: { rule?.chapterName ?? "" }, set: { ensureRule(); rule?.chapterName = $0 }))
                TextField("章节 URL (chapterUrl)", text: Binding(get: { rule?.chapterUrl ?? "" }, set: { ensureRule(); rule?.chapterUrl = $0 }))
            }
        }
        .navigationTitle("目录规则")
    }
    
    @discardableResult
    private func ensureRule() -> TocRule {
        if rule == nil { rule = TocRule() }
        return rule!
    }
}

struct ContentRuleView: View {
    @Binding var rule: ContentRule?
    
    var body: some View {
        Form {
            Section(header: GlassySectionHeader(title: "正文内容")) {
                TextField("正文规则 (content)", text: Binding(get: { rule?.content ?? "" }, set: { ensureRule(); rule?.content = $0 }))
                TextField("下一页 URL (nextContentUrl)", text: Binding(get: { rule?.nextContentUrl ?? "" }, set: { ensureRule(); rule?.nextContentUrl = $0 }))
            }
            Section(header: GlassySectionHeader(title: "净化规则")) {
                TextField("替换正则 (replaceRegex)", text: Binding(get: { rule?.replaceRegex ?? "" }, set: { ensureRule(); rule?.replaceRegex = $0 }))
            }
        }
        .navigationTitle("正文规则")
    }
    
    @discardableResult
    private func ensureRule() -> ContentRule {
        if rule == nil { rule = ContentRule() }
        return rule!
    }
}
