// Ported from echarts/src/model/globalDefault.ts — keep in sync with upstream

import Foundation
import ZRenderKit

// import { modifyHSL } from 'zrender/src/tool/color';  → color.modifyHSL (ZRenderKit)
// import tokens from '../visual/tokens';
// PORT-TODO: visual/tokens.ts is not ported yet (this phase ports only this file). The theme
// palette is inlined below to match `tokens.color.theme`; re-wire to the real `tokens`
// namespace once visual/tokens.swift lands.

// upstream:
//   let platform = '';
//   // Navigator not exists in node
//   if (typeof navigator !== 'undefined') {
//       platform = navigator.platform || '';
//   }
// PORT-TODO: no `navigator` on Apple platforms; platform stays '' (never matches /^Win/), so
// `textStyle.fontFamily` resolves to 'sans-serif' below — same as the node branch upstream.
private let platform = ""

private let decalColor = "rgba(0, 0, 0, 0.2)"

// PORT-TODO: upstream is `tokens.color.theme` (from ../visual/tokens). Inlined verbatim here.
private let themeColorTheme: [String] = [
    "#5070dd",
    "#b6d634",
    "#505372",
    "#ff994d",
    "#0ca8df",
    "#ffd10a",
    "#fb628b",
    "#785db0",
    "#3fbe95"
]

private let themeColor = themeColorTheme[0]
// upstream: modifyHSL(themeColor, null, null, 0.9)
private let lightThemeColor = color.modifyHSL(themeColor, nil, nil, 0.9)!

// upstream: `export default { ... }`
// The default option is a dynamic option bag, modelled as [String: Any] per the dynamic
// option-tree convention (deep-merged via util.merge, keyed via Model.get). Callers that
// referenced `globalDefault.<key>` upstream use `globalDefault.option["<key>"]`.
public enum globalDefault {

    public static let option: [String: Any] = [

        "darkMode": "auto",
        // backgroundColor: 'rgba(0,0,0,0)',

        "colorBy": "series",

        "color": themeColorTheme,  // upstream: tokens.color.theme

        "gradientColor": [lightThemeColor, themeColor],

        "aria": [
            "decal": [
                "decals": [
                    [
                        "color": decalColor,
                        "dashArrayX": [1, 0],
                        "dashArrayY": [2, 5],
                        "symbolSize": 1,
                        "rotation": Double.pi / 6
                    ] as [String: Any],
                    [
                        "color": decalColor,
                        "symbol": "circle",
                        "dashArrayX": [[8, 8], [0, 8, 8, 0]],
                        "dashArrayY": [6, 0],
                        "symbolSize": 0.8
                    ] as [String: Any],
                    [
                        "color": decalColor,
                        "dashArrayX": [1, 0],
                        "dashArrayY": [4, 3],
                        "rotation": -Double.pi / 4
                    ] as [String: Any],
                    [
                        "color": decalColor,
                        "dashArrayX": [[6, 6], [0, 6, 6, 0]],
                        "dashArrayY": [6, 0]
                    ] as [String: Any],
                    [
                        "color": decalColor,
                        "dashArrayX": [[1, 0], [1, 6]],
                        "dashArrayY": [1, 0, 6, 0],
                        "rotation": Double.pi / 4
                    ] as [String: Any],
                    [
                        "color": decalColor,
                        "symbol": "triangle",
                        "dashArrayX": [[9, 9], [0, 9, 9, 0]],
                        "dashArrayY": [7, 2],
                        "symbolSize": 0.75
                    ] as [String: Any]
                ]
            ]
        ] as [String: Any],

        // If xAxis and yAxis declared, grid is created by default.
        // grid: {},

        "textStyle": [
            // color: '#000',
            // decoration: 'none',
            // PENDING
            "fontFamily": platform.range(of: "^Win", options: .regularExpression) != nil ? "Microsoft YaHei" : "sans-serif",
            // fontFamily: 'Arial, Verdana, sans-serif',
            "fontSize": 12,
            "fontStyle": "normal",
            "fontWeight": "normal"
        ] as [String: Any],

        // http://blogs.adobe.com/webplatform/2014/02/24/using-blend-modes-in-html-canvas/
        // https://developer.mozilla.org/en-US/docs/Web/API/CanvasRenderingContext2D/globalCompositeOperation
        // Default is source-over
        // PORT-TODO: upstream value is `null`; represented as NSNull() to retain the key in
        // the [String: Any] bag (merge guards null/undefined when consuming).
        "blendMode": NSNull(),

        "stateAnimation": [
            "duration": 300,
            "easing": "cubicOut"
        ] as [String: Any],

        "animation": "auto",
        "animationDuration": 1000,
        "animationDurationUpdate": 500,
        "animationEasing": "cubicInOut",
        "animationEasingUpdate": "cubicInOut",

        "animationThreshold": 2000,

        // Configuration for progressive/incremental rendering
        "progressiveThreshold": 3000,
        "progressive": 400,

        // Threshold of if use single hover layer to optimize.
        // It is recommended that `hoverLayerThreshold` is equivalent to or less than
        // `progressiveThreshold`, otherwise hover will cause restart of progressive,
        // which is unexpected.
        // see example <echarts/test/heatmap-large.html>.
        "hoverLayerThreshold": 3000,

        // See: module:echarts/scale/Time
        "useUTC": false
    ]
}
