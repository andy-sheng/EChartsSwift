// Ported from zrender/src/config.ts — keep in sync with upstream

// import env from './core/env'  (env is the module-level singleton in Core/env.swift)

public func getDevicePixelRatio() -> Double {
    var dpr: Double = 1

    // If in browser environment
    if env.hasGlobalWindow {
        // PORT-NOTE: browser-only — no global `window`/`window.screen` on iOS.
        // Upstream:
        //   dpr = window.devicePixelRatio
        //       || (window.screen && window.screen.deviceXDPI / window.screen.logicalXDPI)
        //       || 1;
        dpr = 1
    }

    return dpr
}

/**
 * Debug log mode:
 * 0: Do nothing, for release.
 * 1: console.error, for debug.
 */
public let debugMode: Double = 0

/**
 * Determine when to turn on dark mode based on the luminance of backgroundColor
 */
public let DARK_MODE_THRESHOLD: Double = 0.4

/**
 * Color of default dark label.
 */
public let DARK_LABEL_COLOR: String = "#333"

/**
 * Color of default light label.
 */
public let LIGHT_LABEL_COLOR: String = "#ccc"

/**
 * Color of default light label.
 */
public let LIGHTER_LABEL_COLOR: String = "#eee"
