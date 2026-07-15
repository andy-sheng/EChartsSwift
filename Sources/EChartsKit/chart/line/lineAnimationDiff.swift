// Ported from echarts/src/chart/line/lineAnimationDiff.ts — keep in sync with upstream
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
// import {prepareDataCoordInfo, getStackedOnPoint} from './helper';   -> chart/line/helper.swift
// import SeriesData from '../../data/SeriesData';                     -> data/SeriesData.swift
// import type Cartesian2D from '../../coord/cartesian/Cartesian2D';   -> `LineCoordSys` (helper.swift)
// import type Polar from '../../coord/polar/Polar';                   -> `LineCoordSys` (helper.swift)
// import { LineSeriesOption } from './LineSeries';                    -> chart/line/LineSeries.swift
// import { createFloat32Array } from '../../util/vendor';             -> `vendor.createFloat32Array`

// upstream: interface DiffItem { cmd: '+' | '=' | '-'; idx: number; idx1?: number }
public struct LineDiffItem {
    public var cmd: String
    public var idx: Int
    public var idx1: Int?
}

// upstream: function diffData(oldData: SeriesData, newData: SeriesData)
private func diffData(_ oldData: SeriesData?, _ newData: SeriesData) -> [LineDiffItem] {
    var diffResult: [LineDiffItem] = []

    newData.diff(oldData)
        .add({ idx in
            diffResult.append(LineDiffItem(cmd: "+", idx: Int(idx), idx1: nil))
        })
        .update({ newIdx, oldIdx in
            diffResult.append(LineDiffItem(cmd: "=", idx: Int(oldIdx), idx1: Int(newIdx)))
        })
        .remove({ idx in
            diffResult.append(LineDiffItem(cmd: "-", idx: Int(idx), idx1: nil))
        })
        .execute()

    return diffResult
}

// upstream: interface (anonymous) return of `lineAnimationDiff`
public struct LineAnimationDiffResult {
    public var current: [Double]
    public var next: [Double]

    public var stackedOnCurrent: [Double]
    public var stackedOnNext: [Double]

    public var status: [LineDiffItem]
}

