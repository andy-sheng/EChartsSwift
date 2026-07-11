// Ported from zrender/src/core/Transformable.ts — keep in sync with upstream

import Foundation
import simd

// upstream: import * as matrix from './matrix';
// upstream: import { assignProps } from './util';
// upstream: import * as vector from './vector';

// const mIdentity = matrix.identity;
// (matrix.identity is value-returning per CONVENTIONS §3, so this is a `() -> MatrixArray`)
private let mIdentity = matrix.identity

private let EPSILON: Double = 5e-5

private func isNotAroundZero(_ val: Double) -> Bool {
    return val > EPSILON || val < -EPSILON
}

// Module-level scratch buffers (upstream declares these as module `const` and mutates them).
private var scaleTmp = VectorArray()                 // upstream: const scaleTmp: vector.VectorArray = [];
private var tmpTransform: MatrixArray = []           // upstream: const tmpTransform: matrix.MatrixArray = [];
private var originTransform = matrix.create()        // upstream: const originTransform = matrix.create();
// const abs = Math.abs;  → use Swift.abs at call sites.

// NOTE (CONVENTIONS §2): upstream `class Transformable` is the base that `Element extends`.
// It therefore CANNOT be `final` (it must be subclassable).
// OPEN: base of the `Transformable → Element → Displayable → Path` chain. `Path` is the public
//   subclassing seam (see Path.swift) and Swift requires every superclass of an `open` class to be
//   `open`, so the whole chain is `open` (faithful: upstream these are all subclassable).
open class Transformable {

    // upstream: parent: Transformable
    // weak to avoid the parent<->child retain cycle (parent owns children, child references parent).
    // PORT-TODO: verify capture — upstream uses a plain (strong) reference.
    public weak var parent: Transformable?

    public var x: Double = 0
    public var y: Double = 0

    public var scaleX: Double = 1
    public var scaleY: Double = 1

    public var skewX: Double = 0
    public var skewY: Double = 0

    // Suppose positive y is towards screen-bottom and positive x is towards screen-right;
    // positive rotation means rotating anticlockwise. (opposite to CSS transform rotate)
    public var rotation: Double = 0

    /**
     * Will translated the element to the anchor position before applying other transforms.
     */
    public var anchorX: Double = 0
    public var anchorY: Double = 0
    /**
     * Origin of scale, rotation, skew
     */
    public var originX: Double = 0
    public var originY: Double = 0

    /**
     * Scale ratio
     */
    public var globalScaleRatio: Double = 1

    public var transform: MatrixArray?
    public var invTransform: MatrixArray?

    // ===== morphPath seam (PORT-NOTE: see Tool/morphPath.swift) =====
    // Upstream `prepareMorphPath` monkey-patches `updateTransform` to an identity no-op
    //   (`function updateIdentityTransform(this) { this.transform = null; }`). Swift can't reassign
    //   methods on a live instance, so `updateTransform` consults this flag instead. `saveAndModifyMethod`
    //   / `restoreMethod` set & clear it. Default `false`.
    internal var __morphIgnoreTransform: Bool = false

    public init() {}

    /**
     * Get computed local transform
     */
    public func getLocalTransform(_ m: MatrixArray? = nil) -> MatrixArray {
        return transformableGetLocalTransform(self, m)
    }

    /**
     * Set position from array
     */
    public func setPosition(_ arr: [Double]) {
        self.x = arr[0]
        self.y = arr[1]
    }
    /**
     * Set scale from array
     */
    public func setScale(_ arr: [Double]) {
        self.scaleX = arr[0]
        self.scaleY = arr[1]
    }

    /**
     * Set skew from array
     */
    public func setSkew(_ arr: [Double]) {
        self.skewX = arr[0]
        self.skewY = arr[1]
    }

    /**
     * Set origin from array
     */
    public func setOrigin(_ arr: [Double]) {
        self.originX = arr[0]
        self.originY = arr[1]
    }

    /**
     * If needs to compute transform
     */
    public func needLocalTransform() -> Bool {
        return isNotAroundZero(self.rotation)
            || isNotAroundZero(self.x)
            || isNotAroundZero(self.y)
            || isNotAroundZero(self.scaleX - 1)
            || isNotAroundZero(self.scaleY - 1)
            || isNotAroundZero(self.skewX)
            || isNotAroundZero(self.skewY)
    }

