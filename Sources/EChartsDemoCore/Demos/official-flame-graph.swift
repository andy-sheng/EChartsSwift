// official-flame-graph — replica of https://echarts.apache.org/examples/zh/editor.html?c=flame-graph
// title: Flame graph / titleCN: 火焰图
// A `custom` series flame graph: a 535-frame stack trace (17 levels deep) flattened into one rect per
// frame — value = [level, startSample, endSample, frameName, percentOfRoot] — with each rect drawn by
// `renderItem` (api.coord on the invisible x/y axes gives x/width; api.size gives the row height) and
// coloured by the kernel module its name starts with (genunix / unix / ufs / zfs / ...).
//
// DEVIATIONS from the official source:
//   - DATA INLINED: the example does `$.get(ROOT_PATH + '/data/asset/data/stack-trace.json', ...)` and
//     builds `option` inside the callback. The asset is vendored at assets/data/stack-trace.json; the
//     web pane gets its raw text spliced in as a `const stackTrace = {...}` above the (otherwise
//     verbatim) callback body, so `option` is assigned unconditionally at the top level. The
//     showLoading()/hideLoading() pair around the fetch is dropped with it.
//   - INTERACTION DROPPED: `myChart.on('click', ...)` — which re-runs recursionJson(stackTrace, id) to
//     zoom into the clicked frame and re-setOptions x-axis max + data — is gone; the gallery renders one
//     static frame, so only the INITIAL (un-zoomed, full-root) state is ported. `filterJson`'s `id`
//     branch is therefore dead code in both panes, but is kept verbatim in the web pane.
//   - The TS source is de-typed to plain JS for the web pane (the page runs a classic script): type
//     annotations, `as const`, `as keyof typeof`, `as CustomSeriesRenderItemReturn` and the trailing
//     `export {}` are removed. Nothing else in the JS changed — renderItem and the tooltip formatter
//     run verbatim.
//   - `renderItem` IS ported natively (flameGraphRenderItem, below) statement for statement: per frame
//     it computes [level, start, end] via api.value/api.coord, the row height via api.size([0,1])[1],
//     and returns a rounded `rect` (2px corner, 2px itemGap) filled with api.visual('color'), with an
//     insideLeft textContent of the frame name (Verdana, truncated to the rect width - 4).
import Foundation
import EChartsKit

// ---------------------------------------------------------------------------
// The asset: assets/data/stack-trace.json (the upstream /data/asset/data/stack-trace.json), read once
// via Upstream.repoRoot — the same #filePath-relative repo read WebPage.swift uses for the echarts dist.
// Raw text feeds the web pane; the parsed object feeds the Swift data port. A read/parse failure
// degrades to a single-frame root (blank-ish chart) rather than crashing.
// ---------------------------------------------------------------------------
private let flameGraphFallbackJSON = #"{ "id": "root", "name": "root", "value": 1 }"#

private let flameGraphStackTraceJSON: String = {
    let url = Upstream.repoRoot.appendingPathComponent("assets/data/stack-trace.json")
    return (try? String(contentsOf: url, encoding: .utf8)) ?? flameGraphFallbackJSON
}()

private let flameGraphStackTrace: [String: Any] = {
    guard let data = flameGraphStackTraceJSON.data(using: .utf8),
          let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
        return ["id": "root", "name": "root", "value": 1.0]
    }
    return obj
}()

// Upstream `ColorTypes`: a frame is coloured by the first word of its name (the kernel module).
private let flameGraphColorTypes: [String: String] = [
    "root": "#8fd3e8",
    "genunix": "#d95850",
    "unix": "#eb8146",
    "ufs": "#ffb248",
    "FSS": "#f2d643",
    "namefs": "#ebdba4",
    "doorfs": "#fcce10",
    "lofs": "#b5c334",
    "zfs": "#1bca93"
]

// Upstream `heightOfJson` — the deepest level in the tree (becomes yAxis.max).
private func flameGraphHeightOfJSON(_ item: [String: Any], _ level: Int = 0) -> Int {
    let children = (item["children"] as? [[String: Any]]) ?? []
    if children.isEmpty { return level }
    return children.map { flameGraphHeightOfJSON($0, level + 1) }.max() ?? level
}

// Upstream `recursionJson(stackTrace)` (the un-filtered, initial-state call): a depth-first flatten of
// the tree into one datum per frame, `value: [level, start, start + value, name, value / rootVal * 100]`,
// where a node's children are laid out end-to-end starting at the node's own `start`.
private func flameGraphRecursionJSON(_ root: [String: Any]) -> [[String: Any]] {
    var data: [[String: Any]] = []
    let rootVal = (root["value"] as? Double) ?? 1

    func recur(_ item: [String: Any], _ start: Double, _ level: Int) {
        let name = (item["name"] as? String) ?? ""
        let value = (item["value"] as? Double) ?? 0
        var itemStyle: [String: Any] = [:]
        // `ColorTypes[item.name.split(' ')[0]]` — undefined (i.e. no color, palette fallback) on a miss.
        if let module = name.split(separator: " ").first.map(String.init),
           let color = flameGraphColorTypes[module] {
            itemStyle["color"] = color
        }
        data.append([
            "name": (item["id"] as? String) ?? "",
            // [level, start_val, end_val, name, percentage]
            "value": [
                Double(level), start, start + value, name,
                rootVal == 0 ? 0.0 : (value / rootVal) * 100
            ] as [Any],
            "itemStyle": itemStyle
        ] as [String: Any])

        var prevStart = start
        for child in (item["children"] as? [[String: Any]]) ?? [] {
            recur(child, prevStart, level + 1)
            prevStart += (child["value"] as? Double) ?? 0
        }
    }

    recur(root, 0, 0)
    return data
}

