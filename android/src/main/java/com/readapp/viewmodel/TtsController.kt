package com.readapp.viewmodel

import android.net.Uri
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.session.MediaController
import com.readapp.media.AudioCache
import com.readapp.media.ReadAudioService
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.flow.update
import okhttp3.OkHttpClient
import okhttp3.Request
import java.util.Locale

internal class TtsController(private val viewModel: BookViewModel) {
    private var mediaController: MediaController? = null
    private val controllerListener = ControllerListener()
    private var textToSpeech: TextToSpeech? = null
    private var isTtsInitialized = false
    private val httpClient = OkHttpClient()
    private val preloadingIndices = mutableSetOf<Int>()
    private var preloadJob: Job? = null
    private var startOffsetOverrideIndex: Int? = null
    private var startOffsetOverrideChars: Int = 0

    fun initSystemTts() {
        textToSpeech = TextToSpeech(viewModel.appContext) { status ->
            if (status == TextToSpeech.SUCCESS) {
                isTtsInitialized = true
                textToSpeech?.language = Locale.CHINESE
                textToSpeech?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                    override fun onStart(utteranceId: String?) {
                        viewModel._isPlaying.value = true
                        viewModel._isPaused.value = false
                    }
                    override fun onDone(utteranceId: String?) {
                        if (viewModel._keepPlaying.value) {
                            viewModel.viewModelScope.launch {
                                playNextSeamlessly()
                            }
                        }
                    }
                    override fun onError(utteranceId: String?) {
                        viewModel._errorMessage.value = "系统TTS发生错误"
                    }
                })
                viewModel._availableSystemVoices.value = textToSpeech?.voices?.filter {
                    it.locale.language.startsWith("zh") || it.locale.language.startsWith("en")
                } ?: emptyList()
            }
        }
    }

    fun bindMediaController(controller: MediaController) {
        mediaController?.removeListener(controllerListener)
        mediaController = controller
        mediaController?.addListener(controllerListener)
        viewModel._isPlaying.value = mediaController?.isPlaying == true
    }

    fun release() {
        stopPlayback("cleared")
        mediaController?.removeListener(controllerListener)
        mediaController?.release()
        mediaController = null
        textToSpeech?.shutdown()
        textToSpeech = null
        isTtsInitialized = false
    }

    fun togglePlayPause() {
        if (viewModel._selectedBook.value == null) return
        val currentMediaController = mediaController ?: return

        if (currentMediaController.isPlaying) {
            viewModel._keepPlaying.value = false
            viewModel._isPaused.value = true
            pausePlayback("toggle")
        } else if (viewModel._currentParagraphIndex.value >= 0) {
            viewModel._keepPlaying.value = true
            viewModel._showTtsControls.value = true
            viewModel._isPaused.value = false
            currentMediaController.play()
        } else {
            startPlayback()
        }
    }

    fun previousParagraph() {
        val target = viewModel._currentParagraphIndex.value - 1
        if (target >= 0) {
            viewModel._keepPlaying.value = true
            speakParagraph(target)
        }
    }

    fun nextParagraph() {
        val target = viewModel._currentParagraphIndex.value + 1
        if (target < viewModel.currentSentences.size) {
            viewModel._keepPlaying.value = true
            speakParagraph(target)
        }
    }

    fun startTts(startParagraphIndex: Int = -1, startOffsetInParagraph: Int = 0) {
        startPlayback(startParagraphIndex, startOffsetInParagraph)
    }

    fun stopTts() {
        stopPlayback("user")
    }

    fun clearCache() {
        clearAudioCache()
        clearPreloadingIndices()
    }

    fun jumpToParagraph(index: Int) {
        if (!viewModel._keepPlaying.value) return
        speakParagraph(index)
    }

    private inner class ControllerListener : Player.Listener {
        override fun onIsPlayingChanged(isPlaying: Boolean) {
            viewModel._isPlaying.value = isPlaying
            viewModel._isPaused.value = !isPlaying && viewModel._currentParagraphIndex.value >= 0
            if (isPlaying) {
                viewModel._showTtsControls.value = true
            }
        }

        override fun onPlaybackStateChanged(playbackState: Int) {
            if (playbackState == Player.STATE_ENDED && viewModel._keepPlaying.value) {
                playNextSeamlessly()
            }
        }

        override fun onPlayerError(error: PlaybackException) {
            viewModel._errorMessage.value = "播放失败: ${error.errorCodeName}"
            if (viewModel._keepPlaying.value) {
                viewModel.viewModelScope.launch {
                    delay(500)
                    playNextSeamlessly()
                }
            }
        }
    }

    private fun startPlayback(startParagraphIndex: Int = -1, startOffsetInParagraph: Int = 0) {
        viewModel.viewModelScope.launch {
            viewModel._isChapterContentLoading.value = true
            val content = withContext(Dispatchers.IO) { viewModel.ensureCurrentChapterContent() }
            viewModel._isChapterContentLoading.value = false

            if (content.isNullOrBlank()) {
                viewModel._errorMessage.value = "当前章节内容为空，无法播放。"
                return@launch
            }

            viewModel._keepPlaying.value = true
            viewModel.currentSentences = viewModel.parseParagraphs(content)
            viewModel.currentParagraphs = viewModel.currentSentences
            viewModel._totalParagraphs.value = viewModel.currentSentences.size.coerceAtLeast(1)
            val normalizedStart = if (startParagraphIndex in viewModel.currentSentences.indices) {
                startParagraphIndex
            } else if (viewModel._currentParagraphIndex.value >= 0) {
                viewModel._currentParagraphIndex.value
            } else {
                0
            }
            viewModel._currentParagraphIndex.value = normalizedStart
            val normalizedOffset = if (normalizedStart == startParagraphIndex) {
                startOffsetInParagraph.coerceAtLeast(0)
            } else {
                0
            }
            if (normalizedOffset > 0) {
                startOffsetOverrideIndex = normalizedStart
                startOffsetOverrideChars = normalizedOffset
            } else {
                startOffsetOverrideIndex = null
                startOffsetOverrideChars = 0
            }
            viewModel._currentParagraphStartOffset.value = normalizedOffset

            ReadAudioService.startService(viewModel.appContext)
            viewModel._isPaused.value = false

            if (normalizedStart == 0 && normalizedOffset == 0) {
                speakChapterTitle()
            } else {
                viewModel.isReadingChapterTitle = false
                speakParagraph(normalizedStart)
            }

            observeProgress()
        }
    }

    private fun playNextSeamlessly() {
        if (viewModel.isReadingChapterTitle) {
            viewModel.isReadingChapterTitle = false
            speakParagraph(0)
            return
        }
        val nextIndex = viewModel._currentParagraphIndex.value + 1
        speakParagraph(nextIndex)
    }

    private fun moveToNextChapterForTts(): Boolean {
        val nextIndex = viewModel._currentChapterIndex.value + 1
        if (nextIndex > viewModel._chapters.value.lastIndex) {
            return false
        }
        viewModel._currentChapterIndex.value = nextIndex
        viewModel._currentChapterContent.value = ""
        viewModel.currentParagraphs = emptyList()
        viewModel.currentSentences = emptyList()
        startPlayback(0, 0)
        return true
    }

    private fun speakParagraph(index: Int) {
        viewModel.viewModelScope.launch {
            viewModel._currentParagraphIndex.value = index
            viewModel._playbackProgress.value = 0f

            if (index < 0 || index >= viewModel.currentSentences.size) {
                if (viewModel._keepPlaying.value && moveToNextChapterForTts()) {
                    return@launch
                }
                stopPlayback("finished")
                return@launch
            }

            if (startOffsetOverrideIndex != null && startOffsetOverrideIndex != index) {
                startOffsetOverrideIndex = null
                startOffsetOverrideChars = 0
            }

            val sentence = viewModel.currentSentences.getOrNull(index) ?: return@launch
            val overrideOffset = if (startOffsetOverrideIndex == index) startOffsetOverrideChars else 0
            viewModel._currentParagraphStartOffset.value = overrideOffset
            val trimmedSentence = if (overrideOffset in 1 until sentence.length) {
                sentence.substring(overrideOffset)
            } else {
                sentence
            }
            if (overrideOffset >= sentence.length) {
                startOffsetOverrideIndex = null
                startOffsetOverrideChars = 0
                viewModel._currentParagraphStartOffset.value = 0
                playNextSeamlessly()
                return@launch
            }

            if (viewModel._useSystemTts.value) {
                speakWithSystemTts(trimmedSentence)
                return@launch
            }

            val audioCacheKey = generateAudioCacheKey(index, overrideOffset)

            val audioData = AudioCache.get(audioCacheKey) ?: run {
                val audioUrl = viewModel.buildTtsAudioUrl(trimmedSentence, false)

                if (audioUrl == null) {
                    viewModel._errorMessage.value = "无法生成TTS链接，请检查TTS设置"
                    stopPlayback("error")
                    return@launch
                }

                val data = fetchAudioBytes(audioUrl)
                if (data == null) {
                    viewModel._errorMessage.value = "TTS音频下载失败"
                    stopPlayback("error")
                    return@launch
                }
                AudioCache.put(audioCacheKey, data)
                viewModel._preloadedParagraphs.update { it + index }
                data
            }

            playFromService(audioCacheKey)
            preloadNextParagraphs()
        }
    }

    private fun speakWithSystemTts(text: String) {
        if (!isTtsInitialized) {
            viewModel._errorMessage.value = "系统TTS尚未就绪"
            return
        }

        textToSpeech?.let { tts ->
            if (viewModel._systemVoiceId.value.isNotBlank()) {
                tts.voices?.firstOrNull { it.name == viewModel._systemVoiceId.value }?.let {
                    tts.voice = it
                }
            }

            tts.setSpeechRate(viewModel._speechSpeed.value / 20.0f)
            tts.speak(text, TextToSpeech.QUEUE_FLUSH, null, "paragraph_${viewModel._currentParagraphIndex.value}")
        }
    }

    private fun preloadNextParagraphs() {
        if (viewModel._useSystemTts.value) return

        preloadJob?.cancel()
        preloadJob = viewModel.viewModelScope.launch(Dispatchers.IO) {
            val preloadCount = viewModel._preloadCount.value
            if (preloadCount <= 0) return@launch

            val startIndex = viewModel._currentParagraphIndex.value + 1
            val endIndex = (startIndex + preloadCount).coerceAtMost(viewModel.currentSentences.size)
            val validIndices = (startIndex until endIndex).toSet()
            viewModel._preloadedParagraphs.update { it.intersect(validIndices) }

            for (i in startIndex until endIndex) {
                val audioCacheKey = generateAudioCacheKey(i)
                if (AudioCache.get(audioCacheKey) != null) {
                    viewModel._preloadedParagraphs.update { it + i }
                    continue
                }
                if (!markPreloading(i)) continue

                val sentenceToPreload = viewModel.currentSentences.getOrNull(i)
                if (sentenceToPreload.isNullOrBlank() || viewModel.isPunctuationOnly(sentenceToPreload)) {
                    unmarkPreloading(i)
                    continue
                }

                val audioUrlToPreload = viewModel.buildTtsAudioUrl(sentenceToPreload, isChapterTitle = false)
                if (audioUrlToPreload.isNullOrBlank()) {
                    unmarkPreloading(i)
                    continue
                }

                val data = fetchAudioBytes(audioUrlToPreload)
                if (data != null) {
                    AudioCache.put(audioCacheKey, data)
                    viewModel._preloadedParagraphs.update { it + i }
                }
                unmarkPreloading(i)
            }
        }
    }

    private fun generateAudioCacheKey(index: Int, offsetInParagraph: Int = 0): String {
        val base = "${viewModel._selectedBook.value?.bookUrl}/${viewModel._currentChapterIndex.value}/$index"
        return if (offsetInParagraph > 0) {
            "$base/$offsetInParagraph"
        } else {
            base
        }
    }

    private fun clearAudioCache() {
        AudioCache.clear()
        viewModel._preloadedParagraphs.value = emptySet()
    }

    private fun markPreloading(index: Int): Boolean = synchronized(preloadingIndices) {
        preloadingIndices.add(index)
    }

    private fun unmarkPreloading(index: Int) {
        synchronized(preloadingIndices) {
            preloadingIndices.remove(index)
        }
    }

    private fun clearPreloadingIndices() {
        synchronized(preloadingIndices) {
            preloadingIndices.clear()
        }
    }

    private suspend fun fetchAudioBytes(url: String): ByteArray? {
        return withContext(Dispatchers.IO) {
            runCatching {
                val request = Request.Builder().url(url).build()
                httpClient.newCall(request).execute().use { response ->
                    if (!response.isSuccessful) {
                        return@withContext null
                    }
                    val body = response.body ?: return@withContext null
                    body.bytes().takeIf { it.isNotEmpty() }
                }
            }.getOrElse {
                null
            }
        }
    }

    private fun playFromService(audioCacheKey: String) {
        val currentMediaController = mediaController ?: return
        val cacheUri = Uri.Builder()
            .scheme("tts")
            .authority("cache")
            .appendQueryParameter("key", audioCacheKey)
            .build()
        val mediaItem = MediaItem.Builder()
            .setMediaId(audioCacheKey)
            .setUri(cacheUri)
            .build()
        currentMediaController.setMediaItem(mediaItem)
        currentMediaController.prepare()
        currentMediaController.play()
    }

    private fun pausePlayback(reason: String = "unspecified") {
        if (viewModel._useSystemTts.value) {
            textToSpeech?.stop()
        } else {
            mediaController?.pause()
        }
    }

    private fun stopPlayback(reason: String = "unspecified") {
        preloadJob?.cancel()
        clearAudioCache()
        clearPreloadingIndices()

        if (reason != "finished") {
            viewModel.saveBookProgress()
        }

        viewModel._keepPlaying.value = false
        viewModel._showTtsControls.value = false
        viewModel._isPaused.value = false
        startOffsetOverrideIndex = null
        startOffsetOverrideChars = 0
        viewModel._currentParagraphStartOffset.value = 0

        if (viewModel._useSystemTts.value) {
            textToSpeech?.stop()
        } else {
            mediaController?.stop()
            mediaController?.clearMediaItems()
        }

        viewModel._currentParagraphIndex.value = -1
        viewModel.isReadingChapterTitle = false
        viewModel._preloadedParagraphs.value = emptySet()
        viewModel.resetPlayback()
    }

    private fun speakChapterTitle() {
        viewModel.viewModelScope.launch {
            viewModel.isReadingChapterTitle = true
            viewModel._currentParagraphIndex.value = -1
            val title = viewModel.currentChapterTitle
            if (title.isBlank()) {
                playNextSeamlessly()
                return@launch
            }

            if (viewModel._useSystemTts.value) {
                speakWithSystemTts(title)
            } else {
                val audioUrl = viewModel.buildTtsAudioUrl(title, isChapterTitle = true)
                if (audioUrl == null) {
                    playNextSeamlessly()
                    return@launch
                }
                val data = fetchAudioBytes(audioUrl)
                if (data == null) {
                    playNextSeamlessly()
                    return@launch
                }
                val key = "title_${viewModel._selectedBook.value?.bookUrl}_${viewModel._currentChapterIndex.value}"
                AudioCache.put(key, data)
                playFromService(key)
            }
        }
    }

    private fun observeProgress() {
        viewModel.viewModelScope.launch {
            while (viewModel._keepPlaying.value) {
                val currentMediaController = mediaController
                if (currentMediaController == null || !currentMediaController.isPlaying) {
                    delay(500)
                    continue
                }
                val duration = currentMediaController.duration
                val position = currentMediaController.currentPosition
                if (duration <= 0L || position < 0L || position > duration) {
                    delay(200)
                    continue
                }
                viewModel._playbackProgress.value = (position.toFloat() / duration).coerceIn(0f, 1f)
                viewModel._totalTime.value = viewModel.formatTime(duration)
                viewModel._currentTime.value = viewModel.formatTime(position)
                delay(500)
            }
        }
    }
}
