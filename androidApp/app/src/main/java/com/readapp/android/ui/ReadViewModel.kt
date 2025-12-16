package com.readapp.android.ui

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Player
import com.readapp.android.data.ReadApiService
import com.readapp.android.data.ReadRepository
import com.readapp.android.data.UserPreferences
import com.readapp.android.model.Book
import com.readapp.android.model.BookChapter
import com.readapp.android.model.HttpTTS
import com.readapp.android.media.PlayerHolder
import com.readapp.android.media.ReadAudioService
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

class ReadViewModel(private val context: Context) : ViewModel() {

    private val preferences = UserPreferences(context)
    private val repository = ReadRepository { endpoint ->
        ReadApiService.create(endpoint) { _uiState.value.accessToken }
    }
    private val player = PlayerHolder.get(context)
    private val chapterContentCache = mutableMapOf<Int, String>()
    private val preloadingChapters = mutableSetOf<Int>()
    private var allBooks: List<Book> = emptyList()

    private val _uiState = MutableStateFlow(ReadUiState())
    val uiState: StateFlow<ReadUiState> = _uiState

    init {
        viewModelScope.launch {
            val server = preferences.serverUrl.first()
            val public = preferences.publicServerUrl.first()
            val token = preferences.accessToken.first()
            val username = preferences.username.first()
            val fontScale = preferences.fontScale.first()
            val lineSpacing = preferences.lineSpacing.first()
            val sortByRecent = preferences.sortByRecent.first()
            val sortAscending = preferences.sortAscending.first()
            val reverseChapters = preferences.reverseChapterList.first()
            val selectedTtsId = preferences.selectedTtsId.first()
            val speechRate = preferences.speechRate.first()
            val preloadSegments = preferences.preloadSegments.first()
            _uiState.update {
                it.copy(
                    serverUrl = server,
                    publicServerUrl = public,
                    accessToken = token,
                    username = username,
                    fontScale = fontScale,
                    lineSpacing = lineSpacing,
                    sortByRecent = sortByRecent,
                    sortAscending = sortAscending,
                    reverseChapterList = reverseChapters,
                    selectedTtsId = selectedTtsId.ifBlank { null },
                    speechRate = speechRate,
                    preloadSegments = preloadSegments,
                    isLoggedIn = token.isNotBlank()
                )
            }
            if (token.isNotBlank()) {
                fetchBooks()
                fetchTtsOptions()
            }
        }
        player.addListener(object : Player.Listener {
            override fun onPlaybackStateChanged(playbackState: Int) {
                if (playbackState == Player.STATE_ENDED || playbackState == Player.STATE_IDLE) {
                    _uiState.update { it.copy(isSpeaking = false) }
                }
            }

            override fun onPlayWhenReadyChanged(playWhenReady: Boolean, reason: Int) {
                if (!playWhenReady) {
                    _uiState.update { it.copy(isSpeaking = false) }
                }
            }

            override fun onMediaItemTransition(mediaItem: MediaItem?, reason: Int) {
                mediaItem?.mediaId?.let { id ->
                    val segment = SpeechSegment.fromMediaId(id)
                    val nextContent = segment?.chapterIndex?.let { chapterContentCache[it] }
                    val nextParagraphs = nextContent?.let { parseParagraphs(it) }
                    updateParagraphContext(
                        chapterIndex = segment?.chapterIndex ?: _uiState.value.currentChapterIndex,
                        paragraphIndex = segment?.paragraphIndex ?: _uiState.value.currentParagraphIndex,
                        paragraphs = nextParagraphs ?: _uiState.value.currentParagraphs,
                        chapterContent = nextContent ?: _uiState.value.currentChapterContent,
                        keepSpeaking = true
                    )
                    segment?.chapterIndex?.let { current ->
                        viewModelScope.launch { maybePreloadNextChapter(current) }
                    }
                }
            }
        })
    }

    fun updateServers(serverUrl: String, publicUrl: String?) {
        _uiState.update { it.copy(serverUrl = serverUrl, publicServerUrl = publicUrl.orEmpty()) }
        viewModelScope.launch(Dispatchers.IO) {
            preferences.saveServerUrl(serverUrl)
            preferences.savePublicServerUrl(publicUrl.orEmpty())
        }
    }

