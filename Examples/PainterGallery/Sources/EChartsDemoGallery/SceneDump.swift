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

/// `action` is an optional dispatchAction payload (`{"type":"legendToggleSelect","name":"Email"}`)
/// applied AFTER the initial render, so the dump captures the post-interaction state. This is how an
/// interaction bug becomes comparable: the same payload goes to both implementations, and the diff
/// is of the resulting scene, not of two screenshots taken at whatever moment each settled.
@MainActor
func sceneDumpNative(_ demo: EChartsDemo, action: [String: Any]? = nil) -> String? {
    var opt = demo.option
    opt["animation"] = false          // same contract as the web page's `snapshot: true`
    let ec = ECharts(width: demo.width, height: demo.height)
    ec.setOption(opt)

    if let action = action, let type = action["type"] as? String {
        var payload = Payload(type: type)
        for (k, v) in action where k != "type" { payload.other[k] = v }
        ec.dispatchAction(payload)
    }

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

// MARK: - Reachable-action derivation
//
// The frame-0 scene diff only ever compares the INITIAL render, so a bug that appears only after the
// user touches something is invisible to it — which is exactly how "click the legend and the data
// goes wrong" survived a 0.12% pixel score AND a clean structural diff on the same demo.
//
// The fix is to make the interaction states part of the default corpus rather than a later phase.
// Interaction稳态 diffing needs no virtual clock: dispatch the payload, let it settle, compare
// structure. Only mid-ANIMATION frames need the clock.
//
// v1 derives legend actions, because that is the reported failure class and because legend items are
// exactly the set of user-reachable toggles the chart declares about itself. Derivation runs against
// the real ported LegendModel (not a re-implementation of legend collection), and the resulting names
// are written to a manifest that BOTH sweeps consume, so the two sides always receive byte-identical
// payloads — a divergence is then necessarily in the response, never in the stimulus.

@MainActor
func deriveLegendActions(_ demo: EChartsDemo, max: Int) -> [[String: Any]] {
    var opt = demo.option
    opt["animation"] = false
    let ec = ECharts(width: demo.width, height: demo.height)
    ec.setOption(opt)
    guard let ecModel = ec.getModel() else { return [] }

    var out: [[String: Any]] = []

    // Legend toggles — the chart's own declaration of what the user can switch off.
    var names: [String] = []
    var seen = Set<String>()
    for cmpt in ecModel.findComponents(QueryConditionKindA(mainType: "legend")) {
        guard let legend = cmpt as? LegendModel else { continue }
        for item in legend.getData() {
            guard let n = model.convertOptionIdName(item.get("name", true), nil), !n.isEmpty else { continue }
            if seen.insert(n).inserted { names.append(n) }
        }
    }
    out += names.prefix(max).map { ["type": "legendToggleSelect", "name": $0] }

    // dataZoom — one representative window change. The handler consumes `start`/`end` percentages
    // (dataZoomAction.swift:45-46) and, with no index in the payload, targets every dataZoom, which is
    // the same resolution real echarts applies to the identical payload — the comparison stays
    // like-for-like even where the semantics are subtle.
    if !ecModel.findComponents(QueryConditionKindA(mainType: "dataZoom")).isEmpty {
        out.append(["type": "dataZoom", "start": 25.0, "end": 75.0])
    }

    // timeline — step to the second frame. `timelineChange` runs the heavyweight prepareAndUpdate
    // path (setOption-per-frame merge), which is exactly the machinery worth sweeping.
    for cmpt in ecModel.findComponents(QueryConditionKindA(mainType: "timeline")) {
        guard let tl = cmpt as? TimelineModel else { continue }
        if tl.getData().count() > 1 {
            out.append(["type": "timelineChange", "currentIndex": 1.0])
        }
        break
    }
    return out
}

// MARK: - Animation probe
//
// "Click the legend and nothing animates" is invisible to BOTH existing oracles: the structural diff
// compares settled states, and the pixel oracle compares one frame. Yet it is a whole bug CLASS in
// this port — `updateProps(el, ["shape": <a PathShape STRUCT>])` silently creates no animator at all,
// because a Swift struct is not `util.isObject` and the animator takes it as one discrete leaf
// (see `PathShape.animationProps()`, ZRenderKit/Graphic/Path.swift). Chord ribbons hit exactly that
// while the node arcs, which pass a dict, tweened — so the chart half-animated and nobody noticed.
//
// The probe asks one question per demo: after an update that DEMONSTRABLY changes the scene, did any
// element get an animator? "Changed" is established on a separate animation-OFF instance, because on
// the animated instance the post-update scene still sits at its pre-update values until the clock runs.

struct AnimProbeResult {
    let demo: String
    let sceneChanged: Bool
    let initialTotal: Int
    let initialAnimated: Int
    let total: Int
    let animated: Int
}

/// Compact canonical signature of the settled scene — enough to detect "did this update change anything".
@MainActor
func sceneSignature(_ view: EChartsView) -> String {
    let ec = view.ec
    var parts: [String] = []
    for el in ec.storage.getDisplayList(true, true) {
        var s = "\(el.type)|\(canonNum(el.x))|\(canonNum(el.y))|\(canonNum(el.z2))"
        if let p = el as? Path, let shape = p.shape {
            for (k, v) in canonBag(shape).sorted(by: { $0.key < $1.key }) { s += "|\(k)=\(v)" }
        }
        parts.append(s)
    }
    return parts.joined(separator: "\n")
}

@MainActor
func animProbe(_ demo: EChartsDemo, action: [String: Any]?) -> AnimProbeResult {
    // MUST be an EChartsView, not a bare ECharts: `animateOrSetProps` settles a LEAVE synchronously
    // when `el.__zr == nil` (basicTransition.swift's documented headless adaptation — without a zr
    // nothing ticks the animator, so its done-callback would never detach the element). A bare
    // ECharts therefore reports every fade-out as "no animator", which is a property of the harness,
    // not of the port.
    func build(_ animation: Bool) -> EChartsView {
        var opt = demo.option
        // The live side must preserve an example's explicit `animation: false`; the Web oracle runs
        // that option verbatim. Only the synthetic settled side forces animation off.
        if !animation { opt["animation"] = false }
        let v = EChartsView(width: demo.width, height: demo.height)
        v.setOption(opt)
        _ = v.zr.storage.getDisplayList(true)
        return v
    }
    func applyUpdate(_ view: EChartsView, animation: Bool) {
        let ec = view.ec
        if let action = action, let type = action["type"] as? String {
            var payload = Payload(type: type)
            for (k, v) in action where k != "type" { payload.other[k] = v }
            ec.dispatchAction(payload)
        } else {
            // No derived action: re-apply the demo's own option in merge mode, upstream's refresh idiom
            // (the same stimulus --update-invariant uses).
            //
            // The `animation` stamp must MATCH the instance being updated — a merge carrying the demo's
            // own `animation: true` would otherwise switch the still instance back on. An earlier version
            // hard-coded `false` in this branch regardless of instance, i.e. it turned animation off and
            // then asked why nothing animated, reporting all 19 no-action demos (every tree demo among
            // them) as zero-animator false positives.
            var opt = demo.option
            if !animation { opt["animation"] = false }
            ec.setOption(opt, notMerge: false)
        }
    }

    // Did the update change the settled scene at all? Decided WITHOUT animation, so the comparison is
    // between two settled states rather than between a settled state and a mid-flight one.
    let still = build(false)
    let before = sceneSignature(still)
    applyUpdate(still, animation: false)
    let changed = sceneSignature(still) != before

    // Now the same update with animation on: how much of the scene is actually tweening?
    let live = build(true)
    var initialTotal = 0, initialAnimated = 0
    _ = live.ec.getRoot().traverse { el in
        initialTotal += 1
        if !el.animators.isEmpty { initialAnimated += 1 }
        return false
    }
    applyUpdate(live, animation: true)
    var total = 0, animated = 0
    _ = live.ec.getRoot().traverse { el in
        total += 1
        if !el.animators.isEmpty { animated += 1 }
        return false
    }
    return AnimProbeResult(
        demo: demo.name,
        sceneChanged: changed,
        initialTotal: initialTotal,
        initialAnimated: initialAnimated,
        total: total,
        animated: animated
    )
}

/// Verbose single-demo form of `animProbe`: breaks the scene down by element class so a zero-animator
/// report can be read as "which parts of this chart are static", and reports whether the stimulus
/// actually did anything.
@MainActor
func animProbeVerbose(_ demo: EChartsDemo, action: [String: Any]?) {
    // MUST be an EChartsView, not a bare ECharts: `animateOrSetProps` settles a LEAVE synchronously
    // when `el.__zr == nil` (basicTransition.swift's documented headless adaptation — without a zr
    // nothing ticks the animator, so its done-callback would never detach the element). A bare
    // ECharts therefore reports every fade-out as "no animator", which is a property of the harness,
    // not of the port.
    func build(_ animation: Bool) -> EChartsView {
        var opt = demo.option
        if !animation { opt["animation"] = false }
        let v = EChartsView(width: demo.width, height: demo.height)
        v.setOption(opt)
        _ = v.zr.storage.getDisplayList(true)
        return v
    }
    func apply(_ view: EChartsView, _ animation: Bool) {
        let ec = view.ec
        if let action = action, let type = action["type"] as? String {
            var payload = Payload(type: type)
            for (k, v) in action where k != "type" { payload.other[k] = v }
            ec.dispatchAction(payload)
        } else {
            var opt = demo.option
            if !animation { opt["animation"] = false }
            ec.setOption(opt, notMerge: false)
        }
    }
    func breakdown(_ view: EChartsView) -> String {
        let ec = view.ec
        var byType: [String: (Int, Int)] = [:]
        _ = ec.getRoot().traverse { el in
            let t = String(describing: type(of: el))
            var e = byType[t] ?? (0, 0); e.0 += 1
            if !el.animators.isEmpty { e.1 += 1 }
            byType[t] = e
            return false
        }
        return byType.sorted { $0.key < $1.key }
            .map { "\($0.key):\($0.value.0)/\($0.value.1)" }.joined(separator: " ")
    }

    let still = build(false)
    let before = sceneSignature(still)
    apply(still, false)
    let after = sceneSignature(still)
    print("demo: \(demo.name)")
    print("action: \(action.map { "\($0)" } ?? "(re-apply option)")")
    print("sceneChanged: \(after != before)   (signature \(before.count) -> \(after.count) chars)")

    let live = build(true)
    live.ec.getModel()?.eachSeries { series, _ in
        let own = String(describing: series.getShallow("animation", true))
        let resolved = String(describing: series.getShallow("animation"))
        let enabled = String(describing: series.isAnimationEnabled())
        let threshold = String(describing: series.getShallow("animationThreshold"))
        print("series[\(series.seriesIndex)] \(series.subType) animationOwn=\(own) animationResolved=\(resolved) enabled=\(enabled) count=\(series.getData().count()) threshold=\(threshold)")
    }
    print("live  before: \(breakdown(live))")
    apply(live, true)
    print("live  after : \(breakdown(live))    [class:total/animated]")
}

// MARK: - Animation probe, web side
//
// The native-only probe asks "did anything animate?" — but that is not a verdict on its own, because
// upstream does NOT animate every update either. When a legend click hides a series entirely,
// `echarts.ts:1756` removes the whole view group synchronously (`zr.remove(view.group)`) with no fade,
// so a native zero here is FAITHFUL. Judging the port against an absolute "should animate" would have
// turned faithful behaviour into a 23-item bug list.
//
// So the probe is comparative, like the scene diff: run the same stimulus on real echarts.js and count
// elements carrying animators there too. Animators are created synchronously inside dispatchAction /
// setOption on both sides, so sampling immediately after the call is like-for-like without needing a
// shared clock.
let animProbeJS = """
(function () {
  function count() {
    var zr = myChart.getZr();
    var total = 0, animated = 0, byType = {};
    function walk(el) {
      total++;
      var t = el.type || 'el';
      byType[t] = byType[t] || [0, 0];
      byType[t][0]++;
      if (el.animators && el.animators.length) { animated++; byType[t][1]++; }
      if (el.isGroup) { var c = el.childrenRef(); for (var i = 0; i < c.length; i++) walk(c[i]); }
    }
    var roots = zr.storage._roots || [];
    for (var i = 0; i < roots.length; i++) walk(roots[i]);
    return { total: total, animated: animated, byType: byType };
  }
  // `didFinish` is deliberately delayed so async demo setup can settle, which means a short
  // 300ms entrance animation may already be over. Recreate the current chart synchronously and
  // census it immediately after setOption; this is the same phase as the Native probe and avoids
  // classifying animation duration as an implementation mismatch.
  var replayOption = myChart.getOption();
  myChart.clear();
  myChart.setOption(replayOption, true);
  var before = count();
  if (window.__SCENE_ACTION__) {
    myChart.dispatchAction(window.__SCENE_ACTION__);
  } else {
    // Re-apply the chart's OWN current option (upstream's refresh idiom). Using getOption() rather
    // than a serialized copy of the Swift option: several demo options hold non-JSON Swift values,
    // and this is also a closer analogue of the native side re-applying `demo.option`.
    myChart.setOption(myChart.getOption(), false);
  }
  var after = count();
  return JSON.stringify({ before: before, after: after });
})()
"""

/// Web side of the animation probe: one page load per demo, action dispatched, animator census taken.
/// Deliberately NOT the `snapshot: true` page — that one forces `animation: false`, which is exactly
/// the thing under measurement.
final class WebAnimProber: NSObject, WKNavigationDelegate {
    private let jobs: [SweepJob]
    private var idx = 0
    private let wv: WKWebView
    private let out: URL
    private let outHandle: FileHandle
    private var loadGeneration = 0

    init(jobs: [SweepJob], wv: WKWebView, out: URL) {
        self.wv = wv
        self.out = out

        var done = Set<String>()
        if let existing = try? String(contentsOf: out, encoding: .utf8) {
            for line in existing.split(separator: "\n").dropFirst() {
                if let name = line.split(separator: "\t").first { done.insert(String(name)) }
            }
        } else {
            try? "demo\tinitialTotal\tinitialAnimated\tupdateTotal\tupdateAnimated\n"
                .write(to: out, atomically: true, encoding: .utf8)
        }
        self.jobs = jobs.filter { !done.contains($0.demo.name) }
        self.outHandle = try! FileHandle(forWritingTo: out)
        self.outHandle.seekToEndOfFile()
        super.init()
    }

    func start() { loadCurrent() }

    private func finish() {
        try? outHandle.close()
        print("anim-probe-web done: \(idx)/\(jobs.count) -> \(out.path)")
        exit(0)
    }

    private func append(_ row: String) {
        outHandle.write(Data((row + "\n").utf8))
        try? outHandle.synchronize()
        FileHandle.standardOutput.write(Data((row + "\n").utf8))
    }

    private func loadCurrent() {
        guard idx < jobs.count else { return finish() }
        let job = jobs[idx]
        guard let page = echartsHTMLPage(job.demo, snapshot: false) else {
            append("\(job.demo.name)\tERR\tERR\tERR\tERR"); idx += 1; loadCurrent(); return
        }
        loadGeneration += 1
        let generation = loadGeneration
        wv.frame = CGRect(x: 0, y: 0, width: job.demo.width, height: job.demo.height)
        wv.loadHTMLString(page, baseURL: nil)
        // A single malformed/heavy example must not stall the 400+ case sweep forever. The row is
        // persisted immediately, so the command is both observable and safely resumable.
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in
            guard let self, self.loadGeneration == generation, self.idx < self.jobs.count else { return }
            self.append("\(self.jobs[self.idx].demo.name)\tTIMEOUT\tTIMEOUT\tTIMEOUT\tTIMEOUT")
            self.wv.stopLoading()
            self.idx += 1
            self.loadCurrent()
        }
    }

    func webView(_ wv: WKWebView, didFinish nav: WKNavigation!) {
        let job = jobs[idx]
        let generation = loadGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            guard generation == self.loadGeneration, self.idx < self.jobs.count else { return }
            var prelude = ""
            if let a = job.actionJSON { prelude += "window.__SCENE_ACTION__ = \(a);\n" }
            wv.evaluateJavaScript(prelude + animProbeJS) { result, err in
                guard generation == self.loadGeneration, self.idx < self.jobs.count else { return }
                if let json = result as? String,
                   let obj = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any],
                   let after = obj["after"] as? [String: Any], let before = obj["before"] as? [String: Any] {
                    self.append("\(job.demo.name)\t\(before["total"] ?? -1)\t\(before["animated"] ?? -1)\t\(after["total"] ?? -1)\t\(after["animated"] ?? -1)")
                } else {
                    self.append("\(job.demo.name)\tERR\tERR\tERR\t\(err.map { "\($0)" } ?? "")")
                }
                self.idx += 1
                self.loadCurrent()
            }
        }
    }

    func webView(_ wv: WKWebView, didFail nav: WKNavigation!, withError e: Error) {
        append("\(jobs[idx].demo.name)\tERR\tERR\tERR\tload"); idx += 1; loadCurrent()
    }
    func webView(_ wv: WKWebView, didFailProvisionalNavigation nav: WKNavigation!, withError e: Error) {
        append("\(jobs[idx].demo.name)\tERR\tERR\tERR\tprov"); idx += 1; loadCurrent()
    }
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
  if (window.__SCENE_ACTION__) { myChart.dispatchAction(window.__SCENE_ACTION__); }
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
    let actionJSON: String?
    init(out: URL, js: String = sceneDumpJS, actionJSON: String? = nil) {
        self.out = out; self.js = js; self.actionJSON = actionJSON
    }
    func webView(_ wv: WKWebView, didFinish nav: WKNavigation!) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            let prelude = self.actionJSON.map { "window.__SCENE_ACTION__ = \($0);\n" } ?? ""
            wv.evaluateJavaScript(prelude + self.js) { result, err in
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

// MARK: - Batch sweep (web side)

/// One sweep job: a demo, an optional action, and where its dump goes.
struct SweepJob {
    let demo: EChartsDemo
    let actionJSON: String?     // nil = the base (no-interaction) state
    let out: URL
    let label: String
}

/// Drives the whole corpus through ONE process: load page -> settle -> dump -> next.
///
/// A fresh page load per (demo, action) rather than dispatching several actions into one page: the
/// alternative is to undo each action with its inverse, which assumes the undo is faithful — and on a
/// port being tested for exactly that kind of fidelity, a bad undo would silently poison every later
/// variant of the same demo. Reloading costs wall-clock and buys unambiguous results.
final class WebSweeper: NSObject, WKNavigationDelegate {
    private let jobs: [SweepJob]
    private var idx = 0
    private let wv: WKWebView
    private var failures: [String] = []

    init(jobs: [SweepJob], wv: WKWebView) { self.jobs = jobs; self.wv = wv }

    func start() { loadCurrent() }

    private func loadCurrent() {
        guard idx < jobs.count else {
            print("sweep-web done: \(jobs.count - failures.count)/\(jobs.count) ok, \(failures.count) failed")
            for f in failures.prefix(20) { print("  FAILED \(f)") }
            exit(0)
        }
        let job = jobs[idx]
        guard let page = echartsHTMLPage(job.demo, snapshot: true) else {
            failures.append("\(job.label) (no html)"); idx += 1; loadCurrent(); return
        }
        wv.frame = CGRect(x: 0, y: 0, width: job.demo.width, height: job.demo.height)
        wv.loadHTMLString(page, baseURL: nil)
    }

    func webView(_ wv: WKWebView, didFinish nav: WKNavigation!) {
        let job = jobs[idx]
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            let prelude = job.actionJSON.map { "window.__SCENE_ACTION__ = \($0);\n" } ?? ""
            wv.evaluateJavaScript(prelude + sceneDumpJS) { result, err in
                if let json = result as? String {
                    try? json.write(to: job.out, atomically: true, encoding: .utf8)
                } else {
                    self.failures.append("\(job.label): \(err.map { "\($0)" } ?? "non-string result")")
                }
                if (self.idx + 1) % 25 == 0 { print("  … \(self.idx + 1)/\(self.jobs.count)") }
                self.idx += 1
                self.loadCurrent()
            }
        }
    }

    func webView(_ wv: WKWebView, didFail nav: WKNavigation!, withError e: Error) {
        failures.append("\(jobs[idx].label): load \(e)")
        idx += 1; loadCurrent()
    }

    func webView(_ wv: WKWebView, didFailProvisionalNavigation nav: WKNavigation!, withError e: Error) {
        failures.append("\(jobs[idx].label): provisional \(e)")
        idx += 1; loadCurrent()
    }
}

/// Shared naming so the two sweeps land on filenames the report script can pair up.
/// slot 0 is the base state; slot N>0 is the Nth derived action.
func sweepFileName(_ demo: String, slot: Int, side: String) -> String {
    "\(demo)##\(slot).\(side).json"
}
