import ZRenderKit
// Faithful port of zrender test/asciiWidthMap.html
//
// The html is a no-zrender utility: it measures every printable ASCII char (32–126) at
// `12px sans-serif`, computes `ratio = round(width / 12 * 100)`, builds a string of
// `String.fromCharCode(ratio + 20)`, and `document.write`s it (escaping backslashes). The output
// is the packed ASCII width-map string — the very data that powers zrender's built-in ASCII width
// table (core/platform `getWidth`).
//
// This mirrors the algorithm 1:1 using the engine's own measurement (`ZRenderKit.text.getWidth`),
// then renders the resulting map string (the analogue of `document.write`). Equal char count, same
// ratio formula, same +20 char-code packing — so the native output is the same width-map string.
extension DemoRegistry {
    static let demo_asciiWidthMap: Demo = Demo(
        name: "asciiWidthMap", category: "Text",
        summary: "ASCII (32–126) width-map string — round(width/12*100)+20 per char, like the html's document.write",
        width: 1000, height: 200
    ) { zr in
        let font = "12px sans-serif"

        // for (i = 32; i <= 126; i++): ratio = round(measureText(char).width / 12 * 100); map += charCode(ratio + 20)
        var mapStr = ""
        for code in 32...126 {
            let char = String(UnicodeScalar(code)!)
            let width = ZRenderKit.text.getWidth(char, font)
            let ratio = Int((width / 12.0 * 100.0).rounded())
            if let scalar = UnicodeScalar(ratio + 20) {
                mapStr.unicodeScalars.append(scalar)
            }
        }
        // a = mapStr.replace(/\\/g, '\\\\')
        let escaped = mapStr.replacingOccurrences(of: "\\", with: "\\\\")

        zr.add(text("ASCII width map — measureText(char).width for chars 32…126 @ 12px sans-serif:",
                    30, 24, "#333", size: 14))
        // document.write(a): the packed width-map string.
        zr.add(text(escaped, 30, 70, "#111", size: 22))
        zr.add(text("(each char = round(width/12·100)+20; this is the data behind the built-in ASCII width table)",
                    30, 120, "#999", size: 12))
    }
}
