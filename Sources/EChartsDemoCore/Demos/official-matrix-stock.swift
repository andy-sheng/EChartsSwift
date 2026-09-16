// official-matrix-stock — replica of https://echarts.apache.org/examples/zh/editor.html?c=matrix-stock
// title: Matrix Stock Application / titleCN: 股市矩阵图
// A trading terminal laid out on the MATRIX coordinate system: five `grid`s pinned to matrix cells
// (`coordinateSystem: 'matrix'`, `coord: [x, y]`, `mergeCells`) hold an intraday price line + VWAP on a
// `time` axis with a lunch `breaks` gap (11:30–13:00 collapsed, `gap: 0`), a coloured Volume bar row, a
// MACD histogram + DIF/DEA lines, a horizontal Order Book bar with `rich` bid/ask labels, and a stepped
// Depth area. Four `coordinateSystem: 'matrix'` titles label the panes; `markPoint` entries with
// `relativeTo: 'coordinate'` pin the price scale (+2.76% / 50.00 / −2.76%) to the price grid's corners;
// six `graphic` line elements draw the matrix rules.
//
// DEVIATIONS from the official source:
//   - RNG SEEDED. The example synthesises its whole dataset from `Math.random()`, so each run — and each
//     pane — would show DIFFERENT prices, making a native↔web diff (the entire point of this gallery)
//     meaningless and the headless snapshot non-deterministic. Both panes therefore draw from the same
//     seeded mulberry32 (`rnd()`, seed 20251016) in place of `Math.random()`; the Swift side reproduces
//     the identical uint32 PRNG and the identical generation code, so the two panes carry BIT-IDENTICAL
//     data (verified: price/volume/VWAP/MACD/order/depth arrays match to the last digit). Nothing else
//     about the data pipeline is changed — the same walk, EMA/MACD/DEA maths, order book and cumulative
//     depth run on both sides.
//   - TypeScript-only syntax dropped (a classic script cannot parse it): the `: number` / `: number[][]`
//     parameter and variable annotations, `as const`, and `as 'dashed' | false`.
//   - Nothing else. Every series, axis, grid, matrix cell, title, markPoint, rich label and graphic
//     element of the official option is carried by BOTH panes. The example is static (no timers, no
//     `myChart` interaction beyond `getWidth()`/`getHeight()`), so there is no `drive` timeline.
//   - The option contains NO JS closures: `priceFormatter` / `getPriceColor` / `Array.from` / `.map`
//     all evaluate to plain values before `option` is assigned, so the Swift port carries the option in
//     full — no note omissions.
import Foundation

// MARK: - deterministic RNG + the example's JS number semantics

/// mulberry32 — the seeded stand-in for `Math.random()`. Uint32 wrapping arithmetic, bit-identical to
/// the `Math.imul` version spliced into `webOptionJS`, so both panes generate the same sequence.
private struct MatrixStockRNG {
    private var a: UInt32
    init(seed: UInt32) { a = seed }
    mutating func next() -> Double {
        a = a &+ 0x6D2B_79F5
        var t = (a ^ (a >> 15)) &* (a | 1)
        t = (t &+ ((t ^ (t >> 7)) &* (t | 61))) ^ t
        return Double(t ^ (t >> 14)) / 4_294_967_296.0
    }
}

/// JS `Math.round` — half UP (toward +∞), not Swift's half-away-from-zero.
private func matrixStockJSRound(_ x: Double) -> Double { (x + 0.5).rounded(.down) }

/// JS `Number → String`: shortest round-trip, and integers print WITHOUT a `.0` (`50`, not `50.0`).
private func matrixStockJSNum(_ v: Double) -> String {
    if v == v.rounded() && abs(v) < 1e15 { return String(Int64(v)) }
    return "\(v)"
}

/// The example's `priceFormatter`: round to 2dp, then pad the decimals back out to two.
private func matrixStockPriceFormatter(_ value: Double) -> String {
    let result = matrixStockJSNum(matrixStockJSRound(value * 100) / 100)
    guard let dot = result.firstIndex(of: ".") else { return result + ".00" }
    if result.distance(from: result.startIndex, to: dot) == result.count - 2 { return result + "0" }
    return result
}

/// The example's `getPriceColor`.
private func matrixStockPriceColor(_ price: Double) -> String {
    price == matrixStockLastClose ? matrixStockGray
        : (price > matrixStockLastClose ? matrixStockRed : matrixStockGreen)
}

/// `new Date('2025-10-16 hh:mm:00').getTime()` — parsed in the LOCAL zone, exactly as JS does.
private func matrixStockEpochMS(_ hour: Int, _ minute: Int) -> Double {
    var c = DateComponents()
    c.year = 2025; c.month = 10; c.day = 16; c.hour = hour; c.minute = minute; c.second = 0
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone.current
    let d = cal.date(from: c) ?? Date(timeIntervalSince1970: 0)
    return (d.timeIntervalSince1970 * 1000).rounded()
}

private let matrixStockLastClose = 50.0                             // Close value of yesterday
private let matrixStockGreen = "#47b262"
private let matrixStockRed = "#eb5454"
private let matrixStockGray = "#888"
private let matrixStockGreenOpacity = "rgba(71, 178, 98, 0.2)"
private let matrixStockRedOpacity = "rgba(235, 84, 84, 0.2)"

