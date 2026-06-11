import Foundation
import UIKit
import QuartzCore

/// Process-wide gate enabling the "Lite Mode" performance preset for older iPads.
///
/// Read by low-level UI code that cannot import `TelegramUIPreferences`
/// (the canonical home for `ExperimentalUISettings.liteMode`).
/// Mutated only by `SharedAccountContext` after observing the persisted setting,
/// mirroring the existing pattern used for `flatBuffers_checkedGet` and
/// `GlassBackgroundView.useCustomGlassImpl`.
public var sharedLiteModeEnabled: Bool = false

/// Process-wide gate that disables `UIVisualEffectView` blur entirely.
///
/// Set to `true` when Lite Mode is on, but kept as a separate flag so future
/// callers can disable blur independently (e.g. for manual A/B comparison).
public var sharedDisableBlur: Bool = false

/// Process-wide gate that disables animated chat backgrounds (gradient + pattern).
///
/// Defaulted ON when Lite Mode is on. Also driven by the long-existing
/// `ExperimentalUISettings.disableBackgroundAnimation` flag, which previously
/// had no consumers.
public var sharedDisableBackgroundAnimation: Bool = false

/// When true, non-critical startup warmups (story/history preload, secondary
/// accounts, non-primary tabs, device managers) are deferred until after the
/// first root controller is attached.
public var sharedDeferStartupWarmups: Bool = false

/// Captured at the beginning of `didFinishLaunching`; used by cold-start probes.
public var sharedLaunchStartTime: CFAbsoluteTime = 0

public func logColdStartTiming(_ marker: String) {
    guard sharedLaunchStartTime > 0 else {
        return
    }
    let elapsedMs = (CFAbsoluteTimeGetCurrent() - sharedLaunchStartTime) * 1000.0
    print("ColdStart[\(marker)]: \(String(format: "%.1f", elapsedMs)) ms")
}

private var chatOpenTimingStart: CFAbsoluteTime = 0

public func beginChatOpenTiming() {
    chatOpenTimingStart = CFAbsoluteTimeGetCurrent()
}

public func logChatOpenTiming(_ marker: String) {
    guard sharedLiteModeEnabled, chatOpenTimingStart > 0 else {
        return
    }
    let elapsedMs = (CFAbsoluteTimeGetCurrent() - chatOpenTimingStart) * 1000.0
    print("ChatOpen[\(marker)]: \(String(format: "%.1f", elapsedMs)) ms")
}

/// ListView `invisibleInset` when `preloadPages` is on and Lite Mode is active.
/// Max concurrent custom-emoji animation decoders when Lite Mode is on.
public let liteModeMaxSimultaneousEmojiAnimations: Int = 10

/// Max concurrent inline GIF software decoders when Lite Mode is on.
public let liteModeMaxSimultaneousGifDecodes: Int = 4

public let liteModeListPreloadInset: CGFloat = 200.0

/// Standard ListView preload inset for capable devices.
public let defaultListPreloadInset: CGFloat = 500.0

public let defaultListMinimalInset: CGFloat = 20.0

@available(iOS 15.0, *)
public func preferredFrameRateRangeForLiteMode(screenMaxFps: Float, preferHighRefresh: Bool) -> CAFrameRateRange {
    if sharedLiteModeEnabled {
        let cap = min(screenMaxFps, 60.0)
        return CAFrameRateRange(minimum: 30.0, maximum: cap, preferred: cap)
    }
    if preferHighRefresh && screenMaxFps > 61.0 {
        return CAFrameRateRange(minimum: 30.0, maximum: 120.0, preferred: 120.0)
    }
    if screenMaxFps > 61.0 {
        return CAFrameRateRange(minimum: Float(UIScreen.main.maximumFramesPerSecond), maximum: Float(UIScreen.main.maximumFramesPerSecond), preferred: Float(UIScreen.main.maximumFramesPerSecond))
    }
    return .default
}

public func listPreloadInset(preloadPages: Bool) -> CGFloat {
    if !preloadPages {
        return defaultListMinimalInset
    }
    return sharedLiteModeEnabled ? liteModeListPreloadInset : defaultListPreloadInset
}
