// Ported from echarts/src/util/symbol.ts — keep in sync with upstream

// Symbol factory

// upstream imports (resolved to the ported modules):
// import { each, isArray, retrieve2 } from 'zrender/src/core/util';    -> `util.each` / `util.isArray` / `util.retrieve2` (ZRenderKit)
// import * as graphic from './graphic';                                -> ZRenderKit shapes (Line/Rect/Circle) + Path
// import BoundingRect from 'zrender/src/core/BoundingRect';            -> ZRenderKit.BoundingRect (image:// / path:// branches — PORT-NOTE)
// import { calculateTextPosition } from 'zrender/src/contain/text';    -> ZRenderKit.text.calculateTextPosition
// import { Dictionary } from 'zrender/src/core/types';                 -> `[String: T]`
// import { SymbolOptionMixin, ZRColor } from './types';                -> ZRColor is zrender's ZRColor (== ZRenderKit.ZRColor), the type the
//                                                                         PathStyleProps fill/stroke fields carry (NOT EChartsKit.ZRColor); see NOTE below.
// import { parsePercent } from './number';                             -> `number.parsePercent` (EChartsKit)
// import tokens from '../visual/tokens';                               -> PORT-NOTE: `tokens.color.neutral00` inlined verbatim below (visual/tokens.swift is ported).

import Foundation
import ZRenderKit

// PORT-NOTE: `tokens.color.neutral00` is the neutral white
//   used as the empty-brush inner fill; inlined verbatim (== "#fff"), the same way BarSeries inlined
//   `tokens.color.primary`.
private let tokensColorNeutral00 = "#fff"

// NOTE (ZRColor divergence): upstream `ZRColor` re-exported from echarts `./types` is zrender's
//   `ZRColor` — the exact type the ported `PathStyleProps.fill`/`.stroke` fields carry
//   (`ZRenderKit.ZRColor`, the `.string(...)` enum). EChartsKit ALSO has its own `ZRColor`
//   (`.color(...)`), but that is not the type stored on the path style. So `setColor`/`getColor`
//   are typed against `ZRenderKit.ZRColor` to assign the style fields directly (faithful — upstream
//   `symbolStyle.stroke = color`).

// upstream:
//   export type ECSymbol = graphic.Path & {
//       __isEmptyBrush?: boolean
//       setColor: (color: ZRColor, innerColor?: ZRColor) => void
//       getColor: () => ZRColor
//   };
// PORT-NOTE: TS intersection type `graphic.Path & { ... }` — Swift protocols cannot inherit a class,
//   so `ECSymbol` is a plain protocol declaring only the three added members. `SymbolPath` (the
//   `SymbolClz` conformer) is a real `Path` subclass AND conforms to `ECSymbol`; the image:// /
//   path:// branches (which return `graphic.Image` / a `makePath` Path) are deferred.
public protocol ECSymbol: AnyObject {
    var __isEmptyBrush: Bool { get set }
    func setColor(_ color: ZRenderKit.ZRColor, _ innerColor: ZRenderKit.ZRColor?)
    func getColor() -> ZRenderKit.ZRColor
}

// upstream: type SymbolCtor = { new(): ECSymbol };
//   PORT-NOTE: Swift cannot `new Ctor()` a metatype uniformly across the mixed shape classes; the
//   `symbolCtors` map is modeled as factory closures `[String: () -> Path]` (documented deviation).
// upstream: type SymbolShapeMaker = (x, y, w, h, shape: Dictionary<any>) => void;
//   ADAPTATION: upstream mutates the shared proxy's `.shape` object in place; our `Path.shape` is a
//   value-type struct behind the `PathShape` existential, so each maker takes the proxy `Path` and
//   rebuilds its concrete shape struct via `proxy.setShape(...)`.

/**
 * Triangle shape
 * @inner
 */
// upstream: const Triangle = graphic.Path.extend({ type: 'triangle', shape: {cx,cy,width,height}, buildPath })
public struct TriangleShape: PathShape {
    public var cx: Double = 0
    public var cy: Double = 0
    public var width: Double = 0
    public var height: Double = 0
    public init() {}

