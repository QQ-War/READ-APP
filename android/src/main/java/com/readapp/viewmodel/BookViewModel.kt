package com.readapp.viewmodel

import android.app.Application
import android.net.Uri
import android.util.Log
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.common.PlaybackException
import androidx.media3.exoplayer.ExoPlayer
import com.readapp.data.ReadApiService
import com.readapp.data.ReadRepository
import com.readapp.data.UserPreferences
import com.readapp.data.model.Book
import com.readapp.data.model.Chapter
import com.readapp.data.model.HttpTTS
import com.readapp.media.PlayerPool
import com.readapp.media.ReadAudioService
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

import android.util.LruCache
import androidx.media3.datasource.ByteArrayDataSource
import androidx.media3.datasource.DataSource
import androidx.media3.exoplayer.source.ProgressiveMediaSource
import com.readapp.data.model.ReplaceRule
import okhttp3.OkHttpClient
import okhttp3.Request
class BookViewModel(application: Application) : AndroidViewModel(application) {

    companion object {
        private const val TAG = "BookViewModel"
        private const val LOG_FILE_NAME = "reader_logs.txt"
        private const val LOG_EXPORT_NAME = "reader_logs_export.txt"
        private const val MAX_AUDIO_CACHE_BYTES = 20 * 1024 * 1024

        val Factory: ViewModelProvider.Factory = viewModelFactory {
            initializer {
                val application = this[ViewModelProvider.AndroidViewModelFactory.APPLICATION_KEY] as Application
                BookViewModel(application)
            }
        }
    }

    // ==================== Dependencies & Player Management ====================

    private val appContext = getApplication<Application>()
    private val preferences = UserPreferences(appContext)
    private val repository = ReadRepository { endpoint ->
        ReadApiService.create(endpoint) { accessToken.value }
    }

    private val playerListener = AppPlayerListener()
    private val player: ExoPlayer = PlayerPool.get(appContext).apply { addListener(playerListener) }
    private val httpClient = OkHttpClient()
    private val cacheLock = Any()
    private val audioCache = object : LruCache<Int, ByteArray>(MAX_AUDIO_CACHE_BYTES) {
        override fun sizeOf(key: Int, value: ByteArray): Int = value.size

        override fun entryRemoved(evicted: Boolean, key: Int, oldValue: ByteArray, newValue: ByteArray?) {
            if (evicted) {
                _preloadedParagraphs.update { it - key }
            }
        }
    }
    private val preloadingIndices = mutableSetOf<Int>()
    private var preloadJob: Job? = null

    // ==================== 书籍相关状态 ====================

    private var currentSentences: List<String> = emptyList()
    private var currentParagraphs: List<String> = emptyList()
    private var isReadingChapterTitle = false
    private var currentSearchQuery = ""
    private var allBooks: List<Book> = emptyList()
    private val chapterContentCache = mutableMapOf<Int, String>()
    private val logFile = File(appContext.filesDir, LOG_FILE_NAME)

    private val _books = MutableStateFlow<List<Book>>(emptyList())
    val books: StateFlow<List<Book>> = _books.asStateFlow()

    private val _selectedBook = MutableStateFlow<Book?>(null)
    val selectedBook: StateFlow<Book?> = _selectedBook.asStateFlow()

    private val _chapters = MutableStateFlow<List<Chapter>>(emptyList())
    val chapters: StateFlow<List<Chapter>> = _chapters.asStateFlow()

    private val _currentChapterIndex = MutableStateFlow(0)
    val currentChapterIndex: StateFlow<Int> = _currentChapterIndex.asStateFlow()

    private val _currentChapterContent = MutableStateFlow("")
    val currentChapterContent: StateFlow<String> = _currentChapterContent.asStateFlow()

    val currentChapterTitle: String
        get() = _chapters.value.getOrNull(_currentChapterIndex.value)?.title ?: ""

    // ==================== 段落相关状态 ====================

    private val _currentParagraphIndex = MutableStateFlow(-1)
    val currentParagraphIndex: StateFlow<Int> = _currentParagraphIndex.asStateFlow()

    private val _totalParagraphs = MutableStateFlow(1)
    val totalParagraphs: StateFlow<Int> = _totalParagraphs.asStateFlow()

    private val _preloadedParagraphs = MutableStateFlow<Set<Int>>(emptySet())
    val preloadedParagraphs: StateFlow<Set<Int>> = _preloadedParagraphs.asStateFlow()
    private val _preloadedChapters = MutableStateFlow<Set<Int>>(emptySet())
    val preloadedChapters: StateFlow<Set<Int>> = _preloadedChapters.asStateFlow()

    // ==================== TTS 播放状态 ====================

