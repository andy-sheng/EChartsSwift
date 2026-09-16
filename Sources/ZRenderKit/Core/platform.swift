// Ported from zrender/src/core/platform.ts — keep in sync with upstream
import Foundation

// upstream uses DOM `HTMLCanvasElement` / `HTMLImageElement`. There is no DOM
// in Phase 0; we keep opaque placeholder types so the seam compiles. createCanvas/loadImage
// are stubs (see below) — only the ASCII-width-table measureText fallback is functional.
public typealias CanvasLike = Any
public typealias ImageLike = Any

/// Result of `measureText` (upstream returns a `TextMetrics`-like `{ width: number }`).
public struct TextMetrics {
    public var width: Double
    public init(width: Double) {
        self.width = width
    }
}

public let DEFAULT_FONT_SIZE: Double = 12
public let DEFAULT_FONT_FAMILY: String = "sans-serif"
// upstream interpolates the numeric `${DEFAULT_FONT_SIZE}` ("12px sans-serif").
// DEFAULT_FONT_SIZE is a Double per CONVENTIONS §1; cast to Int for the px string so the
// value stays byte-identical to upstream ("12px", not "12.0px").
public let DEFAULT_FONT: String = "\(Int(DEFAULT_FONT_SIZE))px \(DEFAULT_FONT_FAMILY)"

// upstream: interface Platform
//     // TODO CanvasLike?
//     createCanvas(): HTMLCanvasElement
//     measureText(text: string, font?: string): { width: number }
//     loadImage(src, onload, onerror): HTMLImageElement
//     // Testing friendly to control frames
//     getTime(): number
public protocol PlatformAPI: AnyObject {
    func createCanvas() -> CanvasLike?
    func measureText(_ text: String, _ font: String?) -> TextMetrics
    func loadImage(
        _ src: String,
        _ onload: @escaping () -> Void,
        _ onerror: @escaping () -> Void
    ) -> ImageLike?
    // Testing friendly to control frames
    func getTime() -> Double
}

// Text width map used for environment there is no canvas
// Only common ascii is used for size concern.

// Generated from following code
//
// ctx.font = '12px sans-serif';
// const asciiRange = [32, 126];
// let mapStr = '';
// for (let i = asciiRange[0]; i <= asciiRange[1]; i++) {
//     const char = String.fromCharCode(i);
//     const width = ctx.measureText(char).width;
//     const ratio = Math.round(width / 12 * 100);
//     mapStr += String.fromCharCode(ratio + 20))
// }
// mapStr.replace(/\\/g, '\\\\');
private let OFFSET: Double = 20
private let SCALE: Double = 100
// TODO other basic fonts?
// eslint-disable-next-line
private let defaultWidthMapStr: String = "007LLmW'55;N0500LLLLLLLLLL00NNNLzWW\\\\WQb\\0FWLg\\bWb\\WQ\\WrWWQ000CL5LLFLL0LL**F*gLLLL5F0LF\\FFF5.5N"

private func getTextWidthMap(_ mapStr: String) -> [String: Double] {
    var map: [String: Double] = [:]
    // upstream guards `typeof JSON === 'undefined'` (a legacy/no-JSON runtime
    // bailout). JSON is always present in Swift; we take the available branch and drop the
    // early return.
    let codeUnits = Array(mapStr.utf16)
    for i in 0..<codeUnits.count {
        let char = String(UnicodeScalar(UInt32(i) + 32)!)
        let size = (Double(codeUnits[i]) - OFFSET) / SCALE
        map[char] = size
    }
    return map
}

public let DEFAULT_TEXT_WIDTH_MAP: [String: Double] = getTextWidthMap(defaultWidthMapStr)

// upstream: `export const platformApi: Platform = { ... }` — the mutable, injectable
// default implementation (the object literal). Realized as a final class so its identity
// is stable and `setPlatformAPI` can replace the global below.
public final class DefaultPlatformAPI: PlatformAPI {

    // measureText IIFE state (upstream closes over `_ctx` / `_cachedFont`).
    private var _ctx: Any?
    private var _cachedFont: String?

    public init() {}

    // Export methods
    public func createCanvas() -> CanvasLike? {
        // note (platform): stub. Upstream: `typeof document !== 'undefined' && document.createElement('canvas')`.
        // No DOM in this target; there is no HTMLCanvasElement equivalent, so this always returns nil
        // and measureText falls back to the ASCII width table.
        return nil
    }