    /**
     * Update global transform
     */
    public func updateTransform() {
        // morphPath seam: when morphing, `updateTransform` is replaced by an identity no-op that
        //   keeps `transform` null (CONVENTIONS §9 / Tool/morphPath.swift). Faithful to upstream
        //   `updateIdentityTransform`.
        if self.__morphIgnoreTransform {
            self.transform = nil
            return
        }
        let parentTransform = self.parent != nil ? self.parent!.transform : nil
        let needLocalTransform = self.needLocalTransform()

        var m = self.transform
        if !(needLocalTransform || parentTransform != nil) {
            if m != nil {
                self.transform = mIdentity()
                // reset invTransform
                self.invTransform = nil
            }
            return
        }

        m = m ?? matrix.create()

        if needLocalTransform {
            m = self.getLocalTransform(m)
        }
        else {
            m = mIdentity()
        }

        // 应用父节点变换
        if let parentTransform = parentTransform {
            if needLocalTransform {
                m = matrix.mul(parentTransform, m!)
            }
            else {
                m = matrix.copy(parentTransform)
            }
        }
        // 保存这个变换矩阵
        self.transform = m

        self.transform = self._resolveGlobalScaleRatio(m!)

        self.invTransform = self.invTransform ?? matrix.create()
        // upstream: matrix.invert(this.invTransform, m) — return discarded; on a singular
        // matrix invert leaves `out` untouched, so we only overwrite when it succeeds.
        if let inv = matrix.invert(self.transform!) {
            self.invTransform = inv
        }
    }

    // upstream: protected
    private func _resolveGlobalScaleRatio(_ m: MatrixArray) -> MatrixArray {
        var m = m
        let globalScaleRatio = self.globalScaleRatio
        // upstream: if (globalScaleRatio != null && globalScaleRatio !== 1)
        // globalScaleRatio is a non-optional Double here, so the `!= null` check is vacuous.
        if globalScaleRatio != 1 {
            scaleTmp = self.getGlobalScale(scaleTmp)
            let relX: Double = scaleTmp[0] < 0 ? -1 : 1
            let relY: Double = scaleTmp[1] < 0 ? -1 : 1
            let sxRaw = ((scaleTmp[0] - relX) * globalScaleRatio + relX) / scaleTmp[0]
            let syRaw = ((scaleTmp[1] - relY) * globalScaleRatio + relY) / scaleTmp[1]
            // upstream: ... || 0  — JS falsy (0 / NaN) collapses to 0; Infinity stays.
            let sx = jsOr0(sxRaw)
            let sy = jsOr0(syRaw)

            m[0] *= sx
            m[1] *= sx
            m[2] *= sy
            m[3] *= sy
        }
        return m
    }

    /**
     * Get computed global transform
     * NOTE: this method will force update transform on all ancestors.
     * Please be aware of the potential performance cost.
     */
    @discardableResult
    public func getComputedTransform() -> MatrixArray? {
        var transformNode: Transformable? = self
        var ancestors: [Transformable] = []
        while transformNode != nil {
            ancestors.append(transformNode!)
            transformNode = transformNode!.parent
        }

        // Update from topdown.
        while let node = ancestors.popLast() {
            transformNode = node
            transformNode!.updateTransform()
        }

        return self.transform
    }

    // upstream types `m` as vector.VectorArray, but it is actually used as a 6-element
    // matrix (m[0]…m[5]). Since VectorArray == SIMD2<Double> only holds 2 lanes here, we
    // type it as MatrixArray.
    // PORT-NOTE: upstream mistypes the param as vector.VectorArray (a `number[]`).
    public func setLocalTransform(_ m: MatrixArray?) {
        guard let m = m else {
            // TODO return or set identity?
            return
        }
        var sx = m[0] * m[0] + m[1] * m[1]
        var sy = m[2] * m[2] + m[3] * m[3]

        let rotation = atan2(m[1], m[0])

        let shearX = Double.pi / 2 + rotation - atan2(m[3], m[2])
        sy = sqrt(sy) * cos(shearX)
        sx = sqrt(sx)

        self.skewX = shearX
        self.skewY = 0
        self.rotation = -rotation

        self.x = m[4]
        self.y = m[5]
        self.scaleX = sx
        self.scaleY = sy

        self.originX = 0
        self.originY = 0
    }
    /**
     * 分解`transform`矩阵到`position`, `rotation`, `scale`
     */
    public func decomposeTransform() {
        if self.transform == nil {
            return
        }
        let parent = self.parent
        var m = self.transform!
        if let parent = parent, parent.transform != nil {
            // Get local transform and decompose them to position, scale, rotation
            parent.invTransform = parent.invTransform ?? matrix.create()
            tmpTransform = matrix.mul(parent.invTransform!, m)
            m = tmpTransform
        }
        let ox = self.originX
        let oy = self.originY
        if ox != 0 || oy != 0 {
            originTransform[4] = ox
            originTransform[5] = oy
            tmpTransform = matrix.mul(m, originTransform)
            tmpTransform[4] -= ox
            tmpTransform[5] -= oy
            m = tmpTransform
        }

        self.setLocalTransform(m)
    }

    /**
     * Get global scale
     */
    @discardableResult
    public func getGlobalScale(_ out: VectorArray? = nil) -> VectorArray {
        let m = self.transform
        var out = out ?? VectorArray()
        guard let m = m else {
            out[0] = 1
            out[1] = 1
            return out
        }
        out[0] = sqrt(m[0] * m[0] + m[1] * m[1])
        out[1] = sqrt(m[2] * m[2] + m[3] * m[3])
        if m[0] < 0 {
            out[0] = -out[0]
        }
        if m[3] < 0 {
            out[1] = -out[1]
        }
        return out
    }
    /**
     * 变换坐标位置到 shape 的局部坐标空间
     */
    public func transformCoordToLocal(_ x: Double, _ y: Double) -> [Double] {
        var v2 = VectorArray(x, y)
        let invTransform = self.invTransform
        if let invTransform = invTransform {
            v2 = vector.applyTransform(v2, invTransform)
        }
        return [v2[0], v2[1]]
    }

