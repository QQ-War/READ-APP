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
import android.content.ComponentName
import androidx.media3.session.MediaController
import androidx.media3.session.SessionToken
import com.google.common.util.concurrent.MoreExecutors
import com.readapp.data.ReadApiService
import com.readapp.data.ReadRepository
import com.readapp.data.UserPreferences
import com.readapp.data.LocalCacheManager
import com.readapp.media.AudioCache
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
import okhttp3.OkHttpClient
import okhttp3.Request
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.speech.tts.Voice
import android.widget.Toast

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

    private val appContext = getApplication<Application>()
    val preferences = UserPreferences(appContext)
    private val localCache = LocalCacheManager(appContext)
    val repository = ReadRepository { endpoint ->
        ReadApiService.create(endpoint) { accessToken.value }
    }

    private var mediaController: MediaController? = null
    private val controllerListener = ControllerListener()
    private var textToSpeech: TextToSpeech? = null
    private var isTtsInitialized = false

    private val httpClient = OkHttpClient()
    private val preloadingIndices = mutableSetOf<Int>()
    private var preloadJob: Job? = null
    private var startOffsetOverrideIndex: Int? = null
    private var startOffsetOverrideChars: Int = 0


    // ==================== 涔︾睄鐩稿叧鐘舵€?====================

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

    // ==================== 娈佃惤鐩稿叧鐘舵€?====================

    private val _currentParagraphIndex = MutableStateFlow(-1)
    val currentParagraphIndex: StateFlow<Int> = _currentParagraphIndex.asStateFlow()
    private val _currentParagraphStartOffset = MutableStateFlow(0)
    val currentParagraphStartOffset: StateFlow<Int> = _currentParagraphStartOffset.asStateFlow()

    private val _totalParagraphs = MutableStateFlow(1)
    val totalParagraphs: StateFlow<Int> = _totalParagraphs.asStateFlow()

    private val _preloadedParagraphs = MutableStateFlow<Set<Int>>(emptySet())
    val preloadedParagraphs: StateFlow<Set<Int>> = _preloadedParagraphs.asStateFlow()
    private val _preloadedChapters = MutableStateFlow<Set<Int>>(emptySet())
    val preloadedChapters: StateFlow<Set<Int>> = _preloadedChapters.asStateFlow()

    // ==================== TTS 鎾斁鐘舵€?====================

    private val _isPlaying = MutableStateFlow(false)
    val isPlaying: StateFlow<Boolean> = _isPlaying.asStateFlow()
    private val _keepPlaying = MutableStateFlow(false)
    val isPlayingUi: StateFlow<Boolean> = combine(_isPlaying, _keepPlaying) { playing, keep ->
        playing || keep
    }.stateIn(viewModelScope, SharingStarted.Eagerly, false)
    private val _isPaused = MutableStateFlow(false)
    val isPaused: StateFlow<Boolean> = _isPaused.asStateFlow()
    private val _showTtsControls = MutableStateFlow(false)
    val showTtsControls: StateFlow<Boolean> = _showTtsControls.asStateFlow()

    private val _currentTime = MutableStateFlow("00:00")
    val currentTime: StateFlow<String> = _currentTime.asStateFlow()

    private val _totalTime = MutableStateFlow("00:00")
    val totalTime: StateFlow<String> = _totalTime.asStateFlow()

    private val _playbackProgress = MutableStateFlow(0f)
    val playbackProgress: StateFlow<Float> = _playbackProgress.asStateFlow()

    // ==================== 鍑€鍖栬鍒欑姸鎬?====================

    private val _replaceRules = MutableStateFlow<List<ReplaceRule>>(emptyList())
    val replaceRules: StateFlow<List<ReplaceRule>> = _replaceRules.asStateFlow()

    // ==================== TTS 璁剧疆 & 鍏朵粬 ====================
    // (No changes in this section, keeping it compact)
    private val _selectedTtsEngine = MutableStateFlow("")
    val selectedTtsEngine: StateFlow<String> = _selectedTtsEngine.asStateFlow()
    private val _useSystemTts = MutableStateFlow(false)
    val useSystemTts: StateFlow<Boolean> = _useSystemTts.asStateFlow()
    private val _systemVoiceId = MutableStateFlow("")
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

    private val _availableSystemVoices = MutableStateFlow<List<Voice>>(emptyList())
    val availableSystemVoices: StateFlow<List<Voice>> = _availableSystemVoices.asStateFlow()

    private val _speechSpeed = MutableStateFlow(20)
    val speechSpeed: StateFlow<Int> = _speechSpeed.asStateFlow()
    private val _preloadCount = MutableStateFlow(3)
    val preloadCount: StateFlow<Int> = _preloadCount.asStateFlow()
    private val _readingFontSize = MutableStateFlow(16f)
    val readingFontSize: StateFlow<Float> = _readingFontSize.asStateFlow()
    private val _readingHorizontalPadding = MutableStateFlow(24f)
    val readingHorizontalPadding: StateFlow<Float> = _readingHorizontalPadding.asStateFlow()
    private val _loggingEnabled = MutableStateFlow(false)
    val loggingEnabled: StateFlow<Boolean> = _loggingEnabled.asStateFlow()
    private val _bookshelfSortByRecent = MutableStateFlow(false)
    val bookshelfSortByRecent: StateFlow<Boolean> = _bookshelfSortByRecent.asStateFlow()
    private val _searchSourcesFromBookshelf = MutableStateFlow(false)
    val searchSourcesFromBookshelf: StateFlow<Boolean> = _searchSourcesFromBookshelf.asStateFlow()
    private val _preferredSearchSourceUrls = MutableStateFlow<Set<String>>(emptySet())
    val preferredSearchSourceUrls: StateFlow<Set<String>> = _preferredSearchSourceUrls.asStateFlow()
    private val _manualMangaUrls = MutableStateFlow<Set<String>>(emptySet())
    val manualMangaUrls: StateFlow<Set<String>> = _manualMangaUrls.asStateFlow()
    private val _forceMangaProxy = MutableStateFlow(false)
    val forceMangaProxy: StateFlow<Boolean> = _forceMangaProxy.asStateFlow()
    private val _readingMode = MutableStateFlow(com.readapp.data.ReadingMode.Vertical)
    val readingMode: StateFlow<com.readapp.data.ReadingMode> = _readingMode.asStateFlow()
    private val _lockPageOnTTS = MutableStateFlow(false)
    val lockPageOnTTS: StateFlow<Boolean> = _lockPageOnTTS.asStateFlow()
    private val _pageTurningMode = MutableStateFlow(com.readapp.data.PageTurningMode.Scroll)
    val pageTurningMode: StateFlow<com.readapp.data.PageTurningMode> = _pageTurningMode.asStateFlow()
    private val _isDarkMode = MutableStateFlow(false)
    val isDarkMode: StateFlow<Boolean> = _isDarkMode.asStateFlow()
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
    private val _onlineSearchResults = MutableStateFlow<List<Book>>(emptyList())
    val onlineSearchResults: StateFlow<List<Book>> = _onlineSearchResults.asStateFlow()
    private val _isOnlineSearching = MutableStateFlow(false)
    val isOnlineSearching: StateFlow<Boolean> = _isOnlineSearching.asStateFlow()
    private val _isChapterListLoading = MutableStateFlow(false)
    val isChapterListLoading: StateFlow<Boolean> = _isChapterListLoading.asStateFlow()
    private val _isChapterContentLoading = MutableStateFlow(false)
    val isChapterContentLoading: StateFlow<Boolean> = _isChapterContentLoading.asStateFlow()
    private val _isInitialized = MutableStateFlow(false)
    val isInitialized: StateFlow<Boolean> = _isInitialized.asStateFlow()

    fun clearError() { _errorMessage.value = null }

    // ==================== 鍒濆鍖?====================

    init {
        viewModelScope.launch {
            // Load all preferences
            _serverAddress.value = preferences.serverUrl.first()
            _publicServerAddress.value = preferences.publicServerUrl.first()
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
            _readingFontSize.value = preferences.readingFontSize.first()
            _readingHorizontalPadding.value = preferences.readingHorizontalPadding.first()
            _loggingEnabled.value = preferences.loggingEnabled.first()
            _bookshelfSortByRecent.value = preferences.bookshelfSortByRecent.first()
            _searchSourcesFromBookshelf.value = preferences.searchSourcesFromBookshelf.first()
            val urls = preferences.preferredSearchSourceUrls.first()
            _preferredSearchSourceUrls.value = if (urls.isBlank()) emptySet() else urls.split(";").toSet()
            val mUrls = preferences.manualMangaUrls.first()
            _manualMangaUrls.value = if (mUrls.isBlank()) emptySet() else mUrls.split(";").toSet()
            _forceMangaProxy.value = preferences.forceMangaProxy.first()
            _readingMode.value = preferences.readingMode.first()
            _lockPageOnTTS.value = preferences.lockPageOnTTS.first()
            _pageTurningMode.value = preferences.pageTurningMode.first()
            _isDarkMode.value = preferences.isDarkMode.first()

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

        initSystemTts()

        // Connect to MediaSession
        viewModelScope.launch {
            val sessionToken = SessionToken(appContext, ComponentName(appContext, ReadAudioService::class.java))
            val controllerFuture = MediaController.Builder(appContext, sessionToken).buildAsync()
            controllerFuture.addListener({
                mediaController = controllerFuture.get()
                mediaController?.addListener(controllerListener)
                _isPlaying.value = mediaController?.isPlaying == true
            }, MoreExecutors.directExecutor())
        }
    }

    // ==================== Controller Listener ====================

    private fun initSystemTts() {
        textToSpeech = TextToSpeech(appContext) { status ->
            if (status == TextToSpeech.SUCCESS) {
                isTtsInitialized = true
                textToSpeech?.language = Locale.CHINESE
                textToSpeech?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                    override fun onStart(utteranceId: String?) {
                        _isPlaying.value = true
                        _isPaused.value = false
                    }
                    override fun onDone(utteranceId: String?) {
                        if (_keepPlaying.value) {
                            viewModelScope.launch {
                                playNextSeamlessly()
                            }
                        }
                    }
                    override fun onError(utteranceId: String?) {
                        _errorMessage.value = "系统TTS发生错误"
                    }
                })
                // Load available voices
                _availableSystemVoices.value = textToSpeech?.voices?.filter { 
                    it.locale.language.startsWith("zh") || it.locale.language.startsWith("en")
                } ?: emptyList()
            }
        }
    }

    private inner class ControllerListener : Player.Listener {
        override fun onIsPlayingChanged(isPlaying: Boolean) {
            _isPlaying.value = isPlaying
            _isPaused.value = !isPlaying && _currentParagraphIndex.value >= 0
            if (isPlaying) {
                _showTtsControls.value = true
            }
        }

        override fun onPlaybackStateChanged(playbackState: Int) {
            if (playbackState == Player.STATE_ENDED && _keepPlaying.value) {
                playNextSeamlessly()
            }
        }

        override fun onPlayerError(error: PlaybackException) {
            _errorMessage.value = "播放失败: ${error.errorCodeName}"
            if (_keepPlaying.value) {
                viewModelScope.launch {
                    delay(500)
                    playNextSeamlessly()
                }
            }
        }
    }

    // ==================== TTS 鎺у埗鏂规硶 ====================

    fun togglePlayPause() {
        if (_selectedBook.value == null) return
        val currentMediaController = mediaController ?: return

        if (currentMediaController.isPlaying) {
            _keepPlaying.value = false
            _isPaused.value = true
            pausePlayback("toggle")
        } else if (_currentParagraphIndex.value >= 0) {
            _keepPlaying.value = true
            _showTtsControls.value = true
            _isPaused.value = false
            currentMediaController.play()
        } else {
            startPlayback()
        }
    }
    
    private fun startPlayback(startParagraphIndex: Int = -1, startOffsetInParagraph: Int = 0) {
        viewModelScope.launch {
            _isChapterContentLoading.value = true
            val content = withContext(Dispatchers.IO) { ensureCurrentChapterContent() }
            _isChapterContentLoading.value = false

            if (content.isNullOrBlank()) {
                _errorMessage.value = "当前章节内容为空，无法播放。"
                return@launch
            }

            _keepPlaying.value = true
            currentSentences = parseParagraphs(content)
            currentParagraphs = currentSentences
            _totalParagraphs.value = currentSentences.size.coerceAtLeast(1)
            val normalizedStart = if (startParagraphIndex in currentSentences.indices) {
                startParagraphIndex
            } else if (_currentParagraphIndex.value >= 0) {
                _currentParagraphIndex.value
            } else {
                0
            }
            _currentParagraphIndex.value = normalizedStart
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
            _currentParagraphStartOffset.value = normalizedOffset

            ReadAudioService.startService(appContext) // Ensure service is running
            _isPaused.value = false
            
            if (normalizedStart == 0 && normalizedOffset == 0) {
                speakChapterTitle()
            } else {
                isReadingChapterTitle = false
                speakParagraph(normalizedStart)
            }
            
            observeProgress()
        }
    }

    private fun playNextSeamlessly() {
        if (isReadingChapterTitle) {
            isReadingChapterTitle = false
            speakParagraph(0)
            return
        }
        val nextIndex = _currentParagraphIndex.value + 1
        speakParagraph(nextIndex)
    }

    private fun moveToNextChapterForTts(): Boolean {
        val nextIndex = _currentChapterIndex.value + 1
        if (nextIndex > _chapters.value.lastIndex) {
            return false
        }
        _currentChapterIndex.value = nextIndex
        _currentChapterContent.value = ""
        currentParagraphs = emptyList()
        currentSentences = emptyList()
        startPlayback(0, 0)
        return true
    }

    private fun speakParagraph(index: Int) {
        viewModelScope.launch {
            _currentParagraphIndex.value = index
            _playbackProgress.value = 0f

            if (index < 0 || index >= currentSentences.size) {
                if (_keepPlaying.value && moveToNextChapterForTts()) {
                    return@launch
                }
                stopPlayback("finished")
                return@launch
            }

            if (startOffsetOverrideIndex != null && startOffsetOverrideIndex != index) {
                startOffsetOverrideIndex = null
                startOffsetOverrideChars = 0
            }

            val sentence = currentSentences.getOrNull(index) ?: return@launch
            val overrideOffset = if (startOffsetOverrideIndex == index) startOffsetOverrideChars else 0
            _currentParagraphStartOffset.value = overrideOffset
            val trimmedSentence = if (overrideOffset in 1 until sentence.length) {
                sentence.substring(overrideOffset)
            } else {
                sentence
            }
            if (overrideOffset >= sentence.length) {
                startOffsetOverrideIndex = null
                startOffsetOverrideChars = 0
                _currentParagraphStartOffset.value = 0
                playNextSeamlessly()
                return@launch
            }

            if (_useSystemTts.value) {
                speakWithSystemTts(trimmedSentence)
                return@launch
            }

            val audioCacheKey = generateAudioCacheKey(index, overrideOffset)

            val audioData = AudioCache.get(audioCacheKey) ?: run {
                val audioUrl = buildTtsAudioUrl(trimmedSentence, false)

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
                AudioCache.put(audioCacheKey, data)
                _preloadedParagraphs.update { it + index }
                data
            }

            playFromService(audioCacheKey)
            preloadNextParagraphs()
        }
    }

    private fun speakWithSystemTts(text: String) {
        if (!isTtsInitialized) {
            _errorMessage.value = "系统TTS尚未就绪"
            return
        }
        
        textToSpeech?.let { tts ->
            // Set voice if selected
            if (_systemVoiceId.value.isNotBlank()) {
                tts.voices?.firstOrNull { it.name == _systemVoiceId.value }?.let {
                    tts.voice = it
                }
            }
            
            // Set speech rate: 1.0 is normal. 
            // Our speedSpeed is 5..50, where 20 is 1.0.
            tts.setSpeechRate(_speechSpeed.value / 20.0f)
            
            tts.speak(text, TextToSpeech.QUEUE_FLUSH, null, "paragraph_${_currentParagraphIndex.value}")
        }
    }

    private fun preloadNextParagraphs() {
        if (_useSystemTts.value) return
        
        preloadJob?.cancel()
        preloadJob = viewModelScope.launch(Dispatchers.IO) {
            val preloadCount = _preloadCount.value
            if (preloadCount <= 0) return@launch

            val startIndex = _currentParagraphIndex.value + 1
            val endIndex = (startIndex + preloadCount).coerceAtMost(currentSentences.size)
            val validIndices = (startIndex until endIndex).toSet()
            _preloadedParagraphs.update { it.intersect(validIndices) }

            for (i in startIndex until endIndex) {
                val audioCacheKey = generateAudioCacheKey(i)
                if (AudioCache.get(audioCacheKey) != null) {
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
                    AudioCache.put(audioCacheKey, data)
                    _preloadedParagraphs.update { it + i }
                } else {
                }
                unmarkPreloading(i)
            }
        }
    }

    private fun generateAudioCacheKey(index: Int, offsetInParagraph: Int = 0): String {
        val base = "${_selectedBook.value?.bookUrl}/${_currentChapterIndex.value}/$index"
        return if (offsetInParagraph > 0) {
            "$base/$offsetInParagraph"
        } else {
            base
        }
    }

    private fun clearAudioCache() {
        AudioCache.clear()
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
                        return@withContext null
                    }
                    val body = response.body ?: return@withContext null
                    body.bytes().takeIf { it.isNotEmpty() }
                }
            }.getOrElse { error ->
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
        if (_useSystemTts.value) {
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
            saveBookProgress()
        }

        _keepPlaying.value = false
        _showTtsControls.value = false
        _isPaused.value = false
        startOffsetOverrideIndex = null
        startOffsetOverrideChars = 0
        _currentParagraphStartOffset.value = 0
        
        if (_useSystemTts.value) {
            textToSpeech?.stop()
        } else {
            mediaController?.stop()
            mediaController?.clearMediaItems()
        }
        
        _currentParagraphIndex.value = -1
        isReadingChapterTitle = false
        _preloadedParagraphs.value = emptySet()
        resetPlayback()
    }

    // ==================== 鍑€鍖栬鍒欑姸鎬?====================

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

    fun deleteReplaceRule(id: String) {
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

    fun toggleReplaceRule(id: String, isEnabled: Boolean) {
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

    fun saveReplaceRules(jsonContent: String) {
        viewModelScope.launch {
            repository.saveReplaceRules(
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

    fun startTts(startParagraphIndex: Int = -1, startOffsetInParagraph: Int = 0) {
        startPlayback(startParagraphIndex, startOffsetInParagraph)
    }
    fun stopTts() { stopPlayback("user") }
    
    private fun speakChapterTitle() {
        viewModelScope.launch {
            isReadingChapterTitle = true
            _currentParagraphIndex.value = -1
            val title = currentChapterTitle
            if (title.isBlank()) {
                playNextSeamlessly()
                return@launch
            }
            
            if (_useSystemTts.value) {
                speakWithSystemTts(title)
            } else {
                val audioUrl = buildTtsAudioUrl(title, isChapterTitle = true)
                if (audioUrl == null) {
                    playNextSeamlessly()
                    return@launch
                }
                val data = fetchAudioBytes(audioUrl)
                if (data == null) {
                    playNextSeamlessly()
                    return@launch
                }
                val key = "title_${_selectedBook.value?.bookUrl}_${_currentChapterIndex.value}"
                AudioCache.put(key, data)
                playFromService(key)
            }
        }
    }

    private fun observeProgress() {
        viewModelScope.launch {
            while (_keepPlaying.value) {
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
                _playbackProgress.value = (position.toFloat() / duration).coerceIn(0f, 1f)
                _totalTime.value = formatTime(duration)
                _currentTime.value = formatTime(position)
                delay(500)
            }
        }
    }

    // ==================== 娓呯悊 ====================

    override fun onCleared() {
        super.onCleared()
        stopPlayback("cleared")
        mediaController?.removeListener(controllerListener)
        mediaController?.release()
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
                Log.w(TAG, "淇濆瓨闃呰杩涘害澶辫触: ${error.message}", error)
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
        repository.getBookSources(appContext, baseUrl, publicUrl, token).collect { result ->
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
                    repository.searchBook(
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

            repository.saveBook(
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

            repository.deleteBook(
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

            repository.setBookSource(baseUrl, publicUrl, token, oldUrl, newUrl, newSourceUrl)
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
            repository.searchBook(baseUrl, publicUrl, token, bookName, source.bookSourceUrl, 1)
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
        stopPlayback("book_change")
        _selectedBook.value = book
        _showTtsControls.value = false
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

    fun deleteTtsEngine(id: String) {
        viewModelScope.launch {
            repository.deleteTts(currentServerEndpoint(), _publicServerAddress.value.ifBlank { null }, _accessToken.value, id)
                .onSuccess { loadTtsEnginesInternal() }
                .onFailure { _errorMessage.value = "删除失败: ${it.message}" }
        }
    }

    fun addTtsEngine(tts: HttpTTS) {
        viewModelScope.launch {
            repository.addTts(currentServerEndpoint(), _publicServerAddress.value.ifBlank { null }, _accessToken.value, tts)
                .onSuccess { loadTtsEnginesInternal() }
                .onFailure { _errorMessage.value = "保存失败: ${it.message}" }
        }
    }

    fun saveTtsBatch(jsonContent: String) {
        viewModelScope.launch {
            repository.saveTtsBatch(currentServerEndpoint(), _publicServerAddress.value.ifBlank { null }, _accessToken.value, jsonContent)
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

            repository.changePassword(baseUrl, publicUrl, token, oldPass, newPass)
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

        viewModelScope.launch(Dispatchers.IO) {
            for (i in actualStart..actualEnd) {
                if (!localCache.isChapterCached(book.bookUrl ?: "", i)) {
                    val chapter = chapters[i]
                    repository.fetchChapterContent(
                        currentServerEndpoint(),
                        _publicServerAddress.value.ifBlank { null },
                        _accessToken.value,
                        book.bookUrl ?: "",
                        book.origin,
                        chapter.index
                    ).onSuccess { content ->
                        val cleaned = cleanChapterContent(content.orEmpty())
                        localCache.saveChapter(book.bookUrl ?: "", i, cleaned)
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

    private suspend fun loadChapters(book: Book) {
        val bookUrl = book.bookUrl ?: return
        _isChapterListLoading.value = true
        val chaptersResult = runCatching { repository.fetchChapterList(currentServerEndpoint(), _publicServerAddress.value.ifBlank { null }, _accessToken.value, bookUrl, book.origin) }
            .getOrElse { throwable ->
                _errorMessage.value = throwable.message
                Log.e(TAG, "鍔犺浇绔犺妭鍒楄〃澶辫触", throwable)
                _isChapterListLoading.value = false
                return
            }
        chaptersResult.onSuccess { chapterList ->
            _chapters.value = chapterList
            if (chapterList.isNotEmpty()) {
                val index = _currentChapterIndex.value.coerceIn(0, chapterList.lastIndex)
                _currentChapterIndex.value = index
                loadChapterContent(index)
            }
            _isChapterListLoading.value = false
        }.onFailure { error ->
            _errorMessage.value = error.message
            Log.e(TAG, "鍔犺浇绔犺妭鍒楄〃澶辫触", error)
            _isChapterListLoading.value = false
        }
    }

    fun loadChapterContent(index: Int) { viewModelScope.launch { loadChapterContentInternal(index) } }
    fun onChapterChange(index: Int) { setCurrentChapter(index) }
    private suspend fun loadChapterContentInternal(index: Int): String? {
        val book = _selectedBook.value ?: return null
        val chapter = _chapters.value.getOrNull(index) ?: return null
        val bookUrl = book.bookUrl ?: return null
        
        // 1. Check Memory Cache
        val cachedInMemory = chapterContentCache[index]
        if (!cachedInMemory.isNullOrBlank()) {
            updateChapterContent(index, cachedInMemory)
            return cachedInMemory
        }

        // 2. Check Disk Cache
        val cachedOnDisk = localCache.loadChapter(bookUrl, index)
        if (!cachedOnDisk.isNullOrBlank()) {
            updateChapterContent(index, cachedOnDisk)
            return cachedOnDisk
        }

        if (_isChapterContentLoading.value) {
            return _currentChapterContent.value.ifBlank { null }
        }
        _isChapterContentLoading.value = true
        return try {
            val result = repository.fetchChapterContent(currentServerEndpoint(), _publicServerAddress.value.ifBlank { null }, _accessToken.value, bookUrl, book.origin, chapter.index)
            result.onSuccess { content ->
                val cleaned = cleanChapterContent(content.orEmpty())
                val resolved = when {
                    cleaned.isNotBlank() -> cleaned
                    content.orEmpty().isNotBlank() -> content.orEmpty().trim()
                    else -> "章节内容为空"
                }
                // Save to disk cache
                localCache.saveChapter(bookUrl, index, resolved)
                updateChapterContent(index, resolved)
            }.onFailure { error ->
                _errorMessage.value = "加载失败: ${error.message}"
                Log.e(TAG, "加载章节内容失败", error)
            }
            _currentChapterContent.value
        } catch (e: Exception) {
            _errorMessage.value = "系统异常: ${e.localizedMessage}"
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
    fun updateServerAddress(address: String) { _serverAddress.value = address; viewModelScope.launch { preferences.saveServerUrl(address) } }
    fun updateSpeechSpeed(speed: Int) { 
        _speechSpeed.value = speed.coerceIn(50, 300) 
        viewModelScope.launch { preferences.saveSpeechRate(_speechSpeed.value.toDouble()) } 
    }
    fun updatePreloadCount(count: Int) { _preloadCount.value = count.coerceIn(1, 10); viewModelScope.launch { preferences.savePreloadCount(_preloadCount.value.toFloat()) } }
    fun updateReadingFontSize(size: Float) { _readingFontSize.value = size.coerceIn(12f, 28f); viewModelScope.launch { preferences.saveReadingFontSize(_readingFontSize.value) } }
    fun updateReadingHorizontalPadding(padding: Float) { _readingHorizontalPadding.value = padding.coerceIn(8f, 48f); viewModelScope.launch { preferences.saveReadingHorizontalPadding(_readingHorizontalPadding.value) } }
    fun updateLoggingEnabled(enabled: Boolean) { _loggingEnabled.value = enabled; viewModelScope.launch { preferences.saveLoggingEnabled(enabled) } }
    fun updateBookshelfSortByRecent(enabled: Boolean) { _bookshelfSortByRecent.value = enabled; viewModelScope.launch { preferences.saveBookshelfSortByRecent(enabled); applyBooksFilterAndSort() } }
    fun updateReadingMode(mode: com.readapp.data.ReadingMode) { _readingMode.value = mode; viewModelScope.launch { preferences.saveReadingMode(mode) } }
    fun updateLockPageOnTTS(enabled: Boolean) { _lockPageOnTTS.value = enabled; viewModelScope.launch { preferences.saveLockPageOnTTS(enabled) } }
    fun updatePageTurningMode(mode: com.readapp.data.PageTurningMode) { _pageTurningMode.value = mode; viewModelScope.launch { preferences.savePageTurningMode(mode) } }
    fun updateDarkMode(enabled: Boolean) { _isDarkMode.value = enabled; viewModelScope.launch { preferences.saveIsDarkMode(enabled) } }
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
    fun toggleManualManga(url: String) {
        val current = _manualMangaUrls.value.toMutableSet()
        if (current.contains(url)) current.remove(url) else current.add(url)
        _manualMangaUrls.value = current
        viewModelScope.launch { preferences.saveManualMangaUrls(current.joinToString(";")) }
    }
    fun updateForceMangaProxy(enabled: Boolean) {
        _forceMangaProxy.value = enabled
        viewModelScope.launch { preferences.saveForceMangaProxy(enabled) }
    }
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
    private fun isPunctuationOnly(sentence: String): Boolean {
        val punctuation = "，。！？；、\"“”‘’…—·"
        return sentence.trim().all { it in punctuation }
    }
    private fun parseSpeakerMapping(raw: String): Map<String, String> { if (raw.isBlank()) return emptyMap(); return runCatching { val obj = JSONObject(raw); obj.keys().asSequence().associateWith { key -> obj.optString(key) } }.getOrDefault(emptyMap()) }
    private fun serializeSpeakerMapping(mapping: Map<String, String>): String { val obj = JSONObject(); mapping.forEach { (key, value) -> obj.put(key, value) }; return obj.toString() }
    fun exportLogs(context: android.content.Context): android.net.Uri? { if (!logFile.exists()) return null; return runCatching { val exportFile = File(context.cacheDir, LOG_EXPORT_NAME); logFile.copyTo(exportFile, overwrite = true); androidx.core.content.FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", exportFile) }.getOrNull() }
    fun clearLogs() { runCatching { if (logFile.exists()) { logFile.writeText("") } } }
    private fun appendLog(message: String) { if (!_loggingEnabled.value) return; val timestamp = SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.getDefault()).format(Date()); val line = "[$timestamp] $message\n"; runCatching { logFile.appendText(line) } }

    private fun currentServerEndpoint(): String {
        return _serverAddress.value
    }

    private fun formatTime(milliseconds: Long): String {
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