private let flameGraphData: [[String: Any]] = flameGraphRecursionJSON(flameGraphStackTrace)
private let flameGraphMaxLevel: Double = Double(flameGraphHeightOfJSON(flameGraphStackTrace))

// Coerce a ParsedValue (Any: Double | Int | NSNumber) to Double — the recurring Int-vs-Double read trap.
private func fgNum(_ v: Any?) -> Double {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    return .nan
}

// Upstream `renderItem`, statement for statement. Typed EXACTLY `CustomSeriesRenderItem` so
// CustomView's `get("renderItem") as? CustomSeriesRenderItem` cast holds.
//
// One datum (one stack frame) → one rounded `rect` spanning api.coord([value(1), level]) →
// api.coord([value(2), level]) at the row height api.size([0, 1])[1] (minus a 2px itemGap), filled
// with api.visual('color'), plus an insideLeft textContent of value(3) (the frame name).
private let flameGraphRenderItem: CustomSeriesRenderItem = { _, api in
    let level = fgNum(api.value(0.0, nil))
    let start = api.coord([fgNum(api.value(1.0, nil)), level], nil)
    let end = api.coord([fgNum(api.value(2.0, nil)), level], nil)
    guard start.count >= 2, end.count >= 2 else { return nil }
    // `((api.size && api.size([0, 1])) || [0, 20])[1]` — api.size is always present here (cartesian2d
    // custom series), so this is just api.size([0, 1])[1] with a [0, 20] fallback on a malformed result.
    let sizeArr = (api.size([0.0, 1.0], nil) as? [Double]) ?? [0.0, 20.0]
    let height = sizeArr.count > 1 ? sizeArr[1] : 20.0
    let width = end[0] - start[0]

    // JS `fill: api.visual('color')` — a missing visual is `undefined` in JS (key present, value
    // dropped by JSON-less object literal semantics, i.e. no fill applied); Swift cannot store that
    // sentinel, so a nil visual writes no "fill" key at all (mirrors the `undefined` no-op).
    var rectStyle: [String: Any] = [:]
    if let color = api.visual("color", nil) { rectStyle["fill"] = color }

    return [
        "type": "rect",
        "transition": ["shape"],
        "shape": [
            "x": start[0],
            "y": start[1] - height / 2,
            "width": width,
            "height": height - 2 /* itemGap */,
            "r": 2.0
        ] as [String: Any],
        "style": rectStyle,
        "emphasis": [
            "style": ["stroke": "#000"] as [String: Any]
        ] as [String: Any],
        "textConfig": [
            "position": "insideLeft"
        ] as [String: Any],
        "textContent": [
            "style": [
                "text": api.value(3.0, nil),
                "fontFamily": "Verdana",
                "fill": "#000",
                "width": width - 4,
                "overflow": "truncate",
                "ellipsis": "..",
                "truncateMinChar": 1.0
            ] as [String: Any],
            "emphasis": [
                "style": ["stroke": "#000", "lineWidth": 0.5] as [String: Any]
            ] as [String: Any]
        ] as [String: Any]
    ] as [String: Any]
}

