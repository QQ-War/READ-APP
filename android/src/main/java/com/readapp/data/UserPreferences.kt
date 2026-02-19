package com.readapp.data

import android.content.Context
import androidx.datastore.preferences.core.MutablePreferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.doublePreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.floatPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import com.google.gson.GsonBuilder
import com.google.gson.reflect.TypeToken
import com.readapp.data.model.HttpTTS
import com.readapp.data.model.RssSourceItem
import com.readapp.data.model.HttpTtsAdapter
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.first

private val Context.dataStore by preferencesDataStore(name = "readapp2")

enum class ReadingMode {
    Vertical,
    Horizontal
}

enum class PageTurningMode {
    Scroll,
    Simulation
}

enum class DarkModeConfig {
    ON,
    OFF,
    AUTO
}

class UserPreferences(private val context: Context) {
    private val secureStorage = SecureStorage(context)
    private val gson = GsonBuilder()
        .registerTypeAdapter(HttpTTS::class.java, HttpTtsAdapter())
        .create()

    private object Keys {
        val ServerUrl = stringPreferencesKey("serverUrl")
        val ApiBackend = stringPreferencesKey("apiBackend")
        val PublicServerUrl = stringPreferencesKey("publicServerUrl")
        val AccessToken = stringPreferencesKey("accessToken")
        val Username = stringPreferencesKey("username")
        val SelectedTtsId = stringPreferencesKey("selectedTtsId")
        val NarrationTtsId = stringPreferencesKey("narrationTtsId")
        val DialogueTtsId = stringPreferencesKey("dialogueTtsId")
        val SpeakerTtsMapping = stringPreferencesKey("speakerTtsMapping")
        val ReadingFontSize = floatPreferencesKey("readingFontSize")
        val ReadingHorizontalPadding = floatPreferencesKey("readingHorizontalPadding")
        val ReadingMode = stringPreferencesKey("readingMode")
        val PageTurningMode = stringPreferencesKey("pageTurningMode")
        val DarkMode = stringPreferencesKey("darkMode")
        val ReadingTheme = stringPreferencesKey("readingTheme")
        val ReadingFontPath = stringPreferencesKey("readingFontPath")
        val ReadingFontName = stringPreferencesKey("readingFontName")
        val SpeechRate = doublePreferencesKey("speechRate")
        val PreloadCount = floatPreferencesKey("preloadCount")
        val LoggingEnabled = stringPreferencesKey("loggingEnabled")
        val BookshelfSortByRecent = booleanPreferencesKey("bookshelfSortByRecent")
        val LockPageOnTTS = booleanPreferencesKey("lockPageOnTTS")
        val UseSystemTts = booleanPreferencesKey("useSystemTts")
        val SystemVoiceId = stringPreferencesKey("systemVoiceId")
        val SearchSourcesFromBookshelf = booleanPreferencesKey("searchSourcesFromBookshelf")
        val PreferredSearchSourceUrls = stringPreferencesKey("preferredSearchSourceUrls")
        val ManualMangaUrls = stringPreferencesKey("manualMangaUrls")
        val ForceMangaProxy = booleanPreferencesKey("forceMangaProxy")
        val InfiniteScrollEnabled = booleanPreferencesKey("infiniteScrollEnabled")
        val TtsFollowCooldownSeconds = floatPreferencesKey("ttsFollowCooldownSeconds")
        val TtsSentenceChunkLimit = intPreferencesKey("ttsSentenceChunkLimit")
        val MangaSwitchThreshold = intPreferencesKey("mangaSwitchThreshold")
        val VerticalDampingFactor = floatPreferencesKey("verticalDampingFactor")
        val MangaMaxZoom = floatPreferencesKey("mangaMaxZoom")
        val ReadingMaxRefreshRate = floatPreferencesKey("readingMaxRefreshRate")
        val CachedTtsEngines = stringPreferencesKey("cachedTtsEngines")
        val CachedRssSources = stringPreferencesKey("cachedRssSources")
    }

