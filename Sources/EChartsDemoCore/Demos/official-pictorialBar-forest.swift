// official-pictorialBar-forest — replica of https://echarts.apache.org/examples/zh/editor.html?c=pictorialBar-forest
// title: Expansion of forest / titleCN: 森林的增长
//
// A forest that grows. Ten category rows (`yAxis`, hidden) carry two mirrored `pictorialBar` series —
// one positive, one negative — whose symbol is a single tree PNG (`symbol: 'image://' + treeDataURI`,
// `symbolRepeat: true`), so each bar's length reads as a row of trees spreading left and right of the
// centre. The xAxis is the timeline's readout: it draws no line, no ticks and no labels, only its
// `name` — the current year, in 30px green.
//
// THE 800ms TIMELINE IS PORTED, on both panes. The example is NOT a static option: it walks
// `currentYear` from 2016 to 2050 (then wraps) on a `setInterval(..., 800)`, re-`setOption`ing the
// xAxis `name` and both series' data each tick, so the forest visibly thickens year by year and each
// re-layout springs in through `animationEasing: 'elasticOut'`. The web pane runs that interval
// verbatim; the native pane replays the same timeline through `drive` (see EChartsDemoChart). The
// still-frame PNG paths capture the first frame (year 2016 — four saplings in the middle rows) and
// neuter the timer, so a snapshot stays deterministic.
//
// DEVIATIONS from the official source:
//   - The TS type annotations on `makeSeriesData` (`year: number, negative?: boolean):
//     echarts.PictorialBarSeriesOption['data']`) are dropped — the reference pane runs a CLASSIC
//     script, which cannot parse them; they have no runtime meaning. Trailing `export {};` dropped for
//     the same reason (a bare export is a SyntaxError that would kill the whole page).
//   - `treeDataURI` is already an inline base64 data URI in the official source (no fetch, no asset).
//     It is declared ONCE as a Swift constant and interpolated into webOptionJS instead of being
//     duplicated — same bytes, same pixels.
//   - `makeCategoryData()` / `makeSeriesData()` are plain data generators, so they are re-expressed as
//     Swift functions (same arithmetic, same order); nothing is omitted from the native option.
//   - The interval's update passes `xAxis: { name: currentYear }` — a NUMBER upstream, which echarts
//     stringifies internally. The native pane passes the same year as a String; the drawn text is
//     identical.
//
// NATIVE PANE: nativeSupported: true — but read this before diffing the panes. `pictorialBar` and
// `symbolRepeat` are fully ported (Sources/EChartsKit/chart/bar/PictorialBarView.swift), and the whole
// option below carries into Swift with nothing omitted. The gap is one level down, in the SYMBOL layer:
// `symbol.createSymbol`'s `image://` branch is an explicit deferred seam (Sources/EChartsKit/util/
// symbol.swift — "PORT-NOTE (deferred): graphic.makeImage ... requires the ZRenderKit Image element"),
// so it falls through to `makeFallbackSymbol`, a SymbolPath whose unrecognized symbolType draws as a
// plain RECT. The native pane therefore lays the forest out CORRECTLY — same rows, same bar lengths,
// same repeat count, same year ticking over — but draws each tree as a red rectangle. That is exactly
// the gap this gallery exists to surface, so the pane stays ON rather than being hidden behind an
// "N/A"; it goes away the moment createSymbol's image:// branch lands. (The sibling
// official-pictorialBar-hill, whose images are photographs, keeps its pane off for the same seam.)
import Foundation

