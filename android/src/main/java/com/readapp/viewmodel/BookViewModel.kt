package com.readapp.viewmodel

import android.app.Application
import android.net.Uri
import android.util.Log
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import android.content.ComponentName
import androidx.media3.session.MediaController
import androidx.media3.session.SessionToken
import com.google.common.util.concurrent.MoreExecutors
import com.readapp.data.ReadApiService
import com.readapp.data.ReaderApiService
import com.readapp.data.ReadRepository
import com.readapp.data.UserPreferences
import com.readapp.data.LocalCacheManager
import com.readapp.data.LocalSourceCache
import com.readapp.data.ChapterContentRepository
import com.readapp.data.ApiBackend
import com.readapp.data.detectApiBackend
import com.readapp.data.normalizeApiBaseUrl
import com.readapp.data.stripApiBasePath
import com.readapp.data.RemoteDataSourceFactory
import com.readapp.data.manga.MangaAntiScrapingService
import com.readapp.data.manga.MangaImageExtractor
import com.readapp.data.manga.MangaImageNormalizer
import com.readapp.data.repo.AuthRepository
import com.readapp.data.repo.BookRepository
import com.readapp.data.repo.ReplaceRuleRepository
import com.readapp.data.repo.SourceRepository
import com.readapp.data.repo.TtsRepository
import com.readapp.media.ReadAudioService
import com.readapp.data.model.Book
import com.readapp.data.model.Chapter
import com.readapp.data.model.HttpTTS
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

