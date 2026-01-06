import SwiftUI

// 正文处理逻辑已迁移至 ReaderContainer
extension ReadingView {
    func presentReplaceRuleEditor(selectedText: String) {
        // 实现长按唤起净化规则
    }
    func toggleTTS() {
        if ttsManager.isPlaying {
            if ttsManager.isPaused { ttsManager.resume() }
            else { ttsManager.pause() }
        } else {
            // 开始听书逻辑
        }
    }
}