// upstream: export default function lineAnimationDiff(...)
public func lineAnimationDiff(
    _ oldData: SeriesData?, _ newData: SeriesData,
    _ oldStackedOnPoints: [Double], _ newStackedOnPoints: [Double],
    _ oldCoordSys: LineCoordSys, _ newCoordSys: LineCoordSys,
    _ oldValueOrigin: Any?,
    _ newValueOrigin: Any?
) -> LineAnimationDiffResult {
    let diff = diffData(oldData, newData)

    // let newIdList = newData.mapArray(newData.getId);
    // let oldIdList = oldData.mapArray(oldData.getId);

    // convertToIntId(newIdList, oldIdList);

    // // FIXME One data ?
    // diff = arrayDiff(oldIdList, newIdList);

    var currPoints: [Double] = []
    var nextPoints: [Double] = []
    // Points for stacking base line
    var currStackedPoints: [Double] = []
    var nextStackedPoints: [Double] = []

    var status: [LineDiffItem] = []
    var sortedIndices: [Int] = []
    var rawIndices: [Int] = []

    let newDataOldCoordInfo = prepareDataCoordInfo(oldCoordSys, newData, oldValueOrigin)
    // const oldDataNewCoordInfo = prepareDataCoordInfo(newCoordSys, oldData, newValueOrigin);

    let oldPoints = (oldData?.getLayout("points") as? [Double]) ?? []
    let newPoints = (newData.getLayout("points") as? [Double]) ?? []

    // PORT-LOCAL: upstream indexes `Float32Array`s past their end and gets `undefined` -> NaN.
    //   Swift traps on an out-of-range subscript, so read through this (see poly.swift's `polyAt`).
    func at(_ arr: [Double], _ i: Int) -> Double {
        return (i >= 0 && i < arr.count) ? arr[i] : Double.nan
    }

    for i in 0..<diff.count {
        let diffItem = diff[i]
        var pointAdded = true

        var oldIdx2: Int
        var newIdx2: Int

        // FIXME, animation is not so perfect when dataZoom window moves fast
        // Which is in case remvoing or add more than one data in the tail or head
        switch diffItem.cmd {
        case "=":
            oldIdx2 = diffItem.idx * 2
            newIdx2 = (diffItem.idx1 ?? 0) * 2
            var currentX = at(oldPoints, oldIdx2)
            var currentY = at(oldPoints, oldIdx2 + 1)
            let nextX = at(newPoints, newIdx2)
            let nextY = at(newPoints, newIdx2 + 1)

            // If previous data is NaN, use next point directly
            if currentX.isNaN || currentY.isNaN {
                currentX = nextX
                currentY = nextY
            }
            currPoints.append(currentX); currPoints.append(currentY)
            nextPoints.append(nextX); nextPoints.append(nextY)

            currStackedPoints.append(at(oldStackedOnPoints, oldIdx2))
            currStackedPoints.append(at(oldStackedOnPoints, oldIdx2 + 1))
            nextStackedPoints.append(at(newStackedOnPoints, newIdx2))
            nextStackedPoints.append(at(newStackedOnPoints, newIdx2 + 1))

            rawIndices.append(newData.getRawIndex(diffItem.idx1 ?? 0))

        case "+":
            let newIdx = diffItem.idx
            let newDataDimsForPoint = newDataOldCoordInfo.dataDimsForPoint
            let oldPt = oldCoordSys.dataToPoint([
                newDataDimsForPoint.count > 0 && newDataDimsForPoint[0] != nil
                    ? (newData.get(newDataDimsForPoint[0]!, newIdx) as Any) : Double.nan,
                newDataDimsForPoint.count > 1 && newDataDimsForPoint[1] != nil
                    ? (newData.get(newDataDimsForPoint[1]!, newIdx) as Any) : Double.nan
            ])
            newIdx2 = newIdx * 2
            currPoints.append(at(oldPt, 0)); currPoints.append(at(oldPt, 1))

            nextPoints.append(at(newPoints, newIdx2)); nextPoints.append(at(newPoints, newIdx2 + 1))

            let stackedOnPoint = getStackedOnPoint(newDataOldCoordInfo, oldCoordSys, newData, newIdx)

            currStackedPoints.append(at(stackedOnPoint, 0))
            currStackedPoints.append(at(stackedOnPoint, 1))
            nextStackedPoints.append(at(newStackedOnPoints, newIdx2))
            nextStackedPoints.append(at(newStackedOnPoints, newIdx2 + 1))

            rawIndices.append(newData.getRawIndex(newIdx))

        case "-":
            pointAdded = false

        default:
            break
        }

        // Original indices
        if pointAdded {
            status.append(diffItem)
            sortedIndices.append(sortedIndices.count)
        }
    }

    // Diff result may be crossed if all items are changed
    // Sort by data index
    sortedIndices.sort { a, b in
        return rawIndices[a] < rawIndices[b]
    }

    let len = currPoints.count
    var sortedCurrPoints = vendor.createFloat32Array(Double(len))
    var sortedNextPoints = vendor.createFloat32Array(Double(len))

    var sortedCurrStackedPoints = vendor.createFloat32Array(Double(len))
    var sortedNextStackedPoints = vendor.createFloat32Array(Double(len))

    var sortedStatus: [LineDiffItem] = []
    for i in 0..<sortedIndices.count {
        let idx = sortedIndices[i]
        let i2 = i * 2
        let idx2 = idx * 2
        sortedCurrPoints[i2] = currPoints[idx2]
        sortedCurrPoints[i2 + 1] = currPoints[idx2 + 1]
        sortedNextPoints[i2] = nextPoints[idx2]
        sortedNextPoints[i2 + 1] = nextPoints[idx2 + 1]

        sortedCurrStackedPoints[i2] = at(currStackedPoints, idx2)
        sortedCurrStackedPoints[i2 + 1] = at(currStackedPoints, idx2 + 1)
        sortedNextStackedPoints[i2] = at(nextStackedPoints, idx2)
        sortedNextStackedPoints[i2 + 1] = at(nextStackedPoints, idx2 + 1)

        sortedStatus.append(status[idx])
    }

    return LineAnimationDiffResult(
        current: sortedCurrPoints,
        next: sortedNextPoints,

        stackedOnCurrent: sortedCurrStackedPoints,
        stackedOnNext: sortedNextStackedPoints,

        status: sortedStatus
    )
}
