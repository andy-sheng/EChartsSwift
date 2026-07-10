// Ported from zrender/src/tool/color.ts — keep in sync with upstream

import Foundation

// import LRU from '../core/LRU';                                  → Core/LRU.swift (LRU<T>)
// import { extend, isFunction, isGradientObject, isString, map }  → Core/util.swift
//   `map` → util.map. The runtime guards `isFunction` / `isString` / `isGradientObject`
//   and `extend` have no direct equivalent here: `modifyHSL`'s callable params are modeled
//   as the `HSLParam` enum (the `.function` case replaces `isFunction`), and `liftColor`'s
//   `string | GradientObject` argument is modeled as the `ColorValue` enum (the
//   `.string` / `.gradient` switch replaces `isString` / `isGradientObject`).
// import { GradientObject } from '../graphic/Gradient';           → Graphic/Gradient.swift
//   (GradientObject / GradientColorStop). See the `extend({}, color)` PORT-TODO on `liftColor`.

/// Upstream color params are typed `number | string` (e.g. the `(number | string)[]`
/// returned by `.split(',')`, then partly overwritten with parsed floats). Swift has no
/// untagged union, so — like `LRUKey` in LRU.swift — we model the value as a tagged enum.
/// Literal conformances keep call sites close to upstream (`parseCssInt("50%")`).
public enum CssParam {
    case number(Double)
    case string(String)
}

extension CssParam: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
}
extension CssParam: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) { self = .number(Double(value)) }
}
extension CssParam: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) { self = .number(value) }
}

/// Upstream `lerp` returns `string | LerpFullOutput` (TS overloads keyed on `fullOutput`).
/// Swift has no untagged union, so the union return is modelled as a tagged enum — the
/// `fullOutput` flag selects which case is produced (CONVENTIONS §1, like `CssParam` above).
public enum LerpResult {
    case color(String)
    case full(LerpFullOutput)
}

/// upstream: `type LerpFullOutput = { color; leftIndex; rightIndex; value }` (a local TS type).
/// `number` → `Double` (CONVENTIONS §1); `leftIndex`/`rightIndex` are produced by floor/ceil
/// but stay `Double` to match the upstream field types.
public struct LerpFullOutput {
    public var color: String
    public var leftIndex: Double
    public var rightIndex: Double
    public var value: Double

    public init(color: String, leftIndex: Double, rightIndex: Double, value: Double) {
        self.color = color
        self.leftIndex = leftIndex
        self.rightIndex = rightIndex
        self.value = value
    }
}

/// upstream `modifyHSL` params are `number | string | ((x: number) => number)`. Modelled as a
/// tagged enum (no untagged union in Swift). The `.function` case replaces the runtime
/// `isFunction(...)` guard — callers resolve "is this callable" statically, as the
/// `util.isFunction` PORT-TODO recommends. Literal conformances keep call sites close to
/// upstream (`modifyHSL(c, 180, 0.5, "50%")`).
public enum HSLParam {
    case number(Double)
    case string(String)
    case function((Double) -> Double)
}

extension HSLParam: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
}
extension HSLParam: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) { self = .number(Double(value)) }
}
extension HSLParam: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) { self = .number(value) }
}

/// upstream `liftColor` is overloaded `string → string` / `GradientObject → GradientObject`;
/// the implementation takes `string | GradientObject`. Modelled as a tagged enum; the
/// `.string` / `.gradient` switch replaces the runtime `isString` / `isGradientObject` guards.
public enum ColorValue {
    case string(String)
    case gradient(GradientObject)
}

extension ColorValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
}

/// Free-function module → caseless `enum` namespace (CONVENTIONS §2).
/// Call sites stay byte-identical to upstream: `color.parse(...)`, `color.lum(...)`.
public enum color {

