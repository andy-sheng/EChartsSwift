// official-custom-calendar-icon — replica of https://echarts.apache.org/examples/zh/editor.html?c=custom-calendar-icon
// title: Custom Calendar Icon / titleCN: 日历图自定义图标
// A one-month (2017-03) vertical calendar coordinate system carrying a `custom` series: each day cell is
// drawn by `renderItem` as the day-of-month number plus 0…4 SVG-path icons (heart / pin / flag / calendar),
// laid out inside the 70×70 cell by a per-count `layouts` table and coloured from a 4-colour table.
//
// DEVIATIONS from the official source:
//   - DATA INLINED / DETERMINISTIC. Upstream builds its data with `getVirtulData('2017')`, which walks
//     every day of 2017 and picks `Math.round(Math.random() * 4)` events per day, each a
//     `Math.round(Math.random() * 3)` icon index — NONDETERMINISTIC, so no two renders (let alone the two
//     panes) would agree and the reference↔port diff would be meaningless. The same 365 `[date, "i|j|k"]`
//     rows are generated ONCE in Swift by a fixed-seed LCG standing in for Math.random(), and the SAME
//     array feeds BOTH panes: spliced into webOptionJS as a JSON literal (replacing `getVirtulData`, which
//     is therefore dropped) and used verbatim as the native `series.data`. Everything else — `layouts`,
//     `pathes`, `colors`, `renderItem`, `option` — is verbatim (TypeScript annotations stripped, since the
//     page runs the source as a classic script: `const cellWidth: number = (params.coordSys as any).…`
//     becomes `const cellWidth = params.coordSys.…`, etc.).
//   - NATIVE PANE ON (nativeSupported: true). `renderItem` IS ported natively (customCalendarIconRenderItem,
//     below) statement for statement: `api.coord`, `params.coordSys.extra["cellWidth"/"cellHeight"]`,
//     `number.linearMap`, `format.formatTime`, `api.style`, `api.font` are all wired (CustomView.swift +
//     util/number.swift + util/format.swift). THREE small CustomView.swift gaps surfaced and were fixed
//     (all flagged inline at their call sites, "GAP FIX (tiny, faithful)"):
//       1. `CustomRenderItemAPI.coord`'s generic-coordSys fallback (taken for calendar/single/matrix,
//          whose `prepareCustom.coord` closures have a Swift signature `makeRenderItem` doesn't hard-cast
//          to) pre-coerced `data` through `toDoubleArray`, which only recognizes Double/Int/NSNumber/
//          arrays — Calendar's dim-0 value is a raw `"2017-03-01"` date STRING, so it was silently
//          dropped to `[]`, `Calendar.dataToPoint` always saw an empty array, and `api.coord` returned
//          `[NaN, NaN]` for every cell (every icon/day-number in the whole chart). Fixed by passing
//          `data` straight through uncoerced, matching every real `prepareCustom.coord` closure upstream
//          (they all forward `data` to `coordSys.dataToPoint(data, ...)` verbatim).
//       2. `applyUpdateTransitionStatic` did not translate the legacy `position`/`scale`/`origin` ARRAY
//          transform aliases into x/y/scaleX/scaleY/originX/originY — upstream's own
//          `LEGACY_TRANSFORM_PROPS_MAP` (animation/customGraphicTransition.ts) does this inside the
//          DEFERRED `applyUpdateTransition`, so a bare `position: [x, y]` (as this renderItem's path
//          children use) silently rendered at (0, 0).
//       3. `bridgeTextStyle` did not read the `textFont` style key — a genuine zrender `TextStyleProps`
//          field (already ported, just unwired) that `api.font(...)` is written through here, matching
//          zrender's own `font && trim(font) || style.textFont || style.font` fallback in Text.ts.
//
// The upstream source uses the old ECharts-4 locale spelling `cn`. Pin both panes to the current `ZH`
// locale so the comparison is deterministic and matches the Chinese official-gallery rendering.
//
// The full year of data is kept even though `calendar.range` is '2017-03': the out-of-range days are what
// exercise renderItem's `isNaN(cellPoint[0])` early-return guard, exactly as upstream.
import Foundation
import EChartsKit

