import UIKit

struct ReaderFontProvider {
    static func bodyFont(size: CGFloat) -> UIFont {
        font(size: size, weight: .regular)
    }

    static func titleFont(size: CGFloat) -> UIFont {
        font(size: size, weight: .bold)
    }

    private static func font(size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let fontName = UserPreferences.shared.readingFontName
        if !fontName.isEmpty, let base = UIFont(name: fontName, size: size) {
            if weight == .regular { return base }
            if let descriptor = base.fontDescriptor.withSymbolicTraits(.traitBold) {
                return UIFont(descriptor: descriptor, size: size)
            }
            return base
        }
        return UIFont.systemFont(ofSize: size, weight: weight)
    }
}
