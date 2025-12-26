package com.readapp.media

import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.media.AudioManager.OnAudioFocusChangeListener
import android.util.Log
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class ReadAudioService : MediaSessionService() {
    private var mediaSession: MediaSession? = null

    override fun onCreate() {
        super.onCreate()
        appendLog("ReadAudioService onCreate")
        val player = PlayerPool.get(this)
        mediaSession = MediaSession.Builder(this, player).build()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        appendLog("ReadAudioService onStartCommand action=${intent?.action} flags=$flags startId=$startId")
        return super.onStartCommand(intent, flags, startId)
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession? {
        return mediaSession
    }

    override fun onDestroy() {
        appendLog("ReadAudioService onDestroy")
        mediaSession?.release()
        mediaSession = null
        super.onDestroy()
    }

    private fun appendLog(message: String) {
        val timestamp = SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.getDefault()).format(Date())
        val line = "[$timestamp] $message\n"
        runCatching {
            File(filesDir, "reader_logs.txt").appendText(line)
        }
        Log.d("ReadAudioService", message)
    }

    companion object {
        fun startService(context: Context) {
            runCatching {
                val file = File(context.filesDir, "reader_logs.txt")
                val timestamp = SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.getDefault()).format(Date())
                file.appendText("[$timestamp] ReadAudioService startService\n")
            }
            context.startService(Intent(context, ReadAudioService::class.java))
        }
    }
}
