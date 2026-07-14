// official-graph-life-expectancy — replica of https://echarts.apache.org/examples/zh/editor.html?c=graph-life-expectancy
// title: Graph Life Expectancy / titleCN: 预期寿命
// One `graph` series PER COUNTRY (19 of them) laid on a cartesian2d coord system: each node is one year
// (x = income, y = life expectancy), arrow-linked to the next year, so a series traces that country's
// path through the income/longevity plane from 1800 to 2015. A hidden `visualMap` colours the nodes by
// dimension 1 (life expectancy) and the legend is `selectedMode: 'single'`, so exactly ONE country's
// track is visible at a time (the first, China, initially).
//
// DEVIATIONS from the official source:
//   - DATA INLINED: upstream is `$.get(ROOT_PATH + '/data/asset/data/life-expectancy.json', function
//     (rawData) { ... })` and builds the whole option inside the callback. The page has no network, so the
//     asset is vendored at assets/data/life-expectancy.json and read through Upstream.repoRoot. The WEB
//     pane gets the raw JSON text spliced in as `var rawData = ...` and then the callback BODY VERBATIM
//     (same forEach / map / filter / links.pop(), same `myChart.setOption(option)`); only the `$.get`
//     wrapper, the TS type annotations and the trailing `export {};` are gone. The NATIVE pane parses the
//     same bytes and runs the same reshape in Swift.
//   - NATIVE PANE: `animationDelay` is a JS closure (`idx => idx * 100`) and cannot ride in a Swift
//     option — see the PORT-NOTE. Consequence: native nodes animate in together instead of cascading
//     100ms apart per index. Geometry and colour are unaffected.
//   - Node `name`: JS keeps the raw year NUMBER (`item[4]`); the Swift option carries that same year as a
//     String. echarts renders the name as label text either way, so the two panes print the same "1960".
// No `drive`: the example has no timers — the fetch was its only asynchrony, and it is inlined.
import Foundation

// ---------------------------------------------------------------------------
// The asset: { counties: [19 names], timeline: [81 years], series: [81 × [19 × [income, lifeExpectancy,
// population, country, year]]] } — one row per country per year.
// ---------------------------------------------------------------------------
private let graphLifeExpectancyAssetURL =
    Upstream.repoRoot.appendingPathComponent("assets/data/life-expectancy.json")

// The raw JSON text, spliced into webOptionJS so the reference pane runs the official callback body
// against the exact bytes the native pane parses.
private let graphLifeExpectancyJSONText: String =
    (try? String(contentsOf: graphLifeExpectancyAssetURL, encoding: .utf8))
    ?? #"{"counties":[],"timeline":[],"series":[]}"#

// Parsed ONCE; a parse failure degrades to no data (empty axes rather than a crash).
private let graphLifeExpectancyRaw: [String: Any] = {
    guard let data = graphLifeExpectancyJSONText.data(using: .utf8),
          let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
        return ["counties": [String](), "series": [Any]()]
    }
    return obj
}()

private let graphLifeExpectancyCounties: [String] = graphLifeExpectancyRaw["counties"] as? [String] ?? []

/// `rawData.series` — outer index = year, inner = one row per country.
private let graphLifeExpectancyYearRows: [[[Any]]] = graphLifeExpectancyRaw["series"] as? [[[Any]]] ?? []

/// A row is `[income, lifeExpectancy, population, country, year]` — four numbers around a string. Normalise
/// the JSONSerialization NSNumber/NSString mix into Double/String so the Swift option carries plain values.
private func graphLifeExpectancyValue(_ row: [Any]) -> [Any] {
    let num: (Any) -> Double = { ($0 as? NSNumber)?.doubleValue ?? 0 }
    return [num(row[0]), num(row[1]), num(row[2]), (row[3] as? String) ?? "", num(row[4])]
}