import com.readapp.data.model.ReplaceRule
import com.readapp.data.model.TtsAudioRequest
import com.readapp.ui.state.ReaderUiState
import android.speech.tts.Voice
import android.widget.Toast
import android.os.SystemClock

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

    // ==================== Dependencies & Player Management ====================

    internal val appContext = getApplication<Application>()
    val preferences = UserPreferences(appContext)
    private val readerSettings = ReaderSettingsStore(preferences, viewModelScope)
    private val localCache = LocalCacheManager(appContext)
    private val localSourceCache = LocalSourceCache(appContext)
    private val apiFactory: (String) -> ReadApiService = { endpoint ->
        ReadApiService.create(endpoint) { accessToken.value }
    }
    private val readerApiFactory: (String) -> ReaderApiService = { endpoint ->
        ReaderApiService.create(endpoint) { accessToken.value }
    }
    internal val remoteDataSourceFactory = RemoteDataSourceFactory(apiFactory, readerApiFactory)
    val repository = ReadRepository(apiFactory, readerApiFactory)
    internal val authRepository = AuthRepository(remoteDataSourceFactory)
    internal val bookRepository = BookRepository(remoteDataSourceFactory, repository)
    private val sourceRepository = SourceRepository(repository, localSourceCache)
    private val ttsRepository = TtsRepository(remoteDataSourceFactory, repository)
    private val replaceRuleRepository = ReplaceRuleRepository(remoteDataSourceFactory, repository)
    internal val chapterContentRepository = ChapterContentRepository(repository, localCache)
    private val ttsController = TtsController(this)
    private val ttsSyncCoordinator by lazy { TtsSyncCoordinator(this) }
    private val readerInteractor = ReaderInteractor(this)


    // ==================== 涔︾睄鐩稿叧鐘舵€?====================

    internal var currentSentences: List<String> = emptyList()
    internal var currentParagraphs: List<String> = emptyList()
    internal var isReadingChapterTitle = false
    private var currentSearchQuery = ""
    private var allBooks: List<Book> = emptyList()
    private val logFile = File(appContext.filesDir, LOG_FILE_NAME)

    

    // ==================== TTS 鎾斁鐘舵€?====================

    internal val _isPlaying = MutableStateFlow(false)
    val isPlaying: StateFlow<Boolean> = _isPlaying.asStateFlow()
    internal val _keepPlaying = MutableStateFlow(false)
    val isPlayingUi: StateFlow<Boolean> = combine(_isPlaying, _keepPlaying) { playing, keep ->
        playing || keep
    }.stateIn(viewModelScope, SharingStarted.Eagerly, false)
    internal val _isPaused = MutableStateFlow(false)
    val isPaused: StateFlow<Boolean> = _isPaused.asStateFlow()
    internal val _showTtsControls = MutableStateFlow(false)
    val showTtsControls: StateFlow<Boolean> = _showTtsControls.asStateFlow()

    internal val _currentTime = MutableStateFlow("00:00")
    val currentTime: StateFlow<String> = _currentTime.asStateFlow()

    internal val _totalTime = MutableStateFlow("00:00")
    val totalTime: StateFlow<String> = _totalTime.asStateFlow()

    internal val _playbackProgress = MutableStateFlow(0f)
    val playbackProgress: StateFlow<Float> = _playbackProgress.asStateFlow()

    // ==================== 鍑€鍖栬鍒欑姸鎬?====================

    private val _replaceRules = MutableStateFlow<List<ReplaceRule>>(emptyList())
    val replaceRules: StateFlow<List<ReplaceRule>> = _replaceRules.asStateFlow()

    // ==================== TTS 璁剧疆 & 鍏朵粬 ====================
    // (No changes in this section, keeping it compact)
    internal val _selectedTtsEngine = MutableStateFlow("")
    val selectedTtsEngine: StateFlow<String> = _selectedTtsEngine.asStateFlow()
    internal val _useSystemTts = MutableStateFlow(false)
    val useSystemTts: StateFlow<Boolean> = _useSystemTts.asStateFlow()
    internal val _systemVoiceId = MutableStateFlow("")
    val systemVoiceId: StateFlow<String> = _systemVoiceId.asStateFlow()
    private val _narrationTtsEngine = MutableStateFlow("")
    val narrationTtsEngine: StateFlow<String> = _narrationTtsEngine.asStateFlow()
    private val _dialogueTtsEngine = MutableStateFlow("")
    val dialogueTtsEngine: StateFlow<String> = _dialogueTtsEngine.asStateFlow()
    private val _speakerTtsMapping = MutableStateFlow<Map<String, String>>(emptyMap())
    val speakerTtsMapping: StateFlow<Map<String, String>> = _speakerTtsMapping.asStateFlow()
    private val _availableTtsEngines = MutableStateFlow<List<HttpTTS>>(emptyList())
    val availableTtsEngines: StateFlow<List<HttpTTS>> = _availableTtsEngines.asStateFlow()
    
    private val _availableBookSources = MutableStateFlow<List<com.readapp.data.model.BookSource>>(emptyList())
    val availableBookSources: StateFlow<List<com.readapp.data.model.BookSource>> = _availableBookSources.asStateFlow()

    internal val _availableSystemVoices = MutableStateFlow<List<Voice>>(emptyList())
    val availableSystemVoices: StateFlow<List<Voice>> = _availableSystemVoices.asStateFlow()

    internal val _speechSpeed = MutableStateFlow(20)
    val speechSpeed: StateFlow<Int> = _speechSpeed.asStateFlow()
    internal val _preloadCount = MutableStateFlow(3)
    val preloadCount: StateFlow<Int> = _preloadCount.asStateFlow()
    val readingFontSize: StateFlow<Float> = readerSettings.readingFontSize
    val readingFontPath: StateFlow<String> = readerSettings.readingFontPath
    val readingFontName: StateFlow<String> = readerSettings.readingFontName
    val readingHorizontalPadding: StateFlow<Float> = readerSettings.readingHorizontalPadding
    val infiniteScrollEnabled: StateFlow<Boolean> = readerSettings.infiniteScrollEnabled
    private val _loggingEnabled = MutableStateFlow(false)
    val loggingEnabled: StateFlow<Boolean> = _loggingEnabled.asStateFlow()
    private val _bookshelfSortByRecent = MutableStateFlow(false)
    val bookshelfSortByRecent: StateFlow<Boolean> = _bookshelfSortByRecent.asStateFlow()
    private val _searchSourcesFromBookshelf = MutableStateFlow(false)
    val searchSourcesFromBookshelf: StateFlow<Boolean> = _searchSourcesFromBookshelf.asStateFlow()
    private val _preferredSearchSourceUrls = MutableStateFlow<Set<String>>(emptySet())
    val preferredSearchSourceUrls: StateFlow<Set<String>> = _preferredSearchSourceUrls.asStateFlow()
    val manualMangaUrls: StateFlow<Set<String>> = readerSettings.manualMangaUrls
    val forceMangaProxy: StateFlow<Boolean> = readerSettings.forceMangaProxy
    val mangaSwitchThreshold: StateFlow<Int> = readerSettings.mangaSwitchThreshold
    val verticalDampingFactor: StateFlow<Float> = readerSettings.verticalDampingFactor
    val mangaMaxZoom: StateFlow<Float> = readerSettings.mangaMaxZoom

    val readingMode: StateFlow<com.readapp.data.ReadingMode> = readerSettings.readingMode
    val lockPageOnTTS: StateFlow<Boolean> = readerSettings.lockPageOnTTS
    val ttsFollowCooldownSeconds: StateFlow<Float> = readerSettings.ttsFollowCooldownSeconds
    val ttsSentenceChunkLimit: StateFlow<Int> = readerSettings.ttsSentenceChunkLimit
    val pageTurningMode: StateFlow<com.readapp.data.PageTurningMode> = readerSettings.pageTurningMode
    val darkMode: StateFlow<com.readapp.data.DarkModeConfig> = readerSettings.darkMode
    val readingTheme: StateFlow<com.readapp.data.ReaderTheme> = readerSettings.readingTheme
    private val _serverAddress = MutableStateFlow("http://127.0.0.1:8080")
    val serverAddress: StateFlow<String> = _serverAddress.asStateFlow()
    private val _apiBackend = MutableStateFlow(ApiBackend.Read)
    val apiBackend: StateFlow<ApiBackend> = _apiBackend.asStateFlow()
    internal val _publicServerAddress = MutableStateFlow("")
    val publicServerAddress: StateFlow<String> = _publicServerAddress.asStateFlow()
    internal val _accessToken = MutableStateFlow("")
    val accessToken: StateFlow<String> = _accessToken.asStateFlow()
    private val _username = MutableStateFlow("")
    val username: StateFlow<String> = _username.asStateFlow()
    internal val _errorMessage = MutableStateFlow<String?>(null)
    val errorMessage: StateFlow<String?> = _errorMessage.asStateFlow()
    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()
    private val _onlineSearchResults = MutableStateFlow<List<Book>>(emptyList())
    val onlineSearchResults: StateFlow<List<Book>> = _onlineSearchResults.asStateFlow()
    private val _isOnlineSearching = MutableStateFlow(false)
    val isOnlineSearching: StateFlow<Boolean> = _isOnlineSearching.asStateFlow()
    internal val _isChapterListLoading = MutableStateFlow(false)
    val isChapterListLoading: StateFlow<Boolean> = _isChapterListLoading.asStateFlow()
    internal val _isChapterContentLoading = MutableStateFlow(false)
    val isChapterContentLoading: StateFlow<Boolean> = _isChapterContentLoading.asStateFlow()
    private val readerState by lazy {
        ReaderStateReducer(
            scope = viewModelScope,
            errorMessage = errorMessage,
            isContentLoading = isChapterContentLoading,
            readingFontSize = readingFontSize,
            readingFontPath = readingFontPath,
            readingFontName = readingFontName,
            readingHorizontalPadding = readingHorizontalPadding,
            readingMode = readingMode,
            lockPageOnTTS = lockPageOnTTS,
            pageTurningMode = pageTurningMode,
            darkMode = darkMode,
            readingTheme = readingTheme,
            infiniteScrollEnabled = infiniteScrollEnabled,
            forceMangaProxy = forceMangaProxy,
            mangaSwitchThreshold = mangaSwitchThreshold,
            verticalDampingFactor = verticalDampingFactor,
            mangaMaxZoom = mangaMaxZoom,
            manualMangaUrls = manualMangaUrls,
            serverAddress = serverAddress,
            apiBackend = apiBackend
        )
    }

    internal val _books = readerState.books
    val books: StateFlow<List<Book>> = readerState.booksFlow

    internal val _selectedBook = readerState.selectedBook
    val selectedBook: StateFlow<Book?> = readerState.selectedBookFlow

    internal val _chapters = readerState.chapters
    val chapters: StateFlow<List<Chapter>> = readerState.chaptersFlow

    internal val _currentChapterIndex = readerState.currentChapterIndex
    val currentChapterIndex: StateFlow<Int> = readerState.currentChapterIndexFlow

    internal val _currentChapterContent = readerState.currentChapterContent
    val currentChapterContent: StateFlow<String> = readerState.currentChapterContentFlow

    val currentChapterTitle: String
        get() = _chapters.value.getOrNull(_currentChapterIndex.value)?.title ?: ""

    // ==================== 娈佃惤鐩稿叧鐘舵€?====================

    internal val _currentParagraphIndex = readerState.currentParagraphIndex
    val currentParagraphIndex: StateFlow<Int> = readerState.currentParagraphIndexFlow
    private val _firstVisibleParagraphIndex = readerState.firstVisibleParagraphIndex
    val firstVisibleParagraphIndex: StateFlow<Int> = readerState.firstVisibleParagraphIndexFlow
    private val _lastVisibleParagraphIndex = readerState.lastVisibleParagraphIndex
    val lastVisibleParagraphIndex: StateFlow<Int> = readerState.lastVisibleParagraphIndexFlow
    private val _pendingScrollIndex = readerState.pendingScrollIndex
    val pendingScrollIndex: StateFlow<Int?> = readerState.pendingScrollIndexFlow

    internal val _currentParagraphStartOffset = readerState.currentParagraphStartOffset
    val currentParagraphStartOffset: StateFlow<Int> = readerState.currentParagraphStartOffsetFlow

    internal val _totalParagraphs = readerState.totalParagraphs
    val totalParagraphs: StateFlow<Int> = readerState.totalParagraphsFlow

    internal val _preloadedParagraphs = readerState.preloadedParagraphs
    val preloadedParagraphs: StateFlow<Set<Int>> = readerState.preloadedParagraphsFlow
    internal val _preloadedChapters = readerState.preloadedChapters
    val preloadedChapters: StateFlow<Set<Int>> = readerState.preloadedChaptersFlow

    private var firstVisibleParagraphOffset: Int = 0
    private var currentPageStartParagraphIndex: Int = 0
    private var currentPageStartOffset: Int = 0
    private var currentPageEndParagraphIndex: Int = 0
    private var currentPageEndOffset: Int = 0
    private var isUserScrolling: Boolean = false
    private var ttsFollowSuppressedUntil: Long = 0L
    private var ttsFollowJob: Job? = null

    internal val _prevChapterIndex = readerState.prevChapterIndex
    val prevChapterIndex: StateFlow<Int?> = readerState.prevChapterIndexFlow
    internal val _nextChapterIndex = readerState.nextChapterIndex
    val nextChapterIndex: StateFlow<Int?> = readerState.nextChapterIndexFlow
    internal val _prevChapterContent = readerState.prevChapterContent
    val prevChapterContent: StateFlow<String?> = readerState.prevChapterContentFlow
    internal val _nextChapterContent = readerState.nextChapterContent
    val nextChapterContent: StateFlow<String?> = readerState.nextChapterContentFlow
    private val _isInitialized = MutableStateFlow(false)
    val isInitialized: StateFlow<Boolean> = _isInitialized.asStateFlow()

    val readerUiState: StateFlow<ReaderUiState> = readerState.readerUiState

    fun clearError() { _errorMessage.value = null }

    // ==================== 鍒濆鍖?====================

    init {
        viewModelScope.launch {
            // Load all preferences
            val storedServer = preferences.serverUrl.first()
            val storedPublic = preferences.publicServerUrl.first()
            val storedBackend = preferences.getApiBackendSetting()
            val detectedBackend = detectApiBackend(storedServer)
            val resolvedBackend = storedBackend ?: detectedBackend
            if (storedBackend == null) {
                preferences.saveApiBackend(resolvedBackend)
            }
            val normalizedServer = stripApiBasePath(storedServer)
            if (normalizedServer != storedServer) {
                preferences.saveServerUrl(normalizedServer)
            }
            val normalizedPublic = if (storedPublic.isBlank()) storedPublic else stripApiBasePath(storedPublic)
            if (normalizedPublic != storedPublic) {
                preferences.savePublicServerUrl(normalizedPublic)
            }
            _serverAddress.value = normalizedServer
            _publicServerAddress.value = normalizedPublic
            _apiBackend.value = resolvedBackend
            _accessToken.value = preferences.accessToken.first()
            _username.value = preferences.username.first()
            _selectedTtsEngine.value = preferences.selectedTtsId.firstOrNull().orEmpty()
            _useSystemTts.value = preferences.useSystemTts.first()
            _systemVoiceId.value = preferences.systemVoiceId.firstOrNull().orEmpty()
            _narrationTtsEngine.value = preferences.narrationTtsId.firstOrNull().orEmpty()
            _dialogueTtsEngine.value = preferences.dialogueTtsId.firstOrNull().orEmpty()
            _speakerTtsMapping.value = parseSpeakerMapping(preferences.speakerTtsMapping.firstOrNull().orEmpty())
            _speechSpeed.value = preferences.speechRate.first().toInt()
            _preloadCount.value = preferences.preloadCount.first().toInt()
            _loggingEnabled.value = preferences.loggingEnabled.first()
            _bookshelfSortByRecent.value = preferences.bookshelfSortByRecent.first()
            _searchSourcesFromBookshelf.value = preferences.searchSourcesFromBookshelf.first()
            val urls = preferences.preferredSearchSourceUrls.first()
            _preferredSearchSourceUrls.value = if (urls.isBlank()) emptySet() else urls.split(";").toSet()
            readerSettings.loadInitial()

            localCache.loadBookshelfCache()?.let { cached ->
                if (cached.isNotEmpty()) {
                    allBooks = cached
                    applyBooksFilterAndSort()
                }
            }

            if (_accessToken.value.isNotBlank()) {
                _isLoading.value = true
                try {
                    loadTtsEnginesInternal()
                    loadBookSources()
                    refreshBooksInternal(showLoading = true)
                    loadReplaceRules()
                } finally {
                    _isLoading.value = false
                }
            }
            _isInitialized.value = true
        }

        ttsController.initSystemTts()

        // Connect to MediaSession
        viewModelScope.launch {
            val sessionToken = SessionToken(appContext, ComponentName(appContext, ReadAudioService::class.java))
            val controllerFuture = MediaController.Builder(appContext, sessionToken).buildAsync()
            controllerFuture.addListener({
                ttsController.bindMediaController(controllerFuture.get())
            }, MoreExecutors.directExecutor())
        }
    }

    // ==================== 鍑€鍖栬鍒欑姸鎬?====================

    fun loadReplaceRules() {
        viewModelScope.launch {
            replaceRuleRepository.fetchReplaceRules(
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
            replaceRuleRepository.addReplaceRule(
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

    fun deleteReplaceRule(rule: ReplaceRule) {
        viewModelScope.launch {
            replaceRuleRepository.deleteReplaceRule(
                currentServerEndpoint(),
                _publicServerAddress.value.ifBlank { null },
                _accessToken.value,
                rule
            ).onSuccess {
                loadReplaceRules()
            }.onFailure {
                _errorMessage.value = "删除规则失败: ${it.message}"
            }
        }
    }

    fun toggleReplaceRule(rule: ReplaceRule, isEnabled: Boolean) {
        viewModelScope.launch {
            replaceRuleRepository.toggleReplaceRule(
                currentServerEndpoint(),
                _publicServerAddress.value.ifBlank { null },
                _accessToken.value,
                rule,
                isEnabled
            ).onSuccess {
                val updatedRules = _replaceRules.value.map { if (it.id == rule.id) it.copy(isEnabled = isEnabled) else it }
                _replaceRules.value = updatedRules
                loadReplaceRules()
            }.onFailure {
                _errorMessage.value = "切换规则状态失败: ${it.message}"
            }
        }
    }

    fun saveReplaceRules(jsonContent: String) {
        viewModelScope.launch {
            replaceRuleRepository.saveReplaceRules(
                currentServerEndpoint(),
                _publicServerAddress.value.ifBlank { null },
                _accessToken.value,
                jsonContent
            ).onSuccess {
                loadReplaceRules()
            }.onFailure {
                _errorMessage.value = "保存规则失败: ${it.message}"
            }
        }
    }

    fun previousParagraph() {
        ttsController.previousParagraph()
    }

    fun nextParagraph() {
        ttsController.nextParagraph()
    }

    fun startTts(startParagraphIndex: Int = -1, startOffsetInParagraph: Int = 0) {
        ttsController.startTts(startParagraphIndex, startOffsetInParagraph)
    }
    fun stopTts() { ttsController.stopTts() }
    fun togglePlayPause() {
        if (_isPlaying.value || _isPaused.value) {
            ttsController.togglePlayPause()
            return
        }
        if (_firstVisibleParagraphIndex.value >= 0) {
            startTts(_firstVisibleParagraphIndex.value, firstVisibleParagraphOffset)
            return
        }
        ttsController.togglePlayPause()
    }

    internal fun jumpToParagraphForTts(index: Int) {
        ttsController.jumpToParagraph(index)
    }

    // ==================== 娓呯悊 ====================

    override fun onCleared() {
        super.onCleared()
        ttsController.release()
    }

    // =================================================================
    // PASSTHROUGH METHODS (No changes below this line, only player references)
    // =================================================================
    
    internal fun saveBookProgress() {
        val book = _selectedBook.value ?: return
        val bookUrl = book.bookUrl ?: return
        val token = _accessToken.value
        if (token.isBlank()) return

        val index = _currentChapterIndex.value
        val progress = if (_currentParagraphIndex.value >= 0) _currentParagraphIndex.value.toDouble() else 0.0
        val title = _chapters.value.getOrNull(index)?.title ?: book.durChapterTitle

        // 立即更新本地状态，确保 UI 响应
        val now = System.currentTimeMillis()
        val updatedBook = book.copy(
            durChapterIndex = index,
            durChapterProgress = _currentParagraphIndex.value,
            durChapterTitle = title,
            durChapterPos = progress,
            durChapterTime = now
        )
        
        _selectedBook.value = updatedBook
        allBooks = allBooks.map { if (it.bookUrl == bookUrl) updatedBook else it }
        applyBooksFilterAndSort()

        viewModelScope.launch {
            bookRepository.saveBookProgress(
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

    internal suspend fun ensureCurrentChapterContent(): String? {
        if (_currentChapterContent.value.isNotBlank()) {
            return _currentChapterContent.value
        }
        return loadChapterContentInternal(_currentChapterIndex.value)
    }

    internal fun resetPlayback() {
        _playbackProgress.value = 0f
        _currentTime.value = "00:00"
        _totalTime.value = "00:00"
    }

    fun login(server: String, username: String, password: String, onSuccess: () -> Unit) {
        viewModelScope.launch {
            _isLoading.value = true
            _errorMessage.value = null
            val (baseHost, backend) = resolveServerInput(server)
            val normalized = normalizeApiBaseUrl(baseHost, backend)
            val result = authRepository.login(normalized, _publicServerAddress.value.ifBlank { null }, username, password)
            result.onFailure { error -> _errorMessage.value = error.message }
            val loginData = result.getOrNull()
            if (loginData != null) {
                _accessToken.value = loginData.accessToken
                _username.value = username
                _serverAddress.value = baseHost
                _apiBackend.value = backend
                preferences.saveAccessToken(loginData.accessToken)
                preferences.saveUsername(username)
                preferences.saveServerUrl(baseHost)
                preferences.saveApiBackend(backend)
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
            chapterContentRepository.clearMemoryCache()
            ttsController.stopTts()
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
            val result = bookRepository.importBook(currentServerEndpoint(), _publicServerAddress.value.ifBlank { null }, _accessToken.value, uri, appContext)
            result.onFailure { error -> _errorMessage.value = error.message }
            if (result.isSuccess) {
                refreshBooksInternal(showLoading = false)
            }
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
        val booksResult = bookRepository.fetchBooks(currentServerEndpoint(), _publicServerAddress.value.ifBlank { null }, _accessToken.value)
        booksResult.onSuccess { list ->
            allBooks = list
            applyBooksFilterAndSort()
            localCache.saveBookshelfCache(list)
        }.onFailure { error ->
            if (allBooks.isEmpty()) {
                val cached = localCache.loadBookshelfCache()
                if (!cached.isNullOrEmpty()) {
                    allBooks = cached
                    applyBooksFilterAndSort()
                } else {
                    _errorMessage.value = error.message
                }
            }
        }
        if (showLoading) { _isLoading.value = false }
    }

    fun searchBooks(query: String) {
        currentSearchQuery = query
        applyBooksFilterAndSort()
        
        if (query.isNotBlank() && _searchSourcesFromBookshelf.value) {
            performOnlineSearch(query)
        } else {
            _onlineSearchResults.value = emptyList()
            _isOnlineSearching.value = false
        }
    }

    private suspend fun loadBookSources() {
        val (baseUrl, publicUrl, token) = preferences.getCredentials()
        if (token == null) return
        sourceRepository.getBookSources(appContext, baseUrl, publicUrl, token).collect { result ->
            result.onSuccess { _availableBookSources.value = it }
        }
    }

    private var onlineSearchJob: Job? = null
    private fun performOnlineSearch(query: String) {
        onlineSearchJob?.cancel()
        onlineSearchJob = viewModelScope.launch {
            delay(800) // Debounce
            _isOnlineSearching.value = true
            _onlineSearchResults.value = emptyList()

            val (baseUrl, publicUrl, token) = preferences.getCredentials()
            if (token == null) {
                _isOnlineSearching.value = false
                return@launch
            }

            val enabledSources = _availableBookSources.value.filter { it.enabled }
            val targetSources = if (_preferredSearchSourceUrls.value.isEmpty()) {
                enabledSources
            } else {
                enabledSources.filter { _preferredSearchSourceUrls.value.contains(it.bookSourceUrl) }
            }

            val deferredResults = targetSources.map { source ->
                async {
                    bookRepository.searchBook(
                        baseUrl = baseUrl,
                        publicUrl = publicUrl,
                        accessToken = token,
                        keyword = query,
                        bookSourceUrl = source.bookSourceUrl,
                        page = 1
                    ).getOrNull()?.map { it.copy(sourceDisplayName = source.bookSourceName) } ?: emptyList()
                }
            }

            val allResults = deferredResults.awaitAll().flatten()
            _onlineSearchResults.value = allResults
            _isOnlineSearching.value = false
        }
    }

    fun saveBookToBookshelf(book: Book) {
        viewModelScope.launch {
            val (baseUrl, publicUrl, token) = preferences.getCredentials()
            if (token == null) {
                _errorMessage.value = "Not logged in"
                return@launch
            }

            bookRepository.saveBook(
                baseUrl = baseUrl,
                publicUrl = publicUrl,
                accessToken = token,
                book = book
            ).onSuccess {
                refreshBooks()
            }.onFailure {
                _errorMessage.value = it.message ?: "Failed to add book to bookshelf"
            }
        }
    }

    fun removeFromBookshelf(book: Book) {
        viewModelScope.launch {
            val (baseUrl, publicUrl, token) = preferences.getCredentials()
            if (token == null) {
                _errorMessage.value = "Not logged in"
                return@launch
            }

            bookRepository.deleteBook(
                baseUrl = baseUrl,
                publicUrl = publicUrl,
                accessToken = token,
                book = book
            ).onSuccess {
                refreshBooks()
            }.onFailure {
                _errorMessage.value = it.message ?: "Failed to remove book from bookshelf"
            }
        }
    }

    fun changeBookSource(newSourceBook: Book, onSuccess: () -> Unit) {
        val currentBook = _selectedBook.value ?: return
        val oldUrl = currentBook.bookUrl ?: return
        val newUrl = newSourceBook.bookUrl ?: return
        val newSourceUrl = newSourceBook.origin ?: return

        viewModelScope.launch {
            _isLoading.value = true
            val (baseUrl, publicUrl, token) = preferences.getCredentials()
            if (token == null) {
                _isLoading.value = false
                return@launch
            }

            bookRepository.setBookSource(baseUrl, publicUrl, token, oldUrl, newUrl, newSourceUrl)
                .onSuccess { updatedBook ->
                    refreshBooks()
                    _selectedBook.value = updatedBook
                    onSuccess()
                }
                .onFailure { _errorMessage.value = "更换源失败: ${it.message}" }
            _isLoading.value = false
        }
    }

    fun searchNewSource(bookName: String, author: String): Flow<List<Book>> = flow {
        val (baseUrl, publicUrl, token) = preferences.getCredentials()
        if (token == null) return@flow

        val sources = _availableBookSources.value.filter { it.enabled }
        val allResults = mutableListOf<Book>()
        
        sources.forEach { source ->
            // 仅使用书名搜索
            bookRepository.searchBook(baseUrl, publicUrl, token, bookName, source.bookSourceUrl, 1)
                .onSuccess { books ->
                    // 本地精滤：书名必须完全一致
                    val exactMatches = books.filter { it.name == bookName }
                    allResults.addAll(exactMatches.map { it.copy(sourceDisplayName = source.bookSourceName) })
                    
                    // 排序逻辑：作者一致的排最前面
                    allResults.sortByDescending { it.author == author }
                    emit(allResults.toList())
                }
        }
    }

    fun selectBook(book: Book) {
        if (_selectedBook.value?.bookUrl == book.bookUrl) return
        ttsController.stopTts()
        _selectedBook.value = book
        _showTtsControls.value = false
        _currentChapterIndex.value = book.durChapterIndex ?: 0
        _currentParagraphIndex.value = book.durChapterProgress ?: -1
        _currentChapterContent.value = ""
        currentParagraphs = emptyList()
        clearAdjacentChapterCache()
        chapterContentRepository.clearMemoryCache()
        resetPlayback()
        viewModelScope.launch { loadChapters(book) }
    }

    fun setCurrentChapter(index: Int) {
        if (index !in _chapters.value.indices) return
        val shouldContinuePlaying = _keepPlaying.value
        ttsController.stopTts()
        val bookUrl = _selectedBook.value?.bookUrl
        val isManga = bookUrl != null && (manualMangaUrls.value.contains(bookUrl) || _selectedBook.value?.type == 2)
        val prefetchedMangaContent = if (isManga && _nextChapterIndex.value == index) {
            _nextChapterContent.value
        } else {
            null
        }
        _currentChapterIndex.value = index
        _currentChapterContent.value = ""
        currentParagraphs = emptyList()
        clearAdjacentChapterCache()
        
        saveBookProgress()
        
        if (!prefetchedMangaContent.isNullOrBlank()) {
            updateChapterContent(index, prefetchedMangaContent)
            if (shouldContinuePlaying) {
                ttsController.startTts()
            }
            return
        }

        if (shouldContinuePlaying) {
            ttsController.startTts()
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

    fun switchChapterFromInfiniteScroll(direction: Int, anchorParagraphIndex: Int) {
        val target = _currentChapterIndex.value + direction
        if (target !in _chapters.value.indices) return
        val shouldContinuePlaying = _keepPlaying.value
        ttsController.stopTts()
        _currentChapterIndex.value = target
        _currentChapterContent.value = ""
        currentParagraphs = emptyList()
        _pendingScrollIndex.value = anchorParagraphIndex.coerceAtLeast(0)
        
        saveBookProgress()

        val preloadedContent = when (direction) {
            -1 -> if (_prevChapterIndex.value == target) _prevChapterContent.value else null
            1 -> if (_nextChapterIndex.value == target) _nextChapterContent.value else null
            else -> null
        }

        if (!preloadedContent.isNullOrBlank()) {
            updateChapterContent(target, preloadedContent)
            if (shouldContinuePlaying) {
                ttsController.startTts()
            }
        } else {
            if (shouldContinuePlaying) {
                ttsController.startTts()
            } else {
                viewModelScope.launch { loadChapterContent(target) }
            }
        }
    }

    fun loadCurrentChapterContent() {
        viewModelScope.launch { loadChapterContent(_currentChapterIndex.value) }
    }

    fun deleteTtsEngine(id: String) {
        viewModelScope.launch {
            ttsRepository.deleteTts(currentServerEndpoint(), _publicServerAddress.value.ifBlank { null }, _accessToken.value, id)
                .onSuccess { loadTtsEnginesInternal() }
                .onFailure { _errorMessage.value = "删除失败: ${it.message}" }
        }
    }

    fun addTtsEngine(tts: HttpTTS) {
        viewModelScope.launch {
            ttsRepository.addTts(currentServerEndpoint(), _publicServerAddress.value.ifBlank { null }, _accessToken.value, tts)
                .onSuccess { loadTtsEnginesInternal() }
                .onFailure { _errorMessage.value = "保存失败: ${it.message}" }
        }
    }

    fun saveTtsBatch(jsonContent: String) {
        viewModelScope.launch {
            ttsRepository.saveTtsBatch(currentServerEndpoint(), _publicServerAddress.value.ifBlank { null }, _accessToken.value, jsonContent)
                .onSuccess { loadTtsEnginesInternal() }
                .onFailure { _errorMessage.value = "批量导入失败: ${it.message}" }
        }
    }

    fun changePassword(oldPass: String, newPass: String, onSuccess: () -> Unit) {
        viewModelScope.launch {
            _isLoading.value = true
            val (baseUrl, publicUrl, token) = preferences.getCredentials()
            if (token == null) {
                _isLoading.value = false
                return@launch
            }

            authRepository.changePassword(baseUrl, publicUrl, token, oldPass, newPass)
                .onSuccess {
                    onSuccess()
                }
                .onFailure { _errorMessage.value = "修改失败: ${it.message}" }
            _isLoading.value = false
        }
    }

    fun downloadChapters(startIndex: Int, endIndex: Int) {
        val book = _selectedBook.value ?: return
        val chapters = _chapters.value
        if (chapters.isEmpty()) return
        
        val actualStart = startIndex.coerceIn(0, chapters.lastIndex)
        val actualEnd = endIndex.coerceIn(actualStart, chapters.lastIndex)
        val count = actualEnd - actualStart + 1

        // 判断是否为漫画模式
        val isManga = manualMangaUrls.value.contains(book.bookUrl) || book.type == 2
        val effectiveType = if (isManga) 2 else 0

        viewModelScope.launch(Dispatchers.IO) {
            for (i in actualStart..actualEnd) {
                if (!localCache.isChapterCached(book.bookUrl ?: "", i)) {
                    val chapter = chapters[i]
                    bookRepository.fetchChapterContent(
                        currentServerEndpoint(),
                        _publicServerAddress.value.ifBlank { null },
                        _accessToken.value,
                        book.bookUrl ?: "",
                        book.origin,
                        chapter.index,
                        effectiveType
                    ).onSuccess { content ->
                        val cleaned = cleanChapterContent(content.orEmpty())
                        localCache.saveChapter(book.bookUrl ?: "", i, cleaned)
                        if (isManga) {
                            cacheMangaImages(book, chapter, i, cleaned)
                        }
                    }
                }
            }
            withContext(Dispatchers.Main) {
                Toast.makeText(appContext, "缓存完成 ($count 章)", Toast.LENGTH_SHORT).show()
            }
        }
    }

    fun downloadAllChapters() {
        downloadChapters(0, _chapters.value.lastIndex)
    }

    internal fun cacheMangaImages(book: Book, chapter: com.readapp.data.model.Chapter, chapterIndex: Int, content: String) {
        val bookUrl = book.bookUrl ?: return
        val images = MangaImageExtractor.extractImageUrls(content)
        if (images.isEmpty()) return
        val forceProxy = readerSettings.forceMangaProxy.value
        val client = okhttp3.OkHttpClient()
        for (img in images) {
            val resolved = resolveImageUrl(img)
            val profile = MangaAntiScrapingService.resolveProfile(resolved, chapter.url)
            val referer = MangaAntiScrapingService.resolveReferer(profile, chapter.url, resolved)
            if (localCache.isMangaImageCached(bookUrl, chapterIndex, resolved)) continue
            val proxyUrl = buildProxyUrl(resolved)
            val requestUrl = if (forceProxy && proxyUrl != null) proxyUrl else resolved
            val request = okhttp3.Request.Builder()
                .url(requestUrl)
                .apply {
                    if (!referer.isNullOrBlank()) {
                        header("Referer", referer)
                    }
                }
                .header("User-Agent", profile?.userAgent ?: "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Mobile Safari/537.36")
                .apply {
                    profile?.extraHeaders?.forEach { (key, value) ->
                        header(key, value)
                    }
                }
                .build()
            runCatching {
                client.newCall(request).execute().use { response ->
                    if (response.isSuccessful) {
                        val bytes = response.body?.bytes()
                        if (bytes != null && bytes.isNotEmpty()) {
                            localCache.saveMangaImage(bookUrl, chapterIndex, resolved, bytes)
                            return@use
                        }
                    }
                }
            }
            if (!forceProxy && proxyUrl != null) {
                runCatching {
                    val fallback = okhttp3.Request.Builder()
                        .url(proxyUrl)
                        .apply {
                            if (!referer.isNullOrBlank()) {
                                header("Referer", referer)
                            }
                        }
                        .header("User-Agent", profile?.userAgent ?: "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Mobile Safari/537.36")
                        .apply {
                            profile?.extraHeaders?.forEach { (key, value) ->
                                header(key, value)
                            }
                        }
                        .build()
                    client.newCall(fallback).execute().use { response ->
                        if (response.isSuccessful) {
                            val bytes = response.body?.bytes()
                            if (bytes != null && bytes.isNotEmpty()) {
                                localCache.saveMangaImage(bookUrl, chapterIndex, resolved, bytes)
                            }
                        }
                    }
                }
            }
        }
    }

    private fun resolveImageUrl(url: String): String {
        val base = stripApiBasePath(currentServerEndpoint())
        return MangaImageNormalizer.resolveUrl(url, base)
    }

    private fun buildProxyUrl(url: String): String? {
        val backend = detectApiBackend(currentServerEndpoint())
        if (backend != ApiBackend.Read) {
            return null
        }
        val base = stripApiBasePath(normalizeApiBaseUrl(currentServerEndpoint(), backend))
        return Uri.parse(base).buildUpon()
            .path("api/5/proxypng")
            .appendQueryParameter("url", url)
            .appendQueryParameter("accessToken", _accessToken.value)
            .build()
            .toString()
    }

    private suspend fun loadChapters(book: Book) = readerInteractor.loadChapters(book)

    fun loadChapterContent(index: Int) { readerInteractor.loadChapterContent(index) }
    fun onChapterChange(index: Int) { setCurrentChapter(index) }
    private suspend fun loadChapterContentInternal(index: Int): String? = readerInteractor.loadChapterContentInternal(index)
    private fun updateChapterContent(index: Int, content: String) = readerInteractor.updateChapterContent(index, content)
    private fun clearAdjacentChapterCache() = readerInteractor.clearAdjacentChapterCache()
    private suspend fun prefetchAdjacentChapters() = readerInteractor.prefetchAdjacentChapters()
    private suspend fun fetchChapterContentForIndex(index: Int, effectiveType: Int): String? =
        readerInteractor.fetchChapterContentForIndex(index, effectiveType)

    internal fun saveChapterListToCache(bookUrl: String, chapters: List<com.readapp.data.model.Chapter>) {
        localCache.saveChapterList(bookUrl, chapters)
    }

    internal fun loadChapterListFromCache(bookUrl: String): List<com.readapp.data.model.Chapter>? {
        return localCache.loadChapterList(bookUrl)
    }
    internal fun parseParagraphs(content: String, chunkLimit: Int = ttsSentenceChunkLimit.value, includeTitle: Boolean = false): List<String> {
        val lines = content.split("\n").map { it.trim() }.filter { it.isNotBlank() }
        val finalParagraphs = mutableListOf<String>()
        
        if (includeTitle) {
            val title = currentChapterTitle
            if (title.isNotBlank()) {
                if (lines.isEmpty() || lines[0] != title) {
                    finalParagraphs.add(title)
                }
            }
        }

        // 启发式判断：如果全文包含图片且文本较少，极可能是漫画，开启更强过滤
        val likelyManga = content.contains("__IMG__") && content.length < 5000

        for (line in lines) {
            // 过滤：如果一段内容仅仅是 URL 且没有识别标记，说明是 HTML 剥离后的杂质
            val lowerLine = line.lowercase()
            val isRawUrl = lowerLine.startsWith("http") || lowerLine.startsWith("//")
            // 高熵文本拦截：很长的连续字母数字串（无空格）通常是杂质
            val isHighEntropy = likelyManga && line.length > 30 && !line.contains(" ")
            
            if ((isRawUrl || isHighEntropy) && !line.contains("__IMG__")) {
                continue
            }

            if (line.contains("__IMG__")) {
                // 更细致地分割，处理同行有文字和图片的情况
                val parts = line.split("__IMG__")
                for ((index, part) in parts.withIndex()) {
                    val p = part.trim()
                    if (index == 0) {
                        if (p.isNotEmpty()) finalParagraphs.add(p)
                    } else {
                        // 提取 URL 部分（假设 URL 后面跟着空格或直接结束）
                        val urlParts = p.split(" ", limit = 2)
                        val url = urlParts[0].trim()
                        if (url.isNotEmpty()) finalParagraphs.add("__IMG__$url")
                        if (urlParts.size > 1 && urlParts[1].trim().isNotEmpty()) {
                            finalParagraphs.add(urlParts[1].trim())
                        }
                    }
                }
            } else {
                finalParagraphs.add(line)
            }
        }
        val limit = chunkLimit.coerceIn(300, 1000)
        return finalParagraphs.flatMap { splitIntoChunks(it, limit) }
    }

    private fun splitIntoChunks(text: String, limit: Int): List<String> {
        if (text.isEmpty()) return emptyList()
        if (text.length <= limit) return listOf(text)

        val breakChars = setOf(' ', '，', '。', '！', '？', '、', ',', '.', '!', '?')
        val chunks = mutableListOf<String>()
        var remaining = text.trim()

        while (remaining.length > limit) {
            var splitIndex = limit
            while (splitIndex > 0 && !breakChars.contains(remaining[splitIndex - 1])) {
                splitIndex--
            }
            if (splitIndex == 0) splitIndex = limit
            val chunk = remaining.substring(0, splitIndex).trim()
            if (chunk.isNotEmpty()) chunks.add(chunk)
            remaining = remaining.substring(splitIndex).trim()
        }

        if (remaining.isNotEmpty()) {
            chunks.add(remaining)
        }
        return chunks
    }
    internal fun cleanChapterContent(raw: String): String {
        if (raw.isBlank()) return ""

        var content = raw
        _replaceRules.value.filter { it.isEnabled }.sortedBy { it.ruleOrder }.forEach { rule ->
            try {
                content = content.replace(Regex(rule.pattern), rule.replacement)
            } catch (e: Exception) {
                Log.w(TAG, "鍑€鍖栬鍒欐墽琛屽け璐? ${rule.name}", e)
            }
        }

        content = content.replace("(?is)<svg.*?</svg>".toRegex(), "")
        content = content.replace("(?is)<script.*?</script>".toRegex(), "")
        content = content.replace("(?is)<style.*?</style>".toRegex(), "")
        
        // 提取图片并转换为统一占位符
        content = content.replace("(?is)<img[^>]+src\\s*=\\s*[\"']([^\"']+)[\"'][^>]*>".toRegex(), "\n__IMG__$1\n")
        
        // 移除所有其他 HTML 标签
        content = content.replace("(?is)<[^>]+>".toRegex(), "\n")

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
        val enginesResult = ttsRepository.fetchTtsEngines(currentServerEndpoint(), _publicServerAddress.value.ifBlank { null }, _accessToken.value)
        enginesResult.onSuccess { list ->
            engines = list
            _availableTtsEngines.value = list
        }.onFailure { error -> _errorMessage.value = error.message }
        val defaultResult = ttsRepository.fetchDefaultTts(currentServerEndpoint(), _publicServerAddress.value.ifBlank { null }, _accessToken.value)
        val defaultId = defaultResult.getOrNull()
        val resolved = listOf(_selectedTtsEngine.value, defaultId, engines.firstOrNull()?.id).firstOrNull { !it.isNullOrBlank() }.orEmpty()
        if (resolved.isNotBlank() && resolved != _selectedTtsEngine.value) {
            _selectedTtsEngine.value = resolved
            preferences.saveSelectedTtsId(resolved)
        }
    }
    fun loadTtsEngines() { if (_accessToken.value.isBlank()) return; viewModelScope.launch { loadTtsEnginesInternal() } }
    fun selectTtsEngine(engineId: String) { _selectedTtsEngine.value = engineId; viewModelScope.launch { preferences.saveSelectedTtsId(engineId) } }
    fun updateUseSystemTts(enabled: Boolean) { _useSystemTts.value = enabled; viewModelScope.launch { preferences.saveUseSystemTts(enabled) } }
    fun updateSystemVoiceId(voiceId: String) { _systemVoiceId.value = voiceId; viewModelScope.launch { preferences.saveSystemVoiceId(voiceId) } }
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
    fun updateServerAddress(address: String) {
        val (baseHost, backend) = resolveServerInput(address)
        _serverAddress.value = baseHost
        _apiBackend.value = backend
        viewModelScope.launch {
            preferences.saveServerUrl(baseHost)
            preferences.saveApiBackend(backend)
        }
    }
    fun updateApiBackend(backend: ApiBackend) {
        _apiBackend.value = backend
        viewModelScope.launch { preferences.saveApiBackend(backend) }
    }
    fun updateSpeechSpeed(speed: Int) { 
        _speechSpeed.value = speed.coerceIn(50, 300) 
        viewModelScope.launch { preferences.saveSpeechRate(_speechSpeed.value.toDouble()) } 
    }
    fun updatePreloadCount(count: Int) { _preloadCount.value = count.coerceIn(1, 10); viewModelScope.launch { preferences.savePreloadCount(_preloadCount.value.toFloat()) } }
    fun updateReadingFontSize(size: Float) { readerSettings.updateReadingFontSize(size) }
    fun updateReadingFont(path: String, name: String) { readerSettings.updateReadingFont(path, name) }
    fun updateReadingHorizontalPadding(padding: Float) { readerSettings.updateReadingHorizontalPadding(padding) }
    fun updateInfiniteScrollEnabled(enabled: Boolean) {
        readerSettings.updateInfiniteScrollEnabled(
            enabled = enabled,
            onDisable = { clearAdjacentChapterCache() },
            onEnable = { viewModelScope.launch { prefetchAdjacentChapters() } }
        )
    }
    fun updateLoggingEnabled(enabled: Boolean) { _loggingEnabled.value = enabled; viewModelScope.launch { preferences.saveLoggingEnabled(enabled) } }
    fun updateBookshelfSortByRecent(enabled: Boolean) { _bookshelfSortByRecent.value = enabled; viewModelScope.launch { preferences.saveBookshelfSortByRecent(enabled); applyBooksFilterAndSort() } }
    fun updateVisibleParagraphInfo(startIndex: Int, startOffset: Int, endIndex: Int, endOffset: Int) {
        if (startIndex < 0) return
        _firstVisibleParagraphIndex.value = startIndex
        _lastVisibleParagraphIndex.value = endIndex
        firstVisibleParagraphOffset = startOffset.coerceAtLeast(0)
        currentPageStartParagraphIndex = startIndex
        currentPageStartOffset = startOffset.coerceAtLeast(0)
        currentPageEndParagraphIndex = endIndex
        currentPageEndOffset = endOffset.coerceAtLeast(0)
        if (!_isPlaying.value && !_keepPlaying.value) {
            _currentParagraphIndex.value = startIndex
            _currentParagraphStartOffset.value = firstVisibleParagraphOffset
        }
        ttsSyncCoordinator.onUiParagraphVisible(startIndex)
    }

    fun onUserScrollState(isScrolling: Boolean) {
        if (isScrolling) {
            isUserScrolling = true
            ttsFollowJob?.cancel()
            return
        }
        if (!isUserScrolling) return
        isUserScrolling = false
        val delayMs = (ttsFollowCooldownSeconds.value * 1000f).toLong().coerceAtLeast(0L)
        ttsFollowSuppressedUntil = SystemClock.elapsedRealtime() + delayMs
        ttsFollowJob?.cancel()
        ttsFollowJob = viewModelScope.launch {
            delay(delayMs)
            if (!isUserScrolling) {
                handleUserScrollCatchUp()
            }
        }
    }

    internal fun shouldAllowTtsFollow(): Boolean {
        if (isUserScrolling) return false
        if (_isPaused.value) return false
        return SystemClock.elapsedRealtime() >= ttsFollowSuppressedUntil
    }

    private fun handleUserScrollCatchUp() {
        if (!_keepPlaying.value || _isPaused.value) return
        if (!isTtsInCurrentPage()) {
            startTts(currentPageStartParagraphIndex, currentPageStartOffset)
        }
    }

    private fun isTtsInCurrentPage(): Boolean {
        val ttsIndex = _currentParagraphIndex.value
        if (ttsIndex < 0) return false
        if (ttsIndex < currentPageStartParagraphIndex || ttsIndex > currentPageEndParagraphIndex) {
            return false
        }
        if (ttsIndex == currentPageStartParagraphIndex && currentPageStartOffset > 0) {
            val ttsOffset = _currentParagraphStartOffset.value
            if (ttsOffset < currentPageStartOffset) return false
        }
        if (ttsIndex == currentPageEndParagraphIndex && currentPageEndOffset > 0) {
            val ttsOffset = _currentParagraphStartOffset.value
            if (ttsOffset > currentPageEndOffset) return false
        }
        return true
    }

    fun clearPendingScrollIndex() {
        _pendingScrollIndex.value = null
    }

    internal fun requestScrollIndexFromTts(index: Int) {
        _pendingScrollIndex.value = index
    }

    fun updateReadingMode(mode: com.readapp.data.ReadingMode) {
        readerSettings.updateReadingMode(mode) {
            _pendingScrollIndex.value = _firstVisibleParagraphIndex.value
        }
    }
    fun updateLockPageOnTTS(enabled: Boolean) { readerSettings.updateLockPageOnTTS(enabled) }
    fun updateTtsFollowCooldownSeconds(seconds: Float) { readerSettings.updateTtsFollowCooldownSeconds(seconds) }
    fun updateTtsSentenceChunkLimit(limit: Int) { readerSettings.updateTtsSentenceChunkLimit(limit) }
    fun updatePageTurningMode(mode: com.readapp.data.PageTurningMode) { readerSettings.updatePageTurningMode(mode) }
    fun updateDarkModeConfig(config: com.readapp.data.DarkModeConfig) { readerSettings.updateDarkModeConfig(config) }
    fun updateReadingTheme(theme: com.readapp.data.ReaderTheme) { readerSettings.updateReadingTheme(theme) }
    fun updateSearchSourcesFromBookshelf(enabled: Boolean) { 
        _searchSourcesFromBookshelf.value = enabled
        viewModelScope.launch { 
            preferences.saveSearchSourcesFromBookshelf(enabled)
            // Re-trigger search to update online results immediately
            searchBooks(currentSearchQuery)
        } 
    }
    fun togglePreferredSearchSource(url: String) {
        val current = _preferredSearchSourceUrls.value.toMutableSet()
        if (current.contains(url)) current.remove(url) else current.add(url)
        _preferredSearchSourceUrls.value = current
        viewModelScope.launch { preferences.savePreferredSearchSourceUrls(current.joinToString(";")) }
    }
    fun clearPreferredSearchSources() {
        _preferredSearchSourceUrls.value = emptySet()
        viewModelScope.launch { preferences.savePreferredSearchSourceUrls("") }
    }
    fun toggleManualManga(url: String) { readerSettings.toggleManualManga(url) }
    fun updateForceMangaProxy(enabled: Boolean) { readerSettings.updateForceMangaProxy(enabled) }
    fun updateMangaSwitchThreshold(threshold: Int) { readerSettings.updateMangaSwitchThreshold(threshold) }
    fun updateVerticalDampingFactor(factor: Float) { readerSettings.updateVerticalDampingFactor(factor) }
    fun updateMangaMaxZoom(zoom: Float) { readerSettings.updateMangaMaxZoom(zoom) }
    fun clearCache() {
        viewModelScope.launch {
            ttsController.clearCache()
            chapterContentRepository.clearMemoryCache()
        }
    }
    private fun resolveTtsEngine(ttsId: String): HttpTTS? =
        _availableTtsEngines.value.firstOrNull { it.id == ttsId }

    internal fun buildTtsAudioRequest(sentence: String, isChapterTitle: Boolean): TtsAudioRequest? {
        val ttsId = resolveTtsIdForSentence(sentence, isChapterTitle) ?: return null
        val engine = resolveTtsEngine(ttsId) ?: return null
        val speechRate = (_speechSpeed.value / 20.0).coerceIn(0.1, 4.0)
        return ttsRepository.buildTtsAudioRequest(
            currentServerEndpoint(),
            _accessToken.value,
            engine,
            sentence,
            speechRate,
            isChapterTitle
        )
    }

    internal suspend fun fetchReaderTtsAudio(request: TtsAudioRequest.Reader): ByteArray? {
        if (_accessToken.value.isBlank()) {
            _errorMessage.value = "请先登录"
            return null
        }
        val result = withContext(Dispatchers.IO) {
            ttsRepository.requestReaderTtsAudio(currentServerEndpoint(), _accessToken.value, request)
        }
        return result.fold(
            onSuccess = { it },
            onFailure = {
                _errorMessage.value = it.message ?: "播放 TTS 音频失败"
                null
            }
        )
    }
    private fun applyBooksFilterAndSort() {
        val filtered = if (currentSearchQuery.isBlank()) allBooks else allBooks.filter { it.name.orEmpty().lowercase().contains(currentSearchQuery.lowercase()) || it.author.orEmpty().lowercase().contains(currentSearchQuery.lowercase()) }
        val sorted = if (_bookshelfSortByRecent.value) {
            val indexed = filtered.mapIndexed { index, book -> index to book }
            val sortedPairs = indexed.sortedWith { a: Pair<Int, Book>, b: Pair<Int, Book> ->
                val time1 = a.second.durChapterTime ?: 0L
                val time2 = b.second.durChapterTime ?: 0L
                when {
                    time1 == 0L && time2 == 0L -> a.first.compareTo(b.first)
                    time1 == 0L -> 1
                    time2 == 0L -> -1
                    time1 == time2 -> a.first.compareTo(b.first)
                    else -> if (time1 > time2) -1 else 1
                }
            }
            sortedPairs.map { it.second }
        } else {
            filtered
        }
        _books.value = sorted
    }
    internal fun isPunctuationOnly(sentence: String): Boolean {
        val punctuation = "，。！？；、\"“”‘’…—·"
        return sentence.trim().all { it in punctuation }
    }
    private fun parseSpeakerMapping(raw: String): Map<String, String> { if (raw.isBlank()) return emptyMap(); return runCatching { val obj = JSONObject(raw); obj.keys().asSequence().associateWith { key -> obj.optString(key) } }.getOrDefault(emptyMap()) }
    private fun serializeSpeakerMapping(mapping: Map<String, String>): String { val obj = JSONObject(); mapping.forEach { (key, value) -> obj.put(key, value) }; return obj.toString() }
    fun exportLogs(context: android.content.Context): android.net.Uri? { if (!logFile.exists()) return null; return runCatching { val exportFile = File(context.cacheDir, LOG_EXPORT_NAME); logFile.copyTo(exportFile, overwrite = true); androidx.core.content.FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", exportFile) }.getOrNull() }
    fun clearLogs() { runCatching { if (logFile.exists()) { logFile.writeText("") } } }
    private fun appendLog(message: String) { if (!_loggingEnabled.value) return; val timestamp = SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.getDefault()).format(Date()); val line = "[$timestamp] $message\n"; runCatching { logFile.appendText(line) } }

    internal fun currentServerEndpoint(): String {
        return normalizeApiBaseUrl(_serverAddress.value, _apiBackend.value)
    }

    private fun resolveServerInput(server: String): Pair<String, ApiBackend> {
        val trimmed = server.trim()
        val hasSuffix = trimmed.contains("/api/") || trimmed.contains("/reader3")
        val backend = if (hasSuffix) detectApiBackend(trimmed) else _apiBackend.value
        val baseHost = stripApiBasePath(trimmed)
        return baseHost to backend
    }

    internal fun formatTime(milliseconds: Long): String {
        val totalSeconds = milliseconds / 1000
        val minutes = totalSeconds / 60
        val seconds = totalSeconds % 60
        return String.format("%02d:%02d", minutes, seconds)
    }

    private fun resolveTtsIdForSentence(sentence: String, isChapterTitle: Boolean): String? {
        // Check speaker mapping first
        _speakerTtsMapping.value.forEach { (speaker, ttsId) ->
            if (sentence.contains(speaker, ignoreCase = true)) {
                return ttsId
            }
        }

        // Then consider narration/dialogue if available
        if (isChapterTitle) {
            return _narrationTtsEngine.value.ifBlank { _selectedTtsEngine.value.ifBlank { null } }
        } else {
            return _dialogueTtsEngine.value.ifBlank { _narrationTtsEngine.value.ifBlank { _selectedTtsEngine.value.ifBlank { null } } }
        }
    }
}
