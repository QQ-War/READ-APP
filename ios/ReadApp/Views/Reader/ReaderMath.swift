import UIKit

enum ReaderMath {
    static func clamp<T: Comparable>(_ value: T, min minValue: T, max maxValue: T) -> T {
        return max(minValue, min(maxValue, value))
    }

    static func percent(offset: CGFloat, maxOffset: CGFloat) -> Int {
        guard maxOffset > 0 else { return 0 }
        let ratio = clamp(offset / maxOffset, min: 0, max: 1)
        return Int(round(ratio * 100))
    }

    static func percentText(offset: CGFloat, maxOffset: CGFloat) -> String {
        let value = min(100, percent(offset: offset, maxOffset: maxOffset))
        return "\(value)%"
    }

    static func layoutSpec(
        safeAreaTop: CGFloat,
        safeAreaBottom: CGFloat,
        viewSafeArea: UIEdgeInsets,
        pageHorizontalMargin: CGFloat,
        bounds: CGRect
    ) -> ReaderLayoutSpec {
        let topInsetValue = safeAreaTop > 0 ? safeAreaTop : viewSafeArea.top
        let bottomInsetValue = safeAreaBottom > 0 ? safeAreaBottom : viewSafeArea.bottom
        return ReaderLayoutSpec(
            topInset: topInsetValue + ReaderConstants.Layout.extraTopInset,
            bottomInset: bottomInsetValue + ReaderConstants.Layout.extraBottomInset,
            sideMargin: pageHorizontalMargin + ReaderConstants.Layout.sideMarginPadding,
            pageSize: bounds.size
        )
    }

    static func layoutWidth(containerWidth: CGFloat, margin: CGFloat) -> CGFloat {
        return max(ReaderConstants.Layout.minLayoutWidth, containerWidth - margin * 2)
    }
}
