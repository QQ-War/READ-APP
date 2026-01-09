package com.readapp.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.readapp.data.ReadRepository
import com.readapp.data.UserPreferences
import com.readapp.data.model.RssSourceItem
import com.readapp.data.model.RssSourcesResponse
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

class RssViewModel(
    private val repository: ReadRepository,
    private val preferences: UserPreferences
) : ViewModel() {

    private val _rssSources = MutableStateFlow<List<RssSourceItem>>(emptyList())
    val rssSources: StateFlow<List<RssSourceItem>> = _rssSources.asStateFlow()

    private val _isLoading = MutableStateFlow(true)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    private val _errorMessage = MutableStateFlow<String?>(null)
    val errorMessage: StateFlow<String?> = _errorMessage.asStateFlow()

    private val _canEdit = MutableStateFlow(true)
    val canEdit: StateFlow<Boolean> = _canEdit.asStateFlow()

    private val _pendingToggles = MutableStateFlow<Set<String>>(emptySet())
    val pendingToggles: StateFlow<Set<String>> = _pendingToggles.asStateFlow()

    init {
        refreshSources()
    }

    fun refreshSources() {
        viewModelScope.launch {
            val (baseUrl, publicUrl, token) = preferences.getCredentials()
            if (token == null) {
                _errorMessage.value = "请先登录"
                _isLoading.value = false
                return@launch
            }

            _isLoading.value = true
            _errorMessage.value = null
            repository.fetchRssSources(baseUrl, publicUrl, token)
                .onSuccess { response ->
                    updateSources(response)
                }
                .onFailure { error ->
                    _errorMessage.value = error.message ?: "加载订阅源失败"
                }
            _isLoading.value = false
        }
    }

    fun toggleSource(sourceUrl: String, enable: Boolean) {
        viewModelScope.launch {
            val (baseUrl, publicUrl, token) = preferences.getCredentials()
            if (token == null) {
                _errorMessage.value = "请先登录"
                return@launch
            }

            _pendingToggles.value = _pendingToggles.value + sourceUrl
            repository.toggleRssSource(baseUrl, publicUrl, token, sourceUrl, enable)
                .onSuccess {
                    _rssSources.value = _rssSources.value.map { item ->
                        if (item.sourceUrl == sourceUrl) item.copy(enabled = enable) else item
                    }
                }
                .onFailure { error ->
                    _errorMessage.value = error.message ?: "切换订阅源失败"
                }
            _pendingToggles.value = _pendingToggles.value - sourceUrl
        }
    }

    private fun updateSources(response: RssSourcesResponse) {
        _rssSources.value = response.sources
        _canEdit.value = response.can
    }

    class Factory(
        private val repository: ReadRepository,
        private val preferences: UserPreferences
    ) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : ViewModel> create(modelClass: Class<T>): T {
            if (modelClass.isAssignableFrom(RssViewModel::class.java)) {
                return RssViewModel(repository, preferences) as T
            }
            throw IllegalArgumentException("Unknown ViewModel class: $modelClass")
        }
    }
}
