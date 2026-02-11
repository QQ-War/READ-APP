import UIKit
import QuartzCore

/// ProMotion 刷新率管理器，用于在阅读场景下优化能耗
final class DisplayRateManager {
    static let shared = DisplayRateManager()
    
    private var displayLink: CADisplayLink?
    private var isHighRateRequested = false
    
    private init() {}
    
    /// 开启刷新率管理
    func start() {
        guard displayLink == nil else { return }
        // CADisplayLink 即使 selector 为空，也能通过 preferredFrameRateRange 暗示系统调整刷新率
        displayLink = CADisplayLink(target: self, selector: #selector(displayLinkTick))
        displayLink?.add(to: .main, forMode: .common)
        applyRate(high: false) // 初始设为低刷新率
    }
    
    /// 停止刷新率管理
    func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }
    
    /// 请求高刷新率（通常在交互或动画时）
    func requestHighRate(_ high: Bool) {
        guard isHighRateRequested != high else { return }
        isHighRateRequested = high
        applyRate(high: high)
    }
    
    /// 刷新当前刷新率设置
    func refresh() {
        applyRate(high: isHighRateRequested)
    }
    
    private func applyRate(high: Bool) {
        if #available(iOS 15.0, *) {
            let range: CAFrameRateRange
            if high {
                // 交互时：限制最高 60Hz 保持流畅且省电，或者根据 ProMotion 需求设为更高
                // 这里建议遵从用户反馈，限制最高 60Hz 以降低 GPU/显示能耗
                range = CAFrameRateRange(
                    minimum: ReaderConstants.RefreshRate.minInteraction,
                    maximum: ReaderConstants.RefreshRate.maxInteraction,
                    preferred: ReaderConstants.RefreshRate.prefInteraction
                )
            } else {
                // 静态阅读时：根据用户设置降低刷新率
                let staticMin = ReaderConstants.RefreshRate.minStatic
                let rawMax = UserPreferences.shared.staticRefreshRateMax
                let staticMax = max(staticMin, rawMax.isFinite ? rawMax : ReaderConstants.RefreshRate.maxStatic)
                let rawRate = UserPreferences.shared.staticRefreshRate
                let rate = min(max(staticMin, rawRate.isFinite ? rawRate : ReaderConstants.RefreshRate.prefStatic), staticMax)
                range = CAFrameRateRange(
                    minimum: staticMin,
                    maximum: staticMax,
                    preferred: rate
                )
            }
            displayLink?.preferredFrameRateRange = range
        }
    }
    
    @objc private func displayLinkTick() {
        // 无需实际逻辑
    }
}
