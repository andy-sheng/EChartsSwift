// official-custom-spiral-race — replica of https://echarts.apache.org/examples/zh/editor.html?c=custom-spiral-race
// title: Custom Spiral Race / titleCN: 自定义螺旋线竞速
// A `custom` polar series: each of three racers (A/B/C) is drawn as a spiral polygon whose length
// encodes its value; a setTimeout chain steps through 9 datasources so the spirals race + grow, and
// per-arc `during` closures re-tween the spiral geometry every frame. A rich-text label on each arc
// counts the completed rounds and the fractional percent.
//
// renderItem ported to Swift (spiralRaceRenderItem, below) statement-for-statement — nativeSupported:true.
//
// DEVIATIONS:
//   - `during` dropped on both the polygon and the label. CustomView rebuilds the whole element tree
//     from scratch on every renderItem call (transitions/`during` are DEFERRED — see the PORT-NOTE on
//     CustomSeriesRenderItemAPI's `during` doc in CustomSeries.swift), so the per-frame retween body has
//     no effect natively: each call to renderItem already computes geometry for the CURRENT data, which
//     is what `during` was tweening TOWARD. The `drive` timeline below still re-invokes setOption on the
//     schedule upstream uses, so the native pane still steps through the same 9 datasources — just
//     without the 60fps interpolation between steps (a snap instead of a tween).
//   - `extra`/`transition` keys dropped on both elements for the same reason (customGraphicTransition is
//     not ported — nothing reads them).
//   - The 9 datasources are hoisted to a file-scope `spiralDatasourceList`; the initial radiusAxis.max
//     is computed by `spiralMaxRadius` (upstream getMaxRadius). The web pane inlines them verbatim.
//   - `drive` reproduces upstream next()/setTimeout on the native chart (advance after 1s, then every 7s
//     through the datasources), the same as upstream's own setOption timeline.
import Foundation
import EChartsKit

// The 9 datasources the race steps through (each: three [ordinal, value] rows for racers A/B/C).
private let spiralDatasourceList: [[[Double]]] = [
    [[1, 3], [2, 6], [3, 9]],
    [[1, 12], [2, 16], [3, 14]],
    [[1, 17], [2, 22], [3, 19]],
    [[1, 19], [2, 33], [3, 24]],
    [[1, 24], [2, 42], [3, 29]],
    [[1, 27], [2, 47], [3, 41]],
    [[1, 36], [2, 52], [3, 52]],
    [[1, 46], [2, 59], [3, 63]],
    [[1, 60], [2, 63], [3, 69]]
]

// Upstream getMaxRadius(): the radiusAxis.max for a given datasource — ceil(1.2 * max spiral radius),
// where a datum's radius is valOnStartRadius + valOnRadiusStep(4) * (valOnEndAngle / valOnRoundRadian(12)).
private func spiralMaxRadius(_ idx: Int) -> Double {
    var radius = 0.0
    for item in spiralDatasourceList[idx] {
        radius = max(radius, item[0] + 4.0 * (item[1] / 12.0))
    }
    return (radius * 1.2).rounded(.up)
}

// MARK: - the upstream renderItem, ported

// Numeric coercion for the renderItem api values (ParsedValue is `Any`; api.value may box Int or Double).
private func spiralRaceNum(_ v: Any?) -> Double {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    return .nan
}

// angleAxis.startAngle is 90 by default.
private let spiralStartRadian = Double.pi / 2
private let spiralRadianStep = Double.pi / 45
private let spiralBarWidthValue = 0.4
private let spiralValOnRadiusStep = 4.0

private struct SpiralColor { let fill: String; let text: String }
private let spiralColors: [SpiralColor] = [
    SpiralColor(fill: "#5470c6", text: "#2747a5"),
    SpiralColor(fill: "#91cc75", text: "#447f27"),
    SpiralColor(fill: "#fac858", text: "#a0761c")
]

private let spiralRadianLabels = [
    "Aries", "Taurus", "Gemini", "Cancer", "Leo", "Virgo",
    "Libra", "Scorpius", "Sagittarius", "Capricornus", "Aquarius", "Pisces"
]

private let spiralAngleAxisLabelFormatter: AxisLabelValueFormatter = { value, _, _ in
    let index = Int(value.rounded())
    guard index >= 0, index < spiralRadianLabels.count else { return "" }
    return spiralRadianLabels[index]
}

private let spiralRadiusAxisLabelFormatter: AxisLabelValueFormatter = { value, _, _ in
    switch Int(value.rounded()) {
    case 1: return "A"
    case 2: return "B"
    case 3: return "C"
    default: return ""
    }
}

