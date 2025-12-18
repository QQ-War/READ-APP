package com.readapp.viewmodel

import android.app.Application
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
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
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.firstOrNull
import kotlinx.coroutines.launch
import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.readapp.data.model.Book
import com.readapp.data.model.Chapter
import com.readapp.data.repository.BookRepository
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

class BookViewModel(application: Application) : AndroidViewModel(application) {
    private val preferences = UserPreferences(application)
    private val repository = ReadRepository { endpoint ->
        ReadApiService.create(endpoint) { accessToken }
    }
    private val player: ExoPlayer = ExoPlayer.Builder(application).build().apply {
        addListener(object : Player.Listener {
            override fun onIsPlayingChanged(isPlaying: Boolean) {
                this@BookViewModel.isPlaying = isPlaying
            }

            override fun onPlaybackStateChanged(playbackState: Int) {
                if (playbackState == Player.STATE_ENDED) {
                    playbackProgress = 1f
                }
            }
        })
    }

    private var allBooks: List<Book> = emptyList()

    var books by mutableStateOf<List<Book>>(emptyList())
        private set

    var selectedBook by mutableStateOf<Book?>(null)
        private set

    var chapters by mutableStateOf<List<Chapter>>(emptyList())
        private set

    var currentChapterIndex by mutableStateOf(0)
        private set

    var currentChapterContent by mutableStateOf("")
        private set

    var currentParagraph by mutableStateOf(1)
        private set

    var totalParagraphs by mutableStateOf(1)
        private set

    var currentTime by mutableStateOf("00:00")
        private set

    var totalTime by mutableStateOf("00:00")
        private set

    var playbackProgress by mutableStateOf(0f)
        private set

    var isPlaying by mutableStateOf(false)
        private set

    var serverAddress by mutableStateOf("http://127.0.0.1:8080/api/5")
        private set

    var publicServerAddress by mutableStateOf("")
        private set

    var accessToken by mutableStateOf("")
        private set

    var username by mutableStateOf("")
        private set

    var selectedTtsEngine by mutableStateOf("")
        private set

    var availableTtsEngines by mutableStateOf<List<HttpTTS>>(emptyList())
        private set

    var speechSpeed by mutableStateOf(20)
        private set

    var preloadCount by mutableStateOf(3)
        private set

    var errorMessage by mutableStateOf<String?>(null)
        private set

    var isLoading by mutableStateOf(false)
        private set

    var isContentLoading by mutableStateOf(false)
        private set

    val currentChapterTitle: String
        get() = chapters.getOrNull(currentChapterIndex)?.title ?: ""

    init {
        viewModelScope.launch {
            serverAddress = preferences.serverUrl.first()
            publicServerAddress = preferences.publicServerUrl.first()
            accessToken = preferences.accessToken.first()
            username = preferences.username.first()
            selectedTtsEngine = preferences.selectedTtsId.firstOrNull().orEmpty()
            speechSpeed = (preferences.speechRate.first() * 20).toInt()
            preloadCount = preferences.preloadCount.first().toInt()
            if (accessToken.isNotBlank()) {
                loadTtsEngines()
                refreshBooks()
            }
        }
    }

    fun searchBooks(query: String) {
        books = if (query.isBlank()) {
            allBooks
        } else {
            val lower = query.lowercase()
            allBooks.filter {
                it.name.orEmpty().lowercase().contains(lower) || it.author.orEmpty().lowercase().contains(lower)
            }
        }
    }

    fun selectBook(book: Book) {
        selectedBook = book
        currentChapterIndex = book.durChapterIndex ?: 0
        currentChapterContent = ""
        resetPlayback()
        viewModelScope.launch { loadChapters(book) }
    }

    fun setCurrentChapter(index: Int) {
        if (index in chapters.indices) {
            currentChapterIndex = index
            currentChapterContent = ""
            resetPlayback()
            viewModelScope.launch {
                loadChapterContent(index)
            }
        }
    }

    fun togglePlayPause() {
        if (selectedBook == null) return
        if (!isPlaying) {
            viewModelScope.launch {
                val content = ensureCurrentChapterContent()
                if (content != null) {
                    prepareAndPlay(content)
                    observeProgress()
                }
            }
        } else {
            player.playWhenReady = false
        }
    }