    static let kCSSColorTable: [String: [Double]] = [
        "transparent": [0, 0, 0, 0], "aliceblue": [240, 248, 255, 1],
        "antiquewhite": [250, 235, 215, 1], "aqua": [0, 255, 255, 1],
        "aquamarine": [127, 255, 212, 1], "azure": [240, 255, 255, 1],
        "beige": [245, 245, 220, 1], "bisque": [255, 228, 196, 1],
        "black": [0, 0, 0, 1], "blanchedalmond": [255, 235, 205, 1],
        "blue": [0, 0, 255, 1], "blueviolet": [138, 43, 226, 1],
        "brown": [165, 42, 42, 1], "burlywood": [222, 184, 135, 1],
        "cadetblue": [95, 158, 160, 1], "chartreuse": [127, 255, 0, 1],
        "chocolate": [210, 105, 30, 1], "coral": [255, 127, 80, 1],
        "cornflowerblue": [100, 149, 237, 1], "cornsilk": [255, 248, 220, 1],
        "crimson": [220, 20, 60, 1], "cyan": [0, 255, 255, 1],
        "darkblue": [0, 0, 139, 1], "darkcyan": [0, 139, 139, 1],
        "darkgoldenrod": [184, 134, 11, 1], "darkgray": [169, 169, 169, 1],
        "darkgreen": [0, 100, 0, 1], "darkgrey": [169, 169, 169, 1],
        "darkkhaki": [189, 183, 107, 1], "darkmagenta": [139, 0, 139, 1],
        "darkolivegreen": [85, 107, 47, 1], "darkorange": [255, 140, 0, 1],
        "darkorchid": [153, 50, 204, 1], "darkred": [139, 0, 0, 1],
        "darksalmon": [233, 150, 122, 1], "darkseagreen": [143, 188, 143, 1],
        "darkslateblue": [72, 61, 139, 1], "darkslategray": [47, 79, 79, 1],
        "darkslategrey": [47, 79, 79, 1], "darkturquoise": [0, 206, 209, 1],
        "darkviolet": [148, 0, 211, 1], "deeppink": [255, 20, 147, 1],
        "deepskyblue": [0, 191, 255, 1], "dimgray": [105, 105, 105, 1],
        "dimgrey": [105, 105, 105, 1], "dodgerblue": [30, 144, 255, 1],
        "firebrick": [178, 34, 34, 1], "floralwhite": [255, 250, 240, 1],
        "forestgreen": [34, 139, 34, 1], "fuchsia": [255, 0, 255, 1],
        "gainsboro": [220, 220, 220, 1], "ghostwhite": [248, 248, 255, 1],
        "gold": [255, 215, 0, 1], "goldenrod": [218, 165, 32, 1],
        "gray": [128, 128, 128, 1], "green": [0, 128, 0, 1],
        "greenyellow": [173, 255, 47, 1], "grey": [128, 128, 128, 1],
        "honeydew": [240, 255, 240, 1], "hotpink": [255, 105, 180, 1],
        "indianred": [205, 92, 92, 1], "indigo": [75, 0, 130, 1],
        "ivory": [255, 255, 240, 1], "khaki": [240, 230, 140, 1],
        "lavender": [230, 230, 250, 1], "lavenderblush": [255, 240, 245, 1],
        "lawngreen": [124, 252, 0, 1], "lemonchiffon": [255, 250, 205, 1],
        "lightblue": [173, 216, 230, 1], "lightcoral": [240, 128, 128, 1],
        "lightcyan": [224, 255, 255, 1], "lightgoldenrodyellow": [250, 250, 210, 1],
        "lightgray": [211, 211, 211, 1], "lightgreen": [144, 238, 144, 1],
        "lightgrey": [211, 211, 211, 1], "lightpink": [255, 182, 193, 1],
        "lightsalmon": [255, 160, 122, 1], "lightseagreen": [32, 178, 170, 1],
        "lightskyblue": [135, 206, 250, 1], "lightslategray": [119, 136, 153, 1],
        "lightslategrey": [119, 136, 153, 1], "lightsteelblue": [176, 196, 222, 1],
        "lightyellow": [255, 255, 224, 1], "lime": [0, 255, 0, 1],
        "limegreen": [50, 205, 50, 1], "linen": [250, 240, 230, 1],
        "magenta": [255, 0, 255, 1], "maroon": [128, 0, 0, 1],
        "mediumaquamarine": [102, 205, 170, 1], "mediumblue": [0, 0, 205, 1],
        "mediumorchid": [186, 85, 211, 1], "mediumpurple": [147, 112, 219, 1],
        "mediumseagreen": [60, 179, 113, 1], "mediumslateblue": [123, 104, 238, 1],
        "mediumspringgreen": [0, 250, 154, 1], "mediumturquoise": [72, 209, 204, 1],
        "mediumvioletred": [199, 21, 133, 1], "midnightblue": [25, 25, 112, 1],
        "mintcream": [245, 255, 250, 1], "mistyrose": [255, 228, 225, 1],
        "moccasin": [255, 228, 181, 1], "navajowhite": [255, 222, 173, 1],
        "navy": [0, 0, 128, 1], "oldlace": [253, 245, 230, 1],
        "olive": [128, 128, 0, 1], "olivedrab": [107, 142, 35, 1],
        "orange": [255, 165, 0, 1], "orangered": [255, 69, 0, 1],
        "orchid": [218, 112, 214, 1], "palegoldenrod": [238, 232, 170, 1],
        "palegreen": [152, 251, 152, 1], "paleturquoise": [175, 238, 238, 1],
        "palevioletred": [219, 112, 147, 1], "papayawhip": [255, 239, 213, 1],
        "peachpuff": [255, 218, 185, 1], "peru": [205, 133, 63, 1],
        "pink": [255, 192, 203, 1], "plum": [221, 160, 221, 1],
        "powderblue": [176, 224, 230, 1], "purple": [128, 0, 128, 1],
        "red": [255, 0, 0, 1], "rosybrown": [188, 143, 143, 1],
        "royalblue": [65, 105, 225, 1], "saddlebrown": [139, 69, 19, 1],
        "salmon": [250, 128, 114, 1], "sandybrown": [244, 164, 96, 1],
        "seagreen": [46, 139, 87, 1], "seashell": [255, 245, 238, 1],
        "sienna": [160, 82, 45, 1], "silver": [192, 192, 192, 1],
        "skyblue": [135, 206, 235, 1], "slateblue": [106, 90, 205, 1],
        "slategray": [112, 128, 144, 1], "slategrey": [112, 128, 144, 1],
        "snow": [255, 250, 250, 1], "springgreen": [0, 255, 127, 1],
        "steelblue": [70, 130, 180, 1], "tan": [210, 180, 140, 1],
        "teal": [0, 128, 128, 1], "thistle": [216, 191, 216, 1],
        "tomato": [255, 99, 71, 1], "turquoise": [64, 224, 208, 1],
        "violet": [238, 130, 238, 1], "wheat": [245, 222, 179, 1],
        "white": [255, 255, 255, 1], "whitesmoke": [245, 245, 245, 1],
        "yellow": [255, 255, 0, 1], "yellowgreen": [154, 205, 50, 1]
    ]

