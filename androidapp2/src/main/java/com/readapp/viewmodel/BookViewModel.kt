package com.readapp.viewmodel

import android.app.Application
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
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
        resetPlayback()
        viewModelScope.launch { loadChapters(book) }
    }

    fun setCurrentChapter(index: Int) {
        if (index in chapters.indices) {
            currentChapterIndex = index
            resetPlayback()
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
        isPlaying = false
    }

    fun currentServerEndpoint(): String = if (serverAddress.endsWith("/api/5")) serverAddress else "$serverAddress/api/5"

    fun login(server: String, username: String, password: String, onSuccess: () -> Unit) {
        viewModelScope.launch {
            isLoading = true
            errorMessage = null
            val normalized = if (server.contains("/api/")) server else "$server/api/5"
            val result = repository.login(normalized, publicServerAddress.ifBlank { null }, username, password)
            result.onSuccess {
                accessToken = it.accessToken
                this@BookViewModel.username = username
                preferences.saveAccessToken(it.accessToken)
                preferences.saveUsername(username)
                preferences.saveServerUrl(normalized)
                loadTtsEngines()
                refreshBooks()
                onSuccess()
            }.onFailure { error ->
                errorMessage = error.message
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
            defaultResult.onSuccess { defaultId ->
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
        }.onFailure { error ->
            errorMessage = error.message
        }
    }

    private suspend fun ensureCurrentChapterContent(): String? {
        val book = selectedBook ?: return null
        val bookUrl = book.bookUrl ?: return null
        val index = currentChapterIndex
        val cached = chapters.getOrNull(index)?.content
        if (!cached.isNullOrBlank()) return cached
        val contentResult = repository.fetchChapterContent(currentServerEndpoint(), publicServerAddress.ifBlank { null }, accessToken, bookUrl, book.origin, index)
        return contentResult.getOrElse {
            errorMessage = it.message
            null
        }
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
        val Factory: androidx.lifecycle.ViewModelProvider.Factory = androidx.lifecycle.viewmodel.initializer {
            val application = (this[androidx.lifecycle.ViewModelProvider.AndroidViewModelFactory.APPLICATION_KEY] as Application)
            BookViewModel(application)
        }
    }
}