    public func animationGet(_ key: String) -> Any? {
        switch key {
        case "cx": return cx
        case "cy": return cy
        case "width": return width
        case "height": return height
        default: return nil
        }
    }

    public mutating func animationSet(_ key: String, _ value: Any?) {
        guard let v = value as? Double else { return }
        switch key {
        case "cx": cx = v
        case "cy": cy = v
        case "width": width = v
        case "height": height = v
        default: break
        }
    }
}

public final class Triangle: Path {
    public override init(_ opts: PathProps? = nil) {
        super.init(opts)
        self.type = "triangle"
    }

    public override func getDefaultShape() -> PathShape {
        return TriangleShape()
    }

    public override func buildPath(_ path: PathProxy, _ shapeIn: PathShape, _ inBatch: Bool) {
        let shape = shapeIn as! TriangleShape
        let cx = shape.cx
        let cy = shape.cy
        let width = shape.width / 2
        let height = shape.height / 2
        _ = path.moveTo(cx, cy - height)
        _ = path.lineTo(cx + width, cy + height)
        _ = path.lineTo(cx - width, cy + height)
        _ = path.closePath()
    }
}

/**
 * Diamond shape
 * @inner
 */
// upstream: const Diamond = graphic.Path.extend({ type: 'diamond', shape: {cx,cy,width,height}, buildPath })
public struct DiamondShape: PathShape {
    public var cx: Double = 0
    public var cy: Double = 0
    public var width: Double = 0
    public var height: Double = 0
    public init() {}

    public func animationGet(_ key: String) -> Any? {
        switch key {
        case "cx": return cx
        case "cy": return cy
        case "width": return width
        case "height": return height
        default: return nil
        }
    }

    public mutating func animationSet(_ key: String, _ value: Any?) {
        guard let v = value as? Double else { return }
        switch key {
        case "cx": cx = v
        case "cy": cy = v
        case "width": width = v
        case "height": height = v
        default: break
        }
    }
}

public final class Diamond: Path {
    public override init(_ opts: PathProps? = nil) {
        super.init(opts)
        self.type = "diamond"
    }

    public override func getDefaultShape() -> PathShape {
        return DiamondShape()
    }

    public override func buildPath(_ path: PathProxy, _ shapeIn: PathShape, _ inBatch: Bool) {
        let shape = shapeIn as! DiamondShape
        let cx = shape.cx
        let cy = shape.cy
        let width = shape.width / 2
        let height = shape.height / 2
        _ = path.moveTo(cx, cy - height)
        _ = path.lineTo(cx + width, cy)
        _ = path.lineTo(cx, cy + height)
        _ = path.lineTo(cx - width, cy)
        _ = path.closePath()
    }
}

/**
 * Pin shape
 * @inner
 */
// upstream: const Pin = graphic.Path.extend({ type: 'pin', shape: {x,y,width,height}, buildPath })
public struct PinShape: PathShape {
    // x, y on the cusp
    public var x: Double = 0
    public var y: Double = 0
    public var width: Double = 0
    public var height: Double = 0
    public init() {}

    public func animationGet(_ key: String) -> Any? {
        switch key {
        case "x": return x
        case "y": return y
        case "width": return width
        case "height": return height
        default: return nil
        }
    }

    public mutating func animationSet(_ key: String, _ value: Any?) {
        guard let v = value as? Double else { return }
        switch key {
        case "x": x = v
        case "y": y = v
        case "width": width = v
        case "height": height = v
        default: break
        }
    }
}

public final class Pin: Path {
    public override init(_ opts: PathProps? = nil) {
        super.init(opts)
        self.type = "pin"
    }

    public override func getDefaultShape() -> PathShape {
        return PinShape()
    }