    static func clampCssByte(_ i: Double) -> Double {  // Clamp to integer 0 .. 255.
        var i = i
        i = jsRound(i)  // Math.round. Seems to be what Chrome does (vs truncation).
        return i < 0 ? 0 : i > 255 ? 255 : i
    }

    static func clampCssAngle(_ i: Double) -> Double {  // Clamp to integer 0 .. 360.
        var i = i
        i = jsRound(i)  // Math.round. Seems to be what Chrome does (vs truncation).
        return i < 0 ? 0 : i > 360 ? 360 : i
    }

    static func clampCssFloat(_ f: Double) -> Double {  // Clamp to float 0.0 .. 1.0.
        return f < 0 ? 0 : f > 1 ? 1 : f
    }

    public static func parseCssInt(_ val: CssParam) -> Double {  // int or percentage.
        let str = stringOf(val)  // upstream: `let str = val as string` (no-op TS cast)
        if str.count != 0 && charAt(str, str.count - 1) == "%" {
            return clampCssByte(parseFloat(str) / 100 * 255)
        }
        return clampCssByte(parseInt(str, 10))
    }

    public static func parseCssFloat(_ val: CssParam) -> Double {  // float or percentage.
        let str = stringOf(val)  // upstream: `let str = val as string` (no-op TS cast)
        if str.count != 0 && charAt(str, str.count - 1) == "%" {
            return clampCssFloat(parseFloat(str) / 100)
        }
        return clampCssFloat(parseFloat(str))
    }

    static func cssHueToRgb(_ m1: Double, _ m2: Double, _ h: Double) -> Double {
        var h = h
        if h < 0 {
            h += 1
        }
        else if h > 1 {
            h -= 1
        }

        if h * 6 < 1 {
            return m1 + (m2 - m1) * h * 6
        }
        if h * 2 < 1 {
            return m2
        }
        if h * 3 < 2 {
            return m1 + (m2 - m1) * (2 / 3 - h) * 6
        }
        return m1
    }

    static func lerpNumber(_ a: Double, _ b: Double, _ p: Double) -> Double {
        return a + (b - a) * p
    }

    // setRgba/copyRgba: out-param dropped, value-returning per CONVENTIONS §3.
    // (The original mutates `out` in place and returns it; we return a fresh 4-array.
    //  Every caller reassigns the result.)
    static func setRgba(_ out: [Double], _ r: Double, _ g: Double, _ b: Double, _ a: Double) -> [Double] {
        var out = out
        out = [r, g, b, a]
        return out
    }
    static func copyRgba(_ out: [Double], _ a: [Double]) -> [Double] {
        var out = out
        out = [a[0], a[1], a[2], a[3]]
        return out
    }

    static let colorCache = LRU<[Double]>(20)
    static var lastRemovedArr: [Double]? = nil

    static func putToCache(_ colorStr: String, _ rgbaArr: [Double]) {
        // Reuse removed array
        if let lra = lastRemovedArr {
            lastRemovedArr = copyRgba(lra, rgbaArr)
        }
        // upstream: lastRemovedArr = colorCache.put(colorStr, lastRemovedArr || rgbaArr.slice())
        // (Swift arrays are value types, so `?? rgbaArr` stores a copy, matching `.slice()`.)
        lastRemovedArr = colorCache.put(.string(colorStr), lastRemovedArr ?? rgbaArr)
    }

