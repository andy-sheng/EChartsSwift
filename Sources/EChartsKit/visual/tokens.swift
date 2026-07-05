// Ported from echarts/src/visual/tokens.ts — keep in sync with upstream
/*
* Licensed to the Apache Software Foundation (ASF) under one
* or more contributor license agreements.  See the NOTICE file
* distributed with this work for additional information
* regarding copyright ownership.  The ASF licenses this file
* to you under the Apache License, Version 2.0 (the
* "License"); you may not use this file except in compliance
* with the License.  You may obtain a copy of the License at
*
*   http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing,
* software distributed under the License is distributed on an
* "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
* KIND, either express or implied.  See the License for the
* specific language governing permissions and limitations
* under the License.
*/

import Foundation
import ZRenderKit

// import { extend } from 'zrender/src/core/util';       -> the `extend(color, {...})` merge is
//   inlined: the derived color fields (primary/secondary/.../axisMinorSplitLine) are assigned
//   directly in `makeLightColor()`.
// import { modifyHSL } from 'zrender/src/tool/color';   -> ZRenderKit.color.modifyHSL

// interface ColorToken { theme: string[]; neutral00..neutral99; accent05..accent95;
//   transparent; primary; secondary; ...; axisMinorSplitLine; }
//   -> Swift struct with the exact upstream field names. Every field is `let`; `theme` is [String].
public struct ColorToken {
    public let theme: [String]

    public let neutral00: String
    public let neutral05: String
    public let neutral10: String
    public let neutral15: String
    public let neutral20: String
    public let neutral25: String
    public let neutral30: String
    public let neutral35: String
    public let neutral40: String
    public let neutral45: String
    public let neutral50: String
    public let neutral55: String
    public let neutral60: String
    public let neutral65: String
    public let neutral70: String
    public let neutral75: String
    public let neutral80: String
    public let neutral85: String
    public let neutral90: String
    public let neutral95: String
    public let neutral99: String

    public let accent05: String
    public let accent10: String
    public let accent15: String
    public let accent20: String
    public let accent25: String
    public let accent30: String
    public let accent35: String
    public let accent40: String
    public let accent45: String
    public let accent50: String
    public let accent55: String
    public let accent60: String
    public let accent65: String
    public let accent70: String
    public let accent75: String
    public let accent80: String
    public let accent85: String
    public let accent90: String
    public let accent95: String

    public let transparent: String
    // NOTE: `highlight` is declared before the derived block in the interface, but assigned in the
    //   base literal (line 168). Field order here mirrors the interface declaration order.
    public let highlight: String

    public let primary: String
    public let secondary: String
    public let tertiary: String
    public let quaternary: String
    public let disabled: String

    public let border: String
    public let borderTint: String
    public let borderShade: String

    public let background: String
    public let backgroundTint: String
    public let backgroundTransparent: String
    public let backgroundShade: String

    public let shadow: String
    public let shadowTint: String

    public let axisLine: String
    public let axisLineTint: String
    public let axisTick: String
    public let axisTickMinor: String
    public let axisLabel: String
    public let axisSplitLine: String
    public let axisMinorSplitLine: String
}

// interface Tokens { color: ColorToken; darkColor: ColorToken; size: {...} }
public struct SizeToken {
    public let xxs: Double
    public let xs: Double
    public let s: Double
    public let m: Double
    public let l: Double
    public let xl: Double
    public let xxl: Double
    public let xxxl: Double
}

public struct Tokens {
    public let color: ColorToken
    public let darkColor: ColorToken
    public let size: SizeToken
}