    fun previousParagraph() {
        currentParagraph = (currentParagraph - 1).coerceAtLeast(1)
    }

    fun nextParagraph() {
        currentParagraph = (currentParagraph + 1).coerceAtMost(totalParagraphs)
    }

    fun previousChapter() {
        if (currentChapterIndex > 0) {
            setCurrentChapter(currentChapterIndex - 1)
        }
    }

    fun nextChapter() {
        if (currentChapterIndex < chapters.lastIndex) {
            setCurrentChapter(currentChapterIndex + 1)
        }
    }

    fun updateServerAddress(address: String) {
        serverAddress = address
        viewModelScope.launch { preferences.saveServerUrl(address) }
    }

    fun updateSpeechSpeed(speed: Int) {
        speechSpeed = speed.coerceIn(5, 50)
        viewModelScope.launch { preferences.saveSpeechRate(speechSpeed / 20.0) }
    }

    fun updatePreloadCount(count: Int) {
        preloadCount = count.coerceIn(1, 10)
        viewModelScope.launch { preferences.savePreloadCount(preloadCount.toFloat()) }
    }

    fun clearCache() {
        // Placeholder for cache clearing
    }

    fun logout() {
        viewModelScope.launch {
            preferences.saveAccessToken("")
        }
        accessToken = ""
        username = ""
        books = emptyList()
        selectedBook = null
        chapters = emptyList()
        currentChapterIndex = 0
        currentChapterContent = ""
        isPlaying = false
        isContentLoading = false
    }

    fun currentServerEndpoint(): String = if (serverAddress.endsWith("/api/5")) serverAddress else "$serverAddress/api/5"

    fun login(server: String, username: String, password: String, onSuccess: () -> Unit) {
        viewModelScope.launch {
            isLoading = true
            errorMessage = null
            val normalized = if (server.contains("/api/")) server else "$server/api/5"
            val result = repository.login(normalized, publicServerAddress.ifBlank { null }, username, password)
            result.onFailure { error ->
                errorMessage = error.message
            }

            val loginData = result.getOrNull()
            if (loginData != null) {
                accessToken = loginData.accessToken
                this@BookViewModel.username = username
                preferences.saveAccessToken(loginData.accessToken)
                preferences.saveUsername(username)
                preferences.saveServerUrl(normalized)
                loadTtsEngines()
                refreshBooks()
                onSuccess()
            }
            isLoading = false
        }
    }

    fun refreshBooks() {
        if (accessToken.isBlank()) return
        viewModelScope.launch {
            isLoading = true
            val booksResult = repository.fetchBooks(currentServerEndpoint(), publicServerAddress.ifBlank { null }, accessToken)
            booksResult.onSuccess { list ->
                allBooks = list
                books = list
            }.onFailure { error ->
                errorMessage = error.message
            }
            isLoading = false
        }
    }

    fun loadCurrentChapterContent() {
        viewModelScope.launch {
            if (currentChapterContent.isBlank()) {
                currentChapterContent = ""
            }
            loadChapterContent(currentChapterIndex)
        }
    }

    private fun prepareAndPlay(text: String) {
        val ttsId = selectedTtsEngine.ifBlank { availableTtsEngines.firstOrNull()?.id }
        val audioUrl = ttsId?.let {
            repository.buildTtsAudioUrl(currentServerEndpoint(), accessToken, it, text, speechSpeed / 20.0)
        }
        if (audioUrl.isNullOrBlank()) {
            errorMessage = "无法获取TTS音频地址"
            return
        }

        player.setMediaItem(MediaItem.fromUri(audioUrl))
        player.prepare()
        player.play()
        isPlaying = true
    }

    private fun observeProgress() {
        viewModelScope.launch {
            while (isPlaying) {
                val duration = player.duration.takeIf { it > 0 } ?: 1L
                val position = player.currentPosition
                playbackProgress = (position.toFloat() / duration).coerceIn(0f, 1f)
                totalTime = formatTime(duration)
                currentTime = formatTime(position)
                delay(500)
            }
        }
    }

