package com.readapp.viewmodel

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.readapp.data.LocalSourceCache
import com.readapp.data.ReadApiService
import com.readapp.data.ReaderApiService
import com.readapp.data.ReadRepository
import com.readapp.data.RemoteDataSourceFactory
import com.readapp.data.UserPreferences
import com.readapp.data.model.Book
import com.readapp.data.model.BookSource
import com.readapp.data.repo.BookRepository
import com.readapp.data.repo.SourceRepository
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.flow.StateFlow

@OptIn(FlowPreview::class)
class SourceViewModel(application: Application) : AndroidViewModel(application) {

    private val userPreferences = UserPreferences(application)
    private val accessTokenState = MutableStateFlow("")
    private val apiFactory: (String) -> ReadApiService = { endpoint ->
        ReadApiService.create(endpoint) { accessTokenState.value }
    }
    private val readerApiFactory: (String) -> ReaderApiService = { endpoint ->
        ReaderApiService.create(endpoint) { accessTokenState.value }
    }
    private val remoteDataSourceFactory = RemoteDataSourceFactory(apiFactory, readerApiFactory)
    private val readRepository = ReadRepository(
        apiFactory = apiFactory,
        readerApiFactory = readerApiFactory
    )
    val bookRepository = BookRepository(remoteDataSourceFactory, readRepository)
    private val localSourceCache = LocalSourceCache(application)
    private val sourceRepository = SourceRepository(readRepository, localSourceCache)

    // Source List State
    private val _sources = MutableStateFlow<List<BookSource>>(emptyList())
    val sources = _sources.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading = _isLoading.asStateFlow()

    private val _errorMessage = MutableStateFlow<String?>(null)
    val errorMessage = _errorMessage.asStateFlow()

    // Global Search State
    private val _searchText = MutableStateFlow("")
    val searchText = _searchText.asStateFlow()

    private val _searchResults = MutableStateFlow<List<Book>>(emptyList())
    val searchResults = _searchResults.asStateFlow()

    private val _isGlobalSearching = MutableStateFlow(false)
    val isGlobalSearching = _isGlobalSearching.asStateFlow()

    data class ExploreState(
        val books: List<Book> = emptyList(),
        val isLoading: Boolean = false,
        val currentPage: Int = 1,
        val canLoadMore: Boolean = true,
        val hasLoaded: Boolean = false
    )

    private val exploreStates = mutableMapOf<String, MutableStateFlow<ExploreState>>()

    init {
        viewModelScope.launch {
            userPreferences.accessToken.collect { token ->
                accessTokenState.value = token
            }
        }
        // fetchSources is now triggered by UI or searchText changes
        
        viewModelScope.launch {
            _searchText
                .debounce(800) // Debounce search input
                .collectLatest { query ->
                    if (query.isBlank()) {
                        _searchResults.value = emptyList()
                        _isGlobalSearching.value = false
                    } else {
                        performGlobalSearch(query)
                    }
                }
        }
    }

    fun onSearchTextChanged(text: String) {
        _searchText.value = text
    }

    fun getExploreState(key: String): StateFlow<ExploreState> {
        return exploreStates.getOrPut(key) { MutableStateFlow(ExploreState()) }.asStateFlow()
    }

    fun loadExploreIfNeeded(key: String, bookSourceUrl: String, ruleFindUrl: String) {
        val stateFlow = exploreStates.getOrPut(key) { MutableStateFlow(ExploreState()) }
        if (stateFlow.value.hasLoaded || stateFlow.value.isLoading) return
        loadExplore(key, bookSourceUrl, ruleFindUrl, loadMore = false)
    }

    fun loadMoreExplore(key: String, bookSourceUrl: String, ruleFindUrl: String) {
        val stateFlow = exploreStates.getOrPut(key) { MutableStateFlow(ExploreState()) }
        val state = stateFlow.value
        if (state.isLoading || !state.canLoadMore) return
        loadExplore(key, bookSourceUrl, ruleFindUrl, loadMore = true)
    }

    private fun loadExplore(key: String, bookSourceUrl: String, ruleFindUrl: String, loadMore: Boolean) {
        val stateFlow = exploreStates.getOrPut(key) { MutableStateFlow(ExploreState()) }
        val state = stateFlow.value
        val nextPage = if (loadMore) state.currentPage + 1 else 1
        val startBooks = if (loadMore) state.books else emptyList()

        stateFlow.value = state.copy(isLoading = true)
        viewModelScope.launch {
            val result = exploreBook(bookSourceUrl, ruleFindUrl, nextPage)
            result.onSuccess { newBooks ->
                val merged = startBooks + newBooks
                val canLoadMore = newBooks.isNotEmpty() && newBooks.size >= 20
                stateFlow.value = stateFlow.value.copy(
                    books = merged,
                    isLoading = false,
                    currentPage = nextPage,
                    canLoadMore = canLoadMore,
                    hasLoaded = true
                )
            }.onFailure {
                stateFlow.value = stateFlow.value.copy(isLoading = false)
            }
        }
    }

