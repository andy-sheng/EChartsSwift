// Ported from zrender/src/Storage.ts — keep in sync with upstream

import Foundation

// upstream imports (resolved to the ported Core/graphic modules):
// import * as util from './core/util';                         → util.*
// import Group, { GroupLike } from './graphic/Group';          → Group / GroupLike
// import Element from './Element';                              → Element
// import timsort from './core/timsort';                        → see note below
// import Displayable from './graphic/Displayable';             → Displayable
// import Path from './graphic/Path';                           → Path
// import { REDRAW_BIT } from './graphic/constants';            → REDRAW_BIT
// import { NullUndefined } from './core/types';                → modeled as Optional (CONVENTIONS §6)

// PORT-NOTE: upstream uses `timsort` ("because in most case elements are partially sorted").
//   No timsort has been ported (Phase 0 has none). We use Swift's standard-library sort, which
//   is GUARANTEED STABLE as of Swift 5 (SE-0372) — so equal-priority elements keep their
//   insertion order, matching timsort's stable behavior that this code relies on for the
//   (zlevel, z, z2, insertion) ordering. See `updateDisplayList`.

fileprivate var invalidZErrorLogged = false
fileprivate func logInvalidZError() {
    if invalidZErrorLogged {
        return
    }
    invalidZErrorLogged = true
    // console.warn(...)
    print("z / z2 / zlevel of displayable is invalid, which may cause unexpected errors")
}

func shapeCompareFunc(_ a: Displayable, _ b: Displayable) -> Double {
    if a.zlevel == b.zlevel {
        if a.z == b.z {
            return a.z2 - b.z2
        }
        return a.z - b.z
    }
    return a.zlevel - b.zlevel
}

public final class Storage {

    private var _roots: [Element] = []

    private var _displayList: [Displayable] = []

    private var _displayListLen: Int = 0

    public init() {}

    // upstream: traverse<T>(cb: (this: T, el: Element) => void, context?: T)
    // PORT-NOTE: the `<T>`/`this: T` context binding is dropped (Swift closures don't rebind
    //   `this`); `context` is forwarded as `Any?`.
    public func traverse(
        _ cb: (_ el: Element) -> Void,
        _ context: Any? = nil
    ) {
        for i in 0..<self._roots.count {
            self._roots[i].traverse(cb, context)
        }
    }

    /**
     * get a list of elements to be rendered
     *
     * @param {boolean} update whether to update elements before return
     * @param {DisplayParams} params options
     * @return {Displayable[]} a list of elements
     */
    public func getDisplayList(_ update: Bool? = nil, _ includeIgnore: Bool? = nil) -> [Displayable] {
        let includeIgnore = includeIgnore ?? false
        let displayList = self._displayList
        // If displaylist is not created yet. Update force
        if (update ?? false) || displayList.isEmpty {
            self.updateDisplayList(includeIgnore)
        }
        return self._displayList
    }

    /**
     * 更新图形的绘制队列。
     * 每次绘制前都会调用，该方法会先深度优先遍历整个树，更新所有Group和Shape的变换并且把所有可见的Shape保存到数组中，
     * 最后根据绘制的优先级（zlevel > z > 插入顺序）排序得到绘制队列
     */
    public func updateDisplayList(_ includeIgnore: Bool? = nil) {
        self._displayListLen = 0

        let roots = self._roots
        for i in 0..<roots.count {
            self._updateAndAddDisplayable(roots[i], nil, includeIgnore)
        }

        // displayList.length = this._displayListLen — truncate to the slots actually filled.
        if self._displayList.count > self._displayListLen {
            self._displayList.removeSubrange(self._displayListLen..<self._displayList.count)
        }

        // PENDING: Indicatively, it may cost over 10~20ms when list length is over 1e5.
        // See PENDING_SEPARATE_DISPLAY_LIST
        // upstream: timsort(displayList, shapeCompareFunc). Swift's stable sort + a strict-less
        //   wrapper around `shapeCompareFunc` preserves insertion order for equal priorities.
        self._displayList.sort { shapeCompareFunc($0, $1) < 0 }
    }

