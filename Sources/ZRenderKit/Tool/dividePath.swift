// Ported from zrender/src/tool/dividePath.ts — keep in sync with upstream
//
// NAMESPACE DEVIATION (CONVENTIONS §2): a free-function module would normally become a caseless
//   `enum` named after the file (`dividePath`). Upstream consumers import the two exports as NAMED
//   imports (`import { split, clone } from './dividePath'`), so exposing `split` / `clone` as
//   top-level `public func`s keeps call sites byte-identical to upstream. The non-exported helpers
//   stay file-private, mirroring their upstream (un-exported) visibility. Same precedent as
//   Tool/ToolPath.swift / Tool/convertPath.swift.
//
// POINTS REPRESENTATION (port-wide): upstream polygon points are `number[][]`. Our `PolygonShape.points`
//   is `[VectorArray]` (SIMD2<Double>), so the polygon-division helpers below carry points as
//   `[VectorArray]` to interface directly with `PolygonShape`. `core/bbox.fromPoints` takes `[[Double]]`,
//   so its two call sites convert via `toDoublePairs` (the only representation bridge).

import Foundation

// upstream imports (resolved to the ported modules):
// import { fromPoints } from '../core/bbox';          → bbox.fromPoints
// import BoundingRect from '../core/BoundingRect';      → Core/BoundingRect.swift
// import Point from '../core/Point';                    → Core/Point.swift
// import { map } from '../core/util';                   → util.map
// import Path from '../graphic/Path';                   → Graphic/Path.swift
// import Polygon from '../graphic/shape/Polygon';       → Graphic/Shape/Polygon.swift
// import Rect from '../graphic/shape/Rect';             → Graphic/Shape/Rect.swift
// import Sector from '../graphic/shape/Sector';         → Graphic/Shape/Sector.swift
// import { pathToPolygons } from './convertPath';       → Tool/convertPath.swift
// import { clonePath } from './path';                   → Tool/ToolPath.swift

// upstream-only representation bridge: [VectorArray] → number[][] for `bbox.fromPoints`.
private func toDoublePairs(_ points: [VectorArray]) -> [[Double]] {
    return points.map { [$0[0], $0[1]] }
}

// upstream: const newShape = makePolygonShape(points) ⟷ object literal `{ points }`.
private func makePolygonShape(_ points: [VectorArray]) -> PolygonShape {
    var s = PolygonShape()
    s.points = points
    return s
}

// Default shape dividers
// TODO divide polygon by grids.
// upstream: interface BinaryDivide { (shape: Path['shape']): Path['shape'][] }
//   Specialized to PolygonShape — the only shape type binaryDivideRecursive is instantiated with.
private typealias BinaryDivide = (PolygonShape) -> [PolygonShape]

/**
 * Calculating a grid to divide the shape.
 */
// `rowDim` is a pure 0/1 index → Int. `count` / grid counts stay Double (CONVENTIONS §1); cast to
//   Int only at loop bounds / array indexing.
private func getDividingGrids(_ dimSize: [Double], _ rowDim: Int, _ count: Double) -> [Double] {
    let rowSize = dimSize[rowDim]
    let columnSize = dimSize[1 - rowDim]

    let ratio = Swift.abs(rowSize / columnSize)
    var rowCount = ceil(sqrt(ratio * count))
    var columnCount = floor(count / rowCount)
    if columnCount == 0 {
        columnCount = 1
        rowCount = count
    }

    var grids: [Double] = []
    for _ in 0..<Int(rowCount) {
        grids.append(columnCount)
    }
    let currentCount = rowCount * columnCount
    // Distribute the remaind grid evenly on each row.
    let remained = count - currentCount
    if remained > 0 {
        // const stride = Math.max(Math.floor(rowCount / remained), 1);
        for i in 0..<Int(remained) {
            grids[i % Int(rowCount)] += 1
        }
    }
    return grids
}