// getSpiralRadius(startRadius, endRadian, radiusStep)
private func spiralGetRadius(_ startRadius: Double, _ endRadian: Double, _ radiusStep: Double) -> Double {
    return startRadius + radiusStep * ((spiralStartRadian - endRadian) / (Double.pi * 2))
}

// getRadiusStepByWidth(widthRadius)
private func spiralRadiusStepByWidth(_ widthRadius: Double) -> Double {
    return (widthRadius / spiralBarWidthValue) * spiralValOnRadiusStep
}

// convertToPolarPoint(renderItemParams, radius, radian)
private func spiralPolarPoint(_ params: CustomSeriesRenderItemParams, _ radius: Double, _ radian: Double) -> [Double] {
    let cx = spiralRaceNum(params.coordSys.extra["cx"])
    let cy = spiralRaceNum(params.coordSys.extra["cy"])
    return [cos(radian) * radius + cx, -sin(radian) * radius + cy]
}

// makeShapePoints(params, widthRadius, startRadius, endRadian)
private func spiralShapePoints(
    _ params: CustomSeriesRenderItemParams, _ widthRadius: Double, _ startRadius: Double, _ endRadian: Double
) -> [[Double]] {
    var points: [[Double]] = []
    let radiusStep = spiralRadiusStepByWidth(widthRadius)
    // angleAxis.clockwise is true by default. So when rotating clockwise, radian decreases.
    var iRadian = spiralStartRadian
    let end = endRadian - spiralRadianStep
    while iRadian > end {
        if iRadian < endRadian { iRadian = endRadian }
        let iRadius = spiralGetRadius(startRadius - widthRadius, iRadian, radiusStep)
        points.append(spiralPolarPoint(params, iRadius, iRadian))
        iRadian -= spiralRadianStep
    }
    iRadian = endRadian
    while iRadian < spiralStartRadian + spiralRadianStep {
        if iRadian > spiralStartRadian { iRadian = spiralStartRadian }
        let iRadius = spiralGetRadius(startRadius + widthRadius, iRadian, radiusStep)
        points.append(spiralPolarPoint(params, iRadius, iRadian))
        iRadian += spiralRadianStep
    }
    return points
}

// makeLabelPosition(params, widthRadius, startRadius, endRadian)
private func spiralLabelPosition(
    _ params: CustomSeriesRenderItemParams, _ widthRadius: Double, _ startRadius: Double, _ endRadian: Double
) -> [Double] {
    let radiusStep = spiralRadiusStepByWidth(widthRadius)
    let iRadius = spiralGetRadius(startRadius, endRadian, radiusStep)
    return spiralPolarPoint(params, iRadius, endRadian - 10 / iRadius)
}

// makeText(endRadian) — the round/percent rich-text label ('Round {round|N}\n{percent|NN.N%}').
private func spiralLabelText(_ endRadian: Double) -> String {
    let radian = spiralStartRadian - endRadian
    let pi2 = Double.pi * 2
    let round = Int((radian / pi2).rounded(.down))
    let percentValue = (radian / pi2).truncatingRemainder(dividingBy: 1) * 100
    let percent = String(format: "%.1f", percentValue) + "%"
    return "Round {round|\(round)}\n{percent|\(percent)}"
}

// addPolygon(params, children, widthRadius, startRadius, endRadian, color) — `during` dropped, see header.
private func spiralPolygonElement(
    _ params: CustomSeriesRenderItemParams, _ widthRadius: Double, _ startRadius: Double, _ endRadian: Double,
    _ color: SpiralColor
) -> [String: Any] {
    return [
        "type": "polygon",
        "shape": [
            "points": spiralShapePoints(params, widthRadius, startRadius, endRadian)
        ] as [String: Any],
        "style": [
            "fill": color.fill
        ] as [String: Any]
    ] as [String: Any]
}

// addLabel(params, children, widthRadius, startRadius, endRadian, color) — `during` dropped, see header.
private func spiralLabelElement(
    _ params: CustomSeriesRenderItemParams, _ widthRadius: Double, _ startRadius: Double, _ endRadian: Double,
    _ color: SpiralColor
) -> [String: Any] {
    let point = spiralLabelPosition(params, widthRadius, startRadius, endRadian)
    return [
        "type": "text",
        "x": point[0],
        "y": point[1],
        "style": [
            "text": spiralLabelText(endRadian),
            "fill": color.text,
            "stroke": "#fff",
            "lineWidth": 3.0,
            "fontSize": 16.0,
            "align": "center",
            "verticalAlign": "middle",
            "rich": [
                "round": ["fontSize": 24.0] as [String: Any],
                "percent": ["fontSize": 18.0] as [String: Any]
            ] as [String: Any]
        ] as [String: Any],
        "z2": 50.0
    ] as [String: Any]
}

