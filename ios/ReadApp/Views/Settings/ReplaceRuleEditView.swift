import SwiftUI

struct ReplaceRuleEditView: View {
    @ObservedObject var viewModel: ReplaceRuleViewModel
    var rule: ReplaceRule?
    
    @Environment(\.dismiss) var dismiss
    
    // State for all rule properties
    @State private var name: String = ""
    @State private var groupname: String = ""
    @State private var pattern: String = ""
    @State private var replacement: String = ""
    @State private var scope: String = ""
    @State private var excludeScope: String = ""
    @State private var ruleOrder: Int = 0
    @State private var isEnabled: Bool = true
    @State private var isRegex: Bool = true
    @State private var scopeTitle: Bool = false
    @State private var scopeContent: Bool = true

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("基本信息")) {
                    TextField("规则名称*", text: $name)
                    TextField("分组", text: $groupname)
                    TextField("匹配内容* (正则)", text: $pattern)
                        .font(.system(.body, design: .monospaced))
                    TextField("替换为", text: $replacement)
                        .font(.system(.body, design: .monospaced))
                }
                
                Section(header: Text("作用范围")) {
                    TextField("作用范围 (书名,逗号隔开)", text: $scope)
                    TextField("排除范围 (书名,逗号隔开)", text: $excludeScope)
                    Toggle("作用于标题", isOn: $scopeTitle)
                    Toggle("作用于正文", isOn: $scopeContent)
                }
                
                Section(header: Text("选项")) {
                    Stepper(value: $ruleOrder, in: 0...1000) {
                        HStack {
                            Text("执行顺序")
                            Spacer()
                            Text("\(ruleOrder)")
                        }
                    }
                    Toggle("启用规则", isOn: $isEnabled)
                    Toggle("使用正则", isOn: $isRegex)
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
            self.groupname = rule.groupname ?? ""
            self.pattern = rule.pattern
            self.replacement = rule.replacement
            self.scope = rule.scope ?? ""
            self.excludeScope = rule.excludeScope ?? ""
            self.ruleOrder = rule.ruleorder ?? 0
            self.isEnabled = rule.isEnabled ?? true
            self.isRegex = rule.isRegex ?? true
            self.scopeTitle = rule.scopeTitle ?? false
            self.scopeContent = rule.scopeContent ?? true
        }
    }
    
    private func save() {
        let newRule = ReplaceRule(
            id: rule?.id, // Keep original ID for updates
            name: name,
            groupname: groupname,
            pattern: pattern,
            replacement: replacement,
            scope: scope,
            scopeTitle: scopeTitle,
            scopeContent: scopeContent,
            excludeScope: excludeScope,
            isEnabled: isEnabled,
            isRegex: isRegex,
            timeoutMillisecond: rule?.timeoutMillisecond ?? 3000,
            ruleorder: ruleOrder
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
            rule: ReplaceRule(id: "1", name: "示例规则", groupname: "分组1", pattern: "广告", replacement: "", scope: "某本书", scopeTitle: false, scopeContent: true, excludeScope: "", isEnabled: true, isRegex: true, timeoutMillisecond: 3000, ruleorder: 1)
        )
    }
}
