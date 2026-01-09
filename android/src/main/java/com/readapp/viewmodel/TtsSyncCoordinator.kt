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
        if (viewModel.lockPageOnTTS.value && viewModel.pendingScrollIndex.value == index) {
            return
        }
        if (lastUiParagraphIndex == index) return
        lastUiParagraphIndex = index
        if (viewModel._keepPlaying.value) {
            viewModel.jumpToParagraphForTts(index)
        } else {
            viewModel._currentParagraphIndex.value = index
        }
    }

    private fun synchronizeFromTts(index: Int) {
        if (index < 0) return
        if (lastUiParagraphIndex == index) {
            lastUiParagraphIndex = -1
            return
        }
        if (lastTtsParagraphIndex == index) return
        lastTtsParagraphIndex = index
        if (viewModel._isPlaying.value && viewModel.lockPageOnTTS.value) {
            viewModel.requestScrollIndexFromTts(index)
        }
    }
}
