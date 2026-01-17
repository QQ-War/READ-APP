package com.readapp.data.manga

import android.net.Uri

data class MangaAntiScrapingProfile(
    val key: String,
    val name: String,
    val hostSuffixes: List<String>,
    val referer: String?,
    val userAgent: String?,
    val extraHeaders: Map<String, String>
) {
    fun matches(host: String): Boolean {
        val target = host.lowercase()
        return hostSuffixes.any { suffix ->
            val s = suffix.lowercase()
            target == s || target.endsWith(".$s")
        }
    }
}

object MangaAntiScrapingService {
    val profiles = listOf(
        MangaAntiScrapingProfile("acg456", "acg456", listOf("acg456.com", "www.acg456.com"), "http://www.acg456.com/", null, emptyMap()),
        MangaAntiScrapingProfile("baozimh", "baozimh", listOf("baozimh.com", "www.baozimh.com", "bzcdn.net", "bzmh.net"), "https://www.baozimh.com/", null, emptyMap()),
        MangaAntiScrapingProfile("bilibili", "bilibili", listOf("manga.bilibili.com"), "https://manga.bilibili.com/", null, emptyMap()),
        MangaAntiScrapingProfile("boodo", "boodo", listOf("boodo.qq.com"), "https://boodo.qq.com/", null, emptyMap()),
        MangaAntiScrapingProfile("boylove", "boylove", listOf("boylove.cc"), "https://boylove.cc/", null, emptyMap()),
        MangaAntiScrapingProfile("177pic", "177pic", listOf("177pic.info", "www.177pic.info"), "http://www.177pic.info/", null, emptyMap()),
        MangaAntiScrapingProfile("18comic", "18comic", listOf("18comic.vip"), "https://18comic.vip/", null, emptyMap()),
        MangaAntiScrapingProfile("18hmmcg", "18hmmcg", listOf("18h.mm-cg.com"), "https://18h.mm-cg.com/", null, emptyMap()),
        MangaAntiScrapingProfile("2animx", "2animx", listOf("2animx.com", "www.2animx.com"), "https://www.2animx.com/", null, emptyMap()),
        MangaAntiScrapingProfile("2feimh", "2feimh", listOf("2feimh.com", "www.2feimh.com"), "https://www.2feimh.com/", null, emptyMap()),
        MangaAntiScrapingProfile("3250mh", "3250mh", listOf("3250mh.com", "www.3250mh.com"), "https://www.3250mh.com/", null, emptyMap()),
        MangaAntiScrapingProfile("36mh", "36mh", listOf("36mh.com", "www.36mh.com"), "https://www.36mh.com/", null, emptyMap()),
        MangaAntiScrapingProfile("55comic", "55comic", listOf("55comic.com", "www.55comic.com"), "https://www.55comic.com/", null, emptyMap()),
        MangaAntiScrapingProfile("77mh", "77mh", listOf("77mh.cc", "www.77mh.cc"), "https://www.77mh.cc/", null, emptyMap()),
        MangaAntiScrapingProfile("copymanga", "copymanga", listOf("copymanga.tv"), "https://copymanga.tv/", null, emptyMap()),
        MangaAntiScrapingProfile("dm5", "dm5", listOf("dm5.com", "www.dm5.com", "cdndm5.com"), "https://www.dm5.com/", null, emptyMap()),
        MangaAntiScrapingProfile("dmzj", "dmzj", listOf("dmzj.com", "www.dmzj.com"), "https://www.dmzj.com/", null, emptyMap()),
        MangaAntiScrapingProfile("gufengmh", "gufengmh", listOf("gufengmh9.com", "www.gufengmh9.com"), "https://www.gufengmh9.com/", null, emptyMap()),
        MangaAntiScrapingProfile("iqiyi", "iqiyi", listOf("bud.iqiyi.com"), "https://bud.iqiyi.com/", null, emptyMap()),
        MangaAntiScrapingProfile("jmzj", "jmzj", listOf("jmzj.xyz"), "http://jmzj.xyz/", null, emptyMap()),
        MangaAntiScrapingProfile("kanman", "kanman", listOf("kanman.com", "www.kanman.com"), "https://www.kanman.com/", null, emptyMap()),
        MangaAntiScrapingProfile(
            "kuaikan",
            "kuaikan",
            listOf("kuaikanmanhua.com", "www.kuaikanmanhua.com", "kkmh.com", "tn1.kkmh.com"),
            "https://www.kuaikanmanhua.com/",
            null,
            mapOf("Origin" to "https://www.kuaikanmanhua.com")
        ),
        MangaAntiScrapingProfile("kuimh", "kuimh", listOf("kuimh.com", "www.kuimh.com"), "https://www.kuimh.com/", null, emptyMap()),
        MangaAntiScrapingProfile("laimanhua", "laimanhua", listOf("laimanhua.net", "www.laimanhua.net"), "https://www.laimanhua.net/", null, emptyMap()),
        MangaAntiScrapingProfile("manhuadb", "manhuadb", listOf("manhuadb.com", "www.manhuadb.com"), "https://www.manhuadb.com/", null, emptyMap()),
        MangaAntiScrapingProfile("manhuafei", "manhuafei", listOf("manhuafei.com", "www.manhuafei.com"), "https://www.manhuafei.com/", null, emptyMap()),
        MangaAntiScrapingProfile("manhuagui", "manhuagui", listOf("manhuagui.com", "www.manhuagui.com"), "https://www.manhuagui.com/", null, emptyMap()),
        MangaAntiScrapingProfile("manhuatai", "manhuatai", listOf("manhuatai.com", "www.manhuatai.com"), "https://www.manhuatai.com/", null, emptyMap()),
        MangaAntiScrapingProfile("manwa", "manwa", listOf("manwa.site"), "https://manwa.site/", null, emptyMap()),
        MangaAntiScrapingProfile("mh1234", "mh1234", listOf("mh1234.com", "www.mh1234.com"), "https://www.mh1234.com/", null, emptyMap()),
        MangaAntiScrapingProfile("mh160", "mh160", listOf("mh160.cc"), "https://mh160.cc/", null, emptyMap()),
        MangaAntiScrapingProfile("mmkk", "mmkk", listOf("mmkk.me", "www.mmkk.me"), "https://www.mmkk.me/", null, emptyMap()),
        MangaAntiScrapingProfile("myfcomic", "myfcomic", listOf("myfcomic.com", "www.myfcomic.com"), "http://www.myfcomic.com/", null, emptyMap()),
        MangaAntiScrapingProfile("nhentai", "nhentai", listOf("nhentai.net"), "https://nhentai.net/", null, emptyMap()),
        MangaAntiScrapingProfile("nsfwpicx", "nsfwpicx", listOf("picxx.icu"), "http://picxx.icu/", null, emptyMap()),
        MangaAntiScrapingProfile("pufei8", "pufei8", listOf("pufei8.com", "www.pufei8.com"), "http://www.pufei8.com/", null, emptyMap()),
        MangaAntiScrapingProfile("qiman6", "qiman6", listOf("qiman6.com", "www.qiman6.com"), "http://www.qiman6.com/", null, emptyMap()),
        MangaAntiScrapingProfile("qimiaomh", "qimiaomh", listOf("qimiaomh.com", "www.qimiaomh.com"), "https://www.qimiaomh.com/", null, emptyMap()),
        MangaAntiScrapingProfile("qootoon", "qootoon", listOf("qootoon.net", "www.qootoon.net"), "https://www.qootoon.net/", null, emptyMap()),
        MangaAntiScrapingProfile("qq", "qq", listOf("ac.qq.com"), "https://ac.qq.com/", null, emptyMap()),
        MangaAntiScrapingProfile("sixmh6", "sixmh6", listOf("sixmh6.com", "www.sixmh6.com"), "http://www.sixmh6.com/", null, emptyMap()),
        MangaAntiScrapingProfile("tuhao456", "tuhao456", listOf("tuhao456.com", "www.tuhao456.com"), "https://www.tuhao456.com/", null, emptyMap()),
        MangaAntiScrapingProfile("twhentai", "twhentai", listOf("twhentai.com"), "http://twhentai.com/", null, emptyMap()),
        MangaAntiScrapingProfile("u17", "u17", listOf("u17.com", "www.u17.com"), "https://www.u17.com/", null, emptyMap()),
        MangaAntiScrapingProfile("webtoons", "webtoons", listOf("webtoons.com", "www.webtoons.com"), "https://www.webtoons.com/", null, emptyMap()),
        MangaAntiScrapingProfile("wnacg", "wnacg", listOf("wnacg.org", "www.wnacg.org"), "http://www.wnacg.org/", null, emptyMap()),
        MangaAntiScrapingProfile("xiuren", "xiuren", listOf("xiuren.org", "www.xiuren.org"), "http://www.xiuren.org/", null, emptyMap()),
        MangaAntiScrapingProfile("ykmh", "ykmh", listOf("ykmh.com", "www.ykmh.com"), "https://www.ykmh.com/", null, emptyMap()),
        MangaAntiScrapingProfile("yymh889", "yymh889", listOf("yymh889.com"), "http://yymh889.com/", null, emptyMap())
    )

