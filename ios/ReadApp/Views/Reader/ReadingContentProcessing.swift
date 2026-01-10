import SwiftUI

// 正文处理逻辑已迁移至 ReaderContainer
extension ReadingView {
    func presentReplaceRuleEditor(selectedText: String) {
        // 实现长按唤起净化规则
    }
    func toggleTTS() {
        if let action = toggleTTSAction {
            action()
        }
    }
}