// Ported from echarts/src/component/legend/legendScrollAction.ts — keep in sync with upstream.

import Foundation

/// Register the page-flip action dispatched by ScrollableLegendView's page controls.
public func installScrollableLegendAction(_ registers: EChartsExtensionInstallRegisters) {
    _ = registers
    var info = ActionInfo(type: "legendScroll")
    info.event = "legendscroll"
    info.update = "updateView"
    registerAction(info) { payload, ecModel, _ in
        guard let number = payload.other["scrollDataIndex"] as? NSNumber else { return nil }
        ecModel.eachComponent(
            QueryConditionKindA(
                mainType: "legend", query: payload.other, subType: "scroll"
            )
        ) { component, _ in
            (component as? ScrollableLegendModel)?.setScrollDataIndex(number.doubleValue)
        }
        return nil
    }
}
