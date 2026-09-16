// upstream: src/core/echarts.ts — the built-in `Default actions` registration block (echarts.ts:3373-3411).
//
// Upstream registers these at MODULE LOAD (top-level `registerAction({...}, noop)` calls at the bottom
// of echarts.ts). The driver has no module-load side effects, so the equivalent is performed once
// from `ECharts.installOnce()` via `registerBuiltinActions()` below.
//
// The ACTION HANDLERS are all `noop`: highlight/downplay/select carry no model-mutating `action` — the
// real work is the LIGHT UPDATE performed by `updateDirectly` (echarts.ts:1772), driven off the
// `update` field of each descriptor:
//   - highlight   → update:'highlight'  → view.highlight(...)   (emphasis state; blur others in loop 1)
//   - downplay    → update:'downplay'   → view.downplay(...)    (normal state)
//   - select      → update:'select'     → toggleSelectionFromPayload + updateSeriesElementSelection
//   - unselect    → update:'unselect'   → (same, unselect branch)
//   - toggleSelect→ update:'toggleSelect'→ (same, toggle branch)

import Foundation
import ZRenderKit

// Local `noop` ActionHandler (upstream `noop` from zrender/core/util, typed as an action handler here).
private let noopAction: ActionHandler = { _, _, _ in nil }

/// Register the built-in highlight/downplay/select/unselect/toggleSelect actions. Idempotent:
/// `registerAction` early-returns on a duplicate action type, so calling this more than once is safe.
func registerBuiltinActions() {
    // The action-type constants live on the `states` namespace (util/states.swift, TASK 1).

    // registerAction({ type: HIGHLIGHT_ACTION_TYPE, event: HIGHLIGHT_ACTION_TYPE, update: HIGHLIGHT_ACTION_TYPE }, noop);
    var highlight = ActionInfo(type: states.HIGHLIGHT_ACTION_TYPE)
    highlight.event = states.HIGHLIGHT_ACTION_TYPE
    highlight.update = states.HIGHLIGHT_ACTION_TYPE
    registerAction(highlight, noopAction)

    // registerAction({ type: DOWNPLAY_ACTION_TYPE, event: DOWNPLAY_ACTION_TYPE, update: DOWNPLAY_ACTION_TYPE }, noop);
    var downplay = ActionInfo(type: states.DOWNPLAY_ACTION_TYPE)
    downplay.event = states.DOWNPLAY_ACTION_TYPE
    downplay.update = states.DOWNPLAY_ACTION_TYPE
    registerAction(downplay, noopAction)

    // registerAction({ type: SELECT_ACTION_TYPE, event: SELECT_CHANGED_EVENT_TYPE, update: SELECT_ACTION_TYPE,
    //                   action: noop, refineEvent: makeSelectChangedEvent, publishNonRefinedEvent: true });
    // TODO: requires `makeSelectChangedEvent` (echarts.ts:3415, itself needs
    //   getAllSelectedIndices) + the message-center emission — the whole refineEvent/event path is
    //   DEFERRED (see ECharts.doDispatchAction, ECharts.swift:2190). Registering with `refineEvent == nil`
    //   makes `nonRefinedEventType` resolve to 'selectchanged' instead of the action type; harmless while
    //   no events are emitted. The `update`/`action` fields (the parts `updateDirectly` consumes) are exact.
    for selType in [states.SELECT_ACTION_TYPE, states.UNSELECT_ACTION_TYPE, states.TOGGLE_SELECT_ACTION_TYPE] {
        var info = ActionInfo(type: selType)
        info.event = states.SELECT_CHANGED_EVENT_TYPE
        info.update = selType
        info.action = noopAction
        info.publishNonRefinedEvent = true
        // info.refineEvent = makeSelectChangedEvent   // note (deferred, see above).
        registerAction(info, nil)
    }
}