// MARK: - the upstream `layouts` / `pathes` / `colors` tables, verbatim (see webOptionJS below)

/// `layouts[eventCount - 1]` — cell-normalized ([-0.5, 0.5]) offsets for 1…4 icons.
private let calIconLayouts: [[[Double]]] = [
    [[0, 0]],
    [[-0.25, 0], [0.25, 0]],
    [[0, -0.2], [-0.2, 0.2], [0.2, 0.2]],
    [[-0.25, -0.25], [-0.25, 0.25], [0.25, -0.25], [0.25, 0.25]]
]

/// `pathes` — the 4 SVG-path icons (heart / pin / flag / calendar), 1024-viewBox, verbatim strings.
private let calIconPathes: [String] = [
    "M936.857805 523.431322c0 0-42.065715-68.89513-88.786739-68.89513-46.68416 0-95.732122 71.223091-95.732122 71.223091s-44.28544-72.503296-93.440922-71.152538c-35.565466 0.977306-62.89705 30.882406-79.124275 64.06615L579.773747 790.800797c-3.253248 37.391565-5.677568 50.904371-12.002816 69.63497-6.651802 19.698688-19.544883 35.227341-31.650099 45.909606-14.30231 12.621414-29.59831 22.066586-45.854208 27.424563-16.28969 5.362074-30.098739 6.496973-51.536794 6.496973-19.498906 0-36.95104-2.963456-52.395418-8.850534-15.410586-5.887078-28.420403-14.313984-39.034573-25.246003-10.613146-10.930995-18.757939-24.08151-24.435507-39.525171-5.676544-15.443763-8.532685-40.195482-8.532685-59.270963l0-26.232454 74.435273 0c0 24.644301-0.17705 64.452915 8.81408 77.006848 9.02697 12.515021 22.756147 18.092032 41.148826 18.791014 16.728678 0.636518 30.032179-8.061645 30.032179-8.061645s11.922022-10.5472 14.992077-19.756954c2.674995-8.025805 3.565363-22.180147 3.565363-22.180147s2.080461-21.789286 2.080461-34.234675L489.399906 514.299369c-16.678502-18.827776-43.801395-61.938688-82.756096-60.927693-54.699008 1.419366-100.422144 70.059622-100.422144 70.059622s-56.065126-70.059622-93.440922-70.059622c-37.376717 0-91.077939 70.059622-91.077939 70.059622S105.343488 156.737741 476.742042 119.363584l53.70327-74.714624 51.373056 74.714624C964.889395 142.740992 936.857805 523.431322 936.857805 523.431322z",
    "M533.504 268.288q33.792-41.984 71.68-75.776 32.768-27.648 74.24-50.176t86.528-19.456q63.488 5.12 105.984 30.208t67.584 63.488 34.304 87.04 6.144 99.84-17.92 97.792-36.864 87.04-48.64 74.752-53.248 61.952q-40.96 41.984-85.504 78.336t-84.992 62.464-73.728 41.472-51.712 15.36q-20.48 1.024-52.224-14.336t-69.632-41.472-79.872-61.952-82.944-75.776q-26.624-25.6-57.344-59.392t-57.856-74.24-46.592-87.552-21.504-100.352 11.264-99.84 39.936-83.456 65.536-61.952 88.064-35.328q24.576-5.12 49.152-1.536t48.128 12.288 45.056 22.016 40.96 27.648q45.056 33.792 86.016 80.896z",
    "M741.06368 733.310464c8.075264-29.262438 20.615373-40.632422 14.64105-162.810061C966.089728 361.789952 967.93897 72.37847 967.855002 54.693683c0.279347-0.279347 0.418509-0.419533 0.418509-0.419533s-0.17705-0.00512-0.428749-0.00512c0-0.251699 0-0.428749 0-0.428749s-0.139162 0.14633-0.418509 0.425677c-17.695744-0.083866-307.10784 1.760051-515.833958 212.142592-122.181632-5.984256-133.55305 6.563533-162.815693 14.644531C235.35063 295.798886 103.552614 436.975309 90.630758 486.076621c-12.921856 49.105408 39.634227 56.859034 58.579558 58.581197 18.953421 1.724314 121.471386-9.475789 130.09111 4.309094 0 0 16.367411 11.200102 17.226035 41.346662 0.850432 29.796659 15.173222 71.354163 37.123994 97.267302-0.028672 0.027648-0.05632 0.054272-0.083866 0.074752 0.158618 0.13097 0.316211 0.261939 0.474829 0.390861 0.129946 0.149402 0.261939 0.319283 0.393011 0.468685 0.019456-0.019456 0.04608-0.049152 0.075776-0.075674 25.918362 21.961216 67.477504 36.272128 97.269248 37.122458 30.149837 0.859546 41.354547 17.234534 41.354547 17.234534 13.779354 8.608051 2.583962 111.122842 4.302131 130.075546 1.727386 18.95168 9.477222 71.498445 58.579558 58.576077C585.12896 918.526771 726.311117 786.734182 741.06368 733.310464zM595.893555 426.206003c-39.961702-39.965184-39.961702-104.75991 0-144.720077 39.970918-39.96928 104.768307-39.96928 144.730112 0 39.970918 39.960064 39.970918 104.75479 0 144.720077C700.661862 466.171187 635.864474 466.171187 595.893555 426.206003zM358.53312 769.516032c-31.923302-4.573184-54.890394-18.410291-71.41847-35.402342-16.984474-16.526438-30.830387-39.495475-35.405824-71.420621-4.649062-28.082586-20.856832-41.167565-38.76649-38.763827-17.906586 2.40681-77.046886 66.714419-80.857805 89.475891-3.80887 22.752154 29.271859 12.081152 46.424166 27.654861 17.151283 15.590093-2.139853 61.93664-14.733107 86.845952-6.441984 12.735078-10.289766 26.42176-4.22953 33.76087 7.346586 6.070272 21.03593 2.222592 33.769472-4.220109 24.912384-12.585677 71.258829-31.872922 86.842368-14.731469 15.583539 17.160806 4.911002 50.229965 27.674419 46.419251 22.754099-3.807744 87.065395-62.946611 89.466163-80.85248C399.70857 790.374093 386.627072 774.166938 358.53312 769.516032z",
    "M848.794624 939.156685 571.780416 939.156685 571.780416 653.17123l341.897539 0 0 221.100654C913.677926 909.960704 884.482867 939.156685 848.794624 939.156685zM571.780403 318.743552c-11.861606-3.210138-31.443354-8.36864-39.829709-16.176435-0.596582-0.561766-1.016218-1.246413-1.613824-1.841971-0.560845 0.596582-1.016218 1.280205-1.613824 1.841971-8.386355 7.807795-15.96631 12.965274-27.827917 16.176435l0 263.544325L141.030675 582.287877 141.030675 355.202884c0-35.687834 29.195059-64.882688 64.883302-64.882688l150.649125 0c-16.984474-9.525965-32.846438-20.56233-46.111027-32.932045-60.250624-56.144691-71.129907-137.062605-24.283034-180.767027-19.615539-18.264986 46.252237-27.124736 75.026739-27.124736 39.933133 0 83.972915 17.070797 118.995968 49.706086 20.353331 18.983322 37.722624 43.405619 50.145075 69.056819 12.457267-25.6512 29.791744-50.074419 50.180915-69.056819 35.022029-32.63529 79.062835-49.706086 118.994944-49.706086 28.74071 0 55.410176 8.860774 75.025715 27.124736 46.882611 43.704422 35.96759 124.622336-24.283034 180.767027-13.264589 12.368691-29.127578 23.40608-46.111027 32.932045l144.649234 0c35.688243 0 64.882278 29.195981 64.882278 64.882688l0 227.084948L571.780416 582.287833 571.780416 318.743508zM435.064218 147.625267c-21.476966-19.965747-49.094144-31.913882-73.868288-31.913882-7.404954 0-21.125018 1.211597-29.863322 9.386803-2.000691 1.824563-8.070144 7.439462-8.070144 21.369754 0 15.650406 8.492749 40.24873 32.319386 62.477926 29.124506 27.12576 77.202432 47.601152 111.76704 47.601152 12.176794 0 16.492237-2.666701 16.527053-2.702541C489.524736 242.54505 475.664486 185.453773 435.064218 147.625267zM577.78135 254.790963c0 0 0.034816-0.034816 0.069632-0.034816 0.807424 0 5.50871 1.790771 15.509914 1.790771 34.564608 0 82.64151-20.47529 111.76704-47.601152 23.826637-22.229299 32.283546-46.810112 32.283546-62.442189 0-13.930291-6.033613-19.562496-8.035328-21.404467-8.77312-8.17623-22.457344-9.386803-29.864346-9.386803-24.808038 0-52.390298 11.948134-73.867264 31.913882C585.325466 185.208218 571.358822 241.73865 577.78135 254.790963zM500.89513 939.156685 205.914017 939.156685c-35.688243 0-64.883302-29.195981-64.883302-64.883712L141.030714 653.17123l359.864462 0L500.895177 939.15666z"
]

