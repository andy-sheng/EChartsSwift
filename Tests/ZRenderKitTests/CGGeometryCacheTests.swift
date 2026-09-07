import XCTest
import ZRenderKit
import NativePainter
#if canImport(CoreGraphics)
import CoreGraphics

final class CGGeometryCacheTests: XCTestCase {
    func testCommandsPercentAndThresholdInvalidateIndependently() {
        let cache = CGGeometryCache()
        let proxy = PathProxy()
        _ = proxy.moveTo(0, 0).lineTo(20, 0).lineTo(40, 0)
        let full = cache.path(for: proxy)
        XCTAssertTrue(full === cache.path(for: proxy))
        XCTAssertEqual(cache.path(for: proxy, percent: 0.5).boundingBoxOfPath.maxX, 20, accuracy: 0.001)
        XCTAssertEqual(cache.path(for: proxy).boundingBoxOfPath.maxX, 40)

        // setData does not increment the upstream version; same-length replacement must still work.
        let version = proxy.getVersion()
        proxy.setData([1, 0, 0, 2, 20, 0, 2, 60, 0])
        XCTAssertEqual(proxy.getVersion(), version)
        XCTAssertEqual(cache.path(for: proxy).boundingBoxOfPath.maxX, 60)
        let changed = cache.path(for: proxy)
        proxy.setScale(1, 1, 30)
        XCTAssertFalse(changed === cache.path(for: proxy))
        let rebuilt = CGPathRebuilder()
        proxy.rebuildPath(rebuilt, 1)
        XCTAssertEqual(cache.path(for: proxy), rebuilt.path)
    }

    func testCapacityEvictionClearAndWeakSceneOwnership() {
        let cache = CGGeometryCache(maxEntries: 2, maxCommands: 10)
        let a = PathProxy(); _ = a.rect(0, 0, 2, 3)
        let b = PathProxy(); _ = b.rect(1, 1, 2, 3)
        let c = PathProxy(); _ = c.rect(2, 2, 2, 3)
        let first = cache.path(for: a)
        _ = cache.path(for: b); _ = cache.path(for: c)
        XCTAssertFalse(first === cache.path(for: a))
        let last = cache.path(for: a)
        cache.removeAll()
        XCTAssertFalse(last === cache.path(for: a))
        weak var released: PathProxy?
        do {
            let temporary = PathProxy(); released = temporary
            _ = temporary.rect(0, 0, 2, 3)
            _ = cache.path(for: temporary)
        }
        XCTAssertNil(released)

        // Repeated replacement must not leave unbounded or invalid FIFO records.
        for i in 0..<100 {
            _ = a.beginPath().rect(Double(i), 0, 2, 3)
            XCTAssertEqual(cache.path(for: a).boundingBoxOfPath.minX, Double(i))
        }
    }

    func testCachedPainterMatchesFreshRenderingAfterClipShapeAndTransformChanges() {
        let painter = CALayerPainter(size: CGSize(width: 80, height: 80), dpr: 1)
        let root = Group()
        let rect = Rect(); var shape = RectShape()
        shape.x = 5; shape.y = 5; shape.width = 50; shape.height = 50
        rect.setShape(shape)
        let clip = Rect(); var clipShape = shape; clipShape.width = 20
        clip.setShape(clipShape); rect.setClipPath(clip)
        _ = root.add(rect)
        for i in 0..<4 {
            if i == 1 { rect.x = 10; rect.markRedraw() }
            if i == 2 { clipShape.width = 40; clip.setShape(clipShape) }
            if i == 3 { shape.height = 15; rect.setShape(shape) }
            let list = flattenDisplayList(root)
            painter.refresh(list)
            let fresh = CALayerPainter(size: CGSize(width: 80, height: 80), dpr: 1)
            fresh.refresh(list)
            let actual = painter.rootLayer.contents as! CGImage
            let expected = fresh.rootLayer.contents as! CGImage
            XCTAssertEqual(actual.dataProvider!.data! as Data, expected.dataProvider!.data! as Data)
        }
    }
}
#endif
