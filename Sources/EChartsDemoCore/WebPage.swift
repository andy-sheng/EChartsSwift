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
public func echartsHTMLPage(_ demo: EChartsDemo, snapshot: Bool = false) -> String? {
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
      var __setOption = myChart.setOption.bind(myChart);
      myChart.setOption = function (opt, a, b) {
        __applied = true;
        if (__snapshot && opt && typeof opt === 'object') { opt.animation = false; }
        return __setOption(opt, a, b);
      };
      if (__snapshot) {
        // A repeating example would otherwise race the snapshot. setTimeout stays real: echarts
        // schedules its own throttle / lazy-update work on it.
        window.setInterval = function () { return 0; };
      }

    \(exampleScript)

      // The editor's contract: an example that only assigns `option` gets it applied for it. One that
      // drove myChart itself has already applied its own — re-applying would clobber that state.
      if (!__applied && option) { myChart.setOption(option); }
    </script>
    </body></html>
    """
}
