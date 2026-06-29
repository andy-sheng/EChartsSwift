import ZRenderKit
// Migrated from zrender test/pathMerge.html
//
// HTML builds 300 horizontal `Line`s and folds them into ONE element via
// `zrender.path.mergePath(lineList, { style: { stroke:'black', fill:'none' } })`.
// mergePath() concatenates every sub-path's PathProxy into a single compound
// path that is drawn in one stroke. Faithful 1:1 port: same 300 rows, same
// `i * 3` spacing, same full-width 0→1000 spans, on the html's 1000x500 canvas.
extension DemoRegistry {
    static let demo_pathMerge: Demo = Demo(
        name: "pathMerge", category: "Path tools",
        summary: "mergePath: many Lines folded into one compound path, stroked once",
        width: 1000, height: 500
    ) { zr in
        // var lineList = []; for (i = 0; i < 300; i++) lineList.push(new Line({shape:{x1,y1,x2,y2}}))
        var lineList: [Path] = []
        for i in 0..<300 {
            var s = LineShape()
            s.x1 = 0;    s.y1 = Double(i) * 3
            s.x2 = 1000; s.y2 = Double(i) * 3
            let line = Line(); line.setShape(s)
            lineList.append(line)
        }
        // zr.add(zrender.path.mergePath(lineList, { style: { stroke:'black', fill:'none' } }))
        let merged = mergePath(lineList, nil)
        zr.add(styled(merged, stroke: "black", lineWidth: 1))
    }
}
