// official-treemap-disk — replica of https://echarts.apache.org/examples/zh/editor.html?c=treemap-disk
// title: Disk Usage / titleCN: 磁盘占用
// A treemap of a macOS /System/Library directory tree (3,635 nodes, sizes in KB). `visibleMin: 300`
// drops the tiles too small to draw; the three `levels` entries widen the gaps and de-saturate the
// deeper tiles so the hierarchy reads. Every tile is labelled with its node name (`formatter: '{b}'`).
//
// DEVIATIONS from the official source:
//   - DATA INLINED. Upstream does `$.get(ROOT_PATH + '/data/asset/data/disk.tree.json', function (diskData) {...})`
//     and builds the option inside the callback. The page has no network, so the asset is vendored at
//     assets/data/disk.tree.json and read at demo time via Upstream.repoRoot: the web pane keeps the
//     CALLBACK BODY verbatim at top level with the raw JSON spliced in as `var diskData = ...`, and drops
//     only the `$.get` wrapper. `myChart.showLoading()` / `hideLoading()` are KEPT (they now bracket
//     nothing, since the data is already there). The asset IS the series data — no transform — so the
//     native pane parses the same bytes with JSONSerialization (the tree lives in JSON *arrays*, whose
//     order Foundation preserves, so the `sort: 'desc'` tie-breaking order is identical in both panes).
//   - TypeScript-only lines dropped: the `info: any` annotation on the tooltip formatter and the trailing
//     `export {};` (a bare export is a SyntaxError in a classic script).
//   - NATIVE PANE: `tooltip.formatter` is a JS closure and cannot be expressed in a Swift option, so it is
//     omitted — see the PORT-NOTE. Consequence: the native tooltip shows echarts' DEFAULT treemap text
//     instead of the breadcrumb (`treePathInfo` joined by '/') + `'Disk Usage: ' + n + ' KB'`. Nothing
//     else differs: `label.formatter: '{b}'` is a string template (not a closure) and is carried verbatim.
//
// The example drives NO timeline — no setInterval/setTimeout, and its only interactivity (drilling into a
// tile, the breadcrumb) is treemap's own, inside echarts — so there is no `drive` closure. Apart from the
// omitted tooltip formatter, the native `option` below is a complete port of the web one.
import Foundation

// MARK: - the vendored asset

private let treemapDiskAssetURL = Upstream.repoRoot.appendingPathComponent("assets/data/disk.tree.json")

// Raw JSON text — spliced into the web pane's script (the page cannot reach the filesystem).
private let treemapDiskRawJSONText: String =
    (try? String(contentsOf: treemapDiskAssetURL, encoding: .utf8)) ?? "[]"

// The SAME bytes, parsed for the native pane: an array of `{ value, name, path, children? }` nodes, fed
// to the series as-is. A parse failure degrades to no data (an empty treemap rather than a crash).
private let treemapDiskData: [[String: Any]] = {
    guard let data = try? Data(contentsOf: treemapDiskAssetURL),
          let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return [] }
    return arr
}()

// The example's getLevelOption(), ported: level 0 draws no border but leaves a wide gap, levels 1/2
// tighten the gap, and level 2 de-saturates both fill and border.
private let treemapDiskLevels: [[String: Any]] = [
    [
        "itemStyle": [
            "borderWidth": 0.0,
            "gapWidth": 5.0
        ] as [String: Any]
    ],
    [
        "itemStyle": [
            "gapWidth": 1.0
        ] as [String: Any]
    ],
    [
        "colorSaturation": [0.35, 0.5],
        "itemStyle": [
            "gapWidth": 1.0,
            "borderColorSaturation": 0.6
        ] as [String: Any]
    ]
]

extension EChartsDemoRegistry {
    static let official_treemap_disk = EChartsDemo(
        name: "official-treemap-disk", category: "treemap",
        summary: "磁盘占用 — Disk Usage",
        width: 720, height: 460,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
myChart.showLoading();

var diskData = \#(treemapDiskRawJSONText);

myChart.hideLoading();

const formatUtil = echarts.format;

function getLevelOption() {
  return [
    {
      itemStyle: {
        borderWidth: 0,
        gapWidth: 5
      }
    },
    {
      itemStyle: {
        gapWidth: 1
      }
    },
    {
      colorSaturation: [0.35, 0.5],
      itemStyle: {
        gapWidth: 1,
        borderColorSaturation: 0.6
      }
    }
  ];
}

myChart.setOption(
  (option = {
    title: {
      text: 'Disk Usage',
      left: 'center'
    },

    tooltip: {
      formatter: function (info) {
        var value = info.value;
        var treePathInfo = info.treePathInfo;
        var treePath = [];

        for (var i = 1; i < treePathInfo.length; i++) {
          treePath.push(treePathInfo[i].name);
        }

        return [
          '<div class="tooltip-title">' +
            formatUtil.encodeHTML(treePath.join('/')) +
            '</div>',
          'Disk Usage: ' + formatUtil.addCommas(value) + ' KB'
        ].join('');
      }
    },

    series: [
      {
        name: 'Disk Usage',
        type: 'treemap',
        visibleMin: 300,
        label: {
          show: true,
          formatter: '{b}'
        },
        itemStyle: {
          borderColor: '#fff'
        },
        levels: getLevelOption(),
        data: diskData
      }
    ]
  })
);
"""#,
        option: [
            "title": [
                "text": "Disk Usage",
                "left": "center"
            ] as [String: Any],
            "tooltip": [:] as [String: Any],
            // PORT-NOTE: tooltip.formatter omitted — the JS closure built a breadcrumb from
            // `info.treePathInfo` (every ancestor name but the root, joined by '/', HTML-escaped via
            // echarts.format.encodeHTML) as a `<div class="tooltip-title">`, then appended
            // 'Disk Usage: ' + echarts.format.addCommas(info.value) + ' KB' (the size, thousands-separated).
            "series": [
                [
                    "name": "Disk Usage",
                    "type": "treemap",
                    "visibleMin": 300.0,
                    "label": [
                        "show": true,
                        "formatter": "{b}"      // a string template, not a closure — carried verbatim
                    ] as [String: Any],
                    "itemStyle": [
                        "borderColor": "#fff"
                    ] as [String: Any],
                    "levels": treemapDiskLevels as [Any],
                    "data": treemapDiskData as [Any]
                ] as [String: Any]
            ]
        ])
}
