// official-custom-gantt-flight — replica of https://echarts.apache.org/examples/zh/editor.html?c=custom-gantt-flight
// title: Gantt Chart of Airport Flights / titleCN: 机场航班甘特图
// An airport's parking-apron schedule as a Gantt chart: 635 flights (arrival→departure) laid out on a `time`
// x-axis (top) against 326 parking aprons on a hidden numeric y-axis, drawn by a `custom` series whose
// renderItem emits one clipped bar per flight (plus a half-width gold overlay for VIP flights and a centred
// flight-number label). A SECOND `custom` series fakes the y-axis labels: per visible apron it draws a green
// tag (an SVG path) carrying the apron type + near-bridge flag. Four dataZooms (x slider + inside, y slider +
// inside) pan/zoom the schedule, and a custom toolbox feature ("Make bars draggable") flips the chart into a
// drag-and-drop mode where a flight can be moved to another apron / time slot.
//
// DEVIATIONS from the official source:
//  - NATIVE PANE OFF (nativeSupported: false): this example's CHART IS ITS `renderItem` CLOSURES. Every visible
//    mark comes from JS — `renderGanttItem` calls api.value()/api.coord()/api.size()/api.style() and
//    echarts.graphic.clipRectByRect() to build a 3-child group per flight, and `renderAxisLabelItem` builds the
//    path+text tag per apron. NOT, however, because a Swift `[String: Any]` option cannot carry a closure — it
//    CAN: CustomView resolves `customSeries.getRenderItem()`, so a `CustomSeriesRenderItem` may ride on the
//    series option under the "renderItem" key (official-custom-cartesian-polygon.swift does exactly that; and it
//    is safe here because WebPage.swift only JSON-serializes `option` when `webOptionJS` is nil, and we set it).
//    The flag is false because the chart needs FOUR things AROUND the closure that EChartsKit does not have
//    today, none of which could be verified (this port was audited under a no-build constraint):
//      (a) `echarts.graphic.clipRectByRect` is NOT ported to Swift at all, and all three flight rects are clipped
//          with it (it would have to be inlined in this file);
//      (b) `api.style()` is an explicitly DEFERRED best-effort stub in CustomView (it returns only the raw
//          item-visual bag), so the bars' fill/opacity are unproven;
//      (c) the ec4 legacy style compat is DEFERRED (CustomView's `processTxInfo` / the unported styleCompat):
//          the flight number is `style: { text: ..., textFill: '#fff' }` ON A RECT, and the apron tag's two texts
//          use `textVerticalAlign`/`textAlign`/`textFill` — the ported style bridge does not honor those in full;
//      (d) `renderAxisLabelItem` places its group with the LEGACY transform prop `position: [10, y]`, and
//          `updateElNormal` copies only x/y/rotation/scaleX/scaleY/originX/originY — every apron tag would pile
//          up at the origin.
//    The rest of the option (toolbox, title, dataZoom, grid, xAxis, yAxis, both series' dimensions/encode/data)
//    IS ported below, so the gap is exactly the two renderItems and the drag layer — nothing else. Lighting the
//    native pane up is a real, tracked follow-up, not an impossibility.
//  - DATA INLINED: upstream does `$.get(ROOT_PATH + '/data/asset/data/airport-schedule.json', function (rawData)
//    { ... })` and builds the option inside the callback. The page has no network, so the asset is vendored at
//    assets/data/airport-schedule.json (mirrored from echarts-examples' public/data/asset/data/airport-schedule.json)
//    and read via Upstream.repoRoot: the web pane gets the raw JSON text spliced in as `var rawData = ...` with the
//    callback BODY (`_rawData = rawData; myChart.setOption((option = makeOption())); initDrag();`) hoisted to the
//    top level; the native pane gets the same bytes parsed in Swift.
//  - DRAG LAYER: WEB-PANE ONLY. `initDrag()` (myChart.on('mousedown'), myChart.getZr().on('mousemove'/'mouseup'/
//    'globalout'), convertToPixel/convertFromPixel, the zr-level Rect ghost/drop-shadow, the conflict check and the
//    requestAnimationFrame auto-dataZoom) runs VERBATIM on the reference pane — nothing was deleted from the JS.
//    It cannot be reproduced natively, but NOT for want of an event bus: `ECharts` IS Eventful-backed and
//    `EChartsDemoChart.on(...)` exposes `myChart.on('mousedown', ...)` (see EChartsDemo.swift). The blockers are
//    that the CHART-LEVEL `convertToPixel` / `convertFromPixel` — the heart of the drag, pixel↔data in both
//    directions — are not on `ECharts` (only the coord systems have them, e.g. coord/cartesian/Grid.swift), and
//    `EChartsDemoChart` exposes no `getZr()`, so the zr-level ghost Rect and its mousemove/mouseup/globalout
//    handlers have nothing to attach to. There is no `drive` closure because the behaviour is pure pointer
//    interaction, not a timeline — and with nativeSupported: false a `drive` would be inert anyway (the gallery
//    builds no native chart for it).
//  - `toolbox.feature.myDrag.onclick` omitted from the native option — see the PORT-NOTE (it is the JS handler that
//    toggles `_draggable` and disables the two `inside` dataZooms).
import Foundation