    fun login(username: String, password: String) {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, errorMessage = null) }
            val baseUrl = _uiState.value.serverUrl.ifBlank { "http://127.0.0.1:8080/api/5" }
            val result = repository.login(baseUrl, _uiState.value.publicServerUrl.ifBlank { null }, username, password)
            result.fold(
                onSuccess = { response ->
                    preferences.saveAccessToken(response.accessToken)
                    preferences.saveUsername(username)
                    _uiState.update {
                        it.copy(
                            accessToken = response.accessToken,
                            username = username,
                            isLoggedIn = true,
                            isLoading = false
                        )
                    }
                    fetchBooks()
                    fetchTtsOptions()
                },
                onFailure = { error ->
                    _uiState.update { it.copy(isLoading = false, errorMessage = error.message) }
                }
            )
        }
    }

    fun fetchBooks() {
        viewModelScope.launch {
            val token = _uiState.value.accessToken
            if (token.isBlank()) return@launch
            _uiState.update { it.copy(isLoading = true, errorMessage = null) }
            val baseUrl = _uiState.value.serverUrl.ifBlank { "http://127.0.0.1:8080/api/5" }
            val result = repository.fetchBooks(baseUrl, _uiState.value.publicServerUrl.ifBlank { null }, token)
            result.fold(
                onSuccess = { books ->
                    allBooks = books
                    _uiState.update { state ->
                        val filtered = applyBookFilters(allBooks, state.searchQuery)
                        state.copy(
                            isLoading = false,
                            books = applyBookSort(filtered, state.sortByRecent, state.sortAscending)
                        )
                    }
                },
                onFailure = { error ->
                    _uiState.update { it.copy(isLoading = false, errorMessage = error.message) }
                }
            )
        }
    }

    fun selectBook(book: Book) {
        _uiState.update {
            it.copy(
                selectedBook = book,
                chapters = emptyList(),
                currentChapterContent = "",
                currentChapterIndex = book.durChapterIndex ?: 0,
                isNearChapterEnd = false,
                upcomingChapterIndex = null
            )
        }
        fetchChapterList(book)
    }

    fun fetchChapterList(book: Book) {
        viewModelScope.launch {
            val token = _uiState.value.accessToken
            val baseUrl = _uiState.value.serverUrl.ifBlank { "http://127.0.0.1:8080/api/5" }
            _uiState.update { it.copy(isLoading = true, errorMessage = null) }
            val result = repository.fetchChapterList(
                baseUrl,
                _uiState.value.publicServerUrl.ifBlank { null },
                token,
                book.bookUrl ?: return@launch,
                book.origin
            )
            result.fold(
                onSuccess = { chapters ->
                    val ordered = if (_uiState.value.reverseChapterList) chapters.reversed() else chapters
                    val index = _uiState.value.currentChapterIndex ?: book.durChapterIndex ?: 0
                    val safeIndex = index.coerceIn(0, ordered.lastIndex)
                    _uiState.update { it.copy(isLoading = false, chapters = ordered, currentChapterIndex = safeIndex) }
                    if (chapters.isNotEmpty()) {
                        openChapter(safeIndex)
                    }
                },
                onFailure = { error ->
                    _uiState.update { it.copy(isLoading = false, errorMessage = error.message) }
                }
            )
        }
    }

    fun openChapter(index: Int) {
        val book = _uiState.value.selectedBook ?: return
        viewModelScope.launch {
            val token = _uiState.value.accessToken
            val baseUrl = _uiState.value.serverUrl.ifBlank { "http://127.0.0.1:8080/api/5" }
            _uiState.update { it.copy(isLoading = true, errorMessage = null, isSpeaking = false) }
            val result = repository.fetchChapterContent(
                baseUrl,
                _uiState.value.publicServerUrl.ifBlank { null },
                token,
                book.bookUrl ?: return@launch,
                book.origin,
                index
            )
            result.fold(
                onSuccess = { content ->
                    chapterContentCache[index] = content
                    val paragraphs = parseParagraphs(content)
                    _uiState.update {
                        val nearState = evaluateEndState(index, 0, paragraphs)
                        it.copy(
                            isLoading = false,
                            currentChapterContent = content,
                            currentChapterIndex = index,
                            currentParagraphs = paragraphs,
                            currentParagraphIndex = 0,
                            isNearChapterEnd = nearState.first,
                            upcomingChapterIndex = nearState.second
                        )
                    }
                    repository.saveBookProgress(baseUrl, token, book.bookUrl ?: return@fold, index, 0.0, book.durChapterTitle)
                },
                onFailure = { error ->
                    _uiState.update { it.copy(isLoading = false, errorMessage = error.message) }
                }
            )
        }
    }

    fun fetchTtsOptions() {
        viewModelScope.launch {
            val token = _uiState.value.accessToken
            if (token.isBlank()) return@launch
            val baseUrl = _uiState.value.serverUrl.ifBlank { "http://127.0.0.1:8080/api/5" }
            val ttsList = repository.fetchTtsEngines(baseUrl, _uiState.value.publicServerUrl.ifBlank { null }, token)
            ttsList.onSuccess { list ->
                _uiState.update { it.copy(ttsEngines = list) }
            }
            val defaultTts = repository.fetchDefaultTts(baseUrl, _uiState.value.publicServerUrl.ifBlank { null }, token)
            defaultTts.onSuccess { id ->
                _uiState.update { current ->
                    val selected = current.selectedTtsId ?: id
                    current.copy(defaultTtsId = id, selectedTtsId = selected)
                }
            }
        }
    }

    fun speakCurrentChapter() {
        val start = _uiState.value.currentParagraphIndex
        speakFromParagraph(start)
    }

    fun speakFromParagraph(paragraphIndex: Int) {
        viewModelScope.launch {
            val token = _uiState.value.accessToken
            val book = _uiState.value.selectedBook ?: return@launch
            val baseUrl = _uiState.value.serverUrl.ifBlank { "http://127.0.0.1:8080/api/5" }
            val ttsId = _uiState.value.selectedTtsId
                ?: _uiState.value.defaultTtsId
                ?: _uiState.value.ttsEngines.firstOrNull()?.id
                ?: return@launch
            val index = _uiState.value.currentChapterIndex ?: return@launch
            val currentContent = chapterContentCache[index] ?: _uiState.value.currentChapterContent
            val currentParagraphs = _uiState.value.currentParagraphs.ifEmpty { parseParagraphs(currentContent) }
            if (currentParagraphs.isEmpty() || token.isBlank()) return@launch

            val mediaItems = mutableListOf<MediaItem>()
            val speechSegments = mutableListOf<SpeechSegment>()

            currentParagraphs.drop(paragraphIndex).forEachIndexed { offset, paragraph ->
                val segmentIndex = paragraphIndex + offset
                val item = buildMediaItem(baseUrl, token, ttsId, paragraph, book, index, segmentIndex)
                if (item != null) {
                    mediaItems.add(item)
                    speechSegments.add(SpeechSegment(index, segmentIndex))
                }
            }

            val preload = _uiState.value.preloadSegments
            val chapters = _uiState.value.chapters
            val preloaded = mutableListOf<Int>()
            if (preload > 0 && chapters.isNotEmpty()) {
                for (offset in 1..preload) {
                    val nextIndex = index + offset
                    if (nextIndex > chapters.lastIndex) break
                    val content = getOrFetchChapterContent(nextIndex, book)
                    if (content.isNullOrBlank()) continue
                    val paragraphs = parseParagraphs(content)
                    paragraphs.forEachIndexed { pIndex, paragraph ->
                        val item = buildMediaItem(baseUrl, token, ttsId, paragraph, book, nextIndex, pIndex)
                        if (item != null) {
                            mediaItems.add(item)
                            speechSegments.add(SpeechSegment(nextIndex, pIndex))
                        }
                    }
                    preloaded.add(nextIndex)
                }
            }

            if (mediaItems.isNotEmpty()) {
                player.setMediaItems(mediaItems)
                player.prepare()
                ReadAudioService.startService(context)
                player.play()
                updateParagraphContext(index, paragraphIndex, currentParagraphs, currentContent, keepSpeaking = true)
                _uiState.update {
                    it.copy(
                        preloadedChapters = preloaded,
                        speechSegments = speechSegments
                    )
                }
            }
        }
    }

    fun stopSpeaking() {
        player.pause()
        _uiState.update { it.copy(isSpeaking = false) }
    }

    fun toggleSpeaking() {
        if (_uiState.value.isSpeaking) {
            stopSpeaking()
        } else {
            speakCurrentChapter()
        }
    }

    fun exitReader() {
        stopSpeaking()
        preloadingChapters.clear()
        _uiState.update {
            it.copy(
                selectedBook = null,
                chapters = emptyList(),
                currentChapterContent = "",
                currentChapterIndex = null,
                currentParagraphs = emptyList(),
                currentParagraphIndex = 0,
                preloadedChapters = emptyList(),
                speechSegments = emptyList(),
                isNearChapterEnd = false,
                upcomingChapterIndex = null
            )
        }
    }

    fun updateFontScale(value: Float) {
        viewModelScope.launch(Dispatchers.IO) {
            val clamped = value.coerceIn(0.8f, 1.6f)
            preferences.saveFontScale(clamped)
            _uiState.update { it.copy(fontScale = clamped) }
        }
    }

    fun updateLineSpacing(value: Float) {
        viewModelScope.launch(Dispatchers.IO) {
            val clamped = value.coerceIn(1.0f, 2.0f)
            preferences.saveLineSpacing(clamped)
            _uiState.update { it.copy(lineSpacing = clamped) }
        }
    }

    fun setSortByRecent(enabled: Boolean) {
        viewModelScope.launch(Dispatchers.IO) {
            preferences.saveSortByRecent(enabled)
            _uiState.update { state ->
                val filtered = applyBookFilters(allBooks, state.searchQuery)
                state.copy(
                    sortByRecent = enabled,
                    books = applyBookSort(filtered, enabled, state.sortAscending)
                )
            }
        }
    }

    fun setSortAscending(enabled: Boolean) {
        viewModelScope.launch(Dispatchers.IO) {
            preferences.saveSortAscending(enabled)
            _uiState.update { state ->
                val filtered = applyBookFilters(allBooks, state.searchQuery)
                state.copy(books = applyBookSort(filtered, state.sortByRecent, enabled), sortAscending = enabled)
            }
        }
    }

    fun setReverseChapterList(enabled: Boolean) {
        viewModelScope.launch(Dispatchers.IO) {
            preferences.saveReverseChapterList(enabled)
            val current = _uiState.value.chapters
            val reversed = if (enabled == _uiState.value.reverseChapterList) current else current.reversed()
            val currentIdx = _uiState.value.currentChapterIndex ?: 0
            val mappedIndex = if (enabled == _uiState.value.reverseChapterList) currentIdx else (reversed.lastIndex - currentIdx)
            _uiState.update {
                it.copy(reverseChapterList = enabled, chapters = reversed, currentChapterIndex = mappedIndex)
            }
        }
    }

    fun updateSearchQuery(query: String) {
        _uiState.update { state ->
            val filtered = applyBookFilters(allBooks, query)
            state.copy(searchQuery = query, books = applyBookSort(filtered, state.sortByRecent, state.sortAscending))
        }
    }

    fun updateSelectedTts(ttsId: String) {
        viewModelScope.launch(Dispatchers.IO) {
            preferences.saveSelectedTtsId(ttsId)
            _uiState.update { it.copy(selectedTtsId = ttsId) }
        }
    }

    fun updateSpeechRate(value: Double) {
        viewModelScope.launch(Dispatchers.IO) {
            val clamped = value.coerceIn(0.6, 2.0)
            preferences.saveSpeechRate(clamped)
            _uiState.update { it.copy(speechRate = clamped) }
        }
    }

    fun updatePreloadSegments(value: Int) {
        viewModelScope.launch(Dispatchers.IO) {
            val clamped = value.coerceIn(0, 3)
            preferences.savePreloadSegments(clamped)
            _uiState.update { it.copy(preloadSegments = clamped) }
        }
    }

    fun toggleImmersiveMode() {
        _uiState.update { it.copy(isImmersiveMode = !it.isImmersiveMode) }
    }

    fun jumpToParagraph(targetIndex: Int) {
        val chapterIndex = _uiState.value.currentChapterIndex ?: return
        val segments = _uiState.value.speechSegments
        val segmentPosition = segments.indexOfFirst { it.chapterIndex == chapterIndex && it.paragraphIndex == targetIndex }
        if (segmentPosition >= 0 && segmentPosition < player.mediaItemCount) {
            player.seekToDefaultPosition(segmentPosition)
            player.play()
            updateParagraphContext(chapterIndex, targetIndex, _uiState.value.currentParagraphs, _uiState.value.currentChapterContent, keepSpeaking = true)
        } else {
            speakFromParagraph(targetIndex)
        }
    }

    fun clearLocalCaches() {
        chapterContentCache.clear()
        player.clearMediaItems()
        preloadingChapters.clear()
        _uiState.update {
            it.copy(
                currentChapterContent = "",
                currentParagraphs = emptyList(),
                currentParagraphIndex = 0,
                preloadedChapters = emptyList(),
                speechSegments = emptyList(),
                isSpeaking = false,
                isNearChapterEnd = false,
                upcomingChapterIndex = null
            )
        }
    }

    private fun applyBookFilters(books: List<Book>, query: String): List<Book> {
        if (query.isBlank()) return books
        val lower = query.lowercase()
        return books.filter {
            (it.name ?: "").lowercase().contains(lower) || (it.author ?: "").lowercase().contains(lower)
        }
    }

    private fun applyBookSort(books: List<Book>, sortByRecent: Boolean, sortAscending: Boolean): List<Book> {
        val sorted = if (sortByRecent) {
            books.sortedWith(compareByDescending<Book> { it.durChapterTime ?: 0L }.thenBy { it.name })
        } else {
            books.sortedWith(compareBy<Book> { it.name ?: "" }.thenBy { it.id })
        }
        return if (sortAscending) sorted else sorted.reversed()
    }

    override fun onCleared() {
        super.onCleared()
        if (!_uiState.value.isSpeaking) {
            player.clearMediaItems()
        }
    }

    private fun evaluateEndState(
        chapterIndex: Int?,
        paragraphIndex: Int,
        paragraphs: List<String>
    ): Pair<Boolean, Int?> {
        val nearEnd = paragraphs.isNotEmpty() && paragraphIndex >= (paragraphs.size - 2).coerceAtLeast(0)
        val nextChapter = if (nearEnd && chapterIndex != null && chapterIndex < _uiState.value.chapters.lastIndex) {
            chapterIndex + 1
        } else null
        return nearEnd to nextChapter
    }

    private fun updateParagraphContext(
        chapterIndex: Int?,
        paragraphIndex: Int,
        paragraphs: List<String>,
        chapterContent: String,
        keepSpeaking: Boolean
    ) {
        val (nearEnd, nextChapter) = evaluateEndState(chapterIndex, paragraphIndex, paragraphs)
        _uiState.update { state ->
            state.copy(
                currentChapterIndex = chapterIndex,
                currentParagraphIndex = paragraphIndex,
                currentParagraphs = paragraphs,
                currentChapterContent = chapterContent,
                isSpeaking = keepSpeaking,
                isNearChapterEnd = nearEnd,
                upcomingChapterIndex = if (nearEnd) nextChapter else null
            )
        }
        if (nearEnd && chapterIndex != null) {
            viewModelScope.launch { maybePreloadNextChapter(chapterIndex) }
        }
    }

    private suspend fun maybePreloadNextChapter(currentChapterIndex: Int) {
        val chapters = _uiState.value.chapters
        val book = _uiState.value.selectedBook ?: return
        val nextIndex = currentChapterIndex + 1
        if (nextIndex > chapters.lastIndex) return
        if (preloadingChapters.contains(nextIndex)) return
        if (_uiState.value.preloadedChapters.contains(nextIndex)) {
            _uiState.update { it.copy(upcomingChapterIndex = nextIndex) }
            return
        }
        preloadingChapters.add(nextIndex)
        val content = getOrFetchChapterContent(nextIndex, book)
        if (content.isNullOrBlank()) {
            preloadingChapters.remove(nextIndex)
            return
        }
        val paragraphs = parseParagraphs(content)
        val token = _uiState.value.accessToken
        val ttsId = resolveTtsId()
        val baseUrl = _uiState.value.serverUrl.ifBlank { "http://127.0.0.1:8080/api/5" }

        if (_uiState.value.isSpeaking && token.isNotBlank() && ttsId != null && paragraphs.isNotEmpty()) {
            val existing = _uiState.value.speechSegments.any { it.chapterIndex == nextIndex }
            if (!existing) {
                val items = paragraphs.mapIndexedNotNull { pIndex, text ->
                    buildMediaItem(baseUrl, token, ttsId, text, book, nextIndex, pIndex)
                }
                if (items.isNotEmpty()) {
                    player.addMediaItems(items)
                    val updatedSegments = _uiState.value.speechSegments + paragraphs.indices.map { SpeechSegment(nextIndex, it) }
                    _uiState.update {
                        it.copy(
                            speechSegments = updatedSegments,
                            preloadedChapters = (it.preloadedChapters + nextIndex).distinct(),
                            upcomingChapterIndex = nextIndex
                        )
                    }
                }
            }
        }
        if (!_uiState.value.preloadedChapters.contains(nextIndex)) {
            _uiState.update {
                it.copy(
                    preloadedChapters = (it.preloadedChapters + nextIndex).distinct(),
                    upcomingChapterIndex = nextIndex
                )
            }
        }
        preloadingChapters.remove(nextIndex)
    }

    private fun resolveTtsId(): String? {
        return _uiState.value.selectedTtsId
            ?: _uiState.value.defaultTtsId
            ?: _uiState.value.ttsEngines.firstOrNull()?.id
    }

    private fun buildMediaItem(
        baseUrl: String,
        token: String,
        ttsId: String,
        text: String,
        book: Book,
        chapterIndex: Int,
        paragraphIndex: Int
    ): MediaItem? {
        val chapters = _uiState.value.chapters
        val chapterTitle = chapters.getOrNull(chapterIndex)?.title ?: book.durChapterTitle.orEmpty()
        val url = repository.buildTtsAudioUrl(baseUrl, token, ttsId, text, _uiState.value.speechRate) ?: return null
        val metadata = MediaMetadata.Builder()
            .setTitle(book.name ?: "听书")
            .setSubtitle(
                listOf(
                    chapterTitle.ifBlank { "第 ${chapterIndex + 1} 章" },
                    "第 ${paragraphIndex + 1} 段"
                ).joinToString(" · ")
            )
            .build()
        return MediaItem.Builder()
            .setMediaId(SpeechSegment(chapterIndex, paragraphIndex).toMediaId())
            .setUri(url)
            .setMediaMetadata(metadata)
            .build()
    }

    private suspend fun getOrFetchChapterContent(index: Int, book: Book): String? {
        val cached = chapterContentCache[index]
        if (cached != null) return cached
        val token = _uiState.value.accessToken
        val baseUrl = _uiState.value.serverUrl.ifBlank { "http://127.0.0.1:8080/api/5" }
        val result = repository.fetchChapterContent(
            baseUrl,
            _uiState.value.publicServerUrl.ifBlank { null },
            token,
            book.bookUrl ?: return null,
            book.origin,
            index
        )
        val content = result.getOrNull()
        if (!content.isNullOrBlank()) {
            chapterContentCache[index] = content
        }
        return content
    }

    private fun parseParagraphs(content: String): List<String> {
        return content.split("\n").map { it.trim() }.filter { it.isNotBlank() }
    }
}

