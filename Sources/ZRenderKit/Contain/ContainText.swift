// Ported from zrender/src/contain/text.ts — keep in sync with upstream

import Foundation

// upstream:
//   import BoundingRect, { RectLike } from '../core/BoundingRect';   → Core/BoundingRect.swift
//   import { TextAlign, TextVerticalAlign, BuiltinTextPosition } from '../core/types';
//   import LRU from '../core/LRU';
//   import { DEFAULT_FONT, platformApi } from '../core/platform';

// upstream: `export interface FontMeasureInfo`.
// Modeled as a `final class` (NOT a struct): `measureCharWidth` mutates `asciiWidthMap` /
// `asciiWidthMapTried` on the instance stored inside the `_fontMeasureInfoCache` LRU, and
// that mutation must persist for the cached entry (reference semantics, CONVENTIONS §4).
public final class FontMeasureInfo {
    public var font: String
    public var strWidthCache: LRU<Double>
    // Key: char code, index: 0~127 (include 127)
    public var asciiWidthMap: [Double]?
    public var asciiWidthMapTried: Bool
    // Default width char width used both in non-ascii and line height.
    public var stWideCharWidth: Double
    // Default asc char width
    public var asciiCharWidth: Double

    public init(
        font: String,
        strWidthCache: LRU<Double>,
        asciiWidthMap: [Double]?,
        asciiWidthMapTried: Bool,
        stWideCharWidth: Double,
        asciiCharWidth: Double
    ) {
        self.font = font
        self.strWidthCache = strWidthCache
        self.asciiWidthMap = asciiWidthMap
        self.asciiWidthMapTried = asciiWidthMapTried
        self.stWideCharWidth = stWideCharWidth
        self.asciiCharWidth = asciiCharWidth
    }
}

// upstream: `export interface TextPositionCalculationResult { x, y, align, verticalAlign }`.
// `final class` so `calculateTextPosition`'s out-param mutation propagates to the caller
// (Element reuses a shared `tmpTextPosCalcRes` instance), CONVENTIONS §4.
// upstream types `align`/`verticalAlign` as non-optional (strictNullChecks off),
// but the array-position branch assigns them `null`; modeled as Optional per CONVENTIONS §6.
public final class TextPositionCalculationResult {
    public var x: Double
    public var y: Double
    public var align: TextAlign?
    public var verticalAlign: TextVerticalAlign?

    public init(
        x: Double = 0,
        y: Double = 0,
        align: TextAlign? = nil,
        verticalAlign: TextVerticalAlign? = nil
    ) {
        self.x = x
        self.y = y
        self.align = align
        self.verticalAlign = verticalAlign
    }
}

/// Upstream `value: number | string`. Swift has no untagged union, so — like `LRUKey`
/// (LRU.swift) and `CssParam` (color.swift) — we model the value as a tagged enum with
/// literal conformances so call sites stay close to upstream.
public enum NumberOrString {
    case number(Double)
    case string(String)
}

extension NumberOrString: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
}
extension NumberOrString: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) { self = .number(Double(value)) }
}
extension NumberOrString: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) { self = .number(value) }
}

/// Upstream `position?: BuiltinTextPosition | (number | string)[]`.
public enum BuiltinTextPositionOrArray {
    case position(BuiltinTextPosition)
    case array([NumberOrString])
}

/// Upstream inline opts type `{ position?, distance?, global? }` passed to
/// `calculateTextPosition`.
public struct CalculateTextPositionOpts {
    public var position: BuiltinTextPositionOrArray?
    public var distance: Double?   // Default 5
    public var global: Bool?

    public init(
        position: BuiltinTextPositionOrArray? = nil,
        distance: Double? = nil,
        global: Bool? = nil
    ) {
        self.position = position
        self.distance = distance
        self.global = global
    }
}

// upstream marker: free-function module → caseless `enum` namespace (CONVENTIONS §2).
//   Imported elsewhere via named imports (`import { adjustTextX, parsePercent } from
//   '../contain/text'`); call sites become `text.adjustTextX(...)` etc.
public enum text {

    /**
     * @deprecated But keep for possible outside usage.
     *  Use `ensureFontMeasureInfo` + `measureWidth` instead.
     */
    public static func getWidth(_ text: String, _ font: String) -> Double {
        return measureWidth(ensureFontMeasureInfo(font), text)
    }

