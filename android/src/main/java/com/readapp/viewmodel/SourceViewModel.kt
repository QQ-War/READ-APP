package com.readapp.viewmodel

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.readapp.data.ReadApiService
import com.readapp.data.ReadRepository
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

@OptIn(FlowPreview::class)
class SourceViewModel(application: Application) : AndroidViewModel(application) {

    private val userPreferences = UserPreferences(application)
    private val accessTokenState = MutableStateFlow("")
    private val readRepository = ReadRepository { endpoint ->
        ReadApiService.create(endpoint) { accessTokenState.value }
    }
    val bookRepository = BookRepository(readRepository)
    private val sourceRepository = SourceRepository(readRepository)

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

            val serverUrl = userPreferences.serverUrl.first()
            val publicUrl = userPreferences.publicServerUrl.first().ifBlank { null }
            val token = userPreferences.accessToken.first()

            if (token.isBlank()) {
                _errorMessage.value = "Not logged in"
                _isLoading.value = false
                return@launch
            }

            sourceRepository.getBookSources(
                context = getApplication<Application>().applicationContext,
                baseUrl = serverUrl,
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
        deleteSourceById(source.bookSourceUrl)
    }

    fun deleteSourceById(id: String) {
        val currentSources = _sources.value
        _sources.value = currentSources.filter { it.bookSourceUrl != id }

        viewModelScope.launch {
            val serverUrl = userPreferences.serverUrl.first()
            val publicUrl = userPreferences.publicServerUrl.first().ifBlank { null }
            val token = userPreferences.accessToken.first()

            val result = sourceRepository.deleteBookSource(
                context = getApplication<Application>().applicationContext,
                baseUrl = serverUrl,
                publicUrl = publicUrl,
                accessToken = token,
                id = id
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
            val serverUrl = userPreferences.serverUrl.first()
            val publicUrl = userPreferences.publicServerUrl.first().ifBlank { null }
            val token = userPreferences.accessToken.first()

            val result = sourceRepository.toggleBookSource(
                context = getApplication<Application>().applicationContext,
                baseUrl = serverUrl,
                publicUrl = publicUrl,
                accessToken = token,
                id = source.bookSourceUrl,
                isEnabled = !source.enabled
            )
            if (result.isFailure) {
                _sources.value = currentSources // Revert
                _errorMessage.value = result.exceptionOrNull()?.message ?: "操作失败"
            }
        }
    }

    suspend fun getSourceDetail(id: String): String? {
        val serverUrl = userPreferences.serverUrl.first()
        val publicUrl = userPreferences.publicServerUrl.first().ifBlank { null }
        val token = userPreferences.accessToken.first()

        return sourceRepository.getBookSourceDetail(serverUrl, publicUrl, token, id).getOrNull()
    }

    suspend fun fetchExploreKinds(bookSourceUrl: String): String? {
        val serverUrl = userPreferences.serverUrl.first()
        val publicUrl = userPreferences.publicServerUrl.first().ifBlank { null }
        val token = userPreferences.accessToken.first()

        return sourceRepository.fetchExploreKinds(serverUrl, publicUrl, token, bookSourceUrl).getOrNull()
    }

    suspend fun exploreBook(bookSourceUrl: String, ruleFindUrl: String, page: Int): Result<List<Book>> {
        val serverUrl = userPreferences.serverUrl.first()
        val publicUrl = userPreferences.publicServerUrl.first().ifBlank { null }
        val token = userPreferences.accessToken.first()

        return sourceRepository.exploreBook(serverUrl, publicUrl, token, bookSourceUrl, ruleFindUrl, page)
    }

    suspend fun saveSource(jsonContent: String): Result<Any> {
        val serverUrl = userPreferences.serverUrl.first()
        val publicUrl = userPreferences.publicServerUrl.first().ifBlank { null }
        val token = userPreferences.accessToken.first()

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
    
    // Helper to get credentials for factory
    suspend fun UserPreferences.getCredentials(): Triple<String, String?, String?> {
        val serverUrl = userPreferences.serverUrl.first()
        val publicUrl = userPreferences.publicServerUrl.first().ifBlank { null }
        val token = accessToken.first().ifBlank { null }
        return Triple(serverUrl, publicUrl, token)
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