    // upstream: parse(colorStr, rgbaArr?) — out-param `rgbaArr` mutation dropped per §3;
    // value-returning. Internal callers all rely on the return value (`if (colorArr)`).
    // PORT-TODO: the original's error branches (`setRgba(rgbaArr,0,0,0,1); return;`) mutate
    // `rgbaArr` *and* return undefined; here those branches return nil (no out-param).
    @discardableResult
    public static func parse(_ colorStr: String, _ rgbaArr: [Double]? = nil) -> [Double]? {
        if colorStr.isEmpty {  // if (!colorStr)
            return nil
        }
        var rgbaArr = rgbaArr ?? []

        if let cached = colorCache.get(.string(colorStr)) {
            return copyRgba(rgbaArr, cached)
        }

        // colorStr may be not string
        // (TS: `colorStr = colorStr + ''`; a no-op for our String parameter.)
        // Remove all whitespace, not compliant, but should just be more accepting.
        let str = colorStr.replacingOccurrences(of: " ", with: "").lowercased()

        // Color keywords (and transparent) lookup.
        if let entry = kCSSColorTable[str] {  // if (str in kCSSColorTable)
            rgbaArr = copyRgba(rgbaArr, entry)
            putToCache(colorStr, rgbaArr)
            return rgbaArr
        }

        // supports the forms #rgb, #rrggbb, #rgba, #rrggbbaa
        // #rrggbbaa(use the last pair of digits as alpha)
        // see https://drafts.csswg.org/css-color/#hex-notation
        let strLen = str.count
        if charAt(str, 0) == "#" {
            if strLen == 4 || strLen == 5 {
                let iv = parseInt(slice(str, 1, 4), 16)  // TODO(deanm): Stricter parsing.
                if !(iv >= 0 && iv <= Double(0xfff)) {
                    rgbaArr = setRgba(rgbaArr, 0, 0, 0, 1)
                    return nil  // Covers NaN.
                }
                let ivI = Int(iv)
                // interpret values of the form #rgb as #rrggbb and #rgba as #rrggbbaa
                rgbaArr = setRgba(rgbaArr,
                    Double(((ivI & 0xf00) >> 4) | ((ivI & 0xf00) >> 8)),
                    Double((ivI & 0xf0) | ((ivI & 0xf0) >> 4)),
                    Double((ivI & 0xf) | ((ivI & 0xf) << 4)),
                    strLen == 5 ? parseInt(slice(str, 4), 16) / Double(0xf) : 1
                )
                putToCache(colorStr, rgbaArr)
                return rgbaArr
            }
            else if strLen == 7 || strLen == 9 {
                let iv = parseInt(slice(str, 1, 7), 16)  // TODO(deanm): Stricter parsing.
                if !(iv >= 0 && iv <= Double(0xffffff)) {
                    rgbaArr = setRgba(rgbaArr, 0, 0, 0, 1)
                    return nil  // Covers NaN.
                }
                let ivI = Int(iv)
                rgbaArr = setRgba(rgbaArr,
                    Double((ivI & 0xff0000) >> 16),
                    Double((ivI & 0xff00) >> 8),
                    Double(ivI & 0xff),
                    strLen == 9 ? parseInt(slice(str, 7), 16) / Double(0xff) : 1
                )
                putToCache(colorStr, rgbaArr)
                return rgbaArr
            }

            return nil
        }
        let op = indexOf(str, "(")
        let ep = indexOf(str, ")")
        if op != -1 && ep + 1 == strLen {
            let fname = substr(str, 0, op)
            var params: [CssParam] = substr(str, op + 1, ep - (op + 1)).split(separator: ",", omittingEmptySubsequences: false).map { .string(String($0)) }
            var alpha = 1.0  // To allow case fallthrough.
            switch fname {
                case "rgba":
                    if params.count != 4 {
                        return params.count == 3
                            // to be compatible with rgb
                            ? setRgba(rgbaArr, cssPlus(params[0]), cssPlus(params[1]), cssPlus(params[2]), 1)
                            : setRgba(rgbaArr, 0, 0, 0, 1)
                    }
                    alpha = parseCssFloat(params.removeLast())  // jshint ignore:line  (params.pop())
                    fallthrough
                // Fall through.
                case "rgb":
                    if params.count >= 3 {
                        rgbaArr = setRgba(rgbaArr,
                            parseCssInt(params[0]),
                            parseCssInt(params[1]),
                            parseCssInt(params[2]),
                            params.count == 3 ? alpha : parseCssFloat(params[3])
                        )
                        putToCache(colorStr, rgbaArr)
                        return rgbaArr
                    }
                    else {
                        rgbaArr = setRgba(rgbaArr, 0, 0, 0, 1)
                        return nil
                    }
                case "hsla":
                    if params.count != 4 {
                        rgbaArr = setRgba(rgbaArr, 0, 0, 0, 1)
                        return nil
                    }
                    params[3] = .number(parseCssFloat(params[3]))
                    rgbaArr = hsla2rgba(params, rgbaArr)
                    putToCache(colorStr, rgbaArr)
                    return rgbaArr
                case "hsl":
                    if params.count != 3 {
                        rgbaArr = setRgba(rgbaArr, 0, 0, 0, 1)
                        return nil
                    }
                    rgbaArr = hsla2rgba(params, rgbaArr)
                    putToCache(colorStr, rgbaArr)
                    return rgbaArr
                default:
                    return nil
            }
        }

        rgbaArr = setRgba(rgbaArr, 0, 0, 0, 1)
        return nil
    }

