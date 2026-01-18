import SwiftUI

extension ReadingTheme {
    var backgroundColor: UIColor {
        switch self {
        case .system:
            return .systemBackground
        case .paper:
            return UIColor(red: 0.96, green: 0.92, blue: 0.84, alpha: 1.0)
        case .eyeCare:
            return UIColor(red: 0.88, green: 0.95, blue: 0.88, alpha: 1.0)
        case .dim:
            return UIColor(red: 0.12, green: 0.12, blue: 0.13, alpha: 1.0)
        }
    }

    var textColor: UIColor {
        switch self {
        case .dim:
            return UIColor(white: 0.9, alpha: 1.0)
        case .system:
            return .label
        case .paper, .eyeCare:
            return UIColor(red: 0.18, green: 0.18, blue: 0.2, alpha: 1.0)
        }
    }

    var backgroundSwiftUIColor: Color {
        Color(backgroundColor)
    }
}