    private fun formatTime(millis: Long): String {
        val totalSeconds = millis / 1000
        val minutes = totalSeconds / 60
        val seconds = totalSeconds % 60
        return String.format("%02d:%02d", minutes, seconds)
    }

    private fun loadTtsEngines() {
        if (accessToken.isBlank()) return
        viewModelScope.launch {
            val enginesResult = repository.fetchTtsEngines(currentServerEndpoint(), publicServerAddress.ifBlank { null }, accessToken)
            enginesResult.onSuccess {
                availableTtsEngines = it
            }

            val defaultResult = repository.fetchDefaultTts(currentServerEndpoint(), publicServerAddress.ifBlank { null }, accessToken)
            val defaultId = defaultResult.getOrNull()
            if (defaultId != null) {
                selectedTtsEngine = defaultId
                preferences.saveSelectedTtsId(defaultId)
            }
        }
    }

    private suspend fun loadChapters(book: Book) {
        val bookUrl = book.bookUrl ?: return
        val chaptersResult = repository.fetchChapterList(currentServerEndpoint(), publicServerAddress.ifBlank { null }, accessToken, bookUrl, book.origin)
        chaptersResult.onSuccess {
            chapters = it
            totalParagraphs = chapters.size.coerceAtLeast(1)
            if (chapters.isNotEmpty()) {
                currentChapterIndex = currentChapterIndex.coerceIn(0, chapters.lastIndex)
                loadChapterContent(currentChapterIndex)
            }
        }.onFailure { error ->
            errorMessage = error.message
        }
    }

    private suspend fun ensureCurrentChapterContent(): String? {
        if (currentChapterContent.isNotBlank()) return currentChapterContent
        return loadChapterContent(currentChapterIndex)
    }

    private suspend fun loadChapterContent(index: Int): String? {
        val book = selectedBook ?: return null
        val bookUrl = book.bookUrl ?: return null
        if (index !in chapters.indices) return null

        val cached = chapters.getOrNull(index)?.content
        val content = if (!cached.isNullOrBlank()) {
            currentChapterContent = cached
            totalParagraphs = cached.split("\n\n", "\n").count { it.isNotBlank() }.coerceAtLeast(1)
            cached
        } else {
            if (isContentLoading && currentChapterContent.isNotBlank()) {
                return currentChapterContent
            }

            isContentLoading = true
            val contentResult = repository.fetchChapterContent(
                currentServerEndpoint(),
                publicServerAddress.ifBlank { null },
                accessToken,
                bookUrl,
                book.origin,
                index
            )

            contentResult.getOrElse {
                errorMessage = it.message
                ""
            }
        }

        if (content.isNotBlank()) {
            val updatedChapters = chapters.toMutableList()
            updatedChapters[index] = updatedChapters[index].copy(content = content)
            chapters = updatedChapters
            currentChapterContent = content
            totalParagraphs = content.split("\n\n", "\n").count { it.isNotBlank() }.coerceAtLeast(1)
        }

        isContentLoading = false
        return content.ifBlank { null }
    }

    private fun resetPlayback() {
        currentParagraph = 1
        playbackProgress = 0f
        currentTime = "00:00"
        totalTime = "00:00"
        isPlaying = false
    }

    override fun onCleared() {
        super.onCleared()
        player.release()
    }

    companion object {
        val Factory: ViewModelProvider.Factory = viewModelFactory {
            initializer {
                val application = (this[ViewModelProvider.AndroidViewModelFactory.APPLICATION_KEY] as Application)
                BookViewModel(application)
            }
        }
    }
    companion object {
        private const val TAG = "BookViewModel"
    }
    
    // ==================== 书籍相关状态 ====================
    
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
    
    // ==================== TTS 相关状态 ====================
    
    private val _isPlaying = MutableStateFlow(false)
    val isPlaying: StateFlow<Boolean> = _isPlaying.asStateFlow()
    
    private val _currentParagraphIndex = MutableStateFlow(-1)  // -1 表示未开始播放
    val currentParagraphIndex: StateFlow<Int> = _currentParagraphIndex.asStateFlow()
    