private let matrixStockMargin = 10.0
private let matrixStockChartWidth = 720.0                           // myChart.getWidth()
private let matrixStockChartHeight = 460.0                          // myChart.getHeight()
private let matrixStockWidth = matrixStockChartWidth - matrixStockMargin * 2
private let matrixStockHeight = matrixStockChartHeight - matrixStockMargin * 2

// MARK: - the example's synthetic dataset (same code, same seed, same numbers as the web pane)

private struct MatrixStockDataset {
    var priceData: [[Double]] = []            // [time, price]
    var volumeSeriesData: [[String: Any]] = []// { value: [time, volume], itemStyle: { color } }
    var averageData: [[Double]] = []          // volume weighted average price
    var macdData: [[String: Any]] = []        // MACD histogram, coloured per bar
    var macdLineData: [[Double]] = []         // DIF
    var signalLineData: [[Double]] = []       // DEA
    var orderData: [[String: Any]] = []       // order book (rich bid/ask labels)
    var depthHighData: [Any] = []             // sparse: 0..<20 are holes (NSNull), 20..<40 cumulative
    var depthLowData: [Any] = []
    var maxAbs = 0.0
    var sumVolume = 0.0
    var breakStartTime = 0.0
    var breakEndTime = 0.0
}

private let matrixStock: MatrixStockDataset = {
    var out = MatrixStockDataset()
    var rng = MatrixStockRNG(seed: 20251016)

    var sumPrice = 0.0
    let sTime = matrixStockEpochMS(9, 30)
    let eTime = matrixStockEpochMS(15, 0)
    let breakStartTime = matrixStockEpochMS(11, 30)
    let breakEndTime = matrixStockEpochMS(13, 0)
    out.breakStartTime = breakStartTime
    out.breakEndTime = breakEndTime

    // MACD algorithm parameters
    let shortPeriod = 12, longPeriod = 26, signalPeriod = 9

    var volumeData: [[Double]] = []
    var time = sTime
    var price = 0.0
    var direction = 1.0                                             // 1 for up, -1 for down
    while time < eTime {
        let volume = rng.next() * 1000 + 500
        volumeData.append([time, volume])
        out.sumVolume += volume

        if time == sTime {                                          // Today open price
            direction = rng.next() < 0.5 ? 1 : -1
            price = matrixStockLastClose * (1 + (rng.next() - 0.5) * 0.02)
        } else {                                                    // 80% chance to keep direction
            direction = rng.next() < 0.8 ? direction : -direction
            price = matrixStockJSRound((price + direction * (rng.next() * 0.1)) * 100) / 100
        }
        out.priceData.append([time, price])

        sumPrice += price * volume
        out.averageData.append([time, sumPrice / out.sumVolume])

        out.maxAbs = Swift.max(out.maxAbs, abs(price - matrixStockLastClose))

        if time == breakStartTime { time = breakEndTime } else { time += 60 * 1000 }
    }

    // 1. Exponential Moving Average
    func calculateEMA(_ prices: [[Double]], _ period: Int) -> [[Double]] {
        var ema: [[Double]] = []
        let k = 2 / (Double(period) + 1)
        if prices.count >= period {
            var sum = 0.0
            for i in 0..<period { sum += prices[i][1] }
            ema.append([prices[period - 1][0], sum / Double(period)])   // first EMA = SMA
            for i in period..<prices.count {
                let newEMA = prices[i][1] * k + ema[ema.count - 1][1] * (1 - k)
                ema.append([prices[i][0], newEMA])
            }
        }
        return ema
    }

    // 2. MACD = DIF (short EMA − long EMA), DEA (EMA of DIF), histogram (DIF − DEA)
    if out.priceData.count >= longPeriod {
        let shortEMA = calculateEMA(out.priceData, shortPeriod)
        let longEMA = calculateEMA(out.priceData, longPeriod)
        var shortEMAMap: [Double: Double] = [:]
        for it in shortEMA { shortEMAMap[it[0]] = it[1] }
        var longEMAMap: [Double: Double] = [:]
        for it in longEMA { longEMAMap[it[0]] = it[1] }

        var macdLine: [[Double]] = []
        for i in (longPeriod - 1)..<out.priceData.count {
            let t = out.priceData[i][0]
            if let s = shortEMAMap[t], let l = longEMAMap[t] { macdLine.append([t, s - l]) }
        }
        let signalLine = calculateEMA(macdLine, signalPeriod)
        if !signalLine.isEmpty {
            var macdMap: [Double: Double] = [:]
            for it in macdLine { macdMap[it[0]] = it[1] }
            var signalMap: [Double: Double] = [:]
            for it in signalLine { signalMap[it[0]] = it[1] }
            var commonTimestamps: [Double] = []
            for t in macdMap.keys where signalMap[t] != nil { commonTimestamps.append(t) }
            commonTimestamps.sort()
            for t in commonTimestamps {
                let macdValue = macdMap[t]!, signalValue = signalMap[t]!
                out.macdLineData.append([t, macdValue])
                out.signalLineData.append([t, signalValue])
                let histogram = macdValue - signalValue
                out.macdData.append([
                    "value": [t, histogram] as [Any],
                    "itemStyle": ["color": histogram > 0 ? matrixStockRed : matrixStockGreen] as [String: Any]
                ] as [String: Any])
            }
        }
    }

    // Order book: 10 levels straddling the last price, bids green / asks red.
    let orderCount = 10
    var orderPrice = price - (0.01 * Double(orderCount)) / 2
    for _ in 0..<orderCount {
        if price == orderPrice { continue }
        orderPrice += 0.01
        let amount = matrixStockJSRound(rng.next() * 200) + 10
        let isLower = orderPrice < price
        let tag = isLower ? "green" : "red"
        out.orderData.append([
            "value": amount,
            "itemStyle": ["color": isLower ? matrixStockGreenOpacity : matrixStockRedOpacity] as [String: Any],
            "label": [
                "formatter": "{name|\(isLower ? "Bid" : "Ask")} "
                    + "{\(tag)|\(matrixStockPriceFormatter(orderPrice))} "
                    + "{amount|(\(matrixStockJSNum(amount)))}",
                "rich": [
                    "red": ["color": matrixStockRed] as [String: Any],
                    "green": ["color": matrixStockGreen] as [String: Any],
                    "amount": ["color": "#666"] as [String: Any],
                    "name": ["fontWeight": "bold", "color": "#444"] as [String: Any]
                ] as [String: Any]
            ] as [String: Any]
        ] as [String: Any])
    }

    // Depth: cumulative asks in the upper half of the 40 categories, cumulative bids in the lower half.
    // Upstream builds SPARSE arrays (`depthHighData[20 + i] = ...`), so slots 0..<20 of depthHighData
    // read back as `undefined` — NSNull() is the Swift stand-in for those holes.
    let depthCount = 20
    out.depthHighData = Array(repeating: NSNull(), count: depthCount * 2)
    out.depthLowData = Array(repeating: NSNull(), count: depthCount)
    var cumulativeHighVolume = 0.0
    var cumulativeLowVolume = 0.0
    for i in 0..<depthCount {
        out.depthHighData[depthCount + i] = cumulativeHighVolume
        cumulativeHighVolume += matrixStockJSRound(rng.next() * 1000)
        out.depthLowData[depthCount - i - 1] = cumulativeLowVolume
        cumulativeLowVolume += matrixStockJSRound(rng.next() * 1000)
    }

    // Volume bars, coloured by the tick direction of the price they sit under.
    for (index, item) in volumeData.enumerated() {
        var color = matrixStockGray
        if index > 0 {
            color = out.priceData[index][1] > out.priceData[index - 1][1] ? matrixStockRed : matrixStockGreen
        }
        out.volumeSeriesData.append([
            "value": [item[0], item[1]] as [Any],
            "itemStyle": ["color": color] as [String: Any]
        ] as [String: Any])
    }

    return out
}()

