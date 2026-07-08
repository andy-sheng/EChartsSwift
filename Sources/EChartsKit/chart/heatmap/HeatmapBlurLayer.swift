// Ported from echarts/src/chart/heatmap/HeatmapLayer.ts — keep in sync with upstream
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

// FILE BASENAME NOTE: upstream is `HeatmapLayer.ts`; the sibling ported class is named
//   `HeatmapLayer` below but the FILE is `HeatmapBlurLayer.swift` to stay distinctive under the
//   SwiftPM object-file-by-basename / APFS case-insensitive collision rule (CLAUDE.md trap #1).
//
// upstream imports:
//   import { platformApi } from 'zrender/src/core/platform';  -> the offscreen `HTMLCanvasElement`
//     (`platformApi.createCanvas`) is replaced by an explicit RGBA pixel buffer + a CoreGraphics
//     `CGImage` wrapper (the "canvas"): the whole file is canvas pixel-manipulation (getImageData /
//     putImageData), so a plain byte buffer is BOTH more faithful to that inner loop AND testable
//     headless (no live graphics context needed). See the CG note on `makeImage()`.
//   import tokens from '../../visual/tokens';                  -> `neutral99` shadow color inlined; the
//     brush blob is reproduced analytically (see `_getBrush`) rather than via canvas `shadowBlur`.
//
// PORT DEVIATION (noted per the milestone allowance — "render per-point radial-gradient circles as an
//   approximation and note the deviation"): upstream stamps a black disk of radius `pointSize` with a
//   canvas Gaussian `shadowBlur` of `blurSize`, then reads back the accumulated ALPHA channel. Canvas
//   `shadowBlur` (a true Gaussian) is not reproduced; instead `_getBrush` builds the same `2r × 2r`
//   ALPHA blob analytically — flat alpha 1 inside `pointSize`, a smootherstep falloff to 0 across
//   `blurSize` — and the per-point stamps are composited with canvas `source-over` alpha
//   (`a_out = a_src + a_dst·(1 − a_src)`) into a float alpha accumulator. The colorize pass (alpha →
//   gradient RGBA, min/maxOpacity remap) mirrors upstream's `getImageData` while-loop EXACTLY,
//   including the `/256` 8-bit alpha quantization, the `floor(alpha·255)·4` gradient index, and the
//   `Uint8ClampedArray` round-half-to-even clamp. Net effect: smooth heat blobs whose colors match the
//   visualMap gradient; only the blob's radial FALLOFF SHAPE is an approximation of the Gaussian.

import Foundation
import CoreGraphics
import ZRenderKit

// upstream: const GRADIENT_LEVELS = 256;
private let GRADIENT_LEVELS = 256

// upstream: type ColorState = 'inRange' | 'outOfRange';  (used as `colorFunc[state]` keys)
// upstream: type ColorFunc = (grad, fastMode, output) => void;  -> the EChartsKit `ColorMapper`
//   (visual/VisualMapping.swift): `(_ value: Any, _ isNormalized: Bool, _ out: [Double]?) -> Any`.
//   Called with `out != nil` it returns the `[Double]` rgba array (`color.fastLerp` result) — the
//   fast pixel-manipulation path upstream selects via `colorFunc[state](i/255, true, color)`.

// upstream: class HeatmapLayer { ... }
public final class HeatmapLayer {

    // upstream: blurSize = 30; pointSize = 20; maxOpacity = 1; minOpacity = 0;
    public var blurSize: Double = 30
    public var pointSize: Double = 20
    public var maxOpacity: Double = 1
    public var minOpacity: Double = 0

    // upstream: canvas: HTMLCanvasElement;  -> the produced RGBA output buffer + its size (the "canvas").
    //   `pixels` is STRAIGHT (non-premultiplied) RGBA, matching canvas `getImageData` semantics, so
    //   `makeImage()` wraps it as a `CGImageAlphaInfo.last` (straight-alpha) `CGImage`.
    public private(set) var width: Int = 0
    public private(set) var height: Int = 0
    public private(set) var pixels: [UInt8] = []

    // upstream: private _brushCanvas: HTMLCanvasElement;  -> cached alpha blob + the radius it was
    //   built for (rebuilt when pointSize/blurSize change).
    private var _brush: (alpha: [Double], d: Int, r: Double)?

    // upstream: private _gradientPixels: Record<ColorState, Uint8ClampedArray> = { inRange, outOfRange };
    private var _gradientPixels: [String: [UInt8]] = [:]

    public init() {}

