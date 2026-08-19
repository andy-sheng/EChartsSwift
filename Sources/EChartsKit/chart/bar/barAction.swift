// Ported from echarts/src/chart/bar/install.ts (`changeAxisOrder`) — keep in sync with upstream.

import Foundation

/// Register the internal action used by realtime-sort bars after two animated values cross.
/// The handler updates the category axis' sort mapping. In upstream this action declares a full
/// `update`, but this port's full-update path clones every SeriesData before rendering. Doing that from
/// the zrender `rendered` callback destroys the bar elements' diff identity and leaves the old bars in
/// their leave animation while replacement bars enter (the visible double-label/double-bar race bug).
/// The axis and processed data are already current here; `updateLayout` reruns the folded layout stages
/// and renders with the real `changeAxisOrder` payload while preserving the live elements.
public func installBarAction(_ registers: EChartsExtensionInstallRegisters) {
    _ = registers

    var info = ActionInfo(type: "changeAxisOrder")
    info.event = "changeAxisOrder"
    info.update = "updateLayout"
    registerAction(info) { payload, ecModel, _ in
        guard let sortInfo = payload.other["sortInfo"] as? OrdinalSortInfo else { return nil }
        let componentType = (payload.other["componentType"] as? String) ?? "series"
        let requestedIndex = barActionInt(payload.other["axisId"])

        ecModel.eachComponent(componentType) { component, index in
            if let requestedIndex, requestedIndex != index { return }
            guard let axisModel = component as? AxisBaseModel,
                  let axis = axisModel.axis as? Axis2D else { return }
            var axisOption = axisModel.option as? [String: Any] ?? [:]
            axisOption["categorySortInfo"] = sortInfo
            axisModel.option = axisOption
            _ = axis.setCategorySortInfo(sortInfo)
        }
        return nil
    }
}

private func barActionInt(_ value: Any?) -> Double? {
    if let value = value as? Double { return value }
    if let value = value as? Int { return Double(value) }
    if let value = value as? NSNumber { return value.doubleValue }
    return nil
}