    public static func ensureFontMeasureInfo(_ font: String?) -> FontMeasureInfo {
        if _fontMeasureInfoCache == nil {
            _fontMeasureInfoCache = LRU(100)
        }
        // font = font || DEFAULT_FONT — also treats '' as falsy.
        let font = (font == nil || font!.isEmpty) ? DEFAULT_FONT : font!
        var measureInfo = _fontMeasureInfoCache!.get(.string(font))
        if measureInfo == nil {
            measureInfo = FontMeasureInfo(
                font: font,
                strWidthCache: LRU(500),
                asciiWidthMap: nil, // Init lazily for performance.
                asciiWidthMapTried: false,
                // FIXME
                // Other languages?
                // FIXME
                // Consider proportional font?
                stWideCharWidth: platformApi.measureText("国", font).width,
                asciiCharWidth: platformApi.measureText("a", font).width
            )
            _fontMeasureInfoCache!.put(.string(font), measureInfo!)
        }
        return measureInfo!
    }
    private static var _fontMeasureInfoCache: LRU<FontMeasureInfo>?

    /**
     * For getting more precise result in truncate.
     * non-monospace font vary in char width.
     * But if it is time consuming in some platform, return null/undefined.
     * @return Key: char code, index: 0~127 (include 127)
     */
    private static func tryCreateASCIIWidthMap(_ font: String?) -> [Double]? {
        // PENDING: is it necessary? Re-examine it if bad case reported.
        if _getASCIIWidthMapLongCount >= GET_ASCII_WIDTH_LONG_COUNT_MAX {
            return nil
        }
        let font = (font == nil || font!.isEmpty) ? DEFAULT_FONT : font!
        var asciiWidthMap: [Double] = []
        let start = Date().timeIntervalSince1970 * 1000   // +(new Date())
        // 0~31 and 127 may also have width, and may vary in some fonts.
        for code in 0...127 {
            // index `code` filled in order (0...127) — matches `asciiWidthMap[code] = ...`.
            asciiWidthMap.append(platformApi.measureText(String(UnicodeScalar(UInt32(code))!), font).width)
        }
        let cost = Date().timeIntervalSince1970 * 1000 - start
        if cost > 16 {
            _getASCIIWidthMapLongCount = GET_ASCII_WIDTH_LONG_COUNT_MAX
        }
        else if cost > 2 {
            _getASCIIWidthMapLongCount += 1
        }
        return asciiWidthMap
    }
    private static var _getASCIIWidthMapLongCount: Double = 0
    private static let GET_ASCII_WIDTH_LONG_COUNT_MAX: Double = 5

    /**
     * Hot path, performance sensitive.
     */
    public static func measureCharWidth(_ fontMeasureInfo: FontMeasureInfo, _ charCode: Double) -> Double {
        if !fontMeasureInfo.asciiWidthMapTried {
            fontMeasureInfo.asciiWidthMap = tryCreateASCIIWidthMap(fontMeasureInfo.font)
            fontMeasureInfo.asciiWidthMapTried = true
        }
        return (0 <= charCode && charCode <= 127)
            ? (fontMeasureInfo.asciiWidthMap != nil
                ? fontMeasureInfo.asciiWidthMap![Int(charCode)]
                : fontMeasureInfo.asciiCharWidth
            )
            : fontMeasureInfo.stWideCharWidth
    }

    public static func measureWidth(_ fontMeasureInfo: FontMeasureInfo, _ text: String) -> Double {
        let strWidthCache = fontMeasureInfo.strWidthCache
        var width = strWidthCache.get(.string(text))
        if width == nil {
            width = platformApi.measureText(text, fontMeasureInfo.font).width
            strWidthCache.put(.string(text), width!)
        }
        return width!
    }


    /**
     * @deprecated See `getBoundingRect`.
     * Get bounding rect for inner usage(TSpan)
     * Which not include text newline.
     */
    public static func innerGetBoundingRect(
        _ text: String,
        _ font: String,
        _ textAlign: TextAlign? = nil,
        _ textBaseline: TextVerticalAlign? = nil
    ) -> BoundingRect {
        let width = measureWidth(ensureFontMeasureInfo(font), text)
        let height = getLineHeight(font)

        let x = adjustTextX(0, width, textAlign)
        let y = adjustTextY(0, height, textBaseline)

        let rect = BoundingRect(x, y, width, height)

        return rect
    }

    /**
     * @deprecated Use `(new Text(...)).getBoundingRect()` or `(new TSpan(...)).getBoundingRect()` instead.
     *  This method behaves differently from `Text#getBoundingRect()` - e.g., it does not support the overflow
     *  strategy, and only has single line height even if multiple lines.
     *
     * Get bounding rect for outer usage. Compatitable with old implementation
     * Which includes text newline.
     */
    public static func getBoundingRect(
        _ text: String?,
        _ font: String,
        _ textAlign: TextAlign? = nil,
        _ textBaseline: TextVerticalAlign? = nil
    ) -> BoundingRect {
        // ((text || '') + '').split('\n')
        let textLines = (text ?? "").components(separatedBy: "\n")
        let len = textLines.count
        if len == 1 {
            return innerGetBoundingRect(textLines[0], font, textAlign, textBaseline)
        }
        else {
            let uniondRect = BoundingRect(0, 0, 0, 0)
            for i in 0..<textLines.count {
                let rect = innerGetBoundingRect(textLines[i], font, textAlign, textBaseline)
                i == 0 ? uniondRect.copy(rect) : uniondRect.union(rect)
            }
            return uniondRect
        }
    }