private let calIconColors: [String] = ["#c4332b", "#16B644", "#6862FD", "#FDC763"]

/// The official `renderItem`, statement for statement.
///   const cellPoint = api.coord(api.value(0));
///   const cellWidth = params.coordSys.cellWidth;
///   const cellHeight = params.coordSys.cellHeight;
///   const value = api.value(1);
///   const events = value && value.split('|');
///   if (isNaN(cellPoint[0]) || isNaN(cellPoint[1])) { return; }
///   const group = { type: 'group', children: (layouts[events.length - 1] || []).map(...) };
///   group.children.push({ type: 'text', style: {...} });
///   return group;
private let customCalendarIconRenderItem: CustomSeriesRenderItem = { params, api in
    // Dim 0 (the option's `dimensions: [undefined, ...]` leaves it unoverridden) comes back through
    //   `api.value` as the raw `"2017-03-01"`-shaped date String — same as the JS's `api.value(0)`, and
    //   `api.coord`/`format.formatTime` both parse a raw date string themselves (`number.parseDate`), so
    //   it is passed straight through with no coercion, exactly as the JS does.
    let cellPoint = api.coord(api.value(0.0, nil), nil)
    let cellWidth = (params.coordSys.extra["cellWidth"] as? Double) ?? 0
    let cellHeight = (params.coordSys.extra["cellHeight"] as? Double) ?? 0

    // Dim 1 is declared `{type: 'ordinal'}`, whose store keeps the raw value un-coerced (dataValueHelper
    //   .parseDataValue: `if dimType == .ordinal { return value as Any }`) — so this IS the row's raw
    //   "i|j|k" String, exactly what `.split('|')` expects.
    let value = (api.value(1.0, nil) as? String) ?? ""
    // `value && value.split('|')`: JS's `&&` on a non-empty string yields the split array; on an EMPTY
    //   string yields `""` itself (falsy short-circuit) — never actually indexed below since
    //   `layouts[events.length - 1]` (== `layouts[-1]`) is `undefined` -> `[]` either way.
    let events: [String] = value.isEmpty ? [] : value.components(separatedBy: "|")

    guard cellPoint.count >= 2, !cellPoint[0].isNaN, !cellPoint[1].isNaN else {
        return nil
    }

    // (layouts[events.length - 1] || [])
    let layoutIdx = events.count - 1
    let layout: [[Double]] = (layoutIdx >= 0 && layoutIdx < calIconLayouts.count)
        ? calIconLayouts[layoutIdx] : []

    var children: [[String: Any]] = layout.enumerated().compactMap { index, itemLayout -> [String: Any]? in
        // `+events[index]` — unary-plus string-to-number coercion; the data generator only ever emits
        //   digit strings "0"…"3", so this always parses.
        guard index < events.count, let eventIdx = Int(events[index]),
            eventIdx >= 0, eventIdx < calIconPathes.count
        else { return nil }
        return [
            "type": "path",
            "shape": [
                "pathData": calIconPathes[eventIdx],
                "x": -8.0,
                "y": -8.0,
                "width": 16.0,
                "height": 16.0
            ] as [String: Any],
            "position": [
                cellPoint[0] + number.linearMap(itemLayout[0], [-0.5, 0.5], [-cellWidth / 2, cellWidth / 2]),
                cellPoint[1] + number.linearMap(itemLayout[1], [-0.5, 0.5], [-cellHeight / 2 + 20, cellHeight / 2])
            ],
            "style": api.style(["fill": calIconColors[eventIdx]] as [String: Any], nil)
        ] as [String: Any]
    }

    children.append([
        "type": "text",
        "style": [
            "x": cellPoint[0],
            "y": cellPoint[1] - cellHeight / 2 + 15,
            "text": format.formatTime("dd", api.value(0.0, nil)),
            "fill": "#777",
            "textFont": api.font(["fontSize": 14.0] as [String: Any])
        ] as [String: Any]
    ] as [String: Any])

    return ["type": "group", "children": children] as [String: Any]
}