    private func _updateAndAddDisplayable(
        _ el: Element,
        _ parentClipPaths: [Path]?,
        _ includeIgnore: Bool?
    ) {
        if el.ignore && !(includeIgnore ?? false) {
            return
        }

        el.beforeUpdate()
        el.update()
        el.afterUpdate()

        let userSetClipPath = el.getClipPath()
        let parentHasClipPaths = (parentClipPaths != nil) && (parentClipPaths!.count > 0)
        var clipPathIdx = 0
        var thisClipPaths = el.__clipPaths

        if !el.ignoreClip
            && (parentHasClipPaths || userSetClipPath != nil)
        { // has clipPath in this pass
            if thisClipPaths == nil {
                thisClipPaths = []
                el.__clipPaths = thisClipPaths
            }
            // Build into a fresh buffer; writes are sequential from index 0 and the trailing
            // `.length = clipPathIdx` truncation discards everything past `clipPathIdx`, so this
            // reproduces upstream's in-place overwrite-then-truncate result exactly.
            var buffer: [Path] = []
            if parentHasClipPaths {
                // PENDING: performance?
                for idx in 0..<parentClipPaths!.count {
                    buffer.append(parentClipPaths![idx]); clipPathIdx += 1
                }
            }

            var currentClipPath: Path? = userSetClipPath
            var parentClipPath: Element = el
            // Recursively add clip path
            while let cur = currentClipPath {
                // clipPath 的变换是基于使用这个 clipPath 的元素
                // TODO: parent should be group type.
                cur.parent = parentClipPath
                cur.updateTransform()

                buffer.append(cur); clipPathIdx += 1

                parentClipPath = cur
                currentClipPath = cur.getClipPath()
            }
            thisClipPaths = buffer
        }

        if thisClipPaths != nil { // Remove other old clipPath in array.
            // thisClipPaths.length = clipPathIdx
            var arr = thisClipPaths!
            if arr.count > clipPathIdx {
                arr.removeSubrange(clipPathIdx..<arr.count)
            }
            thisClipPaths = arr
            el.__clipPaths = thisClipPaths
        }

        // ZRText and Group and combining morphing Path may use children.
        // Upstream duck-types `(el as GroupLike).childrenRef`; `activeChildrenRef()` is the shared
        // single-source-of-truth for that decision (Group/Text via GroupLike, a combine-morphing Path
        // via its monkey-patched `__morphChildrenRef`). Before this, the plain `as? GroupLike` cast
        // missed the combine `toPath` — it was drawn as its own (un-morphed) shape while its sub-paths
        // never entered the display list.
        if let children = el.activeChildrenRef() {
            for i in 0..<children.count {
                let child = children[i]

                // Force to mark as dirty if group is dirty
                if el.__dirty != 0 {
                    child.__dirty = Double(Int(child.__dirty) | Int(REDRAW_BIT))
                }

                self._updateAndAddDisplayable(child, thisClipPaths, includeIgnore)
            }

            // Mark group clean here
            el.__dirty = 0

        }
        else {
            let disp = el as! Displayable

            // Avoid invalid z, z2, zlevel cause sorting error.
            if disp.z.isNaN {
                logInvalidZError()
                disp.z = 0
            }
            if disp.z2.isNaN {
                logInvalidZError()
                disp.z2 = 0
            }
            if disp.zlevel.isNaN {
                logInvalidZError()
                disp.zlevel = 0
            }

            // this._displayList[this._displayListLen++] = disp — reuse the buffer slot if any.
            if self._displayListLen < self._displayList.count {
                self._displayList[self._displayListLen] = disp
            }
            else {
                self._displayList.append(disp)
            }
            self._displayListLen += 1
        }

        // Add decal
        let decalEl = (el as? Path)?.getDecalElement()
        if let decalEl = decalEl {
            self._updateAndAddDisplayable(decalEl, thisClipPaths, includeIgnore)
        }

        // Add attached text element and guide line.
        let textGuide = el.getTextGuideLine()
        if let textGuide = textGuide {
            self._updateAndAddDisplayable(textGuide, thisClipPaths, includeIgnore)
        }

        let textEl = el.getTextContent()
        if let textEl = textEl {
            self._updateAndAddDisplayable(textEl, thisClipPaths, includeIgnore)
        }
    }

    /**
     * 添加图形(Displayable)或者组(Group)到根节点
     */
    public func addRoot(_ el: Element) -> Void {
        if let zr = el.__zr, zr.storage === self {
            return
        }

        self._roots.append(el)
    }

    /**
     * 删除指定的图形(Displayable)或者组(Group)
     * @param el
     */
    // upstream: delRoot(el: Element | Element[]). Split into two Swift overloads.
    public func delRoot(_ el: [Element]) {
        for i in 0..<el.count {
            self.delRoot(el[i])
        }
        return
    }

    public func delRoot(_ el: Element) {
        // upstream: util.indexOf(this._roots, el) — identity search (Element is a class and not
        //   Equatable; mirror Group's `firstIndex(where: { $0 === })` identity lookup).
        let idx = self._roots.firstIndex(where: { $0 === el })
        if let idx = idx, idx >= 0 {
            self._roots.remove(at: idx)
        }
    }

    public func delAllRoots() {
        self._roots = []
        self._displayList = []
        self._displayListLen = 0

        return
    }

    public func getRoots() -> [Element] {
        return self._roots
    }

    /**
     * 清空并且释放Storage
     */
    public func dispose() {
        // PORT-NOTE: upstream sets `_displayList = null; _roots = null`. The Swift fields are
        //   non-optional arrays; cleared to empty rather than nil.
        self._displayList = []
        self._roots = []
    }

    public let displayableSortFunc: (Displayable, Displayable) -> Double = shapeCompareFunc
}

// upstream: export default Storage;
