// Ported from zrender/src/core/platform.ts — keep in sync with upstream
import Foundation

// PORT-TODO: upstream uses DOM `HTMLCanvasElement` / `HTMLImageElement`. There is no DOM
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
// PORT-TODO: upstream interpolates the numeric `${DEFAULT_FONT_SIZE}` ("12px sans-serif").
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
    // PORT-TODO: upstream guards `typeof JSON === 'undefined'` (a legacy/no-JSON runtime
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
        // PORT-TODO: stub. Upstream: `typeof document !== 'undefined' && document.createElement('canvas')`.
        // No DOM / no Core Graphics canvas in Phase 0 — always returns nil so measureText
        // falls back to the ASCII width table.
        return nil
    }

    public func measureText(_ text: String, _ font: String?) -> TextMetrics {
        if _ctx == nil {
            let canvas = platformApi.createCanvas()
            // PORT-TODO: upstream `_ctx = canvas && canvas.getContext('2d')`. createCanvas is a
            // stub returning nil, so `_ctx` stays nil and we always take the fallback below.
            _ = canvas
            _ctx = nil
        }
        if _ctx != nil {
            // PORT-TODO: real 2d-context measurement (upstream caches `_cachedFont = _ctx.font`
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
        // PORT-TODO: stub. Upstream creates `new Image()`, assigns onload/onerror/src and
        // returns it. No image loader wired in Phase 0; return nil.
        _ = (src, onload, onerror)
        return nil
    }

    public func getTime() -> Double {
        // Indicatively, Date.now can be executed in 13,025,305 ops/second in a certain env.
        // upstream: Date.now ? Date.now() : +(new Date()) — both are epoch milliseconds.
        return Date().timeIntervalSince1970 * 1000
    }

    // Helper mirroring the inline regex extraction in measureText.
    // PORT-TODO: NSRegularExpression replaces JS RegExp.exec; returns capture group 1 if matched.
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

public func setPlatformAPI(_ newPlatformApis: PlatformAPI) {
    // PORT-TODO: upstream takes `Partial<Platform>` and merges per-key (only assigning known,
    // truthy methods). Swift protocols cannot be partially overridden on an arbitrary type, so
    // we replace the global wholesale. Callers needing a single-method override should subclass
    // DefaultPlatformAPI / forward the methods they do not override.
    platformApi = newPlatformApis
}
