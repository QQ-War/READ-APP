import SwiftUI
import UIKit

struct RssSourcesView: View {
    @StateObject private var viewModel = RssSourcesViewModel()
    @Environment(\.dismiss) private var dismiss
    @StateObject private var preferences = UserPreferences.shared

    @State private var showingFilePicker = false
    @State private var showingURLImportDialog = false
    @State private var importURL = ""
    @State private var importResultMessage: String?
    @State private var showingImportResult = false
    
    @State private var showingRemoteSourceEditor = false
    @State private var editingRemoteSource: RssSource?
    @State private var detailSource: RssSource?
    
    // 导出相关
    private struct SharePayload: Identifiable {
        let id = UUID()
        let items: [Any]
    }
    @State private var sharePayload: SharePayload?
    @State private var isExporting = false

    var body: some View {
        ZStack {
            // 路由跳转
            if let source = editingRemoteSource {
                NavigationLink(
                    destination: RssSourceEditView(
                        initialSource: source,
                        onSave: { updated in
                            Task {
                                await viewModel.saveRemoteSource(updated, remoteId: source.id)
                                editingRemoteSource = nil
                            }
                        },
                        onDelete: {
                            Task {
                                await viewModel.deleteRemoteSource(source)
                                editingRemoteSource = nil
                            }
                        }
                    ),
                    isActive: Binding(
                        get: { editingRemoteSource != nil },
                        set: { if !$0 { editingRemoteSource = nil } }
                    )
                ) { EmptyView() }
            }
            
            sourceListView

            if isExporting {
                Color.black.opacity(0.2).ignoresSafeArea()
                ProgressView("正在导出...")
                    .padding()
                    .background(Color(UIColor.systemBackground))
                    .cornerRadius(10)
                    .shadow(radius: 10)
            }
        }
        .navigationTitle("订阅源")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button(action: {
                    Task { await viewModel.refresh() }
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
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("取消") { showingRemoteSourceEditor = false }
                    }
                }
            }
        }
        .sheet(item: $sharePayload) { payload in
            ActivityView(activityItems: payload.items)
        }
        .alert("网络导入", isPresented: $showingURLImportDialog) {
            TextField("输入订阅 JSON 地址", text: $importURL)
                .autocapitalization(.none)
            Button("导入") {
                Task { await importFromURL() }
            }
            Button("取消", role: .cancel) { importURL = "" }
        } message: {
            Text("请输入合法的订阅源 JSON 地址")
        }
        .alert("提示", isPresented: $showingImportResult) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(importResultMessage ?? "")
        }
    }

    @ViewBuilder
    private var sourceListView: some View {
        List {
            Section {
                Text(viewModel.canEdit ? "启用或禁用订阅源将立即同步到服务端。" : "当前账号不可编辑订阅源。")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .listRowBackground(preferences.isLiquidGlassEnabled ? Color.clear : nil)

            if viewModel.remoteSources.isEmpty && !viewModel.isLoading {
                Section {
                    Text("暂未获取到订阅源")
                        .foregroundColor(.secondary)
                }
                .listRowBackground(preferences.isLiquidGlassEnabled ? Color.clear : nil)
            } else {
                ForEach(viewModel.remoteSources) { source in
                    rssSourceRow(source)
                        .listRowBackground(preferences.isLiquidGlassEnabled ? Color.clear : nil)
                }
            }
        }
        .listStyle(.insetGrouped)
        .glassyListStyle()
        .refreshable {
            await viewModel.refresh()
        }
        .overlay {
            if viewModel.isLoading && viewModel.remoteSources.isEmpty {
                ProgressView("正在加载...")
            }
        }
    }

    @ViewBuilder
    private func rssSourceRow(_ source: RssSource) -> some View {
        HStack(spacing: 12) {
            // 点击进入网页
            Button(action: {
                if let url = URL(string: source.sourceUrl) {
                    UIApplication.shared.open(url)
                }
            }) {
                HStack(spacing: 12) {
                    if let iconUrl = source.sourceIcon, let url = URL(string: iconUrl) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().scaledToFill()
                            default:
                                Image(systemName: "rss")
                                    .foregroundColor(.accentColor)
                                    .background(Color.accentColor.opacity(0.1))
                            }
                        }
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        Image(systemName: "rss")
                            .font(.title3)
                            .frame(width: 40, height: 40)
                            .foregroundColor(.accentColor)
                            .background(Color.accentColor.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(source.sourceName ?? source.sourceUrl)
                            .font(.headline)
                            .foregroundColor(source.enabled ? .primary : .secondary)
                        
                        if let group = source.sourceGroup, !group.isEmpty {
                            Text(group)
                                .font(.caption)
                                .foregroundColor(.accentColor)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            
            Toggle("", isOn: Binding(
                get: { source.enabled },
                set: { _ in
                    Task { await viewModel.toggle(source: source, enable: !source.enabled) }
                }
            ))
            .labelsHidden()
            .scaleEffect(0.7)
            .disabled(!viewModel.canEdit || viewModel.pendingToggles.contains(source.id))
        }
        .padding(.vertical, 8)
        .glassyCard(cornerRadius: 14, padding: 6)
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                if let url = URL(string: source.sourceUrl) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Label("打开", systemImage: "safari")
            }
            .tint(.blue)

            Button {
                UIPasteboard.general.string = source.sourceUrl
                importResultMessage = "已复制链接"
                showingImportResult = true
            } label: {
                Label("复制", systemImage: "doc.on.doc")
            }
            .tint(.orange)
            
            Button {
                Task { await exportSource(source) }
            } label: {
                Label("导出", systemImage: "square.and.arrow.up")
            }
            .tint(.green)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                editingRemoteSource = source
            } label: {
                Label("编辑", systemImage: "pencil")
            }
            .tint(.blue)
            .disabled(!viewModel.canEdit)
            
            Button(role: .destructive) {
                Task { await viewModel.deleteRemoteSource(source) }
            } label: {
                Label("删除", systemImage: "trash")
            }
            .disabled(!viewModel.canEdit)
        }
    }

    private func importFromURL() async {
        guard let url = URL(string: importURL) else {
            await MainActor.run {
                importResultMessage = "请输入合法 URL"
                showingImportResult = true
            }
            return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let added = try await viewModel.importCustomSources(from: data)
            await MainActor.run {
                importResultMessage = added.isEmpty ? "未找到有效订阅源" : "成功导入 \(added.count) 个订阅源"
                showingImportResult = true
                importURL = ""
            }
        } catch {
            await MainActor.run {
                importResultMessage = "导入失败: \(error.localizedDescription)"
                showingImportResult = true
            }
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
                        importResultMessage = "导入成功 (\(added.count))"
                        showingImportResult = true
                    }
                } else {
                    await MainActor.run {
                        importResultMessage = "内容无效"
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

    private func exportSource(_ source: RssSource) async {
        isExporting = true
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(source)
            
            let tempDir = FileManager.default.temporaryDirectory
            let fileName = "\((source.sourceName ?? "source").replacingOccurrences(of: "/", with: "_")).json"
            let fileURL = tempDir.appendingPathComponent(fileName)
            try data.write(to: fileURL)
            
            sharePayload = SharePayload(items: [fileURL])
        } catch {
            importResultMessage = "导出失败: \(error.localizedDescription)"
            showingImportResult = true
        }
        isExporting = false
    }
}
