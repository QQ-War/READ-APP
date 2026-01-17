package com.readapp.data

import android.content.Context
import com.google.gson.Gson
import com.readapp.data.model.Book
import com.readapp.data.model.Chapter
import java.io.File
import java.security.MessageDigest

class LocalCacheManager(context: Context) {
    private val baseDir = File(context.filesDir, "BookCache").apply { if (!exists()) mkdirs() }
    private val bookshelfFile = File(context.filesDir, "bookshelf_cache.json")
    private val gson = Gson()

    private fun getBookDir(bookUrl: String): File {
        val hash = md5(bookUrl)
        return File(baseDir, hash).apply { if (!exists()) mkdirs() }
    }

    private fun md5(input: String): String {
        val md = MessageDigest.getInstance("MD5")
        return md.digest(input.toByteArray()).joinToString("") { "%02x".format(it) }
    }

    fun saveChapter(bookUrl: String, index: Int, content: String) {
        val file = File(getBookDir(bookUrl), "$index.raw")
        file.writeText(content)
    }

    fun loadChapter(bookUrl: String, index: Int): String? {
        val file = File(getBookDir(bookUrl), "$index.raw")
        return if (file.exists()) file.readText() else null
    }

    fun isChapterCached(bookUrl: String, index: Int): Boolean {
        return File(getBookDir(bookUrl), "$index.raw").exists()
    }

    fun saveChapterList(bookUrl: String, chapters: List<Chapter>) {
        val file = File(getBookDir(bookUrl), "toc.json")
        file.writeText(gson.toJson(chapters))
    }

    fun loadChapterList(bookUrl: String): List<Chapter>? {
        val file = File(getBookDir(bookUrl), "toc.json")
        if (!file.exists()) return null
        return try {
            gson.fromJson(file.readText(), Array<Chapter>::class.java).toList()
        } catch (e: Exception) {
            null
        }
    }

    fun saveBookshelfCache(books: List<Book>) {
        runCatching {
            bookshelfFile.writeText(gson.toJson(books))
        }
    }

    fun loadBookshelfCache(): List<Book>? {
        if (!bookshelfFile.exists()) return null
        return runCatching {
            gson.fromJson(bookshelfFile.readText(), Array<Book>::class.java).toList()
        }.getOrNull()
    }

    fun saveMangaImage(bookUrl: String, chapterIndex: Int, imageUrl: String, data: ByteArray) {
        val dir = getMangaDir(bookUrl, chapterIndex)
        val file = File(dir, "${md5(imageUrl)}.img")
        file.writeBytes(data)
    }

    fun loadMangaImage(bookUrl: String, chapterIndex: Int, imageUrl: String): ByteArray? {
        val file = File(getMangaDir(bookUrl, chapterIndex), "${md5(imageUrl)}.img")
        return if (file.exists()) file.readBytes() else null
    }

    fun isMangaImageCached(bookUrl: String, chapterIndex: Int, imageUrl: String): Boolean {
        return File(getMangaDir(bookUrl, chapterIndex), "${md5(imageUrl)}.img").exists()
    }

    fun clearCache(bookUrl: String) {
        getBookDir(bookUrl).deleteRecursively()
    }

    fun clearAllCache() {
        baseDir.deleteRecursively()
        baseDir.mkdirs()
    }

    fun getCachedChapterCount(bookUrl: String, totalChapters: Int): Int {
        var count = 0
        for (i in 0 until totalChapters) {
            if (isChapterCached(bookUrl, i)) count++
        }
        return count
    }

    fun getCacheSize(bookUrl: String): Long {
        val dir = getBookDir(bookUrl)
        return dir.walkTopDown().filter { it.isFile }.sumOf { it.length() }
    }

    private fun getMangaDir(bookUrl: String, chapterIndex: Int): File {
        val dir = File(getBookDir(bookUrl), "manga/$chapterIndex")
        if (!dir.exists()) dir.mkdirs()
        return dir
    }
}
