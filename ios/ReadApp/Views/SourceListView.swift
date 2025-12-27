import SwiftUI

struct SourceListView: View {
    @StateObject private var viewModel = SourceListViewModel()

    var body: some View {
        ZStack {
            if viewModel.isLoading {
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
            } else {
                List(viewModel.sources) { source in
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
                        
                        if let comment = source.bookSourceComment, !comment.isEmpty {
                            Text(comment)
                                .font(.footnote)
                                .foregroundColor(.gray)
                                .lineLimit(2)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("书源管理")
        .onAppear {
            if viewModel.sources.isEmpty {
                viewModel.fetchSources()
            }
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
