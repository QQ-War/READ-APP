import SwiftUI

extension ReadingTheme {
    var backgroundColor: UIColor {
        switch self {
        case .system:
            return .systemBackground
        case .day:
            return .white
        case .night:
            return .black
        case .paper:
            return UIColor(red: 0.96, green: 0.92, blue: 0.84, alpha: 1.0)
        case .eyeCare:
            return UIColor(red: 0.88, green: 0.95, blue: 0.88, alpha: 1.0)
        }
    }

    var textColor: UIColor {
        switch self {
        case .night:
            return UIColor(white: 1.0, alpha: 1.0)
        case .system:
            return .label
        case .day, .paper, .eyeCare:
            return .black
        }
    }

    var backgroundSwiftUIColor: Color {
        Color(backgroundColor)
    }

    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .day, .paper, .eyeCare:
            return .light
        case .night:
            return .dark
        case .system:
            return .unspecified
        }
    }
}
