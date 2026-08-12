// Ported from echarts/src/component/timeline/TimelineAxis.ts — keep in sync with upstream.
/*
* Licensed to the Apache Software Foundation (ASF) under one
* or more contributor license agreements.  See the NOTICE file
* distributed with this work for additional information
* regarding copyright ownership.  The ASF licenses this file
* to you under the Apache License, Version 2.0 (the
* "License"); you may not use this file except in compliance
* with the License.  You may obtain a copy of the License at
*
*   http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing,
* software distributed under the License is distributed on an
* "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
* KIND, either express or implied.  See the License for the
* specific language governing permissions and limitations
* under the License.
*/

import Foundation
import ZRenderKit

// upstream imports:
//   import Axis from '../../coord/Axis';       -> `Axis` (coord/Axis.swift).
//   import Scale from '../../scale/Scale';      -> `Scale`.
//   import TimelineModel from './TimelineModel'; -> `TimelineModel` (this component).
//   import Model from '../../model/Model';       -> `Model`.

// export type TimelineAxisType = 'category' | 'time' | 'value';  -> a bare `String` in the port.

/**
 * Extend axis 2d
 */
// upstream: class TimelineAxis extends Axis
//   Not further subclassed → `final class` (CONVENTIONS §2).
public final class TimelineAxis: Axis {

    // upstream: `// @ts-ignore` `model: TimelineModel;` — upstream structurally overrides the base
    //   `Axis.model: AxisBaseModel` slot with a `TimelineModel` (a `ComponentModel`, NOT an
    //   `AxisBaseModel`). The Swift base slot `Axis.model: AxisBaseModel!` cannot hold a
    //   `TimelineModel`, so the timeline model is stored in a dedicated property; every method the
    //   timeline render path exercises (`getLabelModel`, `dataToCoord`, `getExtent`, `getViewLabels`
    //   for value/time axisType) reads either this property or `self.scale`, never the base `model`.
    public var timelineModel: TimelineModel!

    // constructor(dim, scale, coordExtent, axisType) { super(dim, scale, coordExtent); this.type = axisType || 'value'; }
    public init(
        _ dim: DimensionName,
        _ scale: Scale,
        _ coordExtent: [Double],
        _ axisType: String?
    ) {
        super.init(dim, scale, coordExtent)
        // this.type = axisType || 'value';
        self.type = (axisType != nil && !axisType!.isEmpty) ? axisType! : "value"
    }

    /**
     * @override
     */
    // getLabelModel() { return this.model.getModel('label'); }
    public override func getLabelModel() -> Model {
        // Force override — the timeline label lives at `timeline.label`, not `axis.axisLabel`.
        return self.timelineModel.getModel("label")
    }

    // PORT-DEVIATION: upstream inherits `Axis.getViewLabels` → `createAxisLabels`, whose CATEGORY branch's
    //   'auto' interval (`makeCategoryLabels` → `makeAutoCategoryInterval` → `calculateCategoryInterval`)
    //   reads the interval cache via `modelInner(axis.model)`. The timeline axis has no base `model` (it
    //   structurally overrides the slot with a `TimelineModel`, held in `timelineModel` — see above), so
    //   the 'auto' path would crash on a `category` axisType. We therefore mirror `createAxisLabels` here
    //   but never invoke the base-model 'auto' machinery: a numeric / callback `label.interval` is honored
    //   faithfully (via `makeTicksLabelsByCategoryIntervalNumOrCb`'s `ordinalScaleCreateTicks`), while the
    //   default 'auto' falls back to interval 0 (all ticks — timelines are small and show every option).
    public override func getViewLabels(_ ctx: AxisLabelsComputingContext? = nil) -> [AxisLabelInfoDetermined] {
        _ = ctx
        let labelFormatter = axisHelper.makeLabelFormatter(self)

        // upstream `createAxisLabels`: "Only ordinal scale support tick interval" — the CATEGORY branch
        //   honors `label.interval`; value/time fall through to `makeRealNumberLabels` (all ticks).
        if self.type == "category", let ordinalScale = self.scale as? OrdinalScale {
            // makeCategoryLabelsActually: optionLabelInterval = getOptionCategoryInterval(labelModel).
            let optionLabelInterval = axisHelper.getOptionCategoryInterval(self.getLabelModel())
            let categoryIntervalCb = optionLabelInterval as? CategoryTickLabelSplitIntervalCb
            // TimelineAxis cannot use the generic category-axis cache because its model is a
            // TimelineModel rather than AxisBaseModel. Still perform the same width/spacing
            // calculation for `auto`, without that cache, so dense year labels are thinned exactly
            // like the web implementation instead of all being rendered on top of one another.
            let numericLabelInterval: Double
            if categoryIntervalCb != nil {
                numericLabelInterval = 0
            }
            else if (optionLabelInterval as? String) == "auto" {
                let extent = ordinalScale.getExtent()
                let unitSpan = abs(self.dataToCoord(extent[0] + 1) - self.dataToCoord(extent[0]))
                var maxWidth = 7.0
                if unitSpan > 0 {
                    var value = extent[0]
                    while value <= extent[1] {
                        let formatted = labelFormatter(ScaleTick(value: value), nil)
                        let rect = text.getBoundingRect(
                            formatted, self.getLabelModel().getFont(), .center, .top
                        )
                        maxWidth = Swift.max(maxWidth, rect.width * 1.3)
                        value += 1
                    }
                }
                numericLabelInterval = unitSpan > 0
                    ? Swift.max(0, floor(maxWidth / unitSpan))
                    : 0
            }
            else {
                numericLabelInterval = (optionLabelInterval as? Double) ?? 0
            }

            // makeTicksLabelsByCategoryIntervalNumOrCb (onlyTick: false).
            var result: [AxisLabelInfoDetermined] = []
            helper.ordinalScaleCreateTicks(ordinalScale, numericLabelInterval) { tick, isExtentBoundary in
                var tickObj = tick
                let tickLabel = ordinalScale.getLabel(tickObj)
                if let categoryIntervalCb = categoryIntervalCb {
                    // When interval is function, a falsy return means ignore the tick.
                    let isOnInterval = categoryIntervalCb(tickObj.value, tickLabel)
                    tickObj.offInterval = !isOnInterval
                    // axis extent min max labels should be always included.
                    if !isOnInterval && !isExtentBoundary {
                        return
                    }
                }
                result.append(AxisLabelInfoDetermined(
                    formattedLabel: labelFormatter(tickObj, nil),
                    rawLabel: tickLabel,
                    tick: tickObj
                ))
            }
            return result
        }

        // makeRealNumberLabels: one label per (customized `getTicksOverride`) tick.
        let ticks = self.scale.getTicks()
        var result: [AxisLabelInfoDetermined] = []
        for (idx, tick) in ticks.enumerated() {
            result.append(AxisLabelInfoDetermined(
                formattedLabel: labelFormatter(tick, Double(idx)),
                rawLabel: self.scale.getLabel(tick),
                tick: tick
            ))
        }
        return result
    }

    /**
     * @override
     */
    // isHorizontal() { return this.model.get('orient') === 'horizontal'; }
    //   (base `Axis` has no `isHorizontal`; this is a component-local method — not used by the
    //   static render path, kept for fidelity.)
    public func isHorizontal() -> Bool {
        return (self.timelineModel.get("orient") as? String) == "horizontal"
    }
}

// export default TimelineAxis;  -> `public final class TimelineAxis` above.