extension EChartsDemoRegistry {
    static let official_flame_graph = EChartsDemo(
        name: "official-flame-graph", category: "custom",
        summary: "火焰图 — Flame graph",
        width: 720, height: 460,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
const ColorTypes = {
  root: '#8fd3e8',
  genunix: '#d95850',
  unix: '#eb8146',
  ufs: '#ffb248',
  FSS: '#f2d643',
  namefs: '#ebdba4',
  doorfs: '#fcce10',
  lofs: '#b5c334',
  zfs: '#1bca93'
};

const filterJson = (json, id) => {
  if (id == null) {
    return json;
  }

  const recur = (item, id) => {
    if (item.id === id) {
      return item;
    }

    for (const child of item.children || []) {
      const temp = recur(child, id);
      if (temp) {
        item.children = [temp];
        item.value = temp.value; // change the parents' values
        return item;
      }
    }
  };

  return recur(json, id) || json;
};

const recursionJson = (jsonObj, id) => {
  const data = [];
  const filteredJson = filterJson(structuredClone(jsonObj), id);
  const rootVal = filteredJson.value;

  const recur = (item, start = 0, level = 0) => {
    const temp = {
      name: item.id,
      // [level, start_val, end_val, name, percentage]
      value: [
        level,
        start,
        start + item.value,
        item.name,
        (item.value / rootVal) * 100
      ],
      itemStyle: {
        color: ColorTypes[item.name.split(' ')[0]]
      }
    };
    data.push(temp);

    let prevStart = start;
    for (const child of item.children || []) {
      recur(child, prevStart, level + 1);
      prevStart = prevStart + child.value;
    }
  };

  recur(filteredJson);
  return data;
};

const heightOfJson = (json) => {
  const recur = (item, level = 0) => {
    if ((item.children || []).length === 0) {
      return level;
    }

    let maxLevel = level;
    for (const child of item.children) {
      const tempLevel = recur(child, level + 1);
      maxLevel = Math.max(maxLevel, tempLevel);
    }
    return maxLevel;
  };

  return recur(json);
};

const renderItem = (params, api) => {
  const level = api.value(0);
  const start = api.coord([api.value(1), level]);
  const end = api.coord([api.value(2), level]);
  const height = ((api.size && api.size([0, 1])) || [0, 20])[1];
  const width = end[0] - start[0];

  return {
    type: 'rect',
    transition: ['shape'],
    shape: {
      x: start[0],
      y: start[1] - height / 2,
      width,
      height: height - 2 /* itemGap */,
      r: 2
    },
    style: {
      fill: api.visual('color')
    },
    emphasis: {
      style: {
        stroke: '#000'
      }
    },
    textConfig: {
      position: 'insideLeft'
    },
    textContent: {
      style: {
        text: api.value(3),
        fontFamily: 'Verdana',
        fill: '#000',
        width: width - 4,
        overflow: 'truncate',
        ellipsis: '..',
        truncateMinChar: 1
      },
      emphasis: {
        style: {
          stroke: '#000',
          lineWidth: 0.5
        }
      }
    }
  };
};

// Inlined asset: the upstream `$.get(ROOT_PATH + '/data/asset/data/stack-trace.json', ...)` payload.
const stackTrace = \#(flameGraphStackTraceJSON);

const levelOfOriginalJson = heightOfJson(stackTrace);

option = {
  backgroundColor: {
    type: 'linear',
    x: 0,
    y: 0,
    x2: 0,
    y2: 1,
    colorStops: [
      {
        offset: 0.05,
        color: '#eee'
      },
      {
        offset: 0.95,
        color: '#eeeeb0'
      }
    ]
  },
  tooltip: {
    formatter: (params) => {
      const samples = params.value[2] - params.value[1];
      return `${params.marker} ${
        params.value[3]
      }: (${echarts.format.addCommas(
        samples
      )} samples, ${+params.value[4].toFixed(2)}%)`;
    }
  },
  title: [
    {
      text: 'Flame Graph',
      left: 'center',
      top: 10,
      textStyle: {
        fontFamily: 'Verdana',
        fontWeight: 'normal',
        fontSize: 20
      }
    }
  ],
  toolbox: {
    feature: {
      restore: {}
    },
    right: 20,
    top: 10
  },
  xAxis: {
    show: false
  },
  yAxis: {
    show: false,
    max: levelOfOriginalJson
  },
  series: [
    {
      type: 'custom',
      renderItem,
      encode: {
        x: [0, 1, 2],
        y: 0
      },
      data: recursionJson(stackTrace)
    }
  ]
};
"""#,
        option: [
            "backgroundColor": [
                "type": "linear",
                "x": 0.0, "y": 0.0, "x2": 0.0, "y2": 1.0,
                "colorStops": [
                    ["offset": 0.05, "color": "#eee"] as [String: Any],
                    ["offset": 0.95, "color": "#eeeeb0"] as [String: Any]
                ]
            ] as [String: Any],
            // PORT-NOTE: tooltip.formatter omitted — the JS closure renders
            // `<marker> <frameName>: (<end - start, comma-grouped> samples, <pct, 2dp>%)`, i.e. it reads
            // value[1..4] of the datum. The tooltip itself stays enabled (default formatter).
            "tooltip": [:] as [String: Any],
            "title": [
                [
                    "text": "Flame Graph",
                    "left": "center",
                    "top": 10.0,
                    "textStyle": [
                        "fontFamily": "Verdana",
                        "fontWeight": "normal",
                        "fontSize": 20.0
                    ] as [String: Any]
                ] as [String: Any]
            ],
            "toolbox": [
                "feature": ["restore": [:] as [String: Any]] as [String: Any],
                "right": 20.0,
                "top": 10.0
            ] as [String: Any],
            "xAxis": [
                "show": false
            ] as [String: Any],
            "yAxis": [
                "show": false,
                "max": flameGraphMaxLevel
            ] as [String: Any],
            "series": [
                [
                    "type": "custom",
                    "renderItem": flameGraphRenderItem,
                    "encode": [
                        "x": [0.0, 1.0, 2.0],
                        "y": 0.0
                    ] as [String: Any],
                    "data": flameGraphData as [Any]
                ] as [String: Any]
            ]
        ])
}
