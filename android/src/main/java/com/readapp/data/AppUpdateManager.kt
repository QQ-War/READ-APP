package com.readapp.data

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.content.SharedPreferences
import androidx.core.content.FileProvider
import com.readapp.BuildConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

data class AppUpdateInfo(
    val hasUpdate: Boolean,
    val localVersionName: String,
    val localBuildTimeUtc: String,
    val localBuildUnixTime: Long,
    val remoteTag: String,
    val remoteReleaseStamp: String,
    val remoteUpdatedAt: String,
    val remoteBuildUnixTime: Long,
    val downloadUrl: String,
    val assetName: String
)

sealed class AppInstallLaunchResult {
    data object Started : AppInstallLaunchResult()
    data object NeedUnknownSourcesPermission : AppInstallLaunchResult()
    data class Failed(val message: String) : AppInstallLaunchResult()
}

class AppUpdateManager(
    private val context: Context,
    private val client: OkHttpClient = OkHttpClient()
) {
    companion object {
        private const val RELEASE_API = "https://api.github.com/repos/QQ-War/READ-APP/releases/tags/ci-build-main"
        private const val TARGET_ASSET = "ReadApp-android-debug-main.apk"
        private const val PREFS_NAME = "app_update_prefs"
        private const val KEY_INSTALLED_RELEASE_STAMP = "installed_release_stamp"
    }

    private val prefs: SharedPreferences by lazy {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }

    fun currentVersionText(): String {
        return "ReadApp v${BuildConfig.VERSION_NAME} (${BuildConfig.BUILD_TIME_UTC})"
    }

    suspend fun checkCiMainUpdate(): Result<AppUpdateInfo> = withContext(Dispatchers.IO) {
        runCatching {
            val request = Request.Builder()
                .url(RELEASE_API)
                .header("Accept", "application/vnd.github+json")
                .build()

            client.newCall(request).execute().use { response ->
                if (!response.isSuccessful) {
                    error("GitHub 接口请求失败: HTTP ${response.code}")
                }
                val body = response.body?.string().orEmpty()
                val release = JSONObject(body)
                val assets = release.optJSONArray("assets")
                    ?: error("Release 资产为空")
                val releaseBody = release.optString("body")

                var selectedAsset: JSONObject? = null
                for (i in 0 until assets.length()) {
                    val asset = assets.optJSONObject(i) ?: continue
                    if (asset.optString("name") == TARGET_ASSET) {
                        selectedAsset = asset
                        break
                    }
                }
                if (selectedAsset == null) {
                    for (i in 0 until assets.length()) {
                        val asset = assets.optJSONObject(i) ?: continue
                        if (asset.optString("name").endsWith(".apk", ignoreCase = true)) {
                            selectedAsset = asset
                            break
                        }
                    }
                }
                val asset = selectedAsset ?: error("未找到可安装 APK 资产")

                val releaseMeta = parseReleaseBuildMetadata(releaseBody)
                val fallbackUpdatedAt = asset.optString("updated_at")
                    .ifBlank { release.optString("published_at") }
                val remoteBuildUnixTime = releaseMeta.buildUnixTime?.takeIf { it > 0L }
                    ?: parseIsoTime(fallbackUpdatedAt)
                val remoteUpdatedAt = releaseMeta.buildTimeUtc?.ifBlank { null }
                    ?: if (remoteBuildUnixTime > 0L) formatUnixTimeUtc(remoteBuildUnixTime)
                    ?: fallbackUpdatedAt
                val remoteReleaseStamp = releaseMeta.buildUnixTime?.toString()
                    ?: fallbackUpdatedAt
                val localBuildUnixTime = BuildConfig.BUILD_UNIX_TIME
                val installedReleaseStamp = getInstalledReleaseStamp()
                val hasUpdate = if (installedReleaseStamp.isNotBlank() && remoteReleaseStamp.isNotBlank()) {
                    installedReleaseStamp != remoteReleaseStamp
                } else {
                    remoteBuildUnixTime > localBuildUnixTime
                }

                AppUpdateInfo(
                    hasUpdate = hasUpdate,
                    localVersionName = BuildConfig.VERSION_NAME,
                    localBuildTimeUtc = BuildConfig.BUILD_TIME_UTC,
                    localBuildUnixTime = localBuildUnixTime,
                    remoteTag = release.optString("tag_name"),
                    remoteReleaseStamp = remoteReleaseStamp,
                    remoteUpdatedAt = remoteUpdatedAt,
                    remoteBuildUnixTime = remoteBuildUnixTime,
                    downloadUrl = asset.optString("browser_download_url"),
                    assetName = asset.optString("name")
                )
            }
        }
    }

    suspend fun downloadApk(downloadUrl: String, assetName: String): Result<File> = withContext(Dispatchers.IO) {
        runCatching {
            val updateDir = File(context.cacheDir, "update_apk").apply { mkdirs() }
            val targetFile = File(updateDir, assetName.ifBlank { "ReadApp-update.apk" })
            if (targetFile.exists()) {
                targetFile.delete()
            }

            val request = Request.Builder().url(downloadUrl).build()
            client.newCall(request).execute().use { response ->
                if (!response.isSuccessful) {
                    error("下载 APK 失败: HTTP ${response.code}")
                }
                val input = response.body?.byteStream() ?: error("下载内容为空")
                targetFile.outputStream().use { output ->
                    input.copyTo(output)
                }
            }
            targetFile
        }
    }

    fun launchInstall(apkFile: File): AppInstallLaunchResult {
        return runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !context.packageManager.canRequestPackageInstalls()) {
                val permissionIntent = Intent(
                    android.provider.Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:${context.packageName}")
                ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                context.startActivity(permissionIntent)
                return AppInstallLaunchResult.NeedUnknownSourcesPermission
            }

            val apkUri = FileProvider.getUriForFile(
                context,
                "${context.packageName}.fileprovider",
                apkFile
            )
            val installIntent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(apkUri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(installIntent)
            AppInstallLaunchResult.Started
        }.getOrElse { AppInstallLaunchResult.Failed(it.message ?: "无法拉起安装器") }
    }

    fun saveInstalledReleaseStamp(stamp: String) {
        if (stamp.isBlank()) return
        prefs.edit().putString(KEY_INSTALLED_RELEASE_STAMP, stamp).apply()
    }

    private fun getInstalledReleaseStamp(): String {
        return prefs.getString(KEY_INSTALLED_RELEASE_STAMP, "").orEmpty()
    }

    private fun parseIsoTime(isoString: String): Long {
        return runCatching {
            val parser = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US).apply {
                timeZone = TimeZone.getTimeZone("UTC")
            }
            (parser.parse(isoString)?.time ?: 0L) / 1000L
        }.getOrDefault(0L)
    }

    private fun formatUnixTimeUtc(unixTime: Long): String {
        if (unixTime <= 0L) return ""
        val formatter = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US).apply {
            timeZone = TimeZone.getTimeZone("UTC")
        }
        return formatter.format(Date(unixTime * 1000L))
    }

    private fun parseReleaseBuildMetadata(body: String): ReleaseBuildMetadata {
        if (body.isBlank()) return ReleaseBuildMetadata()
        val unixRegex = Regex("""(?im)^\s*build_unix_time\s*[:=]\s*(\d{1,20})\s*$""")
        val utcRegex = Regex("""(?im)^\s*build_time_utc\s*[:=]\s*([0-9TZ:\-]+)\s*$""")
        val unixTime = unixRegex.find(body)?.groupValues?.getOrNull(1)?.toLongOrNull()
        val utcTime = utcRegex.find(body)?.groupValues?.getOrNull(1)
        return ReleaseBuildMetadata(
            buildUnixTime = unixTime,
            buildTimeUtc = utcTime
        )
    }
}

private data class ReleaseBuildMetadata(
    val buildUnixTime: Long? = null,
    val buildTimeUtc: String? = null
)
