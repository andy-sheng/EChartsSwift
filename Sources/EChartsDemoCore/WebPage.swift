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
/// demo's logical size, then `echarts.init(...).setOption(option)` with animation forced off so the
/// snapshot is the final, deterministic frame — matching the static native render.
///
/// The viewport meta pins the layout viewport to the demo's logical width so the fixed-size div
/// scales to fill the WKWebView on iOS (without it, iOS assumes a 980px viewport and the chart
/// renders tiny). macOS WKWebView ignores viewport metas, so the mac pane is unaffected.
public func echartsHTMLPage(_ demo: EChartsDemo) -> String? {
    guard let dist = try? String(contentsOf: Upstream.echartsDistJS, encoding: .utf8) else { return nil }
    guard let optionData = try? JSONSerialization.data(withJSONObject: demo.option, options: []),
          let optionJSON = String(data: optionData, encoding: .utf8) else { return nil }
    // Guard against a stray `</script>` inside the bundle closing the tag early.
    let safeDist = dist.replacingOccurrences(of: "</script", with: "<\\/script")
    return """
    <!DOCTYPE html><html><head><meta charset="utf-8">
    <meta name="viewport" content="width=\(Int(demo.width))">
    <script>\(safeDist)</script>
    </head><body style="margin:0;background:#fff">
    <div id="main" style="width:\(Int(demo.width))px;height:\(Int(demo.height))px"></div>
    <script>
      var opt = \(optionJSON);
      opt.animation = false;
      var chart = echarts.init(document.getElementById('main'), null, { renderer: 'canvas' });
      chart.setOption(opt);
    </script>
    </body></html>
    """
}