// MARK: - option pieces

/// `getTitle(text, subtext, coord)` — a title pinned to a matrix cell.
private func matrixStockTitle(_ text: String, _ subtext: String, _ coord: [Double]) -> [String: Any] {
    [
        "text": text,
        "subtext": subtext,
        "left": 2.0, "top": 2.0, "padding": 0.0,
        "textStyle": ["fontSize": 12.0, "fontWeight": "bold", "color": "#444"] as [String: Any],
        "subtextStyle": ["fontSize": 10.0, "color": "#666"] as [String: Any],
        "itemGap": 0.0,
        "coordinateSystem": "matrix",
        "coord": coord as [Any]
    ]
}

private let matrixStockTitles: [[String: Any]] = [
    matrixStockTitle("Volume", matrixStockJSNum(matrixStockJSRound(matrixStock.sumVolume / 1000)) + "B", [0, 5]),
    matrixStockTitle("MACD", "", [0, 4]),
    matrixStockTitle("Order Book", "", [4, 0]),
    matrixStockTitle("Depth", "", [4, 5])
]

/// The lunch break shared by the three time axes (11:30 → 13:00 collapsed to zero width).
private let matrixStockBreaks: [Any] = [
    ["start": matrixStock.breakStartTime, "end": matrixStock.breakEndTime, "gap": 0.0] as [String: Any]
]

/// The six matrix rules: 3 horizontals across the price/volume/MACD column (the middle one dashed, the
/// last-close line), 3 verticals splitting the 5 matrix columns.
private let matrixStockGraphicElements: [[String: Any]] = {
    var els: [[String: Any]] = []
    for i in 0..<3 {
        let lineWidth = 1.0
        els.append([
            "type": "line",
            "shape": [
                "x1": matrixStockMargin + lineWidth,
                "y1": (matrixStockHeight / 6) * Double(i + 1),
                "x2": (matrixStockWidth / 5) * 4 + matrixStockMargin,
                "y2": (matrixStockHeight / 6) * Double(i + 1)
            ] as [String: Any],
            "style": [
                "stroke": i == 1 ? "#bbb" : "#eee",
                "lineWidth": lineWidth,
                "lineDash": i == 1 ? "dashed" : false
            ] as [String: Any]
        ] as [String: Any])
    }
    for i in 0..<3 {
        let lineWidth = 1.0
        els.append([
            "type": "line",
            "shape": [
                "x1": (matrixStockWidth / 5) * Double(i + 1) + matrixStockMargin,
                "y1": matrixStockMargin + lineWidth,
                "x2": (matrixStockWidth / 5) * Double(i + 1) + matrixStockMargin,
                "y2": matrixStockChartHeight - matrixStockMargin
            ] as [String: Any],
            "style": [
                "stroke": "#eee",
                "lineDash": false,
                "lineWidth": lineWidth
            ] as [String: Any]
        ] as [String: Any])
    }
    return els
}()

