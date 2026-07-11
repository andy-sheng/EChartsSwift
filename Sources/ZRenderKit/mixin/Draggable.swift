// Ported from zrender/src/mixin/Draggable.ts — keep in sync with upstream
//
// Composition choice (documented per task brief):
// Upstream `Draggable` is already a standalone class that Handler *composes* (Handler keeps a
// private `_draggingMgr = new Draggable(this)`), not a method-set mixed into Handler's prototype.
// So the faithful Swift port is a `final class Draggable` (reference type — it holds drag state
// across events). Because the concrete `Handler` lives at the native-event seam and is not yet
// translated (its DOM proxy, `dom/HandlerProxy.ts`, is replaced by a hand-written UIKit bridge —
// see CONVENTIONS §9), Draggable depends on Handler through the minimal `DraggableHandler`
// protocol below: exactly the three Handler members Draggable calls (`on`, `dispatchToElement`,
// `findHover`). When `Handler` is ported it conforms to `DraggableHandler`, and Handler's ctor
// creates `Draggable(self)` just like upstream.
//
// The `handler` back-reference is `unowned` to break the Handler→Draggable→Handler retain cycle
// (Handler strongly owns its `_draggingMgr`, and Handler always outlives it). // PORT-NOTE: verify capture

// import Handler from '../Handler';
// import Element, { ElementEvent } from '../Element';
// import Displayable from '../graphic/Displayable';

/// Target-info bag passed to `Handler.dispatchToElement` / returned by `Handler.findHover`.
/// Upstream uses inline object types `{ target?: Element; topTarget?: Element }`; modeled here as
/// a protocol so both `Param` (below) and Handler's `HoveredResult` satisfy it.
public protocol DraggableTargetInfo: AnyObject {
    var target: Element? { get }
    var topTarget: Element? { get }
}

/// The slice of `Handler` (an `Eventful` subclass) that `Draggable` composes with.
public protocol DraggableHandler: AnyObject {
    @discardableResult
    func on(_ event: String, _ handler: @escaping EventCallback, _ context: AnyObject?) -> Eventful
    // PORT-NOTE: `event` is the ZRRawEvent (browser DOM event), Any? at the native event seam.
    func dispatchToElement(_ targetInfo: DraggableTargetInfo, _ eventName: ElementEventName, _ event: Any?)
    // upstream returns Handler's `HoveredResult` (which conforms to `DraggableTargetInfo`). The
    //   requirement uses the concrete `HoveredResult` (defined in Handler.swift, same module)
    //   rather than the `DraggableTargetInfo` existential: a Swift protocol witness cannot return
    //   a concrete type to satisfy a requirement typed as a protocol existential. Draggable only
    //   reads `.target` (an `Element?`), which `HoveredResult` provides.
    func findHover(_ x: Double, _ y: Double, _ exclude: Displayable?) -> HoveredResult
}

final class Param: DraggableTargetInfo {

    var target: Element?
    var topTarget: Element?

    init(_ target: Element?, _ e: ElementEvent?) {
        self.target = target
        self.topTarget = e?.topTarget
    }
}

// FIXME Draggable on element which has parent rotation or scale
public final class Draggable {

    unowned let handler: DraggableHandler

    var _draggingTarget: Element?
    var _dropTarget: Element?

    var _x: Double = 0
    var _y: Double = 0

    public init(_ handler: DraggableHandler) {
        self.handler = handler

        handler.on("mousedown", { [weak self] _, args in self?._dragStart(args); return nil }, self)
        handler.on("mousemove", { [weak self] _, args in self?._drag(args); return nil }, self)
        handler.on("mouseup", { [weak self] _, args in self?._dragEnd(args); return nil }, self)
        // `mosuemove` and `mouseup` can be continue to fire when dragging.
        // See [DRAG_OUTSIDE] in `Handler.js`. So we do not need to trigger
        // `_dragEnd` when globalout. That would brings better user experience.
        // this.on('globalout', this._dragEnd, this);

        // this._dropTarget = null;
        // this._draggingTarget = null;

        // this._x = 0;
        // this._y = 0;
    }

    // PORT-NOTE: upstream listeners take `(e: ElementEvent)` directly; here they are bound through
    //   `Eventful.on`, whose callback receives `[Any?]` args. These thin shims unwrap `args[0]` to
    //   the dispatched `ElementEvent` and forward to the faithful `_drag*` bodies below.
    private func _dragStart(_ args: [Any?]) {
        guard let e = args.first as? ElementEvent else { return }
        _dragStart(e)
    }
    private func _drag(_ args: [Any?]) {
        guard let e = args.first as? ElementEvent else { return }
        _drag(e)
    }
    private func _dragEnd(_ args: [Any?]) {
        guard let e = args.first as? ElementEvent else { return }
        _dragEnd(e)
    }

    func _dragStart(_ e: ElementEvent) {
        var draggingTarget = e.target
        // Find if there is draggable in the ancestor
        while draggingTarget != nil && draggingTarget!.draggable == .false {
            draggingTarget = (draggingTarget!.parent as? Element) ?? draggingTarget!.__hostTarget
        }
        if let draggingTarget = draggingTarget {
            self._draggingTarget = draggingTarget
            draggingTarget.dragging = true
            self._x = e.offsetX
            self._y = e.offsetY

            self.handler.dispatchToElement(
                Param(draggingTarget, e), .dragstart, e.event
            )
        }
    }

    func _drag(_ e: ElementEvent) {
        let draggingTarget = self._draggingTarget
        if let draggingTarget = draggingTarget {

            let x = e.offsetX
            let y = e.offsetY

            let dx = x - self._x
            let dy = y - self._y
            self._x = x
            self._y = y

            draggingTarget.drift(dx, dy, e)
            self.handler.dispatchToElement(
                Param(draggingTarget, e), .drag, e.event
            )

            let dropTarget = self.handler.findHover(
                x, y, draggingTarget as? Displayable // PENDING
            ).target
            let lastDropTarget = self._dropTarget
            self._dropTarget = dropTarget

            if draggingTarget !== dropTarget {
                if let lastDropTarget = lastDropTarget, dropTarget !== lastDropTarget {
                    self.handler.dispatchToElement(
                        Param(lastDropTarget, e), .dragleave, e.event
                    )
                }
                if let dropTarget = dropTarget, dropTarget !== lastDropTarget {
                    self.handler.dispatchToElement(
                        Param(dropTarget, e), .dragenter, e.event
                    )
                }
            }
        }
    }

    func _dragEnd(_ e: ElementEvent) {
        let draggingTarget = self._draggingTarget

        if let draggingTarget = draggingTarget {
            draggingTarget.dragging = false
        }

        self.handler.dispatchToElement(Param(draggingTarget, e), .dragend, e.event)

        if let _dropTarget = self._dropTarget {
            self.handler.dispatchToElement(Param(_dropTarget, e), .drop, e.event)
        }

        self._draggingTarget = nil
        self._dropTarget = nil
    }

}