// addShapes(params, api, children, valOnStartRadius, valOnEndRadian, color)
private func spiralAddShapes(
    _ params: CustomSeriesRenderItemParams, _ api: CustomSeriesRenderItemAPI, _ children: inout [[String: Any]],
    _ valOnStartRadius: Double, _ valOnEndRadian: Double, _ color: SpiralColor
) {
    let coords = api.coord([valOnStartRadius, valOnEndRadian] as [Double], nil)
    guard coords.count >= 4 else { return }
    let startRadius = coords[2]
    let endRadian = coords[3]
    let widthCoords = api.coord([spiralBarWidthValue, 0] as [Double], nil)
    guard widthCoords.count >= 4 else { return }
    let widthRadius = widthCoords[2]
    children.append(spiralPolygonElement(params, widthRadius, startRadius, endRadian, color))
    children.append(spiralLabelElement(params, widthRadius, startRadius, endRadian, color))
}

// The official `renderItem`, ported statement for statement. Typed EXACTLY `CustomSeriesRenderItem` so
// CustomView's `get("renderItem") as? CustomSeriesRenderItem` cast holds.
private let spiralRaceRenderItem: CustomSeriesRenderItem = { params, api in
    var children: [[String: Any]] = []
    let dataIdx = Int(params.dataIndex)
    guard dataIdx >= 0, dataIdx < spiralColors.count else { return ["type": "group", "children": children] as [String: Any] }
    let color = spiralColors[dataIdx]
    let valOnStartRadius = spiralRaceNum(api.value(0.0, nil))
    let valOnEndRadian = spiralRaceNum(api.value(1.0, nil))
    spiralAddShapes(params, api, &children, valOnStartRadius, valOnEndRadian, color)
    return [
        "type": "group",
        "children": children
    ] as [String: Any]
}

