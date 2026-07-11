// matrix-basic — the MATRIX coordinate system (the 8th, after cartesian/radar/polar/single/parallel/
// calendar/geo), a TABLE of header cells (x = columns, y = rows) plus a body of intersection cells. This
// demo renders the matrix BACKDROP alone: the `matrix` component + MatrixView draw the x/y header cell
// rects with their text labels (ZRText), the divider lines splitting the corner from the body, the body
// cell rects (from `body.data`, keyed by `coord: [xLocator, yLocator]`), and the outer border/background.
// All cell geometry comes from the Matrix coord (an (x,y) header/body cell → a pixel rect). Renders on
// BOTH panes: native (EChartsKit) and echarts.js. (A series ON the matrix is custom-series, ported — this
// demo shows the backdrop only.)
extension EChartsDemoRegistry {
    static let demo_matrix_basic = EChartsDemo(
        name: "matrix-basic", category: "Matrix",
        summary: "matrix coordinate-system backdrop — a 3-column x 2-row table with header labels and body cells",
        width: 520, height: 320,
        option: [
            "matrix": [
                "left": 40.0, "top": 40.0, "right": 40.0, "bottom": 40.0,
                // x = columns header, y = rows header (category cells; the label is each cell's value).
                "x": ["data": ["Jan", "Feb", "Mar"] as [Any]] as [String: Any],
                "y": ["data": ["North", "South"] as [Any]] as [String: Any],
                // Body intersection cells, keyed by coord: [xLocator, yLocator] (leaf ordinals).
                "body": [
                    "data": [
                        ["coord": [0, 0] as [Any], "value": "12"] as [String: Any],
                        ["coord": [1, 0] as [Any], "value": "34"] as [String: Any],
                        ["coord": [2, 0] as [Any], "value": "56"] as [String: Any],
                        ["coord": [0, 1] as [Any], "value": "78"] as [String: Any],
                        ["coord": [1, 1] as [Any], "value": "90"] as [String: Any],
                        ["coord": [2, 1] as [Any], "value": "21"] as [String: Any]
                    ] as [Any]
                ] as [String: Any]
            ] as [String: Any]
        ])
}
