// official-custom-gauge — replica of https://echarts.apache.org/examples/zh/editor.html?c=custom-gauge
// title: Custom Gauge / titleCN: 自定义仪表
// A `custom` series on a polar coordinate system: renderItem returns a group of two clipped copies of a
// panel PNG (a sector clip for the coloured arc, a polygon clip for the needle), a white shadowed inner
// disc, and a centred "%" text. A setInterval re-datasets a random value every 3s, and the option's
// animation* keys + renderItem's `transition` / `enterFrom` / `during` hooks sweep the arc, swing the
// needle and count the number to it. The whole chart IS the renderItem closure.
//
// renderItem ported to Swift (customGaugeRenderItem, below) statement-for-statement — nativeSupported:true.
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
//   - none for animation: CustomView now supports custom-element `transition` / `enterFrom` / `during`,
//     including clip paths. The two Swift callbacks below mirror the official callbacks and rebuild the
//     polygon pointer / percentage text from each frame's interpolated `extra` value.
//   - FRAMEWORK FIX (flagged): CustomView.swift's per-element `clipPath` (`doCreateOrUpdateClipPath`) was
//     entirely unwired (the call site was commented out, deferred with the transition machinery) — every
//     renderItem `clipPath` spec was previously a silent no-op, so an element clipped to a shape (this
//     demo's two panel-image layers, clipped to a sector / polygon) rendered fully UNCLIPPED instead. The
//     STATIC create/update half of `doCreateOrUpdateClipPath` is now ported (its ANIMATION remains
//     deferred, consistent with the rest of the file) — a small, faithful addition this demo required to
//     render at all correctly; see CustomView.swift for the port-note at both the call site and the new
//     function.
import Foundation
import EChartsKit

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

// MARK: - the upstream renderItem, ported

// Numeric coercion for the renderItem api values (ParsedValue is `Any`; api.value may box Int or Double).
private func customGaugeNum(_ v: Any?) -> Double {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    return .nan
}

// _outerRadius / _innerRadius / _pointerInnerRadius / _insidePanelRadius.
private let customGaugeOuterRadius = 200.0
private let customGaugeInnerRadius = 170.0
private let customGaugePointerInnerRadius = 40.0
private let customGaugeInsidePanelRadius = 140.0

// convertToPolarPoint(renderItemParams, radius, radian)
private func customGaugePolarPoint(_ cx: Double, _ cy: Double, _ radius: Double, _ radian: Double) -> [Double] {
    return [cos(radian) * radius + cx, -sin(radian) * radius + cy]
}

// makePionterPoints(renderItemParams, polarEndRadian) — upstream's own spelling kept in this port-note.
private func customGaugePointerPoints(_ cx: Double, _ cy: Double, _ polarEndRadian: Double) -> [[Double]] {
    return [
        customGaugePolarPoint(cx, cy, customGaugeOuterRadius, polarEndRadian),
        customGaugePolarPoint(cx, cy, customGaugeOuterRadius, polarEndRadian + Double.pi * 0.03),
        customGaugePolarPoint(cx, cy, customGaugePointerInnerRadius, polarEndRadian)
    ]
}

// makeText(valOnRadian) — the official `alert()` is a debug-only guard for an impossible tween value;
// the Swift callback uses the same percentage formatting without presenting UI from render code.
private func customGaugeMakeText(_ valOnRadian: Double) -> String {
    let pct = (valOnRadian / customGaugeValOnRadianMax) * 100
    return String(format: "%.0f", pct) + "%"
}