/// The price scale + change-% pinned to the price grid's corners (`relativeTo: 'coordinate'`).
private let matrixStockMarkPointData: [[String: Any]] = {
    let hi = matrixStockLastClose + matrixStock.maxAbs
    let lo = matrixStockLastClose - matrixStock.maxAbs
    let pct = matrixStockPriceFormatter((matrixStock.maxAbs / matrixStockLastClose) * 100) + "%"
    return [
        ["relativeTo": "coordinate", "x": 0.0, "y": 0.0, "name": "max", "type": "max",
         "label": ["align": "left", "verticalAlign": "top",
                   "formatter": matrixStockPriceFormatter(hi),
                   "color": matrixStockPriceColor(hi)] as [String: Any]] as [String: Any],
        ["relativeTo": "coordinate", "x": 0.0, "y": "50%", "name": matrixStockJSNum(matrixStockLastClose),
         "label": ["align": "left", "verticalAlign": "middle",
                   "formatter": matrixStockPriceFormatter(matrixStockLastClose),
                   "color": matrixStockPriceColor(matrixStockLastClose)] as [String: Any]] as [String: Any],
        ["relativeTo": "coordinate", "x": 0.0, "y": "100%", "name": "min", "type": "min",
         "label": ["align": "left", "verticalAlign": "bottom",
                   "formatter": matrixStockPriceFormatter(lo),
                   "color": matrixStockPriceColor(lo)] as [String: Any]] as [String: Any],
        ["relativeTo": "coordinate", "x": "100%", "y": 0.0, "name": pct,
         "label": ["align": "right", "verticalAlign": "top",
                   "color": matrixStockRed, "formatter": "{b}"] as [String: Any]] as [String: Any],
        ["relativeTo": "coordinate", "x": "100%", "y": "50%", "name": "0%",
         "label": ["align": "right", "verticalAlign": "middle",
                   "color": matrixStockGray, "formatter": "{b}"] as [String: Any]] as [String: Any],
        ["relativeTo": "coordinate", "x": "100%", "y": "100%", "name": "-" + pct,
         "label": ["align": "right", "verticalAlign": "bottom",
                   "color": matrixStockGreen, "formatter": "{b}"] as [String: Any]] as [String: Any]
    ]
}()

private let matrixStockDepthCategories: [Any] = (0..<40).map { String($0) }