    private val _preloadedParagraphs = MutableStateFlow<Set<Int>>(emptySet())
    val preloadedParagraphs: StateFlow<Set<Int>> = _preloadedParagraphs.asStateFlow()
    
    // TTS 设置
    private val _selectedTtsEngine = MutableStateFlow("")
    val selectedTtsEngine: StateFlow<String> = _selectedTtsEngine.asStateFlow()
    
    private val _speechSpeed = MutableStateFlow(15)
    val speechSpeed: StateFlow<Int> = _speechSpeed.asStateFlow()
    
    private val _preloadCount = MutableStateFlow(3)
    val preloadCount: StateFlow<Int> = _preloadCount.asStateFlow()
    
    // 服务器设置
    private val _serverAddress = MutableStateFlow("")
    val serverAddress: StateFlow<String> = _serverAddress.asStateFlow()
    
    // ==================== 当前段落列表 ====================
    
    private var currentParagraphs: List<String> = emptyList()
    
    // ==================== 书籍操作方法 ====================
    
    /**
     * 选择书籍
     */
    fun selectBook(book: Book) {
        _selectedBook.value = book
        loadChapters(book.id)
        // 加载第一章内容
        loadChapterContent(0)
    }
    
    /**
     * 加载章节列表
     */
    private fun loadChapters(bookId: String) {
        viewModelScope.launch {
            try {
                val chapterList = bookRepository.getChapterList(bookId)
                _chapters.value = chapterList
                Log.d(TAG, "加载章节列表成功: ${chapterList.size} 章")
            } catch (e: Exception) {
                Log.e(TAG, "加载章节列表失败", e)
                _chapters.value = emptyList()
            }
        }
    }
    
    /**
     * 设置当前章节
     */
    fun setCurrentChapter(index: Int) {
        if (index < 0 || index >= _chapters.value.size) {
            return
        }
        
        _currentChapterIndex.value = index
        loadChapterContent(index)
        
        // 如果正在播放，停止当前播放
        if (_isPlaying.value) {
            stopTts()
        }
    }
    
    /**
     * 加载章节内容
     */
    fun loadChapterContent(index: Int) {
        viewModelScope.launch {
            try {
                val book = _selectedBook.value ?: return@launch
                
                Log.d(TAG, "开始加载章节内容: 第${index + 1}章")
                
                val content = bookRepository.getChapterContent(
                    bookId = book.id,
                    chapterIndex = index
                )
                
                _currentChapterContent.value = content
                
                // 分割段落
                currentParagraphs = content
                    .split("\n")
                    .map { it.trim() }
                    .filter { it.isNotEmpty() }
                
                Log.d(TAG, "章节内容加载成功: ${currentParagraphs.size} 个段落")
                
            } catch (e: Exception) {
                Log.e(TAG, "加载章节内容失败", e)
                _currentChapterContent.value = "加载失败：${e.message}"
            }
        }
    }
    