    // hsla2rgba: out-param `rgba` dropped per §3, value-returning.
    static func hsla2rgba(_ hsla: [CssParam], _ rgba: [Double]? = nil) -> [Double] {
        let h = (((parseFloat(stringOf(hsla[0])).truncatingRemainder(dividingBy: 360)) + 360)
            .truncatingRemainder(dividingBy: 360)) / 360  // 0 .. 1
        // NOTE(deanm): According to the CSS spec s/l should only be
        // percentages, but we don't bother and let float or percentage.
        let s = parseCssFloat(hsla[1])
        let l = parseCssFloat(hsla[2])
        let m2 = l <= 0.5 ? l * (s + 1) : l + s - l * s
        let m1 = l * 2 - m2

        var rgba = rgba ?? []
        rgba = setRgba(rgba,
            clampCssByte(cssHueToRgb(m1, m2, h + 1 / 3) * 255),
            clampCssByte(cssHueToRgb(m1, m2, h) * 255),
            clampCssByte(cssHueToRgb(m1, m2, h - 1 / 3) * 255),
            1
        )

        if hsla.count == 4 {
            rgba[3] = numberOf(hsla[3])  // upstream: hsla[3] as number
        }

        return rgba
    }

    static func rgba2hsla(_ rgba: [Double]?) -> [Double]? {
        guard let rgba = rgba else {  // if (!rgba)
            return nil
        }

        // RGB from 0 to 255
        let R = rgba[0] / 255
        let G = rgba[1] / 255
        let B = rgba[2] / 255

        let vMin = Swift.min(R, G, B)  // Min. value of RGB
        let vMax = Swift.max(R, G, B)  // Max. value of RGB
        let delta = vMax - vMin  // Delta RGB value

        let L = (vMax + vMin) / 2
        var H: Double = 0
        var S: Double = 0
        // HSL results from 0 to 1
        if delta == 0 {
            H = 0
            S = 0
        }
        else {
            if L < 0.5 {
                S = delta / (vMax + vMin)
            }
            else {
                S = delta / (2 - vMax - vMin)
            }

            let deltaR = (((vMax - R) / 6) + (delta / 2)) / delta
            let deltaG = (((vMax - G) / 6) + (delta / 2)) / delta
            let deltaB = (((vMax - B) / 6) + (delta / 2)) / delta

            if R == vMax {
                H = deltaB - deltaG
            }
            else if G == vMax {
                H = (1 / 3) + deltaR - deltaB
            }
            else if B == vMax {
                H = (2 / 3) + deltaG - deltaR
            }

            if H < 0 {
                H += 1
            }

            if H > 1 {
                H -= 1
            }
        }

        var hsla = [H * 360, S, L]

        // upstream: `if (rgba[3] != null) hsla.push(rgba[3])`. Our rgba is always length 4.
        if rgba.count > 3 {
            hsla.append(rgba[3])
        }

        return hsla
    }

    @discardableResult
    public static func lift(_ color: String, _ level: Double) -> String? {
        var colorArr = parse(color)
        if colorArr != nil {
            for i in 0..<3 {
                if level < 0 {
                    colorArr![i] = Double(Int(colorArr![i] * (1 - level)))  // | 0  (truncate toward zero)
                }
                else {
                    colorArr![i] = Double(Int((255 - colorArr![i]) * level + colorArr![i]))  // | 0
                }
                if colorArr![i] > 255 {
                    colorArr![i] = 255
                }
                else if colorArr![i] < 0 {
                    colorArr![i] = 0
                }
            }
            return stringify(colorArr!, colorArr!.count == 4 ? "rgba" : "rgb")
        }
        return nil
    }

    public static func toHex(_ color: String) -> String? {
        let colorArr = parse(color)
        if let colorArr = colorArr {
            // ((1 << 24) + (r << 16) + (g << 8) + b).toString(16).slice(1)
            let v = (1 << 24) + (Int(colorArr[0]) << 16) + (Int(colorArr[1]) << 8) + Int(colorArr[2])
            return slice(String(v, radix: 16), 1)
        }
        return nil
    }

    /**
     * Map value to color. Faster than lerp methods because color is represented by rgba array.
     * @param normalizedValue A float between 0 and 1.
     * @param colors List of rgba color array
     * @param out Mapped gba color array
     * @return will be null/undefined if input illegal.
     */
    // upstream out-param dropped per §3; value-returning.
    @discardableResult
    public static func fastLerp(
        _ normalizedValue: Double,
        _ colors: [[Double]],
        _ out: [Double]? = nil
    ) -> [Double]? {
        if !(!colors.isEmpty)
            || !(normalizedValue >= 0 && normalizedValue <= 1) {
            return nil
        }

        var out = out ?? []

        let value = normalizedValue * Double(colors.count - 1)
        let leftIndex = Int(floor(value))
        let rightIndex = Int(ceil(value))
        let leftColor = colors[leftIndex]
        let rightColor = colors[rightIndex]
        let dv = value - Double(leftIndex)
        out = [
            clampCssByte(lerpNumber(leftColor[0], rightColor[0], dv)),
            clampCssByte(lerpNumber(leftColor[1], rightColor[1], dv)),
            clampCssByte(lerpNumber(leftColor[2], rightColor[2], dv)),
            clampCssFloat(lerpNumber(leftColor[3], rightColor[3], dv))
        ]

        return out
    }

