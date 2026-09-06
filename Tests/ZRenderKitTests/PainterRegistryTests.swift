import XCTest
@testable import ZRenderKit

final class PainterRegistryTests: XCTestCase {
    private var savedCtors: [String: PainterBaseCtor] = [:]
    private var savedOrder: [String] = []
    override func setUp() {
        savedCtors = painterCtors; savedOrder = painterCtorOrder
        painterCtors = [:]; painterCtorOrder = []
    }
    override func tearDown() {
        painterCtors = savedCtors; painterCtorOrder = savedOrder
    }

    private final class Probe: PainterBase {
        let storage: Storage?
        let type: String
        var frames = 0
        var elements: [Displayable] = []
        var disposed = false
        init(_ storage: Storage, _ type: String) { self.storage = storage; self.type = type }
        func refresh(_ list: [Displayable]) { frames += 1; elements = list }
        func resize(_ width: Double?, _ height: Double?, _ dpr: Double?) {}
        func clear() { elements = [] }
        func getWidth() -> Double { 100 }
        func getHeight() -> Double { 80 }
        func dispose() { disposed = true }
    }

    func testMissingRendererThrowsWithoutCreatingAnInstance() {
        XCTAssertThrowsError(try ZRenderKit.`init`()) { error in
            XCTAssertTrue(String(describing: error).contains("not imported"))
        }
    }

    func testOrderedFallbackAndReplacementMatchUpstream() throws {
        registerPainter("first") { _, storage, _, _ in Probe(storage, "first") }
        registerPainter("second") { _, storage, _, _ in Probe(storage, "second") }
        registerPainter("first") { _, storage, _, _ in Probe(storage, "replacement") }
        var opts = ZRenderInitOpt(); opts.renderer = "missing"
        let zr = try ZRenderKit.`init`(nil, opts)
        defer { zr.dispose() }
        XCTAssertEqual(zr.painter.type, "replacement")
        XCTAssertEqual(painterCtorOrder, ["first", "second"])
    }

    func testFactoryReceivesInstanceStorageOptionsAndID() throws {
        var created: [Probe] = []
        var ids: [Double] = []
        registerPainter("probe") { _, storage, opts, id in
            XCTAssertEqual(opts?.width, 320)
            XCTAssertEqual(opts?.devicePixelRatio, 2)
            XCTAssertEqual(opts?.useDirtyRect, false)
            let p = Probe(storage, "probe"); created.append(p); ids.append(id); return p
        }
        var opts = ZRenderInitOpt(); opts.renderer = "probe"; opts.width = 320; opts.devicePixelRatio = 2
        let a = try ZRenderKit.`init`(nil, opts)
        let b = try ZRenderKit.`init`(nil, opts)
        defer { a.dispose(); b.dispose() }
        XCTAssertTrue(a.storage === created[0].storage)
        XCTAssertTrue(b.storage === created[1].storage)
        XCTAssertFalse(a.painter === b.painter)
        XCTAssertEqual(ids, [a.id, b.id])
        a.add(Rect()); a.refreshImmediately()
        XCTAssertEqual(created[0].elements.count, 1)
        XCTAssertEqual(created[1].frames, 0)
        a.dispose()
        XCTAssertTrue(created[0].disposed)
        XCTAssertFalse(created[1].disposed)
        XCTAssertNil(getInstance(a.id))
    }
}