    private val _isPlaying = MutableStateFlow(false)
    val isPlaying: StateFlow<Boolean> = _isPlaying.asStateFlow()
    private val _keepPlaying = MutableStateFlow(false)
    val isPlayingUi: StateFlow<Boolean> = combine(_isPlaying, _keepPlaying) { playing, keep ->
        playing || keep
    }.stateIn(viewModelScope, SharingStarted.Eagerly, false)

    private val _currentTime = MutableStateFlow("00:00")
    val currentTime: StateFlow<String> = _currentTime.asStateFlow()

    private val _totalTime = MutableStateFlow("00:00")
    val totalTime: StateFlow<String> = _totalTime.asStateFlow()

    private val _playbackProgress = MutableStateFlow(0f)
    val playbackProgress: StateFlow<Float> = _playbackProgress.asStateFlow()

    // ==================== 净化规则状态 ====================

    private val _replaceRules = MutableStateFlow<List<ReplaceRule>>(emptyList())
    val replaceRules: StateFlow<List<ReplaceRule>> = _replaceRules.asStateFlow()

    // ==================== TTS 设置 & 其他 ====================
    // (No changes in this section, keeping it compact)
    private val _selectedTtsEngine = MutableStateFlow("")
    val selectedTtsEngine: StateFlow<String> = _selectedTtsEngine.asStateFlow()
    private val _narrationTtsEngine = MutableStateFlow("")
    val narrationTtsEngine: StateFlow<String> = _narrationTtsEngine.asStateFlow()
    private val _dialogueTtsEngine = MutableStateFlow("")
    val dialogueTtsEngine: StateFlow<String> = _dialogueTtsEngine.asStateFlow()
    private val _speakerTtsMapping = MutableStateFlow<Map<String, String>>(emptyMap())
    val speakerTtsMapping: StateFlow<Map<String, String>> = _speakerTtsMapping.asStateFlow()
    private val _availableTtsEngines = MutableStateFlow<List<HttpTTS>>(emptyList())
    val availableTtsEngines: StateFlow<List<HttpTTS>> = _availableTtsEngines.asStateFlow()
    private val _speechSpeed = MutableStateFlow(20)
    val speechSpeed: StateFlow<Int> = _speechSpeed.asStateFlow()
    private val _preloadCount = MutableStateFlow(3)
    val preloadCount: StateFlow<Int> = _preloadCount.asStateFlow()
    private val _readingFontSize = MutableStateFlow(16f)
    val readingFontSize: StateFlow<Float> = _readingFontSize.asStateFlow()
    private val _loggingEnabled = MutableStateFlow(false)
    val loggingEnabled: StateFlow<Boolean> = _loggingEnabled.asStateFlow()
    private val _bookshelfSortByRecent = MutableStateFlow(false)
    val bookshelfSortByRecent: StateFlow<Boolean> = _bookshelfSortByRecent.asStateFlow()
    private val _serverAddress = MutableStateFlow("http://127.0.0.1:8080/api/5")
    val serverAddress: StateFlow<String> = _serverAddress.asStateFlow()
    private val _publicServerAddress = MutableStateFlow("")
    val publicServerAddress: StateFlow<String> = _publicServerAddress.asStateFlow()
    private val _accessToken = MutableStateFlow("")
    val accessToken: StateFlow<String> = _accessToken.asStateFlow()
    private val _username = MutableStateFlow("")
    val username: StateFlow<String> = _username.asStateFlow()
    private val _errorMessage = MutableStateFlow<String?>(null)
    val errorMessage: StateFlow<String?> = _errorMessage.asStateFlow()
    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()
    private val _isChapterListLoading = MutableStateFlow(false)
    val isChapterListLoading: StateFlow<Boolean> = _isChapterListLoading.asStateFlow()
    private val _isChapterContentLoading = MutableStateFlow(false)
    val isChapterContentLoading: StateFlow<Boolean> = _isChapterContentLoading.asStateFlow()
    private val _isInitialized = MutableStateFlow(false)
    val isInitialized: StateFlow<Boolean> = _isInitialized.asStateFlow()

    fun clearError() { _errorMessage.value = null }

    // ==================== 初始化 ====================