    public func measureText(_ text: String, _ font: String?) -> TextMetrics {
        if _ctx == nil {
            let canvas = platformApi.createCanvas()
            // upstream `_ctx = canvas && canvas.getContext('2d')`. createCanvas is a
            // stub returning nil, so `_ctx` stays nil and we always take the fallback below.
            _ = canvas
            _ctx = nil
        }
        if _ctx != nil {
            // real 2d-context measurement (upstream caches `_cachedFont = _ctx.font`
            // then `return _ctx.measureText(text)`). Unreachable in Phase 0 since `_ctx` is nil.
            _ = _cachedFont
            return TextMetrics(width: 0)
        }
        else {
            // text = text || '' — text is a non-optional Swift String, so the `|| ''` is moot.
            let font = font ?? DEFAULT_FONT
            // Use font size if there is no other method can be used.
            // upstream: /((?:\d+)?\.?\d*)px/
            let res = firstCaptureGroup1(pattern: "((?:\\d+)?\\.?\\d*)px", in: font)
            // res && +res[1] || DEFAULT_FONT_SIZE : null/empty/0/NaN all fall back to default.
            let parsed = res.flatMap { Double($0) }
            let fontSize: Double = (parsed != nil && parsed! != 0 && !parsed!.isNaN)
                ? parsed! : DEFAULT_FONT_SIZE
            var width: Double = 0
            // upstream iterates `text.length` (UTF-16 code units) and looks up `text[i]`
            // (the i-th UTF-16 code unit). Swift `String` iterates grapheme clusters and
            // `text.count` is the grapheme count, which diverges for emoji / non-BMP. Iterate
            // `text.utf16` to match `text.length` byte-for-byte (PORT_STATUS §3 item 8).
            let utf16 = Array(text.utf16)
            if font.contains("mono") {   // is monospace
                width = fontSize * Double(utf16.count)
            }
            else {
                for i in 0..<utf16.count {
                    // Lone surrogates (non-BMP halves) are not valid scalars; like JS, they
                    // are absent from the ASCII width map, so they fall back to fontSize.
                    let preCalcWidth: Double? = UnicodeScalar(utf16[i]).flatMap {
                        DEFAULT_TEXT_WIDTH_MAP[String($0)]
                    }
                    width += preCalcWidth == nil ? fontSize : (preCalcWidth! * fontSize)
                }
            }
            return TextMetrics(width: width)
        }
    }

    public func loadImage(
        _ src: String,
        _ onload: @escaping () -> Void,
        _ onerror: @escaping () -> Void
    ) -> ImageLike? {
        // note (platform): stub. Upstream creates a DOM `new Image()`, assigns onload/onerror/src and
        // returns it. No DOM Image loader in this target; return nil.
        _ = (src, onload, onerror)
        return nil
    }

    public func getTime() -> Double {
        // Indicatively, Date.now can be executed in 13,025,305 ops/second in a certain env.
        // upstream: Date.now ? Date.now() : +(new Date()) — both are epoch milliseconds.
        return Date().timeIntervalSince1970 * 1000
    }

    // Helper mirroring the inline regex extraction in measureText.
    // NSRegularExpression replaces JS RegExp.exec; returns capture group 1 if matched.
    private func firstCaptureGroup1(pattern: String, in string: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(string.startIndex..<string.endIndex, in: string)
        guard let match = regex.firstMatch(in: string, range: range),
              match.numberOfRanges > 1,
              let groupRange = Range(match.range(at: 1), in: string) else {
            return nil
        }
        return String(string[groupRange])
    }
}

public var platformApi: PlatformAPI = DefaultPlatformAPI()

// upstream's `Partial<Platform>` — the subset of platform methods a caller wants to override.
// Each key is an optional closure; a nil closure means "leave that method untouched" (mirrors
// upstream skipping keys the partial object does not carry).
public struct PartialPlatformAPI {
    public var createCanvas: (() -> CanvasLike?)?
    public var measureText: ((String, String?) -> TextMetrics)?
    public var loadImage: ((String, @escaping () -> Void, @escaping () -> Void) -> ImageLike?)?
    public var getTime: (() -> Double)?
    public init(
        createCanvas: (() -> CanvasLike?)? = nil,
        measureText: ((String, String?) -> TextMetrics)? = nil,
        loadImage: ((String, @escaping () -> Void, @escaping () -> Void) -> ImageLike?)? = nil,
        getTime: (() -> Double)? = nil
    ) {
        self.createCanvas = createCanvas
        self.measureText = measureText
        self.loadImage = loadImage
        self.getTime = getTime
    }
}

// Wraps a base PlatformAPI, forwarding to the base for every method the partial override did
// not supply. This realizes upstream's per-key merge (`platformApi[key] = newPlatformApis[key]`
// only when the incoming key is truthy) without mutating protocol methods in place.
private final class MergedPlatformAPI: PlatformAPI {
    private let base: PlatformAPI
    private let overrides: PartialPlatformAPI
    init(base: PlatformAPI, overrides: PartialPlatformAPI) {
        self.base = base
        self.overrides = overrides
    }
    func createCanvas() -> CanvasLike? {
        // NB: createCanvas may legitimately return nil, so branch on closure presence rather
        // than `??`-ing the result (which would fall through to base on a nil override result).
        if let f = overrides.createCanvas { return f() }
        return base.createCanvas()
    }
    func measureText(_ text: String, _ font: String?) -> TextMetrics {
        if let f = overrides.measureText { return f(text, font) }
        return base.measureText(text, font)
    }
    func loadImage(
        _ src: String,
        _ onload: @escaping () -> Void,
        _ onerror: @escaping () -> Void
    ) -> ImageLike? {
        if let f = overrides.loadImage { return f(src, onload, onerror) }
        return base.loadImage(src, onload, onerror)
    }
    func getTime() -> Double {
        if let f = overrides.getTime { return f() }
        return base.getTime()
    }
}

// upstream: `setPlatformAPI(newPlatformApis: Partial<Platform>)` — the faithful per-key merge.
// Only the methods the caller supplied are overridden; every other method keeps the current
// implementation. Repeated calls stack (latest override wins, falling back through the chain).
public func setPlatformAPI(_ newPlatformApis: PartialPlatformAPI) {
    platformApi = MergedPlatformAPI(base: platformApi, overrides: newPlatformApis)
}

// Full-object replacement overload. A complete PlatformAPI provides every key, so this is the
// degenerate case of the merge above (all keys truthy → wholesale replace). Kept because Swift
// protocol objects can't be spread into a `Partial` literal like upstream's object shorthand.
public func setPlatformAPI(_ newPlatformApis: PlatformAPI) {
    platformApi = newPlatformApis
}