// const color = tokens.color = { theme: [...], neutral00: '#fff', ... }
// extend(color, { primary: color.neutral80, ... })
//   -> both the base literal and the `extend(...)` merge are assembled here into a single
//      ColorToken. Local constants preserve the `color.neutralXX` self-references upstream uses.
private func makeLightColor() -> ColorToken {
    let neutral00 = "#fff"
    let neutral05 = "#f4f7fd"
    let neutral10 = "#e8ebf0"
    let neutral15 = "#dbdee4"
    let neutral20 = "#cfd2d7"
    let neutral25 = "#c3c5cb"
    let neutral30 = "#b7b9be"
    let neutral35 = "#aaacb2"
    let neutral40 = "#9ea0a5"
    let neutral45 = "#929399"
    let neutral50 = "#86878c"
    let neutral55 = "#797b7f"
    let neutral60 = "#6d6e73"
    let neutral65 = "#616266"
    let neutral70 = "#54555a"
    let neutral75 = "#48494d"
    let neutral80 = "#3c3c41"
    let neutral85 = "#303034"
    let neutral90 = "#232328"
    let neutral95 = "#17171b"
    let neutral99 = "#000"

    return ColorToken(
        theme: [
            "#5070dd",
            "#b6d634",
            "#505372",
            "#ff994d",
            "#0ca8df",
            "#ffd10a",
            "#fb628b",
            "#785db0",
            "#3fbe95"
        ],

        neutral00: neutral00,
        neutral05: neutral05,
        neutral10: neutral10,
        neutral15: neutral15,
        neutral20: neutral20,
        neutral25: neutral25,
        neutral30: neutral30,
        neutral35: neutral35,
        neutral40: neutral40,
        neutral45: neutral45,
        neutral50: neutral50,
        neutral55: neutral55,
        neutral60: neutral60,
        neutral65: neutral65,
        neutral70: neutral70,
        neutral75: neutral75,
        neutral80: neutral80,
        neutral85: neutral85,
        neutral90: neutral90,
        neutral95: neutral95,
        neutral99: neutral99,

        accent05: "#eff1f9",
        accent10: "#e0e4f2",
        accent15: "#d0d6ec",
        accent20: "#c0c9e6",
        accent25: "#b1bbdf",
        accent30: "#a1aed9",
        accent35: "#91a0d3",
        accent40: "#8292cc",
        accent45: "#7285c6",
        accent50: "#6578ba",
        accent55: "#5c6da9",
        accent60: "#536298",
        accent65: "#4a5787",
        accent70: "#404c76",
        accent75: "#374165",
        accent80: "#2e3654",
        accent85: "#252b43",
        accent90: "#1b2032",
        accent95: "#121521",

        transparent: "rgba(0,0,0,0)",

        highlight: "rgba(255,231,130,0.8)",

        // ---- extend(color, {...}) ----
        primary: neutral80,
        secondary: neutral70,
        tertiary: neutral60,
        quaternary: neutral50,
        disabled: neutral20,

        border: neutral30,
        borderTint: neutral20,
        borderShade: neutral40,

        background: neutral05,
        backgroundTint: "rgba(234,237,245,0.5)",
        backgroundTransparent: "rgba(255,255,255,0)",
        backgroundShade: neutral10,

        shadow: "rgba(0,0,0,0.2)",
        shadowTint: "rgba(129,130,136,0.2)",

        axisLine: neutral70,
        axisLineTint: neutral40,
        axisTick: neutral70,
        axisTickMinor: neutral60,
        axisLabel: neutral70,
        axisSplitLine: neutral15,
        axisMinorSplitLine: neutral05
    )
}

