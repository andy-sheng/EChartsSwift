// Ported from echarts/src/util/decal.ts — keep in sync with upstream.
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
#if canImport(CoreGraphics)
import CoreGraphics
#endif
#if canImport(ImageIO)
import ImageIO
#endif

// upstream imports:
//   import WeakMap from 'zrender/src/core/WeakMap';
//   import { ImagePatternObject, PatternObject, SVGPatternObject } from 'zrender/src/graphic/Pattern';
//   import LRU from 'zrender/src/core/LRU';
//   import {defaults, map, isArray, isString, isNumber} from 'zrender/src/core/util';
//   import {getLeastCommonMultiple} from './number';           -> number.getLeastCommonMultiple
//   import {createSymbol} from './symbol';                     -> symbol.createSymbol
//   import ExtensionAPI from '../core/ExtensionAPI';           -> ExtensionAPI
//   import { brushSingle } from 'zrender/src/canvas/graphic';  -> rasterized inline (renderer seam §9)
//   import {DecalDashArrayX, DecalDashArrayY, InnerDecalObject, DecalObject} from './types';
//
// PORT MODELING NOTES
// -------------------
// * A `DecalObject` at runtime is the dynamic option bag `[String: Any]` (the aria-palette entries in
//   globalDefault.swift and `itemStyle.decal` are both plain dicts). So `createOrUpdatePatternFromDecal`
//   takes `Any?` (a `[String: Any]` decal, the sentinel String `"none"`, or nil) rather than the typed
//   `DecalObject` struct (kept in util/types.swift for provenance).
// * `PatternObject` maps to the ZRenderKit `Pattern` (the ImagePatternObject arm). The generated tile is
//   rasterized to a PNG `data:` URI carried in `Pattern.image` as `.url(...)` (the `string` arm of the
//   upstream `ImageLike | string`, modeled by the `ImageSource` enum);
//   the NativePainter renderer (`CGRenderer.fillPatternClipped`/`tilePattern`) decodes + tiles it. The
//   SVG arm is the deferred svg backend seam (CONVENTIONS §9).
// * `decalMap` (the WeakMap keyed by the decal object's IDENTITY) is dropped — our decal objects are value
//   dicts with no stable identity. `decalCache` (the value-keyed LRU) is preserved as `decalCache` below
//   and is the real dedup: identical decal options → the same tile/Pattern.
// * `brushSingle(ctx, symbol)` (zrender canvas backend) is reproduced by rasterizing each `createSymbol`
//   Path into a CoreGraphics bitmap (see `brushDecal`), matching the canvas render exactly enough for the
//   image-pattern tile. dpr is read from `api.getDevicePixelRatio()` (1 in this port; getZr/isSVG=false).

// upstream: const decalKeys = ['symbol','symbolSize','symbolKeepAspect','color','backgroundColor',
//   'dashArrayX','dashArrayY','maxTileWidth','maxTileHeight'];
private let decalKeys: [String] = [
    "symbol", "symbolSize", "symbolKeepAspect",
    "color", "backgroundColor",
    "dashArrayX", "dashArrayY",
    "maxTileWidth", "maxTileHeight"
]

// upstream: const decalCache = new LRU<HTMLCanvasElement | SVGVNode>(100);
//   Here it caches the finished `Pattern` (image tile + transform) keyed by the value cacheKey.
private var _decalCache: [String: Pattern] = [:]

/**
 * Create or update pattern image from decal options
 *
 * upstream:
 *   export function createOrUpdatePatternFromDecal(
 *       decalObject: InnerDecalObject | 'none', api: ExtensionAPI): PatternObject
 *
 * @param decalObject decal options `[String: Any]`, or the sentinel `"none"`/nil if no decal.
 * @return the generated tiling `Pattern`, or nil if no decal.
 */