private let airportScheduleURL = Upstream.repoRoot.appendingPathComponent("assets/data/airport-schedule.json")

// The raw JSON text, spliced into webOptionJS so the reference pane runs the official callback body against the
// exact bytes the native pane parses. Shape: `{ parkingApron: { dimensions, data }, flight: { dimensions, data } }`.
private let airportScheduleJSONText: String =
    (try? String(contentsOf: airportScheduleURL, encoding: .utf8))
    ?? #"{"parkingApron":{"dimensions":[],"data":[]},"flight":{"dimensions":[],"data":[]}}"#

// The same bytes, parsed. A parse failure degrades to empty tables (the pane renders an empty grid, not a crash).
private let airportScheduleRaw: [String: Any] = {
    guard let data = try? Data(contentsOf: airportScheduleURL),
          let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
        let empty: [String: Any] = ["dimensions": [String](), "data": [[Any]]()]
        return ["parkingApron": empty, "flight": empty]
    }
    return obj
}()

private let ganttFlightTable: [String: Any] = (airportScheduleRaw["flight"] as? [String: Any]) ?? [:]
private let ganttApronTable: [String: Any] = (airportScheduleRaw["parkingApron"] as? [String: Any]) ?? [:]

// ['Parking Apron Index', 'Arrival Time', 'Departure Time', 'Flight Number', 'VIP', ...] — 10 dimensions.
private let ganttFlightDimensions: [String] = (ganttFlightTable["dimensions"] as? [String]) ?? []
// 635 rows: [apronIndex, arrivalMs, departureMs, flightNumber, vip, arrCompany, depCompany, arrLine, depLine, reportMs].
private let ganttFlightData: [[Any]] = (ganttFlightTable["data"] as? [[Any]]) ?? []

// ['Name', 'Type', 'Near Bridge'] — 326 rows: ['AB94', 'W', true].
private let ganttApronDimensions: [String] = (ganttApronTable["dimensions"] as? [String]) ?? []
private let ganttApronRows: [[Any]] = (ganttApronTable["data"] as? [[Any]]) ?? []

// JS: `data: _rawData.parkingApron.data.map(function (item, index) { return [index].concat(item); })`
private let ganttApronData: [[Any]] = ganttApronRows.enumerated().map { (index, item) -> [Any] in
    [Double(index) as Any] + item
}

// JS: `yAxis.max: _rawData.parkingApron.data.length`
private let ganttApronCount: Double = Double(ganttApronRows.count)

// The custom toolbox feature's icon (the "pencil over a window" glyph) — verbatim from the example.
private let ganttDragToolboxIcon = "path://M990.55 380.08 q11.69 0 19.88 8.19 q7.02 7.01 7.02 18.71 l0 480.65 q-1.17 43.27 -29.83 71.93 q-28.65 28.65 -71.92 29.82 l-813.96 0 q-43.27 -1.17 -72.5 -30.41 q-28.07 -28.07 -29.24 -71.34 l0 -785.89 q1.17 -43.27 29.24 -72.5 q29.23 -29.24 72.5 -29.24 l522.76 0 q11.7 0 18.71 7.02 q8.19 8.18 8.19 18.71 q0 11.69 -7.6 19.29 q-7.6 7.61 -19.3 7.61 l-518.08 0 q-22.22 1.17 -37.42 16.37 q-15.2 15.2 -15.2 37.42 l0 775.37 q0 23.39 15.2 38.59 q15.2 15.2 37.42 15.2 l804.6 0 q22.22 0 37.43 -15.2 q15.2 -15.2 16.37 -38.59 l0 -474.81 q0 -11.7 7.02 -18.71 q8.18 -8.19 18.71 -8.19 l0 0 ZM493.52 723.91 l-170.74 -170.75 l509.89 -509.89 q23.39 -23.39 56.13 -21.05 q32.75 1.17 59.65 26.9 l47.94 47.95 q25.73 26.89 27.49 59.64 q1.75 32.75 -21.64 57.3 l-508.72 509.9 l0 0 ZM870.09 80.69 l-56.13 56.14 l94.72 95.9 l56.14 -57.31 q8.19 -9.35 8.19 -21.05 q-1.17 -12.86 -10.53 -22.22 l-47.95 -49.12 q-10.52 -9.35 -23.39 -9.35 q-11.69 -1.17 -21.05 7.01 l0 0 ZM867.75 272.49 l-93.56 -95.9 l-380.08 380.08 l94.73 94.73 l378.91 -378.91 l0 0 ZM322.78 553.16 l38.59 39.77 l-33.92 125.13 l125.14 -33.92 l38.59 38.6 l-191.79 52.62 q-5.85 1.17 -12.28 0 q-6.44 -1.17 -11.11 -5.84 q-4.68 -4.68 -5.85 -11.7 q-2.34 -5.85 0 -11.69 l52.63 -192.97 l0 0 Z"