    private fun performGlobalSearch(query: String) {
        if (query.isBlank()) return
        viewModelScope.launch {
            _isGlobalSearching.value = true
            _searchResults.value = emptyList() // Clear previous results

            val currentSources = _sources.value // Get currently loaded sources
            val enabledSources = currentSources.filter { it.enabled }

            val (baseUrl, publicUrl, token) = userPreferences.getCredentials()
            if (token == null) {
                _errorMessage.value = "Not logged in"
                _isGlobalSearching.value = false
                return@launch
            }

            val deferredResults = enabledSources.map { source ->
                async {
                    bookRepository.searchBook(
                        baseUrl = baseUrl,
                        publicUrl = publicUrl,
                        accessToken = token,
                        keyword = query,
                        bookSourceUrl = source.bookSourceUrl,
                        page = 1 // Assuming only first page for global search initially
                    ).getOrNull()?.map { book ->
                        book.copy(sourceDisplayName = source.bookSourceName)
                    } ?: emptyList()
                }
            }

            val allResults = deferredResults.awaitAll().flatten()
            _searchResults.value = allResults
            _isGlobalSearching.value = false
        }
    }

    fun fetchSources() {
        viewModelScope.launch {
            _isLoading.value = true
            _errorMessage.value = null
            val (baseUrl, publicUrl, token) = userPreferences.getCredentials()
            if (token == null) {
                _errorMessage.value = "Not logged in"
                _isLoading.value = false
                return@launch
            }

            sourceRepository.getBookSources(
                context = getApplication<Application>().applicationContext,
                baseUrl = baseUrl,
                publicUrl = publicUrl,
                accessToken = token
            ).collect { result ->
                result.onSuccess {
                    _sources.value = it
                    _isLoading.value = false // Stop loading once we have any data
                }.onFailure {
                    if (_sources.value.isEmpty()) { // Only show error if we have nothing to display
                        _errorMessage.value = it.message ?: "Failed to load sources"
                    }
                    _isLoading.value = false
                }
            }
        }
    }

    fun deleteSource(source: BookSource) {
        val currentSources = _sources.value
        _sources.value = currentSources.filter { it.bookSourceUrl != source.bookSourceUrl }

        viewModelScope.launch {
            val (serverUrl, publicUrl, token) = userPreferences.getCredentials()
            if (token == null) {
                _errorMessage.value = "Not logged in"
                return@launch
            }
            val result = sourceRepository.deleteBookSource(
                context = getApplication<Application>().applicationContext,
                baseUrl = serverUrl,
                publicUrl = publicUrl,
                accessToken = token,
                source = source
            )
            if (result.isFailure) {
                _sources.value = currentSources // Revert
                _errorMessage.value = result.exceptionOrNull()?.message ?: "删除失败"
            }
        }
    }

    fun toggleSource(source: BookSource) {
        val currentSources = _sources.value
        val newSources = currentSources.map {
            if (it.bookSourceUrl == source.bookSourceUrl) it.copy(enabled = !it.enabled) else it
        }
        _sources.value = newSources

        viewModelScope.launch {
            val (serverUrl, publicUrl, token) = userPreferences.getCredentials()
            if (token == null) {
                _errorMessage.value = "Not logged in"
                return@launch
            }
            val result = sourceRepository.toggleBookSource(
                context = getApplication<Application>().applicationContext,
                baseUrl = serverUrl,
                publicUrl = publicUrl,
                accessToken = token,
                source = source,
                isEnabled = !source.enabled
            )
            if (result.isFailure) {
                _sources.value = currentSources // Revert
                _errorMessage.value = result.exceptionOrNull()?.message ?: "操作失败"
            }
        }
    }

    suspend fun getSourceDetail(id: String): String? {
        val (serverUrl, publicUrl, token) = userPreferences.getCredentials()
        if (token == null) return null
        return sourceRepository.getBookSourceDetail(serverUrl, publicUrl, token, id).getOrNull()
    }

    suspend fun fetchExploreKinds(bookSourceUrl: String): String? {
        val (serverUrl, publicUrl, token) = userPreferences.getCredentials()
        if (token == null) return null
        return sourceRepository.fetchExploreKinds(serverUrl, publicUrl, token, bookSourceUrl).getOrNull()
    }

    suspend fun exploreBook(bookSourceUrl: String, ruleFindUrl: String, page: Int): Result<List<Book>> {
        val (serverUrl, publicUrl, token) = userPreferences.getCredentials()
        if (token == null) return Result.failure(IllegalStateException("Not logged in"))
        return sourceRepository.exploreBook(serverUrl, publicUrl, token, bookSourceUrl, ruleFindUrl, page)
    }

    suspend fun saveSource(jsonContent: String): Result<Any> {
        val (serverUrl, publicUrl, token) = userPreferences.getCredentials()
        if (token == null) return Result.failure(IllegalStateException("Not logged in"))
        return sourceRepository.saveBookSource(serverUrl, publicUrl, token, jsonContent)
    }

    fun saveBookToBookshelf(book: Book) {
        viewModelScope.launch {
            val (baseUrl, publicUrl, token) = userPreferences.getCredentials()
            if (token == null) {
                _errorMessage.value = "Not logged in"
                return@launch
            }

            // Note: Currently no specific error handling for saveBook, just logs for now.
            // A separate StateFlow could be used for UI feedback if needed.
            bookRepository.saveBook(
                baseUrl = baseUrl,
                publicUrl = publicUrl,
                accessToken = token,
                book = book
            ).onFailure {
                _errorMessage.value = it.message ?: "Failed to add book to bookshelf"
            }
        }
    }
    
    companion object {
        val Factory: ViewModelProvider.Factory = viewModelFactory {
            initializer {
                val application = this[ViewModelProvider.AndroidViewModelFactory.APPLICATION_KEY] as Application
                SourceViewModel(application)
            }
        }
    }
}
