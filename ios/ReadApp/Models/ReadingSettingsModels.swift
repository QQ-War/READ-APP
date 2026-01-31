import Foundation

// MARK: - User Preferences
enum ReadingMode: String, CaseIterable, Identifiable {
    case vertical = "Vertical"
    case horizontal = "Horizontal"
    case newHorizontal = "NewHorizontal"

    var id: String { self.rawValue }
    var localizedName: String {
        switch self {
        case .vertical: return "上下滚动"
        case .horizontal: return "左右翻页"
        case .newHorizontal: return "新左右翻页(调试)"
        }
    }
}

enum PageTurningMode: String, CaseIterable, Identifiable {
    case scroll = "Scroll"
    case simulation = "Simulation"
    case cover = "Cover"
    case fade = "Fade"
    case flip = "Flip"
    case none = "None"

    var id: String { self.rawValue }
    var localizedName: String {
        switch self {
        case .scroll: return "平滑滑动"
        case .simulation: return "仿真翻页"
        case .cover: return "覆盖翻页"
        case .fade: return "淡入淡出"
        case .flip: return "旋转翻页"
        case .none: return "无动画"
        }
    }
}

enum ReadingTheme: String, CaseIterable, Identifiable {
    case system = "System"
    case day = "Day"
    case night = "Night"
    case paper = "Paper"
    case eyeCare = "EyeCare"

    var id: String { self.rawValue }

    var localizedName: String {
        switch self {
        case .system: return "跟随系统"
        case .day: return "日间模式"
        case .night: return "夜间模式"
        case .paper: return "牛皮纸"
        case .eyeCare: return "护眼绿"
        }
    }
}

enum MangaReaderMode: String, CaseIterable, Identifiable {
    case legacy = "Legacy"
    case collection = "Collection"
    case collectionNoChapterZoom = "CollectionNoChapterZoom"

    var id: String { self.rawValue }
    var localizedName: String {
        switch self {
        case .legacy: return "漫画模式1（经典）"
        case .collection: return "漫画模式2（优化）"
        case .collectionNoChapterZoom: return "漫画模式3（单图缩放）"
        }
    }
}
