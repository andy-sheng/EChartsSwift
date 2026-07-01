// Ported from echarts/src/model/internalComponentCreator.ts — keep in sync with upstream

// import GlobalModel from './Global';
//     -> GlobalModel: referenced via the conventional public API (currently the
//        `GlobalModel` protocol placeholder in util/types.swift; sibling model files
//        provide the real class this phase).
// import { ComponentOption, ComponentMainType } from '../util/types';  → sibling types.swift
// import { createHashMap, assert } from 'zrender/src/core/util';
//     -> createHashMap: local shim in util/model.swift (PORT-TODO until ZRenderKit ports it);
//        assert: ZRenderKit util.assert.
// import { isComponentIdInternal } from '../util/model';  → model.isComponentIdInternal (model.swift)

import ZRenderKit

// PNEDING:
// (1) Only Internal usage at present, do not export to uses.
// (2) "Internal components" are generated internally during the `Global.ts#_mergeOption`.
//     It is added since echarts 3.
// (3) Why keep supporting "internal component" in global model rather than
//     make each type components manage their models themselves?
//     Because a potential feature that reproduces a chart from a different chart instance
//     might be useful in some BI analysis scenario, where the entire state needs to be
//     retrieved from the current chart instance. So we'd better manage all of the
//     state universally.
// (4) Internal component always merged in "replaceMerge" approach, that is, if the existing
//     internal components does not matched by a new option with the same id, it will be
//     removed.
// (5) In `InternalOptionCreator`, only the previous component models (dependencies) can be read.

public typealias InternalOptionCreator = (_ ecModel: GlobalModel) -> [ComponentOption]

private let internalOptionCreatorMap: HashMap<InternalOptionCreator> = createHashMap()


public func registerInternalOptionCreator(
    _ mainType: ComponentMainType, _ creator: @escaping InternalOptionCreator
) {
    // upstream: assert(internalOptionCreatorMap.get(mainType) == null && creator);
    // `&& creator` is a truthiness check on the function arg, which is always non-nil in Swift, so dropped.
    util.assert(internalOptionCreatorMap.get(mainType) == nil)
    internalOptionCreatorMap.set(mainType, creator)
}


public func concatInternalOptions(
    _ ecModel: GlobalModel,
    _ mainType: ComponentMainType,
    _ newCmptOptionList: [ComponentOption]
) -> [ComponentOption] {
    let internalOptionCreator = internalOptionCreatorMap.get(mainType)
    guard let internalOptionCreator = internalOptionCreator else {
        return newCmptOptionList
    }
    let internalOptions = internalOptionCreator(ecModel)
    // upstream: if (!internalOptions) { return newCmptOptionList; }
    // `internalOptions` is a non-optional [ComponentOption] in Swift, so the nullish guard is dropped.
    if __DEV__ {
        for i in 0..<internalOptions.count {
            util.assert(model.isComponentIdInternal(internalOptions[i]))
        }
    }
    return newCmptOptionList + internalOptions
}
