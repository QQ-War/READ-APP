import SwiftUI
import UIKit

struct ReplaceRuleListView: View {
    @StateObject private var viewModel = ReplaceRuleViewModel()
    @State private var showEditView = false
    @State private var selectedRule: ReplaceRule?
    @State private var showingURLImportDialog = false
    @State private var importURL = ""
    @State private var showingFilePicker = false
    @State private var errorMessageAlert: String?
    @State private var exportItems: [Any] = []
    @State private var showingShareSheet = false
    @State private var isExporting = false

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
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button {
                            Task { await exportRule(rule, toFile: false) }
                        } label: {
                            Label("复制", systemImage: "doc.on.doc")
                        }
                        .tint(.orange)

                        Button {
                            Task { await exportRule(rule, toFile: true) }
                        } label: {
                            Label("导出", systemImage: "square.and.arrow.up")
                        }
                        .tint(.green)
                    }
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
        .sheet(isPresented: $showingShareSheet) {
            ActivityView(activityItems: exportItems)
        }
        .sheet(isPresented: $showingFilePicker) {
            DocumentPicker { url in
                Task {
                    if let content = try? String(contentsOf: url) {
                        try? await APIService.shared.saveReplaceRules(jsonContent: content)
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
        .overlay {
            if isExporting {
                Color.black.opacity(0.2).ignoresSafeArea()
                ProgressView("正在导出...")
                    .padding()
                    .background(Color(UIColor.systemBackground))
                    .cornerRadius(10)
                    .shadow(radius: 10)
            }
        }
    }

    private func exportRule(_ rule: ReplaceRule, toFile: Bool) async {
        await MainActor.run { isExporting = true }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode([rule])
            let json = String(data: data, encoding: .utf8) ?? "[]"
            if toFile {
                let tempDir = FileManager.default.temporaryDirectory
                let sanitizedName = rule.name.replacingOccurrences(of: "/", with: "_")
                    .replacingOccurrences(of: "\\", with: "_")
                    .replacingOccurrences(of: ":", with: "_")
                let fileName = "\(sanitizedName).json"
                let fileURL = tempDir.appendingPathComponent(fileName)
                try json.write(to: fileURL, atomically: true, encoding: .utf8)
                await MainActor.run {
                    exportItems = [fileURL]
                    showingShareSheet = true
                }
            } else {
                UIPasteboard.general.string = json
                await MainActor.run {
                    errorMessageAlert = "已复制到剪贴板"
                }
            }
        } catch {
            await MainActor.run {
                errorMessageAlert = "导出失败: \(error.localizedDescription)"
            }
        }
        await MainActor.run { isExporting = false }
    }
    private func importFromURL() async {
        guard let url = URL(string: importURL) else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let content = String(data: data, encoding: .utf8) {
                try await APIService.shared.saveReplaceRules(jsonContent: content)
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