    /**
     * @deprecated
     */
    // upstream: export const fastMapToColor = fastLerp;  (thin forwarding per §2)
    @discardableResult
    public static func fastMapToColor(
        _ normalizedValue: Double,
        _ colors: [[Double]],
        _ out: [Double]? = nil
    ) -> [Double]? {
        return fastLerp(normalizedValue, colors, out)
    }

    /**
     * @param normalizedValue A float between 0 and 1.
     * @param colors Color list.
     * @param fullOutput Default false.
     * @return Result color. If fullOutput,
                return {color: ..., leftIndex: ..., rightIndex: ..., value: ...},
     */
    // upstream TS overloads collapse to one func returning `LerpResult?` (the `string |
    // LerpFullOutput | undefined` union); `fullOutput` selects the case.
    public static func lerp(
        _ normalizedValue: Double,
        _ colors: [String],
        _ fullOutput: Bool = false
    ) -> LerpResult? {
        if !(!colors.isEmpty)
            || !(normalizedValue >= 0 && normalizedValue <= 1) {
            return nil
        }

        let value = normalizedValue * Double(colors.count - 1)
        let leftIndex = Int(floor(value))
        let rightIndex = Int(ceil(value))
        // upstream does not guard parse(); accessing leftColor[0] on undefined would throw.
        // Force-unwrap mirrors that (crashes on unparseable input rather than silently degrading).
        let leftColor = parse(colors[leftIndex])
        let rightColor = parse(colors[rightIndex])
        let dv = value - Double(leftIndex)

        let color = stringify(
            [
                clampCssByte(lerpNumber(leftColor![0], rightColor![0], dv)),
                clampCssByte(lerpNumber(leftColor![1], rightColor![1], dv)),
                clampCssByte(lerpNumber(leftColor![2], rightColor![2], dv)),
                clampCssFloat(lerpNumber(leftColor![3], rightColor![3], dv))
            ],
            "rgba"
        )

        return fullOutput
            ? .full(LerpFullOutput(
                color: color!,
                leftIndex: Double(leftIndex),
                rightIndex: Double(rightIndex),
                value: value
            ))
            : .color(color!)
    }

    /**
     * @deprecated
     */
    // upstream: export const mapToColor = lerp;  (thin forwarding per §2)
    public static func mapToColor(
        _ normalizedValue: Double,
        _ colors: [String],
        _ fullOutput: Bool = false
    ) -> LerpResult? {
        return lerp(normalizedValue, colors, fullOutput)
    }

    /**
     * @param color
     * @param h 0 ~ 360, ignore when null. If function, it takes hue as argument and returns a new hue.
     * @param s 0 ~ 1, ignore when null. If function, it takes saturation as argument and returns a new saturation.
     * @param l 0 ~ 1, ignore when null. If function, it takes lightness as argument and returns a new lightness.
     * @return Color string in rgba format.
     * @memberOf module:zrender/util/color
     */
    public static func modifyHSL(
        _ color: String,
        _ h: HSLParam? = nil,
        _ s: HSLParam? = nil,
        _ l: HSLParam? = nil
    ) -> String? {
        let colorArr = parse(color)

        if !color.isEmpty {  // if (color)
            // upstream reassigns `colorArr = rgba2hsla(colorArr)`. Force-unwrap mirrors upstream
            // proceeding unconditionally (it would throw if rgba2hsla returned undefined).
            var hsl = rgba2hsla(colorArr)!
            // upstream: `h != null && (colorArr[0] = clampCssAngle(isFunction(h) ? h(colorArr[0]) : h))`
            // The `.function` case replaces the `isFunction(...)` runtime guard.
            if let h = h {
                let hv: Double
                switch h {
                case .function(let f): hv = f(hsl[0])
                case .number(let n): hv = n
                case .string(let str): hv = parseFloat(str)  // not in the TS signature for `h`
                }
                hsl[0] = clampCssAngle(hv)
            }
            if let s = s {
                let sp: CssParam
                switch s {
                case .function(let f): sp = .number(f(hsl[1]))
                case .number(let n): sp = .number(n)
                case .string(let str): sp = .string(str)
                }
                hsl[1] = parseCssFloat(sp)
            }
            if let l = l {
                let lp: CssParam
                switch l {
                case .function(let f): lp = .number(f(hsl[2]))
                case .number(let n): lp = .number(n)
                case .string(let str): lp = .string(str)
                }
                hsl[2] = parseCssFloat(lp)
            }
            // hsla2rgba takes [CssParam]; lift the Double hsl array back into the param enum.
            return stringify(hsla2rgba(hsl.map { CssParam.number($0) }), "rgba")
        }
        return nil
    }

