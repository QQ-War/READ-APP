package com.readapp.data

import android.util.Log
import com.readapp.data.manga.MangaImageExtractor
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.ResponseBody
import java.io.File
import java.io.FileOutputStream
import java.util.zip.ZipEntry
import java.util.zip.ZipInputStream

class PackageDownloadManager(
    private val apiService: ReadApiService,
    private val localCache: LocalCacheManager
) {
    suspend fun downloadAndCacheMangaPackage(
        accessToken: String,
        bookUrl: String,
        bookOrigin: String?,
        chapterIndex: Int,
        chapterApiIndex: Int,
        rawContent: String // 需要从中提取图片 URL 列表以进行 MD5 映射
    ): Result<Unit> = withContext(Dispatchers.IO) {
        runCatching {
            val response = apiService.getChapterPackage(
                accessToken = accessToken,
                url = bookUrl,
                index = chapterApiIndex,
                type = 2,
                bookSourceUrl = bookOrigin
            )

            if (!response.isSuccessful) {
                throw Exception("Failed to download package: ${response.code()}")
            }

            val body = response.body() ?: throw Exception("Response body is empty")
            val imageUrls = MangaImageExtractor.extractImageUrls(rawContent)
            
            if (imageUrls.isEmpty()) {
                throw Exception("No image URLs found in content to map package")
            }

            body.use {
                unzipAndSave(it, bookUrl, chapterIndex, imageUrls)
            }
        }
    }

    private fun unzipAndSave(
        body: ResponseBody,
        bookUrl: String,
        chapterIndex: Int,
        imageUrls: List<String> // 假设对应 ZIP 里的 001.png, 002.png...
    ) {
        val zipInputStream = ZipInputStream(body.byteStream())
        val buffer = ByteArray(8 * 1024)
        var entry: ZipEntry? = zipInputStream.nextEntry
        var saveIndex = 0

        // 服务端按 001.png, 002.png... 打包，直接顺序读取并保存
        while (entry != null) {
            if (!entry.isDirectory && saveIndex < imageUrls.size) {
                val baos = java.io.ByteArrayOutputStream()
                var len = zipInputStream.read(buffer)
                while (len > 0) {
                    baos.write(buffer, 0, len)
                    len = zipInputStream.read(buffer)
                }
                val imageUrl = imageUrls[saveIndex]
                localCache.saveMangaImage(bookUrl, chapterIndex, imageUrl, baos.toByteArray())
                saveIndex++
            }
            zipInputStream.closeEntry()
            entry = zipInputStream.nextEntry
        }
        zipInputStream.close()
    }
}
