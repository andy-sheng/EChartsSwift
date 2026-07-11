// Ported from zrender/src/graphic/IncrementalDisplayable.ts — keep in sync with upstream

/**
 * Displayable for incremental rendering. It will be rendered in a separate layer
 * IncrementalDisplay have two main methods. `clearDisplayables` and `addDisplayables`
 * addDisplayables will render the added displayables incremetally.
 *
 * It use a notClear flag to tell the painter don't clear the layer if it's the first element.
 *
 * It's not available for SVG rendering.
 */
// upstream imports (resolved to the ported modules):
// import Displayble from './Displayable';
// import BoundingRect from '../core/BoundingRect';
// import { MatrixArray } from '../core/matrix';
// import Group from './Group';
// import { INCREMENTAL_ID_TRUE_COMPAT } from '../core/types';

// upstream: const m: MatrixArray = []  (a reused scratch matrix). Sized to 6 (vs upstream's empty
//   literal that JS grows on first index-write) so the index writes inside `getLocalTransform`
//   don't trap under Swift's bounds checking.
private let m: MatrixArray = MatrixArray(repeating: 0, count: 6)
// TODO Style override ?

public final class IncrementalDisplayable: Displayable {

    // RENDERING: this stays a single leaf `Displayable` in the display list (NOT a flattened container).
    //   The native painter renders it into its own RETAINED device-pixel bitmap — each flush draws only
    //   the *pending* displayables (`eachPendingDisplayable` / cursor) into that bitmap and composites it
    //   into the frame, so old dots are never redrawn (the upstream incremental-layer perf model). See
    //   `CALayerPainter.drawIncrementalRetained`. (An earlier attempt exposed all displayables via
    //   `childrenRef` so they flattened into the normal list — render-correct but O(total)/frame, which
    //   defeated the whole point; the retained bitmap is O(pending)/frame instead.)

    // PORT-NOTE: upstream re-declares `notClear: boolean = true` / `incremental = …` as own fields;
    //   Swift can't redeclare inherited stored properties (both live on `Displayable`), so they are
    //   seeded in `init` instead.

    private var _displayables: [Displayable] = []
    private var _temporaryDisplayables: [Displayable] = []

    // PORT-NOTE: upstream `private _cursor = 0` is a `number`; it is used purely as an array
    //   index / length (never in float math), so it is modeled as `Int` per CONVENTIONS §7.
    private var _cursor: Int = 0

    public override init(_ props: ElementProps? = nil) {
        super.init(props)
        // upstream field initializers:
        self.notClear = true
        self.incremental = INCREMENTAL_ID_TRUE_COMPAT
    }

    // PORT-NOTE: upstream `traverse<T>(cb, context) { cb.call(context, this) }`. The Swift base
    //   `Element.traverse(_ cb: (_ el: Element) -> Void, _ context: Any?)` is non-generic; we
    //   override it and invoke `cb(self)` (the closure capture replaces the bound `this`).
    public override func traverse(_ cb: (_ el: Element) -> Void, _ context: Any? = nil) {
        cb(self)
    }

    // PORT-NOTE: upstream `useStyle()` takes no args; the Swift base
    //   `Displayable.useStyle(_ obj: CommonStyleProps)` carries one, so we override with it and
    //   ignore `obj`, assigning an empty style as upstream does.
    public override func useStyle(_ obj: CommonStyleProps) {
        // Use an empty style
        // PENDING
        self.style = CommonStyleProps()
    }

    // PORT-NOTE: upstream `_useHoverStyle()` takes no args; the Swift base
    //   `Displayable._useHoverStyle(_ obj: CommonStyleProps)` carries one, so we override with it
    //   and ignore `obj`.
    internal override func _useHoverStyle(_ obj: CommonStyleProps) {  // upstream: protected
        // Use an empty style
        // PENDING
        self.__hoverStyle = nil
    }

    // getCurrentCursor / updateCursorAfterBrush
    // is used in graphic.ts. It's not provided for developers
    public func getCursor() -> Int {
        return self._cursor
    }
    // Update cursor after brush.
    public override func innerAfterBrush() {
        self._cursor = self._displayables.count
    }

    public func clearDisplaybles() {
        self._displayables = []
        self._temporaryDisplayables = []
        self._cursor = 0
        self.markRedraw()

        self.notClear = false
    }

    public func clearTemporalDisplayables() {
        self._temporaryDisplayables = []
    }

    public func addDisplayable(_ displayable: Displayable, _ notPersistent: Bool? = nil) {
        if notPersistent ?? false {
            self._temporaryDisplayables.append(displayable)
        }
        else {
            self._displayables.append(displayable)
        }
        self.markRedraw()
    }

    public func addDisplayables(_ displayables: [Displayable], _ notPersistent: Bool? = nil) {
        let notPersistent = notPersistent ?? false
        for i in 0..<displayables.count {
            self.addDisplayable(displayables[i], notPersistent)
        }
    }

    public func getDisplayables() -> [Displayable] {
        return self._displayables
    }

    public func getTemporalDisplayables() -> [Displayable] {
        return self._temporaryDisplayables
    }

    public func eachPendingDisplayable(_ cb: ((_ displayable: Displayable) -> Void)?) {
        for i in self._cursor..<self._displayables.count {
            cb?(self._displayables[i])
        }
        for i in 0..<self._temporaryDisplayables.count {
            cb?(self._temporaryDisplayables[i])
        }
    }

    public override func update() {
        self.updateTransform()
        for i in self._cursor..<self._displayables.count {
            let displayable = self._displayables[i]
            // PENDING
            displayable.parent = self   // upstream: this as unknown as Group
            displayable.update()
            displayable.parent = nil
        }
        for i in 0..<self._temporaryDisplayables.count {
            let displayable = self._temporaryDisplayables[i]
            // PENDING
            displayable.parent = self   // upstream: this as unknown as Group
            displayable.update()
            displayable.parent = nil
        }
    }

    public override func getBoundingRect() -> BoundingRect? {
        if self._rect == nil {
            let rect = BoundingRect(Double.infinity, Double.infinity, -Double.infinity, -Double.infinity)
            for i in 0..<self._displayables.count {
                let displayable = self._displayables[i]
                // PORT-NOTE: upstream assumes `getBoundingRect()` is non-null (Displayable always
                //   returns one); skip a nil child rather than trap.
                guard let childRect = displayable.getBoundingRect()?.clone() else { continue }
                if displayable.needLocalTransform() {
                    childRect.applyTransform(displayable.getLocalTransform(m))
                }
                rect.union(childRect)
            }
            self._rect = rect
        }
        return self._rect
    }

    public override func contain(_ x: Double, _ y: Double) -> Bool {
        let localPos = self.transformCoordToLocal(x, y)
        let rect = self.getBoundingRect()

        if let rect = rect, rect.contain(localPos[0], localPos[1]) {
            for i in 0..<self._displayables.count {
                let displayable = self._displayables[i]
                if displayable.contain(x, y) {
                    return true
                }
            }
        }
        return false
    }

}

// upstream: export default IncrementalDisplayable;
