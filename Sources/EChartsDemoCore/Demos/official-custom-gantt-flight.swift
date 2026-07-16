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
//  - NATIVE PANE ON (nativeSupported: true): both `renderItem` closures ARE ported (renderGanttItem /
//    renderAxisLabelItem, below) statement for statement, riding on the series option under the "renderItem"
//    key exactly as official-custom-bar-trend.swift's does (CustomView resolves `customSeries.getRenderItem()`;
//    safe here because WebPage.swift only JSON-serializes `option` when `webOptionJS` is nil, and we set it).
//    Four framework gaps had to be worked around, none requiring a framework change:
//      (a) `echarts.graphic.clipRectByRect` is NOT ported to Swift at all — INLINED as `ganttClipRect` below
//          (x=max, x2=min, y=max, y2=min; nil unless x2>=x && y2>=y), byte-for-byte the upstream algorithm.
//      (b) `api.style()` is a DEFERRED best-effort stub (raw item-visual `style` bag + userProps merged, no
//          label/styleCompat) — for the plain bars this is exactly what upstream's `api.style()` normally
//          returns here too (there's no itemStyle/label on this series), so behavior matches.
//      (c) the ec4 legacy "text"/`textFill`/`textAlign`/`textVerticalAlign` embedded-in-shape-style compat is
//          DEFERRED (CustomView's `processTxInfo` is not ported), so `api.style({ text, textFill })` on the
//          flight-number RECT would not draw a label. Translated to an explicit `type: "text"` sibling child,
//          centered on the (clipped) label rect — the same centered-white-label upstream's ec4 compat produces.
//          The apron tag's two texts likewise use the ported style bridge's modern key names (`align` /
//          `verticalAlign`; `bridgeTextStyle` already understands `textFill` as an ec4-compat synonym of `fill`).
//      (d) `renderAxisLabelItem` places its group with the LEGACY transform prop `position: [10, y]`; the ported
//          static transform-apply (`applyUpdateTransitionStatic`) only reads the modern "x"/"y" keys (upstream's
//          own `LEGACY_TRANSFORM_PROPS_MAP` in customGraphicTransition.ts remaps `position` -> `[x, y]`), so the
//          group is returned with "x"/"y" directly instead — the same semantics, spelled the way the static
//          substitute understands.
//    STILL NOT reproduced natively (nothing to do with the renderItems): the drag-and-drop layer (below) and
//    `toolbox.feature.myDrag.onclick` — both are pure pointer-driven interaction, not part of a single rendered
//    frame; see the DRAG LAYER deviation below.
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
//    interaction, not a timeline.
//  - `toolbox.feature.myDrag.onclick` omitted from the native option — see the PORT-NOTE (it is the JS handler that
//    toggles `_draggable` and disables the two `inside` dataZooms).
import Foundation
import EChartsKit

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

// MARK: - the two upstream renderItems, ported

// JS: var HEIGHT_RATIO = 0.6; var DIM_CATEGORY_INDEX = 0; var DIM_TIME_ARRIVAL = 1; var DIM_TIME_DEPARTURE = 2;
private let ganttHeightRatio = 0.6
private let ganttDimCategoryIndex = 0.0
private let ganttDimTimeArrival = 1.0
private let ganttDimTimeDeparture = 2.0

// Coerce a ParsedValue (Any: Double | Int | NSNumber | Bool) to Double — the recurring Int/Bool-vs-Double
//   read trap. Bool -> 1/0 mirrors `number.numberCoerce` (which itself mirrors JS `Number(true) === 1`).
private func gtNum(_ v: Any?) -> Double {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let b = v as? Bool { return b ? 1 : 0 }
    if let n = v as? NSNumber { return n.doubleValue }
    return .nan
}
// JS `x + ''` string coercion — the flight-number / apron-name/type dims arrive as plain strings (ordinal
//   dims pass the raw value through unparsed); fall back to a numeric description for the rare non-string case.
private func gtStr(_ v: Any?) -> String {
    if let s = v as? String { return s }
    if let v = v { return "\(v)" }
    return ""
}

// upstream: function clipRectByRect(params, rect) { return echarts.graphic.clipRectByRect(rect, {x:
//   params.coordSys.x, y: params.coordSys.y, width: params.coordSys.width, height: params.coordSys.height}); }
//   `echarts.graphic.clipRectByRect` itself (util/graphic.ts) is not ported to Swift — inlined verbatim here.
private func ganttClipRectByRect(
    _ x: Double, _ y: Double, _ width: Double, _ height: Double,
    _ coordX: Double, _ coordY: Double, _ coordWidth: Double, _ coordHeight: Double
) -> [String: Any]? {
    let cx = max(x, coordX)
    let cx2 = min(x + width, coordX + coordWidth)
    let cy = max(y, coordY)
    let cy2 = min(y + height, coordY + coordHeight)
    // If the total rect is clipped, nothing, including the border, should be painted. So return nil.
    if cx2 >= cx && cy2 >= cy {
        return ["x": cx, "y": cy, "width": cx2 - cx, "height": cy2 - cy]
    }
    return nil
}