// Verbatim from the official source: the tree, as an inline base64 PNG. Declared once here and
// interpolated into webOptionJS so both panes draw the same bytes.
private let forestTreeDataURI = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABwAAAA2CAYAAADUOvnEAAAACXBIWXMAAAsTAAALEwEAmpwYAAAAGXRFWHRTb2Z0d2FyZQBBZG9iZSBJbWFnZVJlYWR5ccllPAAAA5tJREFUeNrcWE1oE0EUnp0kbWyUpCiNYEpCFSpIMdpLRTD15s2ePHixnj00N4/GoyfTg2fbiwdvvagHC1UQ66GQUIQKKgn1UAqSSFua38b3prPJZDs7s5ufKn0w7CaZ2W/fe9/73kyMRqNB3Nrj1zdn4RJ6du9T2u1a2iHYSxjP4d41oOHGQwAIwSUHIyh8/RA8XeiXh0kLGFoaXiTecw/hoTG4ZCSAaFkY0+BpsZceLtiAoV2FkepZSDk5EpppczBvpuuQCqx0YnkYcVVoqQYMyeCG+lFdaGkXeVOFNu4aEBalOBk6sbQrQF7gSdK5JXjuHXuYVIVyr0TZ0FjKDeCs6km7JYMUdrWAUVmZUBtmRnVPK+x6nIR2xomH06R35ggwJPeofWphr/W5UjPIxq8B2bKgE8C4HVHWvg+2gZjXj19PkdFztY7bk9TDCH/g6oafDPpaoMvZIRI5WyMB/0Hv++HkpTKE0kM+A+h20cPAfN4GuRyp9G+LMTW+z8rCLI8b46XO9zRcYZTde/j0AZm8WGb3Y2F9KLlE2nqYkjFLJAsDOl/lea0q55mqxXcL7YBc++bsCPMe8mUyU2ZIpnCoblca6TZA/ga2Co8PGg7UGUlEDd0ueptglbrRZLLE7poti6pCaWUo2pu1oaYI1CF9b9cCZPO3F8ikJQ/rPpQT5YETht26ss+uCIL2Y8vHwJGpA96GI5mjOlaKhowUy6BcNcgIhDviTGWCGFaqEuufWz4pgcbCh+w0gEOyOjTlTtYYlIWPYWKEsLDzOs+nhzaO1KEpd+MXpOoTUgKiNyhdy5aSMPNVqxtSsJFgza5EWA4zKtCJ2OGbLn0JSLu8+SL4G86p1Fpr7ABXdGFF/UTD4rfmFYFw4G9VAJ9SM3aF8l3yok4/J6IV9sDVb36ynmtJ2M5+CwxTYBdKNMBaocKGV2nYgkz6r+cHBP30MzAfi4Sy+BebSoPIOi8PW1PpCCvr/KOD4k9Zu0WSH0Y0+SxJ2awp/nlwKtcGyHOJ8vNHtRJzhPlsHr8MogtlVtwUU0tSM1x58upSKbfJnSKUR07GVMKkDNfXpzpv0RTHy3nZMVx5IOWdZIaPabGFvfpwpjnvfmJHXLaEvZUTseu/TeLc+xgAPhEAb/PbjO6PBaOTf6LQRh/dERde23zxLtOXbaKNhfq2L/1fAOPHDUhOpIf5485h7l+GNHHiSYPKE3Myz9sFxoJuAyazvwIMAItferha5LTqAAAAAElFTkSuQmCC"

// `const beginYear = 2016; const endYear = 2050; const lineCount = 10;`
private let forestBeginYear = 2016
private let forestEndYear = 2050
private let forestLineCount = 10

// `makeCategoryData()` — ten dummy row ids ('0a' … '9a'); the axis is hidden, only the count matters.
private let forestCategoryData: [String] = (0..<forestLineCount).map { "\($0)a" }

/// `makeSeriesData(year, negative?)` — the example's fake data, arithmetic for arithmetic.
/// `r` grows 10 per year, so bars lengthen as the years pass; the first two years (2016/2017) are the
/// four seedlings in the middle rows (value 5) with the rest of the forest at 0. `sign` alternates a
/// 0.9 shortfall every third row (mirrored between the two series) so the two halves are not identical,
/// and every odd row is nudged half a symbol sideways via `symbolOffset` to stagger the tree grid.
private func forestSeriesData(_ year: Int, _ negative: Bool = false) -> [[String: Any]] {
    // upstream: const r = (year - beginYear + 1) * 10;
    let r = Double(year - forestBeginYear + 1) * 10
    let count = Double(forestLineCount)
    var seriesData: [[String: Any]] = []
    for i in 0..<forestLineCount {
        // upstream: negative ? -1 * (i % 3 ? 0.9 : 1) : 1 * ((i + 1) % 3 ? 0.9 : 1)
        let sign: Double = negative ? -1 * (i % 3 != 0 ? 0.9 : 1.0)
                                    : 1 * ((i + 1) % 3 != 0 ? 0.9 : 1.0)
        // upstream: Math.abs(i - lineCount / 2 + 0.5)
        let dist = abs(Double(i) - count / 2 + 0.5)
        let magnitude: Double = year <= forestBeginYear + 1
            ? (dist < count / 5 ? 5 : 0)
            : (count - dist) * r
        var datum: [String: Any] = ["value": sign * magnitude]
        // upstream: symbolOffset: i % 2 ? ['50%', 0] : undefined  — the key is simply absent when even.
        if i % 2 != 0 { datum["symbolOffset"] = ["50%", 0.0] as [Any] }
        seriesData.append(datum)
    }
    return seriesData
}

