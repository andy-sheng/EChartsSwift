// Ported from echarts/src/component/tooltip/seriesFormatTooltip.ts — keep in sync with upstream
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
//   import SeriesModel from '../../model/Series';    -> `SeriesModel` (model/Series.swift).
//   import { trim, isArray, each, reduce } from 'zrender/src/core/util';
//     -> native Swift (String.trimmingCharacters / `is [Any]` / for-loops / reduce).
//   import { DimensionName, DimensionType, ColorString } from '../../util/types';
//     -> EChartsKit util/types.swift (same module).
//   import { retrieveVisualColorForTooltipMarker, TooltipMarkupBlockFragment, createTooltipMarkup,
//            TooltipMarkupSection } from './tooltipMarkup';  -> tooltipMarkup.swift (same module).
//   import { retrieveRawValue } from '../../data/helper/dataProvider';  -> `retrieveRawValue`.
//   import { isNameSpecified } from '../../util/model';   -> `model.isNameSpecified` (util/modelUtil.swift).

// upstream:
//   export function defaultSeriesFormatTooltip(opt: {
//       series: SeriesModel; dataIndex: number; multipleSeries: boolean;
//   }): TooltipMarkupSection
// The inline `opt` object is flattened to labelled parameters (CONVENTIONS §4).
// `multipleSeries` means multiple series displayed in one tooltip, and this method only returns the
// part of one series.
public func defaultSeriesFormatTooltip(
    series: SeriesModel,
    dataIndex: Double,
    multipleSeries: Bool
) -> TooltipMarkupSection {
    let data = series.getData()
    let tooltipDims = data.mapDimensionsAll("defaultedTooltip")
    let tooltipDimLen = tooltipDims.count
    let value = series.getRawValue(dataIndex)
    let isValueArr = util.isArray(value)
    let markerColor = retrieveVisualColorForTooltipMarker(series, Int(dataIndex))

    // Complicated rule for pretty tooltip.
    var inlineValue: Any?
    var inlineValueType: Any?   // DimensionType | DimensionType[]
    var subBlocks: [TooltipMarkupBlockFragment]?
    var sortParam: Any?
    if tooltipDimLen > 1 || (isValueArr && tooltipDimLen == 0) {
        let formatArrResult = formatTooltipArrayValue(value as? [Any] ?? [], series, dataIndex, tooltipDims, markerColor)
        inlineValue = formatArrResult.inlineValues
        inlineValueType = formatArrResult.inlineValueTypes
        subBlocks = formatArrResult.blocks
        // Only support tooltip sort by the first inline value. It's enough in most cases.
        sortParam = formatArrResult.inlineValues.first ?? nil
    }
    else if tooltipDimLen != 0 {
        let dimInfo = data.getDimensionInfo(tooltipDims[0])
        inlineValue = retrieveRawValue(data, dataIndex, tooltipDims[0])
        sortParam = inlineValue
        inlineValueType = dimInfo.type
    }
    else {
        inlineValue = isValueArr ? (value as! [Any])[0] : value
        sortParam = inlineValue
    }

    // Do not show generated series name. It might not be readable.
    let seriesNameSpecified = model.isNameSpecified(series)
    // `seriesNameSpecified && series.name || ''` — JS truthiness (empty name is falsy).
    let seriesName = (seriesNameSpecified && !series.name.isEmpty) ? series.name : ""
    let itemName = data.getName(Int(dataIndex))
    let inlineName = multipleSeries ? seriesName : itemName

    let inlineBlock: TooltipMarkupBlockFragment = createTooltipMarkup("nameValue", TooltipMarkupNameValueBlock(
        markerType: .item,
        markerColor: markerColor,
        // Do not mix display seriesName and itemName in one tooltip,
        // which might confuses users.
        name: inlineName,
        value: inlineValue,
        // name dimension might be auto assigned, where the name might
        // be not readable. So we check trim here.
        valueType: inlineValueType,
        noName: inlineName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
        rawDataIndex: data.getRawIndex(Int(dataIndex))
    ))

    return createTooltipMarkup("section", TooltipMarkupSection(
        header: seriesName,
        // When series name is not specified, do not show a header line with only '-'.
        // This case always happens in tooltip.trigger: 'item'.
        noHeader: multipleSeries || !seriesNameSpecified,
        blocks: [inlineBlock] + (subBlocks ?? []),
        sortParam: sortParam
    ))
}

private func formatTooltipArrayValue(
    _ value: [Any],
    _ series: SeriesModel,
    _ dataIndex: Double,
    _ tooltipDims: [DimensionName],
    _ colorStr: ColorString
) -> (inlineValues: [Any?], inlineValueTypes: [Any?], blocks: [TooltipMarkupBlockFragment]) {
    // check: category-no-encode-has-axis-data in dataset.html
    let data = series.getData()
    // `reduce(value, (isValueMultipleLine, val, idx) => ...)` -> Swift reduce over indices.
    // upstream guards `dimItem && ...`; `SeriesData.getDimensionInfo(idx)` force-unwraps and would
    //   SIGTRAP on an out-of-range index, so reproduce the nil-guard by bounding on the dim count
    //   (an idx past the last dimension yields `undefined` upstream → contributes false).
    var isValueMultipleLine = false
    for idx in 0..<value.count where idx < data.dimensions.count {
        let dimItem = data.getDimensionInfo(idx)
        // `dimItem.tooltip !== false && dimItem.displayName != null`
        isValueMultipleLine = isValueMultipleLine
            || ((dimItem.tooltip != false) && dimItem.displayName != nil)
    }

    var inlineValues: [Any?] = []
    var inlineValueTypes: [Any?] = []
    var blocks: [TooltipMarkupBlockFragment] = []

    // upstream: `if (!dimInfo || dimInfo.otherDims.tooltip === false) return;`
    //   `dimInfo.otherDims.tooltip === false` — the visual `tooltip` dim can be `DimensionIndex | false`.
    func setEachItem(_ val: Any?, _ dim: Any) {
        let dimInfo = data.getDimensionInfo(dim)
        // If `dimInfo.tooltip` is not set, show tooltip.
        if isFalse(dimInfo.otherDims?.tooltip) {
            return
        }
        if isValueMultipleLine {
            blocks.append(createTooltipMarkup("nameValue", TooltipMarkupNameValueBlock(
                markerType: .subItem,
                markerColor: colorStr,
                name: dimInfo.displayName,
                value: val,
                valueType: dimInfo.type
            )))
        }
        else {
            inlineValues.append(val)
            inlineValueTypes.append(dimInfo.type)
        }
    }

    // By default, all dims is used on tooltip.
    if tooltipDims.count != 0 {
        for dim in tooltipDims {
            setEachItem(retrieveRawValue(data, dataIndex, dim), dim)
        }
    }
    else {
        for (idx, val) in value.enumerated() {
            setEachItem(val, idx)
        }
    }

    return (inlineValues: inlineValues, inlineValueTypes: inlineValueTypes, blocks: blocks)
}

// upstream `x === false` on a value that can be `DimensionIndex | false | undefined`.
private func isFalse(_ v: Any?) -> Bool {
    if let b = v as? Bool { return b == false }
    return false
}
