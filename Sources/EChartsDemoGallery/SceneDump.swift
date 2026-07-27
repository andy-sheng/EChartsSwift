// SceneDump.swift — structural (scene-graph) oracle: dump the z-sorted display list from BOTH the
// native port and real echarts.js as the SAME canonical JSON, so a divergence is reported as a
// NAMED PROPERTY ("sector.r0 380 vs 340") instead of "3.7% of pixels differ".
//
// WHY THIS EXISTS. The PNG oracle (--compare) and the frame-series oracle (--anim-native/--anim-web)
// both compare RASTER output, which conflates three unrelated things: real behaviour divergence,
// text-rasterisation noise, and (for animation) startup-timing skew. --anim-invariant's own header
// records the consequence: a genuine gauge "reset on refresh" bug scored ~1 while a correctly-synced
// morph scored ~27 — the signal was inverted. Raster also cannot see anything that does not paint:
// z-order, `silent`, `ignore`, `invisible`, or a state that is present but unapplied.
//
// The enabling fact is that the port is faithful at the zrender layer: `Storage.getDisplayList`
// exists on both sides with the SAME signature (Sources/ZRenderKit/Storage.swift:70 vs
// upstream/echarts/dist/echarts.js:2964), and the `type` strings match verbatim ("rect", "sector",
// "text", "path"). So one serializer shape covers both.
//
// SCOPE OF THIS PROTOTYPE: frame 0 only, animation forced OFF on both sides (the settled frame — the
// only well-defined instant without a shared clock). Making frames 1..N comparable needs the virtual
// clock; the injection point is the free function `getTime()` at ZRenderKit/Animation/Animation.swift:21.

import Foundation
import WebKit
import ZRenderKit
import EChartsKit
import EChartsDemoCore

// MARK: - Canonicalisation

/// Round to 3dp so float noise (both sides do the same trig in double precision, but not in the
/// same order) does not masquerade as divergence. Non-finite values are preserved AS non-finite —
/// a NaN on one side and a number on the other is exactly the kind of bug this tool is for.
private func canonNum(_ d: Double) -> Any {
    if d.isNaN { return "NaN" }
    if d.isInfinite { return d > 0 ? "Infinity" : "-Infinity" }
    let r = (d * 1000).rounded() / 1000
    return r == 0 ? 0.0 : r    // normalise -0
}

/// Reduce one Swift value to a JSON scalar comparable with its JS counterpart.
/// Optionals unwrap; single-payload enums (ZRColor.string, RectRadius.number, LineDash.values …)
/// unwrap to their payload, which is what the JS side stores directly. Enums with no payload
/// degrade to their case name ("solid"), which is again what JS stores.
private func canonValue(_ v: Any) -> Any? {
    let m = Mirror(reflecting: v)
    if m.displayStyle == .optional {
        guard let inner = m.children.first?.value else { return nil }
        return canonValue(inner)
    }
    switch v {
    case let d as Double:  return canonNum(d)
    case let f as CGFloat: return canonNum(Double(f))
    case let i as Int:     return canonNum(Double(i))
    case let s as String:  return s
    case let b as Bool:    return b
    case let a as [Double]: return a.map { canonNum($0) }
    default: break
    }
    if m.displayStyle == .enum {
        if let payload = m.children.first?.value {
            // A gradient/pattern fill is a nested object on both sides; collapse it to a tag rather
            // than pretending to compare it — an honest "not compared" beats a false match.
            if let s = canonValue(payload) { return s }
            return "<\(String(describing: v).prefix(24))>"
        }
        return String(describing: v)
    }
    return nil
}

/// Enumerate a struct's stored properties as a JSON bag. Deliberately NOT `PathShape.animationProps()`
/// (Path.swift:345): that one filters to fields the shape claims through `animationGet`, so shapes
/// with no keyed accessor return an EMPTY bag — which would silently report "no shape difference"
/// on exactly the shapes nobody wired for animation.
private func canonBag(_ any: Any?) -> [String: Any] {
    guard let any = any else { return [:] }
    var out: [String: Any] = [:]
    for child in Mirror(reflecting: any).children {
        guard let key = child.label, !key.hasPrefix("_") else { continue }
        if let v = canonValue(child.value) { out[key] = v }
    }
    return out
}

// MARK: - Native dump

/// The style bag differs by concrete class: Path flattens CommonStyleProps into its own `pathStyle`
/// (see the STYLE DECISION note at Path.swift:40), ZRText uses `textStyle`, etc.
private func nativeStyleBag(_ el: Displayable) -> [String: Any] {
    if let p = el as? Path      { return canonBag(p.pathStyle) }
    if let t = el as? ZRText    { return canonBag(t.textStyle) }
    if let s = el as? TSpan     { return canonBag(s.tspanStyle) }
    if let i = el as? ZRImage   { return canonBag(i.imageStyle) }
    return canonBag(el.style)
}

