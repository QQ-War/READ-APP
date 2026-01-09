import SwiftUI

struct RssSourceEditView: View {
    let initialSource: RssSource?
    let onSave: (RssSource) -> Void
    let onDelete: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var sourceName: String
    @State private var sourceUrl: String
    @State private var sourceGroup: String
    @State private var variableComment: String
    @State private var sourceIcon: String
    @State private var loginUrl: String
    @State private var loginUi: String
    @State private var isEnabled: Bool
    @State private var showingError = false
    @State private var errorMessage: String?

    init(initialSource: RssSource?, onSave: @escaping (RssSource) -> Void, onDelete: (() -> Void)? = nil) {
        self.initialSource = initialSource
        self.onSave = onSave
        self.onDelete = onDelete
        _sourceName = State(initialValue: initialSource?.sourceName ?? "")
        _sourceUrl = State(initialValue: initialSource?.sourceUrl ?? "")
        _sourceGroup = State(initialValue: initialSource?.sourceGroup ?? "")
        _variableComment = State(initialValue: initialSource?.variableComment ?? "")
        _sourceIcon = State(initialValue: initialSource?.sourceIcon ?? "")
        _loginUrl = State(initialValue: initialSource?.loginUrl ?? "")
        _loginUi = State(initialValue: initialSource?.loginUi ?? "")
        _isEnabled = State(initialValue: initialSource?.enabled ?? true)
    }

    var body: some View {
        Form {
            Section(header: Text("基础信息")) {
                TextField("订阅名称（可选）", text: $sourceName)
                TextField("订阅链接", text: $sourceUrl)
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                Toggle("启用该订阅", isOn: $isEnabled)
            }

            Section(header: Text("分组与备注")) {
                TextField("分组标签", text: $sourceGroup)
                TextField("备注", text: $variableComment)
            }

            Section(header: Text("高级信息（可选）")) {
                TextField("图标地址", text: $sourceIcon)
                    .autocapitalization(.none)
                TextField("登录地址", text: $loginUrl)
                    .autocapitalization(.none)
                TextField("登录界面", text: $loginUi)
                    .autocapitalization(.none)
            }

            if initialSource != nil {
                Section {
                    Button(role: .destructive) {
                        onDelete?()
                        dismiss()
                    } label: {
                        Text("删除订阅源")
                    }
                }
            }
        }
        .navigationTitle(initialSource == nil ? "新建订阅" : "编辑订阅")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    save()
                }
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") {
                    dismiss()
                }
            }
        }
        .alert("校验失败", isPresented: $showingError) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func save() {
        let trimmedUrl = sourceUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUrl.isEmpty, let _ = URL(string: trimmedUrl) else {
            errorMessage = "请输入合法的订阅 URL"
            showingError = true
            return
        }
        let rss = RssSource(
            sourceUrl: trimmedUrl,
            sourceName: sourceName.isEmpty ? nil : sourceName,
            sourceIcon: sourceIcon.isEmpty ? nil : sourceIcon,
            sourceGroup: sourceGroup.isEmpty ? nil : sourceGroup,
            loginUrl: loginUrl.isEmpty ? nil : loginUrl,
            loginUi: loginUi.isEmpty ? nil : loginUi,
            variableComment: variableComment.isEmpty ? nil : variableComment,
            enabled: isEnabled
        )
        onSave(rss)
        dismiss()
    }
}
