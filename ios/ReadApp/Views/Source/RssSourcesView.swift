import SwiftUI

struct RssSourcesView: View {
    @StateObject private var viewModel = RssSourcesViewModel()
    @Environment(\.dismiss) private var dismiss

    @State private var showingFilePicker = false
    @State private var showingURLImportDialog = false
    @State private var importURL = ""
    @State private var importResultMessage: String?
    @State private var showingImportResult = false
    @State private var showingRemoteSourceEditor = false
    @State private var editingRemoteSource: RssSource?
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
                Section(header: GlassySectionHeader(title: "我的订阅")) {
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

            if let error = viewModel.errorMessage {
                Section {
                    Text(error)
                        .foregroundColor(.red)
                }
            }
        }
        .listStyle(.insetGrouped)
        .glassyListStyle()
        .refreshable {
            await viewModel.refresh()
        }
        .navigationTitle("订阅源")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button(action: {
                    Task {
                        await viewModel.refresh()
                    }
                }) {
                    Image(systemName: "arrow.clockwise")
                }
                .glassyToolbarButton()
                Menu {
                    Button(action: { showingRemoteSourceEditor = true }) {
                        Label("新建订阅源", systemImage: "pencil.and.outline")
                    }
                    .disabled(!viewModel.canEdit || viewModel.isRemoteOperationInProgress)
                    
                    Button(action: { importFromClipboard() }) {
                        Label("从剪贴板导入", systemImage: "doc.on.clipboard")
                    }
                    .disabled(!viewModel.canEdit || viewModel.isRemoteOperationInProgress)
                    Button(action: { showingFilePicker = true }) {
                        Label("本地导入", systemImage: "folder")
                    }
                    .disabled(!viewModel.canEdit || viewModel.isRemoteOperationInProgress)
                    Button(action: { showingURLImportDialog = true }) {
                        Label("网络导入", systemImage: "link")
                    }
                    .disabled(!viewModel.canEdit || viewModel.isRemoteOperationInProgress)
                } label: {
                    Image(systemName: "plus")
                }
                .glassyToolbarButton()
            }
        }
        .sheet(isPresented: $showingFilePicker) {
            DocumentPicker { url in
                Task {
                    do {
                        let data = try Data(contentsOf: url)
                        let added = try await viewModel.importCustomSources(from: data)
                        importResultMessage = added.isEmpty ? "未找到有效订阅源" : "成功导入 \(added.count) 个订阅源"
                    } catch {
                        importResultMessage = "导入失败: \(error.localizedDescription)"
                    }
                    showingImportResult = true
                }
            }
        }
        .sheet(isPresented: $showingRemoteSourceEditor) {
            NavigationView {
                RssSourceEditView(initialSource: nil) { newSource in
                    Task {
                        await viewModel.saveRemoteSource(newSource)
                        await MainActor.run { showingRemoteSourceEditor = false }
                    }
                }
            }
        }
        .sheet(item: $editingRemoteSource) { source in
            NavigationView {
                RssSourceEditView(
                    initialSource: source,
                    onSave: { updated in
                        Task {
                            await viewModel.saveRemoteSource(updated, remoteId: source.id)
                            await MainActor.run { editingRemoteSource = nil }
                        }
                    },
                    onDelete: {
                        Task {
                            await viewModel.deleteRemoteSource(source)
                            await MainActor.run { editingRemoteSource = nil }
                        }
                    }
                )
            }
        }
        .sheet(item: $detailSource) { source in
            NavigationView {
                RssSourceDetailView(
                    source: source,
                    canEdit: viewModel.canModifyRemoteSources,
                    isEditingBusy: viewModel.isRemoteOperationInProgress,
                    onEdit: {
                        editingRemoteSource = source
                    },
                    onDelete: {
                        Task {
                            await viewModel.deleteRemoteSource(source)
                        }
                        detailSource = nil
                    }
                )
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
                        let added = try await viewModel.importCustomSources(from: data)
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

    private func importFromClipboard() {
        guard let content = UIPasteboard.general.string, !content.isEmpty else {
            importResultMessage = "剪贴板为空"
            showingImportResult = true
            return
        }
        
        Task {
            do {
                if let data = content.data(using: .utf8) {
                    let added = try await viewModel.importCustomSources(from: data)
                    await MainActor.run {
                        importResultMessage = added.isEmpty ? "未找到有效订阅源" : "成功导入 \(added.count) 个订阅源"
                        showingImportResult = true
                    }
                } else {
                    await MainActor.run {
                        importResultMessage = "剪贴板内容无效"
                        showingImportResult = true
                    }
                }
            } catch {
                await MainActor.run {
                    importResultMessage = "导入失败: \(error.localizedDescription)"
                    showingImportResult = true
                }
            }
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
        HStack(alignment: .center, spacing: 12) {
            Button(action: {
                if let url = URL(string: source.sourceUrl) {
                    UIApplication.shared.open(url)
                }
            }) {
                if let iconUrl = source.sourceIcon, let url = URL(string: iconUrl) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                                .frame(width: 40, height: 40)
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: 40, height: 40)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        default:
                            placeholderIcon
                        }
                    }
                } else {
                    placeholderIcon
                }
            }
            .buttonStyle(PlainButtonStyle())

            VStack(alignment: .leading, spacing: 4) {
                Text(source.sourceName ?? source.sourceUrl)
                    .font(.body)
                    .foregroundColor(.primary)
                if let group = source.sourceGroup, !group.isEmpty {
                    Text(group.split(separator: ",").first.map(String.init) ?? group)
                        .font(.caption)
                        .foregroundColor(.accentColor)
                }
                if let comment = source.variableComment, !comment.isEmpty {
                    Text(comment)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            .onTapGesture {
                onTap?()
            }

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
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private var placeholderIcon: some View {
        Image(systemName: "rss")
            .font(.title3)
            .frame(width: 40, height: 40)
            .foregroundColor(.accentColor)
            .background(Color.accentColor.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