// The 365 rows `getVirtulData('2017')` would have produced, made deterministic (see DEVIATIONS). Row shape
// is the upstream `[dateString, eventIndices.join('|')]` pair; a day with 0 events carries the empty string
// (renderItem's `value && value.split('|')` then short-circuits to no icons).
private let customCalendarIconData: [[String]] = {
    var seed: UInt64 = 2017_03_01
    func nextUnit() -> Double {          // deterministic stand-in for Math.random() → [0, 1)
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return Double((seed >> 33) % 1_000_000) / 1_000_000.0
    }
    let pathCount = 4                    // `pathes.length` upstream
    let monthDays = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]   // 2017 is not a leap year
    var rows: [[String]] = []
    for (i, days) in monthDays.enumerated() {
        for day in 1...days {
            let date = String(format: "2017-%02d-%02d", i + 1, day)
            let eventCount = Int((nextUnit() * Double(pathCount)).rounded())          // 0…4
            var items: [String] = []
            for _ in 0..<eventCount {
                items.append(String(Int((nextUnit() * Double(pathCount - 1)).rounded())))   // 0…3
            }
            rows.append([date, items.joined(separator: "|")])
        }
    }
    return rows
}()

// The same rows as a JSON literal, spliced into the reference pane's JS (see \#( ... ) below).
private let customCalendarIconDataJSON: String = {
    guard let data = try? JSONSerialization.data(withJSONObject: customCalendarIconData, options: []),
          let json = String(data: data, encoding: .utf8) else { return "[]" }
    return json
}()

