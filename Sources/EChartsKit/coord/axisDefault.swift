// Ported from echarts/src/coord/axisDefault.ts — keep in sync with upstream

import Foundation
import ZRenderKit

// import * as zrUtil from 'zrender/src/core/util';  → util.* (ZRenderKit)
// import tokens from '../visual/tokens';               → `tokens` (visual/tokens.swift, global `let tokens`)
// import { AxisBaseOption } from './axisCommonTypes';  → dynamic option bag ([String: Any])
//
// PORT-NOTE: visual/tokens.swift is ported; the `tokens.color.*` values consumed below are wired to the
// real `tokens` namespace (resolved constants for reference):
//   tokens.color.axisLine           = color.neutral70            = '#54555a'
//   tokens.color.axisLabel          = color.neutral70            = '#54555a'
//   tokens.color.axisSplitLine      = color.neutral15            = '#dbdee4'
//   tokens.color.axisMinorSplitLine = color.neutral05            = '#f4f7fd'  (used by valueAxis)
//   tokens.color.backgroundTint     = 'rgba(234,237,245,0.5)'
//   tokens.color.backgroundTransparent = 'rgba(255,255,255,0)'
//   tokens.color.neutral00          = '#fff'
//   tokens.color.border             = color.neutral30            = '#b7b9be'

// upstream: `export default { category, value, time, log }`
// The axis defaults are dynamic option bags, modelled as [String: Any] per the dynamic option-tree
// convention (deep-merged via util.merge / filled via util.defaults, keyed via Model.get). The map
// consumed by `axisModelCreator` is exposed as `axisDefault.option` (keys category/value/time/log).
public enum axisDefault {

    // upstream: const defaultOption: AxisBaseOption = { ... }  (module-const, not exported)
    private static let defaultOption: [String: Any] = [
        "show": true,
        // zlevel: 0,
        "z": 0,
        // Inverse the axis.
        "inverse": false,

        // Axis name displayed.
        "name": "",
        // 'start' | 'middle' | 'end'
        "nameLocation": "end",
        // By degree. By default auto rotate by nameLocation.
        // PORT-NOTE: upstream value is `null`; NSNull() retains the key in the [String: Any] bag.
        "nameRotate": NSNull(),
        "nameTruncate": [
            // PORT-NOTE: upstream value is `null`; NSNull() retains the key.
            "maxWidth": NSNull(),
            "ellipsis": "...",
            "placeholder": "."
        ] as [String: Any],
        // Use global text style by default.
        "nameTextStyle": [String: Any](
            // textMargin: never, // The default value will be specified based on `nameLocation`.
        ),
        // The gap between axisName and axisLine.
        "nameGap": 15,

        // Default `false` to support tooltip.
        "silent": false,
        // Default `false` to avoid legacy user event listener fail.
        "triggerEvent": false,

        "tooltip": [
            "show": false
        ] as [String: Any],

        "axisPointer": [String: Any](),

        "axisLine": [
            "show": true,
            "onZero": "auto",
            // PORT-NOTE: upstream value is `null`; NSNull() retains the key.
            "onZeroAxisIndex": NSNull(),
            "lineStyle": [
                "color": tokens.color.axisLine,
                "width": 1,
                "type": "solid"
            ] as [String: Any],
            // The arrow at both ends the the axis.
            "symbol": ["none", "none"],
            "symbolSize": [10, 15],
            "breakLine": true,
        ] as [String: Any],
        "axisTick": [
            "show": true,
            // Whether axisTick is inside the grid or outside the grid.
            "inside": false,
            // The length of axisTick.
            "length": 5,
            "lineStyle": [
                "width": 1
            ] as [String: Any]
        ] as [String: Any],
        "axisLabel": [
            "show": true,
            // Whether axisLabel is inside the grid or outside the grid.
            "inside": false,
            "rotate": 0,
            // true | false | null/undefined (auto)
            // PORT-NOTE: upstream value is `null`; NSNull() retains the key.
            "showMinLabel": NSNull(),
            // true | false | null/undefined (auto)
            // PORT-NOTE: upstream value is `null`; NSNull() retains the key.
            "showMaxLabel": NSNull(),
            "margin": 8,
            // formatter: null,
            "fontSize": 12,
            "color": tokens.color.axisLabel,
            // In scenarios like axis labels, when labels text's progression direction matches the label
            // layout direction (e.g., when all letters are in a single line), extra start/end margin is
            // needed to prevent the text from appearing visually joined. In the other case, when lables
            // are stacked (e.g., having rotation or horizontal labels on yAxis), the layout needs to be
            // compact, so NO extra top/bottom margin should be applied.
            "textMargin": [0, 3], // Empirical default value.
        ] as [String: Any],
        "splitLine": [
            "show": true,
            "showMinLine": true,
            "showMaxLine": true,
            "lineStyle": [
                "color": tokens.color.axisSplitLine,
                "width": 1,
                "type": "solid"
            ] as [String: Any]
        ] as [String: Any],
        "splitArea": [
            "show": false,
            "areaStyle": [
                "color": [
                    tokens.color.backgroundTint,
                    tokens.color.backgroundTransparent
                ]
            ] as [String: Any]
        ] as [String: Any],
        "breakArea": [
            "show": true,
            "itemStyle": [
                "color": tokens.color.neutral00,
                // Break border color should be darker than the splitLine
                // because it has opacity and should be more prominent
                "borderColor": tokens.color.border,
                "borderWidth": 1,
                "borderType": [3, 3],
                "opacity": 0.6
            ] as [String: Any],
            "zigzagAmplitude": 4,
            "zigzagMinSpan": 4,
            "zigzagMaxSpan": 20,
            "zigzagZ": 100,
            "expandOnClick": true,
        ] as [String: Any],
        "breakLabelLayout": [
            "moveOverlap": "auto",
        ] as [String: Any]
    ]

