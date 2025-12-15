package com.readapp.android.data

import android.content.Context
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.doublePreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.floatPreferencesKey
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

private val Context.dataStore by preferencesDataStore(name = "readapp")

class UserPreferences(private val context: Context) {

    private object Keys {
        val ServerUrl = stringPreferencesKey("serverUrl")
        val PublicServerUrl = stringPreferencesKey("publicServerUrl")
        val AccessToken = stringPreferencesKey("accessToken")
        val Username = stringPreferencesKey("username")
        val FontScale = floatPreferencesKey("fontScale")
        val LineSpacing = floatPreferencesKey("lineSpacing")
        val SortByRecent = booleanPreferencesKey("sortByRecent")
        val SortAscending = booleanPreferencesKey("sortAscending")
        val ReverseChapterList = booleanPreferencesKey("reverseChapterList")
        val SelectedTtsId = stringPreferencesKey("selectedTtsId")
        val SpeechRate = doublePreferencesKey("speechRate")
        val PreloadSegments = intPreferencesKey("preloadSegments")
    }

    val serverUrl: Flow<String> = context.dataStore.data.map { preferences ->
        preferences[Keys.ServerUrl] ?: "http://127.0.0.1:8080/api/5"
    }

    val publicServerUrl: Flow<String> = context.dataStore.data.map { preferences ->
        preferences[Keys.PublicServerUrl] ?: ""
    }

    val accessToken: Flow<String> = context.dataStore.data.map { preferences ->
        preferences[Keys.AccessToken] ?: ""
    }

    val username: Flow<String> = context.dataStore.data.map { preferences ->
        preferences[Keys.Username] ?: ""
    }

    val fontScale: Flow<Float> = context.dataStore.data.map { preferences ->
        preferences[Keys.FontScale] ?: 1.0f
    }

    val lineSpacing: Flow<Float> = context.dataStore.data.map { preferences ->
        preferences[Keys.LineSpacing] ?: 1.4f
    }

    val sortByRecent: Flow<Boolean> = context.dataStore.data.map { preferences ->
        preferences[Keys.SortByRecent] ?: false
    }

    val sortAscending: Flow<Boolean> = context.dataStore.data.map { preferences ->
        preferences[Keys.SortAscending] ?: true
    }

    val reverseChapterList: Flow<Boolean> = context.dataStore.data.map { preferences ->
        preferences[Keys.ReverseChapterList] ?: false
    }

    val selectedTtsId: Flow<String> = context.dataStore.data.map { preferences ->
        preferences[Keys.SelectedTtsId] ?: ""
    }

    val speechRate: Flow<Double> = context.dataStore.data.map { preferences ->
        preferences[Keys.SpeechRate] ?: 1.0
    }

    val preloadSegments: Flow<Int> = context.dataStore.data.map { preferences ->
        preferences[Keys.PreloadSegments] ?: 0
    }

    suspend fun saveServerUrl(value: String) {
        context.dataStore.edit { prefs ->
            prefs[Keys.ServerUrl] = value
        }
    }

    suspend fun savePublicServerUrl(value: String) {
        context.dataStore.edit { prefs ->
            prefs[Keys.PublicServerUrl] = value
        }
    }

    suspend fun saveAccessToken(value: String) {
        context.dataStore.edit { prefs ->
            prefs[Keys.AccessToken] = value
        }
    }

    suspend fun saveUsername(value: String) {
        context.dataStore.edit { prefs ->
            prefs[Keys.Username] = value
        }
    }

    suspend fun saveFontScale(value: Float) {
        context.dataStore.edit { prefs ->
            prefs[Keys.FontScale] = value
        }
    }

    suspend fun saveLineSpacing(value: Float) {
        context.dataStore.edit { prefs ->
            prefs[Keys.LineSpacing] = value
        }
    }

    suspend fun saveSortByRecent(value: Boolean) {
        context.dataStore.edit { prefs ->
            prefs[Keys.SortByRecent] = value
        }
    }

    suspend fun saveSortAscending(value: Boolean) {
        context.dataStore.edit { prefs ->
            prefs[Keys.SortAscending] = value
        }
    }

    suspend fun saveReverseChapterList(value: Boolean) {
        context.dataStore.edit { prefs ->
            prefs[Keys.ReverseChapterList] = value
        }
    }

    suspend fun saveSelectedTtsId(value: String) {
        context.dataStore.edit { prefs ->
            prefs[Keys.SelectedTtsId] = value
        }
    }

    suspend fun saveSpeechRate(value: Double) {
        context.dataStore.edit { prefs ->
            prefs[Keys.SpeechRate] = value
        }
    }

    suspend fun savePreloadSegments(value: Int) {
        context.dataStore.edit { prefs ->
            prefs[Keys.PreloadSegments] = value
        }
    }
}