extension EChartsDemoRegistry {
    static let official_custom_calendar_icon = EChartsDemo(
        name: "official-custom-calendar-icon", category: "custom",
        summary: "日历图自定义图标 — Custom Calendar Icon",
        width: 720, height: 460,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
const layouts = [
  [[0, 0]],
  [
    [-0.25, 0],
    [0.25, 0]
  ],
  [
    [0, -0.2],
    [-0.2, 0.2],
    [0.2, 0.2]
  ],
  [
    [-0.25, -0.25],
    [-0.25, 0.25],
    [0.25, -0.25],
    [0.25, 0.25]
  ]
];
const pathes = [
  'M936.857805 523.431322c0 0-42.065715-68.89513-88.786739-68.89513-46.68416 0-95.732122 71.223091-95.732122 71.223091s-44.28544-72.503296-93.440922-71.152538c-35.565466 0.977306-62.89705 30.882406-79.124275 64.06615L579.773747 790.800797c-3.253248 37.391565-5.677568 50.904371-12.002816 69.63497-6.651802 19.698688-19.544883 35.227341-31.650099 45.909606-14.30231 12.621414-29.59831 22.066586-45.854208 27.424563-16.28969 5.362074-30.098739 6.496973-51.536794 6.496973-19.498906 0-36.95104-2.963456-52.395418-8.850534-15.410586-5.887078-28.420403-14.313984-39.034573-25.246003-10.613146-10.930995-18.757939-24.08151-24.435507-39.525171-5.676544-15.443763-8.532685-40.195482-8.532685-59.270963l0-26.232454 74.435273 0c0 24.644301-0.17705 64.452915 8.81408 77.006848 9.02697 12.515021 22.756147 18.092032 41.148826 18.791014 16.728678 0.636518 30.032179-8.061645 30.032179-8.061645s11.922022-10.5472 14.992077-19.756954c2.674995-8.025805 3.565363-22.180147 3.565363-22.180147s2.080461-21.789286 2.080461-34.234675L489.399906 514.299369c-16.678502-18.827776-43.801395-61.938688-82.756096-60.927693-54.699008 1.419366-100.422144 70.059622-100.422144 70.059622s-56.065126-70.059622-93.440922-70.059622c-37.376717 0-91.077939 70.059622-91.077939 70.059622S105.343488 156.737741 476.742042 119.363584l53.70327-74.714624 51.373056 74.714624C964.889395 142.740992 936.857805 523.431322 936.857805 523.431322z',
  'M533.504 268.288q33.792-41.984 71.68-75.776 32.768-27.648 74.24-50.176t86.528-19.456q63.488 5.12 105.984 30.208t67.584 63.488 34.304 87.04 6.144 99.84-17.92 97.792-36.864 87.04-48.64 74.752-53.248 61.952q-40.96 41.984-85.504 78.336t-84.992 62.464-73.728 41.472-51.712 15.36q-20.48 1.024-52.224-14.336t-69.632-41.472-79.872-61.952-82.944-75.776q-26.624-25.6-57.344-59.392t-57.856-74.24-46.592-87.552-21.504-100.352 11.264-99.84 39.936-83.456 65.536-61.952 88.064-35.328q24.576-5.12 49.152-1.536t48.128 12.288 45.056 22.016 40.96 27.648q45.056 33.792 86.016 80.896z',
  'M741.06368 733.310464c8.075264-29.262438 20.615373-40.632422 14.64105-162.810061C966.089728 361.789952 967.93897 72.37847 967.855002 54.693683c0.279347-0.279347 0.418509-0.419533 0.418509-0.419533s-0.17705-0.00512-0.428749-0.00512c0-0.251699 0-0.428749 0-0.428749s-0.139162 0.14633-0.418509 0.425677c-17.695744-0.083866-307.10784 1.760051-515.833958 212.142592-122.181632-5.984256-133.55305 6.563533-162.815693 14.644531C235.35063 295.798886 103.552614 436.975309 90.630758 486.076621c-12.921856 49.105408 39.634227 56.859034 58.579558 58.581197 18.953421 1.724314 121.471386-9.475789 130.09111 4.309094 0 0 16.367411 11.200102 17.226035 41.346662 0.850432 29.796659 15.173222 71.354163 37.123994 97.267302-0.028672 0.027648-0.05632 0.054272-0.083866 0.074752 0.158618 0.13097 0.316211 0.261939 0.474829 0.390861 0.129946 0.149402 0.261939 0.319283 0.393011 0.468685 0.019456-0.019456 0.04608-0.049152 0.075776-0.075674 25.918362 21.961216 67.477504 36.272128 97.269248 37.122458 30.149837 0.859546 41.354547 17.234534 41.354547 17.234534 13.779354 8.608051 2.583962 111.122842 4.302131 130.075546 1.727386 18.95168 9.477222 71.498445 58.579558 58.576077C585.12896 918.526771 726.311117 786.734182 741.06368 733.310464zM595.893555 426.206003c-39.961702-39.965184-39.961702-104.75991 0-144.720077 39.970918-39.96928 104.768307-39.96928 144.730112 0 39.970918 39.960064 39.970918 104.75479 0 144.720077C700.661862 466.171187 635.864474 466.171187 595.893555 426.206003zM358.53312 769.516032c-31.923302-4.573184-54.890394-18.410291-71.41847-35.402342-16.984474-16.526438-30.830387-39.495475-35.405824-71.420621-4.649062-28.082586-20.856832-41.167565-38.76649-38.763827-17.906586 2.40681-77.046886 66.714419-80.857805 89.475891-3.80887 22.752154 29.271859 12.081152 46.424166 27.654861 17.151283 15.590093-2.139853 61.93664-14.733107 86.845952-6.441984 12.735078-10.289766 26.42176-4.22953 33.76087 7.346586 6.070272 21.03593 2.222592 33.769472-4.220109 24.912384-12.585677 71.258829-31.872922 86.842368-14.731469 15.583539 17.160806 4.911002 50.229965 27.674419 46.419251 22.754099-3.807744 87.065395-62.946611 89.466163-80.85248C399.70857 790.374093 386.627072 774.166938 358.53312 769.516032z',
  'M848.794624 939.156685 571.780416 939.156685 571.780416 653.17123l341.897539 0 0 221.100654C913.677926 909.960704 884.482867 939.156685 848.794624 939.156685zM571.780403 318.743552c-11.861606-3.210138-31.443354-8.36864-39.829709-16.176435-0.596582-0.561766-1.016218-1.246413-1.613824-1.841971-0.560845 0.596582-1.016218 1.280205-1.613824 1.841971-8.386355 7.807795-15.96631 12.965274-27.827917 16.176435l0 263.544325L141.030675 582.287877 141.030675 355.202884c0-35.687834 29.195059-64.882688 64.883302-64.882688l150.649125 0c-16.984474-9.525965-32.846438-20.56233-46.111027-32.932045-60.250624-56.144691-71.129907-137.062605-24.283034-180.767027 19.615539-18.264986 46.252237-27.124736 75.026739-27.124736 39.933133 0 83.972915 17.070797 118.995968 49.706086 20.353331 18.983322 37.722624 43.405619 50.145075 69.056819 12.457267-25.6512 29.791744-50.074419 50.180915-69.056819 35.022029-32.63529 79.062835-49.706086 118.994944-49.706086 28.74071 0 55.410176 8.860774 75.025715 27.124736 46.882611 43.704422 35.96759 124.622336-24.283034 180.767027-13.264589 12.368691-29.127578 23.40608-46.111027 32.932045l144.649234 0c35.688243 0 64.882278 29.195981 64.882278 64.882688l0 227.084948L571.780416 582.287833 571.780416 318.743508zM435.064218 147.625267c-21.476966-19.965747-49.094144-31.913882-73.868288-31.913882-7.404954 0-21.125018 1.211597-29.863322 9.386803-2.000691 1.824563-8.070144 7.439462-8.070144 21.369754 0 15.650406 8.492749 40.24873 32.319386 62.477926 29.124506 27.12576 77.202432 47.601152 111.76704 47.601152 12.176794 0 16.492237-2.666701 16.527053-2.702541C489.524736 242.54505 475.664486 185.453773 435.064218 147.625267zM577.78135 254.790963c0 0 0.034816-0.034816 0.069632-0.034816 0.807424 0 5.50871 1.790771 15.509914 1.790771 34.564608 0 82.64151-20.47529 111.76704-47.601152 23.826637-22.229299 32.283546-46.810112 32.283546-62.442189 0-13.930291-6.033613-19.562496-8.035328-21.404467-8.77312-8.17623-22.457344-9.386803-29.864346-9.386803-24.808038 0-52.390298 11.948134-73.867264 31.913882C585.325466 185.208218 571.358822 241.73865 577.78135 254.790963zM500.89513 939.156685 205.914017 939.156685c-35.688243 0-64.883302-29.195981-64.883302-64.883712L141.030714 653.17123l359.864462 0L500.895177 939.15666z'
];
const colors = ['#c4332b', '#16B644', '#6862FD', '#FDC763'];

// Upstream builds this with getVirtulData('2017') (Math.round(Math.random() * …) per day); the identical
// deterministic 365-row array the native option carries is inlined here instead, so the panes are diffable.
const data = \#(customCalendarIconDataJSON);

option = {
  tooltip: {},
  calendar: [
    {
      left: 'center',
      top: 'middle',
      cellSize: [70, 70],
      yearLabel: { show: false },
      orient: 'vertical',
      dayLabel: {
        firstDay: 1,
        nameMap: 'ZH'
      },
      monthLabel: {
        show: false
      },
      range: '2017-03'
    }
  ],
  series: [
    {
      type: 'custom',
      coordinateSystem: 'calendar',
      renderItem: function (params, api) {
        const cellPoint = api.coord(api.value(0));
        const cellWidth = params.coordSys.cellWidth;
        const cellHeight = params.coordSys.cellHeight;

        const value = api.value(1);
        const events = value && value.split('|');

        if (isNaN(cellPoint[0]) || isNaN(cellPoint[1])) {
          return;
        }

        const group = {
          type: 'group',
          children:
            (layouts[events.length - 1] || []).map(function (
              itemLayout,
              index
            ) {
              return {
                type: 'path',
                shape: {
                  pathData: pathes[+events[index]],
                  x: -8,
                  y: -8,
                  width: 16,
                  height: 16
                },
                position: [
                  cellPoint[0] +
                    echarts.number.linearMap(
                      itemLayout[0],
                      [-0.5, 0.5],
                      [-cellWidth / 2, cellWidth / 2]
                    ),
                  cellPoint[1] +
                    echarts.number.linearMap(
                      itemLayout[1],
                      [-0.5, 0.5],
                      [-cellHeight / 2 + 20, cellHeight / 2]
                    )
                ],
                style: api.style({
                  fill: colors[+events[index]]
                })
              };
            }) || []
        };

        group.children.push({
          type: 'text',
          style: {
            x: cellPoint[0],
            y: cellPoint[1] - cellHeight / 2 + 15,
            text: echarts.format.formatTime('dd', api.value(0)),
            fill: '#777',
            textFont: api.font({ fontSize: 14 })
          }
        });

        return group;
      },
      dimensions: [undefined, { type: 'ordinal' }],
      data: data
    }
  ]
};
"""#,
        option: [
            "tooltip": [:] as [String: Any],
            "calendar": [
                [
                    "left": "center",
                    "top": "middle",
                    "cellSize": [70.0, 70.0],
                    "yearLabel": ["show": false] as [String: Any],
                    "orient": "vertical",
                    "dayLabel": [
                        "firstDay": 1.0,
                        "nameMap": "ZH"
                    ] as [String: Any],
                    "monthLabel": [
                        "show": false
                    ] as [String: Any],
                    "range": "2017-03"
                ] as [String: Any]
            ],
            "series": [
                [
                    "type": "custom",
                    "coordinateSystem": "calendar",
                    // Per day cell returns a `group` of:
                    //   • one `path` element per event in the datum's 'i|j|k' string — `shape.pathData` is
                    //     the matching 1024-viewBox SVG icon from `pathes`, drawn 16×16 centred on the
                    //     origin (x/y: -8), filled with `colors[+events[index]]` through `api.style(...)`,
                    //     and positioned by `number.linearMap`-ing that event's `layouts` slot
                    //     ([-0.5, 0.5] → [-cellWidth/2, cellWidth/2], and the same in y with a 20px top
                    //     inset that leaves room for the day number) off the cell centre `api.coord(...)`;
                    //     the layout used is `layouts[events.length - 1]`, i.e. 1/2/3/4-icon arrangements.
                    //   • one `text` element at the top of the cell: `format.formatTime('dd', …)`
                    //     — the day-of-month number — in `api.font({ fontSize: 14 })`, fill '#777'.
                    // Cells whose date falls outside `calendar.range` return early (nil) on the
                    // `isNaN(cellPoint[0])` guard.
                    "renderItem": customCalendarIconRenderItem,
                    // NSNull is the JS `undefined` hole in the upstream `dimensions: [undefined, {…}]`:
                    // dim 0 (the date) keeps its default, dim 1 (the 'i|j|k' string) is declared ordinal.
                    "dimensions": [NSNull(), ["type": "ordinal"] as [String: Any]] as [Any],
                    "data": customCalendarIconData
                ] as [String: Any]
            ]
        ])
}
