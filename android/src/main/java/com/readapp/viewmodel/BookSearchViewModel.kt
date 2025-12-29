package com.readapp.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.readapp.data.ReadRepository
import com.readapp.data.UserPreferences
import com.readapp.data.model.Book
import com.readapp.data.model.BookSource
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

class BookSearchViewModel(
    val bookSource: BookSource,
    private val repository: ReadRepository,
    private val userPreferences: UserPreferences
) : ViewModel() {

    private val _uiState = MutableStateFlow<BookSearchUiState>(BookSearchUiState.Success(emptyList()))
    val uiState = _uiState.asStateFlow()

    private val _searchText = MutableStateFlow("")
    val searchText = _searchText.asStateFlow()

    private var currentPage = 1
    private var canLoadMore = true

    val canLoadMoreState: Boolean
        get() = canLoadMore

    val isLoading: Boolean
        get() = _uiState.value is BookSearchUiState.Loading

    fun onSearchTextChanged(text: String) {
        _searchText.value = text
    }

    fun performSearch(isNewSearch: Boolean = true) {
        if (isNewSearch) {
            currentPage = 1
            canLoadMore = true
            _uiState.value = BookSearchUiState.Success(emptyList())
        }

        if (!canLoadMore) return
        if (_searchText.value.isBlank()) {
            _uiState.value = BookSearchUiState.Success(emptyList())
            return
        }

        viewModelScope.launch {
            _uiState.value = BookSearchUiState.Loading

            val (baseUrl, publicUrl, token) = userPreferences.getCredentials()
            if (token == null) {
                _uiState.value = BookSearchUiState.Error("Not logged in")
                return@launch
            }

            repository.searchBook(
                baseUrl = baseUrl,
                publicUrl = publicUrl,
                accessToken = token,
                keyword = _searchText.value,
                bookSourceUrl = bookSource.bookSourceUrl,
                page = currentPage
            ).onSuccess { newBooks ->
                if (newBooks.isEmpty()) {
                    canLoadMore = false
                }
                val currentBooks = (_uiState.value as? BookSearchUiState.Success)?.books ?: emptyList()
                _uiState.value = BookSearchUiState.Success(currentBooks + newBooks)
                currentPage++
            }.onFailure {
                _uiState.value = BookSearchUiState.Error(it.message ?: "Unknown error")
            }
        }
    }

    fun addBookToBookshelf(book: Book) {
        viewModelScope.launch {
            val (baseUrl, publicUrl, token) = userPreferences.getCredentials()
            if (token == null) {
                // Optionally expose this error to the UI
                return@launch
            }

            repository.saveBook(
                baseUrl = baseUrl,
                publicUrl = publicUrl,
                accessToken = token,
                book = book
            ).onFailure {
                // Optionally, expose this error to the UI via a separate state/event
            }
        }
    }

    companion object {
        fun Factory(
            bookSource: BookSource,
            repository: ReadRepository,
            userPreferences: UserPreferences
        ): ViewModelProvider.Factory = object : ViewModelProvider.Factory {
            @Suppress("UNCHECKED_CAST")
            override fun <T : ViewModel> create(modelClass: Class<T>): T {
                return BookSearchViewModel(bookSource, repository, userPreferences) as T
            }
        }
    }
}

sealed class BookSearchUiState {
    data class Success(val books: List<Book>) : BookSearchUiState()
    data class Error(val message: String) : BookSearchUiState()
    object Loading : BookSearchUiState()
}
