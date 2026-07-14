// official-custom-gauge — replica of https://echarts.apache.org/examples/zh/editor.html?c=custom-gauge
// title: Custom Gauge / titleCN: 自定义仪表
// A `custom` series on a polar coordinate system: renderItem returns a group of two clipped copies of a
// panel PNG (a sector clip for the coloured arc, a polygon clip for the needle), a white shadowed inner
// disc, and a centred "%" text. A setInterval re-datasets a random value every 3s, and the option's
// animation* keys + renderItem's `transition` / `enterFrom` / `during` hooks sweep the arc, swing the
// needle and count the number to it. The whole chart IS the renderItem closure.
//
// DEVIATIONS from the official source:
//   - ASSET. The panel image `ROOT_PATH + '/data/asset/img/custom-gauge-panel.png'` is not fetched: the
//     repo asset assets/img/custom-gauge-panel.png (byte-identical to the official one — same sha256, a
//     200x200 RGBA PNG) is base64'd into a data: URI at demo time (the page has no network and cannot
//     reach the filesystem) and spliced into the JS in place of the ROOT_PATH URL. Pixels are unchanged.
//     That one `var _panelImageURL = ...` line is the ONLY edit. Nothing was removed: the official
//     source has no `echarts.init` of its own (the editor — here WebPage.swift — declares `myChart`),
//     so EVERYTHING else runs verbatim on the reference pane: renderItem and its helpers (dead
//     `_currentDataIndex` and the `alert()` debug guard in makeText included), the animation hooks, and
//     the trailing `setInterval(..., 3000)` that drives `myChart.setOption({ dataset: ... })`. Only the
//     headless PNG paths (--web-snapshot / --compare) neuter setInterval + animation, so a still frame is
//     deterministic; the live gallery pane runs the example exactly as the website does.
//
// nativeSupported: FALSE. The series is `custom` and its renderItem closure is not decoration but the
// entire chart — a Swift [String: Any] option cannot carry it, so the native pane would draw an empty
// polar grid (angleAxis/radiusAxis are both `show: false`). The Swift `option` below is the same option
// minus that one un-portable key, kept so the two panes stay structurally comparable, and `drive` mirrors
// the example's 3s timeline (inert while nativeSupported is false — the gallery builds no native chart to
// drive — so that the native pane is not ALSO frozen the day a native renderItem hook exists).
import Foundation

// The gauge panel PNG, base64'd into a data: URI. Read once from the repo asset via Upstream.repoRoot —
// the same #filePath-relative read WebPage.swift uses for the upstream echarts dist, so it resolves on
// macOS and the iOS simulator alike. A read failure degrades to an empty URI (the arc/needle then draw
// as blank images rather than crashing).
private let customGaugePanelDataURI: String = {
    let url = Upstream.repoRoot.appendingPathComponent("assets/img/custom-gauge-panel.png")
    guard let data = try? Data(contentsOf: url) else { return "" }
    return "data:image/png;base64," + data.base64EncodedString()
}()

// _valOnRadianMax — the angleAxis max; the needle's value is a fraction of it.
private let customGaugeValOnRadianMax = 200.0

// dataset.source — one row. On polar, dataToPoint maps data[0] → radiusAxis and data[1] → angleAxis, so
// the row is [radiusAxis value, angleAxis value]: renderItem's `valOnRadian` is api.value(1) = 156 of the
// angleAxis max 200 (78%), and the leading 1 is the unused radius. The example's setInterval replaces the
// row with [[1, round(random * 200)]] every 3s (see `drive`).
private let customGaugeSource: [[Double]] = [
    [1, 156]
]