    public static func adjustTextX(_ x: Double, _ width: Double, _ textAlign: TextAlign?, _ inverse: Bool? = nil) -> Double {
        var x = x
        // TODO Right to left language
        if textAlign == .right {
            inverse != true ? (x -= width) : (x += width)
        }
        else if textAlign == .center {
            inverse != true ? (x -= width / 2) : (x += width / 2)
        }
        return x
    }

    public static func adjustTextY(_ y: Double, _ height: Double, _ verticalAlign: TextVerticalAlign?, _ inverse: Bool? = nil) -> Double {
        var y = y
        if verticalAlign == .middle {
            inverse != true ? (y -= height / 2) : (y += height / 2)
        }
        else if verticalAlign == .bottom {
            inverse != true ? (y -= height) : (y += height)
        }
        return y
    }

    public static func getLineHeight(_ font: String? = nil) -> Double {
        // FIXME A rough approach.
        return ensureFontMeasureInfo(font).stWideCharWidth
    }

    public static func measureText(_ text: String, _ font: String? = nil) -> TextMetrics {
        return platformApi.measureText(text, font)
    }


    public static func parsePercent(_ value: NumberOrString, _ maxValue: Double) -> Double {
        switch value {
        case .string(let value):
            // value.lastIndexOf('%') >= 0
            if value.contains("%") {
                // color.parseFloat: faithful JS `parseFloat` (Tool/color.swift), reused here.
                return color.parseFloat(value) / 100 * maxValue
            }
            return color.parseFloat(value)
        case .number(let value):
            return value
        }
    }

    /**
     * Follow same interface to `Displayable.prototype.calculateTextPosition`.
     * @public
     * @param out Prepared out object. If not input, auto created in the method.
     * @param style where `textPosition` and `textDistance` are visited.
     * @param rect {x, y, width, height} Rect of the host elment, according to which the text positioned.
     * @return The input `out`. Set: {x, y, textAlign, textVerticalAlign}
     */
    @discardableResult
    public static func calculateTextPosition(
        _ out: TextPositionCalculationResult?,
        _ opts: CalculateTextPositionOpts,
        _ rect: RectLike
    ) -> TextPositionCalculationResult {
        let textPosition = opts.position ?? .position(.inside)
        let distance = opts.distance != nil ? opts.distance! : 5

        let height = rect.height
        let width = rect.width
        let halfHeight = height / 2

        var x = rect.x
        var y = rect.y

        var textAlign: TextAlign? = .left
        var textVerticalAlign: TextVerticalAlign? = .top

        if case let .array(textPosition) = textPosition {
            x += parsePercent(textPosition[0], rect.width)
            y += parsePercent(textPosition[1], rect.height)
            // Not use textAlign / textVerticalAlign
            textAlign = nil
            textVerticalAlign = nil
        }
        else if case let .position(textPosition) = textPosition {
            switch textPosition {
                case .left:
                    x -= distance
                    y += halfHeight
                    textAlign = .right
                    textVerticalAlign = .middle
                case .right:
                    x += distance + width
                    y += halfHeight
                    textVerticalAlign = .middle
                case .top:
                    x += width / 2
                    y -= distance
                    textAlign = .center
                    textVerticalAlign = .bottom
                case .bottom:
                    x += width / 2
                    y += height + distance
                    textAlign = .center
                case .inside:
                    x += width / 2
                    y += halfHeight
                    textAlign = .center
                    textVerticalAlign = .middle
                case .insideLeft:
                    x += distance
                    y += halfHeight
                    textVerticalAlign = .middle
                case .insideRight:
                    x += width - distance
                    y += halfHeight
                    textAlign = .right
                    textVerticalAlign = .middle
                case .insideTop:
                    x += width / 2
                    y += distance
                    textAlign = .center
                case .insideBottom:
                    x += width / 2
                    y += height - distance
                    textAlign = .center
                    textVerticalAlign = .bottom
                case .insideTopLeft:
                    x += distance
                    y += distance
                case .insideTopRight:
                    x += width - distance
                    y += distance
                    textAlign = .right
                case .insideBottomLeft:
                    x += distance
                    y += height - distance
                    textVerticalAlign = .bottom
                case .insideBottomRight:
                    x += width - distance
                    y += height - distance
                    textAlign = .right
                    textVerticalAlign = .bottom
            }
        }

        let out = out ?? TextPositionCalculationResult()
        out.x = x
        out.y = y
        out.align = textAlign
        out.verticalAlign = textVerticalAlign

        return out
    }
}
