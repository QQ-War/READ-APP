import SwiftUI

struct SourceListView: View {
    @EnvironmentObject var apiService: APIService
    @StateObject private var viewModel = SourceListViewModel()
    
    // For specific source search via swipe action
    @State private var showingBookSearchView = false
    @State private var selectedBookSource: BookSource?
    @State private var showAddResultAlert = false
    @State private var addResultMessage = ""

    @State private var expandedSourceIds: Set<String> = []
    @State private var exploreKinds: [String: [BookSource.ExploreKind]] = [:]
    @State private var loadingExploreIds: Set<String> = []
    @State private var showingURLImportDialog = false
    @State private var importURL = ""
    @State private var showingFilePicker = false

    var body: some View {
        sourceManagementView
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
                            await viewModel.fetchSources()
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
                if let bookSource = selectedBookSource {
                    BookSearchView(viewModel: BookSearchViewModel(bookSource: bookSource))
                }
            }
    }
    
    private func importFromURL() async {
        guard let url = URL(string: importURL) else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let content = String(data: data, encoding: .utf8) {
                try await apiService.saveBookSource(jsonContent: content)
                await viewModel.fetchSources()
            }
        } catch {
            await MainActor.run {
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
                    ForEach(viewModel.filteredSources) { source in
                        VStack(spacing: 0) {
                            HStack {
                                NavigationLink(destination: SourceEditView(sourceId: source.bookSourceUrl)) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(source.bookSourceName)
                                            .font(.headline)
                                            .foregroundColor(source.enabled ? .primary : .secondary)
                                        
                                        if let group = source.bookSourceGroup, !group.isEmpty {
                                            Text("分组: \(group)")
                                                .font(.subheadline)
                                                .foregroundColor(.secondary)
                                        }
                                        
                                        Text(source.bookSourceUrl)
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    }
                                }
                                
                                Spacer()
                                
                                HStack(spacing: 12) {
                                    Toggle("", isOn: Binding(
                                        get: { source.enabled },
                                        set: { _ in viewModel.toggleSource(source: source) }
                                    ))
                                    .labelsHidden()
                                    
                                    Button(action: { toggleExpand(source) }) {
                                        Image(systemName: expandedSourceIds.contains(source.id) ? "chevron.down" : "chevron.right")
                                            .foregroundColor(.blue)
                                            .frame(width: 30, height: 30)
                                    }
                                    .buttonStyle(BorderlessButtonStyle())
                                }
                            }
                            .padding(.vertical, 4)
                            
                            if expandedSourceIds.contains(source.id) {
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
                                        .padding(.leading, 12)
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
                                selectedBookSource = source
                                showingBookSearchView = true
                            } label: {
                                Label("搜索", systemImage: "magnifyingglass")
                            }
                            .tint(.blue)
                        }
                    }
                    .onDelete(perform: deleteSource)
                }
                .refreshable {
                    viewModel.fetchSources()
                }
                .searchable(text: $viewModel.searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "过滤书源...")
            }
        }
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
                await MainActor.run {
                    exploreKinds[source.id] = kinds
                    loadingExploreIds.remove(source.id)
                }
            } catch {
                await MainActor.run {
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