class ReadViewModelFactory(private val context: Context) : ViewModelProvider.Factory {
    override fun <T : ViewModel> create(modelClass: Class<T>): T {
        if (modelClass.isAssignableFrom(ReadViewModel::class.java)) {
            @Suppress("UNCHECKED_CAST")
            return ReadViewModel(context) as T
        }
        throw IllegalArgumentException("Unknown ViewModel class")
    }
}

data class ReadUiState(
    val serverUrl: String = "http://127.0.0.1:8080/api/5",
    val publicServerUrl: String = "",
    val username: String = "",
    val accessToken: String = "",
    val isLoggedIn: Boolean = false,
    val isLoading: Boolean = false,
    val errorMessage: String? = null,
    val books: List<Book> = emptyList(),
    val searchQuery: String = "",
    val selectedBook: Book? = null,
    val chapters: List<BookChapter> = emptyList(),
    val currentChapterIndex: Int? = null,
    val currentChapterContent: String = "",
    val currentParagraphs: List<String> = emptyList(),
    val currentParagraphIndex: Int = 0,
    val ttsEngines: List<HttpTTS> = emptyList(),
    val defaultTtsId: String? = null,
    val selectedTtsId: String? = null,
    val isSpeaking: Boolean = false,
    val speechRate: Double = 1.0,
    val fontScale: Float = 1.0f,
    val lineSpacing: Float = 1.4f,
    val sortByRecent: Boolean = false,
    val sortAscending: Boolean = true,
    val reverseChapterList: Boolean = false,
    val preloadSegments: Int = 0,
    val preloadedChapters: List<Int> = emptyList(),
    val speechSegments: List<SpeechSegment> = emptyList(),
    val isImmersiveMode: Boolean = false,
    val isNearChapterEnd: Boolean = false,
    val upcomingChapterIndex: Int? = null
)

data class SpeechSegment(val chapterIndex: Int, val paragraphIndex: Int) {
    fun toMediaId(): String = "$chapterIndex:$paragraphIndex"

    companion object {
        fun fromMediaId(id: String): SpeechSegment? {
            val parts = id.split(":")
            if (parts.size != 2) return null
            return SpeechSegment(parts[0].toIntOrNull() ?: return null, parts[1].toIntOrNull() ?: return null)
        }
    }
}
