import ZRenderKit
// Migrated from zrender test/origin.html
extension DemoRegistry {
    static let demo_origin: Demo = Demo(
        name: "origin", category: "Transform",
        summary: "Transform-origin grid: origin × rotation × scale × skew on Rects",
        width: 1800, height: 1300
    ) { zr in
        // origin.html lays out a grid of Rects to exercise transform-origin (originX/originY)
        // combined with rotation, scale and skew. The full upstream sweep is mirrored 1:1:
        //   origins(3) × rotations(3) × scales(2) × skews(5) = 90 cells, packed into columns by
        //   columnCount = floor(viewWidth / cellSize). Each cell draws: (a) a semi-transparent
        //   filled Rect carrying the transform, (b) a dashed border Rect marking the untransformed
        //   box, and (c) a 4-line label (origin/rot/scale/skew). Everything lives in one Group at
        //   (50,50). The CSS red-border baseline boxes from the HTML are DOM (not zrender), so they
        //   are omitted; dash keyword 'dashed' → explicit [4,4] array.
        let elSize = 70.0
        let cellSize = elSize * 2 + 5
        let origins: [(Double, Double)] = [(0, 0), (0.5, 0.5), (1, 1)]
        let rotations: [Double] = [0, 90, 180]
        let scales: [(Double, Double)] = [(1, 1), (0.8, 0.8)]
        let skews: [(Double, Double)] = [(0, 0), (10, 0), (-10, 0), (0, 10), (0, -10)]
        let DEG = π / 180

        let viewWidth = zr.getWidth() ?? 1800
        let columnCount = max(1, Int((viewWidth / cellSize).rounded(.down)))
        let offsetX = 50.0
        let offsetY = 50.0

        // Format like JS Number#toString: drop the trailing ".0" on whole numbers (0, 1, 10, -10).
        func num(_ d: Double) -> String { d == d.rounded() ? String(Int(d)) : String(d) }

        let group = Group()
        group.x = offsetX
        group.y = offsetY

        var idx = 0
        for origin in origins {
            for rot in rotations {
                for scale in scales {
                    for skew in skews {
                        let column = Double(idx % columnCount)
                        let row = Double(idx / columnCount)

                        // (a) filled Rect carrying the transform: shape sits at local (0,0)-(elSize)
                        // and the element is translated to the cell; originX/originY stay in local
                        // (percent × elSize) space, mirroring upstream.
                        let el = rect(0, 0, elSize, elSize)
                        el.x = column * cellSize
                        el.y = row * cellSize
                        el.rotation = rot * DEG
                        el.scaleX = scale.0
                        el.scaleY = scale.1
                        el.originX = origin.0 * elSize
                        el.originY = origin.1 * elSize
                        el.skewX = skew.0 * DEG
                        el.skewY = skew.1 * DEG
                        group.add(styled(el, fill: "rgba(0, 0, 0, 0.2)"))

                        // (b) dashed border Rect (no transform): shape carries the absolute cell
                        // position so it marks the untransformed box.
                        let border = rect(column * cellSize, row * cellSize, elSize, elSize)
                        group.add(styled(border, stroke: "#000", lineWidth: 1, dash: [4, 4]))

                        // (c) 4-line label, white-outlined like upstream (stroke '#fff', lineHeight 16).
                        var ts = TextStyleProps()
                        ts.text = [
                            "origin: [\(num(origin.0)), \(num(origin.1))]",
                            "rot: \(num(rot))deg",
                            "scale: [\(num(scale.0)), \(num(scale.1))]",
                            "skew: [\(num(skew.0))deg, \(num(skew.1))deg]",
                        ].joined(separator: "\n")
                        ts.x = 3
                        ts.y = 3
                        ts.align = .left
                        ts.verticalAlign = .top
                        ts.fill = "#000"
                        ts.stroke = "#fff"
                        ts.lineHeight = 16
                        ts.lineWidth = 1
                        let t = ZRText()
                        t.useStyle(ts)
                        t.x = column * cellSize
                        t.y = row * cellSize
                        t.z = 1
                        group.add(t)

                        idx += 1
                    }
                }
            }
        }
        zr.add(group)
    }
}