    public override func buildPath(_ path: PathProxy, _ shapeIn: PathShape, _ inBatch: Bool) {
        let shape = shapeIn as! PinShape
        let x = shape.x
        let y = shape.y
        let w = shape.width / 5 * 3
        // Height must be larger than width
        let h = Swift.max(w, shape.height)
        let r = w / 2

        // Dist on y with tangent point and circle center
        let dy = r * r / (h - r)
        let cy = y - h + r + dy
        let angle = asin(dy / r)
        // Dist on x with tangent point and circle center
        let dx = cos(angle) * r

        let tanX = sin(angle)
        let tanY = cos(angle)

        let cpLen = r * 0.6
        let cpLen2 = r * 0.7

        _ = path.moveTo(x - dx, cy + dy)

        _ = path.arc(
            x, cy, r,
            Double.pi - angle,
            Double.pi * 2 + angle
        )
        _ = path.bezierCurveTo(
            x + dx - tanX * cpLen, cy + dy + tanY * cpLen,
            x, y - cpLen2,
            x, y
        )
        _ = path.bezierCurveTo(
            x, y - cpLen2,
            x - dx + tanX * cpLen, cy + dy + tanY * cpLen,
            x - dx, cy + dy
        )
        _ = path.closePath()
    }
}

/**
 * Arrow shape
 * @inner
 */
// upstream: const Arrow = graphic.Path.extend({ type: 'arrow', shape: {x,y,width,height}, buildPath })
public struct ArrowShape: PathShape {
    public var x: Double = 0
    public var y: Double = 0
    public var width: Double = 0
    public var height: Double = 0
    public init() {}

    public func animationGet(_ key: String) -> Any? {
        switch key {
        case "x": return x
        case "y": return y
        case "width": return width
        case "height": return height
        default: return nil
        }
    }

    public mutating func animationSet(_ key: String, _ value: Any?) {
        guard let v = value as? Double else { return }
        switch key {
        case "x": x = v
        case "y": y = v
        case "width": width = v
        case "height": height = v
        default: break
        }
    }
}

public final class Arrow: Path {
    public override init(_ opts: PathProps? = nil) {
        super.init(opts)
        self.type = "arrow"
    }

    public override func getDefaultShape() -> PathShape {
        return ArrowShape()
    }

    public override func buildPath(_ ctx: PathProxy, _ shapeIn: PathShape, _ inBatch: Bool) {
        let shape = shapeIn as! ArrowShape
        let height = shape.height
        let width = shape.width
        let x = shape.x
        let y = shape.y
        let dx = width / 3 * 2
        _ = ctx.moveTo(x, y)
        _ = ctx.lineTo(x + dx, y + height)
        _ = ctx.lineTo(x, y + height / 4 * 3)
        _ = ctx.lineTo(x - dx, y + height)
        _ = ctx.lineTo(x, y)
        _ = ctx.closePath()
    }
}

// upstream: const SymbolClz = graphic.Path.extend({ type: 'symbol', shape: {symbolType,x,y,width,height},
//   calculateTextPosition, buildPath })
public struct SymbolShape: PathShape {
    public var symbolType: String = ""
    public var x: Double = 0
    public var y: Double = 0
    public var width: Double = 0
    public var height: Double = 0
    public init() {}

    // symbolType (a String) is not tweened; only the numeric geometry fields are exposed.
    public func animationGet(_ key: String) -> Any? {
        switch key {
        case "x": return x
        case "y": return y
        case "width": return width
        case "height": return height
        default: return nil
        }
    }

    public mutating func animationSet(_ key: String, _ value: Any?) {
        guard let v = value as? Double else { return }
        switch key {
        case "x": x = v
        case "y": y = v
        case "width": width = v
        case "height": height = v
        default: break
        }
    }
}

// upstream: SymbolClz. `type = 'symbol'`; conforms to `ECSymbol` (setColor/getColor/__isEmptyBrush).
public final class SymbolPath: Path, ECSymbol {

    // upstream: `(symbolPath as ECSymbol).__isEmptyBrush = isEmpty;` (set by createSymbol).
    public var __isEmptyBrush: Bool = false

