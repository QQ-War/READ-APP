import SwiftUI

struct RssSourcesView: View {
    @StateObject private var viewModel = RssSourcesViewModel()
    @Environment(\.dismiss) var dismiss

    var body: some View {
        List {
            Section {
                Text(viewModel.canEdit ? "启用或禁用订阅源将立即同步到服务端。" : "当前账号不可编辑订阅源。")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            if viewModel.sources.isEmpty {
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
                Section {
                    ForEach(viewModel.sources) { source in
                        RssSourceRow(
                            source: source,
                            isBusy: viewModel.pendingToggles.contains(source.id),
                            isEnabled: source.enabled,
                            canToggle: viewModel.canEdit
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
        .navigationTitle("订阅源")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    Task {
                        await viewModel.refresh()
                    }
                }) {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(viewModel.isLoading)
            }
        }
    }
}

private struct RssSourceRow: View {
    let source: RssSource
    let isBusy: Bool
    let isEnabled: Bool
    let canToggle: Bool
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
    }
}