    /**
     * @param color
     * @param alpha 0 ~ 1
     * @return Color string in rgba format.
     * @memberOf module:zrender/util/color
     */
    public static func modifyAlpha(_ color: String, _ alpha: Double? = nil) -> String? {
        var colorArr = parse(color)

        if colorArr != nil && alpha != nil {
            colorArr![3] = clampCssFloat(alpha!)
            return stringify(colorArr!, "rgba")
        }
        return nil
    }

    /**
     * @param arrColor like [12,33,44,0.4]
     * @param type 'rgba', 'hsva', ...
     * @return Result color. (If input illegal, return undefined).
     */
    public static func stringify(_ arrColor: [Double], _ type: String) -> String? {
        if arrColor.isEmpty {  // if (!arrColor || !arrColor.length)
            return nil
        }
        // JS concatenates numbers without trailing ".0" (255, not 255.0) — replicate via numToStr.
        var colorStr = numToStr(arrColor[0]) + "," + numToStr(arrColor[1]) + "," + numToStr(arrColor[2])
        if type == "rgba" || type == "hsva" || type == "hsla" {
            colorStr += "," + numToStr(arrColor[3])
        }
        return type + "(" + colorStr + ")"
    }

    /**
     * Calculate luminance. It will include alpha.
     */
    public static func lum(_ color: String, _ backgroundLum: Double) -> Double {
        let arr = parse(color)
        return arr != nil
            ? (0.299 * arr![0] + 0.587 * arr![1] + 0.114 * arr![2]) * arr![3] / 255
                + (1 - arr![3]) * backgroundLum  // Blending with assumed white background.
            : 0
    }

    /**
     * Generate a random color
     */
    public static func random() -> String {
        return stringify([
            jsRound(Double.random(in: 0..<1) * 255),
            jsRound(Double.random(in: 0..<1) * 255),
            jsRound(Double.random(in: 0..<1) * 255)
        ], "rgb")!
    }

    static let liftedColorCache = LRU<String>(100)
    // upstream overloads (`string → string`, `GradientObject → GradientObject`) collapse to one
    // func over the `ColorValue` union; the switch replaces the `isString`/`isGradientObject` guards.
    public static func liftColor(_ color: ColorValue) -> ColorValue {
        switch color {
        case .string(let s):  // if (isString(color))
            var liftedColor = liftedColorCache.get(.string(s))
            if liftedColor == nil {
                // upstream `lift` is typed `string` but returns `undefined` when `parse` fails
                // (e.g. the sankey/chord edge sentinel "source"/"target"/"gradient" surviving on a
                // stroke). A failed lift must round-trip the input unchanged — a force-unwrap here
                // SIGTRAPped the demo app on hover (createEmphasisDefaultState → liftZRColor).
                guard let lifted = lift(s, -0.1) else { return color }
                liftedColor = lifted
                liftedColorCache.put(.string(s), lifted)
            }
            return .string(liftedColor!)
        case .gradient(let g):  // else if (isGradientObject(color))
            // upstream: `const ret = extend({}, color); ret.colorStops = map(...)`.
            // PORT-TODO: `extend({}, color)` shallow-clones into a NEW plain object; GradientObject
            // has no generic clone, and for a class-backed existential `var ret = g` shares the
            // reference, so the lifted stops are written onto the same instance (and subclass
            // geometry — LinearGradient x/y/x2/y2, RadialGradient x/y/r — is not deep-copied).
            // Wire up a proper Gradient clone when the graphic layer's copy seam lands.
            var ret = g
            ret.colorStops = util.map(g.colorStops) { stop, _ in
                // A stop whose color fails to parse keeps its original value (upstream would write
                // `undefined`; round-tripping is the crash-safe Swift analogue).
                GradientColorStop(offset: stop.offset, color: lift(stop.color, -0.1) ?? stop.color)
            }
            return .gradient(ret)
        }
    }

    // ---------------------------------------------------------------------------------------
    // Helpers backing JS built-ins that have no direct Swift equivalent.
    // These reproduce the (narrow) semantics the functions above actually exercise.
    // ---------------------------------------------------------------------------------------

    /// JS `Math.round` rounds half **up** (toward +Infinity): `floor(x + 0.5)` (CONVENTIONS §5).
    /// Propagates NaN like the original.
    static func jsRound(_ x: Double) -> Double {
        return floor(x + 0.5)
    }

    static func stringOf(_ p: CssParam) -> String {
        switch p {
        case .string(let s): return s
        // PORT-TODO: full JS Number→String fidelity (exponential form, etc.) not replicated.
        case .number(let n): return numToStr(n)
        }
    }

    static func numberOf(_ p: CssParam) -> Double {
        switch p {
        case .number(let n): return n
        case .string(let s): return parseFloat(s)
        }
    }

