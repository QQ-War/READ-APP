import SwiftUI

struct SourceListView: View {
    @EnvironmentObject var bookshelfStore: BookshelfStore
    @StateObject private var viewModel = SourceListViewModel()
    
    @State private var showAddResultAlert = false
    @State private var addResultMessage = ""

    @State private var showingURLImportDialog = false
    @State private var importURL = ""
    @State private var showingFilePicker = false
    
    // 分组展开状态
    @State private var expandedGroups: Set<String> = []
    @State private var sourceIdToEdit: String? = nil
    @State private var selectedSourceForExplore: BookSource? = nil

    var groupedSources: [(key: String, value: [BookSource])] {
        let dict = Dictionary(grouping: viewModel.filteredSources) { $0.bookSourceGroup?.isEmpty == false ? $0.bookSourceGroup! : "未分组" }
        return dict.sorted { $0.key < $1.key }
    }

    var body: some View {
        ZStack {
            if let id = sourceIdToEdit {
                NavigationLink(
                    destination: SourceEditView(sourceId: id),
                    isActive: Binding(
                        get: { sourceIdToEdit != nil },
                        set: { if !$0 { sourceIdToEdit = nil } }
                    )
                ) { EmptyView() }
            }
            
            if let source = selectedSourceForExplore {
                NavigationLink(
                    destination: SourceExploreContainerView(source: source, bookshelfStore: bookshelfStore),
                    isActive: Binding(
                        get: { selectedSourceForExplore != nil },
                        set: { if !$0 { selectedSourceForExplore = nil } }
                    )
                ) { EmptyView() }
            }
            
            sourceManagementView
        }
        .navigationTitle("书源管理")
        .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        NavigationLink(destination: SourceEditView()) {
                            Label("新建书源", systemImage: "pencil.and.outline")
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
                                if let content = try? String(contentsOf: url) {
                            try? await APIService.shared.saveBookSource(jsonContent: content)
                            viewModel.fetchSources()
                                }
                            }
                        }
            }
            .alert("网络导入", isPresented: $showingURLImportDialog) {
                TextField("输入书源 URL", text: $importURL)
                    .autocapitalization(.none)
                Button("导入") {
                    Task { await importFromURL() }
                }
                Button("取消", role: .cancel) { importURL = "" }
            } message: {
                Text("请输入合法的书源 JSON 地址")
            }
            .alert("加入书架", isPresented: $showAddResultAlert) {
                Button("确定", role: .cancel) { }
            } message: {
                Text(addResultMessage)
            }
    }
    
    private func importFromURL() async {
        guard let url = URL(string: importURL) else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let content = String(data: data, encoding: .utf8) {
                try await APIService.shared.saveBookSource(jsonContent: content)
                viewModel.fetchSources()
            }
        } catch {
            _ = await MainActor.run {
                addResultMessage = "导入失败: \(error.localizedDescription)"
                showAddResultAlert = true
            }
        }
        importURL = ""
    }
    
    @ViewBuilder
    private var sourceManagementView: some View {
        ZStack {
            if viewModel.isLoading && viewModel.sources.isEmpty {
                ProgressView("正在加载书源...")
            } else if let errorMessage = viewModel.errorMessage {
                VStack {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .padding()
                    Button("重试") {
                        viewModel.fetchSources()
                    }
                }
            }
            else {
                List {
                    ForEach(groupedSources, id: \.key) { group in
                        Section(header: groupHeader(name: group.key, count: group.value.count)) {
                            if expandedGroups.contains(group.key) {
                                ForEach(group.value) { source in
                                    sourceRow(source)
                                }
                            }
                        }
                    }
                }
                .listStyle(InsetGroupedListStyle())
                .refreshable {
                    viewModel.fetchSources()
                }
                .searchable(text: $viewModel.searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "过滤书源...")
            }
        }
    }

    private func groupHeader(name: String, count: Int) -> some View {
        Button(action: {
            withAnimation {
                if expandedGroups.contains(name) {
                    expandedGroups.remove(name)
                } else {
                    expandedGroups.insert(name)
                }
            }
        }) {
            HStack {
                Text(name)
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
                Text("\(count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .rotationEffect(.degrees(expandedGroups.contains(name) ? 90 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func sourceRow(_ source: BookSource) -> some View {
        HStack(spacing: 12) {
            // 点击进入详情 (占据除开关以外的所有空间)
            Button(action: { selectedSourceForExplore = source }) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(source.bookSourceName)
                        .font(.headline)
                        .foregroundColor(source.enabled ? .primary : .secondary)
                    
                    Text(source.bookSourceUrl)
                        .font(.caption)
                        .foregroundColor(.gray)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            
            // 右侧功能区：开关
            Toggle("", isOn: Binding(
                get: { source.enabled },
                set: { _ in viewModel.toggleSource(source: source) }
            ))
            .labelsHidden()
            .scaleEffect(0.7)
        }
        .padding(.vertical, 8)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                sourceIdToEdit = source.bookSourceUrl
            } label: {
                Label("编辑", systemImage: "pencil")
            }
            .tint(.blue)
            
            Button(role: .destructive) {
                viewModel.deleteSource(source: source)
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private var globalSearchView: some View {
        List {
            ForEach(viewModel.searchResults) { book in
                BookSearchResultRow(book: book) {
                    Task {
                        // For global search results, directly call APIService to save
                        // or handle errors appropriately
                        do {
                            try await bookshelfStore.saveBook(book)
                            addResultMessage = "已加入书架"
                            showAddResultAlert = true
                        } catch {
                            addResultMessage = "加入失败: \(error.localizedDescription)"
                            showAddResultAlert = true
                        }
                    }
                }
            }
            if viewModel.isSearching {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            }
        }
    }
    
    private func deleteSource(at offsets: IndexSet) {
        offsets.forEach { index in
            let source = viewModel.sources[index]
            viewModel.deleteSource(source: source)
        }
    }
}

struct SourceListView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            SourceListView()
        }
    }
}