// The official `renderItem`, ported statement-for-statement. Typed EXACTLY
// `CustomSeriesRenderItem` so CustomView's `get("renderItem") as? CustomSeriesRenderItem` cast holds.
private let customGaugeRenderItem: CustomSeriesRenderItem = { params, api in
    // var valOnRadian = api.value(1);
    let valOnRadian = customGaugeNum(api.value(1.0, nil))
    // var coords = api.coord([api.value(0), valOnRadian]);
    let coords = api.coord([customGaugeNum(api.value(0.0, nil)), valOnRadian], nil)
    guard coords.count >= 4 else { return nil }
    // var polarEndRadian = coords[3];
    let polarEndRadian = coords[3]
    // params.coordSys.{cx,cy} — the polar center (polarPrepareCustom's `extra` bag).
    let cx = customGaugeNum(params.coordSys.extra["cx"])
    let cy = customGaugeNum(params.coordSys.extra["cy"])

    // var imageStyle = { image: _panelImageURL, x: cx - _outerRadius, y: cy - _outerRadius,
    //   width: _outerRadius * 2, height: _outerRadius * 2 };
    let imageStyle: [String: Any] = [
        "image": customGaugePanelDataURI,
        "x": cx - customGaugeOuterRadius,
        "y": cy - customGaugeOuterRadius,
        "width": customGaugeOuterRadius * 2,
        "height": customGaugeOuterRadius * 2
    ]

    return [
        "type": "group",
        "children": [
            // The coloured arc: the panel image clipped to a sector sweeping from 0 to -polarEndRadian.
            [
                "type": "image",
                "style": imageStyle,
                "clipPath": [
                    "type": "sector",
                    "shape": [
                        "cx": cx,
                        "cy": cy,
                        "r": customGaugeOuterRadius,
                        "r0": customGaugeInnerRadius,
                        "startAngle": 0.0,
                        "endAngle": -polarEndRadian,
                        "transition": "endAngle",
                        "enterFrom": ["endAngle": 0.0] as [String: Any]
                    ] as [String: Any]
                ] as [String: Any]
            ] as [String: Any],
            // The needle: the SAME panel image clipped to the 3-point pointer polygon.
            [
                "type": "image",
                "style": imageStyle,
                "clipPath": [
                    "type": "polygon",
                    "shape": [
                        "points": customGaugePointerPoints(cx, cy, polarEndRadian)
                    ] as [String: Any],
                    "extra": [
                        "polarEndRadian": polarEndRadian,
                        "transition": "polarEndRadian",
                        "enterFrom": ["polarEndRadian": 0.0] as [String: Any]
                    ] as [String: Any],
                    "during": { (duringAPI: TransitionDuringAPI) in
                        let raw = duringAPI.getExtra("polarEndRadian")
                        let radian = customGaugeNum(raw)
                        guard radian.isFinite else { return }
                        _ = duringAPI.setShape(
                            "points",
                            customGaugePointerPoints(cx, cy, radian)
                        )
                    } as (TransitionDuringAPI) -> Void
                ] as [String: Any]
            ] as [String: Any],
            // The white shadowed inner disc.
            [
                "type": "circle",
                "shape": ["cx": cx, "cy": cy, "r": customGaugeInsidePanelRadius] as [String: Any],
                "style": [
                    "fill": "#fff",
                    "shadowBlur": 25.0,
                    "shadowOffsetX": 0.0,
                    "shadowOffsetY": 0.0,
                    "shadowColor": "rgba(76,107,167,0.4)"
                ] as [String: Any]
            ] as [String: Any],
            // The centred percentage number.
            [
                "type": "text",
                "extra": [
                    "valOnRadian": valOnRadian,
                    "transition": "valOnRadian",
                    "enterFrom": ["valOnRadian": 0.0] as [String: Any]
                ] as [String: Any],
                "style": [
                    "text": customGaugeMakeText(valOnRadian),
                    "fontSize": 50.0,
                    "fontWeight": 700.0,
                    "x": cx,
                    "y": cy,
                    "fill": "rgb(0,50,190)",
                    "align": "center",
                    "verticalAlign": "middle",
                    "enterFrom": ["opacity": 0.0] as [String: Any]
                ] as [String: Any],
                "during": { (duringAPI: TransitionDuringAPI) in
                    let raw = duringAPI.getExtra("valOnRadian")
                    let value = customGaugeNum(raw)
                    guard value.isFinite else { return }
                    _ = duringAPI.setStyle("text", customGaugeMakeText(value))
                } as (TransitionDuringAPI) -> Void
            ] as [String: Any]
        ]
    ] as [String: Any]
}

extension EChartsDemoRegistry {
    static let official_custom_gauge = EChartsDemo(
        name: "official-custom-gauge", category: "custom",
        summary: "自定义仪表 — Custom Gauge",
        width: 720, height: 460,
        nativeSupported: true,   // renderItem ported to Swift (customGaugeRenderItem) — see header
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
                    "coordinateSystem": "polar",
                    // renderItem ported to Swift (customGaugeRenderItem, top of file): per datum it reads
                    // api.value(0)/api.value(1), converts them to a polar radian via api.coord(), and
                    // returns a group of four elements: the panel PNG clipped to a sector (r0 170 → r 200,
                    // endAngle -polarEndRadian) for the coloured arc; the SAME PNG clipped to a 3-point
                    // polygon (outerRadius 200 → pointerInnerRadius 40) for the needle; a white circle of
                    // r 140 with a blue shadow; and a centred 50px text showing (val / 200 * 100).toFixed(0)
                    // + '%'. The clip-path and text `during` callbacks rebuild their typed shape/style
                    // from interpolated `extra` values on every animation frame, matching echarts.js.
                    "renderItem": customGaugeRenderItem
                ] as [String: Any]
            ]
        ])
}