    public override init(_ opts: PathProps? = nil) {
        super.init(opts)
        self.type = "symbol"
        // upstream overrides `calculateTextPosition` as a prototype method; our Element models it as a
        //   settable hook (`Element.calculateTextPosition`), so wire it here.
        self.calculateTextPosition = { [unowned self] out, config, rect in
            var opts = CalculateTextPositionOpts()
            opts.position = SymbolPath.textConfigPositionOpt(config.position)
            opts.distance = config.distance
            let res = ZRenderKit.text.calculateTextPosition(out, opts, rect)
            let shape = self.shape as? SymbolShape
            // upstream: if (shape && shape.symbolType === 'pin' && config.position === 'inside')
            let isInside = (config.position as? BuiltinTextPosition == .inside)
                || (config.position as? String == "inside")
            if let shape = shape, shape.symbolType == "pin", isInside {
                res.y = rect.y + rect.height * 0.4
            }
            return res
        }
    }

    // Convert `textConfig.position` (the `Any?` union) into the typed opts contain/text takes.
    //   (Mirrors Element's private `_textConfigPositionOpt`, which is not accessible from here.)
    private static func textConfigPositionOpt(_ pos: Any?) -> BuiltinTextPositionOrArray? {
        if let bp = pos as? BuiltinTextPosition { return .position(bp) }
        if let s = pos as? String, let bp = BuiltinTextPosition(rawValue: s) { return .position(bp) }
        // upstream `position: (number | string)[]` — percent strings must reach `parsePercent`, so carry
        //   them through as `.string` instead of dropping the whole array (kept in sync with Element).
        if let arr = pos as? [Any] {
            return .array(arr.map { v in
                if let d = v as? Double { return NumberOrString.number(d) }
                if let i = v as? Int { return NumberOrString.number(Double(i)) }
                if let n = v as? NSNumber { return NumberOrString.number(n.doubleValue) }
                return NumberOrString.string(v as? String ?? "")
            })
        }
        return nil
    }

    public override func getDefaultShape() -> PathShape {
        return SymbolShape()
    }

    public override func buildPath(_ ctx: PathProxy, _ shapeIn: PathShape, _ inBundle: Bool) {
        let shape = shapeIn as! SymbolShape
        var symbolType = shape.symbolType
        if symbolType != "none" {
            var proxySymbol = symbol.symbolBuildProxies[symbolType]
            if proxySymbol == nil {
                // Default rect
                symbolType = "rect"
                proxySymbol = symbol.symbolBuildProxies[symbolType]
            }
            symbol.symbolShapeMakers[symbolType]!(
                shape.x, shape.y, shape.width, shape.height, proxySymbol!
            )
            proxySymbol!.buildPath(ctx, proxySymbol!.shape, inBundle)
        }
    }

    // Provide setColor helper method to avoid determine if set the fill or stroke outside
    // upstream: function symbolPathSetColor(this: ECSymbol, color, innerColor?) { ... }
    //   Assigned dynamically onto the returned symbol in createSymbol; here it is a native method on
    //   the `SymbolClz` conformer (the image:// / path:// conformers are deferred).
    public func setColor(_ color: ZRenderKit.ZRColor, _ innerColor: ZRenderKit.ZRColor? = nil) {
        if self.type != "image" {
            // upstream: const symbolStyle = this.style; (== our `self.pathStyle`)
            if self.__isEmptyBrush {
                self.pathStyle.stroke = color
                self.pathStyle.fill = innerColor ?? .string(tokensColorNeutral00)
                // TODO Same width with lineStyle in LineView
                self.pathStyle.lineWidth = 2
            }
            else if (self.shape as! SymbolShape).symbolType == "line" {
                self.pathStyle.stroke = color
            }
            else {
                self.pathStyle.fill = color
            }
            self.markRedraw()
        }
    }

    // upstream: ECSymbol declares `getColor: () => ZRColor` but symbol.ts never assigns it here (it is
    //   supplied by callers, e.g. chart/helper/Symbol). Provide a faithful reader off the style bag.
    // PORT-NOTE: upstream `getColor` is set externally; returns the fill (or stroke) currently painted.
    public func getColor() -> ZRenderKit.ZRColor {
        return self.pathStyle.fill ?? self.pathStyle.stroke ?? .string(tokensColorNeutral00)
    }
}