    init {
        viewModelScope.launch {
            // Load all preferences
            _serverAddress.value = preferences.serverUrl.first()
            _publicServerAddress.value = preferences.publicServerUrl.first()
            _accessToken.value = preferences.accessToken.first()
            _username.value = preferences.username.first()
            _selectedTtsEngine.value = preferences.selectedTtsId.firstOrNull().orEmpty()
            _narrationTtsEngine.value = preferences.narrationTtsId.firstOrNull().orEmpty()
            _dialogueTtsEngine.value = preferences.dialogueTtsId.firstOrNull().orEmpty()
            _speakerTtsMapping.value = parseSpeakerMapping(preferences.speakerTtsMapping.firstOrNull().orEmpty())
            _speechSpeed.value = (preferences.speechRate.first() * 20).toInt()
            _preloadCount.value = preferences.preloadCount.first().toInt()
            _readingFontSize.value = preferences.readingFontSize.first()
            _loggingEnabled.value = preferences.loggingEnabled.first()
            _bookshelfSortByRecent.value = preferences.bookshelfSortByRecent.first()

            if (_accessToken.value.isNotBlank()) {
                _isLoading.value = true
                try {
                    loadTtsEnginesInternal()
                    refreshBooksInternal(showLoading = true)
                    loadReplaceRules()
                } finally {
                    _isLoading.value = false
                }
            }
            _isInitialized.value = true
        }
    }

    // ==================== Player Listener ====================

    private inner class AppPlayerListener : Player.Listener {
        override fun onIsPlayingChanged(isPlaying: Boolean) {
            _isPlaying.value = isPlaying
            appendLog("TTS player isPlaying=$isPlaying state=${player.playbackState} " +
                        "playWhenReady=${player.playWhenReady} keepPlaying=${_keepPlaying.value}")
        }

        override fun onPlaybackStateChanged(playbackState: Int) {
            appendLog("TTS playback state=$playbackState playWhenReady=${player.playWhenReady} " +
                        "isPlaying=${player.isPlaying}")
            if (playbackState == Player.STATE_ENDED && _keepPlaying.value) {
                playNextSeamlessly()
            }
        }

        override fun onPlayerError(error: PlaybackException) {
            appendLog("TTS player error: ${error.errorCodeName} ${error.message}")
            _errorMessage.value = "播放失败: ${error.errorCodeName}"
            if (_keepPlaying.value) {
                viewModelScope.launch {
                    delay(500)
                    playNextSeamlessly()
                }
            }
        }
    }

    // ==================== TTS 控制方法 ====================

    fun togglePlayPause() {
        if (_selectedBook.value == null) return
        appendLog("TTS toggle: isPlaying=${player.isPlaying} keepPlaying=${_keepPlaying.value}")

        if (player.isPlaying) {
            _keepPlaying.value = false
            pausePlayback("toggle")
        } else if (_currentParagraphIndex.value >= 0) {
            _keepPlaying.value = true
            player.play()
        } else {
            startPlayback()
        }
    }
    
    private fun startPlayback() {
        viewModelScope.launch {
            _isChapterContentLoading.value = true
            val content = withContext(Dispatchers.IO) { ensureCurrentChapterContent() }
            _isChapterContentLoading.value = false

            if (content.isNullOrBlank()) {
                _errorMessage.value = "当前章节内容为空，无法开始朗读"
                return@launch
            }

            _keepPlaying.value = true
            currentSentences = parseParagraphs(content)
            currentParagraphs = currentSentences
            _totalParagraphs.value = currentSentences.size.coerceAtLeast(1)
            if (_currentParagraphIndex.value < 0) {
                _currentParagraphIndex.value = 0
            }

            ReadAudioService.startService(appContext)
            speakParagraph(_currentParagraphIndex.value)
            observeProgress()
        }
    }

    private fun playNextSeamlessly() {
        val nextIndex = _currentParagraphIndex.value + 1
        speakParagraph(nextIndex)
    }

    private fun speakParagraph(index: Int) {
        viewModelScope.launch {
            _currentParagraphIndex.value = index

            if (index < 0 || index >= currentSentences.size) {
                appendLog("朗读完毕或索引无效，停止播放. Index: $index, Sentences: ${currentSentences.size}")
                stopPlayback("finished")
                return@launch
            }

            val cachedAudio = getCachedAudio(index)
            val audioData = if (cachedAudio != null) {
                cachedAudio
            } else {
                val sentence = currentSentences.getOrNull(index)
                val audioUrl = sentence?.let { buildTtsAudioUrl(it, false) }

                if (audioUrl == null) {
                    _errorMessage.value = "无法生成TTS链接，请检查TTS设置"
                    stopPlayback("error")
                    return@launch
                }

                val data = fetchAudioBytes(audioUrl)
                if (data == null) {
                    _errorMessage.value = "TTS音频下载失败"
                    stopPlayback("error")
                    return@launch
                }

                cacheAudio(index, data)
                _preloadedParagraphs.update { it + index }
                data
            }

            playFromMemory(index, audioData)
            preloadNextParagraphs()
        }
    }

