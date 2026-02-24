package com.readapp.data

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey

class SecureStorage(context: Context) {
    private val sharedPreferences: SharedPreferences? = createEncryptedPrefs(context)

    private fun createEncryptedPrefs(context: Context): SharedPreferences? {
        return try {
            val masterKey = MasterKey.Builder(context)
                .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
                .build()
            EncryptedSharedPreferences.create(
                context,
                "secure_prefs",
                masterKey,
                EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
            )
        } catch (e: Exception) {
            Log.e("SecureStorage", "Failed to initialize encrypted storage", e)
            null
        }
    }

    fun saveAccessToken(token: String) {
        sharedPreferences?.edit()?.putString("accessToken", token)?.apply()
    }

    fun getAccessToken(): String? {
        return sharedPreferences?.getString("accessToken", null)
    }

    fun clearAccessToken() {
        sharedPreferences?.edit()?.remove("accessToken")?.apply()
    }
}
