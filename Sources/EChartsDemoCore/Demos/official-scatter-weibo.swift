// official-scatter-weibo — replica of https://echarts.apache.org/examples/zh/editor.html?c=scatter-weibo
// title: Sign in of weibo / titleCN: 微博签到数据点亮中国
// ~118k Weibo check-in points, split into three signal-strength series (弱 / 中 / 强), drawn as
// `large: true` scatter on a `geo` China map — the points alone light up the country's road network.
// The upstream payload is DELTA-ENCODED: each row is [x0, y0, dx1, dy1, dx2, dy2, ...] in 1/1000 degree
// units, cumulatively summed into lon/lat pairs by the example's `weiboData.map(...)` prelude.
//
// DEVIATIONS from the official source:
//  - DATA INLINED. Upstream fetches the payload with `$.get(ROOT_PATH + '/data/asset/data/weibo.json', ...)`;
//    the page here has no network. The 773 KB payload is read from assets/data/weibo.json at demo time via
//    Upstream.repoRoot (same #filePath-relative repo read WebPage.swift uses for the echarts dist) and
//    spliced into the web pane's script as `var weiboData = [...]`. The $.get wrapper is dropped and its
//    CALLBACK BODY kept verbatim — the delta-decoding prelude still runs as real JS in the web pane — and
//    `myChart.setOption((option = {...}))` becomes a top-level `option = {...}`. The native pane gets the
//    same decode reimplemented in Swift (weiboSeriesData below).
//  - TS ANNOTATIONS STRIPPED from that prelude (`serieData, idx: number` → `serieData, idx`;
//    `let res: number[][] = ...` → `let res = ...`): the web pane is a classic script, not TypeScript.
//  - MAP REGISTERED. The option asks for `geo: { map: 'china' }` but the example never registers it — the
//    official editor leaned on the china map echarts shipped built-in through v4 (it is not in the
//    examples' asset tree, and echarts 6 ships no maps at all, so `map: 'china'` resolves to nothing on
//    either pane unless we supply it). We register 'china' from assets/geo/china.json — apache/echarts
//    4.9.0 `map/json/china.json`, the 42-region map this example was authored against — through
//    `mapRegistrations` (WebPage.swift injects echarts.registerMap before the option script) and
//    `ECharts.registerMap` (native pane). The option text itself is untouched.
//  - `myChart.showLoading()` / `hideLoading()` dropped (editor-harness only), as is the trailing
//    `export {};` (a bare export is a SyntaxError in a classic script and would blank the whole page).
import Foundation
import EChartsKit

// The China provinces GeoJSON (42 regions). Parsed ONCE from the repo asset; a parse failure degrades to
// an empty FeatureCollection (the pane renders blank rather than crashing).
private let weiboChinaGeoJSON: [String: Any] = {
    let url = Upstream.repoRoot.appendingPathComponent("assets/geo/china.json")
    guard let data = try? Data(contentsOf: url),
          let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
        return ["type": "FeatureCollection", "features": [] as [Any]]
    }
    return obj
}()

// Raw upstream payload, verbatim — spliced into the web pane's script in place of the $.get.
private let weiboRawJSON: String = {
    let url = Upstream.repoRoot.appendingPathComponent("assets/data/weibo.json")
    return (try? String(contentsOf: url, encoding: .utf8)) ?? "[[],[],[]]"
}()

// The example's decoding prelude, in Swift: cumulative-sum the 1/1000-degree deltas into [lon, lat] pairs.
// Mirrors `weiboData.map(...)` exactly — the first point of a row is [x, y] (2 components), every later one
// is [+x.toFixed(2), +y.toFixed(2), 1] (a third component, the scatter value). Always yields 3 rows.
private let weiboSeriesData: [[[Double]]] = {
    guard let data = weiboRawJSON.data(using: .utf8),
          let rows = (try? JSONSerialization.jsonObject(with: data)) as? [[Double]] else {
        return [[], [], []]
    }
    var decoded: [[[Double]]] = rows.map { serieData -> [[Double]] in
        guard serieData.count >= 2 else { return [] }
        var px = serieData[0] / 1000
        var py = serieData[1] / 1000
        var res: [[Double]] = [[px, py]]
        var i = 2
        while i + 1 < serieData.count {
            let x = px + serieData[i] / 1000
            let y = py + serieData[i + 1] / 1000
            // JS `+x.toFixed(2)` — round to 2 decimals.
            res.append([(x * 100).rounded() / 100, (y * 100).rounded() / 100, 1])
            px = x
            py = y
            i += 2
        }
        return res
    }
    while decoded.count < 3 { decoded.append([]) }
    return decoded
}()

