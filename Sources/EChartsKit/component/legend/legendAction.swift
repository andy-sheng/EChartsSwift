// Ported from echarts/src/component/legend/legendAction.ts — keep in sync with upstream.
//
// The legend selection actions (dispatched by a legend item click, or programmatically). Each mutates
// the LegendModel(s)' `selected` map, then the driver runs a full `update()` (update:'update'), which
// re-runs `legendFilter` → the toggled series shows/hides. Cross-legend sync mirrors upstream so multiple
// legend components stay consistent.

import Foundation
import ZRenderKit

// type LegendSelectMethodNames = 'select' | 'unSelect' | 'toggleSelected' | 'allSelect' | 'inverseSelect';
private func callLegendMethod(_ lm: LegendModel, _ methodName: String, _ name: String?) {
    switch methodName {
    case "select":         if let n = name { lm.select(n) }
    case "unSelect":       if let n = name { lm.unSelect(n) }
    case "toggleSelected": if let n = name { lm.toggleSelected(n) }
    case "allSelect":      lm.allSelect()
    case "inverseSelect":  lm.inverseSelect()
    default: break
    }
}

// function makeSelectedMap(legendModel, out?) — the selected status of every named legend datum.
private func makeSelectedMap(_ legendModel: LegendModel, _ out: inout [String: Bool]) {
    for model in legendModel.getData() {
        guard let name = model.get("name") as? String else { continue }
        // Wrap element
        if name == "\n" || name == "" { continue }
        let isItemSelected = legendModel.isSelected(name)
        if let existing = out[name] {
            // Unselected if any legend is unselected
            out[name] = existing && isItemSelected
        } else {
            out[name] = isItemSelected
        }
    }
}

// function legendSelectActionHandler(methodName, payload, ecModel)
@discardableResult
private func legendSelectActionHandler(_ methodName: String, _ payload: Payload, _ ecModel: GlobalModel) -> [String: Any] {
    let isAllSelect = (methodName == "allSelect" || methodName == "inverseSelect")
    var selectedMap: [String: Bool] = [:]
    var actionLegendIndices: [Double] = []

    let name = payload.other["name"] as? String

    // ecModel.eachComponent({ mainType: 'legend', query: payload }, ...)
    ecModel.eachComponent(QueryConditionKindA(mainType: "legend", query: payload.other)) { legendModelBase, _ in
        guard let legendModel = legendModelBase as? LegendModel else { return }
        if isAllSelect {
            callLegendMethod(legendModel, methodName, nil)
        } else {
            callLegendMethod(legendModel, methodName, name)
        }
        makeSelectedMap(legendModel, &selectedMap)
        actionLegendIndices.append(legendModel.componentIndex)
    }

    var allSelectedMap: [String: Bool] = [:]

    // make selectedMap from all legend components — force other legends to the same selected status.
    ecModel.eachComponent("legend") { legendModelBase, _ in
        guard let legendModel = legendModelBase as? LegendModel else { return }
        for (n, isSelected) in selectedMap {
            if isSelected { legendModel.select(n) } else { legendModel.unSelect(n) }
        }
        makeSelectedMap(legendModel, &allSelectedMap)
    }

    // Return the event explicitly
    return isAllSelect
        ? ["selected": allSelectedMap, "legendIndex": actionLegendIndices]
        : ["name": name as Any, "selected": allSelectedMap]
}

// export function installLegendAction(registers)
public func installLegendAction(_ registers: EChartsExtensionInstallRegisters) {
    _ = registers

    // registerAction('legendToggleSelect', 'legendselectchanged', curry(handler, 'toggleSelected'))
    var toggleInfo = ActionInfo(type: "legendToggleSelect")
    toggleInfo.event = "legendselectchanged"
    toggleInfo.update = "update"
    registerAction(toggleInfo) { payload, ecModel, _ in
        return legendSelectActionHandler("toggleSelected", payload, ecModel)
    }

    // registerAction('legendAllSelect', 'legendselectall', curry(handler, 'allSelect'))
    var allInfo = ActionInfo(type: "legendAllSelect")
    allInfo.event = "legendselectall"
    allInfo.update = "update"
    registerAction(allInfo) { payload, ecModel, _ in
        return legendSelectActionHandler("allSelect", payload, ecModel)
    }

    // registerAction('legendInverseSelect', 'legendinverseselect', curry(handler, 'inverseSelect'))
    var inverseInfo = ActionInfo(type: "legendInverseSelect")
    inverseInfo.event = "legendinverseselect"
    inverseInfo.update = "update"
    registerAction(inverseInfo) { payload, ecModel, _ in
        return legendSelectActionHandler("inverseSelect", payload, ecModel)
    }

    // registerAction('legendSelect', 'legendselected', curry(handler, 'select'))
    var selectInfo = ActionInfo(type: "legendSelect")
    selectInfo.event = "legendselected"
    selectInfo.update = "update"
    registerAction(selectInfo) { payload, ecModel, _ in
        return legendSelectActionHandler("select", payload, ecModel)
    }

    // registerAction('legendUnSelect', 'legendunselected', curry(handler, 'unSelect'))
    var unSelectInfo = ActionInfo(type: "legendUnSelect")
    unSelectInfo.event = "legendunselected"
    unSelectInfo.update = "update"
    registerAction(unSelectInfo) { payload, ecModel, _ in
        return legendSelectActionHandler("unSelect", payload, ecModel)
    }
}
