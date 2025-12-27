package com.readapp.media

import android.net.Uri
import androidx.media3.common.C
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.TransferListener
import java.io.IOException

/**
 * DataSource that serves TTS audio directly from AudioCache via a tts:// URI.
 */
class TtsDataSource : DataSource {
    private var data: ByteArray? = null
    private var uri: Uri? = null
    private var readPosition: Int = 0
    private var bytesRemaining: Int = 0

    override fun addTransferListener(transferListener: TransferListener) = Unit

    override fun open(dataSpec: DataSpec): Long {
        uri = dataSpec.uri
        val key = uri?.getQueryParameter("key") ?: throw IOException("Missing cache key")
        val cached = AudioCache.get(key) ?: throw IOException("Audio not cached")

        data = cached
        val length = cached.size
        val skip = dataSpec.position.toInt()
        if (skip > length) {
            throw IOException("Position out of range")
        }
        readPosition = skip
        bytesRemaining = length - skip
        return bytesRemaining.toLong()
    }

    override fun read(buffer: ByteArray, offset: Int, readLength: Int): Int {
        if (bytesRemaining == 0) {
            return C.RESULT_END_OF_INPUT
        }
        val toRead = minOf(readLength, bytesRemaining)
        val source = data ?: return C.RESULT_END_OF_INPUT
        System.arraycopy(source, readPosition, buffer, offset, toRead)
        readPosition += toRead
        bytesRemaining -= toRead
        return toRead
    }

    override fun getUri(): Uri? = uri

    override fun close() {
        data = null
        uri = null
        readPosition = 0
        bytesRemaining = 0
    }
}
