package com.readapp.data

import android.content.Context
import androidx.datastore.preferences.core.MutablePreferences
import androidx.datastore.preferences.core.doublePreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.floatPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

private val Context.dataStore by preferencesDataStore(name = "readapp2")

class UserPreferences(private val context: Context) {

    private object Keys {
        val ServerUrl = stringPreferencesKey("serverUrl")
        val PublicServerUrl = stringPreferencesKey("publicServerUrl")
        val AccessToken = stringPreferencesKey("accessToken")
        val Username = stringPreferencesKey("username")
        val SelectedTtsId = stringPreferencesKey("selectedTtsId")
        val SpeechRate = doublePreferencesKey("speechRate")
        val PreloadCount = floatPreferencesKey("preloadCount")
    }

    val serverUrl: Flow<String> = context.dataStore.data.map { it[Keys.ServerUrl] ?: "http://127.0.0.1:8080/api/5" }
    val publicServerUrl: Flow<String> = context.dataStore.data.map { it[Keys.PublicServerUrl] ?: "" }
    val accessToken: Flow<String> = context.dataStore.data.map { it[Keys.AccessToken] ?: "" }
    val username: Flow<String> = context.dataStore.data.map { it[Keys.Username] ?: "" }
    val selectedTtsId: Flow<String> = context.dataStore.data.map { it[Keys.SelectedTtsId] ?: "" }
    val speechRate: Flow<Double> = context.dataStore.data.map { it[Keys.SpeechRate] ?: 1.0 }
    val preloadCount: Flow<Float> = context.dataStore.data.map { it[Keys.PreloadCount] ?: 3f }

    suspend fun saveServerUrl(value: String) {
        context.dataStore.edit { prefs: MutablePreferences ->
            prefs[Keys.ServerUrl] = value
        }
    }

    suspend fun savePublicServerUrl(value: String) {
        context.dataStore.edit { prefs: MutablePreferences ->
            prefs[Keys.PublicServerUrl] = value
        }
    }

    suspend fun saveAccessToken(value: String) {
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
}
