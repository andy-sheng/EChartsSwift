// WebPage.swift — the shared "real echarts.js" reference pane, used by BOTH galleries
// (macOS EChartsDemoGallery and iOS EChartsDemoGalleryiOS).

import Foundation

// ---------------------------------------------------------------------------
// upstream echarts UMD dist (the REAL echarts 6.1.0), baked in via #filePath — the same trick
// DemoGallery uses for the zrender test dir. WebPage.swift lives at <repo>/Sources/EChartsDemoCore/.
// On iOS this only resolves in the SIMULATOR (which shares the host filesystem); the staged .app is
// a local dev/test artifact either way, exactly like the macOS one.
// ---------------------------------------------------------------------------
public enum Upstream {
    public static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // EChartsDemoCore
        .deletingLastPathComponent()   // Sources
        .deletingLastPathComponent()   // repo root
    public static let echartsDistJS = repoRoot.appendingPathComponent("upstream/echarts/dist/echarts.js")
}

// ---------------------------------------------------------------------------
// HTML render: the SAME option fed to the REAL echarts in a self-contained page (dist inlined).
// ---------------------------------------------------------------------------

/// A self-contained page: inline the echarts UMD bundle (global `echarts`), a `#main` div at the
/// demo's logical size, and the demo's option applied to a real chart.
///
/// THE PAGE IS THE OFFICIAL EDITOR'S CONTRACT, not a wrapper of our own invention. The editor puts
/// `myChart` (and an `app` config bag) in scope and then runs the example's code; the example either
/// just assigns `option` — the common case, which the harness then applies — or drives `myChart`
/// itself. 87 of the ~300 official examples do the latter: they `setInterval` a `setOption`,
/// `dispatchAction` a highlight, listen with `myChart.on(...)`, or read `myChart.convertToPixel`.
/// A page that hides `myChart` forces those examples to be gutted before they run, which would make
/// the reference pane a strawman on exactly the cases the port is most likely to get wrong. So:
/// declare `myChart` FIRST, run the example verbatim, and only apply `option` if the example did not
/// already apply one itself (doing both would clobber the state it set up).
///
/// `snapshot: true` is for the headless PNG paths (`--web-snapshot` / `--compare`), which need one
/// deterministic frame: animation is forced off on whatever gets applied, and `setInterval` is
/// neutered so a repeating example cannot race the snapshot. (`setTimeout` is left real — echarts
/// uses it internally for throttling and lazy update; stubbing it would break rendering.) The live
/// gallery pane passes `false` and gets the example as the website runs it.
///
/// The viewport meta pins the layout viewport to the demo's logical width so the fixed-size div
/// scales to fill the WKWebView on iOS (without it, iOS assumes a 980px viewport and the chart
/// renders tiny). macOS WKWebView ignores viewport metas, so the mac pane is unaffected.
public func echartsHTMLPage(
    _ demo: EChartsDemo,
    snapshot: Bool = false,
    freezeEntranceAnimation: Bool = false,
    captureIntervals: Bool = false
) -> String? {
    guard let dist = try? String(contentsOf: Upstream.echartsDistJS, encoding: .utf8) else { return nil }
    // The example script: either the official example's verbatim JS (which may drive `myChart` and
    // schedule timers), or — for the port-tab demos, which have no JS — the serialized Swift option.
    let exampleScript: String
    if let js = demo.webOptionJS {
        exampleScript = js
    } else {
        guard let optionData = try? JSONSerialization.data(withJSONObject: demo.option, options: []),
              let optionJSON = String(data: optionData, encoding: .utf8) else { return nil }
        exampleScript = "option = \(optionJSON);"
    }
    // Guard against a stray `</script>` inside the bundle closing the tag early.
    let safeDist = dist.replacingOccurrences(of: "</script", with: "<\\/script")

    // Inject `echarts.registerMap(name, data)` for every map this demo registers, BEFORE setOption —
    // real echarts renders a `map`/`geo` series blank otherwise (no map is registered by the option
    // alone; the native pane registers via ECharts.registerMap, which never reaches the page).
    // Each value is a GeoJSON dict or `{ svg: "<string>" }`; both are valid registerMap payloads.
    var registerJS = ""
    for (mapName, mapData) in demo.mapRegistrations {
        guard let d = try? JSONSerialization.data(withJSONObject: mapData, options: []),
              let json = String(data: d, encoding: .utf8),
              let nd = try? JSONSerialization.data(withJSONObject: [mapName], options: []),
              let nameJSON = String(data: nd, encoding: .utf8) else { continue }
        // nameJSON is `["toy"]`; slice off the brackets to get the quoted, escaped string literal.
        let quotedName = String(nameJSON.dropFirst().dropLast())
        registerJS += "      echarts.registerMap(\(quotedName), \(json));\n"
    }

    return """
    <!DOCTYPE html><html><head><meta charset="utf-8">
    <meta name="viewport" content="width=\(Int(demo.width))">
    <script>\(safeDist)</script>
    </head><body style="margin:0;background:#fff">
    <div id="main" style="width:\(Int(demo.width))px;height:\(Int(demo.height))px"></div>
    <script>
    \(registerJS)
      // What the official editor puts in scope before an example runs.
      var myChart = echarts.init(document.getElementById('main'), null, { renderer: 'canvas' });
      var option;
      var app = {};            // the editor's live-config bag; examples assign app.config/app.configParameters

      var __applied = false;   // did the example apply an option itself?
      var __snapshot = \(snapshot);
      var __freezeEntranceAnimation = \(freezeEntranceAnimation);
      var __captureIntervals = \(captureIntervals);
      window.__capturedIntervals = [];
      window.__entranceStage = 'page-script';
      window.__entranceError = '';
      window.addEventListener('error', function (event) {
        window.__entranceError = event.error && event.error.stack
          ? String(event.error.stack)
          : String(event.message || event.error || 'unknown error');
      });
      // Deterministic entrance-frame oracle: stop the real RAF clock before setOption creates any
      // animators. The validation driver advances their clips explicitly after the page is loaded.
      if (__freezeEntranceAnimation) { myChart.getZr().animation.stop(); }
      var __setOption = myChart.setOption.bind(myChart);
      myChart.setOption = function (opt, a, b) {
        __applied = true;
        if (__snapshot && opt && typeof opt === 'object') { opt.animation = false; }
        var result = __setOption(opt, a, b);
        // A zero-delay example may call setOption after the page's main script returns. Creating its
        // animators wakes zrender again, so park RAF immediately inside the wrapper as well.
        if (__freezeEntranceAnimation) { myChart.getZr().animation.stop(); }
        return result;
      };
      var __dispatchAction = myChart.dispatchAction.bind(myChart);
      myChart.dispatchAction = function (payload, opt) {
        var result = __dispatchAction(payload, opt);
        // Initial actions can wake zrender just like setOption. Their semantic result may need to
        // settle before clip collection, but their animation clock must remain parked meanwhile.
        if (__freezeEntranceAnimation) { myChart.getZr().animation.stop(); }
        return result;
      };
      if (__captureIntervals) {
        // Deterministic interaction captures advance demo-owned repeating callbacks explicitly.
        // This avoids depending on throttled WKWebView wall-clock/RAF behaviour while still running
        // the official callback body and its real setOption/dispatchAction calls.
        window.setInterval = function (body) {
          window.__capturedIntervals.push(body);
          return window.__capturedIntervals.length;
        };
      }
      else if (__snapshot || __freezeEntranceAnimation) {
        // A repeating example would otherwise race the snapshot. setTimeout stays real: echarts
        // schedules its own throttle / lazy-update work on it.
        window.setInterval = function () { return 0; };
      }

    \(exampleScript)

      // The editor's contract: an example that only assigns `option` gets it applied for it. One that
      // drove myChart itself has already applied its own — re-applying would clobber that state.
      if (!__applied && option) { myChart.setOption(option); }

      window.__entranceReady = !__freezeEntranceAnimation;
      if (__freezeEntranceAnimation) {
        // Async image decodes and component actions may call zr.wakeUp while their setup settles.
        // Keep parking RAF until collection begins; clip state is later reset to the exact t=0 frame.
        function __holdEntranceClock() {
          if (window.__entranceReady) { return; }
          myChart.getZr().animation.stop();
          window.setTimeout(__holdEntranceClock, 16);
        }
        __holdEntranceClock();
        // zrender resolves `image://` symbols lazily on their first canvas brush. Pre-decode every
        // image referenced by the option so logical t=0 does not depend on which reload happened to
        // warm WebKit's image cache first.
        var __entranceImageSources = new Set();
        var __entranceOptionSeen = new Set();
        function __collectEntranceImageSources(value) {
          if (typeof value === 'string') {
            if (value.indexOf('image://') === 0) { __entranceImageSources.add(value.slice(8)); }
            else if (value.indexOf('data:image') === 0) { __entranceImageSources.add(value); }
            return;
          }
          if (!value || typeof value !== 'object' || __entranceOptionSeen.has(value)) { return; }
          __entranceOptionSeen.add(value);
          if (typeof HTMLImageElement !== 'undefined' && value instanceof HTMLImageElement) {
            if (value.src) { __entranceImageSources.add(value.src); }
            return;
          }
          Object.keys(value).forEach(function (key) { __collectEntranceImageSources(value[key]); });
        }
        __collectEntranceImageSources(option);
        window.__entranceStage = 'resource-wait:' + __entranceImageSources.size;
        var __entranceImagePromises = Array.from(__entranceImageSources).map(function (source) {
          return new Promise(function (resolve) {
            var image = new Image();
            var finish = function () { resolve(); };
            image.onload = finish;
            image.onerror = finish;
            image.src = source;
            if (image.decode) { image.decode().then(finish, finish); }
            else if (image.complete) { finish(); }
          });
        });
        Promise.all(__entranceImagePromises).then(function () {
        // Run after zero-delay setup owned by the example. Because this timer is registered after the
        // verbatim example script, FIFO timer ordering lets examples such as dataset-link and
        // line-draggable create their chart/graphics before we freeze and enumerate entrance clips.
        window.__entranceStage = 'setup-wait';
        window.setTimeout(function () {
        window.__entranceStage = 'collecting';
        // Animator-bearing clip/text/guide elements are not necessarily ordinary storage display-list
        // entries. Walk the element tree and all attached components so entrance clips are complete.
        var __entranceClips = [];
        var __entranceSeenElements = new Set();
        var __entranceSeenClips = new Set();
        function __collectEntranceElement(el) {
          if (!el || __entranceSeenElements.has(el)) { return; }
          __entranceSeenElements.add(el);
          var animators = el.animators || [];
          for (var ai = 0; ai < animators.length; ai++) {
            var clip = animators[ai].getClip && animators[ai].getClip();
            if (clip && !__entranceSeenClips.has(clip)) {
              __entranceSeenClips.add(clip);
              __entranceClips.push(clip);
            }
          }
          if (el.getClipPath) { __collectEntranceElement(el.getClipPath()); }
          if (el.getTextContent) { __collectEntranceElement(el.getTextContent()); }
          if (el.getTextGuideLine) { __collectEntranceElement(el.getTextGuideLine()); }
          if (el.children) {
            var children = el.children();
            for (var ci = 0; ci < children.length; ci++) { __collectEntranceElement(children[ci]); }
          }
        }
        var __entranceRoots = myChart.getZr().storage.getRoots();
        for (var ri = 0; ri < __entranceRoots.length; ri++) { __collectEntranceElement(__entranceRoots[ri]); }
        // Adding an animator calls zr.wakeUp(), so the pre-setOption stop above is intentionally
        // repeated after all elements/clips exist. Otherwise RAF races and overwrites the sampled
        // intermediate state before WKWebView commits the canvas for its snapshot.
        myChart.getZr().animation.stop();
        for (var cli = 0; cli < __entranceClips.length; cli++) {
          __entranceClips[cli]._inited = false;
          __entranceClips[cli]._startTime = 0;
          __entranceClips[cli]._pausedTime = 0;
          __entranceClips[cli]._paused = false;
          __entranceClips[cli].__entranceFinished = false;
        }
        window.__stepEntranceAnimation = function (timeMs) {
          for (var i = 0; i < __entranceClips.length; i++) {
            var clip = __entranceClips[i];
            if (clip.__entranceFinished) { continue; }
            var elapsed = timeMs - clip._delay;
            var percent = clip.loop && elapsed >= 0
              ? (elapsed % clip._life) / clip._life
              : Math.max(0, Math.min(elapsed / clip._life, 1));
            clip.onframe(clip.easingFunc ? clip.easingFunc(percent) : percent);
            if (!clip.loop && elapsed >= clip._life) {
              clip.ondestroy();
              clip.__entranceFinished = true;
            }
          }
          // Animation.update normally drives zrender's frame stage, which dirties animated elements
          // before painting. The deterministic oracle bypasses that loop, so mark the collected tree
          // dirty explicitly before the synchronous refresh.
          __entranceSeenElements.forEach(function (el) { if (el.markRedraw) { el.markRedraw(); } });
          // markRedraw schedules zr.refresh(), which wakes the animation loop again. Stop it once more
          // after dirtying so RAF cannot replace the requested logical frame before painting.
          myChart.getZr().animation.stop();
          myChart.getZr().refreshImmediately(true);
          return { clips: __entranceClips.length, time: timeMs };
        };
        window.__entranceReady = true;
        window.__entranceStage = 'ready:' + __entranceClips.length;
        }, \(demo.entranceSetupDelayMs));
        });
      }
    </script>
    </body></html>
    """
}