@MainActor
func sceneDumpNative(_ demo: EChartsDemo) -> String? {
    var opt = demo.option
    opt["animation"] = false          // same contract as the web page's `snapshot: true`
    let ec = ECharts(width: demo.width, height: demo.height)
    ec.setOption(opt)

    // includeIgnore: true — an element the port wrongly marks `ignore` is precisely a bug we want
    // reported, and dropping it here would instead show up as a confusing count mismatch.
    let list = ec.storage.getDisplayList(true, true)

    var out: [[String: Any]] = []
    for (i, el) in list.enumerated() {
        var rec: [String: Any] = [
            "i": i,
            "type": el.type,
            "name": el.name,
            "z": canonNum(el.z), "z2": canonNum(el.z2), "zlevel": canonNum(el.zlevel),
            "ignore": el.ignore, "invisible": el.invisible, "silent": el.silent,
            "x": canonNum(el.x), "y": canonNum(el.y),
            "scaleX": canonNum(el.scaleX), "scaleY": canonNum(el.scaleY),
            "rotation": canonNum(el.rotation),
            "style": nativeStyleBag(el),
        ]
        if let p = el as? Path { rec["shape"] = canonBag(p.shape) }
        if let t = el as? ZRText { rec["text"] = t.textStyle?.text ?? "" }
        out.append(rec)
    }
    guard let data = try? JSONSerialization.data(withJSONObject: out, options: [.sortedKeys]) else { return nil }
    return String(data: data, encoding: .utf8)
}

// MARK: - Web dump

/// The mirror image of `sceneDumpNative`, evaluated inside the page that already hosts real
/// echarts.js (WebPage.swift puts `myChart` in global scope).
///
/// NOTE on `for (var k in o)` WITHOUT hasOwnProperty: zrender style objects are built by
/// `createObject(DEFAULT_PATH_STYLE, props)` (echarts.js:742) — Object.create, so the defaults live
/// on the PROTOTYPE. Filtering to own properties would drop every defaulted field and make the JS
/// bag artificially sparse against the Swift struct, which materialises all of its fields.
let sceneDumpJS = """
(function () {
  var zr = myChart.getZr();
  var list = zr.storage.getDisplayList(true, true);
  function num(d) {
    if (typeof d !== 'number') return d;
    if (isNaN(d)) return 'NaN';
    if (!isFinite(d)) return d > 0 ? 'Infinity' : '-Infinity';
    var r = Math.round(d * 1000) / 1000;
    return r === 0 ? 0 : r;
  }
  function bag(o) {
    var r = {};
    if (!o || typeof o !== 'object') return r;
    for (var k in o) {
      if (k.charAt(0) === '_') continue;
      var v = o[k];
      if (v == null) continue;
      var t = typeof v;
      if (t === 'number') r[k] = num(v);
      else if (t === 'string' || t === 'boolean') r[k] = v;
      else if (Object.prototype.toString.call(v) === '[object Array]') {
        var allNum = true;
        for (var j = 0; j < v.length; j++) { if (typeof v[j] !== 'number') { allNum = false; break; } }
        if (allNum) r[k] = v.map(num);
      }
    }
    return r;
  }
  var out = [];
  for (var i = 0; i < list.length; i++) {
    var el = list[i];
    var rec = {
      i: i, type: el.type, name: el.name || '',
      z: num(el.z || 0), z2: num(el.z2 || 0), zlevel: num(el.zlevel || 0),
      ignore: !!el.ignore, invisible: !!el.invisible, silent: !!el.silent,
      x: num(el.x || 0), y: num(el.y || 0),
      scaleX: num(el.scaleX == null ? 1 : el.scaleX),
      scaleY: num(el.scaleY == null ? 1 : el.scaleY),
      rotation: num(el.rotation || 0),
      style: bag(el.style)
    };
    if (el.shape) rec.shape = bag(el.shape);
    if (el.type === 'text') rec.text = (el.style && el.style.text) || '';
    out.push(rec);
  }
  return JSON.stringify(out);
})()
"""

/// Loads the real-echarts page, waits the same settle delay `WebSnapper` uses, then evaluates
/// `js` and writes the result.
///
/// `js` defaults to `sceneDumpJS`; passing an arbitrary script (via `--eval-web`) turns this into a
/// general probe of the reference implementation, which is what you want the moment a scene diff
/// raises a question the TS source does not answer on its own ("where does this z2 come from?").
final class WebSceneDumper: NSObject, WKNavigationDelegate {
    let out: URL
    let js: String
    init(out: URL, js: String = sceneDumpJS) { self.out = out; self.js = js }
    func webView(_ wv: WKWebView, didFinish nav: WKNavigation!) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            wv.evaluateJavaScript(self.js) { result, err in
                defer { exit(err == nil ? 0 : 1) }
                if let err = err {
                    FileHandle.standardError.write(Data("scene dump JS failed: \(err)\n".utf8)); return
                }
                guard let json = result as? String else {
                    FileHandle.standardError.write(Data("scene dump returned non-string\n".utf8)); return
                }
                try? json.write(to: self.out, atomically: true, encoding: .utf8)
                print("wrote \(self.out.path) (\(json.count) bytes)")
            }
        }
    }
    func webView(_ wv: WKWebView, didFail nav: WKNavigation!, withError e: Error) {
        FileHandle.standardError.write(Data("web load failed: \(e)\n".utf8)); exit(1)
    }
}