@discardableResult
public func createOrUpdatePatternFromDecal(
    _ decalObject: Any?,
    _ api: ExtensionAPI
) -> Pattern? {
    // upstream: if (decalObject === 'none') { return null; }
    if decalObject == nil { return nil }
    if let s = decalObject as? String, s == "none" { return nil }
    guard let decalObj = decalObject as? [String: Any] else { return nil }

    // upstream: const dpr = api.getDevicePixelRatio(); const zr = api.getZr();
    //   const isSVG = zr.painter.type === 'svg';
    let dpr = api.getDevicePixelRatio()
    let isSVG = false   // canvas backend only in this port (svg painter not ported, §9)

    // upstream: decalMap dirty/lookup — dropped (value dicts have no identity; see header note).

    // upstream:
    //   const decalOpt = defaults(decalObject, { symbol:'rect', symbolSize:1, symbolKeepAspect:true,
    //       color:'rgba(0, 0, 0, 0.2)', backgroundColor:null, dashArrayX:5, dashArrayY:5, rotation:0,
    //       maxTileWidth:512, maxTileHeight:512 });
    //   if (decalOpt.backgroundColor === 'none') { decalOpt.backgroundColor = null; }
    let decalOpt = DecalOpt(decalObj)

    // upstream:
    //   const pattern: PatternObject = { repeat: 'repeat' };
    //   setPatternnSource(pattern);
    //   pattern.rotation = decalOpt.rotation;
    //   pattern.scaleX = pattern.scaleY = isSVG ? 1 : 1 / dpr;
    // DEVIATION: upstream has no failure arm (it assigns the live canvas element unconditionally);
    //   our rasterization goes through ImageIO and can fail, so a nil tile propagates as "no decal"
    //   rather than being cached as an empty-string image URI.
    guard let pattern = setPatternSource(decalOpt, dpr: dpr, isSVG: isSVG) else { return nil }
    pattern.rotation = decalOpt.rotation
    pattern.scaleX = isSVG ? 1 : 1 / dpr
    pattern.scaleY = isSVG ? 1 : 1 / dpr

    return pattern
}

// upstream: function setPatternnSource(pattern) { ... } (nested; returns the assembled Pattern here).
private func setPatternSource(_ decalOpt: DecalOpt, dpr: Double, isSVG: Bool) -> Pattern? {
    // upstream: build the cacheKey from [dpr, ...decalKeys values]; join(',') + (isSVG ? '-svg' : '').
    var keys: [String] = [numToken(dpr)]
    for k in decalKeys {
        keys.append(anyToken(decalOpt.raw[k]))
    }
    let cacheKey = keys.joined(separator: ",") + (isSVG ? "-svg" : "")
    if let cached = _decalCache[cacheKey] {
        // upstream reuses the cached HTMLCanvasElement/SVGVNode as the pattern image; here the whole
        //   Pattern is cached (same tile → same data URI + geometry).
        // NOTE: `cached.image` is already an `ImageSource` — pass it through unwrapped; do NOT
        //   re-wrap in `.url(...)` (that would nest an ImageSource inside the String arm).
        return Pattern(cached.image, .repeat)
    }

    // upstream:
    //   const dashArrayX = normalizeDashArrayX(decalOpt.dashArrayX);
    //   const dashArrayY = normalizeDashArrayY(decalOpt.dashArrayY);
    //   const symbolArray = normalizeSymbolArray(decalOpt.symbol);
    //   const lineBlockLengthsX = getLineBlockLengthX(dashArrayX);
    //   const lineBlockLengthY = getLineBlockLengthY(dashArrayY);
    let dashArrayX = normalizeDashArrayX(decalOpt.raw["dashArrayX"] ?? 5)
    let dashArrayY = normalizeDashArrayY(decalOpt.raw["dashArrayY"] ?? 5)
    let symbolArray = normalizeSymbolArray(decalOpt.raw["symbol"] ?? "rect")
    let lineBlockLengthsX = getLineBlockLengthX(dashArrayX)
    let lineBlockLengthY = getLineBlockLengthY(dashArrayY)

    // upstream:
    //   const pSize = getPatternSize();
    let pSize = getPatternSize(
        lineBlockLengthsX: lineBlockLengthsX,
        lineBlockLengthY: lineBlockLengthY,
        symbolArray: symbolArray,
        maxTileWidth: decalOpt.maxTileWidth,
        maxTileHeight: decalOpt.maxTileHeight
    )

    // upstream: rasterize the tile onto a canvas (brushDecal), then set pattern.image = canvas.
    let dataURI = brushDecal(
        decalOpt: decalOpt, dpr: dpr, pSize: pSize,
        dashArrayX: dashArrayX, dashArrayY: dashArrayY,
        symbolArray: symbolArray, lineBlockLengthY: lineBlockLengthY
    )

    // DEVIATION (see createOrUpdatePatternFromDecal): upstream cannot fail here. Bail WITHOUT
    //   caching on a failed rasterization — caching an empty image URI would poison every
    //   subsequent hit on this cacheKey with a permanently blank tile.
    guard let dataURI = dataURI else { return nil }

    let pattern = Pattern(.url(dataURI), .repeat)
    _decalCache[cacheKey] = pattern
    return pattern
}