extension EChartsDemoRegistry {
    static let official_custom_spiral_race = EChartsDemo(
        name: "official-custom-spiral-race", category: "custom",
        summary: "自定义螺旋线竞速 — Custom Spiral Race",
        width: 720, height: 460,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
var _animationDuration = 5000;
var _animationDurationUpdate = 7000;
var _animationEasingUpdate = 'linear';
// prettier-ignore
var _radianLabels = ['Aries', 'Taurus', 'Gemini', 'Cancer', 'Leo', 'Virgo', 'Libra', 'Scorpius', 'Sagittarius', 'Capricornus', 'Aquarius', 'Pisces'];
var _valOnRoundRadian = _radianLabels.length;
var _radianStep = Math.PI / 45;
var _barWidthValue = 0.4;
var _valOnRadiusStep = 4;
// angleAxis.startAngle is 90 by default.
var _startRadian = Math.PI / 2;
// prettier-ignore
var _colors = [
    {fill: '#5470c6', text: '#2747a5'},
    {fill: '#91cc75', text: '#447f27'},
    {fill: '#fac858', text: '#a0761c'}
];

var _currentDataIndex = 0;
// prettier-ignore
var _datasourceList = [
    [ [1, 3], [2, 6], [3, 9] ], // datasource 0
    [ [1, 12], [2, 16], [3, 14] ], // datasource 1
    [ [1, 17], [2, 22], [3, 19] ],  // datasource 2
    [ [1, 19], [2, 33], [3, 24] ],
    [ [1, 24], [2, 42], [3, 29] ],
    [ [1, 27], [2, 47], [3, 41] ],
    [ [1, 36], [2, 52], [3, 52] ],
    [ [1, 46], [2, 59], [3, 63] ],
    [ [1, 60], [2, 63], [3, 69] ],
];
var _barNamesByOrdinal = { 1: 'A', 2: 'B', 3: 'C' };

function getMaxRadius() {
  var radius = 0;
  var datasource = _datasourceList[_currentDataIndex];
  for (var j = 0; j < datasource.length; j++) {
    var dataItem = datasource[j];
    radius = Math.max(radius, getSpiralValueOnRadius(dataItem[0], dataItem[1]));
  }
  return Math.ceil(radius * 1.2);
}

function getSpiralValueOnRadius(valOnStartRadius, valOnEndAngle) {
  return (
    valOnStartRadius + _valOnRadiusStep * (valOnEndAngle / _valOnRoundRadian)
  );
}
function getSpiralRadius(startRadius, endRadian, radiusStep) {
  return (
    startRadius + radiusStep * ((_startRadian - endRadian) / (Math.PI * 2))
  );
}

function renderItem(params, api) {
  var children = [];
  var dataIdx = params.dataIndex;
  addShapes(
    params,
    api,
    children,
    api.value(0),
    api.value(1),
    _colors[dataIdx]
  );

  return {
    type: 'group',
    children: children
  };
}

function addShapes(
  params,
  api,
  children,
  valOnStartRadius,
  valOnEndRadian,
  color
) {
  var coords = api.coord([valOnStartRadius, valOnEndRadian]);
  var startRadius = coords[2];
  var endRadian = coords[3];
  var widthRadius = api.coord([_barWidthValue, 0])[2];
  addPolygon(params, children, widthRadius, startRadius, endRadian, color);
  addLabel(params, children, widthRadius, startRadius, endRadian, color);
}

function addPolygon(
  params,
  children,
  widthRadius,
  startRadius,
  endRadian,
  color
) {
  children.push({
    type: 'polygon',
    shape: {
      points: makeShapePoints(params, widthRadius, startRadius, endRadian)
    },
    extra: {
      widthRadius: widthRadius,
      startRadius: startRadius,
      endRadian: endRadian,
      transition: ['widthRadius', 'startRadius', 'endRadian']
    },
    style: {
      fill: color.fill
    },
    during: function (apiDuring) {
      apiDuring.setShape(
        'points',
        makeShapePoints(
          params,
          apiDuring.getExtra('widthRadius'),
          apiDuring.getExtra('startRadius'),
          apiDuring.getExtra('endRadian')
        )
      );
    }
  });
}

function makeShapePoints(params, widthRadius, startRadius, endRadian) {
  var points = [];
  var radiusStep = getRadiusStepByWidth(widthRadius);
  // angleAxis.clockwise is true by default. So when rotate clickwisely, radian decreases.
  for (
    var iRadian = _startRadian, end = endRadian - _radianStep;
    iRadian > end;
    iRadian -= _radianStep
  ) {
    iRadian < endRadian && (iRadian = endRadian);
    var iRadius = getSpiralRadius(
      startRadius - widthRadius,
      iRadian,
      radiusStep
    );
    points.push(convertToPolarPoint(params, iRadius, iRadian));
  }
  for (
    var iRadian = endRadian;
    iRadian < _startRadian + _radianStep;
    iRadian += _radianStep
  ) {
    iRadian > _startRadian && (iRadian = _startRadian);
    var iRadius = getSpiralRadius(
      startRadius + widthRadius,
      iRadian,
      radiusStep
    );
    points.push(convertToPolarPoint(params, iRadius, iRadian));
  }
  return points;
}

function getRadiusStepByWidth(widthRadius) {
  return (widthRadius / _barWidthValue) * _valOnRadiusStep;
}

function addLabel(
  params,
  children,
  widthRadius,
  startRadius,
  endRadian,
  color
) {
  var point = makeLabelPosition(params, widthRadius, startRadius, endRadian);
  children.push({
    type: 'text',
    x: point[0],
    y: point[1],
    transition: [],
    extra: {
      startRadius: startRadius,
      endRadian: endRadian,
      widthRadius: widthRadius,
      transition: ['startRadius', 'endRadian', 'widthRadius']
    },
    style: {
      text: makeText(endRadian),
      fill: color.text,
      stroke: '#fff',
      lineWidth: 3,
      fontSize: 16,
      align: 'center',
      verticalAlign: 'middle',
      rich: {
        round: { fontSize: 24 },
        percent: { fontSize: 18 }
      }
    },
    z2: 50,
    during: function (apiDuring) {
      var endRadian = apiDuring.getExtra('endRadian');
      var point = makeLabelPosition(
        params,
        apiDuring.getExtra('widthRadius'),
        apiDuring.getExtra('startRadius'),
        endRadian
      );
      apiDuring.setTransform('x', point[0]).setTransform('y', point[1]);
      apiDuring.setStyle('text', makeText(endRadian));
    }
  });

  function makeText(endRadian) {
    var radian = _startRadian - endRadian;
    var PI2 = Math.PI * 2;
    var round = Math.floor(radian / PI2);
    var percent = (((radian / PI2) % 1) * 100).toFixed(1) + '%';
    return 'Round {round|' + round + '}\n{percent|' + percent + '}';
  }
}

function makeLabelPosition(params, widthRadius, startRadius, endRadian) {
  var radiusStep = getRadiusStepByWidth(widthRadius);
  var iRadius = getSpiralRadius(startRadius, endRadian, radiusStep);
  return convertToPolarPoint(params, iRadius, endRadian - 10 / iRadius);
}

function convertToPolarPoint(renderItemParams, radius, radian) {
  return [
    Math.cos(radian) * radius + renderItemParams.coordSys.cx,
    -Math.sin(radian) * radius + renderItemParams.coordSys.cy
  ];
}

option = {
  animationDuration: _animationDuration,
  animationDurationUpdate: _animationDurationUpdate,
  animationEasingUpdate: _animationEasingUpdate,
  dataset: {
    source: _datasourceList[_currentDataIndex]
  },
  tooltip: {},
  angleAxis: {
    type: 'value',
    splitArea: { show: true },
    axisLabel: {
      formatter: function (val) {
        return _radianLabels[val];
      },
      color: 'rgba(0,0,0,0.2)'
    },
    axisLine: { lineStyle: { color: 'rgba(0,0,0,0.2)' } },
    min: 0,
    max: _valOnRoundRadian
  },
  radiusAxis: {
    type: 'value',
    interval: 1,
    splitLine: { show: false },
    axisLabel: {
      color: 'rgba(0,0,0,0.6)',
      formatter: function (value) {
        return _barNamesByOrdinal[value] || '';
      }
    },
    axisTick: { show: false },
    axisLine: { lineStyle: { color: 'rgba(0,0,0,0.2)' } },
    min: 0,
    max: getMaxRadius()
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

function next() {
  ++_currentDataIndex;
  myChart.setOption({
    dataset: {
      source: _datasourceList[_currentDataIndex]
    },
    radiusAxis: {
      max: getMaxRadius()
    }
  });

  if (_currentDataIndex < _datasourceList.length - 1) {
    setTimeout(next, _animationDurationUpdate);
  }
}

setTimeout(next, 1000);
"""#,
        drive: { chart in
            // Upstream next()/setTimeout: first advance after 1s, then every animationDurationUpdate (7s)
            // through the remaining datasources. Each step MERGES the new dataset.source + radiusAxis.max
            // (upstream calls the default, merging, setOption).
            @MainActor func schedule(_ idx: Int) {
                chart.after(idx == 1 ? 1 : 7) {
                    chart.setOption([
                        "dataset": ["source": spiralDatasourceList[idx] as [Any]] as [String: Any],
                        "radiusAxis": ["max": spiralMaxRadius(idx)] as [String: Any]
                    ], notMerge: false)
                    if idx < spiralDatasourceList.count - 1 {
                        schedule(idx + 1)
                    }
                }
            }
            schedule(1)
        },
        option: [
            "animationDuration": 5000.0,
            "animationDurationUpdate": 7000.0,
            "animationEasingUpdate": "linear",
            "dataset": ["source": spiralDatasourceList[0] as [Any]] as [String: Any],
            "tooltip": [:] as [String: Any],
            "angleAxis": [
                "type": "value",
                "splitArea": ["show": true] as [String: Any],
                "axisLabel": [
                    "color": "rgba(0,0,0,0.2)",
                    "formatter": spiralAngleAxisLabelFormatter as AxisLabelValueFormatter
                ] as [String: Any],
                "axisLine": ["lineStyle": ["color": "rgba(0,0,0,0.2)"] as [String: Any]] as [String: Any],
                "min": 0.0,
                "max": 12.0
            ] as [String: Any],
            "radiusAxis": [
                "type": "value",
                "interval": 1.0,
                "splitLine": ["show": false] as [String: Any],
                "axisLabel": [
                    "color": "rgba(0,0,0,0.6)",
                    "formatter": spiralRadiusAxisLabelFormatter as AxisLabelValueFormatter
                ] as [String: Any],
                "axisTick": ["show": false] as [String: Any],
                "axisLine": ["lineStyle": ["color": "rgba(0,0,0,0.2)"] as [String: Any]] as [String: Any],
                "min": 0.0,
                "max": spiralMaxRadius(0)
            ] as [String: Any],
            "polar": [:] as [String: Any],
            "series": [
                [
                    "type": "custom",
                    "coordinateSystem": "polar",
                    // renderItem ported to Swift (spiralRaceRenderItem, top of file): each datum draws a
                    // spiral polygon (makeShapePoints/convertToPolarPoint over api.coord/api.value) plus a
                    // rich-text round/percent label. `during` per-frame retweening is not applicable — see
                    // header DEVIATIONS (CustomView rebuilds the tree from scratch on every renderItem call).
                    "renderItem": spiralRaceRenderItem
                ] as [String: Any]
            ]
        ])
}