// for (const key in color) { ... tokens.darkColor[key] = modifyHSL(...) }
//   -> the darkColor derivation loop, applied field-by-field:
//      - `theme`     : copied verbatim (color.theme.slice()).
//      - `highlight` : hard-set to 'rgba(255,231,130,0.4)'.
//      - `accent*`   : modifyHSL(hex, null, s => s * 0.5, l => Math.min(1, 1.3 - l)).
//      - all others  : modifyHSL(hex, null, s => s * 0.9, l => 1 - Math.pow(l, 1.5)).
private func makeDarkColor(_ c: ColorToken) -> ColorToken {
    // else-branch transform (desaturate slightly, invert-and-lighten).
    func d(_ hex: String) -> String {
        return ZRenderKit.color.modifyHSL(
            hex, nil,
            .function { s in s * 0.9 },
            .function { l in 1 - pow(l, 1.5) }
        ) ?? hex
    }
    // accent-branch transform (desaturate strongly, lighten toward white).
    func a(_ hex: String) -> String {
        return ZRenderKit.color.modifyHSL(
            hex, nil,
            .function { s in s * 0.5 },
            .function { l in min(1, 1.3 - l) }
        ) ?? hex
    }

    return ColorToken(
        theme: c.theme,   // Don't modify theme colors. (color.theme.slice())

        neutral00: d(c.neutral00),
        neutral05: d(c.neutral05),
        neutral10: d(c.neutral10),
        neutral15: d(c.neutral15),
        neutral20: d(c.neutral20),
        neutral25: d(c.neutral25),
        neutral30: d(c.neutral30),
        neutral35: d(c.neutral35),
        neutral40: d(c.neutral40),
        neutral45: d(c.neutral45),
        neutral50: d(c.neutral50),
        neutral55: d(c.neutral55),
        neutral60: d(c.neutral60),
        neutral65: d(c.neutral65),
        neutral70: d(c.neutral70),
        neutral75: d(c.neutral75),
        neutral80: d(c.neutral80),
        neutral85: d(c.neutral85),
        neutral90: d(c.neutral90),
        neutral95: d(c.neutral95),
        neutral99: d(c.neutral99),

        accent05: a(c.accent05),
        accent10: a(c.accent10),
        accent15: a(c.accent15),
        accent20: a(c.accent20),
        accent25: a(c.accent25),
        accent30: a(c.accent30),
        accent35: a(c.accent35),
        accent40: a(c.accent40),
        accent45: a(c.accent45),
        accent50: a(c.accent50),
        accent55: a(c.accent55),
        accent60: a(c.accent60),
        accent65: a(c.accent65),
        accent70: a(c.accent70),
        accent75: a(c.accent75),
        accent80: a(c.accent80),
        accent85: a(c.accent85),
        accent90: a(c.accent90),
        accent95: a(c.accent95),

        transparent: d(c.transparent),

        highlight: "rgba(255,231,130,0.4)",

        primary: d(c.primary),
        secondary: d(c.secondary),
        tertiary: d(c.tertiary),
        quaternary: d(c.quaternary),
        disabled: d(c.disabled),

        border: d(c.border),
        borderTint: d(c.borderTint),
        borderShade: d(c.borderShade),

        background: d(c.background),
        backgroundTint: d(c.backgroundTint),
        backgroundTransparent: d(c.backgroundTransparent),
        backgroundShade: d(c.backgroundShade),

        shadow: d(c.shadow),
        shadowTint: d(c.shadowTint),

        axisLine: d(c.axisLine),
        axisLineTint: d(c.axisLineTint),
        axisTick: d(c.axisTick),
        axisTickMinor: d(c.axisTickMinor),
        axisLabel: d(c.axisLabel),
        axisSplitLine: d(c.axisSplitLine),
        axisMinorSplitLine: d(c.axisMinorSplitLine)
    )
}

private func makeTokens() -> Tokens {
    let color = makeLightColor()
    let darkColor = makeDarkColor(color)
    // tokens.size = { xxs: 2, xs: 5, s: 10, m: 15, l: 20, xl: 30, xxl: 40, xxxl: 50 }
    let size = SizeToken(xxs: 2, xs: 5, s: 10, m: 15, l: 20, xl: 30, xxl: 40, xxxl: 50)
    return Tokens(color: color, darkColor: darkColor, size: size)
}

// export default tokens;  -> read as `tokens.color.neutral30`, `tokens.size.m`, etc.
public let tokens: Tokens = makeTokens()