// The Swift twin of the example's `rawData.counties.forEach(...)`: for each country, pick that country's
// row out of every year, chain the years with links, and push one `graph` series.
private let graphLifeExpectancySeries: [[String: Any]] = graphLifeExpectancyCounties.map { country in
    let data: [[String: Any]] = graphLifeExpectancyYearRows.compactMap { yearRows -> [String: Any]? in
        // JS: yearData.filter(item => item[3] === country)[0]
        guard let row = yearRows.first(where: { $0.count > 4 && ($0[3] as? String) == country }) else {
            return nil
        }
        let value = graphLifeExpectancyValue(row)
        let year = value[4] as? Double ?? 0
        return [
            // JS: show: +item[4] % 20 === 0 && +item[4] > 1940  →  1960, 1980, 2000 carry a top label.
            "label": [
                "show": year.truncatingRemainder(dividingBy: 20) == 0 && year > 1940,
                "position": "top"
            ] as [String: Any],
            "emphasis": ["label": ["show": true] as [String: Any]] as [String: Any],
            "name": String(Int(year)),
            "value": value
        ] as [String: Any]
    }
    // JS: data.map((item, idx) => ({ source: idx, target: idx + 1 })) then links.pop() — year N → year N+1.
    var links: [[String: Any]] = data.indices.map {
        ["source": Double($0), "target": Double($0 + 1)] as [String: Any]
    }
    if !links.isEmpty { links.removeLast() }

    return [
        "name": country,
        "type": "graph",
        "coordinateSystem": "cartesian2d",
        "data": data,
        "links": links,
        "edgeSymbol": ["none", "arrow"],
        "edgeSymbolSize": 5.0,
        "legendHoverLink": false,
        "lineStyle": ["color": "#333"] as [String: Any],
        "itemStyle": ["borderWidth": 1.0, "borderColor": "#333"] as [String: Any],
        "label": ["color": "#333", "position": "right"] as [String: Any],
        "symbolSize": 10.0
        // PORT-NOTE: series.animationDelay omitted — the JS closure `function (idx) { return idx * 100; }`
        // staggered each node's entry animation by 100ms × its index, so a country's track drew itself
        // year by year. A Swift option cannot carry the closure; the nodes appear together instead.
    ] as [String: Any]
}

extension EChartsDemoRegistry {
    static let official_graph_life_expectancy = EChartsDemo(
        name: "official-graph-life-expectancy", category: "graph",
        summary: "预期寿命 — Graph Life Expectancy",
        width: 720, height: 460,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
var rawData = \#(graphLifeExpectancyJSONText);

const series = [];

rawData.counties.forEach(function (country) {
  const data = rawData.series.map(function (yearData) {
    const item = yearData.filter(function (item) {
      return item[3] === country;
    })[0];
    return {
      label: {
        show: +item[4] % 20 === 0 && +item[4] > 1940,
        position: 'top'
      },
      emphasis: {
        label: {
          show: true
        }
      },
      name: item[4],
      value: item
    };
  });
  var links = data.map(function (item, idx) {
    return {
      source: idx,
      target: idx + 1
    };
  });
  links.pop();

  series.push({
    name: country,
    type: 'graph',
    coordinateSystem: 'cartesian2d',
    data: data,
    links: links,
    edgeSymbol: ['none', 'arrow'],
    edgeSymbolSize: 5,
    legendHoverLink: false,
    lineStyle: {
      color: '#333'
    },
    itemStyle: {
      borderWidth: 1,
      borderColor: '#333'
    },
    label: {
      color: '#333',
      position: 'right'
    },
    symbolSize: 10,
    animationDelay: function (idx) {
      return idx * 100;
    }
  });
});

option = {
  visualMap: {
    show: false,
    min: 0,
    max: 100,
    dimension: 1
  },
  legend: {
    data: rawData.counties,
    selectedMode: 'single',
    right: 100
  },
  grid: {
    left: 0,
    bottom: 0,
    containLabel: true,
    top: 80
  },
  xAxis: {
    type: 'value'
  },
  yAxis: {
    type: 'value',
    scale: true
  },
  toolbox: {
    feature: {
      dataZoom: {}
    }
  },
  dataZoom: {
    type: 'inside'
  },
  series: series
};

myChart.setOption(option);
"""#,
        option: [
            "visualMap": [
                "show": false,
                "min": 0.0,
                "max": 100.0,
                "dimension": 1.0
            ] as [String: Any],
            "legend": [
                "data": graphLifeExpectancyCounties,
                "selectedMode": "single",
                "right": 100.0
            ] as [String: Any],
            "grid": [
                "left": 0.0,
                "bottom": 0.0,
                "containLabel": true,
                "top": 80.0
            ] as [String: Any],
            "xAxis": [
                "type": "value"
            ] as [String: Any],
            "yAxis": [
                "type": "value",
                "scale": true
            ] as [String: Any],
            "toolbox": [
                "feature": ["dataZoom": [:] as [String: Any]] as [String: Any]
            ] as [String: Any],
            "dataZoom": [
                "type": "inside"
            ] as [String: Any],
            "series": graphLifeExpectancySeries
        ])
}
