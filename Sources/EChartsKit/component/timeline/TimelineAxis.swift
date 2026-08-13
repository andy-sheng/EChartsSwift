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

    // PORT-DEVIATION: upstream inherits `Axis.getViewLabels`, but the Swift base `Axis.model` cannot hold
    // a TimelineModel. Mirror the category-label builder here while retaining the shared auto-interval
    // calculation. That calculation is orientation-aware, which is essential for vertical timelines:
    // label HEIGHT, not its much larger text width, determines whether adjacent steps overlap.
    public override func getViewLabels(_ ctx: AxisLabelsComputingContext? = nil) -> [AxisLabelInfoDetermined] {
        let labelFormatter = axisHelper.makeLabelFormatter(self)

        // upstream `createAxisLabels`: "Only ordinal scale support tick interval" — the CATEGORY branch
        //   honors `label.interval`; value/time fall through to `makeRealNumberLabels` (all ticks).
        if self.type == "category", let ordinalScale = self.scale as? OrdinalScale {
            // makeCategoryLabelsActually: optionLabelInterval = getOptionCategoryInterval(labelModel).
            let optionLabelInterval = axisHelper.getOptionCategoryInterval(self.getLabelModel())
            let categoryIntervalCb = optionLabelInterval as? CategoryTickLabelSplitIntervalCb
            let numericLabelInterval: Double
            if categoryIntervalCb != nil {
                numericLabelInterval = 0
            }
            else if (optionLabelInterval as? String) == "auto" {
                // TimelineAxis has no AxisBaseModel in the inherited `model` slot, so use the
                // no-cache estimate path. The geometry calculation is identical; only the generic
                // AxisBaseModel interval-stability cache is bypassed.
                numericLabelInterval = self.calculateCategoryInterval(
                    createAxisLabelsComputingContext(AxisTickLabelComputingKind.estimate)
                )
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
