package com.readapp.viewmodel

import android.app.Application
import android.util.Log
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import com.readapp.data.ReadApiService
import com.readapp.data.ReadRepository
import com.readapp.data.UserPreferences
import com.readapp.data.model.Book
import com.readapp.data.model.Chapter
import com.readapp.data.model.HttpTTS
import com.readapp.media.PlayerHolder
import com.readapp.media.ReadAudioService
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.firstOrNull
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class BookViewModel(application: Application) : AndroidViewModel(application) {

    private data class PlaybackSegment(
        val chapterIndex: Int,
        val paragraphIndex: Int,
        val isChapterTitle: Boolean
    )

    private data class ChapterPlaybackData(
        val content: String,
        val paragraphs: List<String>
    )

    companion object {
        private const val TAG = "BookViewModel"
        private const val LOG_FILE_NAME = "reader_logs.txt"
        private const val LOG_EXPORT_NAME = "reader_logs_export.txt"

        val Factory: ViewModelProvider.Factory = viewModelFactory {
            initializer {
                val application = this[ViewModelProvider.AndroidViewModelFactory.APPLICATION_KEY] as Application
                BookViewModel(application)
            }
        }
    }

    // ==================== Dependencies ====================

    private val appContext = getApplication<Application>()
    private val preferences = UserPreferences(appContext)
    private val repository = ReadRepository { endpoint ->
        ReadApiService.create(endpoint) { accessToken.value }
    }
    private val player: ExoPlayer = PlayerHolder.get(appContext).apply {
        addListener(object : Player.Listener {
            override fun onIsPlayingChanged(isPlaying: Boolean) {
                _isPlaying.value = isPlaying
            }

            override fun onMediaItemTransition(mediaItem: MediaItem?, reason: Int) {
                val segment = playbackSegments.getOrNull(currentMediaItemIndex)
                updatePlaybackSegment(segment)
            }

            override fun onPlaybackStateChanged(playbackState: Int) {
                if (playbackState == Player.STATE_ENDED) {
                    _playbackProgress.value = 1f
                    stopPlayback()
                }
            }
        })
    }
    private var currentSentences: List<String> = emptyList()
    private var isReadingChapterTitle = false
    private var currentSearchQuery = ""
    private var playbackSegments: List<PlaybackSegment> = emptyList()
    private var playbackChapterData: Map<Int, ChapterPlaybackData> = emptyMap()

    // ==================== 书籍相关状态 ====================

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

    private var currentParagraphs: List<String> = emptyList()

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

    // ==================== TTS 设置 ====================

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

    // ==================== 服务器设置 ====================

    private val _serverAddress = MutableStateFlow("http://127.0.0.1:8080/api/5")
    val serverAddress: StateFlow<String> = _serverAddress.asStateFlow()

    private val _publicServerAddress = MutableStateFlow("")
    val publicServerAddress: StateFlow<String> = _publicServerAddress.asStateFlow()

    private val _accessToken = MutableStateFlow("")
    val accessToken: StateFlow<String> = _accessToken.asStateFlow()

    private val _username = MutableStateFlow("")
    val username: StateFlow<String> = _username.asStateFlow()

    // ==================== UI 状态 ====================

    private val _errorMessage = MutableStateFlow<String?>(null)
    val errorMessage: StateFlow<String?> = _errorMessage.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    private val _isContentLoading = MutableStateFlow(false)
    val isContentLoading: StateFlow<Boolean> = _isContentLoading.asStateFlow()
    private val _isInitialized = MutableStateFlow(false)
    val isInitialized: StateFlow<Boolean> = _isInitialized.asStateFlow()

    // ==================== 初始化 ====================

    init {
        viewModelScope.launch {
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
                } finally {
                    _isLoading.value = false
                }
            }

            _isInitialized.value = true
        }
    }

    // ==================== 认证方法 ====================

    fun login(server: String, username: String, password: String, onSuccess: () -> Unit) {
        viewModelScope.launch {
            _isLoading.value = true
            _errorMessage.value = null

            val normalized = if (server.contains("/api/")) server else "$server/api/5"
            val result = repository.login(
                normalized,
                _publicServerAddress.value.ifBlank { null },
                username,
                password
            )

            result.onFailure { error ->
                _errorMessage.value = error.message
            }

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
            clearPlaybackQueue()
            stopPlayback()
            _availableTtsEngines.value = emptyList()
            _selectedTtsEngine.value = ""
            _narrationTtsEngine.value = ""
            _dialogueTtsEngine.value = ""
            _speakerTtsMapping.value = emptyMap()
        }
    }

    // ==================== 书籍操作方法 ====================

    fun refreshBooks() {
        if (_accessToken.value.isBlank()) return

        viewModelScope.launch {
            refreshBooksInternal()
        }
    }

    private suspend fun refreshBooksInternal(showLoading: Boolean = true) {
        if (_accessToken.value.isBlank()) return

        if (showLoading) {
            _isLoading.value = true
        }

        val booksResult = repository.fetchBooks(
            currentServerEndpoint(),
            _publicServerAddress.value.ifBlank { null },
            _accessToken.value
        )

        booksResult.onSuccess { list ->
            allBooks = list
            applyBooksFilterAndSort()
        }.onFailure { error ->
            _errorMessage.value = error.message
        }

        if (showLoading) {
            _isLoading.value = false
        }
    }

    fun searchBooks(query: String) {
        currentSearchQuery = query
        applyBooksFilterAndSort()
    }

    fun selectBook(book: Book) {
        _selectedBook.value = book
        appendLog("选择书籍: ${book.name.orEmpty()} (${book.bookUrl.orEmpty()})")
        _currentChapterIndex.value = book.durChapterIndex ?: 0
        _currentChapterContent.value = ""
        _currentParagraphIndex.value = -1
        currentParagraphs = emptyList()
        chapterContentCache.clear()
        resetPlayback()

        viewModelScope.launch {
            loadChapters(book)
        }
    }

    // ==================== 章节操作方法 ====================

    fun setCurrentChapter(index: Int) {
        if (index !in _chapters.value.indices) return

        val chapterTitle = _chapters.value.getOrNull(index)?.title.orEmpty()
        appendLog("切换章节: index=$index title=$chapterTitle")
        _keepPlaying.value = _isPlaying.value || _keepPlaying.value
        _currentChapterIndex.value = index
        val cachedContent = chapterContentCache[index]
        _currentChapterContent.value = cachedContent.orEmpty()
        currentParagraphs = cachedContent?.let { parseParagraphs(it) } ?: emptyList()
        _totalParagraphs.value = currentParagraphs.size.coerceAtLeast(1)
        _currentParagraphIndex.value = -1
        currentSentences = currentParagraphs
        clearPlaybackQueue()
        resetPlayback()

        viewModelScope.launch {
            loadChapterContent(index)
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
        viewModelScope.launch {
            loadChapterContent(_currentChapterIndex.value)
        }
    }

    private suspend fun loadChapters(book: Book) {
        val bookUrl = book.bookUrl ?: return

        _isContentLoading.value = true
        appendLog("加载章节列表: bookUrl=$bookUrl source=${book.origin.orEmpty()}")
        val chaptersResult = runCatching {
            repository.fetchChapterList(
                currentServerEndpoint(),
                _publicServerAddress.value.ifBlank { null },
                _accessToken.value,
                bookUrl,
                book.origin
            )
        }.getOrElse { throwable ->
            _errorMessage.value = throwable.message
            Log.e(TAG, "加载章节列表失败", throwable)
            _isContentLoading.value = false
            return
        }

        chaptersResult.onSuccess { chapterList ->
            _chapters.value = chapterList
            appendLog("章节列表加载成功: ${chapterList.size} 章")

            if (chapterList.isNotEmpty()) {
                val index = _currentChapterIndex.value.coerceIn(0, chapterList.lastIndex)
                _currentChapterIndex.value = index
                val inlineContent = chapterList.getOrNull(index)?.content.orEmpty()
                if (inlineContent.isNotBlank()) {
                    updateChapterContent(index, cleanChapterContent(inlineContent))
                }
                loadChapterContent(index)
            }
            _isContentLoading.value = false
        }.onFailure { error ->
            _errorMessage.value = error.message
            appendLog("章节列表加载失败: ${error.message.orEmpty()}")
            Log.e(TAG, "加载章节列表失败", error)
            _isContentLoading.value = false
        }
    }

    fun loadChapterContent(index: Int) {
        viewModelScope.launch {
            appendLog("触发加载章节内容: index=$index")
            loadChapterContentInternal(index)
        }
    }

    fun onChapterChange(index: Int) {
        setCurrentChapter(index)
    }

    private suspend fun loadChapterContentInternal(index: Int): String? {
        appendLog("进入loadChapterContentInternal: index=$index")
        val book = _selectedBook.value ?: return null
        val chapter = _chapters.value.getOrNull(index) ?: return null
        val bookUrl = book.bookUrl ?: return null

        if (_isContentLoading.value) {
            appendLog("章节内容加载中，跳过请求: index=$index")
            return _currentChapterContent.value.ifBlank { null }
        }

        // 优先使用缓存内容
        val cached = chapter.content
        val cachedInMemory = chapterContentCache[index]
        if (!cached.isNullOrBlank()) {
            appendLog("章节内容命中缓存: index=$index")
            updateChapterContent(index, cached)
            return cached
        }
        if (!cachedInMemory.isNullOrBlank()) {
            appendLog("章节内容命中内存缓存: index=$index")
            updateChapterContent(index, cachedInMemory)
            return cachedInMemory
        }

        _isContentLoading.value = true
        appendLog("开始请求章节内容: index=$index")
        _currentChapterContent.value = ""
        appendLog("开始加载章节内容: index=$index url=${chapter.url}")
        appendLog(
            "请求章节内容: bookUrl=$bookUrl source=${book.origin.orEmpty()} index=$index chapterUrl=${chapter.url}"
        )

        return try {
            val result = repository.fetchChapterContent(
                currentServerEndpoint(),
                _publicServerAddress.value.ifBlank { null },
                _accessToken.value,
                bookUrl,
                book.origin,
                chapter.index
            )

            result.onSuccess { content ->
                appendLog("章节内容原文: index=$index length=${content.orEmpty().length}")
                appendLog("章节内容原文内容: index=$index content=${content.orEmpty()}")
                val cleaned = cleanChapterContent(content.orEmpty())
                val resolved = when {
                    cleaned.isNotBlank() -> cleaned
                    content.orEmpty().isNotBlank() -> content.orEmpty().trim()
                    else -> "章节内容为空"
                }
                appendLog("章节内容清洗后: index=$index length=${resolved.length}")
                appendLog("章节内容清洗后内容: index=$index content=$resolved")
                appendLog("章节内容加载成功: index=$index length=${resolved.length}")
                updateChapterContent(index, resolved)
            }.onFailure { error ->
                _currentChapterContent.value = "加载失败: ${error.message}".trim()
                appendLog("章节内容加载失败: index=$index error=${error.message.orEmpty()}")
                Log.e(TAG, "加载章节内容失败", error)
            }

            _currentChapterContent.value.ifBlank { cachedInMemory }
        } catch (e: Exception) {
            _currentChapterContent.value = "系统异常: ${e.localizedMessage}".trim()
            appendLog("章节内容加载异常: index=$index error=${e.localizedMessage.orEmpty()}")
            Log.e(TAG, "加载章节内容异常", e)
            cachedInMemory
        } finally {
            _isContentLoading.value = false
            if (_currentChapterContent.value.isBlank() && !cachedInMemory.isNullOrBlank()) {
                updateChapterContent(index, cachedInMemory)
            }
        }
    }

    private fun updateChapterContent(index: Int, content: String) {
        // 更新章节列表中的内容
        val updatedChapters = _chapters.value.toMutableList()
        if (index in updatedChapters.indices) {
            updatedChapters[index] = updatedChapters[index].copy(content = content)
            _chapters.value = updatedChapters
        }

        // 更新当前章节内容
        _currentChapterContent.value = content
        chapterContentCache[index] = content

        // 分割段落
        currentParagraphs = parseParagraphs(content)
        currentSentences = currentParagraphs

        _totalParagraphs.value = currentParagraphs.size.coerceAtLeast(1)


        if (_keepPlaying.value && !_isPlaying.value) {
            _currentParagraphIndex.value = 0
            startPlayback()
        }
    }

    private fun parseParagraphs(content: String): List<String> {
        return content.split("\n").map { it.trim() }.filter { it.isNotBlank() }
    }

    private fun cleanChapterContent(raw: String): String {
        if (raw.isBlank()) return ""

        val withoutSvg = raw.replace("(?is)<svg.*?</svg>".toRegex(), "")
        val withoutScripts = withoutSvg
            .replace("(?is)<script.*?</script>".toRegex(), "")
            .replace("(?is)<style.*?</style>".toRegex(), "")

        val withoutTags = withoutScripts.replace("(?is)<(?!img\\b)[^>]+>".toRegex(), "\n")

        return withoutTags
            .replace("&nbsp;", " ")
            .replace("&amp;", "&")
            .lines()
            .map { it.trim() }
            .filter { it.isNotBlank() }
            .joinToString("\n")
    }

    // ==================== TTS 控制方法 ====================

    fun togglePlayPause() {
        if (_selectedBook.value == null) return

        if (!_isPlaying.value) {
            startPlayback()
        } else {
            pausePlayback()
        }
    }

    private fun startPlayback() {
        viewModelScope.launch {
            // 确保有章节内容
            val content = ensureCurrentChapterContent() ?: return@launch

            // 如果还没有段落索引，从第一段开始
            if (_currentParagraphIndex.value < 0) {
                _currentParagraphIndex.value = 0
            }

            // 更新句子列表
            currentSentences = splitTextIntoSentences(content)
            currentParagraphs = currentSentences
            _totalParagraphs.value = currentSentences.size.coerceAtLeast(1)
            _keepPlaying.value = true

            ReadAudioService.startService(appContext)

            startPlaybackFrom(_currentChapterIndex.value, _currentParagraphIndex.value)

            // 开始观察播放进度
            observeProgress()
        }
    }

    private fun pausePlayback() {
        player.playWhenReady = false
        _keepPlaying.value = false
    }

    private fun stopPlayback() {
        player.stop()
        _isPlaying.value = false
        _keepPlaying.value = false
        _currentParagraphIndex.value = -1
        isReadingChapterTitle = false
        clearPlaybackQueue()
        resetPlayback()
    }

    fun previousParagraph() {
        if (player.hasPreviousMediaItem()) {
            player.seekToPreviousMediaItem()
            if (_keepPlaying.value) {
                player.play()
            }
        } else if (_currentChapterIndex.value > 0) {
            // 跳到上一章的最后一段
            previousChapter()
        }
    }

    fun nextParagraph() {
        if (player.hasNextMediaItem()) {
            player.seekToNextMediaItem()
            if (_keepPlaying.value) {
                player.play()
            }
        } else {
            // 切换到下一章
            if (_currentChapterIndex.value < _chapters.value.lastIndex) {
                nextChapter()
                viewModelScope.launch {
                    delay(500) // 等待章节加载
                    if (currentParagraphs.isNotEmpty()) {
                        _currentParagraphIndex.value = 0
                        startPlaybackFrom(_currentChapterIndex.value, _currentParagraphIndex.value)
                    }
                }
            } else {
                // 已经是最后一章，停止播放
                stopPlayback()
            }
        }
    }

    private suspend fun ensureCurrentChapterContent(): String? {
        if (_currentChapterContent.value.isNotBlank()) {
            return _currentChapterContent.value
        }
        return loadChapterContentInternal(_currentChapterIndex.value)
    }

    private fun observeProgress() {
        viewModelScope.launch {
            while (_isPlaying.value) {
                val duration = player.duration.takeIf { it > 0 } ?: 1L
                val position = player.currentPosition
                _playbackProgress.value = (position.toFloat() / duration).coerceIn(0f, 1f)
                _totalTime.value = formatTime(duration)
                _currentTime.value = formatTime(position)
                delay(500)
            }
        }
    }

    // ==================== TTS 对外接口 ====================

    fun startTts() {
        startPlayback()
    }

    fun stopTts() {
        stopPlayback()
    }

    // ==================== TTS 引擎管理 ====================

    fun loadTtsEngines() {
        if (_accessToken.value.isBlank()) return

        viewModelScope.launch {
            loadTtsEnginesInternal()
        }
    }

    private suspend fun loadTtsEnginesInternal() {
        if (_accessToken.value.isBlank()) return

        var engines: List<HttpTTS> = emptyList()
        val enginesResult = repository.fetchTtsEngines(
            currentServerEndpoint(),
            _publicServerAddress.value.ifBlank { null },
            _accessToken.value
        )

        enginesResult.onSuccess { list ->
            engines = list
            _availableTtsEngines.value = list
        }.onFailure { error ->
            _errorMessage.value = error.message
        }

        val defaultResult = repository.fetchDefaultTts(
            currentServerEndpoint(),
            _publicServerAddress.value.ifBlank { null },
            _accessToken.value
        )

        val defaultId = defaultResult.getOrNull()
        val resolved = listOf(
            _selectedTtsEngine.value,
            defaultId,
            engines.firstOrNull()?.id
        ).firstOrNull { !it.isNullOrBlank() }.orEmpty()

        if (resolved.isNotBlank() && resolved != _selectedTtsEngine.value) {
            _selectedTtsEngine.value = resolved
            preferences.saveSelectedTtsId(resolved)
        }
    }

    fun selectTtsEngine(engineId: String) {
        _selectedTtsEngine.value = engineId
        viewModelScope.launch {
            preferences.saveSelectedTtsId(engineId)
        }
    }

    fun selectNarrationTtsEngine(engineId: String) {
        _narrationTtsEngine.value = engineId
        viewModelScope.launch {
            preferences.saveNarrationTtsId(engineId)
        }
    }

    fun selectDialogueTtsEngine(engineId: String) {
        _dialogueTtsEngine.value = engineId
        viewModelScope.launch {
            preferences.saveDialogueTtsId(engineId)
        }
    }

    fun updateSpeakerMapping(name: String, engineId: String) {
        val trimmed = name.trim()
        if (trimmed.isBlank()) return
        val updated = _speakerTtsMapping.value.toMutableMap()
        updated[trimmed] = engineId
        _speakerTtsMapping.value = updated
        viewModelScope.launch {
            preferences.saveSpeakerTtsMapping(serializeSpeakerMapping(updated))
        }
    }

    fun removeSpeakerMapping(name: String) {
        val updated = _speakerTtsMapping.value.toMutableMap()
        updated.remove(name)
        _speakerTtsMapping.value = updated
        viewModelScope.launch {
            preferences.saveSpeakerTtsMapping(serializeSpeakerMapping(updated))
        }
    }

    // ==================== 设置方法 ====================

    fun updateServerAddress(address: String) {
        _serverAddress.value = address
        viewModelScope.launch {
            preferences.saveServerUrl(address)
        }
    }

    fun updateSpeechSpeed(speed: Int) {
        _speechSpeed.value = speed.coerceIn(5, 50)
        viewModelScope.launch {
            preferences.saveSpeechRate(_speechSpeed.value / 20.0)
        }
    }

    fun updatePreloadCount(count: Int) {
        _preloadCount.value = count.coerceIn(1, 10)
        viewModelScope.launch {
            preferences.savePreloadCount(_preloadCount.value.toFloat())
        }
    }

    fun updateReadingFontSize(size: Float) {
        _readingFontSize.value = size.coerceIn(12f, 28f)
        viewModelScope.launch {
            preferences.saveReadingFontSize(_readingFontSize.value)
        }
    }

    fun updateLoggingEnabled(enabled: Boolean) {
        _loggingEnabled.value = enabled
        viewModelScope.launch {
            preferences.saveLoggingEnabled(enabled)
        }
    }

    fun updateBookshelfSortByRecent(enabled: Boolean) {
        _bookshelfSortByRecent.value = enabled
        viewModelScope.launch {
            preferences.saveBookshelfSortByRecent(enabled)
            applyBooksFilterAndSort()
        }
    }

    fun clearCache() {
        // TODO: 实现缓存清理逻辑
    }

    fun saveBookProgress() {
        val book = _selectedBook.value ?: return
        val bookUrl = book.bookUrl ?: return
        val token = _accessToken.value
        if (token.isBlank()) return

        val index = _currentChapterIndex.value
        val title = _chapters.value.getOrNull(index)?.title ?: book.durChapterTitle

        viewModelScope.launch {
            repository.saveBookProgress(
                currentServerEndpoint(),
                _publicServerAddress.value.ifBlank { null },
                token,
                bookUrl,
                index,
                0.0,
                title
            ).onFailure { error ->
                Log.w(TAG, "保存阅读进度失败: ${error.message}", error)
            }
        }
    }

    // ==================== 辅助方法 ====================

    private fun currentServerEndpoint(): String {
        val normalized = _serverAddress.value
            .trim()
            .trimEnd('/')
        return if (normalized.contains("/api/")) normalized else "$normalized/api/5"
    }

    private fun resetPlayback() {
        _playbackProgress.value = 0f
        _currentTime.value = "00:00"
        _totalTime.value = "00:00"
    }

    private fun formatTime(millis: Long): String {
        val totalSeconds = millis / 1000
        val minutes = totalSeconds / 60
        val seconds = totalSeconds % 60
        return String.format("%02d:%02d", minutes, seconds)
    }

    private fun splitTextIntoSentences(text: String): List<String> {
        val filtered = cleanChapterContent(text)
        return filtered.split("\n").map { it.trim() }.filter { it.isNotBlank() }
    }

    private fun resolvedNarrationTtsId(): String {
        return _narrationTtsEngine.value.ifBlank { _selectedTtsEngine.value }
    }

    private fun resolvedDialogueTtsId(): String {
        return _dialogueTtsEngine.value.ifBlank { resolvedNarrationTtsId() }
    }

    private fun isDialogueSentence(sentence: String): Boolean {
        return sentence.contains("“") || sentence.contains("\"")
    }

    private fun extractSpeaker(sentence: String): String? {
        val regex = "^\\s*([\\p{Han}A-Za-z0-9_·]{1,12})[\\s　]*[：:，,]?\\s*[\"“]".toRegex()
        val match = regex.find(sentence) ?: return null
        return match.groups[1]?.value?.trim()
    }

    private fun resolveTtsIdForSentence(sentence: String, isChapterTitle: Boolean): String? {
        if (isChapterTitle) {
            return resolvedNarrationTtsId().ifBlank { _selectedTtsEngine.value }.ifBlank { null }
        }

        var targetId = resolvedNarrationTtsId()
        if (isDialogueSentence(sentence)) {
            val speaker = extractSpeaker(sentence)
            if (speaker != null) {
                val normalized = speaker.replace(" ", "")
                val mapped = _speakerTtsMapping.value[speaker] ?: _speakerTtsMapping.value[normalized]
                if (!mapped.isNullOrBlank()) {
                    targetId = mapped
                } else {
                    targetId = resolvedDialogueTtsId()
                }
            } else {
                targetId = resolvedDialogueTtsId()
            }
        }

        if (targetId.isBlank()) targetId = _selectedTtsEngine.value
        return targetId.ifBlank { null }
    }

    private fun buildTtsAudioUrl(sentence: String, isChapterTitle: Boolean): String? {
        val ttsId = resolveTtsIdForSentence(sentence, isChapterTitle) ?: return null
        return repository.buildTtsAudioUrl(
            currentServerEndpoint(),
            _accessToken.value,
            ttsId,
            sentence,
            _speechSpeed.value / 20.0
        )
    }

    private suspend fun startPlaybackFrom(chapterIndex: Int, paragraphIndex: Int) {
        val book = _selectedBook.value ?: return
        val chapters = _chapters.value
        if (chapters.isEmpty()) return

        val startIndex = paragraphIndex.coerceAtLeast(0)
        val queue = buildPlaybackQueue(book, chapterIndex, startIndex)
        if (queue.mediaItems.isEmpty()) {
            _errorMessage.value = "无法获取TTS音频地址"
            return
        }

        playbackSegments = queue.segments
        playbackChapterData = queue.chapterData
        _preloadedParagraphs.value = emptySet()
        _preloadedChapters.value = queue.preloadedChapters.toSet()

    private fun playAudioData(data: ByteArray) {
        val mediaItem = MediaItem.Builder().setUri("bytearray://tts").build()
        val mediaSourceFactory = ProgressiveMediaSource.Factory(
            object : DataSource.Factory {
                override fun createDataSource(): DataSource {
                    return ByteArrayDataSource(data)
                }
            }
        )
        val mediaSource = mediaSourceFactory.createMediaSource(mediaItem)
        player.setMediaSource(mediaSource)
        player.prepare()
        player.play()
        updatePlaybackSegment(queue.segments.firstOrNull())
    }

    private data class PlaybackQueue(
        val mediaItems: List<MediaItem>,
        val segments: List<PlaybackSegment>,
        val chapterData: Map<Int, ChapterPlaybackData>,
        val preloadedChapters: List<Int>
    )

    private suspend fun buildPlaybackQueue(
        book: Book,
        startChapterIndex: Int,
        startParagraphIndex: Int
    ): PlaybackQueue {
        val chapters = _chapters.value
        val endChapterIndex = (startChapterIndex + _preloadCount.value).coerceAtMost(chapters.lastIndex)
        val mediaItems = mutableListOf<MediaItem>()
        val segments = mutableListOf<PlaybackSegment>()
        val chapterData = mutableMapOf<Int, ChapterPlaybackData>()
        val preloadedChapters = mutableListOf<Int>()

        for (chapterIndex in startChapterIndex..endChapterIndex) {
            val content = if (chapterIndex == _currentChapterIndex.value) {
                ensureCurrentChapterContent()
            } else {
                fetchChapterContentForPlayback(chapterIndex, book)
            }

    private fun processPreloadQueue() {
        if (preloadingJobActive) return
        preloadingJobActive = true
        viewModelScope.launch(Dispatchers.IO) {
            try {
                appendLog("TTS预加载: 开始处理队列")
                val semaphore = Semaphore(maxConcurrentPreloads)
                val jobs = mutableListOf<kotlinx.coroutines.Job>()

                while (true) {
                    val index = dequeuePreloadIndex() ?: break
                    if (getCachedAudio(_currentChapterIndex.value, index) != null) {
                        appendLog("TTS预加载: 队列跳过已缓存 index=$index")
                        markPreloaded(index)
                        continue
                    }

            val chapterTitle = chapters.getOrNull(chapterIndex)?.title.orEmpty()
            if (chapterTitle.isNotBlank()) {
                buildMediaItem(chapterIndex, -1, chapterTitle, isChapterTitle = true)?.let { item ->
                    mediaItems.add(item)
                    segments.add(PlaybackSegment(chapterIndex, -1, true))
                }
            }

            val startIndex = if (chapterIndex == startChapterIndex) startParagraphIndex else 0
            for (index in startIndex until paragraphs.size) {
                val sentence = paragraphs[index]
                if (sentence.isBlank() || isPunctuationOnly(sentence)) continue
                buildMediaItem(chapterIndex, index, sentence, isChapterTitle = false)?.let { item ->
                    mediaItems.add(item)
                    segments.add(PlaybackSegment(chapterIndex, index, false))
                }
            }
        }

        return PlaybackQueue(mediaItems, segments, chapterData, preloadedChapters)
    }

    private fun buildMediaItem(
        chapterIndex: Int,
        paragraphIndex: Int,
        sentence: String,
        isChapterTitle: Boolean = false
    ): Boolean {
        val audioUrl = buildTtsAudioUrl(sentence, isChapterTitle) ?: run {
            appendLog("TTS预加载: 无法构建音频URL index=$sentenceIndex")
            return false
        }
        appendLog("TTS预加载: 请求URL index=$sentenceIndex url=$audioUrl")
        val request = Request.Builder().url(audioUrl).build()
        return withContext(Dispatchers.IO) {
            val response = try {
                httpClient.newCall(request).execute()
            } catch (error: Exception) {
                appendLog("TTS预加载: 请求异常 index=$sentenceIndex error=$error")
                return@withContext false
            }

            response.use { httpResponse ->
                if (!httpResponse.isSuccessful) {
                    appendLog("TTS预加载: 请求失败 index=$sentenceIndex code=${httpResponse.code} url=$audioUrl")
                    return@withContext false
                }
                val contentType = httpResponse.header("Content-Type").orEmpty()
                val bytes = httpResponse.body?.bytes() ?: run {
                    appendLog("TTS预加载: 响应无内容 index=$sentenceIndex url=$audioUrl")
                    return@withContext false
                }
                if (!contentType.contains("audio") && bytes.size < 2000) {
                    appendLog("TTS预加载: 音频无效 index=$sentenceIndex contentType=$contentType size=${bytes.size} url=$audioUrl")
                    return@withContext false
                }
            } catch (error: Exception) {
                appendLog("TTS预加载: 请求异常 index=$sentenceIndex error=$error")
                false
            }
        }
    }

    private suspend fun fetchChapterContentForPlayback(index: Int, book: Book): String? {
        val chapter = _chapters.value.getOrNull(index) ?: return null
        val cached = chapter.content ?: chapterContentCache[index]
        if (!cached.isNullOrBlank()) {
            val cleaned = cleanChapterContent(cached)
            cacheChapterContent(index, cleaned)
            return cleaned
        }

        val result = repository.fetchChapterContent(
            currentServerEndpoint(),
            _publicServerAddress.value.ifBlank { null },
            _accessToken.value,
            book.bookUrl ?: return null,
            book.origin,
            chapter.index
        )

        result.onSuccess { content ->
            val cleaned = cleanChapterContent(content.orEmpty())
            cacheChapterContent(index, cleaned)
        }

        return chapterContentCache[index]
    }

    private fun cacheChapterContent(index: Int, content: String) {
        if (content.isBlank()) return
        val updated = _chapters.value.toMutableList()
        if (index in updated.indices) {
            updated[index] = updated[index].copy(content = content)
            _chapters.value = updated
        }
        chapterContentCache[index] = content
    }

    private fun updatePlaybackSegment(segment: PlaybackSegment?) {
        if (segment == null) return
        val data = playbackChapterData[segment.chapterIndex]
        if (data != null) {
            _currentChapterContent.value = data.content
            currentParagraphs = data.paragraphs
            currentSentences = data.paragraphs
            _totalParagraphs.value = data.paragraphs.size.coerceAtLeast(1)
        }
        _currentChapterIndex.value = segment.chapterIndex
        _currentParagraphIndex.value = segment.paragraphIndex
        isReadingChapterTitle = segment.isChapterTitle
    }

    private fun clearPlaybackQueue() {
        playbackSegments = emptyList()
        playbackChapterData = emptyMap()
        _preloadedParagraphs.value = emptySet()
        _preloadedChapters.value = emptySet()
    }

    private fun applyBooksFilterAndSort() {
        val filtered = if (currentSearchQuery.isBlank()) {
            allBooks
        } else {
            val lower = currentSearchQuery.lowercase()
            allBooks.filter {
                it.name.orEmpty().lowercase().contains(lower) ||
                it.author.orEmpty().lowercase().contains(lower)
            }
        }

        val sorted = if (_bookshelfSortByRecent.value) {
            filtered.mapIndexed { index, book -> index to book }
                .sortedWith { first, second ->
                    val time1 = first.second.durChapterTime ?: 0L
                    val time2 = second.second.durChapterTime ?: 0L
                    when {
                        time1 == 0L && time2 == 0L -> first.first.compareTo(second.first)
                        time1 == 0L -> 1
                        time2 == 0L -> -1
                        time1 == time2 -> first.first.compareTo(second.first)
                        else -> if (time1 > time2) -1 else 1
                    }
                }
                .map { it.second }
        } else {
            filtered
        }

        _books.value = sorted
    }

    private fun isPunctuationOnly(sentence: String): Boolean {
        return sentence.trim().all { it in "，。！？；、“”\"'…—-· " }
    }

    private fun parseSpeakerMapping(raw: String): Map<String, String> {
        if (raw.isBlank()) return emptyMap()
        return runCatching {
            val obj = JSONObject(raw)
            obj.keys().asSequence().associateWith { key -> obj.optString(key) }
        }.getOrDefault(emptyMap())
    }

    private fun serializeSpeakerMapping(mapping: Map<String, String>): String {
        val obj = JSONObject()
        mapping.forEach { (key, value) -> obj.put(key, value) }
        return obj.toString()
    }

    fun exportLogs(context: android.content.Context): android.net.Uri? {
        if (!logFile.exists()) return null
        return runCatching {
            val exportFile = File(context.cacheDir, LOG_EXPORT_NAME)
            logFile.copyTo(exportFile, overwrite = true)
            androidx.core.content.FileProvider.getUriForFile(
                context,
                "${context.packageName}.fileprovider",
                exportFile
            )
        }.getOrNull()
    }

    fun clearLogs() {
        runCatching {
            if (logFile.exists()) {
                logFile.writeText("")
            }
        }
    }

    private fun appendLog(message: String) {
        if (!_loggingEnabled.value) return
        val timestamp = SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.getDefault()).format(Date())
        val line = "[$timestamp] $message\n"
        runCatching {
            logFile.appendText(line)
        }
    }


    // ==================== 清理 ====================

    override fun onCleared() {
        super.onCleared()
        player.release()
    }

}