/**
 * Get minimum length that can make a repeatable pattern.
 * upstream: function getPatternSize(): {width, height}
 */
func getPatternSize(
    lineBlockLengthsX: [Double],
    lineBlockLengthY: Double,
    symbolArray: [[String]],
    maxTileWidth: Double,
    maxTileHeight: Double
) -> (width: Double, height: Double) {
    // upstream:
    //   let width = 1;
    //   for (...) width = getLeastCommonMultiple(width, lineBlockLengthsX[i]);
    var width: Double = 1
    for x in lineBlockLengthsX {
        width = number.getLeastCommonMultiple(width, x) ?? width
    }

    // upstream:
    //   let symbolRepeats = 1;
    //   for (...) symbolRepeats = getLeastCommonMultiple(symbolRepeats, symbolArray[i].length);
    //   width *= symbolRepeats;
    var symbolRepeats: Double = 1
    for row in symbolArray {
        symbolRepeats = number.getLeastCommonMultiple(symbolRepeats, Double(row.count)) ?? symbolRepeats
    }
    width *= symbolRepeats

    // upstream: const height = lineBlockLengthY * lineBlockLengthsX.length * symbolArray.length;
    let height = lineBlockLengthY * Double(lineBlockLengthsX.count) * Double(symbolArray.count)

    // upstream __DEV__ warnings when width/height > maxTileWidth/Height (log-only; skipped).

    // upstream:
    //   return { width: Math.max(1, Math.min(width, maxTileWidth)),
    //            height: Math.max(1, Math.min(height, maxTileHeight)) };
    return (
        width: max(1, min(width, maxTileWidth)),
        height: max(1, min(height, maxTileHeight))
    )
}

// ================================================================================================
// Tile rasterization — upstream `brushDecal()` (nested), reproduced with CoreGraphics.
// Returns a PNG `data:` URI for the tile, or nil if CG/ImageIO is unavailable.
// ================================================================================================
private func brushDecal(
    decalOpt: DecalOpt,
    dpr: Double,
    pSize: (width: Double, height: Double),
    dashArrayX: [[Double]],
    dashArrayY: [Double],
    symbolArray: [[String]],
    lineBlockLengthY: Double
) -> String? {
    #if canImport(CoreGraphics) && canImport(ImageIO)
    let pxW = max(1, Int((pSize.width * dpr).rounded()))
    let pxH = max(1, Int((pSize.height * dpr).rounded()))
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil, width: pxW, height: pxH, bitsPerComponent: 8, bytesPerRow: 0,
        space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    // Flip to canvas space (origin top-left, +y DOWN) so the CGPathRebuilder's arc convention +
    // the symbol coordinates (canvas space) map 1:1 (see NativePainter/CGPathRebuilder header).
    ctx.translateBy(x: 0, y: CGFloat(pxH))
    ctx.scaleBy(x: 1, y: -1)

    // upstream:
    //   ctx.clearRect(0, 0, canvas.width, canvas.height);
    //   if (decalOpt.backgroundColor) { ctx.fillStyle = ...; ctx.fillRect(0,0,w,h); }
    if let bg = decalOpt.backgroundColor, let bgColor = cgColor(fromString: bg) {
        ctx.setFillColor(bgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: Double(pxW), height: Double(pxH)))
    }

    // upstream: let ySum = sum(dashArrayY); if (ySum <= 0) return; (dashArrayY is 0, draw nothing)
    let ySum = dashArrayY.reduce(0, +)
    if ySum > 0 {
        let scale = dpr   // upstream: isSVG ? 1 : dpr

        // upstream double loop.
        var y = -lineBlockLengthY
        var yId = 0
        var yIdTotal = 0
        var xId0 = 0
        let symbolFill = cgColor(fromString: decalOpt.color)
        while y < pSize.height {
            if yId % 2 == 0 {
                let symbolYId = Int((Double(yIdTotal) / 2).truncatingRemainder(dividingBy: Double(symbolArray.count)))
                var x: Double = 0
                var xId1 = 0
                var xId1Total = 0
                while x < pSize.width * 2 {
                    var xSum: Double = 0
                    for v in dashArrayX[xId0] { xSum += v }
                    if xSum <= 0 { break }   // Skip empty line

                    // E.g., [15, 5, 20, 5] draws only for 15 and 20
                    if xId1 % 2 == 0 {
                        let size = (1 - decalOpt.symbolSize) * 0.5
                        let left = x + dashArrayX[xId0][xId1] * size
                        let top = y + dashArrayY[yId] * size
                        let w = dashArrayX[xId0][xId1] * decalOpt.symbolSize
                        let h = dashArrayY[yId] * decalOpt.symbolSize
                        let symbolXId = Int((Double(xId1Total) / 2)
                            .truncatingRemainder(dividingBy: Double(symbolArray[symbolYId].count)))
                        let symbolType = symbolArray[symbolYId][symbolXId]

                        // upstream: brushSymbol(left, top, width, height, symbolType)
                        brushSymbol(
                            ctx: ctx, symbolType: symbolType,
                            x: left * scale, y: top * scale, w: w * scale, h: h * scale,
                            color: decalOpt.color, keepAspect: decalOpt.symbolKeepAspect,
                            fill: symbolFill
                        )
                    }

                    x += dashArrayX[xId0][xId1]
                    xId1Total += 1
                    xId1 += 1
                    if xId1 == dashArrayX[xId0].count { xId1 = 0 }
                }

                xId0 += 1
                if xId0 == dashArrayX.count { xId0 = 0 }
            }
            y += dashArrayY[yId]
            yIdTotal += 1
            yId += 1
            if yId == dashArrayY.count { yId = 0 }
        }
    }

    guard let img = ctx.makeImage() else { return nil }
    return cgImageToPNGDataURI(img)
    #else
    // No CoreGraphics/ImageIO — the value-level normalization + geometry above still run; the tile
    // image cannot be rasterized. Returns nil (Pattern gets an empty image; renderer skips the fill).
    _ = (decalOpt, dpr, pSize, dashArrayX, dashArrayY, symbolArray, lineBlockLengthY)
    return nil
    #endif
}

