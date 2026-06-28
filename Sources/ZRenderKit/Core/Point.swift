// Ported from zrender/src/core/Point.ts — keep in sync with upstream

import Foundation

// MatrixArray comes from matrix.swift (typealias MatrixArray = [Double]).

// Faithful port of the JS `x || 0` idiom (NOT `x ?? 0`): JS treats `0`, `NaN`, `null`, and
// `undefined` as falsy, so `x || 0` substitutes 0 for all of them. `?? 0` only covers nil,
// leaving NaN intact — which would poison transform matrices / origins downstream. Used by
// `Point` ctor and `Transformable` (originX/Y, rotation, scale-ratio). See PORT_STATUS §3
// item 3. Accepts an Optional so it serves both `x?: number` and non-optional `number` sites
// (non-optionals promote to Optional automatically).
@inline(__always) func jsOr0(_ x: Double?) -> Double {
    guard let x = x, x != 0, !x.isNaN else { return 0 }
    return x
}

// upstream: export interface PointLike { x: number; y: number }
// Modeled as a class-bound protocol so the `static` out-param mutators below
// (set/copy/add/sub/scale/...) mutate the caller's object in place via reference
// semantics, matching upstream's in-place mutation of the `out` argument.
// PORT-TODO: upstream PointLike is a structural interface that also accepts plain
// object literals / value types; we constrain to AnyObject to preserve mutation.
public protocol PointLike: AnyObject {
    var x: Double { get set }
    var y: Double { get set }
}

public final class Point: PointLike {

    public var x: Double

    public var y: Double

    public init(_ x: Double? = nil, _ y: Double? = nil) {
        self.x = jsOr0(x)   // upstream: this.x = x || 0
        self.y = jsOr0(y)   // upstream: this.y = y || 0
    }

    /**
     * Copy from another point
     */
    @discardableResult
    public func copy(_ other: PointLike) -> Point {
        self.x = other.x
        self.y = other.y
        return self
    }

    /**
     * Clone a point
     */
    public func clone() -> Point {
        return Point(self.x, self.y)
    }

    /**
     * Set x and y
     */
    @discardableResult
    public func set(_ x: Double, _ y: Double) -> Point {
        self.x = x
        self.y = y
        return self
    }

    /**
     * If equal to another point
     */
    public func equal(_ other: PointLike) -> Bool {
        return other.x == self.x && other.y == self.y
    }

    /**
     * Add another point
     */
    @discardableResult
    public func add(_ other: PointLike) -> Point {
        self.x += other.x
        self.y += other.y
        return self
    }

    public func scale(_ scalar: Double) {
        self.x *= scalar
        self.y *= scalar
    }

    public func scaleAndAdd(_ other: PointLike, _ scalar: Double) {
        self.x += other.x * scalar
        self.y += other.y * scalar
    }

    /**
     * Sub another point
     */
    @discardableResult
    public func sub(_ other: PointLike) -> Point {
        self.x -= other.x
        self.y -= other.y
        return self
    }

    /**
     * Dot product with other point
     */
    public func dot(_ other: PointLike) -> Double {
        return self.x * other.x + self.y * other.y
    }

    /**
     * Get length of point
     */
    public func len() -> Double {
        return sqrt(self.x * self.x + self.y * self.y)
    }

    /**
     * Get squared length
     */
    public func lenSquare() -> Double {
        return self.x * self.x + self.y * self.y
    }

    /**
     * Normalize
     */
    @discardableResult
    public func normalize() -> Point {
        let len = self.len()
        self.x /= len
        self.y /= len
        return self
    }

    /**
     * Distance to another point
     */
    public func distance(_ other: PointLike) -> Double {
        let dx = self.x - other.x
        let dy = self.y - other.y
        return sqrt(dx * dx + dy * dy)
    }

    /**
     * Square distance to another point
     */
    public func distanceSquare(_ other: Point) -> Double {
        let dx = self.x - other.x
        let dy = self.y - other.y
        return dx * dx + dy * dy
    }

    /**
     * Negate
     */
    @discardableResult
    public func negate() -> Point {
        self.x = -self.x
        self.y = -self.y
        return self
    }

    /**
     * Apply a transform matrix array.
     */
    @discardableResult
    public func transform(_ m: MatrixArray?) -> Point? {
        guard let m = m else {
            return nil
        }
        let x = self.x
        let y = self.y
        self.x = m[0] * x + m[2] * y + m[4]
        self.y = m[1] * x + m[3] * y + m[5]
        return self
    }

    // upstream mutates the passed-in `out` array and returns it. `[Double]` is a
    // value type in Swift, so we follow CONVENTIONS §3 (single scratch-array output):
    // return the (mutated copy of the) array; call site does `out = p.toArray(out)`.
    public func toArray(_ out: [Double]) -> [Double] {
        var out = out
        out[0] = self.x
        out[1] = self.y
        return out
    }

    public func fromArray(_ input: [Double]) {
        self.x = input[0]
        self.y = input[1]
    }

    public static func set(_ p: PointLike, _ x: Double, _ y: Double) {
        p.x = x
        p.y = y
    }

    public static func copy(_ p: PointLike, _ p2: PointLike) {
        p.x = p2.x
        p.y = p2.y
    }

    public static func len(_ p: PointLike) -> Double {
        return sqrt(p.x * p.x + p.y * p.y)
    }

    public static func lenSquare(_ p: PointLike) -> Double {
        return p.x * p.x + p.y * p.y
    }

    public static func dot(_ p0: PointLike, _ p1: PointLike) -> Double {
        return p0.x * p1.x + p0.y * p1.y
    }

    public static func add(_ out: PointLike, _ p0: PointLike, _ p1: PointLike) {
        out.x = p0.x + p1.x
        out.y = p0.y + p1.y
    }

    public static func sub(_ out: PointLike, _ p0: PointLike, _ p1: PointLike) {
        out.x = p0.x - p1.x
        out.y = p0.y - p1.y
    }

    public static func scale(_ out: PointLike, _ p0: PointLike, _ scalar: Double) {
        out.x = p0.x * scalar
        out.y = p0.y * scalar
    }

    public static func scaleAndAdd(_ out: PointLike, _ p0: PointLike, _ p1: PointLike, _ scalar: Double) {
        out.x = p0.x + p1.x * scalar
        out.y = p0.y + p1.y * scalar
    }

    public static func lerp(_ out: PointLike, _ p0: PointLike, _ p1: PointLike, _ t: Double) {
        let onet = 1 - t
        out.x = onet * p0.x + t * p1.x
        out.y = onet * p0.y + t * p1.y
    }
}