    private fun preloadNextParagraphs() {
        preloadJob?.cancel()
        preloadJob = viewModelScope.launch(Dispatchers.IO) {
            val preloadCount = _preloadCount.value
            if (preloadCount <= 0) return@launch

            val startIndex = _currentParagraphIndex.value + 1
            val endIndex = (startIndex + preloadCount).coerceAtMost(currentSentences.size)
            val validIndices = (startIndex until endIndex).toSet()
            _preloadedParagraphs.update { it.intersect(validIndices) }

            for (i in startIndex until endIndex) {
                if (getCachedAudio(i) != null) {
                    _preloadedParagraphs.update { it + i }
                    continue
                }
                if (!markPreloading(i)) continue

                val sentenceToPreload = currentSentences.getOrNull(i)
                if (sentenceToPreload.isNullOrBlank() || isPunctuationOnly(sentenceToPreload)) {
                    unmarkPreloading(i)
                    continue
                }

                val audioUrlToPreload = buildTtsAudioUrl(sentenceToPreload, isChapterTitle = false)
                if (audioUrlToPreload.isNullOrBlank()) {
                    unmarkPreloading(i)
                    continue
                }

                val data = fetchAudioBytes(audioUrlToPreload)
                if (data != null) {
                    cacheAudio(i, data)
                    _preloadedParagraphs.update { it + i }
                    appendLog("Preloaded paragraph $i successfully.")
                } else {
                    appendLog("Failed to preload paragraph $i: download failed")
                }
                unmarkPreloading(i)
            }
        }
    }

    private fun getCachedAudio(index: Int): ByteArray? = synchronized(cacheLock) {
        audioCache.get(index)
    }

    private fun cacheAudio(index: Int, data: ByteArray) {
        synchronized(cacheLock) {
            audioCache.put(index, data)
        }
    }