    /**
     * 搜索书籍
     */
    fun searchBooks(query: String) {
        viewModelScope.launch {
            try {
                val allBooks = bookRepository.getAllBooks()
                _books.value = if (query.isEmpty()) {
                    allBooks
                } else {
                    allBooks.filter { 
                        it.title.contains(query, ignoreCase = true) ||
                        it.author.contains(query, ignoreCase = true)
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "搜索书籍失败", e)
            }
        }
    }
    
    // ==================== TTS 控制方法 ====================
    
    /**
     * 开始听书
     */
    fun startTts() {
        if (currentParagraphs.isEmpty()) {
            Log.w(TAG, "没有可播放的内容")
            return
        }
        
        Log.d(TAG, "开始听书")
        
        // 从第一段开始播放
        _currentParagraphIndex.value = 0
        _isPlaying.value = true
        
        // 开始播放当前段落
        playCurrentParagraph()
        
        // 预加载后续段落
        preloadNextParagraphs()
    }
    
    /**
     * 停止听书
     */
    fun stopTts() {
        Log.d(TAG, "停止听书")
        
        _isPlaying.value = false
        _currentParagraphIndex.value = -1
        _preloadedParagraphs.value = emptySet()
        
        // TODO: 停止音频播放
        // ttsManager.stop()
    }
    
    /**
     * 播放/暂停切换
     */
    fun togglePlayPause() {
        if (_isPlaying.value) {
            // 暂停
            _isPlaying.value = false
            // TODO: 暂停音频
            // ttsManager.pause()
        } else {
            // 继续播放
            _isPlaying.value = true
            // TODO: 继续播放
            // ttsManager.resume()
        }
    }
    
    /**
     * 上一段
     */
    fun previousParagraph() {
        val currentIndex = _currentParagraphIndex.value
        if (currentIndex > 0) {
            _currentParagraphIndex.value = currentIndex - 1
            playCurrentParagraph()
        }
    }
    
    /**
     * 下一段
     */
    fun nextParagraph() {
        val currentIndex = _currentParagraphIndex.value
        if (currentIndex < currentParagraphs.size - 1) {
            _currentParagraphIndex.value = currentIndex + 1
            playCurrentParagraph()
            
            // 预加载后续段落
            preloadNextParagraphs()
        } else {
            // 已经是最后一段，切换到下一章
            if (_currentChapterIndex.value < _chapters.value.size - 1) {
                setCurrentChapter(_currentChapterIndex.value + 1)
                startTts()
            } else {
                // 已经是最后一章，停止播放
                stopTts()
            }
        }
    }
    
    /**
     * 播放当前段落
     */
    private fun playCurrentParagraph() {
        val index = _currentParagraphIndex.value
        if (index < 0 || index >= currentParagraphs.size) {
            return
        }
        
        val paragraph = currentParagraphs[index]
        
        Log.d(TAG, "播放段落 $index: ${paragraph.take(20)}...")
        
        // TODO: 调用 TTS API 播放
        viewModelScope.launch {
            try {
                // val audioUrl = bookRepository.getTtsAudio(
                //     ttsId = _selectedTtsEngine.value,
                //     text = paragraph,
                //     speed = _speechSpeed.value
                // )
                // ttsManager.play(audioUrl)
                
                // 播放完成后自动播放下一段
                // nextParagraph()
                
            } catch (e: Exception) {
                Log.e(TAG, "播放段落失败", e)
                // 失败时跳到下一段
                nextParagraph()
            }
        }
    }
    
    /**
     * 预加载后续段落
     */
    private fun preloadNextParagraphs() {
        val currentIndex = _currentParagraphIndex.value
        val count = _preloadCount.value
        
        viewModelScope.launch {
            val preloaded = mutableSetOf<Int>()
            
            for (i in 1..count) {
                val nextIndex = currentIndex + i
                if (nextIndex < currentParagraphs.size) {
                    try {
                        val paragraph = currentParagraphs[nextIndex]
                        
                        // TODO: 预加载音频
                        // val audioUrl = bookRepository.getTtsAudio(
                        //     ttsId = _selectedTtsEngine.value,
                        //     text = paragraph,
                        //     speed = _speechSpeed.value
                        // )
                        // ttsManager.preload(audioUrl)
                        
                        preloaded.add(nextIndex)
                        Log.d(TAG, "预加载段落 $nextIndex 成功")
                        
                    } catch (e: Exception) {
                        Log.e(TAG, "预加载段落 $nextIndex 失败", e)
                    }
                }
            }
            
            _preloadedParagraphs.value = preloaded
        }
    }
    
    // ==================== 设置方法 ====================
    
    fun updateServerAddress(address: String) {
        _serverAddress.value = address
        // TODO: 保存到 SharedPreferences
    }
    
    fun updateSpeechSpeed(speed: Int) {
        _speechSpeed.value = speed
        // TODO: 保存到 SharedPreferences
    }
    
    fun updatePreloadCount(count: Int) {
        _preloadCount.value = count
        // TODO: 保存到 SharedPreferences
    }
    
    fun clearCache() {
        viewModelScope.launch {
            try {
                bookRepository.clearCache()
                Log.d(TAG, "清除缓存成功")
            } catch (e: Exception) {
                Log.e(TAG, "清除缓存失败", e)
            }
        }
    }
    
    fun logout() {
        // TODO: 清除登录信息
        _books.value = emptyList()
        _selectedBook.value = null
        _chapters.value = emptyList()
        stopTts()
    }
}