    /**
     * upstream: update(data, width, height, normalize, colorFunc, isInRange?)
     * Renders the heatmap into `pixels` (the "canvas") and returns a `CGImage` of it.
     * @param data array of points, each `[x, y, value]`.
     */
    @discardableResult
    public func update(
        _ data: [[Double]],
        _ width: Int,
        _ height: Int,
        _ normalize: (Double) -> Double,
        _ colorFunc: [String: ColorMapper],
        _ isInRange: (Double) -> Bool
    ) -> CGImage? {
        // const brush = this._getBrush();
        let brush = self._getBrush()
        // const gradientInRange = this._getGradient(colorFunc, 'inRange');
        let gradientInRange = self._getGradient(colorFunc, "inRange")
        // const gradientOutOfRange = this._getGradient(colorFunc, 'outOfRange');
        let gradientOutOfRange = self._getGradient(colorFunc, "outOfRange")
        // const r = this.pointSize + this.blurSize;
        let r = self.pointSize + self.blurSize

        // canvas.width = width; canvas.height = height;
        self.width = max(0, width)
        self.height = max(0, height)

        // if (!canvas.width || !canvas.height) { return canvas; }
        if self.width == 0 || self.height == 0 {
            self.pixels = []
            return nil
        }

        let w = self.width
        let h = self.height
        let d = brush.d

        // Float ALPHA accumulator (the destination alpha channel canvas `drawImage` accumulates into
        //   via `source-over`). Upstream's canvas stores it as premultiplied 8-bit; the colorize pass
        //   below re-quantizes to 8-bit (`/256`) exactly as `getImageData` returns it.
        var accum = [Double](repeating: 0, count: w * h)

        // for (let i = 0; i < len; ++i) { ... ctx.globalAlpha = alpha; ctx.drawImage(brush, x - r, y - r); }
        for p in data {
            let x = p.count > 0 ? p[0] : 0
            let y = p.count > 1 ? p[1] : 0
            let value = p.count > 2 ? p[2] : 0

            // calculate alpha using value  ->  ctx.globalAlpha = normalize(value)
            let ga = normalize(value)
            if ga <= 0 { continue }

            // draw with the circle brush with alpha  ->  ctx.drawImage(brush, x - r, y - r)
            let ox = Int((x - r).rounded(.down))
            let oy = Int((y - r).rounded(.down))
            for by in 0..<d {
                let py = oy + by
                if py < 0 || py >= h { continue }
                let rowBrush = by * d
                let rowAccum = py * w
                for bx in 0..<d {
                    let px = ox + bx
                    if px < 0 || px >= w { continue }
                    let ba = brush.alpha[rowBrush + bx]
                    if ba <= 0 { continue }
                    // canvas globalAlpha scales the source alpha; source-over composites it.
                    let src = ga * ba
                    if src <= 0 { continue }
                    let dst = accum[rowAccum + px]
                    accum[rowAccum + px] = src + dst * (1 - src)
                }
            }
        }

        // colorize the canvas using alpha value and set with gradient
        // const imageData = ctx.getImageData(...); const pixels = imageData.data;
        var out = [UInt8](repeating: 0, count: w * h * 4)

        // const minOpacity = this.minOpacity; const maxOpacity = this.maxOpacity;
        // const diffOpacity = maxOpacity - minOpacity;
        let minOpacity = self.minOpacity
        let maxOpacity = self.maxOpacity
        let diffOpacity = maxOpacity - minOpacity

        // while (offset < pixelLen) { ... }  — one iteration per pixel.
        for i in 0..<(w * h) {
            // let alpha = pixels[offset + 3] / 256;
            //   `pixels[offset+3]` is the 8-bit accumulated alpha; reproduce the 8-bit quantization
            //   (clamp the float accumulator to a UInt8 first) then divide by 256 (NOT 255) as upstream.
            let aByte = Double(clampU8(accum[i] * 255))
            var alpha = aByte / 256

            // const gradientOffset = Math.floor(alpha * (GRADIENT_LEVELS - 1)) * 4;
            let gradientOffset = Int((alpha * Double(GRADIENT_LEVELS - 1)).rounded(.down)) * 4

            let o = i * 4
            // Simple optimize to ignore the empty data  ->  if (alpha > 0) { ... } else { offset += 4; }
            if alpha > 0 {
                // const gradient = isInRange(alpha) ? gradientInRange : gradientOutOfRange;
                let gradient = isInRange(alpha) ? gradientInRange : gradientOutOfRange
                // Any alpha > 0 will be mapped to [minOpacity, maxOpacity]
                // alpha > 0 && (alpha = alpha * diffOpacity + minOpacity);
                alpha = alpha * diffOpacity + minOpacity
                // pixels[offset++] = gradient[gradientOffset]; (+1 g) (+2 b)
                out[o] = gradient[gradientOffset]
                out[o + 1] = gradient[gradientOffset + 1]
                out[o + 2] = gradient[gradientOffset + 2]
                // pixels[offset++] = gradient[gradientOffset + 3] * alpha * 256;  (Uint8ClampedArray)
                out[o + 3] = clampU8(Double(gradient[gradientOffset + 3]) * alpha * 256)
            }
            // else: leave the pixel transparent (0,0,0,0) — matches the untouched imageData bytes.
        }

        // ctx.putImageData(imageData, 0, 0);  ->  store the buffer; makeImage() wraps it as a CGImage.
        self.pixels = out
        return self.makeImage()
    }