extension EChartsDemoRegistry {
    static let official_custom_gauge = EChartsDemo(
        name: "official-custom-gauge", category: "custom",
        summary: "自定义仪表 — Custom Gauge",
        width: 720, height: 460,
        nativeSupported: false,
        collection: .official,
        webOptionJS: #"""
var _panelImageURL = '\#(customGaugePanelDataURI)';
var _animationDuration = 1000;
var _animationDurationUpdate = 1000;
var _animationEasingUpdate = 'quarticInOut';
var _valOnRadianMax = 200;
var _outerRadius = 200;
var _innerRadius = 170;
var _pointerInnerRadius = 40;
var _insidePanelRadius = 140;
var _currentDataIndex = 0;

function renderItem(params, api) {
  var valOnRadian = api.value(1);
  var coords = api.coord([api.value(0), valOnRadian]);
  var polarEndRadian = coords[3];
  var imageStyle = {
    image: _panelImageURL,
    x: params.coordSys.cx - _outerRadius,
    y: params.coordSys.cy - _outerRadius,
    width: _outerRadius * 2,
    height: _outerRadius * 2
  };

  return {
    type: 'group',
    children: [
      {
        type: 'image',
        style: imageStyle,
        clipPath: {
          type: 'sector',
          shape: {
            cx: params.coordSys.cx,
            cy: params.coordSys.cy,
            r: _outerRadius,
            r0: _innerRadius,
            startAngle: 0,
            endAngle: -polarEndRadian,
            transition: 'endAngle',
            enterFrom: { endAngle: 0 }
          }
        }
      },
      {
        type: 'image',
        style: imageStyle,
        clipPath: {
          type: 'polygon',
          shape: {
            points: makePionterPoints(params, polarEndRadian)
          },
          extra: {
            polarEndRadian: polarEndRadian,
            transition: 'polarEndRadian',
            enterFrom: { polarEndRadian: 0 }
          },
          during: function (apiDuring) {
            apiDuring.setShape(
              'points',
              makePionterPoints(params, apiDuring.getExtra('polarEndRadian'))
            );
          }
        }
      },
      {
        type: 'circle',
        shape: {
          cx: params.coordSys.cx,
          cy: params.coordSys.cy,
          r: _insidePanelRadius
        },
        style: {
          fill: '#fff',
          shadowBlur: 25,
          shadowOffsetX: 0,
          shadowOffsetY: 0,
          shadowColor: 'rgba(76,107,167,0.4)'
        }
      },
      {
        type: 'text',
        extra: {
          valOnRadian: valOnRadian,
          transition: 'valOnRadian',
          enterFrom: { valOnRadian: 0 }
        },
        style: {
          text: makeText(valOnRadian),
          fontSize: 50,
          fontWeight: 700,
          x: params.coordSys.cx,
          y: params.coordSys.cy,
          fill: 'rgb(0,50,190)',
          align: 'center',
          verticalAlign: 'middle',
          enterFrom: { opacity: 0 }
        },
        during: function (apiDuring) {
          apiDuring.setStyle(
            'text',
            makeText(apiDuring.getExtra('valOnRadian'))
          );
        }
      }
    ]
  };
}

function convertToPolarPoint(renderItemParams, radius, radian) {
  return [
    Math.cos(radian) * radius + renderItemParams.coordSys.cx,
    -Math.sin(radian) * radius + renderItemParams.coordSys.cy
  ];
}

function makePionterPoints(renderItemParams, polarEndRadian) {
  return [
    convertToPolarPoint(renderItemParams, _outerRadius, polarEndRadian),
    convertToPolarPoint(
      renderItemParams,
      _outerRadius,
      polarEndRadian + Math.PI * 0.03
    ),
    convertToPolarPoint(renderItemParams, _pointerInnerRadius, polarEndRadian)
  ];
}

function makeText(valOnRadian) {
  // Validate additive animation calc.
  if (valOnRadian < -10) {
    alert('illegal during val: ' + valOnRadian);
  }
  return ((valOnRadian / _valOnRadianMax) * 100).toFixed(0) + '%';
}

option = {
  animationEasing: _animationEasingUpdate,
  animationDuration: _animationDuration,
  animationDurationUpdate: _animationDurationUpdate,
  animationEasingUpdate: _animationEasingUpdate,
  dataset: {
    source: [[1, 156]]
  },
  tooltip: {},
  angleAxis: {
    type: 'value',
    startAngle: 0,
    show: false,
    min: 0,
    max: _valOnRadianMax
  },
  radiusAxis: {
    type: 'value',
    show: false
  },
  polar: {},
  series: [
    {
      type: 'custom',
      coordinateSystem: 'polar',
      renderItem: renderItem
    }
  ]
};

setInterval(function () {
  var nextSource = [[1, Math.round(Math.random() * _valOnRadianMax)]];
  myChart.setOption({
    dataset: {
      source: nextSource
    }
  });
}, 3000);
"""#,
        // The example's `setInterval(..., 3000)`: a merge-setOption of a fresh random dataset row, which
        // the animation* keys + renderItem's transition/during hooks animate the arc, needle and number to.
        drive: { chart in
            chart.every(3) {
                let next: [[Double]] = [[1, Double(Int.random(in: 0...Int(customGaugeValOnRadianMax)))]]
                chart.setOption(["dataset": ["source": next] as [String: Any]], notMerge: false)
            }
        },
        option: [
            "animationEasing": "quarticInOut",          // _animationEasingUpdate
            "animationDuration": 1000.0,
            "animationDurationUpdate": 1000.0,
            "animationEasingUpdate": "quarticInOut",
            "dataset": [
                "source": customGaugeSource
            ] as [String: Any],
            "tooltip": [:] as [String: Any],
            "angleAxis": [
                "type": "value",
                "startAngle": 0.0,
                "show": false,
                "min": 0.0,
                "max": customGaugeValOnRadianMax
            ] as [String: Any],
            "radiusAxis": [
                "type": "value",
                "show": false
            ] as [String: Any],
            "polar": [:] as [String: Any],
            "series": [
                [
                    "type": "custom",
                    "coordinateSystem": "polar"
                    // PORT-NOTE: renderItem omitted — the JS closure IS the chart. Per datum it read
                    // api.value(0)/api.value(1), converted them to a polar radian via api.coord(), and
                    // returned a group of four elements: the panel PNG clipped to a sector
                    // (r0 170 → r 200, endAngle -polarEndRadian) for the coloured arc; the SAME PNG
                    // clipped to a 3-point polygon (outerRadius 200 → pointerInnerRadius 40) for the
                    // needle; a white circle of r 140 with a blue shadow; and a centred 50px text
                    // showing (val / 200 * 100).toFixed(0) + '%'. Its `transition` / `enterFrom` /
                    // `during` hooks drove the arc, needle and number as one additive animation on
                    // every dataset update.
                ] as [String: Any]
            ]
        ])
}