// A `path://` symbol is built as a ZRenderKit `SVGPath` (util/symbol.createSymbol → ToolPath.makePath).
//   `createSymbol` returns an `ECSymbol`, so `SVGPath` conforms here. `__isEmptyBrush` is stored on the
//   ZRenderKit class (extensions cannot add stored properties); `setColor`/`getColor` mirror SymbolPath.
extension ZRenderKit.SVGPath: ECSymbol {
    public func setColor(_ color: ZRenderKit.ZRColor, _ innerColor: ZRenderKit.ZRColor? = nil) {
        if self.type == "image" { return }
        if self.__isEmptyBrush {
            self.pathStyle.stroke = color
            self.pathStyle.fill = innerColor ?? .string(tokensColorNeutral00)
            self.pathStyle.lineWidth = 2
        } else {
            self.pathStyle.fill = color
        }
        self.markRedraw()
    }

    public func getColor() -> ZRenderKit.ZRColor {
        return self.pathStyle.fill ?? self.pathStyle.stroke ?? .string(tokensColorNeutral00)
    }
}

// An `image://` symbol is built as a ZRenderKit `ZRImage` (util/symbol.createSymbol → ToolPath.makeImage).
//   `createSymbol` returns an `ECSymbol`, so `ZRImage` conforms here. `__isEmptyBrush` is stored on the
//   ZRenderKit class. `setColor` is a NO-OP for an image (upstream `symbolPathSetColor` early-returns when
//   `this.type === 'image'` — an image's pixels are not recoloured); `getColor` returns transparent.
extension ZRenderKit.ZRImage: ECSymbol {
    public func setColor(_ color: ZRenderKit.ZRColor, _ innerColor: ZRenderKit.ZRColor? = nil) {
        // upstream: `if (this.type === 'image') { return; }`
    }

    public func getColor() -> ZRenderKit.ZRColor {
        return .string("transparent")
    }
}

// upstream: free-function exports (createSymbol / normalizeSymbolSize / normalizeSymbolOffset /
//   symbolBuildProxies). Per CONVENTIONS §2 a free-function module maps to a caseless `enum`
//   namespace named after the file (`symbol`). The shape subclasses above are exported class-likes,
//   so they stay top-level.
public enum symbol {

    /**
     * Map of path constructors
     */
    // TODO Use function to build symbol path.
    // upstream: const symbolCtors: Dictionary<SymbolCtor> = { line, rect, roundRect, square, circle,
    //   diamond, pin, arrow, triangle }. PORT-NOTE: modeled as factory closures (see SymbolCtor note).
    fileprivate static let symbolCtors: [String: () -> Path] = [
        "line": { Line() },

        "rect": { Rect() },

        "roundRect": { Rect() },

        "square": { Rect() },

        "circle": { Circle() },

        "diamond": { Diamond() },

        "pin": { Pin() },

        "arrow": { Arrow() },

        "triangle": { Triangle() }
    ]

