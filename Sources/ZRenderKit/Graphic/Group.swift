// Ported from zrender/src/graphic/Group.ts — keep in sync with upstream

/**
 * Group是一个容器，可以插入子节点，Group的变换也会被应用到子节点上
 * @module zrender/graphic/Group
 * @example
 *     const Group = require('zrender/graphic/Group');
 *     const Circle = require('zrender/graphic/shape/Circle');
 *     const g = new Group();
 *     g.position[0] = 100;
 *     g.position[1] = 100;
 *     g.add(new Circle({
 *         style: {
 *             x: 100,
 *             y: 100,
 *             r: 20,
 *         }
 *     }));
 *     zr.add(g);
 */

import Foundation

// upstream imports (resolved to the ported modules):
// import * as zrUtil from '../core/util';                 → util.*
// import Element, { ElementProps } from '../Element';     → Element (same module)
// import BoundingRect from '../core/BoundingRect';        → Core/BoundingRect
// import { MatrixArray } from '../core/matrix';           → Core/matrix
// import Displayable from './Displayable';                → Displayable (graphic/Displayable.swift).
// import { ZRenderType } from '../zrender';               → Element.ZRenderType (forward-declared placeholder)

public typealias GroupProps = ElementProps   // upstream: interface GroupProps extends ElementProps {}

// NOTE (CONVENTIONS §2): upstream `class Group extends Element`. `Element` is a (non-final)
//   `class`, and `Group` is itself never subclassed, but we keep it `public final class`.
// upstream `class Group extends Element` is NOT final — `chart/helper/Symbol` and others extend it.
// `open` (not `final`) so EChartsKit's `Symbol` (a Group wrapping a symbol path) can subclass it.
open class Group: Element {

    // upstream: readonly isGroup = true — Element declares `var isGroup` (default false); set in init.

    private var _children: [Element] = []

    // `override` because GroupProps == ElementProps, so this signature matches Element.init.
    public override init(_ opts: GroupProps? = nil) {
        super.init()

        self.isGroup = true        // upstream: readonly isGroup = true
        self.type = "group"        // upstream: Group.prototype.type = 'group'

        _ = self.attr(opts ?? [:])
    }

    /**
     * Get children reference.
     */
    // PORT-NOTE: Swift `Array` is a value type, so this returns a COPY, not a live reference
    //   like upstream. Storage walks it read-only (see GroupLike), so the copy is acceptable;
    //   revisit if a consumer mutates the returned array expecting it to alias `_children`.
    public func childrenRef() -> [Element] {
        return self._children
    }

    /**
     * Get children copy.
     */
    public func children() -> [Element] {
        return Array(self._children)   // upstream: this._children.slice()
    }

    /**
     * 获取指定 index 的儿子节点
     */
    // upstream return type is `Element`, but JS returns `undefined` out of bounds → `Element?`.
    public func childAt(_ idx: Int) -> Element? {
        if idx < 0 || idx >= self._children.count {
            return nil
        }
        return self._children[idx]
    }

    /**
     * 获取指定名字的儿子节点
     */
    // upstream return type is `Element`, but the loop can fall through (no match) → `Element?`.
    public func childOfName(_ name: String) -> Element? {
        let children = self._children
        for i in 0..<children.count {
            if children[i].name == name {
                return children[i]
            }
        }
        return nil
    }

    public func childCount() -> Int {
        return self._children.count
    }

    /**
     * 添加子节点到最后
     */
    @discardableResult
    public func add(_ child: Element?) -> Group {
        if let child = child {
            if child !== self && child.parent !== self {
                self._children.append(child)
                self._doAdd(child)
            }
            // PORT-NOTE: dev-mode guard (process.env.NODE_ENV !== 'production'):
            //   if (child.__hostTarget) throw 'This elemenet has been used as an attachment';
        }

        return self
    }

