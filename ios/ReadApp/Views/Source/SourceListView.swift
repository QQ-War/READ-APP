import SwiftUI

struct SourceListView: View {
    @EnvironmentObject var apiService: APIService
    @StateObject private var viewModel = SourceListViewModel()
    
    // For specific source search via swipe action
    @State private var showingBookSearchView = false
    @State private var selectedBookSource: BookSource?
    @State private var bookSearchViewModel: BookSearchViewModel?
    @State private var showAddResultAlert = false
    @State private var addResultMessage = ""

    @State private var expandedSourceIds: Set<String> = []
    @State private var exploreKinds: [String: [BookSource.ExploreKind]] = [:]
    @State private var loadingExploreIds: Set<String> = []
    @State private var showingURLImportDialog = false
    @State private var importURL = ""
    @State private var showingFilePicker = false
    
    // 分组展开状态
    @State private var expandedGroups: Set<String> = []
    @State private var sourceIdToEdit: String? = nil

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
                            try? await apiService.saveBookSource(jsonContent: content)
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
            .sheet(isPresented: $showingBookSearchView) {
                if let viewModel = bookSearchViewModel {
                    BookSearchView(viewModel: viewModel)
                        .environmentObject(apiService)
                }
            }
    }
    
    private func importFromURL() async {
        guard let url = URL(string: importURL) else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let content = String(data: data, encoding: .utf8) {
                try await apiService.saveBookSource(jsonContent: content)
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
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // 左侧及中间：点击展开/隐藏频道 (占据除滑块以外的所有空间)
                Button(action: { withAnimation { toggleExpand(source) } }) {
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
                
                // 右侧功能区：开关 + 编辑图标
                HStack(spacing: 12) {
                    // 启用开关
                    Toggle("", isOn: Binding(
                        get: { source.enabled },
                        set: { _ in viewModel.toggleSource(source: source) }
                    ))
                    .labelsHidden()
                    .scaleEffect(0.7)
                    
                    // 右侧：点击进入编辑 (独立的小按钮)
                    Button(action: {
                        // 先清空再设置，确保每次点击都触发跳转
                        sourceIdToEdit = nil
                        DispatchQueue.main.async {
                            sourceIdToEdit = source.bookSourceUrl
                        }
                    }) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(BorderlessButtonStyle())
                }
                .padding(.trailing, 4)
            }
            .padding(.vertical, 8)
            
            if expandedSourceIds.contains(source.id) {
                // ... 发现频道代码 (保持原样) ...
                if loadingExploreIds.contains(source.id) {
                    ProgressView().padding(.vertical, 8)
                } else if let kinds = exploreKinds[source.id], !kinds.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(kinds) { kind in
                                NavigationLink(destination: SourceExploreView(source: source, kind: kind).environmentObject(apiService)) {
                                    Text(kind.title)
                                        .font(.caption)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color.blue.opacity(0.1))
                                        .foregroundColor(.blue)
                                        .cornerRadius(12)
                                }
                            }
                        }
                        .padding(.vertical, 8)
                        .padding(.leading, 4)
                    }
                } else {
                    Text("该书源暂无发现配置")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 4)
                }
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                openBookSearch(for: source)
            } label: {
                Label("搜索", systemImage: "magnifyingglass")
            }
            .tint(.blue)
            
            Button(role: .destructive) {
                viewModel.deleteSource(source: source)
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    private func openBookSearch(for source: BookSource) {
        if selectedBookSource?.bookSourceUrl != source.bookSourceUrl || bookSearchViewModel == nil {
            selectedBookSource = source
            bookSearchViewModel = BookSearchViewModel(bookSource: source)
        }
        showingBookSearchView = true
    }
    
    private func toggleExpand(_ source: BookSource) {
        if expandedSourceIds.contains(source.id) {
            expandedSourceIds.remove(source.id)
        } else {
            expandedSourceIds.insert(source.id)
            if exploreKinds[source.id] == nil {
                loadExploreKinds(for: source)
            }
        }
    }
    
    private func loadExploreKinds(for source: BookSource) {
        loadingExploreIds.insert(source.id)
        Task {
            do {
                let kinds = try await apiService.fetchExploreKinds(bookSourceUrl: source.bookSourceUrl)
                _ = await MainActor.run {
                    exploreKinds[source.id] = kinds
                    loadingExploreIds.remove(source.id)
                }
            } catch {
                _ = await MainActor.run {
                    loadingExploreIds.remove(source.id)
                }
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
                            try await APIService.shared.saveBook(book: book)
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
