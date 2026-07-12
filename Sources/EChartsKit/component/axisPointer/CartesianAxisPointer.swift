// Ported from echarts/src/component/axisPointer/CartesianAxisPointer.ts — keep in sync with upstream
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

// import BaseAxisPointer, { AxisPointerElementOptions } from './BaseAxisPointer'; -> sibling BaseAxisPointer.swift
// import * as viewHelper from './viewHelper';                      -> viewHelper.* (sibling)
// import * as cartesianAxisHelper from '../../coord/cartesian/cartesianAxisHelper'; -> cartesianAxisHelper.*
// import CartesianAxisModel from '../../coord/cartesian/AxisModel'; -> CartesianAxisModel
// import ExtensionAPI from '../../core/ExtensionAPI';              -> ExtensionAPI
// import Grid from '../../coord/cartesian/Grid';                   -> Grid (coord/cartesian/Grid.swift)
// import Axis2D from '../../coord/cartesian/Axis2D';               -> Axis2D
// import { mathMax, mathMin } from '../../util/number';            -> number.mathMax / number.mathMin
// import type GlobalModel from '../../model/Global';               -> GlobalModel
//
// type AxisPointerModel = Model<CommonAxisPointerOption>  -> `Model` (non-generic in the port).

// upstream: interface Transform { x, y, rotation } (from BaseAxisPointer) — the handle transform.
public struct AxisPointerHandleTransform {
    public var x: Double
    public var y: Double
    public var rotation: Double
    public init(x: Double, y: Double, rotation: Double) {
        self.x = x; self.y = y; self.rotation = rotation
    }
}

// upstream: Transform & { cursorPoint: number[]; tooltipOption?: { verticalAlign?, align? } }
public struct AxisPointerUpdatedHandleTransform {
    public var x: Double
    public var y: Double
    public var rotation: Double
    public var cursorPoint: [Double]
    public var tooltipOption: [String: Any]?
    public init(x: Double, y: Double, rotation: Double, cursorPoint: [Double], tooltipOption: [String: Any]?) {
        self.x = x; self.y = y; self.rotation = rotation
        self.cursorPoint = cursorPoint; self.tooltipOption = tooltipOption
    }
}

// class CartesianAxisPointer extends BaseAxisPointer
public final class CartesianAxisPointer: BaseAxisPointer {

    /**
     * @override
     */
    // OVERRIDE-SIGNATURE: must match BaseAxisPointer.makeElOption exactly (axisModel: AxisBaseModel,
    //   value: Any?). Narrow to the concrete CartesianAxisModel INSIDE (protocol-witness/narrowing trap).
    public override func makeElOption(
        _ elOption: inout AxisPointerElementOptions,
        _ value: Any?,
        _ axisModel: AxisBaseModel,
        _ axisPointerModel: Model,
        _ api: ExtensionAPI
    ) {
        guard let axisModel = axisModel as? CartesianAxisModel else { return }

        // CAUTION (protocol-witness trap): `axisModel.axis` is typed `Any`; narrow to the concrete
        //   `Axis2D` so `getGlobalExtent` / `grid` / `toGlobalCoord` / `dataToCoord` resolve to the real
        //   Axis2D members (not a nil-returning protocol default).
        let axis = axisModel.axis as! Axis2D
        let grid = axis.grid!
        let axisPointerType = axisPointerModel.get("type") as? String
        let thisExtent = axis.getGlobalExtent()
        let otherExtent = getCartesian(grid, axis)!.getOtherAxis(axis).getGlobalExtent()
        let pixelValue = axis.toGlobalCoord(axis.dataToCoord(value ?? NSNull(), true))

        if let axisPointerType = axisPointerType, axisPointerType != "none" {
            let elStyle = viewHelper.buildElStyle(axisPointerModel)
            var pointerOption: PointerElementOption?
            if axisPointerType == "line" {
                pointerOption = pointerShapeBuilderLine(axis, pixelValue, thisExtent, otherExtent)
            }
            else if axisPointerType == "shadow" {
                pointerOption = pointerShapeBuilderShadow(
                    axis, pixelValue, thisExtent, otherExtent,
                    axisPointerModel.get("seriesDataIndices") as? [AxisTriggerDataIndex],
                    axisPointerModel.ecModel!
                )
            }
            if var pointerOption = pointerOption {
                pointerOption.style = elStyle
                elOption.graphicKey = pointerOption.type
                elOption.pointer = pointerOption
            }
        }

        let layoutInfo = AxisTransformedPositionLayoutInfo(
            cartesianAxisHelper.layout(grid.getRect(), axisModel)
        )
        viewHelper.buildCartesianSingleLabelElOption(
            value, &elOption, layoutInfo, axisModel, axisPointerModel, api
        )
    }

