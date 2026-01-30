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

enum DarkModeConfig: String, CaseIterable, Identifiable {
    case off = "Off"
    case on = "On"
    case system = "System"

    var id: String { self.rawValue }
    var localizedName: String {
        switch self {
        case .off: return "关闭"
        case .on: return "开启"
        case .system: return "跟随系统"
        }
    }
}

enum ReadingTheme: String, CaseIterable, Identifiable {
    case system = "System"
    case paper = "Paper"
    case eyeCare = "EyeCare"
    case dim = "Dim"

    var id: String { self.rawValue }

    var localizedName: String {
        switch self {
        case .system: return "系统默认"
        case .paper: return "牛皮纸"
        case .eyeCare: return "护眼绿"
        case .dim: return "深色微调"
        }
    }
}

enum MangaReaderMode: String, CaseIterable, Identifiable {
    case legacy = "Legacy"
    case collection = "Collection"

    var id: String { self.rawValue }
    var localizedName: String {
        switch self {
        case .legacy: return "漫画模式1（经典）"
        case .collection: return "漫画模式2（优化）"
        }
    }
}
