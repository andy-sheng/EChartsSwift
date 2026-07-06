// Ported from echarts/src/processor/dataStack.ts — keep in sync with upstream
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

// type StackInfo = Pick<DataCalculationInfo<...>, 'stackedDimension' | 'isStackedByIndex'
//     | 'stackedByDimension' | 'stackResultDimension' | 'stackedOverDimension'>
//     & { data: SeriesData; seriesModel: SeriesModel };
private struct StackInfo {
    var stackResultDimension: String?
    var stackedOverDimension: String?
    var stackedDimension: String?
    var stackedByDimension: String?
    var isStackedByIndex: Bool
    var data: SeriesData
    var seriesModel: SeriesModel
}

// JS numeric coercion of a store value (ParsedValue = Any). nil/non-numeric → NaN.
private func stackNum(_ v: Any?) -> Double {
    guard let v = v else { return .nan }
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    if let s = v as? String { return Double(s) ?? .nan }
    return .nan
}

// export const dataStackStageHandler = createSimpleOverallStageHandler2(dataStack);
// (1) [Caution]: the logic is correct based on the premises: data processing stage is blocked in stream.
// (2) Only register once when import repeatedly. Should be executed after series is filtered and before
//     stack calculation.
public func dataStack(_ ecModel: GlobalModel) {
    var stackInfoMap: [String: [StackInfo]] = [:]
    var stackOrderKeys: [String] = []   // preserve first-seen (series) order — HashMap iteration order

    ecModel.eachSeries({ (seriesModel, _) in
        let stack = seriesModel.get("stack", false)
        // Compatible: when `stack` is set as '', do not stack.
        guard stackTruthy(stack) else { return }
        let stackKey = "\(stackUnwrap(stack))"

        let data = seriesModel.getData()

        let stackInfo = StackInfo(
            // Used for calculate axis extent automatically.
            stackResultDimension: data.getCalculationInfo("stackResultDimension") as? String,
            stackedOverDimension: data.getCalculationInfo("stackedOverDimension") as? String,
            stackedDimension: data.getCalculationInfo("stackedDimension") as? String,
            stackedByDimension: data.getCalculationInfo("stackedByDimension") as? String,
            isStackedByIndex: (data.getCalculationInfo("isStackedByIndex") as? Bool) ?? false,
            data: data,
            seriesModel: seriesModel
        )

        // If stacked on axis that do not support data stack.
        if stackInfo.stackedDimension == nil
            || !(stackInfo.isStackedByIndex || stackInfo.stackedByDimension != nil) {
            return
        }

        if stackInfoMap[stackKey] == nil {
            stackInfoMap[stackKey] = []
            stackOrderKeys.append(stackKey)
        }
        stackInfoMap[stackKey]!.append(stackInfo)
    })

    // Process each stack group
    for key in stackOrderKeys {
        var stackInfoList = stackInfoMap[key]!
        if stackInfoList.isEmpty { continue }

        // Check if stack order needs to be reversed
        let firstSeries = stackInfoList[0].seriesModel
        let stackOrder = (firstSeries.get("stackOrder", false) as? String) ?? "seriesAsc"

        if stackOrder == "seriesDesc" {
            stackInfoList.reverse()
        }

        // Set stackedOnSeries for each series in the final order
        for (index, stackInfo) in stackInfoList.enumerated() {
            stackInfo.data.setCalculationInfo(
                "stackedOnSeries",
                index > 0 ? stackInfoList[index - 1].seriesModel : nil
            )
        }

        // Calculate stack values
        calculateStack(stackInfoList)
    }
}

private func calculateStack(_ stackInfoList: [StackInfo]) {
    for (idxInStack, targetStackInfo) in stackInfoList.enumerated() {
        let resultNaN: [ParsedValue] = [Double.nan, Double.nan]
        let dims: [String] = [
            targetStackInfo.stackResultDimension ?? "",
            targetStackInfo.stackedOverDimension ?? ""
        ]
        let targetData = targetStackInfo.data
        let isStackedByIndex = targetStackInfo.isStackedByIndex
        let stackStrategy = (targetStackInfo.seriesModel.get("stackStrategy", false) as? String) ?? "samesign"
        let stackedDim = targetStackInfo.stackedDimension ?? ""
        let stackedByDim = targetStackInfo.stackedByDimension ?? ""

        // Should not write on raw data, because stack series model list changes depending on legend
        // selection. `modify` passes [v0, v1, dataIndex] — dataIndex is the trailing element.
        targetData.modify(dims) { (args: [ParsedValue]) -> ParsedValue? in
            let dataIndex = Int(stackNum(args.last))
            var sum = stackNum(targetData.get(stackedDim, dataIndex))

            // Consider `connectNulls` of line area, if value is NaN, stackedOver should also be NaN,
            // to draw a appropriate belt area.
            if sum.isNaN { return resultNaN }

            var byValue = Double.nan
            var stackedDataRawIndex = -1

            if isStackedByIndex {
                stackedDataRawIndex = targetData.getRawIndex(dataIndex)
            }
            else {
                byValue = stackNum(targetData.get(stackedByDim, dataIndex))
            }

            // If stackOver is NaN, chart view will render point on value start.
            var stackedOver = Double.nan

            var j = idxInStack - 1
            while j >= 0 {
                let stackInfo = stackInfoList[j]

                // Has been optimized by inverted indices on `stackedByDimension`.
                if !isStackedByIndex {
                    stackedDataRawIndex = stackInfo.data.rawIndexOf(stackInfo.stackedByDimension ?? "", byValue)
                }

                if stackedDataRawIndex >= 0 {
                    let val = stackNum(stackInfo.data.getByRawIndex(stackInfo.stackResultDimension ?? "", stackedDataRawIndex))

                    // Considering positive stack, negative stack and empty data
                    if stackStrategy == "all" // single stack group
                        || (stackStrategy == "positive" && val > 0)
                        || (stackStrategy == "negative" && val < 0)
                        || (stackStrategy == "samesign" && sum >= 0 && val > 0) // All positive stack
                        || (stackStrategy == "samesign" && sum <= 0 && val < 0) // All negative stack
                    {
                        // The sum has to be very small to be affected by the floating arithmetic problem.
                        sum = number.addSafe(sum, val)
                        stackedOver = val
                        break
                    }
                }
                j -= 1
            }

            return [sum, stackedOver] as [ParsedValue]
        }
    }
}

// JS truthiness for `seriesModel.get('stack')` (mirrors dataStackHelper's private shim).
private func stackTruthy(_ v: Any?) -> Bool {
    guard let v = stackUnwrapOpt(v) else { return false }
    if let b = v as? Bool { return b }
    if let d = v as? Double { return d != 0 && !d.isNaN }
    if let i = v as? Int { return i != 0 }
    if let s = v as? String { return !s.isEmpty }
    return true
}

// Recursively unwrap a boxed Optional (`Any` wrapping `String?`), returning nil for `.none`.
private func stackUnwrapOpt(_ v: Any?) -> Any? {
    guard let v = v else { return nil }
    let m = Mirror(reflecting: v)
    if m.displayStyle == .optional {
        guard let child = m.children.first else { return nil }
        return stackUnwrapOpt(child.value)
    }
    return v
}

private func stackUnwrap(_ v: Any?) -> Any {
    return stackUnwrapOpt(v) ?? ""
}
