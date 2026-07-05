// upstream: src/core/echarts.ts — the module-global action registry + `registerAction`.
//
// This file ports the action-registration plumbing that lives, in upstream, as module-scoped
// state and functions inside echarts.ts:
//   - the `ActionInfoParsed` type (echarts.ts:2878-2885)
//   - the module-global `actions` registry + `connectionEventRevertMap` + `publicEventTypeMap`
//     (echarts.ts:2886-2897)
//   - the `ACTION_REG` validation regex (echarts.ts:288)
//   - the three `registerAction` overloads + shared body (echarts.ts:3114-3188)
//
// The descriptor / handler / refine-event TYPES themselves (`ActionInfo`, `ActionHandler`,
// `ActionRefineEvent`, `ECActionEvent`, `ECEventData`) already live in util/types.swift — this
// file REUSES them and only adds the registry state + `registerAction` + an accessor.
//
// PORT NOTE: upstream keeps these as private module locals of echarts.ts. Swift has no
// file-private module scope shared across files, so the registry is module-`internal` here and
// exposed for reads only through `lookupAction(_:)` (the dispatch author reads via that accessor).

import Foundation
import ZRenderKit

// upstream echarts.ts:2878-2885
//   type ActionInfoParsed = {
//       actionType, nonRefinedEventType, refinedEventType,
//       update, action, refineEvent
//   };
public struct ActionInfoParsed {
    public var actionType: String
    public var nonRefinedEventType: String
    public var refinedEventType: String
    public var update: String?                 // ActionInfo['update']
    public var action: ActionHandler?          // ActionInfo['action']
    public var refineEvent: ActionRefineEvent? // ActionInfo['refineEvent']
    public init(
        actionType: String,
        nonRefinedEventType: String,
        refinedEventType: String,
        update: String?,
        action: ActionHandler?,
        refineEvent: ActionRefineEvent?
    ) {
        self.actionType = actionType
        self.nonRefinedEventType = nonRefinedEventType
        self.refinedEventType = refinedEventType
        self.update = update
        self.action = action
        self.refineEvent = refineEvent
    }
}

// upstream echarts.ts:2886-2888 — const actions: { [actionType: string]: ActionInfoParsed } = {};
internal var actions: [String: ActionInfoParsed] = [:]

// upstream echarts.ts:2890-2893
//   Map event type to action type for reproducing action from event for `connect`.
internal var connectionEventRevertMap: [String: String] = [:]

// upstream echarts.ts:2894-2897
//   To remove duplication.  (value is the literal `1` in JS; a Bool flag here.)
internal var publicEventTypeMap: [String: Bool] = [:]

/// Read-only accessor for the module-global `actions` registry, so `EChartsSlim.doDispatchAction`
/// (a different file) can look up a parsed action descriptor without touching internals directly.
public func lookupAction(_ type: String) -> ActionInfoParsed? {
    return actions[type]
}

// upstream echarts.ts:288 — const ACTION_REG = /^[a-zA-Z0-9_]+$/;
private let ACTION_REG = "^[a-zA-Z0-9_]+$"
private func actionRegTest(_ s: String) -> Bool {
    // `^...$` anchors make a substring match equivalent to a whole-string match.
    return s.range(of: ACTION_REG, options: .regularExpression) != nil
}

// ============================================================================
// registerAction — upstream echarts.ts:3114-3188
//
// Upstream is one union-typed function with three overload declarations:
//   registerAction(type, eventType, action)
//   registerAction(type, action)
//   registerAction(actionInfo, action?)
// The three thin overloads below resolve their arguments into the shared `registerActionInternal`,
// which reproduces the upstream body line-by-line (isFunction(arg1) collapse, isObject(arg0)
// branch, createEventType lowercasing, nonRefinedEventType logic, dedup early-return, ACTION_REG
// asserts, and registry population).
// ============================================================================

// registerAction(type: string, eventType: string, action: ActionHandler): void;
public func registerAction(_ type: String, _ eventType: String, _ action: @escaping ActionHandler) {
    registerActionInternal(type, eventType, action)
}

// registerAction(type: string, action: ActionHandler): void;
public func registerAction(_ type: String, _ action: @escaping ActionHandler) {
    // arg1 receives the handler; the internal's isFunction(arg1) collapse handles it.
    registerActionInternal(type, action, nil)
}

// registerAction(actionInfo: ActionInfo, action?: ActionHandler): void;
public func registerAction(_ actionInfo: ActionInfo, _ action: ActionHandler? = nil) {
    // Upstream maps `registerAction(info, handler)` to arg0=info, arg1=handler, action=undefined.
    registerActionInternal(actionInfo, action, nil)
}

