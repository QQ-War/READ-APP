package com.readapp.data

import android.content.Context
import android.graphics.Typeface
import android.net.Uri
import java.io.File

data class ReaderFontEntry(
    val name: String,
    val path: String
)

object ReaderFontManager {
    private const val FONT_DIR = "reader_fonts"

    fun listFonts(context: Context): List<ReaderFontEntry> {
        val dir = fontDirectory(context)
        val files = dir.listFiles()?.toList().orEmpty()
        return files.map {
            ReaderFontEntry(name = it.nameWithoutExtension, path = it.absolutePath)
        }
    }

    fun importFont(context: Context, uri: Uri): ReaderFontEntry? {
        val resolver = context.contentResolver
        val name = uri.lastPathSegment?.substringAfterLast("/") ?: return null
        val ext = name.substringAfterLast('.', "")
        if (ext.lowercase() !in listOf("ttf", "otf")) return null
        val target = File(fontDirectory(context), name)
        resolver.openInputStream(uri)?.use { input ->
            target.outputStream().use { output ->
                input.copyTo(output)
            }
        } ?: return null
        return ReaderFontEntry(name = target.nameWithoutExtension, path = target.absolutePath)
    }

    fun loadTypeface(path: String): Typeface? {
        return try {
            Typeface.createFromFile(path)
        } catch (_: Exception) {
            null
        }
    }

    private fun fontDirectory(context: Context): File {
        val dir = File(context.filesDir, FONT_DIR)
        if (!dir.exists()) {
            dir.mkdirs()
        }
        return dir
    }
}