// upstream: function renderGanttItem(params, api) { ... } — one clipped bar per flight, statement for
//   statement. Typed EXACTLY `CustomSeriesRenderItem` so CustomView's `get("renderItem") as?
//   CustomSeriesRenderItem` cast holds (see header).
//
// DEVIATION (header gap (c)): the third rect's `api.style({ fill: 'transparent', stroke: 'transparent',
//   text: text, textFill: '#fff' })` relies on the ec4 legacy "text on shape" compat (CustomView's
//   `processTxInfo`), which is DEFERRED — a rect never grows an attached label from its style bag in this
//   port. The rect is still returned (transparent, so invisible either way), and an explicit `type: "text"`
//   sibling — centered on the same clipped rect, matching upstream's default centered/inside label
//   placement — carries the flight number instead.
private let renderGanttItem: CustomSeriesRenderItem = { params, api in
    let categoryIndex = gtNum(api.value(ganttDimCategoryIndex, nil))
    let timeArrival = api.coord([gtNum(api.value(ganttDimTimeArrival, nil)), categoryIndex], nil)
    let timeDeparture = api.coord([gtNum(api.value(ganttDimTimeDeparture, nil)), categoryIndex], nil)
    guard timeArrival.count >= 2, timeDeparture.count >= 2 else { return nil }

    // var coordSys = params.coordSys; _cartesianXBounds/_cartesianYBounds — drag-layer bookkeeping, web-pane
    //   only (see header DRAG LAYER deviation); the cartesian rect itself is still needed for clipping below.
    let coordX = (params.coordSys.extra["x"] as? Double) ?? 0
    let coordY = (params.coordSys.extra["y"] as? Double) ?? 0
    let coordWidth = (params.coordSys.extra["width"] as? Double) ?? 0
    let coordHeight = (params.coordSys.extra["height"] as? Double) ?? 0

    let barLength = timeDeparture[0] - timeArrival[0]
    // Get the height corresponds to length 1 on y axis.
    let sizeArr = (api.size([0.0, 1.0], nil) as? [Double]) ?? [0, 0]
    let barHeight = (sizeArr.count > 1 ? sizeArr[1] : 0) * ganttHeightRatio
    let x = timeArrival[0]
    let y = timeArrival[1] - barHeight

    let flightNumber = gtStr(api.value(3.0, nil))
    let flightNumberWidth = format.getTextRect(flightNumber).width
    let text = (barLength > flightNumberWidth + 40 && x + barLength >= 180) ? flightNumber : ""

    let rectNormal = ganttClipRectByRect(x, y, barLength, barHeight, coordX, coordY, coordWidth, coordHeight)
    let rectVIP = ganttClipRectByRect(x, y, barLength / 2, barHeight, coordX, coordY, coordWidth, coordHeight)
    let rectText = ganttClipRectByRect(x, y, barLength, barHeight, coordX, coordY, coordWidth, coordHeight)

    let vipFlag = gtNum(api.value(4.0, nil)) != 0   // JS: !!api.value(4)

    var normalChild: [String: Any] = [
        "type": "rect",
        "ignore": rectNormal == nil,          // JS: ignore: !rectNormal
        "style": api.style(nil, nil)          // JS: api.style()
    ]
    if let rectNormal = rectNormal { normalChild["shape"] = rectNormal }

    var vipChild: [String: Any] = [
        "type": "rect",
        // JS: ignore: !rectVIP && !api.value(4) — faithfully kept as-is (only ignored when BOTH the clip
        //   emptied out AND the flight is not VIP; a non-VIP flight with a non-empty clip still shows through).
        "ignore": (rectVIP == nil) && !vipFlag,
        "style": api.style(["fill": "#ddb30b"], nil)
    ]
    if let rectVIP = rectVIP { vipChild["shape"] = rectVIP }

    var rectTextChild: [String: Any] = [
        "type": "rect",
        "ignore": rectText == nil,            // JS: ignore: !rectText
        "style": api.style([
            "fill": "transparent",
            "stroke": "transparent",
            "text": text,
            "textFill": "#fff"
        ] as [String: Any], nil)
    ]
    if let rectText = rectText { rectTextChild["shape"] = rectText }

    // See the DEVIATION note above: the explicit text sibling standing in for the ec4 text-on-rect compat.
    var labelChild: [String: Any] = [
        "type": "text",
        "ignore": rectText == nil || text.isEmpty,
        "style": ["fill": "#fff", "align": "center", "verticalAlign": "middle"] as [String: Any]
    ]
    if let rectText = rectText {
        let rx = (rectText["x"] as? Double) ?? 0
        let ry = (rectText["y"] as? Double) ?? 0
        let rw = (rectText["width"] as? Double) ?? 0
        let rh = (rectText["height"] as? Double) ?? 0
        labelChild["style"] = [
            "text": text,
            "fill": "#fff",
            "align": "center",
            "verticalAlign": "middle",
            "x": rx + rw / 2,
            "y": ry + rh / 2
        ] as [String: Any]
    }

    return [
        "type": "group",
        "children": [normalChild, vipChild, rectTextChild, labelChild]
    ] as [String: Any]
}

