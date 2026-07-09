// Ported from echarts/src/component/legend/legendFilter.ts — keep in sync with upstream.
//
// The SERIES_FILTER processor behind legend show/hide: a series is dropped from the rendered set when
// its name is UNSELECTED in ANY legend component (a series absent from a legend is assumed selected).
// Registered upstream at PRIORITY.PROCESSOR.SERIES_FILTER; the driver invokes `legendFilter(ecModel)`
// directly in the data-processor stage (before coordSysMgr.update, so a hidden series contributes no axis
// extent, and before the visual + view stages, so it does not render). `filterSeries` shrinks
// `_seriesIndices`, which `eachSeries`/renderSeries honour; `restoreData()` (run at the top of each
// update) resets it, so toggling a legend item back on restores the series.

import Foundation
import ZRenderKit

// export const legendFilterStageHandler = createSimpleOverallStageHandler2(legendFilter);
public func legendFilter(_ ecModel: GlobalModel) {
    // const legendModels = ecModel.findComponents({ mainType: 'legend' }) as LegendModel[];
    let legendModels = ecModel.findComponents(QueryConditionKindA(mainType: "legend"))
    if !legendModels.isEmpty {
        ecModel.filterSeries { series, _ in
            // If in any legend component the status is not selected.
            // Because in legend series is assumed selected when it is not in the legend data.
            for lm in legendModels {
                if let legend = lm as? LegendModel, !legend.isSelected(series.name) {
                    return false
                }
            }
            return true
        }
    }
}
