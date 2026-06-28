// Ported from zrender/src/core/env.ts — keep in sync with upstream
import Foundation

// PORT-TODO: upstream `declare const wx: { getSystemInfoSync: Function }` — WeChat
// mini-program global. Not available on iOS; the `wx` detection branch below is dropped.

final class Browser {
    var firefox = false
    var ie = false
    var edge = false
    var newEdge = false
    var weChat = false
    // upstream: `version: string | number` — left undefined (Optional) until detect() sets it.
    // PORT-TODO: upstream union string|number; modeled as String? here. Numeric uses convert
    // with Double(version) at the boundary (see detect()).
    var version: String?
}

final class Env {
    var browser = Browser()
    var node = false
    var wxa = false
    var worker = false

    var svgSupported = false
    var touchEventsSupported = false
    var pointerEventsSupported = false
    var domSupported = false
    var transformSupported = false
    var transform3dSupported = false

    // upstream: `typeof window !== 'undefined'`
    // PORT-TODO: browser-only — no global `window` on iOS, so this is always false.
    var hasGlobalWindow = false
}

// NOTE (port): upstream creates `const env = new Env()` then mutates it in the top-level
// branch chain below. Swift library globals have no guaranteed load-time execution, so the
// native-branch configuration is folded into this lazy initializer; it runs the first time
// `env` is accessed (all access goes through this singleton).
let env: Env = {
    let env = Env()
    configureNativeEnv(env)
    return env
}()

// upstream runs a `wx`/`document`/`self`/`window`/`navigator` feature-detection chain to
// populate `env`. None of those globals exist on iOS, so we take the native branch and
// hardcode the native-relevant flags below. The original chain is preserved as a comment
// for diffability.
//
// if (typeof wx === 'object' && typeof wx.getSystemInfoSync === 'function') {
//     env.wxa = true;
//     env.touchEventsSupported = true;
// }
// else if (typeof document === 'undefined' && typeof self !== 'undefined') {
//     // In worker
//     env.worker = true;
// }
// else if (
//     !env.hasGlobalWindow
//     || 'Deno' in window
//     || (typeof navigator !== 'undefined' && typeof navigator.userAgent === 'string'
//         && navigator.userAgent.indexOf('Node.js') > -1)
// ) {
//     // In node
//     env.node = true;
//     env.svgSupported = true;
// }
// else {
//     detect(navigator.userAgent, env);
// }
//
// On iOS there is no global `window` (`hasGlobalWindow == false`), so upstream's top-level
// chain falls through to the **windowless (node) branch**:
//
//     else if (!env.hasGlobalWindow || 'Deno' in window || ...userAgent.indexOf('Node.js')) {
//         env.node = true;
//         env.svgSupported = true;
//     }
//
// We replicate that branch faithfully here (node = true, svgSupported = true); every other
// flag stays at the `Env` class default (`false`), exactly as upstream's node branch leaves
// them. This resolves the prior divergence where `if env.node` / `if env.svgSupported`
// gates would have branched opposite to upstream (PORT_STATUS §3 item 4).
func configureNativeEnv(_ env: Env) {
    // Faithful to upstream's windowless (node) branch:
    env.node = true
    env.svgSupported = true

    // PORT-TODO: not faithful, native deviation — upstream's node branch leaves these at the
    // `Env` default `false`; we override them for the native Core Graphics / touch backend.
    // Confined to here so the rest of `env` mirrors upstream's node env exactly.
    env.touchEventsSupported = true     // native touch is the input model (vs. browser DOM events)
    env.transformSupported = true       // affine transforms via Core Graphics
    env.transform3dSupported = true     // 3D transforms via Core Animation
}

// Zepto.js
// (c) 2010-2013 Thomas Fuchs
// Zepto.js may be freely distributed under the MIT license.

// PORT-TODO: dead, not faithful. `detect` parses a navigator userAgent string and probes
// browser globals (SVGRect, window, document, WebKitCSSMatrix). It is NEVER called on iOS
// (configureNativeEnv takes the node branch instead), and the global-membership guards —
// `'ontouchstart' in window`, `'onpointerdown' in window`, `typeof SVGRect !== 'undefined'`,
// `typeof document !== 'undefined'` — have no iOS equivalent and are hardcoded false/dropped
// below. The regex UA-parsing portion is translated faithfully for diffability; the feature-
// detection lines are deliberately non-faithful stubs (PORT_STATUS §3 item 5).
func detect(_ ua: String, _ env: Env) {
    let browser = env.browser
    let firefox = firstMatch(ua, #"Firefox\/([\d.]+)"#)
    let ie = firstMatch(ua, #"MSIE\s([\d.]+)"#)
        // IE 11 Trident/7.0; rv:11.0
        ?? firstMatch(ua, #"Trident\/.+?rv:(([\d.]+))"#)
    let edge = firstMatch(ua, #"Edge?\/([\d.]+)"#) // IE 12 and 12+

    let weChat = ua.range(of: "micromessenger", options: [.regularExpression, .caseInsensitive]) != nil

    if let firefox = firefox {
        browser.firefox = true
        browser.version = firefox[1]
    }
    if let ie = ie {
        browser.ie = true
        browser.version = ie[1]
    }

    if let edge = edge {
        browser.edge = true
        browser.version = edge[1]
        browser.newEdge = (Double(edge[1].split(separator: ".")[0]) ?? 0) > 18
    }

    // It is difficult to detect WeChat in Win Phone precisely, because ua can
    // not be set on win phone. So we do not consider Win Phone.
    if weChat {
        browser.weChat = true
    }

    // PORT-TODO: `typeof SVGRect !== 'undefined'` — browser global, no SVG on iOS.
    env.svgSupported = false
    // PORT-TODO: `'ontouchstart' in window && !browser.ie && !browser.edge` — browser globals.
    env.touchEventsSupported = !browser.ie && !browser.edge
    // PORT-TODO: `'onpointerdown' in window && (browser.edge || (browser.ie && +browser.version >= 11))`
    env.pointerEventsSupported = browser.edge || (browser.ie && (Double(browser.version ?? "") ?? 0) >= 11)

    // PORT-TODO: `typeof document !== 'undefined'` — browser global, no DOM on iOS.
    let domSupported = false
    env.domSupported = domSupported
    if domSupported {
        // PORT-TODO: browser-only style/transform feature detection through
        // `document.documentElement.style`, `WebKitCSSMatrix`, etc. Cannot be replicated on iOS.
        //
        // const style = document.documentElement.style;
        //
        // env.transform3dSupported = (
        //     (browser.ie && 'transition' in style)
        //     || browser.edge
        //     || (('WebKitCSSMatrix' in window) && ('m11' in new WebKitCSSMatrix()))
        //     || 'MozPerspective' in style
        // ) && !('OTransition' in style);
        //
        // env.transformSupported = env.transform3dSupported
        //     || (browser.ie && +browser.version >= 9);
    }
}

// PORT-TODO: helper replacing JS `String.prototype.match`. Returns an array-like where
// index 0 is the full match and index 1+ are capture-group substrings, or nil on no match.
private func firstMatch(_ s: String, _ pattern: String) -> [String]? {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
    let range = NSRange(s.startIndex..<s.endIndex, in: s)
    guard let match = regex.firstMatch(in: s, range: range) else { return nil }
    var groups: [String] = []
    for i in 0..<match.numberOfRanges {
        if let r = Range(match.range(at: i), in: s) {
            groups.append(String(s[r]))
        } else {
            groups.append("")
        }
    }
    return groups
}

// export default env;
// PORT-TODO: `env` is exposed as the module-level singleton (see `let env = Env()` above).
