import SwiftUI

struct ReplaceRuleListView: View {
    @StateObject private var viewModel = ReplaceRuleViewModel()
    @EnvironmentObject var apiService: APIService
    @State private var showEditView = false
    @State private var selectedRule: ReplaceRule?
    @State private var showingURLImportDialog = false
    @State private var importURL = ""
    @State private var showingFilePicker = false
    @State private var errorMessageAlert: String?

    var body: some View {
        List {
            if viewModel.isLoading && viewModel.rules.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
            } else {
                ForEach(viewModel.rules, id: \.identifiableId) { rule in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(rule.name)
                                .font(.headline)
                            Spacer()
                            if let group = rule.groupname, !group.isEmpty {
                                Text(group)
                                    .font(.footnote)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.2))
                                    .cornerRadius(6)
                            }
                        }

                        Text("模式: \(rule.pattern)")
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(2)
                        
                        Text("替换: \(rule.replacement)")
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(2)

                        HStack {
                            Text("顺序: \(rule.ruleorder ?? 0)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Spacer()
                            Toggle(isOn: Binding(
                                get: { rule.isEnabled ?? true },
                                set: { newValue in
                                    Task {
                                        await viewModel.toggleRule(rule: rule, isEnabled: newValue)
                                    }
                                }
                            )) {
                                Text("启用").font(.caption2)
                            }
                            .scaleEffect(0.8) // Make toggle smaller
                        }
                    }
                    .padding(.vertical, 4)
                    .onTapGesture {
                        self.selectedRule = rule
                        self.showEditView = true
                    }
                }
                .onDelete(perform: deleteRule)
            }
        }
        .navigationTitle("净化规则管理")
        .ifAvailableHideTabBar()
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(action: {
                        self.selectedRule = nil
                        self.showEditView = true
                    }) {
                        Label("新建规则", systemImage: "pencil.and.outline")
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
        .sheet(isPresented: $showEditView) {
            ReplaceRuleEditView(viewModel: viewModel, rule: selectedRule)
        }
        .sheet(isPresented: $showingFilePicker) {
            DocumentPicker { url in
                Task {
                    if let content = try? String(contentsOf: url) {
                        try? await apiService.saveReplaceRules(jsonContent: content)
                        await viewModel.fetchRules()
                    }
                }
            }
        }
        .alert("网络导入", isPresented: $showingURLImportDialog) {
            TextField("输入规则 URL", text: $importURL)
                .autocapitalization(.none)
            Button("导入") {
                Task { await importFromURL() }
            }
            Button("取消", role: .cancel) { importURL = "" }
        } message: {
            Text("请输入合法的规则 JSON 地址")
        }
        .alert("错误", isPresented: .constant(errorMessageAlert != nil)) {
            Button("确定") { errorMessageAlert = nil }
        } message: {
            if let error = errorMessageAlert { Text(error) }
        }
        .onAppear {
            Task {
                await viewModel.fetchRules()
            }
        }
    }

    private func importFromURL() async {
        guard let url = URL(string: importURL) else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let content = String(data: data, encoding: .utf8) {
                try await apiService.saveReplaceRules(jsonContent: content)
                await viewModel.fetchRules()
            }
        } catch {
            await MainActor.run {
                errorMessageAlert = "导入失败: \(error.localizedDescription)"
            }
        }
        importURL = ""
    }

    private func deleteRule(at offsets: IndexSet) {
        let rulesToDelete = offsets.map { viewModel.rules[$0] }
        Task {
            for rule in rulesToDelete {
                await viewModel.deleteRule(rule: rule)
            }
        }
    }
}

struct ReplaceRuleListView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            ReplaceRuleListView()
        }
    }
}