    /**
     * @override
     */
    // Handle drag geometry (the draggable axisPointer handle). BaseAxisPointer's handle surface is a
    //   PORT-NOTE (deferred: handle/drag surface out of scope for the headless crosshair — see
    //   BaseAxisPointer._renderHandle note), so these are plain methods (not `override`s) — pure geometry
    //   kept faithful.
    public func getHandleTransform(
        _ value: Any?,
        _ axisModel: CartesianAxisModel,
        _ axisPointerModel: Model
    ) -> AxisPointerHandleTransform {
        let axis = axisModel.axis as! Axis2D
        var layoutInfo = AxisTransformedPositionLayoutInfo(
            cartesianAxisHelper.layout(
                axis.grid.getRect(), axisModel, cartesianAxisHelper.LayoutOpt(labelInside: false)
            )
        )
        layoutInfo.labelMargin = axisPointerModel.get(["handle", "margin"]) as? Double
        let pos = viewHelper.getTransformedPosition(axis, value, layoutInfo)
        return AxisPointerHandleTransform(
            x: pos[0],
            y: pos[1],
            rotation: layoutInfo.rotation + ((layoutInfo.labelDirection ?? 1) < 0 ? Double.pi : 0)
        )
    }

    /**
     * @override
     */
    public func updateHandleTransform(
        _ transform: AxisPointerHandleTransform,
        _ delta: [Double],
        _ axisModel: CartesianAxisModel,
        _ axisPointerModel: Model
    ) -> AxisPointerUpdatedHandleTransform {
        let axis = axisModel.axis as! Axis2D
        let grid = axis.grid!
        let axisExtent = axis.getGlobalExtent(true)
        let otherExtent = getCartesian(grid, axis)!.getOtherAxis(axis).getGlobalExtent()
        let dimIndex = axis.dim == "x" ? 0 : 1

        var currPosition = [transform.x, transform.y]
        currPosition[dimIndex] += delta[dimIndex]
        currPosition[dimIndex] = number.mathMin(axisExtent[1], currPosition[dimIndex])
        currPosition[dimIndex] = number.mathMax(axisExtent[0], currPosition[dimIndex])

        let cursorOtherValue = (otherExtent[1] + otherExtent[0]) / 2
        var cursorPoint = [cursorOtherValue, cursorOtherValue]
        cursorPoint[dimIndex] = currPosition[dimIndex]

        // Make tooltip do not overlap axisPointer and in the middle of the grid.
        let tooltipOptions: [[String: Any]] = [
            ["verticalAlign": "middle"],
            ["align": "center"]
        ]

        return AxisPointerUpdatedHandleTransform(
            x: currPosition[0],
            y: currPosition[1],
            rotation: transform.rotation,
            cursorPoint: cursorPoint,
            tooltipOption: tooltipOptions[dimIndex]
        )
    }
}

// upstream: getCartesian(grid, axis) — resolve the Cartesian2D owning `axis`.
private func getCartesian(_ grid: Grid, _ axis: Axis2D) -> Cartesian2D? {
    // opt[axis.dim + 'AxisIndex'] = axis.index;
    if axis.dim == "x" {
        return grid.getCartesian(axis.index, nil)
    }
    else {
        return grid.getCartesian(nil, axis.index)
    }
}

// upstream: pointerShapeBuilder.line
private func pointerShapeBuilderLine(
    _ axis: Axis2D,
    _ pixelValue: Double,
    _ thisExtent: [Double],
    _ otherExtent: [Double]
) -> PointerElementOption {
    let targetShape = viewHelper.makeLineShape(
        [pixelValue, otherExtent[0]],
        [pixelValue, otherExtent[1]],
        getAxisDimIndex(axis)
    )
    return PointerElementOption(
        type: "Line",
        shape: targetShape,
        subPixelOptimize: true
    )
}

// upstream: pointerShapeBuilder.shadow
private func pointerShapeBuilderShadow(
    _ axis: Axis2D,
    _ pixelValue: Double,
    _ thisExtent: [Double],
    _ otherExtent: [Double],
    _ seriesDataIndices: [AxisTriggerDataIndex]?,
    _ ecModel: GlobalModel
) -> PointerElementOption {
    let bandWidth = viewHelper.calcAxisPointerShadowBandWidth(axis, seriesDataIndices, ecModel)
    let otherSpan = otherExtent[1] - otherExtent[0]
    let ends = viewHelper.calcAxisPointerShadowEnds(pixelValue, thisExtent, bandWidth)
    let min = ends[0]
    let max = ends[1]
    return PointerElementOption(
        type: "Rect",
        shape: viewHelper.makeRectShape(
            [min, otherExtent[0]],
            [max - min, otherSpan],
            getAxisDimIndex(axis)
        )
    )
}

private func getAxisDimIndex(_ axis: Axis2D) -> Int {
    return axis.dim == "x" ? 0 : 1
}