    private fun clearAudioCache() {
        synchronized(cacheLock) {
            audioCache.evictAll()
        }
        _preloadedParagraphs.value = emptySet()
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
                        appendLog("TTS download failed: http=${response.code}")
                        return@withContext null
                    }
                    val body = response.body ?: return@withContext null
                    body.bytes().takeIf { it.isNotEmpty() }
                }
            }.getOrElse { error ->
                appendLog("TTS download failed: ${error.message}")
                null
            }
        }
    }

    private fun playFromMemory(index: Int, data: ByteArray) {
        val dataSourceFactory = DataSource.Factory { ByteArrayDataSource(data) }
        val mediaSource = ProgressiveMediaSource.Factory(dataSourceFactory)
            .createMediaSource(MediaItem.fromUri("memory://tts/$index"))
        player.setMediaSource(mediaSource)
        player.prepare()
        player.play()
    }

    private fun pausePlayback(reason: String = "unspecified") {
        appendLog("TTS pause: reason=$reason")
        player.pause()
    }

    private fun stopPlayback(reason: String = "unspecified") {
        appendLog("TTS stop: reason=$reason")
        preloadJob?.cancel()
        clearAudioCache()
        clearPreloadingIndices()

        if (reason != "finished") {
            saveBookProgress()
        }

        _keepPlaying.value = false
        player.stop()
        player.clearMediaItems()
        _currentParagraphIndex.value = -1
        isReadingChapterTitle = false
        _preloadedParagraphs.value = emptySet()
        resetPlayback()
    }

    // ==================== 净化规则状态 ====================

    fun loadReplaceRules() {
        viewModelScope.launch {
            repository.fetchReplaceRules(
                currentServerEndpoint(),
                _publicServerAddress.value.ifBlank { null },
                _accessToken.value
            ).onSuccess {
                _replaceRules.value = it
            }.onFailure {
                _errorMessage.value = "加载净化规则失败: ${it.message}"
            }
        }
    }

    fun addReplaceRule(rule: ReplaceRule) {
        viewModelScope.launch {
            repository.addReplaceRule(
                currentServerEndpoint(),
                _publicServerAddress.value.ifBlank { null },
                _accessToken.value,
                rule
            ).onSuccess {
                loadReplaceRules()
            }.onFailure {
                _errorMessage.value = "添加规则失败: ${it.message}"
            }
        }
    }

    fun deleteReplaceRule(id: Long) {
        viewModelScope.launch {
            repository.deleteReplaceRule(
                currentServerEndpoint(),
                _publicServerAddress.value.ifBlank { null },
                _accessToken.value,
                id
            ).onSuccess {
                loadReplaceRules()
            }.onFailure {
                _errorMessage.value = "删除规则失败: ${it.message}"
            }
        }
    }

    fun toggleReplaceRule(id: Long, isEnabled: Boolean) {
        viewModelScope.launch {
            repository.toggleReplaceRule(
                currentServerEndpoint(),
                _publicServerAddress.value.ifBlank { null },
                _accessToken.value,
                id,
                isEnabled
            ).onSuccess {
                val updatedRules = _replaceRules.value.map { if (it.id == id) it.copy(isEnabled = isEnabled) else it }
                _replaceRules.value = updatedRules
                loadReplaceRules()
            }.onFailure {
                _errorMessage.value = "切换规则状态失败: ${it.message}"
            }
        }
    }

    fun previousParagraph() {
        val target = _currentParagraphIndex.value - 1
        if (target >= 0) {
            _keepPlaying.value = true
            speakParagraph(target)
        }
    }

    fun nextParagraph() {
        val target = _currentParagraphIndex.value + 1
        if (target < currentSentences.size) {
            _keepPlaying.value = true
            speakParagraph(target)
        }
    }

    fun startTts() { startPlayback() }
    fun stopTts() { stopPlayback("user") }
    
    private fun observeProgress() {
        viewModelScope.launch {
            while (_keepPlaying.value) {
                if (!player.isPlaying) {
                    delay(500)
                    continue
                }
                val duration = player.duration.takeIf { it > 0 } ?: 1L
                val position = player.currentPosition
                _playbackProgress.value = (position.toFloat() / duration).coerceIn(0f, 1f)
                _totalTime.value = formatTime(duration)
                _currentTime.value = formatTime(position)
                delay(500)
            }
        }
    }

    // ==================== 清理 ====================

    override fun onCleared() {
        super.onCleared()
        stopPlayback("cleared")
        player.removeListener(playerListener)
        PlayerPool.release()
    }

    // =================================================================
    // PASSTHROUGH METHODS (No changes below this line, only player references)
    // =================================================================
    
    fun saveBookProgress() {
        val book = _selectedBook.value ?: return
        val bookUrl = book.bookUrl ?: return
        val token = _accessToken.value
        if (token.isBlank()) return

        val index = _currentChapterIndex.value
        val progress = if (_currentParagraphIndex.value >= 0) _currentParagraphIndex.value.toDouble() else 0.0
        val title = _chapters.value.getOrNull(index)?.title ?: book.durChapterTitle

        viewModelScope.launch {
            repository.saveBookProgress(
                currentServerEndpoint(),
                _publicServerAddress.value.ifBlank { null },
                token,
                bookUrl,
                index,
                progress,
                title
            ).onFailure { error ->
                Log.w(TAG, "保存阅读进度失败: ${error.message}", error)
            }
        }
    }

    private suspend fun ensureCurrentChapterContent(): String? {
        if (_currentChapterContent.value.isNotBlank()) {
            return _currentChapterContent.value
        }
        return loadChapterContentInternal(_currentChapterIndex.value)
    }

    private fun resetPlayback() {
        _playbackProgress.value = 0f
        _currentTime.value = "00:00"
        _totalTime.value = "00:00"
    }

    fun login(server: String, username: String, password: String, onSuccess: () -> Unit) {
        viewModelScope.launch {
            _isLoading.value = true
            _errorMessage.value = null
            val normalized = if (server.contains("/api/")) server else "$server/api/5"
            val result = repository.login(normalized, _publicServerAddress.value.ifBlank { null }, username, password)
            result.onFailure { error -> _errorMessage.value = error.message }
            val loginData = result.getOrNull()
            if (loginData != null) {
                _accessToken.value = loginData.accessToken
                _username.value = username
                _serverAddress.value = normalized
                preferences.saveAccessToken(loginData.accessToken)
                preferences.saveUsername(username)
                preferences.saveServerUrl(normalized)
                loadTtsEnginesInternal()
                refreshBooksInternal(showLoading = true)
                loadReplaceRules()
                onSuccess()
            }
            _isLoading.value = false
        }
    }

    fun logout() {
        viewModelScope.launch {
            preferences.saveAccessToken("")
            _accessToken.value = ""
            _username.value = ""
            _books.value = emptyList()
            allBooks = emptyList()
            _selectedBook.value = null
            _chapters.value = emptyList()
            _currentChapterIndex.value = 0
            _currentChapterContent.value = ""
            _currentParagraphIndex.value = -1
            currentParagraphs = emptyList()
            currentSentences = emptyList()
            chapterContentCache.clear()
            stopPlayback("logout")
            clearAudioCache()
            clearPreloadingIndices()
            _availableTtsEngines.value = emptyList()
            _selectedTtsEngine.value = ""
            _narrationTtsEngine.value = ""
            _dialogueTtsEngine.value = ""
            _speakerTtsMapping.value = emptyMap()
            _replaceRules.value = emptyList()
        }
    }

    fun importBook(uri: android.net.Uri) {
        viewModelScope.launch {
            _isLoading.value = true
            _errorMessage.value = null
            val result = repository.importBook(currentServerEndpoint(), _publicServerAddress.value.ifBlank { null }, _accessToken.value, uri, appContext)
            result.onFailure { error -> _errorMessage.value = error.message }
            result.onSuccess { refreshBooksInternal(showLoading = false) }
            _isLoading.value = false
        }
    }

    fun refreshBooks() {
        if (_accessToken.value.isBlank()) return
        viewModelScope.launch { refreshBooksInternal() }
    }

    private suspend fun refreshBooksInternal(showLoading: Boolean = true) {
        if (_accessToken.value.isBlank()) return
        if (showLoading) { _isLoading.value = true }
        val booksResult = repository.fetchBooks(currentServerEndpoint(), _publicServerAddress.value.ifBlank { null }, _accessToken.value)
        booksResult.onSuccess { list ->
            allBooks = list
            applyBooksFilterAndSort()
        }.onFailure { error -> _errorMessage.value = error.message }
        if (showLoading) { _isLoading.value = false }
    }

    fun searchBooks(query: String) {
        currentSearchQuery = query
        applyBooksFilterAndSort()
    }

    fun selectBook(book: Book) {
        if (_selectedBook.value?.bookUrl == book.bookUrl) return
        stopPlayback("book_change")
        _selectedBook.value = book
        appendLog("选择书籍: ${book.name.orEmpty()} (${book.bookUrl.orEmpty()})")
        _currentChapterIndex.value = book.durChapterIndex ?: 0
        _currentParagraphIndex.value = book.durChapterProgress ?: -1
        _currentChapterContent.value = ""
        currentParagraphs = emptyList()
        chapterContentCache.clear()
        resetPlayback()
        viewModelScope.launch { loadChapters(book) }
    }

    fun setCurrentChapter(index: Int) {
        if (index !in _chapters.value.indices) return
        val chapterTitle = _chapters.value.getOrNull(index)?.title.orEmpty()
        appendLog("切换章节: index=$index title=$chapterTitle")
        val shouldContinuePlaying = _keepPlaying.value
        stopPlayback("chapter_change")
        _currentChapterIndex.value = index
        _currentChapterContent.value = ""
        currentParagraphs = emptyList()
        if (shouldContinuePlaying) {
            startPlayback()
        } else {
            viewModelScope.launch { loadChapterContent(index) }
        }
    }

    fun previousChapter() {
        if (_currentChapterIndex.value > 0) {
            setCurrentChapter(_currentChapterIndex.value - 1)
        }
    }

    fun nextChapter() {
        if (_currentChapterIndex.value < _chapters.value.lastIndex) {
            setCurrentChapter(_currentChapterIndex.value + 1)
        }
    }

    fun loadCurrentChapterContent() {
        viewModelScope.launch { loadChapterContent(_currentChapterIndex.value) }
    }

    private suspend fun loadChapters(book: Book) {
        val bookUrl = book.bookUrl ?: return
        _isChapterListLoading.value = true
        appendLog("加载章节列表: bookUrl=$bookUrl source=${book.origin.orEmpty()}")
        val chaptersResult = runCatching { repository.fetchChapterList(currentServerEndpoint(), _publicServerAddress.value.ifBlank { null }, _accessToken.value, bookUrl, book.origin) }
            .getOrElse { throwable ->
                _errorMessage.value = throwable.message
                Log.e(TAG, "加载章节列表失败", throwable)
                _isChapterListLoading.value = false
                return
            }
        chaptersResult.onSuccess { chapterList ->
            _chapters.value = chapterList
            appendLog("章节列表加载成功: ${chapterList.size} 章")
            if (chapterList.isNotEmpty()) {
                val index = _currentChapterIndex.value.coerceIn(0, chapterList.lastIndex)
                _currentChapterIndex.value = index
                loadChapterContent(index)
            }
            _isChapterListLoading.value = false
        }.onFailure { error ->
            _errorMessage.value = error.message
            appendLog("章节列表加载失败: ${error.message.orEmpty()}")
            Log.e(TAG, "加载章节列表失败", error)
            _isChapterListLoading.value = false
        }
    }

    fun loadChapterContent(index: Int) { viewModelScope.launch { appendLog("触发加载章节内容: index=$index"); loadChapterContentInternal(index) } }
    fun onChapterChange(index: Int) { setCurrentChapter(index) }
    private suspend fun loadChapterContentInternal(index: Int): String? {
        appendLog("进入loadChapterContentInternal: index=$index")
        val book = _selectedBook.value ?: return null
        val chapter = _chapters.value.getOrNull(index) ?: return null
        val bookUrl = book.bookUrl ?: return null
        val cachedInMemory = chapterContentCache[index]
        if (!cachedInMemory.isNullOrBlank()) {
            appendLog("章节内容命中内存缓存: index=$index")
            updateChapterContent(index, cachedInMemory)
            return cachedInMemory
        }
        if (_isChapterContentLoading.value) {
            appendLog("章节内容加载中，跳过请求: index=$index")
            return _currentChapterContent.value.ifBlank { null }
        }
        _isChapterContentLoading.value = true
        appendLog("开始请求章节内容: index=$index url=${chapter.url}")
        return try {
            val result = repository.fetchChapterContent(currentServerEndpoint(), _publicServerAddress.value.ifBlank { null }, _accessToken.value, bookUrl, book.origin, chapter.index)
            result.onSuccess { content ->
                appendLog("章节内容原文: index=$index length=${content.orEmpty().length}")
                val cleaned = cleanChapterContent(content.orEmpty())
                val resolved = when {
                    cleaned.isNotBlank() -> cleaned
                    content.orEmpty().isNotBlank() -> content.orEmpty().trim()
                    else -> "章节内容为空"
                }
                appendLog("章节内容清洗后: index=$index length=${resolved.length}")
                updateChapterContent(index, resolved)
            }.onFailure { error ->
                _errorMessage.value = "加载失败: ${error.message}".trim()
                appendLog("章节内容加载失败: index=$index error=${error.message.orEmpty()}")
                Log.e(TAG, "加载章节内容失败", error)
            }
            _currentChapterContent.value
        } catch (e: Exception) {
            _errorMessage.value = "系统异常: ${e.localizedMessage}".trim()
            appendLog("章节内容加载异常: index=$index error=${e.localizedMessage.orEmpty()}")
            Log.e(TAG, "加载章节内容异常", e)
            null
        } finally {
            _isChapterContentLoading.value = false
        }
    }
    private fun updateChapterContent(index: Int, content: String) {
        _currentChapterContent.value = content
        chapterContentCache[index] = content
        currentParagraphs = parseParagraphs(content)
        currentSentences = currentParagraphs
        _totalParagraphs.value = currentParagraphs.size.coerceAtLeast(1)
    }
    private fun parseParagraphs(content: String): List<String> = content.split("\n").map { it.trim() }.filter { it.isNotBlank() }
    private fun cleanChapterContent(raw: String): String {
        if (raw.isBlank()) return ""

        var content = raw
        _replaceRules.value.filter { it.isEnabled }.sortedBy { it.order }.forEach { rule ->
            try {
                content = content.replace(Regex(rule.pattern), rule.replacement)
            } catch (e: Exception) {
                Log.w(TAG, "净化规则执行失败: ${rule.name}", e)
            }
        }

        content = content.replace("(?is)<svg.*?</svg>".toRegex(), "")
        content = content.replace("(?is)<script.*?</script>".toRegex(), "")
        content = content.replace("(?is)<style.*?</style>".toRegex(), "")
        content = content.replace("(?is)<(?!img\\b)[^>]+>".toRegex(), "\n")

        return content
            .replace("&nbsp;", " ")
            .replace("&amp;", "&")
            .lines()
            .map { it.trim() }
            .filter { it.isNotBlank() }
            .joinToString("\n")
    }
    private suspend fun loadTtsEnginesInternal() {
        if (_accessToken.value.isBlank()) return
        var engines: List<HttpTTS> = emptyList()
        val enginesResult = repository.fetchTtsEngines(currentServerEndpoint(), _publicServerAddress.value.ifBlank { null }, _accessToken.value)
        enginesResult.onSuccess { list ->
            engines = list
            _availableTtsEngines.value = list
        }.onFailure { error -> _errorMessage.value = error.message }
        val defaultResult = repository.fetchDefaultTts(currentServerEndpoint(), _publicServerAddress.value.ifBlank { null }, _accessToken.value)
        val defaultId = defaultResult.getOrNull()
        val resolved = listOf(_selectedTtsEngine.value, defaultId, engines.firstOrNull()?.id).firstOrNull { !it.isNullOrBlank() }.orEmpty()
        if (resolved.isNotBlank() && resolved != _selectedTtsEngine.value) {
            _selectedTtsEngine.value = resolved
            preferences.saveSelectedTtsId(resolved)
        }
    }
    fun loadTtsEngines() { if (_accessToken.value.isBlank()) return; viewModelScope.launch { loadTtsEnginesInternal() } }
    fun selectTtsEngine(engineId: String) { _selectedTtsEngine.value = engineId; viewModelScope.launch { preferences.saveSelectedTtsId(engineId) } }
    fun selectNarrationTtsEngine(engineId: String) { _narrationTtsEngine.value = engineId; viewModelScope.launch { preferences.saveNarrationTtsId(engineId) } }
    fun selectDialogueTtsEngine(engineId: String) { _dialogueTtsEngine.value = engineId; viewModelScope.launch { preferences.saveDialogueTtsId(engineId) } }
    fun updateSpeakerMapping(name: String, engineId: String) {
        val trimmed = name.trim(); if (trimmed.isBlank()) return
        val updated = _speakerTtsMapping.value.toMutableMap(); updated[trimmed] = engineId
        _speakerTtsMapping.value = updated
        viewModelScope.launch { preferences.saveSpeakerTtsMapping(serializeSpeakerMapping(updated)) }
    }
    fun removeSpeakerMapping(name: String) {
        val updated = _speakerTtsMapping.value.toMutableMap(); updated.remove(name)
        _speakerTtsMapping.value = updated
        viewModelScope.launch { preferences.saveSpeakerTtsMapping(serializeSpeakerMapping(updated)) }
    }
    fun updateServerAddress(address: String) { _serverAddress.value = address; viewModelScope.launch { preferences.saveServerUrl(address) } }
    fun updateSpeechSpeed(speed: Int) { _speechSpeed.value = speed.coerceIn(5, 50); viewModelScope.launch { preferences.saveSpeechRate(_speechSpeed.value / 20.0) } }
    fun updatePreloadCount(count: Int) { _preloadCount.value = count.coerceIn(1, 10); viewModelScope.launch { preferences.savePreloadCount(_preloadCount.value.toFloat()) } }
    fun updateReadingFontSize(size: Float) { _readingFontSize.value = size.coerceIn(12f, 28f); viewModelScope.launch { preferences.saveReadingFontSize(_readingFontSize.value) } }
    fun updateLoggingEnabled(enabled: Boolean) { _loggingEnabled.value = enabled; viewModelScope.launch { preferences.saveLoggingEnabled(enabled) } }
    fun updateBookshelfSortByRecent(enabled: Boolean) { _bookshelfSortByRecent.value = enabled; viewModelScope.launch { preferences.saveBookshelfSortByRecent(enabled); applyBooksFilterAndSort() } }
    fun clearCache() {
        viewModelScope.launch {
            clearAudioCache()
            clearPreloadingIndices()
        }
    }
    private fun buildTtsAudioUrl(sentence: String, isChapterTitle: Boolean): String? {
        val ttsId = resolveTtsIdForSentence(sentence, isChapterTitle) ?: return null
        return repository.buildTtsAudioUrl(currentServerEndpoint(), _accessToken.value, ttsId, sentence, _speechSpeed.value / 20.0)
    }
    private fun applyBooksFilterAndSort() {
        val filtered = if (currentSearchQuery.isBlank()) allBooks else allBooks.filter { it.name.orEmpty().lowercase().contains(currentSearchQuery.lowercase()) || it.author.orEmpty().lowercase().contains(currentSearchQuery.lowercase()) }
        val sorted = if (_bookshelfSortByRecent.value) filtered.mapIndexed { index, book -> index to book }.sortedWith { a, b ->
            val time1 = a.second.durChapterTime ?: 0L; val time2 = b.second.durChapterTime ?: 0L
            when { time1 == 0L && time2 == 0L -> a.first.compareTo(b.first); time1 == 0L -> 1; time2 == 0L -> -1; time1 == time2 -> a.first.compareTo(b.first); else -> if (time1 > time2) -1 else 1 }
        }.map { it.second } else filtered
        _books.value = sorted
    }
    private fun isPunctuationOnly(sentence: String): Boolean = sentence.trim().all { it in "，。！？；、“”\"'…—-· " }
    private fun parseSpeakerMapping(raw: String): Map<String, String> { if (raw.isBlank()) return emptyMap(); return runCatching { val obj = JSONObject(raw); obj.keys().asSequence().associateWith { key -> obj.optString(key) } }.getOrDefault(emptyMap()) }
    private fun serializeSpeakerMapping(mapping: Map<String, String>): String { val obj = JSONObject(); mapping.forEach { (key, value) -> obj.put(key, value) }; return obj.toString() }
    fun exportLogs(context: android.content.Context): android.net.Uri? { if (!logFile.exists()) return null; return runCatching { val exportFile = File(context.cacheDir, LOG_EXPORT_NAME); logFile.copyTo(exportFile, overwrite = true); androidx.core.content.FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", exportFile) }.getOrNull() }
    fun clearLogs() { runCatching { if (logFile.exists()) { logFile.writeText("") } } }
    private fun appendLog(message: String) { if (!_loggingEnabled.value) return; val timestamp = SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.getDefault()).format(Date()); val line = "[$timestamp] $message\n"; runCatching { logFile.appendText(line) } }
}
