import SwiftUI

struct ReplaceRuleListView: View {
    @StateObject private var viewModel = ReplaceRuleViewModel()
    @State private var showEditView = false
    @State private var selectedRule: ReplaceRule?

    var body: some View {
        List {
            if viewModel.isLoading && viewModel.rules.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
            } else {
                ForEach($viewModel.rules) { $rule in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(rule.name)
                            .font(.headline)
                        
                        HStack {
                            Text("替换:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(rule.pattern)
                                .font(.system(.caption, design: .monospaced))
                                .lineLimit(1)
                            Spacer()
                            Image(systemName: "arrow.right")
                            Spacer()
                            Text(rule.replaceWith)
                                .font(.system(.caption, design: .monospaced))
                                .lineLimit(1)
                        }
                        
                        Toggle(isOn: Binding(
                            get: { rule.isEnabled },
                            set: { newValue in
                                Task {
                                    await viewModel.toggleRule(id: rule.id ?? "", isEnabled: newValue)
                                }
                            }
                        )) {
                            Text("启用")
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
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    self.selectedRule = nil
                    self.showEditView = true
                }) {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showEditView) {
            ReplaceRuleEditView(viewModel: viewModel, rule: selectedRule)
        }
        .onAppear {
            Task {
                await viewModel.fetchRules()
            }
        }
    }

    private func deleteRule(at offsets: IndexSet) {
        let rulesToDelete = offsets.map { viewModel.rules[$0] }
        Task {
            for rule in rulesToDelete {
                if let id = rule.id {
                    await viewModel.deleteRule(id: id)
                }
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