// TODO cornerRadius
private func divideSector(_ sectorShape: SectorShape, _ count: Double, _ outShapes: inout [PathShape]) {
    let r0 = sectorShape.r0
    let r = sectorShape.r
    let startAngle = sectorShape.startAngle
    let endAngle = sectorShape.endAngle
    let angle = Swift.abs(endAngle - startAngle)
    let arcLen = angle * r
    let deltaR = r - r0

    let isAngleRow = arcLen > Swift.abs(deltaR)
    let grids = getDividingGrids([arcLen, deltaR], isAngleRow ? 0 : 1, count)

    let rowSize = (isAngleRow ? angle : deltaR) / Double(grids.count)

    for row in 0..<grids.count {
        let columnSize = (isAngleRow ? deltaR : angle) / grids[row]
        for column in 0..<Int(grids[row]) {
            // upstream: const newShape = {} as Sector['shape']; (typed-struct default below)
            var newShape = SectorShape()

            if isAngleRow {
                newShape.startAngle = startAngle + rowSize * Double(row)
                newShape.endAngle = startAngle + rowSize * Double(row + 1)
                newShape.r0 = r0 + columnSize * Double(column)
                newShape.r = r0 + columnSize * Double(column + 1)
            }
            else {
                newShape.startAngle = startAngle + columnSize * Double(column)
                newShape.endAngle = startAngle + columnSize * Double(column + 1)
                newShape.r0 = r0 + rowSize * Double(row)
                newShape.r = r0 + rowSize * Double(row + 1)
            }

            newShape.clockwise = sectorShape.clockwise
            newShape.cx = sectorShape.cx
            newShape.cy = sectorShape.cy

            outShapes.append(newShape)
        }
    }
}

private func divideRect(_ rectShape: RectShape, _ count: Double, _ outShapes: inout [PathShape]) {
    let width = rectShape.width
    let height = rectShape.height

    let isHorizontalRow = width > height
    let grids = getDividingGrids([width, height], isHorizontalRow ? 0 : 1, count)
    // upstream selects the dim names dynamically (rowSizeDim/columnSizeDim/rowDim/columnDim) and
    //   assigns `newShape[rowDim] = ...`. Swift has no dynamic keys on a typed struct, so the two
    //   orientations are written out explicitly below (same arithmetic, faithful result).
    let rowSize = (isHorizontalRow ? rectShape.width : rectShape.height) / Double(grids.count)

    for row in 0..<grids.count {
        let columnSize = (isHorizontalRow ? rectShape.height : rectShape.width) / grids[row]
        for column in 0..<Int(grids[row]) {
            var newShape = RectShape()
            if isHorizontalRow {
                newShape.x = Double(row) * rowSize          // newShape[rowDim='x']
                newShape.y = Double(column) * columnSize    // newShape[columnDim='y']
                newShape.width = rowSize                     // newShape[rowSizeDim='width']
                newShape.height = columnSize                 // newShape[columnSizeDim='height']
            }
            else {
                newShape.y = Double(row) * rowSize          // newShape[rowDim='y']
                newShape.x = Double(column) * columnSize    // newShape[columnDim='x']
                newShape.height = rowSize                     // newShape[rowSizeDim='height']
                newShape.width = columnSize                   // newShape[columnSizeDim='width']
            }

            newShape.x += rectShape.x
            newShape.y += rectShape.y

            outShapes.append(newShape)
        }
    }
}

