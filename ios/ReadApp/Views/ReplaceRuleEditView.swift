import SwiftUI

struct ReplaceRuleEditView: View {
    @ObservedObject var viewModel: ReplaceRuleViewModel
    var rule: ReplaceRule?
    
    @Environment(\.dismiss) var dismiss
    
    @State private var name: String = ""
    @State private var pattern: String = ""
    @State private var replaceWith: String = ""
    @State private var order: Int = 0
    @State private var isEnabled: Bool = true
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("规则信息")) {
                    TextField("规则名称", text: $name)
                    TextField("匹配内容 (正则表达式)", text: $pattern)
                        .font(.system(.body, design: .monospaced))
                    TextField("替换为", text: $replaceWith)
                        .font(.system(.body, design: .monospaced))
                }
                
                Section(header: Text("选项")) {
                    Stepper(value: $order, in: 0...1000) {
                        HStack {
                            Text("执行顺序")
                            Spacer()
                            Text("\(order)")
                        }
                    }
                    Toggle("启用规则", isOn: $isEnabled)
                }
            }
            .navigationTitle(rule == nil ? "添加规则" : "编辑规则")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") {
                        save()
                        dismiss()
                    }
                    .disabled(name.isEmpty || pattern.isEmpty)
                }
            }
            .onAppear(perform: setup)
        }
    }
    
    private func setup() {
        if let rule = rule {
            self.name = rule.name
            self.pattern = rule.pattern
            self.replaceWith = rule.replaceWith
            self.order = rule.order
            self.isEnabled = rule.isEnabled
        }
    }
    
    private func save() {
        let newRule = ReplaceRule(
            id: rule?.id, // Keep original ID for updates
            name: name,
            pattern: pattern,
            replaceWith: replaceWith,
            scope: rule?.scope ?? "global", // Default scope
            order: order,
            isEnabled: isEnabled
        )
        Task {
            await viewModel.saveRule(rule: newRule)
        }
    }
}

struct ReplaceRuleEditView_Previews: PreviewProvider {
    static var previews: some View {
        ReplaceRuleEditView(
            viewModel: ReplaceRuleViewModel(),
            rule: ReplaceRule(id: "1", name: "示例规则", pattern: "广告", replaceWith: "", scope: "global", order: 1, isEnabled: true)
        )
    }
}
