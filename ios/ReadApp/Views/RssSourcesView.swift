import SwiftUI

struct RssSourcesView: View {
    @StateObject private var viewModel = RssSourcesViewModel()
    @Environment(\.dismiss) private var dismiss

    @State private var showingFilePicker = false
    @State private var showingURLImportDialog = false
    @State private var importURL = ""
    @State private var importResultMessage: String?
    @State private var showingImportResult = false
    @State private var showingNewSourceEditor = false
    @State private var editingCustomSource: RssSource?
    @State private var detailSource: RssSource?

    var body: some View {
        List {
            Section {
                Text(viewModel.canEdit ? "启用或禁用订阅源将立即同步到服务端。" : "当前账号不可编辑订阅源。")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            if viewModel.remoteSources.isEmpty {
                Section {
                    if viewModel.isLoading {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    } else {
                        Text("暂未获取到订阅源")
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                Section(header: Text("官方订阅")) {
                    ForEach(viewModel.remoteSources) { source in
                        RssSourceRow(
                            source: source,
                            isBusy: viewModel.pendingToggles.contains(source.id),
                            isEnabled: source.enabled,
                            canToggle: viewModel.canEdit,
                            onTap: { detailSource = source }
                        ) { isEnabled in
                            Task {
                                await viewModel.toggle(source: source, enable: isEnabled)
                            }
                        }
                    }
                }
            }

            Section(header: Text("自定义订阅"),
                    footer: viewModel.customSources.isEmpty ? Text("添加后可在本地管理订阅。") : nil) {
                if viewModel.customSources.isEmpty {
                    Text("尚未添加自定义订阅源，可通过上方菜单新建或导入。")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(viewModel.customSources) { source in
                        RssSourceRow(
                            source: source,
                            isBusy: false,
                            isEnabled: source.enabled,
                            canToggle: true,
                            onTap: { editingCustomSource = source }
                        ) { isEnabled in
                            viewModel.toggleCustomSource(source, enable: isEnabled)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                viewModel.deleteCustomSource(source)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                }
            }

            if let error = viewModel.errorMessage {
                Section {
                    Text(error)
                        .foregroundColor(.red)
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await viewModel.refresh()
        }
        .navigationTitle("订阅源")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                }
            }
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button(action: {
                    Task {
                        await viewModel.refresh()
                    }
                }) {
                    Image(systemName: "arrow.clockwise")
                }
                Menu {
                    Button(action: { showingNewSourceEditor = true }) {
                        Label("新建订阅源", systemImage: "pencil.and.outline")
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
        .sheet(isPresented: $showingFilePicker) {
            DocumentPicker { url in
                Task {
                    do {
                        let data = try Data(contentsOf: url)
                        let added = try viewModel.importCustomSources(from: data)
                        importResultMessage = added.isEmpty ? "未找到有效订阅源" : "成功导入 \(added.count) 个订阅源"
                    } catch {
                        importResultMessage = "导入失败: \(error.localizedDescription)"
                    }
                    showingImportResult = true
                }
            }
        }
        .sheet(item: $editingCustomSource) { source in
            NavigationView {
                RssSourceEditView(
                    initialSource: source,
                    onSave: { updated in
                        viewModel.addOrUpdateCustomSource(updated)
                        editingCustomSource = nil
                    },
                    onDelete: {
                        viewModel.deleteCustomSource(source)
                        editingCustomSource = nil
                    }
                )
            }
        }
        .sheet(isPresented: $showingNewSourceEditor) {
            NavigationView {
                RssSourceEditView(initialSource: nil) { newSource in
                    viewModel.addOrUpdateCustomSource(newSource)
                    showingNewSourceEditor = false
                }
            }
        }
        .sheet(item: $detailSource) { source in
            NavigationView {
                RssSourceDetailView(source: source)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("关闭") { detailSource = nil }
                        }
                    }
            }
        }
        .alert("网络导入", isPresented: $showingURLImportDialog) {
            TextField("输入订阅 JSON 地址", text: $importURL)
                .autocapitalization(.none)
            Button("导入") {
                Task {
                    guard let url = URL(string: importURL) else {
                        importResultMessage = "请输入合法 URL"
                        showingImportResult = true
                        return
                    }
                    do {
                        let (data, _) = try await URLSession.shared.data(from: url)
                        let added = try viewModel.importCustomSources(from: data)
                        importResultMessage = added.isEmpty ? "未找到有效订阅源" : "成功导入 \(added.count) 个订阅源"
                    } catch {
                        importResultMessage = "导入失败: \(error.localizedDescription)"
                    }
                    showingImportResult = true
                }
                importURL = ""
            }
            Button("取消", role: .cancel) { importURL = "" }
        } message: {
            Text("请输入合法的订阅源 JSON 地址")
        }
        .alert("导入结果", isPresented: $showingImportResult) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(importResultMessage ?? "")
        }
    }
}

private struct RssSourceRow: View {
    let source: RssSource
    let isBusy: Bool
    let isEnabled: Bool
    let canToggle: Bool
    let onTap: (() -> Void)?
    let onToggle: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(source.sourceName ?? source.sourceUrl)
                    .font(.body)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { isEnabled },
                    set: {
                        guard canToggle && !isBusy else { return }
                        onToggle($0)
                    }
                ))
                .labelsHidden()
                .disabled(!canToggle || isBusy)
            }

            if let group = source.sourceGroup, !group.isEmpty {
                Text(group.split(separator: ",").first.map(String.init) ?? group)
                    .font(.caption)
                    .foregroundColor(.accentColor)
            }

            if let comment = source.variableComment, !comment.isEmpty {
                Text(comment)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap?()
        }
    }
}