#if canImport(CoreGraphics)
// upstream: function brushSymbol(x, y, width, height, symbolType) — createSymbol + brushSingle(ctx, symbol).
private func brushSymbol(
    ctx: CGContext, symbolType: String,
    x: Double, y: Double, w: Double, h: Double,
    color: String, keepAspect: Bool, fill: CGColor?
) {
    // upstream: const symbol = createSymbol(symbolType, x, y, width, height, color, symbolKeepAspect);
    let sym = symbol.createSymbol(symbolType, x, y, w, h, .string(color), keepAspect)
    guard let symPath = sym as? Path else { return }

    let proxy = symPath.getUpdatedPathProxy()
    let builder = DecalCGPathBuilder()
    builder.beginPath()
    proxy.rebuildPath(builder, 1.0)
    let cgPath = builder.path

    // Non-empty symbols (the decal default 'rect'/'circle'/'triangle') are filled with the symbol's
    // fill color; empty (`emptyCircle`, …) symbols are stroked (mirrors brushSingle honoring style).
    if sym.__isEmptyBrush {
        if let stroke = cgColorFromZR(symPath.pathStyle.stroke) ?? fill {
            ctx.addPath(cgPath)
            ctx.setStrokeColor(stroke)
            ctx.setLineWidth(CGFloat(symPath.pathStyle.lineWidth ?? 1))
            ctx.strokePath()
        }
    }
    else if let fillColor = cgColorFromZR(symPath.pathStyle.fill) ?? fill {
        ctx.addPath(cgPath)
        ctx.setFillColor(fillColor)
        ctx.fillPath()
    }
}

// Parse a ZRenderKit ZRColor to a CGColor (solid `.string` arm only).
private func cgColorFromZR(_ c: ZRenderKit.ZRColor?) -> CGColor? {
    if case let .some(.string(s)) = c { return cgColor(fromString: s) }
    return nil
}

// Parse a CSS color string to a CGColor via ZRenderKit's `color.parse` ([r,g,b,a], 0..255 rgb, 0..1 a).
private func cgColor(fromString s: String) -> CGColor? {
    if s.isEmpty || s == "none" || s == "transparent" { return nil }
    guard let rgba = color.parse(s), rgba.count >= 3 else { return nil }
    let a = rgba.count > 3 ? rgba[3] : 1
    return CGColor(
        red: CGFloat(rgba[0] / 255), green: CGFloat(rgba[1] / 255),
        blue: CGFloat(rgba[2] / 255), alpha: CGFloat(a)
    )
}
#endif

