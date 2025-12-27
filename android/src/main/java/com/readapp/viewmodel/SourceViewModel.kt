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
import com.readapp.data.model.BookSource
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch

class SourceViewModel(application: Application) : AndroidViewModel(application) {

    private val userPreferences = UserPreferences(application)
    private val repository = ReadRepository { endpoint ->
        ReadApiService.create(endpoint) { userPreferences.accessToken.value }
    }

    private val _sources = MutableStateFlow<List<BookSource>>(emptyList())
    val sources = _sources.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading = _isLoading.asStateFlow()

    private val _errorMessage = MutableStateFlow<String?>(null)
    val errorMessage = _errorMessage.asStateFlow()

    init {
        fetchSources()
    }

    fun fetchSources() {
        viewModelScope.launch {
            _isLoading.value = true
            _errorMessage.value = null

            // We need to get the latest values from preferences
            val serverUrl = userPreferences.serverUrl.first()
            val publicUrl = userPreferences.publicServerUrl.first().ifBlank { null }
            val token = userPreferences.accessToken.first()
            
            if (token.isBlank()) {
                _errorMessage.value = "用户未登录"
                _isLoading.value = false
                return@launch
            }

            val result = repository.getBookSources(
                baseUrl = serverUrl,
                publicUrl = publicUrl,
                accessToken = token
            )

            result.onSuccess {
                _sources.value = it
            }.onFailure {
                _errorMessage.value = it.message ?: "获取书源失败"
            }
            
            _isLoading.value = false
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