// upstream: function renderAxisLabelItem(params, api) { ... } — the fake y-axis apron tag, statement for
//   statement. Typed EXACTLY `CustomSeriesRenderItem`.
//
// DEVIATION (header gap (d)): upstream returns the group at the LEGACY `position: [10, y]`; the ported
//   static transform-apply only reads the modern "x"/"y" transform keys (upstream's own
//   `LEGACY_TRANSFORM_PROPS_MAP` remaps `position` -> `[x, y]` inside the DEFERRED `applyUpdateTransition`),
//   so "x"/"y" are written directly instead — the identical semantics.
// DEVIATION (header gap (c)): the two texts' ec4 `textAlign`/`textVerticalAlign` keys are translated to the
//   ported style bridge's modern `align`/`verticalAlign` keys; `textFill` itself IS already honored by
//   `bridgeTextStyle` as an ec4-compat synonym of `fill` and is kept as-is.
private let renderAxisLabelItem: CustomSeriesRenderItem = { params, api in
    let apronIndex = gtNum(api.value(0.0, nil))
    let yCoord = api.coord([0.0, apronIndex], nil)
    guard yCoord.count >= 2 else { return nil }
    let y = yCoord[1]

    let coordY = (params.coordSys.extra["y"] as? Double) ?? 0
    if y < coordY + 5 {
        return nil   // JS: if (y < params.coordSys.y + 5) { return; }
    }

    // dim 1 = apron Name (e.g. 'AB94'), dim 2 = apron Type (e.g. 'W') — column layout is
    //   `[index].concat(item)` where item = [Name, Type, Near Bridge]; api.value reads by column INDEX, so
    //   the mismatched `dimensions: ['Name', 'Type', 'Near Bridge']` labels (which describe columns 0..2,
    //   NOT the actual index-prepended columns 0..3) don't affect which raw values dims 1/2 read.
    let apronName = gtStr(api.value(1.0, nil))
    let apronType = gtStr(api.value(2.0, nil))

    let pathChild: [String: Any] = [
        "type": "path",
        "shape": [
            "d": "M0,0 L0,-20 L30,-20 C42,-20 38,-1 50,-1 L70,-1 L70,0 Z",
            "x": 0.0,
            "y": -20.0,
            "width": 90.0,
            "height": 20.0,
            "layout": "cover"
        ] as [String: Any],
        "style": ["fill": "#368c6c"] as [String: Any]
    ]
    let nameTextChild: [String: Any] = [
        "type": "text",
        "style": [
            "x": 24.0,
            "y": -3.0,
            "text": apronName,
            "verticalAlign": "bottom",     // ec4: textVerticalAlign
            "align": "center",             // ec4: textAlign
            "fill": "#fff"                 // ec4: textFill (already honored as-is too)
        ] as [String: Any]
    ]
    let typeTextChild: [String: Any] = [
        "type": "text",
        "style": [
            "x": 75.0,
            "y": -2.0,
            "verticalAlign": "bottom",
            "align": "center",
            "text": apronType,
            "fill": "#000"
        ] as [String: Any]
    ]

    return [
        "type": "group",
        "x": 10.0,   // JS: position: [10, y] — see the DEVIATION note above.
        "y": y,
        "children": [pathChild, nameTextChild, typeTextChild]
    ] as [String: Any]
}

extension EChartsDemoRegistry {
    static let official_custom_gantt_flight = EChartsDemo(
        name: "official-custom-gantt-flight", category: "custom",
        summary: "机场航班甘特图 — Gantt Chart of Airport Flights",
        width: 720, height: 460,
        nativeSupported: true,   // both renderItems ARE ported (renderGanttItem / renderAxisLabelItem) — see the header.
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
                    // renderGanttItem, ported statement for statement (see MARK above) — riding on the option
                    // under "renderItem" exactly like official-custom-bar-trend.swift's does.
                    "renderItem": renderGanttItem,
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
                    // renderAxisLabelItem, ported statement for statement (see MARK above). Per apron it takes
                    // the pixel y of api.coord([0, api.value(0)]), skips rows scrolled above the grid (y <
                    // coordSys.y + 5), and returns a group at (10, y) holding the green (#368c6c) tag path
                    // 'M0,0 L0,-20 L30,-20 C42,-20 38,-1 50,-1 L70,-1 L70,0 Z' plus two texts: the apron Name
                    // (dim 1, white, inside the tag) and the apron Type (dim 2, black, to its right).
                    "renderItem": renderAxisLabelItem,
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