private func crossProduct2d(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Double {
    return x1 * y2 - x2 * y1
}

private func lineLineIntersect(
    _ a1x: Double, _ a1y: Double, _ a2x: Double, _ a2y: Double, // p1
    _ b1x: Double, _ b1y: Double, _ b2x: Double, _ b2y: Double  // p2
) -> Point? {
    let mx = a2x - a1x
    let my = a2y - a1y
    let nx = b2x - b1x
    let ny = b2y - b1y

    let nmCrossProduct = crossProduct2d(nx, ny, mx, my)
    if Swift.abs(nmCrossProduct) < 1e-6 {
        return nil
    }

    let b1a1x = a1x - b1x
    let b1a1y = a1y - b1y

    let p = crossProduct2d(b1a1x, b1a1y, nx, ny) / nmCrossProduct
    if p < 0 || p > 1 {
        return nil
    }
    // p2 is an infinite line
    return Point(
        p * mx + a1x,
        p * my + a1y
    )
}

private func projPtOnLine(_ pt: Point, _ lineA: Point, _ lineB: Point) -> Double {
    let dir = Point()
    Point.sub(dir, lineB, lineA)
    dir.normalize()
    let dir2 = Point()
    Point.sub(dir2, pt, lineA)
    let len = dir2.dot(dir)
    return len
}

private func addToPoly(_ poly: inout [VectorArray], _ pt: VectorArray) {
    let last = poly.last
    if let last = last, last[0] == pt[0] && last[1] == pt[1] {
        return
    }
    poly.append(pt)
}

private func splitPolygonByLine(_ points: [VectorArray], _ lineA: Point, _ lineB: Point) -> [PolygonShape] {
    let len = points.count
    // upstream: { projPt: number, pt: Point, idx: number }[]
    var intersections: [(projPt: Double, pt: Point, idx: Int)] = []
    for i in 0..<len {
        let p0 = points[i]
        let p1 = points[(i + 1) % len]
        let intersectionPt = lineLineIntersect(
            p0[0], p0[1], p1[0], p1[1],
            lineA.x, lineA.y, lineB.x, lineB.y
        )
        if let intersectionPt = intersectionPt {
            intersections.append((
                projPt: projPtOnLine(intersectionPt, lineA, lineB),
                pt: intersectionPt,
                idx: i
            ))
        }
    }

    // TODO No intersection?
    if intersections.count < 2 {
        // Do clone
        return [ makePolygonShape(points), makePolygonShape(points) ]
    }

    // Find two farthest points.
    intersections.sort { a, b in
        return a.projPt < b.projPt
    }
    var splitPt0 = intersections[0]
    var splitPt1 = intersections[intersections.count - 1]
    if splitPt1.idx < splitPt0.idx {
        let tmp = splitPt0
        splitPt0 = splitPt1
        splitPt1 = tmp
    }

    let splitPt0Arr = VectorArray(splitPt0.pt.x, splitPt0.pt.y)
    let splitPt1Arr = VectorArray(splitPt1.pt.x, splitPt1.pt.y)

    var newPolyA: [VectorArray] = [splitPt0Arr]
    var newPolyB: [VectorArray] = [splitPt1Arr]

    var i = splitPt0.idx + 1
    while i <= splitPt1.idx {
        addToPoly(&newPolyA, points[i])   // upstream: points[i].slice() (VectorArray is a value copy)
        i += 1
    }
    addToPoly(&newPolyA, splitPt1Arr)
    // Close the path
    addToPoly(&newPolyA, splitPt0Arr)

    i = splitPt1.idx + 1
    while i <= splitPt0.idx + len {
        addToPoly(&newPolyB, points[i % len])
        i += 1
    }
    addToPoly(&newPolyB, splitPt0Arr)
    // Close the path
    addToPoly(&newPolyB, splitPt1Arr)

    return [makePolygonShape(newPolyA), makePolygonShape(newPolyB)]
}

private func binaryDividePolygon(
    _ polygonShape: PolygonShape
) -> [PolygonShape] {
    let points = polygonShape.points ?? []
    var min = VectorArray()
    var max = VectorArray()
    (min, max) = bbox.fromPoints(toDoublePairs(points), min, max)
    let boundingRect = BoundingRect(
        min[0], min[1], max[0] - min[0], max[1] - min[1]
    )

    let width = boundingRect.width
    let height = boundingRect.height
    let x = boundingRect.x
    let y = boundingRect.y

    let pt0 = Point()
    let pt1 = Point()
    if width > height {
        pt0.x = x + width / 2; pt1.x = pt0.x
        pt0.y = y
        pt1.y = y + height
    }
    else {
        pt0.y = y + height / 2; pt1.y = pt0.y
        pt0.x = x
        pt1.x = x + width
    }
    return splitPolygonByLine(points, pt0, pt1)
}


// upstream: function binaryDivideRecursive<T extends Path['shape']>(divider, shape, count, out): T[]
//   Specialized to PolygonShape; `out` is an inout [PathShape] (the shared `outShapes`), and the
//   return value (upstream returns `out`) is dropped — all call sites use it as a statement.
private func binaryDivideRecursive(
    _ divider: BinaryDivide, _ shape: PolygonShape, _ count: Double, _ out: inout [PathShape]
) {
    if count == 1 {
        out.append(shape)
    }
    else {
        let mid = floor(count / 2)
        let sub = divider(shape)
        binaryDivideRecursive(divider, sub[0], mid, &out)
        binaryDivideRecursive(divider, sub[1], count - mid, &out)
    }
}

public func clone(_ path: Path, _ count: Double) -> [Path] {
    var paths: [Path] = []
    for _ in 0..<Int(count) {
        paths.append(clonePath(path))
    }
    return paths
}

private func copyPathProps(_ source: Path, _ target: Path) {
    // upstream: target.setStyle(source.style);
    // PORT-TODO: our rich style is `pathStyle` (PathStyleProps); mirror clonePath's approach
    //   (useStyle round-trips the magic style by value). Merge-vs-replace edge cases deferred.
    target.useStyle(source.pathStyle)
    target.z = source.z
    target.z2 = source.z2
    target.zlevel = source.zlevel
}

private func polygonConvert(_ points: [Double]) -> [VectorArray] {
    var out: [VectorArray] = []
    var i = 0
    while i < points.count {
        let x = points[i]; i += 1
        let y = points[i]; i += 1
        out.append(VectorArray(x, y))
    }
    return out
}

public func split(
    _ path: Path, _ count: Double
) -> [Path] {
    var outShapes: [PathShape] = []
    let shape = path.shape!
    // upstream: let OutShapeCtor: new() => Path; — modeled as a factory closure (CONVENTIONS §2/§8).
    var OutShapeCtor: (() -> Path)? = nil
    // TODO Use clone when shape size is small
    switch path.type {
    case "rect":
        divideRect(shape as! RectShape, count, &outShapes)
        OutShapeCtor = { Rect() }
    case "sector":
        divideSector(shape as! SectorShape, count, &outShapes)
        OutShapeCtor = { Sector() }
    case "circle":
        let circleShape = shape as! CircleShape
        var sectorShape = SectorShape()
        sectorShape.r0 = 0
        sectorShape.r = circleShape.r
        sectorShape.startAngle = 0
        sectorShape.endAngle = Double.pi * 2
        sectorShape.cx = circleShape.cx
        sectorShape.cy = circleShape.cy
        divideSector(sectorShape, count, &outShapes)
        OutShapeCtor = { Sector() }
    default:
        let m = path.getComputedTransform()
        let scale: Double = m != nil ? sqrt(Swift.max(m![0] * m![0] + m![1] * m![1], m![2] * m![2] + m![3] * m![3])) : 1
        let polygons = util.map(
            pathToPolygons(path.getUpdatedPathProxy(), scale)
        ) { poly, _ in polygonConvert(poly) }
        let polygonCount = polygons.count
        if polygonCount == 0 {
            // PORT-TODO: upstream indexes `polygons[0]` here even though polygonCount === 0 (a latent
            //   upstream bug — `polygons[0]` is `undefined` in JS). Guarded to avoid a Swift bounds
            //   trap; the empty-polygon path yields an empty point set.
            binaryDivideRecursive(binaryDividePolygon, makePolygonShape(polygons.first ?? []), count, &outShapes)
        }
        else if Double(polygonCount) == count {   // In case we only split batched paths to non-batched paths. No need to split.
            for i in 0..<polygonCount {
                outShapes.append(makePolygonShape(polygons[i]))
            }
        }
        else {
            // Most complex case. Assign multiple subpath to each polygon based on it's area.
            var totalArea: Double = 0
            var items = util.map(polygons) { poly, _ -> (poly: [VectorArray], area: Double) in
                var min = VectorArray()
                var max = VectorArray()
                (min, max) = bbox.fromPoints(toDoublePairs(poly), min, max)
                // TODO: polygon area?
                let area = (max[1] - min[1]) * (max[0] - min[0])
                totalArea += area
                return (poly: poly, area: area)
            }
            items.sort { a, b in b.area < a.area }   // upstream: (a, b) => b.area - a.area (descending)

            var left = count
            for i in 0..<polygonCount {
                let item = items[i]
                if left <= 0 {
                    break
                }

                let selfCount = i == polygonCount - 1
                    ? left   // Use the last piece directly
                    : ceil(item.area / totalArea * count)

                if selfCount < 0 {
                    continue
                }

                binaryDivideRecursive(binaryDividePolygon, makePolygonShape(item.poly), selfCount, &outShapes)
                left -= selfCount
            }
        }
        OutShapeCtor = { Polygon() }
    }

    if OutShapeCtor == nil {
        // Unkown split algorithm. Use clone instead
        return clone(path, count)
    }
    var out: [Path] = []

    for i in 0..<outShapes.count {
        let subPath = OutShapeCtor!()
        subPath.setShape(outShapes[i])
        copyPathProps(path, subPath)
        out.append(subPath)
    }

    return out
}