    /**
     * upstream: _getBrush() — canvas of a soft circular ALPHA blob used to stamp each point.
     * DEVIATION (see the file header): the canvas `shadowBlur` Gaussian is reproduced analytically as a
     *   `2r × 2r` alpha field — flat 1 inside `pointSize`, smootherstep falloff to 0 across `blurSize`.
     */
    private func _getBrush() -> (alpha: [Double], d: Int, r: Double) {
        // const r = this.pointSize + this.blurSize; const d = r * 2;
        let r = self.pointSize + self.blurSize
        if let cached = self._brush, cached.r == r {
            return cached
        }
        let d = max(1, Int((r * 2).rounded(.up)))
        var alpha = [Double](repeating: 0, count: d * d)
        // center of the brush (upstream draws the circle at the canvas center via shadowOffset).
        let cx = Double(d) / 2
        let cy = Double(d) / 2
        let pointSize = self.pointSize
        let blurSize = max(0.000001, self.blurSize)
        for by in 0..<d {
            let dy = Double(by) + 0.5 - cy
            for bx in 0..<d {
                let dx = Double(bx) + 0.5 - cx
                let dist = (dx * dx + dy * dy).squareRoot()
                var a: Double
                if dist <= pointSize {
                    a = 1
                } else if dist >= r {
                    a = 0
                } else {
                    // smootherstep falloff (approximates the Gaussian shadow tail): 1 → 0 over blurSize.
                    let t = (dist - pointSize) / blurSize
                    a = 1 - (t * t * t * (t * (t * 6 - 15) + 10))
                    if a < 0 { a = 0 } else if a > 1 { a = 1 }
                }
                alpha[by * d + bx] = a
            }
        }
        let brush = (alpha: alpha, d: d, r: r)
        self._brush = brush
        return brush
    }

    /**
     * upstream: _getGradient(colorFunc, state) — build the 256-entry RGBA color map for a state.
     */
    private func _getGradient(_ colorFunc: [String: ColorMapper], _ state: String) -> [UInt8] {
        // const pixelsSingleState = gradientPixels[state] || (gradientPixels[state] = new Uint8ClampedArray(256*4));
        var pixels = self._gradientPixels[state] ?? [UInt8](repeating: 0, count: 256 * 4)
        guard let colorMapper = colorFunc[state] else {
            self._gradientPixels[state] = pixels
            return pixels
        }
        // for (let i = 0; i < 256; i++) { colorFunc[state](i/255, true, color); ... }
        var off = 0
        let out: [Double] = [0, 0, 0, 0]
        for i in 0..<256 {
            let mapped = colorMapper(Double(i) / 255.0, true, out)
            let c = (mapped as? [Double]) ?? [0, 0, 0, 0]
            // color[0..2] are 0..255 rgb; color[3] is 0..1 (clampCssFloat) — the Uint8ClampedArray
            //   store rounds it to 0/1, matching upstream's gradient alpha behavior.
            pixels[off] = clampU8(c.count > 0 ? c[0] : 0)
            pixels[off + 1] = clampU8(c.count > 1 ? c[1] : 0)
            pixels[off + 2] = clampU8(c.count > 2 ? c[2] : 0)
            pixels[off + 3] = clampU8((c.count > 3 ? c[3] : 0) * 255)
            off += 4
        }
        self._gradientPixels[state] = pixels
        return pixels
    }

    /// Wrap the STRAIGHT-alpha RGBA `pixels` buffer as a `CGImage` (the produced offscreen "canvas").
    /// Uses `CGImageAlphaInfo.last` (non-premultiplied) to match canvas `putImageData` byte semantics;
    /// the painter blits it via `ZRImage` → `drawImage`.
    public func makeImage() -> CGImage? {
        if width <= 0 || height <= 0 || pixels.count < width * height * 4 { return nil }
        let cs = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue)
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: cs,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }
}

// Reproduce `Uint8ClampedArray` element assignment: round-half-to-even then clamp to [0, 255].
private func clampU8(_ value: Double) -> UInt8 {
    if value.isNaN { return 0 }
    if value <= 0 { return 0 }
    if value >= 255 { return 255 }
    let rounded = value.rounded(.toNearestOrEven)
    return UInt8(rounded)
}