#if canImport(CoreGraphics) && canImport(ImageIO)
// Encode a CGImage to a base64 PNG `data:` URI (the renderer's `loadCGImage` decodes it).
private func cgImageToPNGDataURI(_ img: CGImage) -> String? {
    let data = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(data as CFMutableData, "public.png" as CFString, 1, nil)
    else { return nil }
    CGImageDestinationAddImage(dest, img, nil)
    guard CGImageDestinationFinalize(dest) else { return nil }
    return "data:image/png;base64," + data.base64EncodedString()
}
#endif

// ================================================================================================
// Normalization helpers — faithful ports of the module-level functions in util/decal.ts.
// (internal for unit testing via @testable import EChartsKit)
// ================================================================================================

/**
 * Convert symbol array into normalized array.
 * upstream: function normalizeSymbolArray(symbol): string[][]
 */
func normalizeSymbolArray(_ symbol: Any?) -> [[String]] {
    // upstream: if (!symbol || symbol.length === 0) return [['rect']];
    if symbol == nil { return [["rect"]] }
    // upstream: if (isString(symbol)) return [[symbol]];  (empty string falls to the guard above)
    if let s = symbol as? String {
        return s.isEmpty ? [["rect"]] : [[s]]
    }
    let arr = symbol as? [Any] ?? []
    if arr.isEmpty { return [["rect"]] }

    // upstream: isAllString ? normalizeSymbolArray([symbol]) : ...
    var isAllString = true
    for e in arr { if !(e is String) { isAllString = false; break } }
    if isAllString {
        return normalizeSymbolArray([arr] as [Any])
    }

    var result: [[String]] = []
    for e in arr {
        if let s = e as? String {
            result.append([s])
        }
        else {
            result.append((e as? [Any] ?? []).map { ($0 as? String) ?? "rect" })
        }
    }
    return result
}

/**
 * Convert dash input into dashArray.
 * upstream: function normalizeDashArrayX(dash): number[][]
 */
func normalizeDashArrayX(_ dash: Any?) -> [[Double]] {
    // upstream: if (!dash || dash.length === 0) return [[0, 0]];
    if dash == nil { return [[0, 0]] }
    if let a = dash as? [Any], a.isEmpty { return [[0, 0]] }
    // upstream: if (isNumber(dash)) { const dashValue = Math.ceil(dash); return [[dashValue, dashValue]]; }
    if isNumberLike(dash) {
        let dv = ceil(toDouble(dash))
        return [[dv, dv]]
    }
    let arr = dash as? [Any] ?? []

    // upstream: isAllNumber ? normalizeDashArrayX([dash]) : ...
    var isAllNumber = true
    for e in arr { if !isNumberLike(e) { isAllNumber = false; break } }
    if isAllNumber {
        return normalizeDashArrayX([arr] as [Any])
    }

    var result: [[Double]] = []
    for e in arr {
        if isNumberLike(e) {
            let dv = ceil(toDouble(e))
            result.append([dv, dv])
        }
        else {
            let inner = (e as? [Any] ?? []).map { ceil(toDouble($0)) }
            // odd length → [4,2,1] means the pattern repeats mirrored: concat with itself.
            if inner.count % 2 == 1 {
                result.append(inner + inner)
            }
            else {
                result.append(inner)
            }
        }
    }
    return result
}

/**
 * Convert dash input into dashArray.
 * upstream: function normalizeDashArrayY(dash): number[]
 */
func normalizeDashArrayY(_ dash: Any?) -> [Double] {
    // upstream: if (!dash || typeof dash === 'object' && dash.length === 0) return [0, 0];
    if dash == nil { return [0, 0] }
    if let a = dash as? [Any], a.isEmpty { return [0, 0] }
    // upstream: if (isNumber(dash)) { const dashValue = Math.ceil(dash); return [dashValue, dashValue]; }
    if isNumberLike(dash) {
        let dv = ceil(toDouble(dash))
        return [dv, dv]
    }
    let arr = dash as? [Any] ?? []
    let dashValue = arr.map { ceil(toDouble($0)) }
    // upstream: return dash.length % 2 ? dashValue.concat(dashValue) : dashValue;
    return arr.count % 2 == 1 ? dashValue + dashValue : dashValue
}

