// official-treemap-drill-down — replica of https://echarts.apache.org/examples/zh/editor.html?c=treemap-drill-down
// title: ECharts Option Query / titleCN: ECharts 配置项查询分布
// A treemap of how often each ECharts option path was queried in the docs (2016/04). `leafDepth: 2`
// makes it a DRILL-DOWN treemap: only two levels are drawn at a time and clicking a tile zooms in
// (that behaviour is treemap's own — no JS), with `visibleMin: 300` hiding the tiny tiles.
//
// DEVIATIONS from the official source:
//   - DATA INLINED. Upstream does `$.getJSON(ROOT_PATH + '/data/asset/data/ec-option-doc-statistics-201604.json', cb)`.
//     The asset is vendored at assets/data/ec-option-doc-statistics-201604.json and read at demo time via
//     Upstream.repoRoot; the web pane keeps the CALLBACK BODY verbatim at top level with the raw JSON
//     spliced in as `rawData`, and drops only the fetch wrapper. `myChart.showLoading()` /
//     `hideLoading()` are kept (they now bracket nothing, since the data is already there).
//   - TypeScript-only lines dropped: the `RawNode` / `TreeNode` type declarations, the `as TreeNode`
//     casts and the trailing `export {};` (a bare export is a SyntaxError in a classic script).
//   - The example's `convert()` is a DATA transform, not an option closure, so the native pane ports it
//     to Swift (`treemapDrillDownConvert`) rather than omitting it. Foundation's JSONSerialization
//     returns UNORDERED dictionaries while JS `for..in` walks keys in insertion order — and that order
//     is what breaks ties in the treemap's `sort: 'desc'` layout — so the asset is read with the small
//     order-preserving reader below instead.
//   - `title.left: 'leafDepth'` is upstream's own quirk (not a valid `left` value: `parsePercent`
//     yields NaN and `getLayoutRect`'s `left = left || 0` safety net puts the title back at the
//     default x=0). Kept verbatim in both panes so both reproduce the quirk.
//
// NO OPTION KEY IS A JS CLOSURE (the only function in the example is `convert`, a data transform, and
// it is ported above — not omitted), and the example drives NO timeline: `leafDepth` drill-down is
// click-driven inside echarts itself, so there is no `setInterval`/`setTimeout` to reproduce and hence
// no `drive` closure. The native `option` below is therefore a COMPLETE port of the web one — every key
// of the upstream option (title.{text,subtext,left}, tooltip, series[0].{name,type,visibleMin,data,
// leafDepth,levels}) is present, nothing dropped or simplified.
import Foundation

// MARK: - the vendored asset

// Raw JSON text — spliced into the web pane's script (the page cannot reach the filesystem).
private let treemapDrillDownRawJSONText: String = {
    let url = Upstream.repoRoot.appendingPathComponent("assets/data/ec-option-doc-statistics-201604.json")
    return (try? String(contentsOf: url, encoding: .utf8)) ?? "{}"
}()

// MARK: - order-preserving JSON reader (see DEVIATIONS)

// The asset is a plain tree: every value is either a nested object or the integer `$count`, and no
// key contains an escape — so this stays a ~40-line reader rather than a JSON library.
private indirect enum TreemapDrillDownJSON {
    case object([(String, TreemapDrillDownJSON)])
    case number(Double)
}

private struct TreemapDrillDownJSONReader {
    private let b: [UInt8]
    private var i = 0
    private init(_ text: String) { b = Array(text.utf8) }

    static func parse(_ text: String) -> TreemapDrillDownJSON? {
        var r = TreemapDrillDownJSONReader(text)
        return r.value()
    }

    private mutating func skipWS() {
        while i < b.count, b[i] == 0x20 || b[i] == 0x09 || b[i] == 0x0A || b[i] == 0x0D { i += 1 }
    }

    private mutating func value() -> TreemapDrillDownJSON? {
        skipWS()
        guard i < b.count else { return nil }
        return b[i] == UInt8(ascii: "{") ? object() : number()
    }

    private mutating func object() -> TreemapDrillDownJSON? {
        i += 1                                             // '{'
        var pairs: [(String, TreemapDrillDownJSON)] = []
        skipWS()
        if i < b.count, b[i] == UInt8(ascii: "}") { i += 1; return .object(pairs) }
        while i < b.count {
            skipWS()
            guard let key = string() else { return nil }
            skipWS()
            guard i < b.count, b[i] == UInt8(ascii: ":") else { return nil }
            i += 1
            guard let v = value() else { return nil }
            pairs.append((key, v))
            skipWS()
            guard i < b.count else { return nil }
            if b[i] == UInt8(ascii: ",") { i += 1; continue }
            if b[i] == UInt8(ascii: "}") { i += 1; return .object(pairs) }
            return nil
        }
        return nil
    }

    private mutating func string() -> String? {
        guard i < b.count, b[i] == UInt8(ascii: "\"") else { return nil }
        i += 1
        let start = i
        while i < b.count, b[i] != UInt8(ascii: "\"") { i += 1 }   // no escapes in this asset
        guard i < b.count else { return nil }
        defer { i += 1 }
        return String(decoding: b[start..<i], as: UTF8.self)
    }

    private mutating func number() -> TreemapDrillDownJSON? {
        let start = i
        while i < b.count, b[i] != UInt8(ascii: ","), b[i] != UInt8(ascii: "}"),
              b[i] != 0x20, b[i] != 0x09, b[i] != 0x0A, b[i] != 0x0D { i += 1 }
        guard let d = Double(String(decoding: b[start..<i], as: UTF8.self)) else { return nil }
        return .number(d)
    }
}

