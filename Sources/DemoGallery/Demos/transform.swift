import ZRenderKit
// Migrated from zrender test/transform.html
extension DemoRegistry {
    static let demo_transform: Demo = Demo(
        name: "transform", category: "Transform", summary: "Same arrow under translate / rotate / scale via element x,y,rotation,scaleX,scaleY"
    ) { zr in
        // transform.html transforms one glyph by translate / rotate / scale / skew. Here the same
        // asymmetric arrow (defined around its own local origin, so rotation & scale pivot about it
        // since originX/originY default to 0) is shown under each transform, over a faint identity
        // "ghost" for comparison.
        func arrow(_ fill: String, stroke: String?, opacity: Double?) -> ZRenderKit.Polygon {
            var s = PolygonShape()
            s.points = [[-30, -10], [8, -10], [8, -22], [35, 0], [8, 22], [8, 10], [-30, 10]]
                .map { VectorArray($0[0], $0[1]) }
            let p = ZRenderKit.Polygon(); p.setShape(s)
            return styled(p, fill: fill, stroke: stroke, lineWidth: 1.5, opacity: opacity)
        }

        let cx: [Double] = [90, 255, 420, 590]
        let cy = 95.0
        let labels = ["translate", "rotate", "scale", "combined"]

        // faint identity reference + label in every cell
        for i in 0..<4 {
            let ghost = arrow("#cfd8e3", stroke: nil, opacity: 0.35)
            ghost.x = cx[i]; ghost.y = cy
            zr.add(ghost)
            zr.add(text(labels[i], cx[i], 165, "#333", size: 15, align: .center))
        }

        // 1) translate — element x / y offset from the ghost origin
        let a0 = arrow("#5470c6", stroke: "#22337a", opacity: nil)
        a0.x = cx[0] + 22; a0.y = cy - 20
        zr.add(a0)

        // 2) rotate — element rotation (radians, anticlockwise) about the shape origin
        let a1 = arrow("#91cc75", stroke: "#3e7d2c", opacity: nil)
        a1.x = cx[1]; a1.y = cy; a1.rotation = π / 4
        zr.add(a1)

        // 3) scale — non-uniform scaleX / scaleY about the shape origin
        let a2 = arrow("#fac858", stroke: "#b8860b", opacity: nil)
        a2.x = cx[2]; a2.y = cy; a2.scaleX = 1.5; a2.scaleY = 0.6
        zr.add(a2)

        // 4) combined — translate + rotate + scale on one element
        let a3 = arrow("#ee6666", stroke: "#a23a3a", opacity: nil)
        a3.x = cx[3] + 12; a3.y = cy - 8
        a3.rotation = π / 6; a3.scaleX = 1.3; a3.scaleY = 1.3
        zr.add(a3)
    }
}