private let matrixStockOption: [String: Any] = [
    "title": matrixStockTitles as [Any],
    "xAxis": [
        ["type": "time", "show": false, "breaks": matrixStockBreaks] as [String: Any],
        ["type": "time", "gridIndex": 1.0, "show": false, "breaks": matrixStockBreaks] as [String: Any],
        ["type": "time", "gridIndex": 2.0, "show": false, "breaks": matrixStockBreaks] as [String: Any],
        ["type": "value", "gridIndex": 3.0, "show": false, "max": "dataMax"] as [String: Any],
        ["type": "category", "gridIndex": 4.0, "show": false, "boundaryGap": false,
         "data": matrixStockDepthCategories] as [String: Any]
    ] as [Any],
    "yAxis": [
        // Value should be symmetric around zero
        ["type": "value", "show": false,
         "min": matrixStockLastClose - matrixStock.maxAbs,
         "max": matrixStockLastClose + matrixStock.maxAbs] as [String: Any],
        ["type": "value", "gridIndex": 1.0, "show": false] as [String: Any],
        ["type": "value", "gridIndex": 2.0, "show": false] as [String: Any],
        ["type": "category", "gridIndex": 3.0, "show": false] as [String: Any],
        ["type": "value", "gridIndex": 4.0, "show": false, "max": "dataMax", "min": "dataMin"] as [String: Any]
    ] as [Any],
    "grid": [
        ["coordinateSystem": "matrix", "coord": [0.0, 0.0] as [Any],
         "top": 0.0, "bottom": 0.0, "left": 0.0, "right": 0.0] as [String: Any],
        ["coordinateSystem": "matrix", "coord": [0.0, 5.0] as [Any],
         "top": 20.0, "bottom": 0.0, "left": 0.0, "right": 0.0] as [String: Any],
        ["coordinateSystem": "matrix", "coord": [0.0, 4.0] as [Any],
         "top": 20.0, "bottom": 0.0, "left": 0.0, "right": 0.0] as [String: Any],
        ["coordinateSystem": "matrix", "coord": [4.0, 0.0] as [Any],
         "top": 15.0, "bottom": 2.0, "left": 2.0, "right": 2.0] as [String: Any],
        ["coordinateSystem": "matrix", "coord": [4.0, 4.0] as [Any],
         "top": 15.0, "bottom": 0.0, "left": 0.0, "right": 0.0] as [String: Any]
    ] as [Any],
    "series": [
        ["type": "line", "symbolSize": 0.0, "data": matrixStock.priceData as [Any],
         "markPoint": ["symbolSize": 0.0, "symbol": "circle",
                       "data": matrixStockMarkPointData as [Any]] as [String: Any]] as [String: Any],
        ["type": "line", "symbolSize": 0.0, "data": matrixStock.averageData as [Any],
         "xAxisIndex": 0.0, "yAxisIndex": 0.0] as [String: Any],
        ["type": "line", "symbolSize": 0.0, "data": matrixStock.averageData as [Any],
         "xAxisIndex": 0.0, "yAxisIndex": 0.0,
         "lineStyle": ["color": "#FFC458", "width": 1.0] as [String: Any]] as [String: Any],
        ["name": "Volume", "type": "bar", "xAxisIndex": 1.0, "yAxisIndex": 1.0,
         "data": matrixStock.volumeSeriesData as [Any]] as [String: Any],
        ["name": "MACD", "type": "bar", "xAxisIndex": 2.0, "yAxisIndex": 2.0,
         "data": matrixStock.macdData as [Any],
         "barWidth": "70%"] as [String: Any],                     // 70% of the coordinate area
        ["name": "DIF", "type": "line", "xAxisIndex": 2.0, "yAxisIndex": 2.0,
         "data": matrixStock.macdLineData as [Any],
         "lineStyle": ["color": "#FFC458", "width": 1.0] as [String: Any],
         "symbol": "none"] as [String: Any],
        ["name": "DEA", "type": "line", "xAxisIndex": 2.0, "yAxisIndex": 2.0,
         "data": matrixStock.signalLineData as [Any],
         "lineStyle": ["color": "#333", "width": 1.0] as [String: Any],
         "symbol": "none"] as [String: Any],
        ["name": "Order Book", "type": "bar", "xAxisIndex": 3.0, "yAxisIndex": 3.0,
         "data": matrixStock.orderData as [Any], "barWidth": "90%",
         "label": ["show": true, "position": "insideLeft"] as [String: Any]] as [String: Any],
        ["name": "Depth High", "type": "line", "xAxisIndex": 4.0, "yAxisIndex": 4.0,
         "data": matrixStock.depthHighData, "step": "end",
         "lineStyle": ["color": matrixStockRed, "width": 2.0] as [String: Any],
         "areaStyle": ["color": matrixStockRedOpacity, "opacity": 1.0] as [String: Any],
         "symbol": "none"] as [String: Any],
        ["name": "Depth Low", "type": "line", "xAxisIndex": 4.0, "yAxisIndex": 4.0,
         "data": matrixStock.depthLowData, "step": "end",
         "lineStyle": ["color": matrixStockGreen, "width": 2.0] as [String: Any],
         "areaStyle": ["color": matrixStockGreenOpacity, "opacity": 1.0] as [String: Any],
         "symbol": "none"] as [String: Any]
    ] as [Any],
    "matrix": [
        "left": matrixStockMargin, "right": matrixStockMargin,
        "top": matrixStockMargin, "bottom": matrixStockMargin,
        "x": ["show": false, "data": Array(repeating: NSNull(), count: 5) as [Any]] as [String: Any],
        "y": ["show": false, "data": Array(repeating: NSNull(), count: 6) as [Any]] as [String: Any],
        "body": [
            "data": [
                ["coord": [[0.0, 3.0], [0.0, 3.0]] as [Any], "mergeCells": true] as [String: Any],
                ["coord": [[0.0, 3.0], [5.0, 5.0]] as [Any], "mergeCells": true] as [String: Any],
                ["coord": [[0.0, 3.0], [4.0, 4.0]] as [Any], "mergeCells": true] as [String: Any],
                ["coord": [[4.0, 4.0], [0.0, 3.0]] as [Any], "mergeCells": true] as [String: Any],
                ["coord": [[4.0, 4.0], [4.0, 5.0]] as [Any], "mergeCells": true] as [String: Any]
            ] as [Any]
        ] as [String: Any]
    ] as [String: Any],
    "graphic": ["elements": matrixStockGraphicElements as [Any]] as [String: Any]
]