extension EChartsDemoRegistry {
    static let official_scatter_weibo = EChartsDemo(
        name: "official-scatter-weibo", category: "scatter",
        summary: "微博签到数据点亮中国 — Sign in of weibo",
        width: 640, height: 420,
        nativeSupported: true,
        mapRegistrations: ["china": weiboChinaGeoJSON],
        collection: .official,
        webOptionJS: #"""
var weiboData = \#(weiboRawJSON);

const newWeiboData = weiboData.map(function (serieData, idx) {
  let px = serieData[0] / 1000;
  let py = serieData[1] / 1000;
  let res = [[px, py]];

  for (let i = 2; i < serieData.length; i += 2) {
    let dx = serieData[i] / 1000;
    let dy = serieData[i + 1] / 1000;
    let x = px + dx;
    let y = py + dy;
    res.push([+x.toFixed(2), +y.toFixed(2), 1]);

    px = x;
    py = y;
  }
  return res;
});

option = {
  backgroundColor: '#404a59',
  title: {
    text: '微博签到数据点亮中国',
    subtext: 'From ThinkGIS',
    sublink: 'http://www.thinkgis.cn/public/sina',
    left: 'center',
    top: 'top',
    textStyle: {
      color: '#fff'
    }
  },
  tooltip: {},
  legend: {
    left: 'left',
    data: ['强', '中', '弱'],
    textStyle: {
      color: '#ccc'
    }
  },
  geo: {
    map: 'china',
    roam: true,
    emphasis: {
      label: {
        show: false
      },
      itemStyle: {
        areaColor: '#2a333d'
      }
    },
    itemStyle: {
      areaColor: '#323c48',
      borderColor: '#111'
    }
  },
  series: [
    {
      name: '弱',
      type: 'scatter',
      coordinateSystem: 'geo',
      symbolSize: 1,
      large: true,
      itemStyle: {
        shadowBlur: 2,
        shadowColor: 'rgba(37, 140, 249, 0.8)',
        color: 'rgba(37, 140, 249, 0.8)'
      },
      data: newWeiboData[0]
    },
    {
      name: '中',
      type: 'scatter',
      coordinateSystem: 'geo',
      symbolSize: 1,
      large: true,
      itemStyle: {
        shadowBlur: 2,
        shadowColor: 'rgba(14, 241, 242, 0.8)',
        color: 'rgba(14, 241, 242, 0.8)'
      },
      data: newWeiboData[1]
    },
    {
      name: '强',
      type: 'scatter',
      coordinateSystem: 'geo',
      symbolSize: 1,
      large: true,
      itemStyle: {
        shadowBlur: 2,
        shadowColor: 'rgba(255, 255, 255, 0.8)',
        color: 'rgba(255, 255, 255, 0.8)'
      },
      data: newWeiboData[2]
    }
  ]
};
"""#,
        option: {
            // Upstream leaves this implicit (echarts 4 bundled the china map); echarts 6 does not.
            ECharts.registerMap("china", weiboChinaGeoJSON)
            return [
                "backgroundColor": "#404a59",
                "title": [
                    "text": "微博签到数据点亮中国",
                    "subtext": "From ThinkGIS",
                    "sublink": "http://www.thinkgis.cn/public/sina",
                    "left": "center",
                    "top": "top",
                    "textStyle": [
                        "color": "#fff"
                    ] as [String: Any]
                ] as [String: Any],
                "tooltip": [:] as [String: Any],
                "legend": [
                    "left": "left",
                    "data": ["强", "中", "弱"],
                    "textStyle": [
                        "color": "#ccc"
                    ] as [String: Any]
                ] as [String: Any],
                "geo": [
                    "map": "china",
                    "roam": true,
                    "emphasis": [
                        "label": [
                            "show": false
                        ] as [String: Any],
                        "itemStyle": [
                            "areaColor": "#2a333d"
                        ] as [String: Any]
                    ] as [String: Any],
                    "itemStyle": [
                        "areaColor": "#323c48",
                        "borderColor": "#111"
                    ] as [String: Any]
                ] as [String: Any],
                "series": [
                    [
                        "name": "弱",
                        "type": "scatter",
                        "coordinateSystem": "geo",
                        "symbolSize": 1.0,
                        "large": true,
                        "itemStyle": [
                            "shadowBlur": 2.0,
                            "shadowColor": "rgba(37, 140, 249, 0.8)",
                            "color": "rgba(37, 140, 249, 0.8)"
                        ] as [String: Any],
                        "data": weiboSeriesData[0]
                    ] as [String: Any],
                    [
                        "name": "中",
                        "type": "scatter",
                        "coordinateSystem": "geo",
                        "symbolSize": 1.0,
                        "large": true,
                        "itemStyle": [
                            "shadowBlur": 2.0,
                            "shadowColor": "rgba(14, 241, 242, 0.8)",
                            "color": "rgba(14, 241, 242, 0.8)"
                        ] as [String: Any],
                        "data": weiboSeriesData[1]
                    ] as [String: Any],
                    [
                        "name": "强",
                        "type": "scatter",
                        "coordinateSystem": "geo",
                        "symbolSize": 1.0,
                        "large": true,
                        "itemStyle": [
                            "shadowBlur": 2.0,
                            "shadowColor": "rgba(255, 255, 255, 0.8)",
                            "color": "rgba(255, 255, 255, 0.8)"
                        ] as [String: Any],
                        "data": weiboSeriesData[2]
                    ] as [String: Any]
                ]
            ]
        }())
}