    val serverUrl: Flow<String> = context.dataStore.data.map { it[Keys.ServerUrl] ?: "http://127.0.0.1:8080" }
    val apiBackend: Flow<ApiBackend> = context.dataStore.data.map { prefs ->
        val raw = prefs[Keys.ApiBackend]
        raw?.let { runCatching { ApiBackend.valueOf(it) }.getOrNull() }
            ?: detectApiBackend(prefs[Keys.ServerUrl] ?: "")
    }
    val publicServerUrl: Flow<String> = context.dataStore.data.map { it[Keys.PublicServerUrl] ?: "" }
    val accessToken: Flow<String> = context.dataStore.data.map { 
        secureStorage.getAccessToken() ?: it[Keys.AccessToken] ?: "" 
    }
    val username: Flow<String> = context.dataStore.data.map { it[Keys.Username] ?: "" }
    val selectedTtsId: Flow<String> = context.dataStore.data.map { it[Keys.SelectedTtsId] ?: "" }
    val useSystemTts: Flow<Boolean> = context.dataStore.data.map { it[Keys.UseSystemTts] ?: false }
    val systemVoiceId: Flow<String> = context.dataStore.data.map { it[Keys.SystemVoiceId] ?: "" }
    val searchSourcesFromBookshelf: Flow<Boolean> = context.dataStore.data.map { it[Keys.SearchSourcesFromBookshelf] ?: false }
    val preferredSearchSourceUrls: Flow<String> = context.dataStore.data.map { it[Keys.PreferredSearchSourceUrls] ?: "" }
    val manualMangaUrls: Flow<String> = context.dataStore.data.map { it[Keys.ManualMangaUrls] ?: "" }
    val forceMangaProxy: Flow<Boolean> = context.dataStore.data.map { it[Keys.ForceMangaProxy] ?: false }
    val infiniteScrollEnabled: Flow<Boolean> = context.dataStore.data.map { it[Keys.InfiniteScrollEnabled] ?: true }
    val ttsFollowCooldownSeconds: Flow<Float> = context.dataStore.data.map { it[Keys.TtsFollowCooldownSeconds] ?: 3f }
    val ttsSentenceChunkLimit: Flow<Int> = context.dataStore.data.map { it[Keys.TtsSentenceChunkLimit] ?: 600 }
    val mangaSwitchThreshold: Flow<Int> = context.dataStore.data.map { it[Keys.MangaSwitchThreshold] ?: 80 }
    val verticalDampingFactor: Flow<Float> = context.dataStore.data.map { it[Keys.VerticalDampingFactor] ?: 0.15f }
    val mangaMaxZoom: Flow<Float> = context.dataStore.data.map { it[Keys.MangaMaxZoom] ?: 3.0f }
    val readingMaxRefreshRate: Flow<Float> = context.dataStore.data.map {
        (it[Keys.ReadingMaxRefreshRate] ?: 0f).coerceIn(0f, 120f)
    }

    suspend fun saveCachedTtsEngines(engines: List<HttpTTS>) {
        val json = gson.toJson(engines)
        context.dataStore.edit { prefs -> prefs[Keys.CachedTtsEngines] = json }
    }

    suspend fun loadCachedTtsEngines(): List<HttpTTS> {
        val json = context.dataStore.data.first()[Keys.CachedTtsEngines].orEmpty()
        if (json.isBlank()) return emptyList()
        val type = object : TypeToken<List<HttpTTS>>() {}.type
        return runCatching { gson.fromJson<List<HttpTTS>>(json, type) }.getOrElse { emptyList() }
    }

    suspend fun saveCachedRssSources(sources: List<RssSourceItem>) {
        val json = gson.toJson(sources)
        context.dataStore.edit { prefs -> prefs[Keys.CachedRssSources] = json }
    }