// The x dataZoom slider's handle icon — verbatim from the example.
private let ganttSliderHandleIcon = "path://M10.7,11.9H9.3c-4.9,0.3-8.8,4.4-8.8,9.4c0,5,3.9,9.1,8.8,9.4h1.3c4.9-0.3,8.8-4.4,8.8-9.4C19.5,16.3,15.6,12.2,10.7,11.9z M13.3,24.4H6.7V23h6.6V24.4z M13.3,19.6H6.7v-1.4h6.6V19.6z"

extension EChartsDemoRegistry {
    static let official_custom_gantt_flight = EChartsDemo(
        name: "official-custom-gantt-flight", category: "custom",
        summary: "机场航班甘特图 — Gantt Chart of Airport Flights",
        width: 720, height: 460,
        nativeSupported: false,   // both renderItems ARE the chart — see the header.
        collection: .official,
        webOptionJS: #"""
var HEIGHT_RATIO = 0.6;
var DIM_CATEGORY_INDEX = 0;
var DIM_TIME_ARRIVAL = 1;
var DIM_TIME_DEPARTURE = 2;
var DATA_ZOOM_AUTO_MOVE_THROTTLE = 30;
var DATA_ZOOM_X_INSIDE_INDEX = 1;
var DATA_ZOOM_Y_INSIDE_INDEX = 3;
var DATA_ZOOM_AUTO_MOVE_SPEED = 0.2;
var DATA_ZOOM_AUTO_MOVE_DETECT_AREA_WIDTH = 30;

var _draggable;
var _draggingEl;
var _dropShadow;
var _draggingCursorOffset = [0, 0];
var _draggingTimeLength;
var _draggingRecord;
var _dropRecord;
var _cartesianXBounds = [];
var _cartesianYBounds = [];
var _rawData;
var _autoDataZoomAnimator;

// Upstream: $.get(ROOT_PATH + '/data/asset/data/airport-schedule.json', function (rawData) { ... });
// The page has no network — the vendored asset is spliced in and the callback body runs at the top level.
var rawData = \#(airportScheduleJSONText);

_rawData = rawData;
myChart.setOption((option = makeOption()));
initDrag();

function makeOption() {
  return {
    tooltip: {},
    animation: false,
    toolbox: {
      left: 20,
      top: 0,
      itemSize: 20,
      feature: {
        myDrag: {
          show: true,
          title: 'Make bars\ndraggable',
          icon: 'path://M990.55 380.08 q11.69 0 19.88 8.19 q7.02 7.01 7.02 18.71 l0 480.65 q-1.17 43.27 -29.83 71.93 q-28.65 28.65 -71.92 29.82 l-813.96 0 q-43.27 -1.17 -72.5 -30.41 q-28.07 -28.07 -29.24 -71.34 l0 -785.89 q1.17 -43.27 29.24 -72.5 q29.23 -29.24 72.5 -29.24 l522.76 0 q11.7 0 18.71 7.02 q8.19 8.18 8.19 18.71 q0 11.69 -7.6 19.29 q-7.6 7.61 -19.3 7.61 l-518.08 0 q-22.22 1.17 -37.42 16.37 q-15.2 15.2 -15.2 37.42 l0 775.37 q0 23.39 15.2 38.59 q15.2 15.2 37.42 15.2 l804.6 0 q22.22 0 37.43 -15.2 q15.2 -15.2 16.37 -38.59 l0 -474.81 q0 -11.7 7.02 -18.71 q8.18 -8.19 18.71 -8.19 l0 0 ZM493.52 723.91 l-170.74 -170.75 l509.89 -509.89 q23.39 -23.39 56.13 -21.05 q32.75 1.17 59.65 26.9 l47.94 47.95 q25.73 26.89 27.49 59.64 q1.75 32.75 -21.64 57.3 l-508.72 509.9 l0 0 ZM870.09 80.69 l-56.13 56.14 l94.72 95.9 l56.14 -57.31 q8.19 -9.35 8.19 -21.05 q-1.17 -12.86 -10.53 -22.22 l-47.95 -49.12 q-10.52 -9.35 -23.39 -9.35 q-11.69 -1.17 -21.05 7.01 l0 0 ZM867.75 272.49 l-93.56 -95.9 l-380.08 380.08 l94.73 94.73 l378.91 -378.91 l0 0 ZM322.78 553.16 l38.59 39.77 l-33.92 125.13 l125.14 -33.92 l38.59 38.6 l-191.79 52.62 q-5.85 1.17 -12.28 0 q-6.44 -1.17 -11.11 -5.84 q-4.68 -4.68 -5.85 -11.7 q-2.34 -5.85 0 -11.69 l52.63 -192.97 l0 0 Z',
          onclick: onDragSwitchClick
        }
      }
    },
    title: {
      text: 'Gantt of Airport Flight',
      left: 'center'
    },
    dataZoom: [
      {
        type: 'slider',
        xAxisIndex: 0,
        filterMode: 'weakFilter',
        height: 20,
        bottom: 0,
        start: 0,
        end: 26,
        handleIcon:
          'path://M10.7,11.9H9.3c-4.9,0.3-8.8,4.4-8.8,9.4c0,5,3.9,9.1,8.8,9.4h1.3c4.9-0.3,8.8-4.4,8.8-9.4C19.5,16.3,15.6,12.2,10.7,11.9z M13.3,24.4H6.7V23h6.6V24.4z M13.3,19.6H6.7v-1.4h6.6V19.6z',
        handleSize: '80%',
        showDetail: false
      },
      {
        type: 'inside',
        id: 'insideX',
        xAxisIndex: 0,
        filterMode: 'weakFilter',
        start: 0,
        end: 26,
        zoomOnMouseWheel: false,
        moveOnMouseMove: true
      },
      {
        type: 'slider',
        yAxisIndex: 0,
        zoomLock: true,
        width: 10,
        right: 10,
        top: 70,
        bottom: 20,
        start: 95,
        end: 100,
        handleSize: 0,
        showDetail: false
      },
      {
        type: 'inside',
        id: 'insideY',
        yAxisIndex: 0,
        start: 95,
        end: 100,
        zoomOnMouseWheel: false,
        moveOnMouseMove: true,
        moveOnMouseWheel: true
      }
    ],
    grid: {
      show: true,
      top: 70,
      bottom: 20,
      left: 100,
      right: 20,
      backgroundColor: '#fff',
      borderWidth: 0
    },
    xAxis: {
      type: 'time',
      position: 'top',
      splitLine: {
        lineStyle: {
          color: ['#E9EDFF']
        }
      },
      axisLine: {
        show: false
      },
      axisTick: {
        lineStyle: {
          color: '#929ABA'
        }
      },
      axisLabel: {
        color: '#929ABA',
        inside: false,
        align: 'center'
      }
    },
    yAxis: {
      axisTick: { show: false },
      splitLine: { show: false },
      axisLine: { show: false },
      axisLabel: { show: false },
      min: 0,
      max: _rawData.parkingApron.data.length
    },
    series: [
      {
        id: 'flightData',
        type: 'custom',
        renderItem: renderGanttItem,
        dimensions: _rawData.flight.dimensions,
        encode: {
          x: [DIM_TIME_ARRIVAL, DIM_TIME_DEPARTURE],
          y: DIM_CATEGORY_INDEX,
          tooltip: [DIM_CATEGORY_INDEX, DIM_TIME_ARRIVAL, DIM_TIME_DEPARTURE]
        },
        data: _rawData.flight.data
      },
      {
        type: 'custom',
        renderItem: renderAxisLabelItem,
        dimensions: _rawData.parkingApron.dimensions,
        encode: {
          x: -1, // Then this series will not controlled by x.
          y: 0
        },
        data: _rawData.parkingApron.data.map(function (item, index) {
          return [index].concat(item);
        })
      }
    ]
  };
}

function renderGanttItem(params, api) {
  var categoryIndex = api.value(DIM_CATEGORY_INDEX);
  var timeArrival = api.coord([api.value(DIM_TIME_ARRIVAL), categoryIndex]);
  var timeDeparture = api.coord([api.value(DIM_TIME_DEPARTURE), categoryIndex]);

  var coordSys = params.coordSys;
  _cartesianXBounds[0] = coordSys.x;
  _cartesianXBounds[1] = coordSys.x + coordSys.width;
  _cartesianYBounds[0] = coordSys.y;
  _cartesianYBounds[1] = coordSys.y + coordSys.height;

  var barLength = timeDeparture[0] - timeArrival[0];
  // Get the heigth corresponds to length 1 on y axis.
  var barHeight = api.size([0, 1])[1] * HEIGHT_RATIO;
  var x = timeArrival[0];
  var y = timeArrival[1] - barHeight;

  var flightNumber = api.value(3) + '';
  var flightNumberWidth = echarts.format.getTextRect(flightNumber).width;
  var text =
    barLength > flightNumberWidth + 40 && x + barLength >= 180
      ? flightNumber
      : '';

  var rectNormal = clipRectByRect(params, {
    x: x,
    y: y,
    width: barLength,
    height: barHeight
  });
  var rectVIP = clipRectByRect(params, {
    x: x,
    y: y,
    width: barLength / 2,
    height: barHeight
  });
  var rectText = clipRectByRect(params, {
    x: x,
    y: y,
    width: barLength,
    height: barHeight
  });

  return {
    type: 'group',
    children: [
      {
        type: 'rect',
        ignore: !rectNormal,
        shape: rectNormal,
        style: api.style()
      },
      {
        type: 'rect',
        ignore: !rectVIP && !api.value(4),
        shape: rectVIP,
        style: api.style({ fill: '#ddb30b' })
      },
      {
        type: 'rect',
        ignore: !rectText,
        shape: rectText,
        style: api.style({
          fill: 'transparent',
          stroke: 'transparent',
          text: text,
          textFill: '#fff'
        })
      }
    ]
  };
}

function renderAxisLabelItem(params, api) {
  var y = api.coord([0, api.value(0)])[1];
  if (y < params.coordSys.y + 5) {
    return;
  }
  return {
    type: 'group',
    position: [10, y],
    children: [
      {
        type: 'path',
        shape: {
          d: 'M0,0 L0,-20 L30,-20 C42,-20 38,-1 50,-1 L70,-1 L70,0 Z',
          x: 0,
          y: -20,
          width: 90,
          height: 20,
          layout: 'cover'
        },
        style: {
          fill: '#368c6c'
        }
      },
      {
        type: 'text',
        style: {
          x: 24,
          y: -3,
          text: api.value(1),
          textVerticalAlign: 'bottom',
          textAlign: 'center',
          textFill: '#fff'
        }
      },
      {
        type: 'text',
        style: {
          x: 75,
          y: -2,
          textVerticalAlign: 'bottom',
          textAlign: 'center',
          text: api.value(2),
          textFill: '#000'
        }
      }
    ]
  };
}

function clipRectByRect(params, rect) {
  return echarts.graphic.clipRectByRect(rect, {
    x: params.coordSys.x,
    y: params.coordSys.y,
    width: params.coordSys.width,
    height: params.coordSys.height
  });
}

// -------------
//  Enable Drag
// -------------

function onDragSwitchClick(model, api, type) {
  _draggable = !_draggable;
  myChart.setOption({
    dataZoom: [
      {
        id: 'insideX',
        disabled: _draggable
      },
      {
        id: 'insideY',
        disabled: _draggable
      }
    ]
  });
  this.model.setIconStatus(type, _draggable ? 'emphasis' : 'normal');
}

function initDrag() {
  _autoDataZoomAnimator = makeAnimator(dispatchDataZoom);

  myChart.on('mousedown', function (param) {
    if (!_draggable || !param || param.seriesIndex == null) {
      return;
    }

    // Drag start
    _draggingRecord = {
      dataIndex: param.dataIndex,
      categoryIndex: param.value[DIM_CATEGORY_INDEX],
      timeArrival: param.value[DIM_TIME_ARRIVAL],
      timeDeparture: param.value[DIM_TIME_DEPARTURE]
    };
    var style = {
      lineWidth: 2,
      fill: 'rgba(255,0,0,0.1)',
      stroke: 'rgba(255,0,0,0.8)',
      lineDash: [6, 3]
    };

    _draggingEl = addOrUpdateBar(_draggingEl, _draggingRecord, style, 100);
    _draggingCursorOffset = [
      _draggingEl.position[0] - param.event.offsetX,
      _draggingEl.position[1] - param.event.offsetY
    ];
    _draggingTimeLength =
      _draggingRecord.timeDeparture - _draggingRecord.timeArrival;
  });

  myChart.getZr().on('mousemove', function (event) {
    if (!_draggingEl) {
      return;
    }

    var cursorX = event.offsetX;
    var cursorY = event.offsetY;

    // Move _draggingEl.
    _draggingEl.attr('position', [
      _draggingCursorOffset[0] + cursorX,
      _draggingCursorOffset[1] + cursorY
    ]);

    prepareDrop();

    autoDataZoomWhenDraggingOutside(cursorX, cursorY);
  });

  myChart.getZr().on('mouseup', function () {
    // Drop
    if (_draggingEl && _dropRecord) {
      updateRawData() &&
        myChart.setOption({
          series: {
            id: 'flightData',
            data: _rawData.flight.data
          }
        });
    }
    dragRelease();
  });
  myChart.getZr().on('globalout', dragRelease);

  function dragRelease() {
    _autoDataZoomAnimator.stop();

    if (_draggingEl) {
      myChart.getZr().remove(_draggingEl);
      _draggingEl = null;
    }
    if (_dropShadow) {
      myChart.getZr().remove(_dropShadow);
      _dropShadow = null;
    }
    _dropRecord = _draggingRecord = null;
  }

  function addOrUpdateBar(el, itemData, style, z) {
    var pointArrival = myChart.convertToPixel('grid', [
      itemData.timeArrival,
      itemData.categoryIndex
    ]);
    var pointDeparture = myChart.convertToPixel('grid', [
      itemData.timeDeparture,
      itemData.categoryIndex
    ]);

    var barLength = pointDeparture[0] - pointArrival[0];
    var barHeight =
      Math.abs(
        myChart.convertToPixel('grid', [0, 0])[1] -
          myChart.convertToPixel('grid', [0, 1])[1]
      ) * HEIGHT_RATIO;

    if (!el) {
      el = new echarts.graphic.Rect({
        shape: { x: 0, y: 0, width: 0, height: 0 },
        style: style,
        z: z
      });
      myChart.getZr().add(el);
    }
    el.attr({
      shape: { x: 0, y: 0, width: barLength, height: barHeight },
      position: [pointArrival[0], pointArrival[1] - barHeight]
    });
    return el;
  }

  function prepareDrop() {
    // Check droppable place.
    var xPixel = _draggingEl.shape.x + _draggingEl.position[0];
    var yPixel = _draggingEl.shape.y + _draggingEl.position[1];
    var cursorData = myChart.convertFromPixel('grid', [xPixel, yPixel]);
    if (cursorData) {
      // Make drop shadow and _dropRecord
      _dropRecord = {
        categoryIndex: Math.floor(cursorData[1]),
        timeArrival: cursorData[0],
        timeDeparture: cursorData[0] + _draggingTimeLength
      };
      var style = { fill: 'rgba(0,0,0,0.4)' };
      _dropShadow = addOrUpdateBar(_dropShadow, _dropRecord, style, 99);
    }
  }

  // This is some business logic, don't care about it.
  function updateRawData() {
    var flightData = _rawData.flight.data;
    var movingItem = flightData[_draggingRecord.dataIndex];

    // Check conflict
    for (var i = 0; i < flightData.length; i++) {
      var dataItem = flightData[i];
      if (
        dataItem !== movingItem &&
        _dropRecord.categoryIndex === dataItem[DIM_CATEGORY_INDEX] &&
        _dropRecord.timeArrival < dataItem[DIM_TIME_DEPARTURE] &&
        _dropRecord.timeDeparture > dataItem[DIM_TIME_ARRIVAL]
      ) {
        alert('Conflict! Find a free space to settle the bar!');
        return;
      }
    }

    // No conflict.
    movingItem[DIM_CATEGORY_INDEX] = _dropRecord.categoryIndex;
    movingItem[DIM_TIME_ARRIVAL] = _dropRecord.timeArrival;
    movingItem[DIM_TIME_DEPARTURE] = _dropRecord.timeDeparture;
    return true;
  }

  function autoDataZoomWhenDraggingOutside(cursorX, cursorY) {
    // When cursor is outside the cartesian and being dragging,
    // auto move the dataZooms.
    var cursorDistX = getCursorCartesianDist(cursorX, _cartesianXBounds);
    var cursorDistY = getCursorCartesianDist(cursorY, _cartesianYBounds);

    if (cursorDistX !== 0 || cursorDistY !== 0) {
      _autoDataZoomAnimator.start({
        cursorDistX: cursorDistX,
        cursorDistY: cursorDistY
      });
    } else {
      _autoDataZoomAnimator.stop();
    }
  }

  function dispatchDataZoom(params) {
    var option = myChart.getOption();
    var optionInsideX = option.dataZoom[DATA_ZOOM_X_INSIDE_INDEX];
    var optionInsideY = option.dataZoom[DATA_ZOOM_Y_INSIDE_INDEX];
    var batch = [];

    prepareBatch(
      batch,
      'insideX',
      optionInsideX.start,
      optionInsideX.end,
      params.cursorDistX
    );
    prepareBatch(
      batch,
      'insideY',
      optionInsideY.start,
      optionInsideY.end,
      -params.cursorDistY
    );

    batch.length &&
      myChart.dispatchAction({
        type: 'dataZoom',
        batch: batch
      });

    function prepareBatch(batch, id, start, end, cursorDist) {
      if (cursorDist === 0) {
        return;
      }
      var sign = cursorDist / Math.abs(cursorDist);
      var size = end - start;
      var delta = DATA_ZOOM_AUTO_MOVE_SPEED * sign;

      start += delta;
      end += delta;

      if (end > 100) {
        end = 100;
        start = end - size;
      }
      if (start < 0) {
        start = 0;
        end = start + size;
      }
      batch.push({
        dataZoomId: id,
        start: start,
        end: end
      });
    }
  }

  function getCursorCartesianDist(cursorXY, bounds) {
    var dist0 = cursorXY - (bounds[0] + DATA_ZOOM_AUTO_MOVE_DETECT_AREA_WIDTH);
    var dist1 = cursorXY - (bounds[1] - DATA_ZOOM_AUTO_MOVE_DETECT_AREA_WIDTH);
    return dist0 * dist1 <= 0
      ? 0 // cursor is in cartesian
      : dist0 < 0
      ? dist0 // cursor is at left/top of cartesian
      : dist1; // cursor is at right/bottom of cartesian
  }

  function makeAnimator(callback) {
    var requestId;
    var callbackParams;
    // Use throttle to prevent from calling dispatchAction frequently.
    callback = echarts.throttle(callback, DATA_ZOOM_AUTO_MOVE_THROTTLE);

    function onFrame() {
      callback(callbackParams);
      requestId = requestAnimationFrame(onFrame);
    }

    return {
      start: function (params) {
        callbackParams = params;
        if (requestId == null) {
          onFrame();
        }
      },
      stop: function () {
        if (requestId != null) {
          cancelAnimationFrame(requestId);
        }
        requestId = callbackParams = null;
      }
    };
  }
}
"""#,
        option: [
            "tooltip": [:] as [String: Any],
            "animation": false,
            "toolbox": [
                "left": 20.0,
                "top": 0.0,
                "itemSize": 20.0,
                "feature": [
                    "myDrag": [
                        "show": true,
                        "title": "Make bars\ndraggable",
                        "icon": ganttDragToolboxIcon
                        // PORT-NOTE: toolbox.feature.myDrag.onclick omitted — the JS handler flipped the
                        // module-level `_draggable` flag, re-setOption'd `dataZoom: [{ id: 'insideX', disabled },
                        // { id: 'insideY', disabled }]` (so panning does not fight the drag) and called
                        // `this.model.setIconStatus(type, _draggable ? 'emphasis' : 'normal')` to light the icon up.
                        // It is the entry point of the whole drag layer (see the header) — web pane only.
                    ] as [String: Any]
                ] as [String: Any]
            ] as [String: Any],
            "title": [
                "text": "Gantt of Airport Flight",
                "left": "center"
            ] as [String: Any],
            "dataZoom": [
                [
                    "type": "slider",
                    "xAxisIndex": 0.0,
                    "filterMode": "weakFilter",
                    "height": 20.0,
                    "bottom": 0.0,
                    "start": 0.0,
                    "end": 26.0,
                    "handleIcon": ganttSliderHandleIcon,
                    "handleSize": "80%",
                    "showDetail": false
                ] as [String: Any],
                [
                    "type": "inside",
                    "id": "insideX",
                    "xAxisIndex": 0.0,
                    "filterMode": "weakFilter",
                    "start": 0.0,
                    "end": 26.0,
                    "zoomOnMouseWheel": false,
                    "moveOnMouseMove": true
                ] as [String: Any],
                [
                    "type": "slider",
                    "yAxisIndex": 0.0,
                    "zoomLock": true,
                    "width": 10.0,
                    "right": 10.0,
                    "top": 70.0,
                    "bottom": 20.0,
                    "start": 95.0,
                    "end": 100.0,
                    "handleSize": 0.0,
                    "showDetail": false
                ] as [String: Any],
                [
                    "type": "inside",
                    "id": "insideY",
                    "yAxisIndex": 0.0,
                    "start": 95.0,
                    "end": 100.0,
                    "zoomOnMouseWheel": false,
                    "moveOnMouseMove": true,
                    "moveOnMouseWheel": true
                ] as [String: Any]
            ],
            "grid": [
                "show": true,
                "top": 70.0,
                "bottom": 20.0,
                "left": 100.0,
                "right": 20.0,
                "backgroundColor": "#fff",
                "borderWidth": 0.0
            ] as [String: Any],
            "xAxis": [
                "type": "time",
                "position": "top",
                "splitLine": [
                    "lineStyle": ["color": ["#E9EDFF"]] as [String: Any]
                ] as [String: Any],
                "axisLine": ["show": false] as [String: Any],
                "axisTick": [
                    "lineStyle": ["color": "#929ABA"] as [String: Any]
                ] as [String: Any],
                "axisLabel": [
                    "color": "#929ABA",
                    "inside": false,
                    "align": "center"
                ] as [String: Any]
            ] as [String: Any],
            "yAxis": [
                "axisTick": ["show": false] as [String: Any],
                "splitLine": ["show": false] as [String: Any],
                "axisLine": ["show": false] as [String: Any],
                "axisLabel": ["show": false] as [String: Any],
                "min": 0.0,
                "max": ganttApronCount          // JS: _rawData.parkingApron.data.length (326)
            ] as [String: Any],
            "series": [
                [
                    "id": "flightData",
                    "type": "custom",
                    // PORT-NOTE: series[0].renderItem (`renderGanttItem`) omitted — the JS closure IS this chart.
                    // Per flight it read the apron index (dim 0) and projected both times with api.coord(), sized the
                    // bar with api.size([0, 1])[1] * 0.6, clipped three rects to params.coordSys via
                    // echarts.graphic.clipRectByRect(), and returned a `group` of: the full-length bar (api.style()),
                    // a half-length gold (#ddb30b) overlay shown only when the VIP flag (dim 4) is set, and a
                    // transparent rect carrying the flight number (dim 3) as white centred text — dropped when the bar
                    // is narrower than the label + 40px. It also cached the cartesian bounds for the drag layer.
                    // It is OMITTED rather than ported because of gaps (a)/(b)/(c) in the header — clipRectByRect
                    // is not ported, api.style() is a deferred stub, and the ec4 `text`/`textFill`-on-a-rect label
                    // is not honored — NOT because the option cannot hold a Swift `CustomSeriesRenderItem`.
                    "dimensions": ganttFlightDimensions,
                    "encode": [
                        "x": [1.0, 2.0],        // DIM_TIME_ARRIVAL, DIM_TIME_DEPARTURE
                        "y": 0.0,               // DIM_CATEGORY_INDEX
                        "tooltip": [0.0, 1.0, 2.0]
                    ] as [String: Any],
                    "data": ganttFlightData
                ] as [String: Any],
                [
                    "type": "custom",
                    // PORT-NOTE: series[1].renderItem (`renderAxisLabelItem`) omitted — this series IS the (fake)
                    // y-axis labels. Per apron it took the pixel y of api.coord([0, api.value(0)]), skipped rows
                    // scrolled above the grid (y < coordSys.y + 5), and returned a `group` at [10, y] holding the
                    // green (#368c6c) tag path 'M0,0 L0,-20 L30,-20 C42,-20 38,-1 50,-1 L70,-1 L70,0 Z' plus two
                    // texts: the apron Type (dim 1, white, inside the tag) and the Near-Bridge flag (dim 2, black,
                    // to its right). Omitted for header gaps (c)/(d): its group rides on the LEGACY transform prop
                    // `position: [10, y]` (updateElNormal copies only x/y/rotation/scale/origin, so every tag would
                    // land on the origin) and its texts use the ec4 `textVerticalAlign`/`textAlign`/`textFill` keys.
                    "dimensions": ganttApronDimensions,
                    "encode": [
                        "x": -1.0,              // Then this series will not controlled by x.
                        "y": 0.0
                    ] as [String: Any],
                    "data": ganttApronData      // JS: parkingApron.data.map((item, index) => [index].concat(item))
                ] as [String: Any]
            ]
        ])
}
