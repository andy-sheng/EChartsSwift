// Same fixed-input CPU benchmark for Native and the pinned WKWebView ECharts renderer.
// Run from the repository root. Timings measure submitted CPU work, not presentation latency.
#if os(macOS)
  import Foundation
  import AppKit
  import WebKit
  import EChartsKit
  import EChartsDemoCore
  import ZRenderKit
  import NativePainter

  func now() -> Double { ProcessInfo.processInfo.systemUptime * 1000 }
  func emit(_ value: [String: Any]) {
    let d = try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    print(String(data: d, encoding: .utf8)!)
    fflush(stdout)
  }
  final class MeterPainter: PainterBase {
    let base = CALayerPainter(size: CGSize(width: 640, height: 420), dpr: 2)
    var times: [Double] = []
    var type: String { "canvas" }
    func refresh(_ list: [Displayable]) {
      let t = now()
      base.refresh(list)
      times.append(now() - t)
    }
    func resize(_ w: Double?, _ h: Double?, _ dpr: Double?) { base.resize(w, h, dpr) }
    func clear() { base.clear() }
    func getWidth() -> Double { 640 }
    func getHeight() -> Double { 420 }
    func dispose() { base.dispose() }
  }
  guard CommandLine.arguments.count >= 2 else {
    fputs("usage: ChartPerformanceProbe <demo> [native|web]\n", stderr)
    exit(2)
  }
  let name = CommandLine.arguments[1]
  let mode = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "native"
  guard mode == "native" || mode == "web" else { exit(2) }
  emit([
    "phase": "metadata", "mode": mode, "width": 640, "height": 420, "dpr": 2, "wheelCount": 5,
    "wheelDelta": 1, "wheelIntervalMs": 150, "metric": "submitted-cpu-ms",
  ])
  let tRegistry = now()
  guard let demo = EChartsDemoRegistry.byName(name) else { fatalError(name) }
  emit(["phase": "registry", "ms": now() - tRegistry, "demo": name])
  if mode == "native" {
    let painter = MeterPainter()
    let view = EChartsView(width: 640, height: 420, painter: painter, useCoarsePointer: false)
    let t = now()
    view.setOption(demo.liveOption ?? demo.option)
    emit(["phase": "setOption", "ms": now() - t, "paintMs": painter.times.reduce(0, +)])
    var t2 = now()
    view.zr.flush()
    emit(["phase": "initialFlush", "ms": now() - t2, "paintMs": painter.times])
    painter.times = []
    for i in 0..<5 {
      RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.15))
      painter.times = []
      t2 = now()
      view._injectWheelForTest(zrDelta: 1, zrX: 320, zrY: 100)
      let eventMs = now() - t2
      let t3 = now()
      view.zr.flush()
      let flushMs = now() - t3
      let counts = view.ec.getModel()!.getSeries().map { $0.getData().count() }
      var ranges: [[Double]] = []
      view.ec.getModel()!.eachComponent("dataZoom") { m, _ in
        if let d = m as? DataZoomModel, let r = d.getPercentRange() { ranges.append(r) }
      }
      emit([
        "phase": "wheel", "i": i, "eventMs": eventMs, "flushMs": flushMs, "paintMs": painter.times,
        "dataCounts": counts, "ranges": ranges,
      ])
    }
    for i in 0..<3 {
      let t = now()
      view.zr.refreshImmediately()
      emit(["phase": "repaint", "i": i, "ms": now() - t])
    }
    view.dispose()
    exit(0)
  }
  final class WebDriver: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    var web: WKWebView!
    func userContentController(
      _ userContentController: WKUserContentController, didReceive message: WKScriptMessage
    ) {
      if let o = message.body as? [String: Any] {
        emit(o)
        if o["phase"] as? String == "done" { exit(0) }
      }
    }
  }
  let app = NSApplication.shared
  app.setActivationPolicy(.prohibited)
  let driver = WebDriver()
  let config = WKWebViewConfiguration()
  config.userContentController.add(driver, name: "probe")
  driver.web = WKWebView(frame: CGRect(x: 0, y: 0, width: 640, height: 420), configuration: config)
  let dist = try! String(contentsOfFile: "upstream/echarts/dist/echarts.js")
  let optionJS: String
  if let js = demo.webOptionJS {
    optionJS = js
  } else {
    let data = try! JSONSerialization.data(withJSONObject: demo.option)
    optionJS = "option = " + String(data: data, encoding: .utf8)! + ";"
  }
  let script = """
    function report(x){window.webkit.messageHandlers.probe.postMessage(x);}
    var option;
    \(optionJS)
    var chart=echarts.init(document.getElementById('main'),null,{width:640,height:420,devicePixelRatio:2});
    var paints=[]; var painter=chart.getZr().painter; var orig=painter.refresh;
    painter.refresh=function(){var t=performance.now();var r=orig.apply(this,arguments);paints.push(performance.now()-t);return r;};
    var t=performance.now();chart.setOption(option);report({phase:'setOption',ms:performance.now()-t,paintMs:paints.slice()});
    var i=0;
    function wheel(){paints=[];var t=performance.now();chart.getZr().handler.mousewheel({zrX:320,zrY:100,zrDelta:1,wheelDelta:1,preventDefault:function(){},stopPropagation:function(){}});var eventMs=performance.now()-t;var t2=performance.now();chart.getZr().flush();report({phase:'wheel',i:i,eventMs:eventMs,flushMs:performance.now()-t2,paintMs:paints.slice(),dataCounts:chart.getModel().getSeries().map(s=>s.getData().count()),ranges:chart.getOption().dataZoom.map(d=>[d.start,d.end])});if(++i<5)setTimeout(wheel,150);else {for(var j=0;j<3;j++){t=performance.now();chart.getZr().refreshImmediately();report({phase:'repaint',i:j,ms:performance.now()-t});}report({phase:'done'});}}
    setTimeout(wheel,300);
    """
  let html =
    "<html><body style='margin:0'><div id='main' style='width:640px;height:420px'></div><script>"
    + dist + "</script><script>" + script + "</script></body></html>"
  driver.web.loadHTMLString(
    html, baseURL: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
  DispatchQueue.main.asyncAfter(deadline: .now() + 180) {
    emit(["phase": "timeout"])
    exit(3)
  }
  app.run()

#else
  import Foundation
  fatalError("ChartPerformanceProbe requires macOS")
#endif