    // upstream: const symbolShapeMakers: Dictionary<SymbolShapeMaker> = { ... }.
    //   ADAPTATION: each maker receives the proxy `Path` and rebuilds its concrete shape struct in
    //   place via `setShape` (the value-type `.shape` cannot be mutated field-by-field through the
    //   existential); the per-name field math is preserved verbatim.
    fileprivate static let symbolShapeMakers: [String: (Double, Double, Double, Double, Path) -> Void] = [

        "line": { x, y, w, h, proxy in
            var shape = LineShape()
            shape.x1 = x
            shape.y1 = y + h / 2
            shape.x2 = x + w
            shape.y2 = y + h / 2
            proxy.setShape(shape)
        },

        "rect": { x, y, w, h, proxy in
            var shape = RectShape()
            shape.x = x
            shape.y = y
            shape.width = w
            shape.height = h
            proxy.setShape(shape)
        },

        "roundRect": { x, y, w, h, proxy in
            var shape = RectShape()
            shape.x = x
            shape.y = y
            shape.width = w
            shape.height = h
            shape.r = .number(Swift.min(w, h) / 4)
            proxy.setShape(shape)
        },

        "square": { x, y, w, h, proxy in
            let size = Swift.min(w, h)
            var shape = RectShape()
            shape.x = x
            shape.y = y
            shape.width = size
            shape.height = size
            proxy.setShape(shape)
        },

        "circle": { x, y, w, h, proxy in
            var shape = CircleShape()
            // Put circle in the center of square
            shape.cx = x + w / 2
            shape.cy = y + h / 2
            shape.r = Swift.min(w, h) / 2
            proxy.setShape(shape)
        },

        "diamond": { x, y, w, h, proxy in
            var shape = DiamondShape()
            shape.cx = x + w / 2
            shape.cy = y + h / 2
            shape.width = w
            shape.height = h
            proxy.setShape(shape)
        },

        "pin": { x, y, w, h, proxy in
            var shape = PinShape()
            shape.x = x + w / 2
            shape.y = y + h / 2
            shape.width = w
            shape.height = h
            proxy.setShape(shape)
        },

        "arrow": { x, y, w, h, proxy in
            var shape = ArrowShape()
            shape.x = x + w / 2
            shape.y = y + h / 2
            shape.width = w
            shape.height = h
            proxy.setShape(shape)
        },

        "triangle": { x, y, w, h, proxy in
            var shape = TriangleShape()
            shape.cx = x + w / 2
            shape.cy = y + h / 2
            shape.width = w
            shape.height = h
            proxy.setShape(shape)
        }
    ]

    // upstream:
    //   export const symbolBuildProxies: Dictionary<ECSymbol> = {};
    //   each(symbolCtors, function (Ctor, name) { symbolBuildProxies[name] = new Ctor(); });
    // PORT-NOTE: no `util.each` dict overload — iterate the dict directly (order-independent).
    public static let symbolBuildProxies: [String: Path] = {
        var proxies: [String: Path] = [:]
        for (name, Ctor) in symbolCtors {
            proxies[name] = Ctor()
        }
        return proxies
    }()

    /**
     * Create a symbol element with given symbol configuration: shape, x, y, width, height, color
     */
    // upstream: export function createSymbol(symbolType, x, y, w, h, color?, keepAspect?)
    @discardableResult
    public static func createSymbol(
        _ symbolTypeIn: String,
        _ x: Double,
        _ y: Double,
        _ w: Double,
        _ h: Double,
        _ color: ZRenderKit.ZRColor? = nil,
        // whether to keep the ratio of w/h,
        _ keepAspect: Bool? = nil
    ) -> ECSymbol {
        // TODO Support image object, DynamicImage.

        var symbolType = symbolTypeIn
        let isEmpty = symbolType.hasPrefix("empty")   // upstream: symbolType.indexOf('empty') === 0
        if isEmpty {
            // upstream: symbolType.substr(5, 1).toLowerCase() + symbolType.substr(6)
            symbolType = jsSubstr(symbolType, 5, 1).lowercased() + jsSubstr(symbolType, 6)
        }
        let symbolPath: ECSymbol

        if symbolType.hasPrefix("image://") {
            // upstream: `graphic.makeImage(symbolType.slice(8), new BoundingRect(x,y,w,h),
            //   keepAspect ? 'center' : 'cover')`. `makeImage` + `ZRImage` (ECSymbol conformer above) are
            //   ported; the returned ZRImage renders via the painter's drawZRImage.
            let src = String(symbolType.dropFirst("image://".count))
            symbolPath = ZRenderKit.makeImage(
                src, BoundingRect(x, y, w, h), (keepAspect ?? false) ? "center" : "cover"
            )
        }
        else if symbolType.hasPrefix("path://") {
            // upstream: `graphic.makePath(symbolType.slice(7), {}, new BoundingRect(x,y,w,h),
            //   keepAspect ? 'center' : 'cover')`. The SVG parser + resize live in ZRenderKit
            //   (ToolPath.makePath); the returned SVGPath conforms to ECSymbol via the extension below.
            let pathData = String(symbolType.dropFirst("path://".count))
            symbolPath = ZRenderKit.makePath(
                pathData, nil, BoundingRect(x, y, w, h), (keepAspect ?? false) ? "center" : "cover"
            )
        }
        else {
            var shape = SymbolShape()
            shape.symbolType = symbolType
            shape.x = x
            shape.y = y
            shape.width = w
            shape.height = h
            symbolPath = SymbolPath(["shape": shape])
        }

        symbolPath.__isEmptyBrush = isEmpty

        // TODO Should deprecate setColor
        // upstream assigns `(symbolPath as ECSymbol).setColor = symbolPathSetColor`; our conformer
        //   implements setColor natively (see SymbolPath.setColor).

        if let color = color {
            symbolPath.setColor(color, nil)
        }

        return symbolPath
    }