    // upstream: const categoryAxis = zrUtil.merge({ ... }, defaultOption);
    private static let categoryAxis: [String: Any] = {
        var target: [String: Any] = [
            // The gap at both ends of the axis. For categoryAxis, boolean.
            "boundaryGap": true,
            // Set false to faster category collection.
            // PORT-NOTE: upstream value is `null`; NSNull() retains the key.
            "deduplication": NSNull(),
            "jitter": 0,
            "jitterOverlap": true,
            "jitterMargin": 2,
            // splitArea: {
                // show: false
            // },
            "splitLine": [
                "show": false
            ] as [String: Any],
            "axisTick": [
                // If tick is align with label when boundaryGap is true
                "alignWithLabel": false,
                "interval": "auto",
                "show": "auto"
            ] as [String: Any],
            "axisLabel": [
                "interval": "auto"
            ] as [String: Any]
        ]
        return util.merge(&target, defaultOption)
    }()

    // upstream: const valueAxis = zrUtil.merge({ ... }, defaultOption);
    private static let valueAxis: [String: Any] = {
        var target: [String: Any] = [
            "boundaryGap": [0, 0],

            "axisLine": [
                // Not shown when other axis is categoryAxis in cartesian
                "show": "auto"
            ] as [String: Any],
            "axisTick": [
                // Not shown when other axis is categoryAxis in cartesian
                "show": "auto"
            ] as [String: Any],

            // TODO
            // min/max: [30, datamin, 60] or [20, datamin] or [datamin, 60]

            "splitNumber": 5,

            "minorTick": [
                // Minor tick, not available for cateogry axis.
                "show": false,
                // Split number of minor ticks. The value should be in range of (0, 100)
                "splitNumber": 5,
                // Length of minor tick
                "length": 3,

                // Line style
                "lineStyle": [String: Any](
                    // Default to be same with axisTick
                )
            ] as [String: Any],

            "minorSplitLine": [
                "show": false,

                "lineStyle": [
                    "color": tokens.color.axisMinorSplitLine,
                    "width": 1
                ] as [String: Any]
            ] as [String: Any]
        ]
        return util.merge(&target, defaultOption)
    }()

    // upstream: const timeAxis = zrUtil.merge({ ... }, valueAxis);
    private static let timeAxis: [String: Any] = {
        var target: [String: Any] = [
            "splitNumber": 6,
            "axisLabel": [
                // The default value of TimeScale is determined in `AxisBuilder`
                // showMinLabel: false,
                // showMaxLabel: false,
                "rich": [
                    "primary": [
                        "fontWeight": "bold"
                    ] as [String: Any]
                ] as [String: Any]
            ] as [String: Any],
            "splitLine": [
                "show": false
            ] as [String: Any]
        ]
        return util.merge(&target, valueAxis)
    }()

    // upstream: const logAxis = zrUtil.defaults({ ... }, valueAxis);
    private static let logAxis: [String: Any] = {
        var target: [String: Any] = [
            "logBase": 10
        ]
        return util.defaults(&target, valueAxis)
    }()

    // upstream: export default { category, value, time, log };
    public static let option: [String: Any] = [
        "category": categoryAxis,
        "value": valueAxis,
        "time": timeAxis,
        "log": logAxis
    ]
}