    /**
     * 变换局部坐标位置到全局坐标空间
     */
    public func transformCoordToGlobal(_ x: Double, _ y: Double) -> [Double] {
        var v2 = VectorArray(x, y)
        let transform = self.transform
        if let transform = transform {
            v2 = vector.applyTransform(v2, transform)
        }
        return [v2[0], v2[1]]
    }


    public func getLineScale() -> Double {
        let m = self.transform
        // Get the line scale.
        // Determinant of `m` means how much the area is enlarged by the
        // transformation. So its square root can be used as a scale factor
        // for width.
        if let m = m, Swift.abs(m[0] - 1) > 1e-10 && Swift.abs(m[3] - 1) > 1e-10 {
            return sqrt(Swift.abs(m[0] * m[3] - m[2] * m[1]))
        }
        return 1
    }

    public func copyTransform(_ source: Transformable) {
        ZRenderKit.copyTransform(self, source)
    }


    public static func getLocalTransform(_ target: Transformable, _ m: MatrixArray? = nil) -> MatrixArray {
        // Upstream callers pass a reused scratch `const m: MatrixArray = []` and rely on JS
        // auto-extending it when `m[4] = …` is assigned. Swift arrays can't grow by subscript, so an
        // empty/short scratch must be (re)allocated to the 6-slot identity here — otherwise `m[4]`
        // traps with "Index out of range" (e.g. ZRText/Group.getBoundingRect → getLocalTransform([])).
        var m = (m?.count ?? 0) >= 6 ? m! : MatrixArray(repeating: 0, count: 6)

        let ox = jsOr0(target.originX)                           // upstream: target.originX || 0
        let oy = jsOr0(target.originY)                           // upstream: target.originY || 0
        let sx = target.scaleX
        let sy = target.scaleY
        let ax = target.anchorX
        let ay = target.anchorY
        let rotation = jsOr0(target.rotation)                    // upstream: target.rotation || 0
        let x = target.x
        let y = target.y
        let skewX = target.skewX != 0 ? tan(target.skewX) : 0
        // TODO: zrender use different hand in coordinate system and y axis is inversed.
        let skewY = target.skewY != 0 ? tan(-target.skewY) : 0

        // The order of transform (-anchor * -origin * scale * skew * rotate * origin * translate).
        // We merge (-origin * scale * skew) into one. Also did identity in these operations.
        // origin
        if ox != 0 || oy != 0 || ax != 0 || ay != 0 {
            let dx = ox + ax
            let dy = oy + ay
            m[4] = -dx * sx - skewX * dy * sy
            m[5] = -dy * sy - skewY * dx * sx
        }
        else {
            m[4] = 0
            m[5] = 0
        }
        // scale
        m[0] = sx
        m[3] = sy
        // skew
        m[1] = skewY * sx
        m[2] = skewX * sy

        // Apply rotation
        if rotation != 0 {
            m = matrix.rotate(m, rotation)
        }

        // Translate back from origin and apply translation
        m[4] += ox + x
        m[5] += oy + y

        // NOTICE: All of `m[0~5]` must be set, since `m` may be reused.
        return m
    }

    // private static initDefaultProps — upstream seeds prototype defaults
    //   (scaleX = scaleY = globalScaleRatio = 1; x = y = originX = originY = skewX =
    //    skewY = rotation = anchorX = anchorY = 0).
    // Replaced here by stored-property default values above.
}

// upstream: export const transformableGetLocalTransform = Transformable.getLocalTransform;
public func transformableGetLocalTransform(_ target: Transformable, _ m: MatrixArray? = nil) -> MatrixArray {
    return Transformable.getLocalTransform(target, m)
}

public func transformableCreate() -> Transformable {
    return Transformable()
}

public let TRANSFORMABLE_PROPS: [String] = [
    "x", "y", "originX", "originY", "anchorX", "anchorY", "rotation", "scaleX", "scaleY", "skewX", "skewY"
]

// upstream: export type TransformProp = (typeof TRANSFORMABLE_PROPS)[number]
// PORT-NOTE: TransformProp string-literal union has no faithful Swift analogue.

// upstream: export function copyTransform(target, source) { return assignProps(target, source, TRANSFORMABLE_PROPS); }
// PORT-NOTE: util.assignProps is not ported; we copy the TRANSFORMABLE_PROPS set explicitly.
@discardableResult
public func copyTransform(_ target: Transformable, _ source: Transformable) -> Transformable {
    target.x = source.x
    target.y = source.y
    target.originX = source.originX
    target.originY = source.originY
    target.anchorX = source.anchorX
    target.anchorY = source.anchorY
    target.rotation = source.rotation
    target.scaleX = source.scaleX
    target.scaleY = source.scaleY
    target.skewX = source.skewX
    target.skewY = source.skewY
    return target
}

// upstream: export default Transformable;
