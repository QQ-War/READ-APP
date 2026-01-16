import Foundation

struct MangaAntiScrapingProfile: Identifiable {
    let key: String
    let name: String
    let hostSuffixes: [String]
    let referer: String?
    let userAgent: String?
    let extraHeaders: [String: String]

    var id: String { key }

    func matches(host: String) -> Bool {
        let target = host.lowercased()
        for suffix in hostSuffixes {
            let s = suffix.lowercased()
            if target == s || target.hasSuffix("." + s) {
                return true
            }
        }
        return false
    }
}

final class MangaAntiScrapingService {
    static let profiles: [MangaAntiScrapingProfile] = [
        MangaAntiScrapingProfile(key: "acg456", name: "acg456", hostSuffixes: ["acg456.com", "www.acg456.com"], referer: "http://www.acg456.com/", userAgent: nil, extraHeaders: [:]),
        MangaAntiScrapingProfile(key: "baozimh", name: "baozimh", hostSuffixes: ["baozimh.com", "www.baozimh.com", "bzcdn.net"], referer: "https://www.baozimh.com/", userAgent: nil, extraHeaders: [:]),
        MangaAntiScrapingProfile(key: "bilibili", name: "bilibili", hostSuffixes: ["manga.bilibili.com"], referer: "https://manga.bilibili.com/", userAgent: nil, extraHeaders: [:]),
        MangaAntiScrapingProfile(key: "boodo", name: "boodo", hostSuffixes: ["boodo.qq.com"], referer: "https://boodo.qq.com/", userAgent: nil, extraHeaders: [:]),
        MangaAntiScrapingProfile(key: "boylove", name: "boylove", hostSuffixes: ["boylove.cc"], referer: "https://boylove.cc/", userAgent: nil, extraHeaders: [:]),
        MangaAntiScrapingProfile(key: "177pic", name: "177pic", hostSuffixes: ["177pic.info", "www.177pic.info"], referer: "http://www.177pic.info/", userAgent: nil, extraHeaders: [:]),
        MangaAntiScrapingProfile(key: "18comic", name: "18comic", hostSuffixes: ["18comic.vip"], referer: "https://18comic.vip/", userAgent: nil, extraHeaders: [:]),
        MangaAntiScrapingProfile(key: "18hmmcg", name: "18hmmcg", hostSuffixes: ["18h.mm-cg.com"], referer: "https://18h.mm-cg.com/", userAgent: nil, extraHeaders: [:]),
        MangaAntiScrapingProfile(key: "2animx", name: "2animx", hostSuffixes: ["2animx.com", "www.2animx.com"], referer: "https://www.2animx.com/", userAgent: nil, extraHeaders: [:]),
        MangaAntiScrapingProfile(key: "2feimh", name: "2feimh", hostSuffixes: ["2feimh.com", "www.2feimh.com"], referer: "https://www.2feimh.com/", userAgent: nil, extraHeaders: [:]),
        MangaAntiScrapingProfile(key: "3250mh", name: "3250mh", hostSuffixes: ["3250mh.com", "www.3250mh.com"], referer: "https://www.3250mh.com/", userAgent: nil, extraHeaders: [:]),
        MangaAntiScrapingProfile(key: "36mh", name: "36mh", hostSuffixes: ["36mh.com", "www.36mh.com"], referer: "https://www.36mh.com/", userAgent: nil, extraHeaders: [:]),
        MangaAntiScrapingProfile(key: "55comic", name: "55comic", hostSuffixes: ["55comic.com", "www.55comic.com"], referer: "https://www.55comic.com/", userAgent: nil, extraHeaders: [:]),
        MangaAntiScrapingProfile(key: "77mh", name: "77mh", hostSuffixes: ["77mh.cc", "www.77mh.cc"], referer: "https://www.77mh.cc/", userAgent: nil, extraHeaders: [:]),
        MangaAntiScrapingProfile(key: "copymanga", name: "copymanga", hostSuffixes: ["copymanga.tv"], referer: "https://copymanga.tv/", userAgent: nil, extraHeaders: [:]),
        MangaAntiScrapingProfile(key: "dm5", name: "dm5", hostSuffixes: ["dm5.com", "www.dm5.com", "cdndm5.com"], referer: "https://www.dm5.com/", userAgent: nil, extraHeaders: [:]),
        MangaAntiScrapingProfile(key: "dmzj", name: "dmzj", hostSuffixes: ["dmzj.com", "www.dmzj.com"], referer: "https://www.dmzj.com/", userAgent: nil, extraHeaders: [:]),
        MangaAntiScrapingProfile(key: "gufengmh", name: "gufengmh", hostSuffixes: ["gufengmh9.com", "www.gufengmh9.com"], referer: "https://www.gufengmh9.com/", userAgent: nil, extraHeaders: [:]),
        MangaAntiScrapingProfile(key: "iqiyi", name: "iqiyi", hostSuffixes: ["bud.iqiyi.com"], referer: "https://bud.iqiyi.com/", userAgent: nil, extraHeaders: [:]),
        MangaAntiScrapingProfile(key: "jmzj", name: "jmzj", hostSuffixes: ["jmzj.xyz"], referer: "http://jmzj.xyz/", userAgent: nil, extraHeaders: [:]),
        MangaAntiScrapingProfile(key: "kanman", name: "kanman", hostSuffixes: ["kanman.com", "www.kanman.com"], referer: "https://www.kanman.com/", userAgent: nil, extraHeaders: [:]),
        MangaAntiScrapingProfile(
            key: "kuaikan",
            name: "kuaikan",
            hostSuffixes: ["kuaikanmanhua.com", "www.kuaikanmanhua.com", "kkmh.com", "tn1.kkmh.com"],
            referer: "https://m.kuaikanmanhua.com/",
            userAgent: nil,
            extraHeaders: ["Origin": "https://m.kuaikanmanhua.com"]
        ),
        MangaAntiScrapingProfile(key: "kuimh", name: "kuimh", hostSuffixes: ["kuimh.com", "www.kuimh.com"], referer: "https://www.kuimh.com/", userAgent: nil, extraHeaders: [:]),
        MangaAntiScrapingProfile(key: "laimanhua", name: "laimanhua", hostSuffixes: ["laimanhua.net", "www.laimanhua.net"], referer: "https://www.laimanhua.net/", userAgent: nil, extraHeaders: [:]),
        MangaAntiScrapingProfile(key: "manhuadb", name: "manhuadb", hostSuffixes: ["manhuadb.com", "www.manhuadb.com"], referer: "https://www.manhuadb.com/", userAgent: nil, extraHeaders: [:]),
        MangaAntiScrapingProfile(key: "manhuafei", name: "manhuafei", hostSuffixes: ["manhuafei.com", "www.manhuafei.com"], referer: "https://www.manhuafei.com/", userAgent: nil, extraHeaders: [:]),
        MangaAntiScrapingProfile(key: "manhuagui", name: "manhuagui", hostSuffixes: ["manhuagui.com", "www.manhuagui.com"], referer: "https://www.manhuagui.com/", userAgent: nil, extraHeaders: [:]),
        MangaAntiScrapingProfile(key: "manhuatai", name: "manhuatai", hostSuffixes: ["manhuatai.com", "www.manhuatai.com"], referer: "https://www.manhuatai.com/", userAgent: nil, extraHeaders: [:]),
        MangaAntiScrapingProfile(key: "manwa", name: "manwa", hostSuffixes: ["manwa.site"], referer: "https://manwa.site/", userAgent: nil, extraHeaders: [:]),
        MangaAntiScrapingProfile(key: "mh1234", name: "mh1234", hostSuffixes: ["mh1234.com", "www.mh1234.com"], referer: "https://www.mh1234.com/", userAgent: nil, extraHeaders: [:]),
        MangaAntiScrapingProfile(key: "mh160", name: "mh160", hostSuffixes: ["mh160.cc"], referer: "https://mh160.cc/", userAgent: nil, extraHeaders: [:]),
        MangaAntiScrapingProfile(key: "mmkk", name: "mmkk", hostSuffixes: ["mmkk.me", "www.mmkk.me"], referer: "https://www.mmkk.me/", userAgent: nil, extraHeaders: [:]),
        MangaAntiScrapingProfile(key: "myfcomic", name: "myfcomic", hostSuffixes: ["myfcomic.com", "www.myfcomic.com"], referer: "http://www.myfcomic.com/", userAgent: nil, extraHeaders: [:]),
        MangaAntiScrapingProfile(key: "nhentai", name: "nhentai", hostSuffixes: ["nhentai.net"], referer: "https://nhentai.net/", userAgent: nil, extraHeaders: [:]),
        MangaAntiScrapingProfile(key: "nsfwpicx", name: "nsfwpicx", hostSuffixes: ["picxx.icu"], referer: "http://picxx.icu/", userAgent: nil, extraHeaders: [:]),
        MangaAntiScrapingProfile(key: "pufei8", name: "pufei8", hostSuffixes: ["pufei8.com", "www.pufei8.com"], referer: "http://www.pufei8.com/", userAgent: nil, extraHeaders: [:]),
        MangaAntiScrapingProfile(key: "qiman6", name: "qiman6", hostSuffixes: ["qiman6.com", "www.qiman6.com"], referer: "http://www.qiman6.com/", userAgent: nil, extraHeaders: [:]),
        MangaAntiScrapingProfile(key: "qimiaomh", name: "qimiaomh", hostSuffixes: ["qimiaomh.com", "www.qimiaomh.com"], referer: "https://www.qimiaomh.com/", userAgent: nil, extraHeaders: [:]),
        MangaAntiScrapingProfile(key: "qootoon", name: "qootoon", hostSuffixes: ["qootoon.net", "www.qootoon.net"], referer: "https://www.qootoon.net/", userAgent: nil, extraHeaders: [:]),
        MangaAntiScrapingProfile(key: "qq", name: "qq", hostSuffixes: ["ac.qq.com"], referer: "https://ac.qq.com/", userAgent: nil, extraHeaders: [:]),
        MangaAntiScrapingProfile(key: "sixmh6", name: "sixmh6", hostSuffixes: ["sixmh6.com", "www.sixmh6.com"], referer: "http://www.sixmh6.com/", userAgent: nil, extraHeaders: [:]),
        MangaAntiScrapingProfile(key: "tuhao456", name: "tuhao456", hostSuffixes: ["tuhao456.com", "www.tuhao456.com"], referer: "https://www.tuhao456.com/", userAgent: nil, extraHeaders: [:]),
        MangaAntiScrapingProfile(key: "twhentai", name: "twhentai", hostSuffixes: ["twhentai.com"], referer: "http://twhentai.com/", userAgent: nil, extraHeaders: [:]),
        MangaAntiScrapingProfile(key: "u17", name: "u17", hostSuffixes: ["u17.com", "www.u17.com"], referer: "https://www.u17.com/", userAgent: nil, extraHeaders: [:]),
        MangaAntiScrapingProfile(key: "webtoons", name: "webtoons", hostSuffixes: ["webtoons.com", "www.webtoons.com"], referer: "https://www.webtoons.com/", userAgent: nil, extraHeaders: [:]),
        MangaAntiScrapingProfile(key: "wnacg", name: "wnacg", hostSuffixes: ["wnacg.org", "www.wnacg.org"], referer: "http://www.wnacg.org/", userAgent: nil, extraHeaders: [:]),
        MangaAntiScrapingProfile(key: "xiuren", name: "xiuren", hostSuffixes: ["xiuren.org", "www.xiuren.org"], referer: "http://www.xiuren.org/", userAgent: nil, extraHeaders: [:]),
        MangaAntiScrapingProfile(key: "ykmh", name: "ykmh", hostSuffixes: ["ykmh.com", "www.ykmh.com"], referer: "https://www.ykmh.com/", userAgent: nil, extraHeaders: [:]),
        MangaAntiScrapingProfile(key: "yymh889", name: "yymh889", hostSuffixes: ["yymh889.com"], referer: "http://yymh889.com/", userAgent: nil, extraHeaders: [:])
    ]
    static let profileKeys = profiles.map { $0.key }
    static let shared = MangaAntiScrapingService()

    private init() {}

    func resolveProfile(imageURL: URL, referer: String?) -> MangaAntiScrapingProfile? {
        guard UserPreferences.shared.isMangaAntiScrapingEnabled else { return nil }
        let enabledSites = UserPreferences.shared.mangaAntiScrapingEnabledSites
        guard !enabledSites.isEmpty else { return nil }

        let refererHost = URL(string: referer ?? "")?.host?.lowercased()
        let imageHost = imageURL.host?.lowercased()
        for profile in Self.profiles {
            if !enabledSites.contains(profile.key) { continue }
            if let refererHost, profile.matches(host: refererHost) {
                return profile
            }
            if let imageHost, profile.matches(host: imageHost) {
                return profile
            }
        }
        return nil
    }
}