    // Fallback builder for the deferred image:// / path:// branches (see createSymbol PORT-NOTEs).
    private static func makeFallbackSymbol(_ symbolType: String, _ x: Double, _ y: Double, _ w: Double, _ h: Double) -> ECSymbol {
        var shape = SymbolShape()
        shape.symbolType = symbolType
        shape.x = x
        shape.y = y
        shape.width = w
        shape.height = h
        return SymbolPath(["shape": shape])
    }

    // upstream: export function normalizeSymbolSize(symbolSize: number | number[]): [number, number]
    public static func normalizeSymbolSize(_ symbolSize: Any) -> (Double, Double) {
        var arr: [Any]
        if !util.isArray(symbolSize) {
            // upstream: symbolSize = [+symbolSize, +symbolSize];
            arr = [symbolSize, symbolSize]
        }
        else {
            arr = symbolSize as! [Any]
        }
        // upstream: return [symbolSize[0] || 0, symbolSize[1] || 0];
        return (orZero(toNumber(arr[0])), orZero(toNumber(arr[1])))
    }

    // upstream: export function normalizeSymbolOffset(symbolOffset: SymbolOptionMixin['symbolOffset'],
    //   symbolSize: number[]): [number, number]
    public static func normalizeSymbolOffset(_ symbolOffsetIn: Any?, _ symbolSize: [Double]) -> (Double, Double)? {
        let symbolOffset = symbolOffsetIn
        if symbolOffset == nil {
            return nil
        }
        var offset: [Any]
        if !util.isArray(symbolOffset) {
            // upstream: symbolOffset = [symbolOffset, symbolOffset];
            offset = [symbolOffset!, symbolOffset!]
        }
        else {
            offset = symbolOffset as! [Any]
        }
        // upstream:
        //   return [
        //       parsePercent(symbolOffset[0], symbolSize[0]) || 0,
        //       parsePercent(retrieve2(symbolOffset[1], symbolOffset[0]), symbolSize[1]) || 0
        //   ];
        return (
            orZero(number.parsePercent(offset[0], symbolSize[0])),
            orZero(number.parsePercent(util.retrieve2(offset[1], offset[0]), symbolSize[1]))
        )
    }
}

// ---- faithful helpers ----

// JS `+value` numeric coercion (number → itself, numeric string → parsed, else NaN).
private func toNumber(_ v: Any) -> Double {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let s = v as? String { return Double(s) ?? Double.nan }
    return Double.nan
}

// JS `x || 0` for a numeric value: falsy (0 or NaN) → 0, else x.
private func orZero(_ x: Double) -> Double {
    return (x == 0 || x.isNaN) ? 0 : x
}

// JS `String.prototype.substr(start, length?)` (out-of-range → "").
private func jsSubstr(_ s: String, _ start: Int, _ length: Int? = nil) -> String {
    let chars = Array(s)
    if start >= chars.count { return "" }
    let end: Int
    if let length = length {
        end = Swift.min(start + length, chars.count)
    }
    else {
        end = chars.count
    }
    if end <= start { return "" }
    return String(chars[start..<end])
}
