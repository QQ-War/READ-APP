package com.readapp.viewmodel

import com.readapp.data.DarkModeConfig
import com.readapp.data.PageTurningMode
import com.readapp.data.ReadingMode
import com.readapp.data.UserPreferences
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch

class ReaderSettingsStore(
    private val preferences: UserPreferences,
    private val scope: CoroutineScope
) {
    private val _readingMode = MutableStateFlow(ReadingMode.Vertical)
    val readingMode: StateFlow<ReadingMode> = _readingMode.asStateFlow()

    private val _lockPageOnTTS = MutableStateFlow(false)
    val lockPageOnTTS: StateFlow<Boolean> = _lockPageOnTTS.asStateFlow()

    private val _pageTurningMode = MutableStateFlow(PageTurningMode.Scroll)
    val pageTurningMode: StateFlow<PageTurningMode> = _pageTurningMode.asStateFlow()

    private val _darkMode = MutableStateFlow(DarkModeConfig.OFF)
    val darkMode: StateFlow<DarkModeConfig> = _darkMode.asStateFlow()

    private val _readingFontSize = MutableStateFlow(16f)
    val readingFontSize: StateFlow<Float> = _readingFontSize.asStateFlow()

    private val _readingHorizontalPadding = MutableStateFlow(24f)
    val readingHorizontalPadding: StateFlow<Float> = _readingHorizontalPadding.asStateFlow()

    private val _infiniteScrollEnabled = MutableStateFlow(true)
    val infiniteScrollEnabled: StateFlow<Boolean> = _infiniteScrollEnabled.asStateFlow()

    private val _ttsFollowCooldownSeconds = MutableStateFlow(3f)
    val ttsFollowCooldownSeconds: StateFlow<Float> = _ttsFollowCooldownSeconds.asStateFlow()

    private val _manualMangaUrls = MutableStateFlow<Set<String>>(emptySet())
    val manualMangaUrls: StateFlow<Set<String>> = _manualMangaUrls.asStateFlow()

    private val _forceMangaProxy = MutableStateFlow(false)
    val forceMangaProxy: StateFlow<Boolean> = _forceMangaProxy.asStateFlow()

    suspend fun loadInitial() {
        _readingMode.value = preferences.readingMode.first()
        _lockPageOnTTS.value = preferences.lockPageOnTTS.first()
        _pageTurningMode.value = preferences.pageTurningMode.first()
        _darkMode.value = preferences.darkMode.first()
        _readingFontSize.value = preferences.readingFontSize.first()
        _readingHorizontalPadding.value = preferences.readingHorizontalPadding.first()
        _infiniteScrollEnabled.value = preferences.infiniteScrollEnabled.first()
        _ttsFollowCooldownSeconds.value = preferences.ttsFollowCooldownSeconds.first()
        val manualRaw = preferences.manualMangaUrls.first()
        _manualMangaUrls.value = if (manualRaw.isBlank()) emptySet() else manualRaw.split(";").toSet()
        _forceMangaProxy.value = preferences.forceMangaProxy.first()
    }

    fun updateReadingMode(mode: ReadingMode, onPendingScroll: () -> Unit) {
        val oldMode = _readingMode.value
        if (oldMode != mode) {
            onPendingScroll()
            _readingMode.value = mode
            scope.launch { preferences.saveReadingMode(mode) }
        }
    }

    fun updateReadingFontSize(size: Float) {
        _readingFontSize.value = size.coerceIn(12f, 28f)
        scope.launch { preferences.saveReadingFontSize(_readingFontSize.value) }
    }

    fun updateReadingHorizontalPadding(padding: Float) {
        _readingHorizontalPadding.value = padding.coerceIn(8f, 48f)
        scope.launch { preferences.saveReadingHorizontalPadding(_readingHorizontalPadding.value) }
    }

    fun updateInfiniteScrollEnabled(enabled: Boolean, onDisable: () -> Unit, onEnable: () -> Unit) {
        _infiniteScrollEnabled.value = enabled
        scope.launch {
            preferences.saveInfiniteScrollEnabled(enabled)
            if (!enabled) {
                onDisable()
            } else {
                onEnable()
            }
        }
    }

    fun updateLockPageOnTTS(enabled: Boolean) {
        _lockPageOnTTS.value = enabled
        scope.launch { preferences.saveLockPageOnTTS(enabled) }
    }

    fun updateTtsFollowCooldownSeconds(seconds: Float) {
        _ttsFollowCooldownSeconds.value = seconds.coerceIn(0f, 10f)
        scope.launch { preferences.saveTtsFollowCooldownSeconds(_ttsFollowCooldownSeconds.value) }
    }

    fun updatePageTurningMode(mode: PageTurningMode) {
        _pageTurningMode.value = mode
        scope.launch { preferences.savePageTurningMode(mode) }
    }

    fun updateDarkModeConfig(config: DarkModeConfig) {
        _darkMode.value = config
        scope.launch { preferences.saveDarkMode(config) }
    }

    fun toggleManualManga(url: String) {
        val current = _manualMangaUrls.value.toMutableSet()
        if (current.contains(url)) current.remove(url) else current.add(url)
        _manualMangaUrls.value = current
        scope.launch { preferences.saveManualMangaUrls(current.joinToString(";")) }
    }

    fun updateForceMangaProxy(enabled: Boolean) {
        _forceMangaProxy.value = enabled
        scope.launch { preferences.saveForceMangaProxy(enabled) }
    }
}