    /// JS unary `+` (i.e. `Number(value)`): empty → 0, else the parsed number or NaN.
    /// PORT-TODO: not a complete ECMAScript ToNumber (no 0x.. / Infinity literals, etc.).
    static func cssPlus(_ p: CssParam) -> Double {
        switch p {
        case .number(let n): return n
        case .string(let s):
            let t = s.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { return 0 }
            return Double(t) ?? Double.nan
        }
    }

    /// JS Number→String for the integral/short-fraction values color produces.
    /// PORT-TODO: not full ECMAScript Number::toString (exponential notation, etc.).
    static func numToStr(_ n: Double) -> String {
        if n.isNaN { return "NaN" }
        if n.isInfinite { return n > 0 ? "Infinity" : "-Infinity" }
        if n == n.rounded(.towardZero) && Swift.abs(n) < 1e16 {
            return String(Int(n))
        }
        return String(n)  // Swift's shortest round-trippable form matches JS for typical fractions.
    }

    /// JS `parseFloat`: parse a leading float, ignore trailing junk, NaN if none.
    /// PORT-TODO: narrow subset (no exponent edge cases beyond the common forms).
    static func parseFloat(_ s: String) -> Double {
        let chars = Array(s)
        let n = chars.count
        var i = 0
        while i < n && isWhitespace(chars[i]) { i += 1 }
        var end = i
        if end < n && (chars[end] == "+" || chars[end] == "-") { end += 1 }
        var sawDigit = false
        while end < n && isDigit(chars[end]) { end += 1; sawDigit = true }
        if end < n && chars[end] == "." {
            end += 1
            while end < n && isDigit(chars[end]) { end += 1; sawDigit = true }
        }
        if sawDigit && end < n && (chars[end] == "e" || chars[end] == "E") {
            var e2 = end + 1
            if e2 < n && (chars[e2] == "+" || chars[e2] == "-") { e2 += 1 }
            var sawExp = false
            while e2 < n && isDigit(chars[e2]) { e2 += 1; sawExp = true }
            if sawExp { end = e2 }
        }
        if !sawDigit { return Double.nan }
        return Double(String(chars[i..<end])) ?? Double.nan
    }

    /// JS `parseInt(str, radix)` for radix 10 / 16: parse a leading integer, ignore trailing
    /// junk, NaN if none. Accumulates in Double (matches JS, where the result is a Number).
    static func parseInt(_ s: String, _ radix: Int) -> Double {
        let chars = Array(s)
        let n = chars.count
        var i = 0
        while i < n && isWhitespace(chars[i]) { i += 1 }
        var sign = 1.0
        if i < n && (chars[i] == "+" || chars[i] == "-") {
            if chars[i] == "-" { sign = -1 }
            i += 1
        }
        var value = 0.0
        var sawDigit = false
        while i < n {
            let d = digitValue(chars[i])
            if d < 0 || d >= radix { break }
            value = value * Double(radix) + Double(d)
            sawDigit = true
            i += 1
        }
        if !sawDigit { return Double.nan }
        return sign * value
    }

    static func isWhitespace(_ c: Character) -> Bool {
        return c == " " || c == "\t" || c == "\n" || c == "\r" || c == "\u{0B}" || c == "\u{0C}"
    }
    static func isDigit(_ c: Character) -> Bool {
        return c >= "0" && c <= "9"
    }
    static func digitValue(_ c: Character) -> Int {
        if c >= "0" && c <= "9" { return Int(c.asciiValue! - 48) }
        if c >= "a" && c <= "z" { return Int(c.asciiValue! - 97) + 10 }
        if c >= "A" && c <= "Z" { return Int(c.asciiValue! - 65) + 10 }
        return -1
    }

    /// JS `String.charAt(index)` (returns the empty string out of range → here `nil`).
    static func charAt(_ s: String, _ index: Int) -> Character? {
        if index < 0 || index >= s.count { return nil }
        return Array(s)[index]
    }

    /// JS `String.indexOf(char)` → first character offset or -1.
    static func indexOf(_ s: String, _ c: Character) -> Int {
        let chars = Array(s)
        for (i, ch) in chars.enumerated() where ch == c {
            return i
        }
        return -1
    }

    /// JS `String.slice(start, end?)` over character offsets (supports negative indices).
    static func slice(_ s: String, _ start: Int, _ end: Int? = nil) -> String {
        let chars = Array(s)
        let n = chars.count
        var a = start
        var b = end ?? n
        if a < 0 { a = Swift.max(n + a, 0) }
        if b < 0 { b = Swift.max(n + b, 0) }
        a = Swift.min(a, n); b = Swift.min(b, n)
        if a >= b { return "" }
        return String(chars[a..<b])
    }

    /// JS `String.substr(start, length)` over character offsets.
    static func substr(_ s: String, _ start: Int, _ length: Int) -> String {
        let chars = Array(s)
        let n = chars.count
        var a = start
        if a < 0 { a = Swift.max(n + a, 0) }
        a = Swift.min(a, n)
        let b = Swift.min(a + Swift.max(length, 0), n)
        if a >= b { return "" }
        return String(chars[a..<b])
    }
}