/**
 * Get block length of each line. A block is the length of dash line and space.
 * upstream: function getLineBlockLengthX(dash): number[]
 */
func getLineBlockLengthX(_ dash: [[Double]]) -> [Double] {
    return dash.map { getLineBlockLengthY($0) }
}

// upstream: function getLineBlockLengthY(dash): number
func getLineBlockLengthY(_ dash: [Double]) -> Double {
    var blockLength: Double = 0
    for v in dash { blockLength += v }
    // upstream: [4,2,1] → total length is (4+2+1)*2 when odd.
    return dash.count % 2 == 1 ? blockLength * 2 : blockLength
}

// ================================================================================================
// The `defaults(decalObject, { ... })` result — the resolved decal options with fallbacks.
// upstream default: symbol 'rect', symbolSize 1, symbolKeepAspect true, color 'rgba(0,0,0,0.2)',
//   backgroundColor null, dashArrayX 5, dashArrayY 5, rotation 0, maxTileWidth 512, maxTileHeight 512;
//   plus `backgroundColor === 'none' → null`.
// ================================================================================================
struct DecalOpt {
    let raw: [String: Any]      // the merged option bag (dashArrayX/Y/symbol read raw for normalization)
    let symbolSize: Double
    let symbolKeepAspect: Bool
    let color: String
    let backgroundColor: String?
    let rotation: Double
    let maxTileWidth: Double
    let maxTileHeight: Double

    init(_ decalObject: [String: Any]) {
        var merged = decalObject
        // defaults(...) fills only ABSENT keys (mirrors zrUtil.defaults; existing keys win).
        func fill(_ key: String, _ value: Any) { if merged[key] == nil { merged[key] = value } }
        fill("symbol", "rect")
        fill("symbolSize", 1)
        fill("symbolKeepAspect", true)
        fill("color", "rgba(0, 0, 0, 0.2)")
        fill("dashArrayX", 5)
        fill("dashArrayY", 5)
        fill("rotation", 0)
        fill("maxTileWidth", 512)
        fill("maxTileHeight", 512)
        self.raw = merged

        self.symbolSize = decalToDouble(merged["symbolSize"], 1)
        self.symbolKeepAspect = (merged["symbolKeepAspect"] as? Bool) ?? true
        self.color = (merged["color"] as? String) ?? "rgba(0, 0, 0, 0.2)"
        // if (decalOpt.backgroundColor === 'none') { decalOpt.backgroundColor = null; }
        let bg = merged["backgroundColor"] as? String
        self.backgroundColor = (bg == "none") ? nil : bg
        self.rotation = decalToDouble(merged["rotation"], 0)
        self.maxTileWidth = decalToDouble(merged["maxTileWidth"], 512)
        self.maxTileHeight = decalToDouble(merged["maxTileHeight"], 512)
    }
}

// ---- port-local numeric coercion helpers (JS `isNumber` / `Math.ceil(+x)`; Int-vs-Double trap) ----

private func isNumberLike(_ v: Any?) -> Bool {
    guard let v = v else { return false }
    if v is Bool { return false }          // JS isNumber(true) === false
    return v is Int || v is Double || v is Float || v is NSNumber
}

private func toDouble(_ v: Any?) -> Double {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let f = v as? Float { return Double(f) }
    if let n = v as? NSNumber { return n.doubleValue }
    if let s = v as? String, let d = Double(s) { return d }
    return 0
}

private func decalToDouble(_ v: Any?, _ fallback: Double) -> Double {
    guard let v = v, isNumberLike(v) else { return fallback }
    return toDouble(v)
}

// cacheKey token for a number: JS `'' + value` (integral doubles print without ".0").
private func numToken(_ d: Double) -> String {
    if d == d.rounded() && abs(d) < 1e15 { return String(Int(d)) }
    return String(d)
}

// cacheKey token for any decal option value (string / number / bool / array).
private func anyToken(_ v: Any?) -> String {
    guard let v = v else { return "" }
    if let s = v as? String { return s }
    if let b = v as? Bool { return b ? "true" : "false" }
    if isNumberLike(v) { return numToken(toDouble(v)) }
    if let arr = v as? [Any] { return "[" + arr.map { anyToken($0) }.joined(separator: ",") + "]" }
    return "\(v)"
}
