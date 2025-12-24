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
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.firstOrNull
import kotlinx.coroutines.launch
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class BookViewModel(application: Application) : AndroidViewModel(application) {

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

    private val preferences = UserPreferences(application)
    private val repository = ReadRepository { endpoint ->
        ReadApiService.create(endpoint) { accessToken.value }
    }
    private val player: ExoPlayer = ExoPlayer.Builder(application).build().apply {
        addListener(object : Player.Listener {
            override fun onIsPlayingChanged(isPlaying: Boolean) {
                _isPlaying.value = isPlaying
            }

            override fun onPlaybackStateChanged(playbackState: Int) {
                if (playbackState == Player.STATE_ENDED) {
                    _playbackProgress.value = 1f
                    // 播放完成后自动播放下一段
                    nextParagraph()
                }
            }
        })
    }

    // ==================== 书籍相关状态 ====================

    private var allBooks: List<Book> = emptyList()
    private val chapterContentCache = mutableMapOf<Int, String>()
    private val logFile = File(application.filesDir, LOG_FILE_NAME)

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

    // ==================== TTS 播放状态 ====================

    private val _isPlaying = MutableStateFlow(false)
    val isPlaying: StateFlow<Boolean> = _isPlaying.asStateFlow()

    private val _currentTime = MutableStateFlow("00:00")
    val currentTime: StateFlow<String> = _currentTime.asStateFlow()

    private val _totalTime = MutableStateFlow("00:00")
    val totalTime: StateFlow<String> = _totalTime.asStateFlow()

    private val _playbackProgress = MutableStateFlow(0f)
    val playbackProgress: StateFlow<Float> = _playbackProgress.asStateFlow()

    // ==================== TTS 设置 ====================

    private val _selectedTtsEngine = MutableStateFlow("")
    val selectedTtsEngine: StateFlow<String> = _selectedTtsEngine.asStateFlow()

    private val _availableTtsEngines = MutableStateFlow<List<HttpTTS>>(emptyList())
    val availableTtsEngines: StateFlow<List<HttpTTS>> = _availableTtsEngines.asStateFlow()

    private val _speechSpeed = MutableStateFlow(20)
    val speechSpeed: StateFlow<Int> = _speechSpeed.asStateFlow()

    private val _preloadCount = MutableStateFlow(3)
    val preloadCount: StateFlow<Int> = _preloadCount.asStateFlow()

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
            _speechSpeed.value = (preferences.speechRate.first() * 20).toInt()
            _preloadCount.value = preferences.preloadCount.first().toInt()

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
            chapterContentCache.clear()
            stopPlayback()
            _availableTtsEngines.value = emptyList()
            _selectedTtsEngine.value = ""
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
            _books.value = list
        }.onFailure { error ->
            _errorMessage.value = error.message
        }

        if (showLoading) {
            _isLoading.value = false
        }
    }

    fun searchBooks(query: String) {
        _books.value = if (query.isBlank()) {
            allBooks
        } else {
            val lower = query.lowercase()
            allBooks.filter {
                it.name.orEmpty().lowercase().contains(lower) ||
                it.author.orEmpty().lowercase().contains(lower)
            }
        }
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

        _currentChapterIndex.value = index
        val cachedContent = chapterContentCache[index]
        _currentChapterContent.value = cachedContent.orEmpty()
        currentParagraphs = cachedContent?.let { parseParagraphs(it) } ?: emptyList()
        _totalParagraphs.value = currentParagraphs.size.coerceAtLeast(1)
        _currentParagraphIndex.value = -1
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
        appendLog("加载章节列表: bookUrl=$bookUrl")
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
            Log.d(TAG, "加载章节列表成功: ${chapterList.size} 章")

            if (chapterList.isNotEmpty()) {
                val index = _currentChapterIndex.value.coerceIn(0, chapterList.lastIndex)
                _currentChapterIndex.value = index
                val inlineContent = chapterList.getOrNull(index)?.content.orEmpty()
                if (inlineContent.isNotBlank()) {
                    updateChapterContent(index, cleanChapterContent(inlineContent))
                }
                loadChapterContent(index)
            }
        }.onFailure { error ->
            _errorMessage.value = error.message
            appendLog("章节列表加载失败: ${error.message.orEmpty()}")
            Log.e(TAG, "加载章节列表失败", error)
            _isContentLoading.value = false
        }
    }

    fun loadChapterContent(index: Int) {
        viewModelScope.launch {
            loadChapterContentInternal(index)
        }
    }

    fun onChapterChange(index: Int) {
        setCurrentChapter(index)
    }

    private suspend fun loadChapterContentInternal(index: Int): String? {
        val book = _selectedBook.value ?: return null
        val chapter = _chapters.value.getOrNull(index) ?: return null
        val bookUrl = book.bookUrl ?: return null

        if (_isContentLoading.value) return _currentChapterContent.value.ifBlank { null }

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
        _currentChapterContent.value = ""
        appendLog("开始加载章节内容: index=$index url=${chapter.url}")
        Log.d(TAG, "开始加载章节内容: 第${index + 1}章")

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
                val cleaned = cleanChapterContent(content.orEmpty())
                val resolved = when {
                    cleaned.isNotBlank() -> cleaned
                    content.orEmpty().isNotBlank() -> content.orEmpty().trim()
                    else -> "章节内容为空"
                }
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

        _totalParagraphs.value = currentParagraphs.size.coerceAtLeast(1)

        Log.d(TAG, "章节内容加载成功: ${currentParagraphs.size} 个段落")
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

            // 播放当前段落
            playCurrentParagraph()

            // 预加载后续段落
            preloadNextParagraphs()

            // 开始观察播放进度
            observeProgress()
        }
    }

    private fun pausePlayback() {
        player.playWhenReady = false
    }

    private fun stopPlayback() {
        player.stop()
        _isPlaying.value = false
        _currentParagraphIndex.value = -1
        _preloadedParagraphs.value = emptySet()
        resetPlayback()
    }

    fun previousParagraph() {
        val currentIndex = _currentParagraphIndex.value
        if (currentIndex > 0) {
            _currentParagraphIndex.value = currentIndex - 1
            playCurrentParagraph()
        } else if (_currentChapterIndex.value > 0) {
            // 跳到上一章的最后一段
            previousChapter()
        }
    }

    fun nextParagraph() {
        val currentIndex = _currentParagraphIndex.value
        if (currentIndex < currentParagraphs.size - 1) {
            _currentParagraphIndex.value = currentIndex + 1
            playCurrentParagraph()
            preloadNextParagraphs()
        } else {
            // 切换到下一章
            if (_currentChapterIndex.value < _chapters.value.lastIndex) {
                nextChapter()
                viewModelScope.launch {
                    delay(500) // 等待章节加载
                    if (currentParagraphs.isNotEmpty()) {
                        _currentParagraphIndex.value = 0
                        playCurrentParagraph()
                        preloadNextParagraphs()
                    }
                }
            } else {
                // 已经是最后一章，停止播放
                stopPlayback()
            }
        }
    }

    private fun playCurrentParagraph() {
        val index = _currentParagraphIndex.value
        if (index < 0 || index >= currentParagraphs.size) return

        val paragraph = currentParagraphs[index]
        Log.d(TAG, "播放段落 $index: ${paragraph.take(20)}...")

        val ttsId = _selectedTtsEngine.value.ifBlank {
            _availableTtsEngines.value.firstOrNull()?.id
        }

        val audioUrl = ttsId?.let {
            repository.buildTtsAudioUrl(
            currentServerEndpoint(),
            _accessToken.value,
            it,
            paragraph,
            _speechSpeed.value / 20.0
            )
        }

        if (audioUrl.isNullOrBlank()) {
            _errorMessage.value = "无法获取TTS音频地址"
            nextParagraph() // 尝试下一段
            return
        }

        player.setMediaItem(MediaItem.fromUri(audioUrl))
        player.prepare()
        player.play()
    }

    private fun preloadNextParagraphs() {
        val currentIndex = _currentParagraphIndex.value
        val count = _preloadCount.value

        viewModelScope.launch {
            val preloaded = mutableSetOf<Int>()

            for (i in 1..count) {
                val nextIndex = currentIndex + i
                if (nextIndex < currentParagraphs.size) {
                    // TODO: 实现音频预加载逻辑
                    preloaded.add(nextIndex)
                    Log.d(TAG, "预加载段落 $nextIndex")
                }
            }

            _preloadedParagraphs.value = preloaded
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
            Log.d(TAG, "加载TTS引擎成功: ${list.size} 个")
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

    fun clearCache() {
        // TODO: 实现缓存清理逻辑
        Log.d(TAG, "清除缓存")
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

    private fun appendLog(message: String) {
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
        Log.d(TAG, "ViewModel cleared")
    }

}