// Faithful port of the single upstream `registerAction` body (echarts.ts:3117-3188).
// `arg0` is `String | ActionInfo`, `arg1` is `String | ActionHandler | nil`.
private func registerActionInternal(_ arg0: Any, _ arg1Input: Any?, _ actionInput: ActionHandler?) {
    var action = actionInput
    var arg1 = arg1Input

    var actionType: String                 // ActionInfo['type']
    var publicEventType: String?           // ActionInfo['event']
    var refineEvent: ActionRefineEvent?    // ActionInfo['refineEvent']
    var update: String?                    // ActionInfo['update']
    var publishNonRefinedEvent: Bool?      // ActionInfo['publishNonRefinedEvent']

    // if (isFunction(arg1)) { action = arg1; arg1 = ''; }
    if util.isFunction(arg1) {
        action = arg1 as? ActionHandler
        arg1 = ""
    }

    // if (isObject(arg0)) { ... } else { ... }
    if let info = arg0 as? ActionInfo {
        actionType = info.type
        publicEventType = info.event
        update = info.update
        publishNonRefinedEvent = info.publishNonRefinedEvent
        if action == nil {
            action = info.action
        }
        refineEvent = info.refineEvent
    } else {
        actionType = arg0 as! String
        publicEventType = arg1 as? String
    }

    // function createEventType(actionOrEventType) { return actionOrEventType.toLowerCase(); }
    func createEventType(_ actionOrEventType: String) -> String {
        return actionOrEventType.lowercased()
    }

    // publicEventType = createEventType(publicEventType || actionType);
    //   JS `||`: an empty/undefined `publicEventType` falls back to `actionType`.
    let eventSource = (publicEventType != nil && !(publicEventType!.isEmpty)) ? publicEventType! : actionType
    let resolvedPublicEventType = createEventType(eventSource)

    // const nonRefinedEventType = refineEvent ? createEventType(actionType) : publicEventType;
    let nonRefinedEventType = (refineEvent != nil) ? createEventType(actionType) : resolvedPublicEventType

    // Support calling `registerAction` multiple times with the same action type; dedup early-return.
    // if (actions[actionType]) { return; }
    if actions[actionType] != nil {
        return
    }

    // Validate action type and event name.
    // assert(ACTION_REG.test(actionType) && ACTION_REG.test(publicEventType));
    util.assert(actionRegTest(actionType) && actionRegTest(resolvedPublicEventType))
    if refineEvent != nil {
        // An event replicated from the action will be triggered internally for `connect`.
        util.assert(resolvedPublicEventType != actionType)
    }

    // actions[actionType] = { ... };
    actions[actionType] = ActionInfoParsed(
        actionType: actionType,
        nonRefinedEventType: nonRefinedEventType,
        refinedEventType: resolvedPublicEventType,
        update: update,
        action: action,
        refineEvent: refineEvent
    )

    // publicEventTypeMap[publicEventType] = 1;
    publicEventTypeMap[resolvedPublicEventType] = true
    // if (refineEvent && publishNonRefinedEvent) { publicEventTypeMap[nonRefinedEventType] = 1; }
    if refineEvent != nil && (publishNonRefinedEvent ?? false) {
        publicEventTypeMap[nonRefinedEventType] = true
    }

    // PORT-TODO: upstream's `if (__DEV__ && connectionEventRevertMap[nonRefinedEventType]) error(...)`
    //   dev-only shared-event-name warning is omitted (no __DEV__ flag / logging path wired here).
    // connectionEventRevertMap[nonRefinedEventType] = actionType;
    connectionEventRevertMap[nonRefinedEventType] = actionType
}

// ============================================================================
// registerAction on the install registrar.
//
// Component/chart installs call `registers.registerAction(...)` (see commented call sites in
// component/visualMap/installCommon.swift and chart/sankey/sankeyInstall.swift). These forward to
// the module-global free `registerAction`. The free function is qualified `EChartsKit.registerAction`
// to avoid recursing into these same-named instance methods.
// ============================================================================
extension EChartsExtensionInstallRegisters {
    public func registerAction(_ type: String, _ eventType: String, _ action: @escaping ActionHandler) {
        EChartsKit.registerAction(type, eventType, action)
    }
    public func registerAction(_ type: String, _ action: @escaping ActionHandler) {
        EChartsKit.registerAction(type, action)
    }
    public func registerAction(_ actionInfo: ActionInfo, _ action: ActionHandler? = nil) {
        EChartsKit.registerAction(actionInfo, action)
    }
}
