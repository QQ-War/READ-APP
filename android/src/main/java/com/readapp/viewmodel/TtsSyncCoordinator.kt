package com.readapp.viewmodel

import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch

internal class TtsSyncCoordinator(private val viewModel: BookViewModel) {
    private val coroutineScope = viewModel.viewModelScope
    private var lastUiParagraphIndex: Int = -1
    private var lastTtsParagraphIndex: Int = -1

    init {
        coroutineScope.launch {
            viewModel.currentParagraphIndex.collect { index ->
                synchronizeFromTts(index)
            }
        }
    }

    fun onUiParagraphVisible(index: Int) {
        if (index < 0) return
        if (viewModel.pendingScrollIndex.value == index) {
            return
        }
        
        // 反向同步逻辑：从 UI 索引映射回 TTS 索引
        var ttsTargetIndex = index
        if (viewModel.currentSentences.isNotEmpty() && viewModel.currentSentences[0] == viewModel.currentChapterTitle) {
            ttsTargetIndex = index + 1
        }

        if (lastUiParagraphIndex == index) return
        lastUiParagraphIndex = index
        
        if (!viewModel._isPlaying.value && !viewModel._keepPlaying.value) {
            viewModel._currentParagraphIndex.value = ttsTargetIndex
        }
    }

    private fun synchronizeFromTts(index: Int) {
        if (index < 0) return
        
        // 增加偏移对齐逻辑：UI 端的段落列表通常不含标题
        var targetUiIndex = index
        if (viewModel.isReadingChapterTitle) {
            // 正在读标题时，UI 强制定位到第 0 段（正文第一段）
            targetUiIndex = 0
        } else if (viewModel.currentSentences.isNotEmpty() && viewModel.currentSentences[0] == viewModel.currentChapterTitle) {
            // 如果列表包含标题且当前不在读标题，则 UI 索引需要减 1 才能对齐
            targetUiIndex = (index - 1).coerceAtLeast(0)
        }

        if (lastUiParagraphIndex == targetUiIndex) {
            lastUiParagraphIndex = -1
            return
        }
        if (lastTtsParagraphIndex == index) return
        lastTtsParagraphIndex = index
        
        if (viewModel.isPlayingUi.value && viewModel.shouldAllowTtsFollow()) {
            viewModel.requestScrollIndexFromTts(targetUiIndex)
        }
    }
}
