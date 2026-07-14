// official-treemap-show-parent — replica of https://echarts.apache.org/examples/zh/editor.html?c=treemap-show-parent
// title: Show Parent Labels / titleCN: 显示父层级标签
// A "Disk Usage" treemap of a real directory tree: `upperLabel` (height 30) turns every non-leaf node
// into a titled frame, so the parent hierarchy stays readable while the leaves are tiled inside it.
// `visibleMin: 300` drops nodes smaller than 300 KB, and the three `levels` entries give each depth its
// own border width / gap / colour saturation.
//
// DEVIATIONS from the official source:
//   - DATA INLINED: upstream does `$.get(ROOT_PATH + '/data/asset/data/disk.tree.json', function (diskData) {...})`
//     and builds the option inside the callback. The page has no network, so the asset is vendored at
//     assets/data/disk.tree.json and read via Upstream.repoRoot: the web pane gets the raw JSON text
//     spliced in as `var diskData = ...` (the callback BODY — getLevelOption() included — is otherwise
//     verbatim, `myChart.setOption((option = {...}))` and all), the native pane gets it parsed. Only the
//     `$.get` wrapper is gone; `showLoading()` / `hideLoading()` keep their upstream order (they now
//     bracket the inlined literal instead of a request, so they pair up synchronously).
//   - TypeScript-only text dropped, as it must be to run as a classic script: the `info: any` annotation
//     on the tooltip formatter's parameter, and the trailing `export {};` (a bare export is a SyntaxError).
//   - NATIVE PANE: tooltip.formatter is a JS closure and cannot be expressed in a Swift option, so it is
//     omitted — see the PORT-NOTE. Consequence: the native tooltip shows echarts' default treemap text
//     instead of the `<div class="tooltip-title">a/b/c</div>Disk Usage: 12,345 KB` breadcrumb the closure
//     built from `info.treePathInfo` (`echarts.format.encodeHTML` + `addCommas`). Everything drawn on the
//     canvas — layout, labels, upperLabels, level styling — is identical.
//
// The example drives NO timeline — no `setInterval`/`setTimeout`, and the treemap's own upperLabel framing
// is drawn by echarts itself — so there is no `drive` closure to write. tooltip.formatter is the ONLY
// function-valued key in the upstream option; every other key is present, verbatim, in the native `option`.
import Foundation

private let diskTreeAssetURL = Upstream.repoRoot.appendingPathComponent("assets/data/disk.tree.json")

// The disk-usage tree (nested { value, name, path, children? } nodes). Parsed ONCE from the repo asset;
// a parse failure degrades to no data (the pane renders an empty treemap rather than crashing).
private let diskTreeData: [[String: Any]] = {
    guard let data = try? Data(contentsOf: diskTreeAssetURL),
          let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return [] }
    return arr
}()

// The raw JSON text, spliced into webOptionJS so the reference pane runs the official callback body
// against the exact bytes the native pane parses.
private let diskTreeJSONText: String =
    (try? String(contentsOf: diskTreeAssetURL, encoding: .utf8)) ?? "[]"

// getLevelOption() — verbatim, one entry per treemap depth (root frame, level-1 frames, leaves).
private let diskTreeLevels: [[String: Any]] = [
    [
        "itemStyle": [
            "borderColor": "#777",
            "borderWidth": 0.0,
            "gapWidth": 1.0
        ] as [String: Any],
        "upperLabel": [
            "show": false
        ] as [String: Any]
    ] as [String: Any],
    [
        "itemStyle": [
            "borderColor": "#555",
            "borderWidth": 5.0,
            "gapWidth": 1.0
        ] as [String: Any],
        "emphasis": [
            "itemStyle": [
                "borderColor": "#ddd"
            ] as [String: Any]
        ] as [String: Any]
    ] as [String: Any],
    [
        "colorSaturation": [0.35, 0.5],
        "itemStyle": [
            "borderWidth": 5.0,
            "gapWidth": 1.0,
            "borderColorSaturation": 0.6
        ] as [String: Any]
    ] as [String: Any]
]

extension EChartsDemoRegistry {
    static let official_treemap_show_parent = EChartsDemo(
        name: "official-treemap-show-parent", category: "treemap",
        summary: "显示父层级标签 — Show Parent Labels",
        width: 720, height: 460,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
myChart.showLoading();

var diskData = \#(diskTreeJSONText);

myChart.hideLoading();

function getLevelOption() {
  return [
    {
      itemStyle: {
        borderColor: '#777',
        borderWidth: 0,
        gapWidth: 1
      },
      upperLabel: {
        show: false
      }
    },
    {
      itemStyle: {
        borderColor: '#555',
        borderWidth: 5,
        gapWidth: 1
      },
      emphasis: {
        itemStyle: {
          borderColor: '#ddd'
        }
      }
    },
    {
      colorSaturation: [0.35, 0.5],
      itemStyle: {
        borderWidth: 5,
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
            echarts.format.encodeHTML(treePath.join('/')) +
            '</div>',
          'Disk Usage: ' + echarts.format.addCommas(value) + ' KB'
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
        upperLabel: {
          show: true,
          height: 30
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
            // PORT-NOTE: tooltip.formatter omitted — the JS closure walked `info.treePathInfo` (skipping
            // the virtual root) into an `a/b/c` breadcrumb, HTML-escaped it via echarts.format.encodeHTML
            // into a `<div class="tooltip-title">`, and appended
            // `'Disk Usage: ' + echarts.format.addCommas(info.value) + ' KB'`.
            "tooltip": [:] as [String: Any],
            "series": [
                [
                    "name": "Disk Usage",
                    "type": "treemap",
                    "visibleMin": 300.0,
                    "label": [
                        "show": true,
                        "formatter": "{b}"
                    ] as [String: Any],
                    "upperLabel": [
                        "show": true,
                        "height": 30.0
                    ] as [String: Any],
                    "itemStyle": [
                        "borderColor": "#fff"
                    ] as [String: Any],
                    "levels": diskTreeLevels,
                    "data": diskTreeData
                ] as [String: Any]
            ]
        ])
}
