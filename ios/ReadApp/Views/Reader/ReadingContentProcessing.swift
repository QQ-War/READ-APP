import SwiftUI

// 正文处理逻辑已迁移至 ReaderContainer
extension ReadingView {
    func presentReplaceRuleEditor(selectedText: String) {
        self.textToSelect = selectedText
        self.showSelectionHelper = true
    }
    func toggleTTS() {
        if let action = toggleTTSAction {
            action()
        }
    }
}