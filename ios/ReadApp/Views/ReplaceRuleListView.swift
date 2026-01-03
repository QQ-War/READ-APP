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
                                        await viewModel.toggleRule(id: rule.id ?? "", isEnabled: newValue)
                                    }
                                }
                            )) {
                                Text("启用").font(.caption2)
                            }
                            .scaleEffect(0.8) // Make toggle smaller
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
        .ifAvailableHideTabBar()
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