// MARK: - the example's convert(), ported

private final class TreemapDrillDownNode {
    let name: String
    var value: Double?
    var children: [TreemapDrillDownNode] = []
    init(name: String) { self.name = name }

    var asOption: [String: Any] {
        var d: [String: Any] = ["name": name]
        if let value = value { d["value"] = value }               // absent == JS `undefined`
        if !children.isEmpty { d["children"] = children.map { $0.asOption } as [Any] }
        return d
    }
}

// The upstream `convert(source, target, basePath)`, one-to-one:
//   - every non-`$` key becomes a child named by its dotted path, recursed into;
//   - a LEAF takes `source.$count || 1`;
//   - a BRANCH additionally gets a child carrying its own `$count` (the root has none, so — exactly as
//     upstream — that extra child ends up with an undefined/absent value).
// (Upstream's leaf test is `!target.children` — "was the array ever created?" — which the root, seeded
// as `{ children: [] }`, always fails; the test below is `children.isEmpty`. The two differ only for a
// childless ROOT, i.e. only if the asset were empty, so on the real asset they agree exactly. Verified:
// this function's output is identical to the JS one's, node for node, on the vendored file.)
private func treemapDrillDownConvert(_ source: TreemapDrillDownJSON,
                                     into target: TreemapDrillDownNode,
                                     basePath: String) {
    var pairs: [(String, TreemapDrillDownJSON)] = []
    if case .object(let p) = source { pairs = p }
    var count: Double?

    for (key, child) in pairs {                                   // insertion order, like JS `for..in`
        if key == "$count", case .number(let n) = child { count = n }
        guard !key.hasPrefix("$") else { continue }
        let path = basePath.isEmpty ? key : basePath + "." + key
        let node = TreemapDrillDownNode(name: path)
        target.children.append(node)
        treemapDrillDownConvert(child, into: node, basePath: path)
    }

    if target.children.isEmpty {
        let c = count ?? 0
        target.value = c == 0 ? 1 : c                             // `source.$count || 1`
    } else {
        let own = TreemapDrillDownNode(name: basePath)
        own.value = count
        target.children.append(own)
    }
}

// `data.children` — what the series is fed.
private let treemapDrillDownData: [[String: Any]] = {
    guard let raw = TreemapDrillDownJSONReader.parse(treemapDrillDownRawJSONText) else { return [] }
    let root = TreemapDrillDownNode(name: "")
    treemapDrillDownConvert(raw, into: root, basePath: "")
    return root.children.map { $0.asOption }
}()

private let treemapDrillDownLevels: [[String: Any]] = [
    [
        "itemStyle": [
            "borderColor": "#555",
            "borderWidth": 4.0,
            "gapWidth": 4.0
        ] as [String: Any]
    ],
    [
        "colorSaturation": [0.3, 0.6],
        "itemStyle": [
            "borderColorSaturation": 0.7,
            "gapWidth": 2.0,
            "borderWidth": 2.0
        ] as [String: Any]
    ],
    [
        "colorSaturation": [0.3, 0.5],
        "itemStyle": [
            "borderColorSaturation": 0.6,
            "gapWidth": 1.0
        ] as [String: Any]
    ],
    [
        "colorSaturation": [0.3, 0.5]
    ]
]

extension EChartsDemoRegistry {
    static let official_treemap_drill_down = EChartsDemo(
        name: "official-treemap-drill-down", category: "treemap",
        summary: "ECharts 配置项查询分布 — ECharts Option Query",
        width: 720, height: 460,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
myChart.showLoading();

var rawData = \#(treemapDrillDownRawJSONText);

myChart.hideLoading();

function convert(source, target, basePath) {
  for (let key in source) {
    let path = basePath ? basePath + '.' + key : key;
    if (!key.match(/^\$/)) {
      target.children = target.children || [];
      const child = {
        name: path
      };
      target.children.push(child);
      convert(source[key], child, path);
    }
  }

  if (!target.children) {
    target.value = source.$count || 1;
  } else {
    target.children.push({
      name: basePath,
      value: source.$count
    });
  }
}

const data = {
  children: []
};

convert(rawData, data, '');

myChart.setOption(
  (option = {
    title: {
      text: 'ECharts Options',
      subtext: '2016/04',
      left: 'leafDepth'
    },
    tooltip: {},
    series: [
      {
        name: 'option',
        type: 'treemap',
        visibleMin: 300,
        data: data.children,
        leafDepth: 2,
        levels: [
          {
            itemStyle: {
              borderColor: '#555',
              borderWidth: 4,
              gapWidth: 4
            }
          },
          {
            colorSaturation: [0.3, 0.6],
            itemStyle: {
              borderColorSaturation: 0.7,
              gapWidth: 2,
              borderWidth: 2
            }
          },
          {
            colorSaturation: [0.3, 0.5],
            itemStyle: {
              borderColorSaturation: 0.6,
              gapWidth: 1
            }
          },
          {
            colorSaturation: [0.3, 0.5]
          }
        ]
      }
    ]
  })
);
"""#,
        option: [
            "title": [
                "text": "ECharts Options",
                "subtext": "2016/04",
                "left": "leafDepth"
            ] as [String: Any],
            "tooltip": [:] as [String: Any],
            "series": [
                [
                    "name": "option",
                    "type": "treemap",
                    "visibleMin": 300.0,
                    "data": treemapDrillDownData as [Any],
                    "leafDepth": 2.0,
                    "levels": treemapDrillDownLevels as [Any]
                ] as [String: Any]
            ]
        ])
}
