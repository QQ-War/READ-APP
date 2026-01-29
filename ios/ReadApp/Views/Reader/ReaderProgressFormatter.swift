import UIKit

struct ReaderProgressFormatter {
    static func chapterProgressText(current: Int, total: Int) -> String? {
        guard total > 0 else { return nil }
        let clampedCurrent = max(1, min(total, current))
        return "\(clampedCurrent)/\(total)"
    }

    static func percentProgressText(offset: CGFloat, maxOffset: CGFloat) -> String {
        ReaderMath.percentText(offset: offset, maxOffset: maxOffset)
    }
}
