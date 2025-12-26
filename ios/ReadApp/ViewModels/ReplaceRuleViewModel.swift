import Foundation
import Combine

@MainActor
class ReplaceRuleViewModel: ObservableObject {
    @Published var rules: [ReplaceRule] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let apiService = APIService.shared

    func fetchRules() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let fetchedRules = try await apiService.fetchReplaceRules()
            self.rules = fetchedRules.sorted(by: { $0.order < $1.order })
        } catch {
            self.errorMessage = "加载规则失败: \(error.localizedDescription)"
            LogManager.shared.log("获取净化规则失败: \(error)", category: "错误")
        }
        
        isLoading = false
    }

    func saveRule(rule: ReplaceRule) async {
        isLoading = true
        errorMessage = nil
        
        do {
            try await apiService.saveReplaceRule(rule: rule)
            // 保存成功后刷新列表
            await fetchRules()
        } catch {
            self.errorMessage = "保存规则失败: \(error.localizedDescription)"
            LogManager.shared.log("保存净化规则失败: \(error)", category: "错误")
        }
        
        isLoading = false
    }

    func deleteRule(id: String) async {
        isLoading = true
        errorMessage = nil
        
        do {
            try await apiService.deleteReplaceRule(id: id)
            // 删除成功后刷新列表
            await fetchRules()
        } catch {
            self.errorMessage = "删除规则失败: \(error.localizedDescription)"
            LogManager.shared.log("删除净化规则失败: \(error)", category: "错误")
        }
        
        isLoading = false
    }

    func toggleRule(id: String, isEnabled: Bool) async {
        // We don't set isLoading to true for this to make the UI feel more responsive
        errorMessage = nil
        
        do {
            try await apiService.toggleReplaceRule(id: id, isEnabled: isEnabled)
            // Optimistically update the local state
            if let index = rules.firstIndex(where: { $0.id == id }) {
                // This is tricky without the full object back. Re-fetching is safer.
                await fetchRules()
            }
        } catch {
            self.errorMessage = "切换规则状态失败: \(error.localizedDescription)"
            LogManager.shared.log("切换净化规则状态失败: \(error)", category: "错误")
        }
    }
}