    /**
     * 添加子节点在 nextSibling 之前
     */
    @discardableResult
    public func addBefore(_ child: Element?, _ nextSibling: Element?) -> Group {
        if let child = child, child !== self, child.parent !== self,
           let nextSibling = nextSibling, nextSibling.parent === self {

            let children = self._children
            // upstream: children.indexOf(nextSibling) — identity search (objects).
            let idx = children.firstIndex(where: { $0 === nextSibling })

            if let idx = idx, idx >= 0 {
                self._children.insert(child, at: idx)   // upstream: children.splice(idx, 0, child)
                self._doAdd(child)
            }
        }

        return self
    }

    @discardableResult
    public func replace(_ oldChild: Element, _ newChild: Element) -> Group {
        // upstream: zrUtil.indexOf(this._children, oldChild) — identity search.
        if let idx = self._children.firstIndex(where: { $0 === oldChild }), idx >= 0 {
            self.replaceAt(newChild, idx)
        }
        return self
    }

    @discardableResult
    public func replaceAt(_ child: Element?, _ index: Int) -> Group {
        let old = self._children[index]

        if let child = child, child !== self, child.parent !== self, child !== old {
            self._children[index] = child

            old.parent = nil
            let zr = self.__zr
            if let zr = zr {
                old.removeSelfFromZr(zr)
            }

            self._doAdd(child)
        }

        return self
    }

    func _doAdd(_ child: Element) {
        if child.parent != nil {
            // Parent must be a group
            (child.parent as? Group)?.remove(child)
        }

        child.parent = self

        let zr = self.__zr
        if let zr = zr, zr !== child.__zr {    // Only group has __storage

            child.addSelfToZr(zr)
        }

        // NOTE: Group does not mark itself dirty when adding children.
        // Otherwise, a dirty group will dirty all children in _updateAndAddDisplayable,
        // which breaks incremental case.

        zr?.refresh()
    }

    /**
     * Remove child
     * @param child
     */
    @discardableResult
    public func remove(_ child: Element) -> Group {
        let zr = self.__zr

        // upstream: zrUtil.indexOf(children, child) — identity search.
        let idx = self._children.firstIndex(where: { $0 === child })
        guard let idx = idx, idx >= 0 else {
            return self
        }
        self._children.remove(at: idx)   // upstream: children.splice(idx, 1)

        child.parent = nil

        if let zr = zr {

            child.removeSelfFromZr(zr)
        }

        zr?.refresh()

        return self
    }

    /**
     * Remove all children
     */
    @discardableResult
    public func removeAll() -> Group {
        let children = self._children
        let zr = self.__zr
        for i in 0..<children.count {
            let child = children[i]
            if let zr = zr {
                child.removeSelfFromZr(zr)
            }
            child.parent = nil
        }
        self._children.removeAll()   // upstream: children.length = 0

        return self
    }

    /**
     * 遍历所有子节点
     */
    // PORT-NOTE: upstream binds the callback `this` to `context`; Swift closures capture, so
    //   `context` is unused for binding (kept for signature fidelity). `index` is the genuine
    //   array index (upstream types it `number`).
    @discardableResult
    public func eachChild(_ cb: (_ el: Element, _ index: Int) -> Void, _ context: Any? = nil) -> Group {
        let children = self._children
        for i in 0..<children.count {
            let child = children[i]
            cb(child, i)
        }
        return self
    }

    /**
     * Visit all descendants.
     * Return false in callback to stop visit descendants of current node
     */
    // TODO Group itself should also invoke the callback.
    // PORT-NOTE: upstream `cb` returns `boolean | void`; modeled as `-> Bool` (return `true`
    //   to stop descending). This is an OVERLOAD of `Element.traverse` (whose closure returns
    //   `Void`), not an override — the closure types differ. Recursion casts each child to
    //   `Group` to reach this method.
    @discardableResult
    public func traverse(_ cb: (_ el: Element) -> Bool, _ context: Any? = nil) -> Group {
        for i in 0..<self._children.count {
            let child = self._children[i]
            let stopped = cb(child)

            if child.isGroup && !stopped {
                (child as? Group)?.traverse(cb, context)
            }
        }
        return self
    }

    public override func addSelfToZr(_ zr: ZRenderType) {
        super.addSelfToZr(zr)
        for i in 0..<self._children.count {
            let child = self._children[i]
            child.addSelfToZr(zr)
        }
    }

