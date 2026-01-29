import UIKit

enum ReaderTextPositioning {
    static func detectionOffset(fontSize: CGFloat, lineSpacing: CGFloat) -> CGFloat {
        let spacingDriven = lineSpacing > 0 ? lineSpacing * ReaderConstants.Interaction.lineSpacingFactor : ReaderConstants.Interaction.minVerticalOffset
        return min(ReaderConstants.Interaction.maxVerticalOffset, max(ReaderConstants.Interaction.minVerticalOffset, spacingDriven))
    }

    static func lineDetectionOffset(fontSize: CGFloat) -> CGFloat {
        return max(ReaderConstants.Interaction.detectionOffsetMin, fontSize * ReaderConstants.Interaction.detectionOffsetFactor)
    }

    static func clampCharOffset(_ offset: Int, totalLength: Int) -> Int {
        guard totalLength > 0 else { return 0 }
        return max(0, min(offset, totalLength - 1))
    }

    static func isAutoScrollNeeded(relativeOffset: CGFloat, estimatedLineHeight: CGFloat, isFirstSentence: Bool, viewportHeight: CGFloat) -> (shouldScroll: Bool, shouldAnimate: Bool) {
        let threshold = isFirstSentence
            ? ReaderConstants.Interaction.firstSentenceThreshold
            : (estimatedLineHeight * ReaderConstants.Interaction.lineThresholdFactor)
        let shouldScroll = abs(relativeOffset) > threshold
        let shouldAnimate = abs(relativeOffset) < viewportHeight * ReaderConstants.Animation.shouldAnimateViewportThreshold
        return (shouldScroll, shouldAnimate)
    }
}