// The example's initial frame: `option` at `beginYear`. `drive` re-applies xAxis.name + both series'
// data on top of this every 800ms.
private let forestOption: [String: Any] = [
    "color": ["#e54035"],
    "xAxis": [
        "axisLine": ["show": false] as [String: Any],
        "axisLabel": ["show": false] as [String: Any],
        "axisTick": ["show": false] as [String: Any],
        "splitLine": ["show": false] as [String: Any],
        "name": "\(forestBeginYear)",   // upstream: beginYear + ''
        "nameLocation": "middle",
        "nameGap": 40.0,
        "nameTextStyle": [
            "color": "green",
            "fontSize": 30.0,
            "fontFamily": "Arial"
        ] as [String: Any],
        "min": -2800.0,
        "max": 2800.0
    ] as [String: Any],
    "yAxis": [
        "data": forestCategoryData,
        "show": false
    ] as [String: Any],
    "grid": [
        "top": "center",
        "height": 280.0
    ] as [String: Any],
    "series": [
        [
            "name": "all",
            "type": "pictorialBar",
            "symbol": "image://" + forestTreeDataURI,
            "symbolSize": [30.0, 55.0],
            "symbolRepeat": true,
            "data": forestSeriesData(forestBeginYear) as [Any],
            "animationEasing": "elasticOut"
        ] as [String: Any],
        [
            "name": "all",
            "type": "pictorialBar",
            "symbol": "image://" + forestTreeDataURI,
            "symbolSize": [30.0, 55.0],
            "symbolRepeat": true,
            "data": forestSeriesData(forestBeginYear, true) as [Any],
            "animationEasing": "elasticOut"
        ] as [String: Any]
    ]
]

extension EChartsDemoRegistry {
    static let official_pictorialbar_forest = EChartsDemo(
        name: "official-pictorialBar-forest", category: "pictorialBar",
        summary: "森林的增长 — Expansion of forest",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
const treeDataURI = '\#(forestTreeDataURI)';

const beginYear = 2016;
const endYear = 2050;
const lineCount = 10;

// Basic option:
option = {
  color: ['#e54035'],
  xAxis: {
    axisLine: { show: false },
    axisLabel: { show: false },
    axisTick: { show: false },
    splitLine: { show: false },
    name: beginYear + '',
    nameLocation: 'middle',
    nameGap: 40,
    nameTextStyle: {
      color: 'green',
      fontSize: 30,
      fontFamily: 'Arial'
    },
    min: -2800,
    max: 2800
  },
  yAxis: {
    data: makeCategoryData(),
    show: false
  },
  grid: {
    top: 'center',
    height: 280
  },
  series: [
    {
      name: 'all',
      type: 'pictorialBar',
      symbol: 'image://' + treeDataURI,
      symbolSize: [30, 55],
      symbolRepeat: true,
      data: makeSeriesData(beginYear),
      animationEasing: 'elasticOut'
    },
    {
      name: 'all',
      type: 'pictorialBar',
      symbol: 'image://' + treeDataURI,
      symbolSize: [30, 55],
      symbolRepeat: true,
      data: makeSeriesData(beginYear, true),
      animationEasing: 'elasticOut'
    }
  ]
};

// Make fake data.
function makeCategoryData() {
  var categoryData = [];
  for (var i = 0; i < lineCount; i++) {
    categoryData.push(i + 'a');
  }
  return categoryData;
}

function makeSeriesData(year, negative) {
  // make a fake value just for demo.
  const r = (year - beginYear + 1) * 10;
  const seriesData = [];

  for (let i = 0; i < lineCount; i++) {
    let sign = negative ? -1 * (i % 3 ? 0.9 : 1) : 1 * ((i + 1) % 3 ? 0.9 : 1);
    seriesData.push({
      value:
        sign *
        (year <= beginYear + 1
          ? Math.abs(i - lineCount / 2 + 0.5) < lineCount / 5
            ? 5
            : 0
          : (lineCount - Math.abs(i - lineCount / 2 + 0.5)) * r),
      symbolOffset: i % 2 ? ['50%', 0] : undefined
    });
  }
  return seriesData;
}

// Set dynamic data.
var currentYear = beginYear;
setInterval(function () {
  currentYear++;
  if (currentYear > endYear) {
    currentYear = beginYear;
  }
  myChart.setOption({
    xAxis: {
      name: currentYear
    },
    series: [
      {
        data: makeSeriesData(currentYear)
      },
      {
        data: makeSeriesData(currentYear, true)
      }
    ]
  });
}, 800);
"""#,
        // The native pane's half of the same timeline: the example's `setInterval(..., 800)`. A MERGE
        // (notMerge: false) — upstream's bare `myChart.setOption({...})` — so the patch only replaces
        // xAxis.name and each series' data and leaves the axes, grid and symbols standing.
        drive: { chart in
            var currentYear = forestBeginYear
            chart.every(0.8) {
                currentYear += 1
                if currentYear > forestEndYear { currentYear = forestBeginYear }
                chart.setOption([
                    "xAxis": ["name": "\(currentYear)"] as [String: Any],
                    "series": [
                        ["data": forestSeriesData(currentYear) as [Any]] as [String: Any],
                        ["data": forestSeriesData(currentYear, true) as [Any]] as [String: Any]
                    ]
                ], notMerge: false)
            }
        },
        option: forestOption)
}