    suspend fun loadCachedRssSources(): List<RssSourceItem> {
        val json = context.dataStore.data.first()[Keys.CachedRssSources].orEmpty()
        if (json.isBlank()) return emptyList()
        val type = object : TypeToken<List<RssSourceItem>>() {}.type
        return runCatching { gson.fromJson<List<RssSourceItem>>(json, type) }.getOrElse { emptyList() }
    }
    val narrationTtsId: Flow<String> = context.dataStore.data.map { it[Keys.NarrationTtsId] ?: "" }
    val dialogueTtsId: Flow<String> = context.dataStore.data.map { it[Keys.DialogueTtsId] ?: "" }
    val speakerTtsMapping: Flow<String> = context.dataStore.data.map { it[Keys.SpeakerTtsMapping] ?: "" }
    val readingFontSize: Flow<Float> = context.dataStore.data.map { it[Keys.ReadingFontSize] ?: 16f }
    val readingHorizontalPadding: Flow<Float> = context.dataStore.data.map { it[Keys.ReadingHorizontalPadding] ?: 24f }
    val speechRate: Flow<Double> = context.dataStore.data.map { it[Keys.SpeechRate] ?: 1.0 }
    val preloadCount: Flow<Float> = context.dataStore.data.map { it[Keys.PreloadCount] ?: 3f }
    val loggingEnabled: Flow<Boolean> = context.dataStore.data.map {
        it[Keys.LoggingEnabled]?.toBooleanStrictOrNull() ?: false
    }
    val bookshelfSortByRecent: Flow<Boolean> = context.dataStore.data.map {
        it[Keys.BookshelfSortByRecent] ?: false
    }
    val lockPageOnTTS: Flow<Boolean> = context.dataStore.data.map {
        it[Keys.LockPageOnTTS] ?: false
    }
    val readingMode: Flow<ReadingMode> = context.dataStore.data.map {
        ReadingMode.valueOf(it[Keys.ReadingMode] ?: ReadingMode.Vertical.name)
    }
    val pageTurningMode: Flow<PageTurningMode> = context.dataStore.data.map {
        PageTurningMode.valueOf(it[Keys.PageTurningMode] ?: PageTurningMode.Scroll.name)
    }
    val darkMode: Flow<DarkModeConfig> = context.dataStore.data.map {
        DarkModeConfig.valueOf(it[Keys.DarkMode] ?: DarkModeConfig.OFF.name)
    }
    val readingTheme: Flow<ReaderTheme> = context.dataStore.data.map {
        runCatching { ReaderTheme.valueOf(it[Keys.ReadingTheme] ?: ReaderTheme.System.name) }
            .getOrDefault(ReaderTheme.System)
    }
    val readingFontPath: Flow<String> = context.dataStore.data.map { it[Keys.ReadingFontPath] ?: "" }
    val readingFontName: Flow<String> = context.dataStore.data.map { it[Keys.ReadingFontName] ?: "" }

    suspend fun saveReadingMode(value: ReadingMode) {
        context.dataStore.edit { prefs: MutablePreferences ->
            prefs[Keys.ReadingMode] = value.name
        }
    }

    suspend fun savePageTurningMode(value: PageTurningMode) {
        context.dataStore.edit { prefs: MutablePreferences ->
            prefs[Keys.PageTurningMode] = value.name
        }
    }

    suspend fun saveDarkMode(value: DarkModeConfig) {
        context.dataStore.edit { prefs: MutablePreferences ->
            prefs[Keys.DarkMode] = value.name
        }
    }

    suspend fun saveReadingTheme(value: ReaderTheme) {
        context.dataStore.edit { prefs: MutablePreferences ->
            prefs[Keys.ReadingTheme] = value.name
        }
    }

    suspend fun saveReadingFont(path: String, name: String) {
        context.dataStore.edit { prefs: MutablePreferences ->
            prefs[Keys.ReadingFontPath] = path
            prefs[Keys.ReadingFontName] = name
        }
    }

    suspend fun saveLockPageOnTTS(value: Boolean) {
        context.dataStore.edit { prefs: MutablePreferences ->
            prefs[Keys.LockPageOnTTS] = value
        }
    }

    suspend fun saveTtsSentenceChunkLimit(value: Int) {
        context.dataStore.edit { prefs: MutablePreferences ->
            prefs[Keys.TtsSentenceChunkLimit] = value
        }
    }

    suspend fun saveMangaSwitchThreshold(value: Int) {
        context.dataStore.edit { prefs: MutablePreferences ->
            prefs[Keys.MangaSwitchThreshold] = value
        }
    }

    suspend fun saveVerticalDampingFactor(value: Float) {
        context.dataStore.edit { prefs: MutablePreferences ->
            prefs[Keys.VerticalDampingFactor] = value
        }
    }

    suspend fun saveMangaMaxZoom(value: Float) {
        context.dataStore.edit { prefs: MutablePreferences ->
            prefs[Keys.MangaMaxZoom] = value
        }
    }

    suspend fun saveReadingMaxRefreshRate(value: Float) {
        context.dataStore.edit { prefs: MutablePreferences ->
            prefs[Keys.ReadingMaxRefreshRate] = value.coerceIn(0f, 120f)
        }
    }

    suspend fun saveServerUrl(value: String) {
        context.dataStore.edit { prefs: MutablePreferences ->
            prefs[Keys.ServerUrl] = value
        }
    }

    suspend fun saveApiBackend(value: ApiBackend) {
        context.dataStore.edit { prefs: MutablePreferences ->
            prefs[Keys.ApiBackend] = value.name
        }
    }

    suspend fun savePublicServerUrl(value: String) {
        context.dataStore.edit { prefs: MutablePreferences ->
            prefs[Keys.PublicServerUrl] = value
        }
    }

    suspend fun saveAccessToken(value: String) {
        if (value.isBlank()) {
            secureStorage.clearAccessToken()
        } else {
            secureStorage.saveAccessToken(value)
        }
        context.dataStore.edit { prefs: MutablePreferences ->
            prefs[Keys.AccessToken] = value
        }
    }

