package com.readapp.data

import android.content.Context
import com.readapp.data.model.BookSource
import com.google.gson.Gson
import java.io.File

class LocalSourceCache(context: Context) {
    private val gson = Gson()
    private val cacheFile = File(context.filesDir, "sources_cache.json")

    fun loadSources(): List<BookSource>? {
        if (!cacheFile.exists()) return null
        return runCatching {
            val json = cacheFile.readText()
            gson.fromJson(json, Array<BookSource>::class.java)?.toList()
        }.getOrNull()
    }

    fun saveSources(sources: List<BookSource>) {
        val json = gson.toJson(sources)
        cacheFile.writeText(json)
    }
}