    public override func removeSelfFromZr(_ zr: ZRenderType) {
        super.removeSelfFromZr(zr)
        for i in 0..<self._children.count {
            let child = self._children[i]
            child.removeSelfFromZr(zr)
        }
    }

    // Polymorphic entry (overrides Element.getBoundingRect() -> BoundingRect?). Delegates to the
    // `includeChildren` overload below (upstream's single optional-arg method).
    public override func getBoundingRect() -> BoundingRect? {
        return self.getBoundingRect(nil)
    }

    public func getBoundingRect(_ includeChildren: [Element]?) -> BoundingRect {
        // TODO Caching
        // FIXME: if no child or all ignored, the returned boundingRect (0, 0, 0, 0)
        //  is not a correct bounding rect in some scenarios, such as rect union and intersection detection.
        let tmpRect = BoundingRect(0, 0, 0, 0)
        let children = includeChildren ?? self._children
        let tmpMat: MatrixArray = []
        var rect: BoundingRect? = nil

        for i in 0..<children.count {
            let child = children[i]
            // TODO invisible?
            // PORT-TODO: upstream also skips `(child as Displayable).invisible`; Displayable
            //   (graphic/Displayable.ts) is not ported yet, so only `child.ignore` is checked.
            if child.ignore /* || (child as Displayable).invisible */ {
                continue
            }

            guard let childRect = child.getBoundingRect() else {
                // PORT-NOTE: upstream assumes `getBoundingRect()` returns a BoundingRect
                //   (Displayable always does). Bare Element returns nil here → skip.
                continue
            }
            // upstream `getLocalTransform` always returns a matrix (truthy), so the `else`
            //   branch below is effectively dead; kept structurally for diffability.
            let transform: MatrixArray? = child.getLocalTransform(tmpMat)
            // TODO
            // The boundingRect cacluated by transforming original
            // rect may be bigger than the actual bundingRect when rotation
            // is used. (Consider a circle rotated aginst its center, where
            // the actual boundingRect should be the same as that not be
            // rotated.) But we can not find better approach to calculate
            // actual boundingRect yet, considering performance.
            if let transform = transform {
                BoundingRect.applyTransform(tmpRect, childRect, transform)
                rect = rect ?? tmpRect.clone()
                rect!.union(tmpRect)
            }
            else {
                rect = rect ?? childRect.clone()
                rect!.union(childRect)
            }
        }
        return rect ?? tmpRect
    }
}

// Storage will use childrenRef to get children to render.
// PORT-NOTE: upstream `interface GroupLike extends Element { childrenRef(): Element[] }`. Swift
//   protocols cannot inherit from a class, so the `extends Element` part is dropped; conformers
//   are expected to be `Element` subclasses (i.e. `Group`).
public protocol GroupLike: AnyObject {
    func childrenRef() -> [Element]
}

extension Group: GroupLike {}

public extension Element {
    /// Whether this element currently acts as a CONTAINER, and if so the children to descend into.
    ///
    /// Upstream duck-types `(el as GroupLike).childrenRef` — truthy whenever a `childrenRef` method is
    /// present on the instance: `Group` and `ZRText` always have it; a `Path` acquires a monkey-patched
    /// one ONLY while combine-morphing (`__morphChildrenRef` set by `combineMorph`). Returns the
    /// children for a container, or `nil` for a leaf `Displayable`.
    ///
    /// This is the SINGLE source of truth for that decision so every traversal (`Storage`, the painter's
    /// `flattenDisplayList`) duck-types identically. Narrowing it to a concrete type — `as? GroupLike`
    /// alone (misses the combine-morph `Path`) or `isGroup` (also misses `ZRText`) — silently drops
    /// rich-text spans or combine-morph sub-paths from the display list. Matches upstream Storage.ts.
    func activeChildrenRef() -> [Element]? {
        if let g = self as? GroupLike { return g.childrenRef() }
        if let p = self as? Path, p.__morphChildrenRef != nil { return p.childrenRef() }
        return nil
    }
}

// upstream: export default Group;