extension EChartsDemoRegistry {
    static let official_matrix_stock = EChartsDemo(
        name: "official-matrix-stock", category: "matrix",
        summary: "股市矩阵图 — Matrix Stock Application",
        width: 720, height: 460,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
// DEVIATION (see the Swift header): the official example seeds its dataset from Math.random(), which
// would give the two gallery panes different prices and make the snapshot non-deterministic. Both panes
// draw from this seeded mulberry32 instead; everything downstream of it is the example, unchanged.
function mulberry32(a) {
  return function () {
    a |= 0;
    a = (a + 0x6d2b79f5) | 0;
    var t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const rnd = mulberry32(20251016);

const lastClose = 50; // Close value of yesterday
const colorGreen = '#47b262';
const colorRed = '#eb5454';
const colorGray = '#888';
const colorGreenOpacity = 'rgba(71, 178, 98, 0.2)';
const colorRedOpacity = 'rgba(235, 84, 84, 0.2)';

const matrixMargin = 10;
const chartWidth = myChart.getWidth();
const chartHeight = myChart.getHeight();
const matrixWidth = chartWidth - matrixMargin * 2;
const matrixHeight = chartHeight - matrixMargin * 2;

const getPriceColor = (price) => {
  return price === lastClose
    ? colorGray
    : price > lastClose
    ? colorRed
    : colorGreen;
};
const priceFormatter = (value) => {
  const result = Math.round(value * 100) / 100 + '';
  // Adding padding 0 if needed
  let dotIndex = result.indexOf('.');
  if (dotIndex < 0) {
    return result + '.00';
  } else if (dotIndex === result.length - 2) {
    return result + '0';
  }
  return result;
};

const priceData = [];
const volumeData = [];
const averageData = []; // Volume weighted average price
const macdData = []; // MACD histogram data
const macdLineData = []; // MACD line (DIF) data
const signalLineData = []; // Signal line (DEA) data

let sumPrice = 0;
let sumVolume = 0;
const sTime = new Date('2025-10-16 09:30:00').getTime();
const eTime = new Date('2025-10-16 15:00:00').getTime();
const breakStartTime = new Date('2025-10-16 11:30:00').getTime();
const breakEndTime = new Date('2025-10-16 13:00:00').getTime();

// MACD algorithm parameters
const shortPeriod = 12; // Short-term EMA period, typically 12
const longPeriod = 26; // Long-term EMA period, typically 26
const signalPeriod = 9; // Signal line EMA period, typically 9

let time = sTime;
let price = 0;
let direction = 1; // 1 for up, -1 for down
let maxAbs = 0;
while (time < eTime) {
  const volume = rnd() * 1000 + 500;
  volumeData.push([time, volume]);
  sumVolume += volume;

  if (time === sTime) {
    // Today open price
    direction = rnd() < 0.5 ? 1 : -1;
    price = lastClose * (1 + (rnd() - 0.5) * 0.02);
  } else {
    // 70% chance to maintain the last direction
    direction = rnd() < 0.8 ? direction : -direction;
    price = Math.round((price + direction * (rnd() * 0.1)) * 100) / 100;
  }
  priceData.push([time, price]);

  sumPrice += price * volume;
  averageData.push([time, sumPrice / sumVolume]);

  maxAbs = Math.max(maxAbs, Math.abs(price - lastClose));

  if (time === breakStartTime) {
    time = breakEndTime;
  } else {
    time += 60 * 1000; // increment by 1 minute
  }
}

// Calculate MACD
// 1. Calculate Exponential Moving Average (EMA)
function calculateEMA(prices, period) {
  let ema = [];
  const k = 2 / (period + 1);

  // No special handling for small datasets
  // Just calculate EMA from the period point onwards

  // If we have enough data points
  if (prices.length >= period) {
    // Calculate first EMA using Simple Moving Average (SMA)
    let sum = 0;
    for (let i = 0; i < period; i++) {
      sum += prices[i][1];
    }
    const firstEMA = sum / period;

    // First EMA at the period point
    ema.push([prices[period - 1][0], firstEMA]);

    // Calculate subsequent EMAs
    for (let i = period; i < prices.length; i++) {
      const newEMA = prices[i][1] * k + ema[ema.length - 1][1] * (1 - k);
      ema.push([prices[i][0], newEMA]);
    }
  }

  return ema;
}

// Calculate MACD indicators
if (priceData.length >= longPeriod) {
  // Need at least longPeriod data points
  // Calculate short and long-term EMA
  const shortEMA = calculateEMA(priceData, shortPeriod);
  const longEMA = calculateEMA(priceData, longPeriod);

  // Calculate MACD line (DIF: Difference) for points where both EMAs are available
  const macdLine = [];

  // Find the earliest point where both EMAs are available
  // This should be at longPeriod-1
  let startIndex = longPeriod - 1;

  // Map EMA data to timestamps for easier lookup
  const shortEMAMap = new Map(shortEMA.map((item) => [item[0], item[1]]));
  const longEMAMap = new Map(longEMA.map((item) => [item[0], item[1]]));

  // Process data points starting from where both EMAs are available
  for (let i = startIndex; i < priceData.length; i++) {
    const time = priceData[i][0];

    // If we have both EMA values for this timestamp
    if (shortEMAMap.has(time) && longEMAMap.has(time)) {
      const diff = (shortEMAMap.get(time) || 0) - (longEMAMap.get(time) || 0);
      macdLine.push([time, diff]);
    }
  }

  // Calculate signal line (DEA: Signal Line) using standard EMA
  const signalLine = calculateEMA(macdLine, signalPeriod);

  // Clear existing data arrays
  macdLineData.length = 0;
  signalLineData.length = 0;
  macdData.length = 0;

  // Find common time range where both MACD and signal are available
  const startTimestamp = signalLine.length > 0 ? signalLine[0][0] : null;

  if (startTimestamp !== null) {
    // Create a map of MACD values by timestamp
    const macdMap = new Map();
    for (const item of macdLine) {
      macdMap.set(item[0], item[1]);
    }

    // Create a map of signal values by timestamp
    const signalMap = new Map();
    for (const item of signalLine) {
      signalMap.set(item[0], item[1]);
    }

    // Find all common timestamps between MACD and signal lines
    const commonTimestamps = [];
    for (const time of macdMap.keys()) {
      if (signalMap.has(time)) {
        commonTimestamps.push(time);
      }
    }

    // Sort timestamps to ensure correct order
    commonTimestamps.sort((a, b) => a - b);

    // Use only common timestamps for all three data series
    for (const time of commonTimestamps) {
      const macdValue = macdMap.get(time);
      const signalValue = signalMap.get(time);

      macdLineData.push([time, macdValue]);
      signalLineData.push([time, signalValue]);

      // Calculate histogram
      const histogram = macdValue - signalValue;

      // Determine color based on histogram value
      const color = histogram > 0 ? colorRed : colorGreen;

      macdData.push({
        value: [time, histogram],
        itemStyle: {
          color: color
        }
      });
    }
  }
}

const orderData = [];
const orderCat = [];
const orderCount = 10;
let orderPrice = price - (0.01 * orderCount) / 2;
for (let i = 0; i < orderCount; ++i) {
  if (price === orderPrice) {
    continue;
  }
  orderPrice += 0.01;
  orderCat.push(orderPrice);
  const amount = Math.round(rnd() * 200) + 10;
  const isLower = orderPrice < price;
  orderData.push({
    value: amount,
    itemStyle: {
      color: isLower ? colorGreenOpacity : colorRedOpacity
    },
    label: {
      formatter:
        `{name|${isLower ? 'Bid' : 'Ask'}} ` +
        `{${isLower ? 'green' : 'red'}|${priceFormatter(orderPrice)}} ` +
        `{amount|(${amount})}`,
      rich: {
        red: {
          color: colorRed
        },
        green: {
          color: colorGreen
        },
        amount: {
          color: '#666'
        },
        name: {
          fontWeight: 'bold',
          color: '#444'
        }
      }
    }
  });
}

const depthCount = 20;
const depthHighData = [];
const depthLowData = [];
let cumulativeHighVolume = 0;
let cumulativeLowVolume = 0;
for (let i = 0; i < depthCount; ++i) {
  depthHighData[depthCount + i] = cumulativeHighVolume;
  cumulativeHighVolume += Math.round(rnd() * 1000);

  depthLowData[depthCount - i - 1] = cumulativeLowVolume;
  cumulativeLowVolume += Math.round(rnd() * 1000);
}

const getTitle = (text, subtext, coord) => {
  return {
    text: text,
    subtext: subtext,
    left: 2,
    top: 2,
    padding: 0,
    textStyle: {
      fontSize: 12,
      fontWeight: 'bold',
      color: '#444'
    },
    subtextStyle: {
      fontSize: 10,
      color: '#666'
    },
    itemGap: 0,
    coordinateSystem: 'matrix',
    coord: coord
  };
};
const titles = [
  getTitle('Volume', Math.round(sumVolume / 1000) + 'B', [0, 5]),
  getTitle('MACD', '', [0, 4]),
  getTitle('Order Book', '', [4, 0]),
  getTitle('Depth', '', [4, 5])
];

option = {
  title: titles,
  xAxis: [
    {
      type: 'time',
      show: false,
      breaks: [
        {
          start: breakStartTime,
          end: breakEndTime,
          gap: 0
        }
      ]
    },
    {
      type: 'time',
      gridIndex: 1,
      show: false,
      breaks: [
        {
          start: breakStartTime,
          end: breakEndTime,
          gap: 0
        }
      ]
    },
    {
      type: 'time',
      gridIndex: 2,
      show: false,
      breaks: [
        {
          start: breakStartTime,
          end: breakEndTime,
          gap: 0
        }
      ]
    },
    {
      type: 'value',
      gridIndex: 3,
      show: false,
      max: 'dataMax'
    },
    {
      type: 'category',
      gridIndex: 4,
      show: false,
      boundaryGap: false,
      data: Array.from({ length: depthCount * 2 }, (_, i) => i + '')
    }
  ],
  yAxis: [
    {
      type: 'value',
      show: false,
      // Value should be symmetric around zero
      min: lastClose - maxAbs,
      max: lastClose + maxAbs
    },
    {
      type: 'value',
      gridIndex: 1,
      show: false
    },
    {
      type: 'value',
      gridIndex: 2,
      show: false
    },
    {
      type: 'category',
      gridIndex: 3,
      show: false
    },
    {
      type: 'value',
      gridIndex: 4,
      show: false,
      max: 'dataMax',
      min: 'dataMin'
    }
  ],
  grid: [
    {
      coordinateSystem: 'matrix',
      coord: [0, 0],
      top: 0,
      bottom: 0,
      left: 0,
      right: 0
    },
    {
      coordinateSystem: 'matrix',
      coord: [0, 5],
      top: 20,
      bottom: 0,
      left: 0,
      right: 0
    },
    {
      coordinateSystem: 'matrix',
      coord: [0, 4],
      top: 20,
      bottom: 0,
      left: 0,
      right: 0
    },
    {
      coordinateSystem: 'matrix',
      coord: [4, 0],
      top: 15,
      bottom: 2,
      left: 2,
      right: 2
    },
    {
      coordinateSystem: 'matrix',
      coord: [4, 4],
      top: 15,
      bottom: 0,
      left: 0,
      right: 0
    }
  ],
  series: [
    {
      type: 'line',
      symbolSize: 0,
      data: priceData,
      markPoint: {
        symbolSize: 0,
        symbol: 'circle',
        data: [
          {
            relativeTo: 'coordinate',
            x: 0,
            y: 0,
            name: 'max',
            type: 'max',
            label: {
              align: 'left',
              verticalAlign: 'top',
              formatter: priceFormatter(lastClose + maxAbs),
              color: getPriceColor(lastClose + maxAbs)
            }
          },
          {
            relativeTo: 'coordinate',
            x: 0,
            y: '50%',
            name: lastClose + '',
            label: {
              align: 'left',
              verticalAlign: 'middle',
              formatter: priceFormatter(lastClose),
              color: getPriceColor(lastClose)
            }
          },
          {
            relativeTo: 'coordinate',
            x: 0,
            y: '100%',
            name: 'min',
            type: 'min',
            label: {
              align: 'left',
              verticalAlign: 'bottom',
              formatter: priceFormatter(lastClose - maxAbs),
              color: getPriceColor(lastClose - maxAbs)
            }
          },
          {
            relativeTo: 'coordinate',
            x: '100%',
            y: 0,
            name: priceFormatter((maxAbs / lastClose) * 100) + '%',
            label: {
              align: 'right',
              verticalAlign: 'top',
              color: colorRed,
              formatter: '{b}'
            }
          },
          {
            relativeTo: 'coordinate',
            x: '100%',
            y: '50%',
            name: '0%',
            label: {
              align: 'right',
              verticalAlign: 'middle',
              color: colorGray,
              formatter: '{b}'
            }
          },
          {
            relativeTo: 'coordinate',
            x: '100%',
            y: '100%',
            name: '-' + priceFormatter((maxAbs / lastClose) * 100) + '%',
            label: {
              align: 'right',
              verticalAlign: 'bottom',
              color: colorGreen,
              formatter: '{b}'
            }
          }
        ]
      }
    },
    {
      type: 'line',
      symbolSize: 0,
      data: averageData,
      xAxisIndex: 0,
      yAxisIndex: 0
    },
    {
      type: 'line',
      symbolSize: 0,
      data: averageData,
      xAxisIndex: 0,
      yAxisIndex: 0,
      lineStyle: {
        color: '#FFC458',
        width: 1
      }
    },
    {
      name: 'Volume',
      type: 'bar',
      xAxisIndex: 1,
      yAxisIndex: 1,
      data: volumeData.map((item, index) => {
        // Compare current price with previous price to determine color
        let color = colorGray;
        if (index > 0) {
          const currentPrice = priceData[index][1];
          const prevPrice = priceData[index - 1][1];
          color = currentPrice > prevPrice ? colorRed : colorGreen;
        }
        return {
          value: [item[0], item[1]],
          itemStyle: {
            color: color
          }
        };
      })
    },
    {
      name: 'MACD',
      type: 'bar',
      xAxisIndex: 2,
      yAxisIndex: 2,
      data: macdData,
      barWidth: '70%' // Set bar width to 70% of coordinate area
    },
    {
      name: 'DIF',
      type: 'line',
      xAxisIndex: 2,
      yAxisIndex: 2,
      data: macdLineData,
      lineStyle: {
        color: '#FFC458',
        width: 1
      },
      symbol: 'none'
    },
    {
      name: 'DEA',
      type: 'line',
      xAxisIndex: 2,
      yAxisIndex: 2,
      data: signalLineData,
      lineStyle: {
        color: '#333',
        width: 1
      },
      symbol: 'none'
    },
    {
      name: 'Order Book',
      type: 'bar',
      xAxisIndex: 3,
      yAxisIndex: 3,
      data: orderData,
      barWidth: '90%',
      label: {
        show: true,
        position: 'insideLeft'
      }
    },
    {
      name: 'Depth High',
      type: 'line',
      xAxisIndex: 4,
      yAxisIndex: 4,
      data: depthHighData,
      step: 'end',
      lineStyle: {
        color: colorRed,
        width: 2
      },
      areaStyle: {
        color: colorRedOpacity,
        opacity: 1
      },
      symbol: 'none'
    },
    {
      name: 'Depth Low',
      type: 'line',
      xAxisIndex: 4,
      yAxisIndex: 4,
      data: depthLowData,
      step: 'end',
      lineStyle: {
        color: colorGreen,
        width: 2
      },
      areaStyle: {
        color: colorGreenOpacity,
        opacity: 1
      },
      symbol: 'none'
    }
  ],
  matrix: {
    left: matrixMargin,
    right: matrixMargin,
    top: matrixMargin,
    bottom: matrixMargin,
    x: {
      show: false,
      data: Array(5).fill(null)
    },
    y: {
      show: false,
      data: Array(6).fill(null)
    },
    body: {
      data: [
        {
          coord: [
            [0, 3],
            [0, 3]
          ],
          mergeCells: true
        },
        {
          coord: [
            [0, 3],
            [5, 5]
          ],
          mergeCells: true
        },
        {
          coord: [
            [0, 3],
            [4, 4]
          ],
          mergeCells: true
        },
        {
          coord: [
            [4, 4],
            [0, 3]
          ],
          mergeCells: true
        },
        {
          coord: [
            [4, 4],
            [4, 5]
          ],
          mergeCells: true
        }
      ]
    }
  },
  graphic: {
    elements: Array.from({ length: 3 }, (_, i) => {
      const lineWidth = 1;
      return {
        type: 'line',
        shape: {
          x1: matrixMargin + lineWidth,
          y1: (matrixHeight / 6) * (i + 1),
          x2: (matrixWidth / 5) * 4 + matrixMargin,
          y2: (matrixHeight / 6) * (i + 1)
        },
        style: {
          stroke: i === 1 ? '#bbb' : '#eee',
          lineWidth,
          lineDash: i == 1 ? 'dashed' : false
        }
      };
    }).concat(
      Array.from({ length: 3 }, (_, i) => {
        const lineWidth = 1;
        const matrixWidth = chartWidth - matrixMargin * 2;
        return {
          type: 'line',
          shape: {
            x1: (matrixWidth / 5) * (i + 1) + matrixMargin,
            y1: matrixMargin + lineWidth,
            x2: (matrixWidth / 5) * (i + 1) + matrixMargin,
            y2: chartHeight - matrixMargin
          },
          style: {
            stroke: '#eee',
            lineDash: false,
            lineWidth
          }
        };
      })
    )
  }
};
"""#,
        option: matrixStockOption)
}