    suspend fun saveUsername(value: String) {
        context.dataStore.edit { prefs: MutablePreferences ->
            prefs[Keys.Username] = value
        }
    }

    suspend fun saveSelectedTtsId(value: String) {
        context.dataStore.edit { prefs: MutablePreferences ->
            prefs[Keys.SelectedTtsId] = value
        }
    }

    suspend fun saveUseSystemTts(value: Boolean) {
        context.dataStore.edit { prefs: MutablePreferences ->
            prefs[Keys.UseSystemTts] = value
        }
    }

    suspend fun saveSystemVoiceId(value: String) {
        context.dataStore.edit { prefs: MutablePreferences ->
            prefs[Keys.SystemVoiceId] = value
        }
    }

    suspend fun saveSearchSourcesFromBookshelf(value: Boolean) {
        context.dataStore.edit { prefs: MutablePreferences ->
            prefs[Keys.SearchSourcesFromBookshelf] = value
        }
    }

    suspend fun savePreferredSearchSourceUrls(value: String) {
        context.dataStore.edit { prefs: MutablePreferences ->
            prefs[Keys.PreferredSearchSourceUrls] = value
        }
    }

    suspend fun saveManualMangaUrls(value: String) {
        context.dataStore.edit { prefs: MutablePreferences ->
            prefs[Keys.ManualMangaUrls] = value
        }
    }

    suspend fun saveForceMangaProxy(value: Boolean) {
        context.dataStore.edit { prefs: MutablePreferences ->
            prefs[Keys.ForceMangaProxy] = value
        }
    }

    suspend fun saveTtsFollowCooldownSeconds(value: Float) {
        context.dataStore.edit { prefs: MutablePreferences ->
            prefs[Keys.TtsFollowCooldownSeconds] = value
        }
    }

    suspend fun saveInfiniteScrollEnabled(value: Boolean) {
        context.dataStore.edit { prefs: MutablePreferences ->
            prefs[Keys.InfiniteScrollEnabled] = value
        }
    }

    suspend fun saveNarrationTtsId(value: String) {
        context.dataStore.edit { prefs: MutablePreferences ->
            prefs[Keys.NarrationTtsId] = value
        }
    }

    suspend fun saveDialogueTtsId(value: String) {
        context.dataStore.edit { prefs: MutablePreferences ->
            prefs[Keys.DialogueTtsId] = value
        }
    }

    suspend fun saveSpeakerTtsMapping(value: String) {
        context.dataStore.edit { prefs: MutablePreferences ->
            prefs[Keys.SpeakerTtsMapping] = value
        }
    }

    suspend fun saveReadingFontSize(value: Float) {
        context.dataStore.edit { prefs: MutablePreferences ->
            prefs[Keys.ReadingFontSize] = value
        }
    }

    suspend fun saveReadingHorizontalPadding(value: Float) {
        context.dataStore.edit { prefs: MutablePreferences ->
            prefs[Keys.ReadingHorizontalPadding] = value
        }
    }

    suspend fun saveSpeechRate(value: Double) {
        context.dataStore.edit { prefs: MutablePreferences ->
            prefs[Keys.SpeechRate] = value
        }
    }

    suspend fun savePreloadCount(value: Float) {
        context.dataStore.edit { prefs: MutablePreferences ->
            prefs[Keys.PreloadCount] = value
        }
    }

    suspend fun saveLoggingEnabled(value: Boolean) {
        context.dataStore.edit { prefs: MutablePreferences ->
            prefs[Keys.LoggingEnabled] = value.toString()
        }
    }

    suspend fun saveBookshelfSortByRecent(value: Boolean) {
        context.dataStore.edit { prefs: MutablePreferences ->
            prefs[Keys.BookshelfSortByRecent] = value
        }
    }

    suspend fun getApiBackendSetting(): ApiBackend? {
        val raw = context.dataStore.data.first()[Keys.ApiBackend] ?: return null
        return runCatching { ApiBackend.valueOf(raw) }.getOrNull()
    }

    suspend fun getCredentials(): Triple<String, String?, String?> {
        val backend = apiBackend.first()
        val baseUrl = normalizeApiBaseUrl(serverUrl.first(), backend)
        val publicUrl = publicServerUrl.first().ifBlank { null }?.let {
            normalizeApiBaseUrl(it, backend)
        }
        val token = accessToken.first().ifBlank { null }
        return Triple(baseUrl, publicUrl, token)
    }
}