    fun resolveProfile(imageUrl: String?, referer: String?): MangaAntiScrapingProfile? {
        val refererHost = referer?.let { Uri.parse(it).host?.lowercase() }
        val imageHost = imageUrl?.let { Uri.parse(it).host?.lowercase() }
        for (profile in profiles) {
            if (refererHost != null && profile.matches(refererHost)) return profile
            if (imageHost != null && profile.matches(imageHost)) return profile
        }
        return null
    }

    fun resolveReferer(profile: MangaAntiScrapingProfile?, referer: String?, imageUrl: String?): String? {
        val normalized = normalizeReferer(referer, imageUrl)
        if (profile?.key == "dm5" && !normalized.isNullOrBlank()) {
            return normalizeHttp(normalized)
        }
        if (profile != null) {
            return profile.referer
        }
        if (!normalized.isNullOrBlank()) return normalizeHttp(normalized)
        val host = imageUrl?.let { Uri.parse(it).host } ?: return null
        return "https://$host/"
    }

    private fun normalizeReferer(referer: String?, imageUrl: String?): String? {
        val value = referer?.trim().orEmpty()
        if (value.isEmpty()) return null
        if (value.startsWith("http://") || value.startsWith("https://")) return value
        val host = imageUrl?.let { Uri.parse(it).host } ?: return value
        val normalized = if (value.startsWith("/")) value else "/$value"
        return "https://$host$normalized"
    }

    private fun normalizeHttp(value: String): String {
        var v = value
        if (v.startsWith("http://")) v = v.replace("http://", "https://")
        if (!v.endsWith("/")) v += "/"
        return v
    }
}
