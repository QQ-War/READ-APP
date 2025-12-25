package com.readapp.media

import android.content.Context
import androidx.media3.common.AudioAttributes
import androidx.media3.database.StandaloneDatabaseProvider
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.datasource.cache.CacheDataSource
import androidx.media3.datasource.cache.LeastRecentlyUsedCacheEvictor
import androidx.media3.datasource.cache.SimpleCache
import androidx.media3.exoplayer.ExoPlayer
import java.io.File
import java.util.LinkedList
import java.util.Queue

object PlayerPool {
    @Volatile
    private var cache: SimpleCache? = null
    private const val MAX_CACHE_SIZE: Long = 100 * 1024 * 1024 // 100MB
    private const val POOL_SIZE = 3 // One for playback, two for pre-buffering

    private val pool: Queue<ExoPlayer> = LinkedList()
    private val allPlayers: MutableList<ExoPlayer> = mutableListOf()

    fun initialize(context: Context) {
        if (allPlayers.isNotEmpty()) return
        synchronized(this) {
            if (allPlayers.isNotEmpty()) return
            for (i in 1..POOL_SIZE) {
                val player = buildPlayer(context.applicationContext)
                pool.add(player)
                allPlayers.add(player)
            }
        }
    }

    fun acquire(): ExoPlayer? {
        synchronized(this) {
            return pool.poll()
        }
    }

    fun release(player: ExoPlayer) {
        player.stop()
        player.clearMediaItems()
        synchronized(this) {
            // Ensure we don't add a player back to the pool if it's already there
            if (!pool.contains(player) && allPlayers.contains(player)) {
                pool.add(player)
            }
        }
    }

    fun releaseAll() {
        synchronized(this) {
            allPlayers.forEach { 
                it.stop()
                it.release() 
            }
            pool.clear()
            allPlayers.clear()
        }
    }

    fun getCache(context: Context): SimpleCache {
        return cache ?: synchronized(this) {
            cache ?: buildCache(context.applicationContext).also { cache = it }
        }
    }

    fun getCacheDataSourceFactory(context: Context): CacheDataSource.Factory {
        val upstreamFactory = DefaultHttpDataSource.Factory()
        return CacheDataSource.Factory()
            .setCache(getCache(context))
            .setUpstreamDataSourceFactory(upstreamFactory)
            .setFlags(CacheDataSource.FLAG_IGNORE_CACHE_ON_ERROR)
    }

    private fun buildCache(context: Context): SimpleCache {
        val cacheFolder = File(context.cacheDir, "tts_audio")
        val databaseProvider = StandaloneDatabaseProvider(context)
        return SimpleCache(cacheFolder, LeastRecentlyUsedCacheEvictor(MAX_CACHE_SIZE), databaseProvider)
    }

    private fun buildPlayer(context: Context): ExoPlayer {
        val audioAttributes = AudioAttributes.Builder()
            .setUsage(androidx.media3.common.C.USAGE_MEDIA)
            .setContentType(androidx.media3.common.C.AUDIO_CONTENT_TYPE_SPEECH)
            .build()
        
        return ExoPlayer.Builder(context)
            .setAudioAttributes(audioAttributes, true)
            .setHandleAudioBecomingNoisy(true)
            .build()
    }
}