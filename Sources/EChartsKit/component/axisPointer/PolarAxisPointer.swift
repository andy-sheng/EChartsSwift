// Ported from echarts/src/component/axisPointer/PolarAxisPointer.ts — keep in sync with upstream.

import Foundation
import ZRenderKit

/// The angle/radius axis pointer used by polar coordinate systems.
///
/// Geometry, label placement and animation thresholds intentionally mirror the upstream implementation.
public final class PolarAxisPointer: BaseAxisPointer {

    public override func makeElOption(
        _ elOption: inout AxisPointerElementOptions,
        _ value: Any?,
        _ axisModel: AxisBaseModel,
        _ axisPointerModel: Model,
        _ api: ExtensionAPI
    ) {
        guard let axisModel = axisModel as? PolarAxisModel,
              let axis = axisModel.axis as? Axis else { return }

        if axis.dim == "angle" {
            self.animationThreshold = Double.pi / 18
        }

        let polar: Polar
        if let angleAxis = axis as? AngleAxis {
            polar = angleAxis.polar
        }
        else if let radiusAxis = axis as? RadiusAxis {
            polar = radiusAxis.polar
        }
        else {
            return
        }

        let thisExtent = axis.getExtent()
        let otherExtent = polar.getOtherAxis(axis).getExtent()
        let coordValue = axis.dataToCoord(value ?? NSNull())

        if let axisPointerType = axisPointerModel.get("type") as? String,
           axisPointerType != "none" {
            var pointerOption: PointerElementOption?
            if axisPointerType == "line" {
                pointerOption = makePolarLinePointer(axis, polar, coordValue, otherExtent)
            }
            else if axisPointerType == "shadow",
                    let ecModel = axisPointerModel.ecModel {
                pointerOption = makePolarShadowPointer(
                    axis,
                    polar,
                    coordValue,
                    thisExtent,
                    otherExtent,
                    axisPointerModel.get("seriesDataIndices") as? [AxisTriggerDataIndex],
                    ecModel
                )
            }
            if var pointerOption {
                pointerOption.style = viewHelper.buildElStyle(axisPointerModel)
                elOption.graphicKey = pointerOption.type
                elOption.pointer = pointerOption
            }
        }

        let labelMargin = polarAxisPointerDouble(axisPointerModel.get(["label", "margin"])) ?? 0
        let labelPos = getPolarLabelPosition(value, axisModel, polar, labelMargin)
        viewHelper.buildLabelElOption(&elOption, axisModel, axisPointerModel, api, labelPos)
    }

    // Upstream PolarAxisPointer deliberately does not support a draggable handle.
}

private func getPolarLabelPosition(
    _ value: Any?,
    _ axisModel: PolarAxisModel,
    _ polar: Polar,
    _ labelMargin: Double
) -> viewHelper.LabelPos {
    let axis = axisModel.axis as! Axis
    let coord = axis.dataToCoord(value ?? NSNull())
    let axisAngle = polar.getAngleAxis().getExtent()[0] / 180 * Double.pi
    let radiusExtent = polar.getRadiusAxis().getExtent()

    if axis.dim == "radius" {
        var transform = matrix.create()
        transform = matrix.rotate(transform, axisAngle)
        transform = matrix.translate(transform, VectorArray(polar.cx, polar.cy))
        let point = vector.applyTransform(VectorArray(coord, -labelMargin), transform)

        let labelRotation = polarAxisPointerDouble(axisModel.get(["axisLabel", "rotate"])) ?? 0
        let layout = AxisBuilder.innerTextLayout(axisAngle, labelRotation * Double.pi / 180, -1)
        return viewHelper.LabelPos(
            align: layout.textAlign,
            verticalAlign: layout.textVerticalAlign,
            position: [point[0], point[1]]
        )
    }

    let radius = radiusExtent[1]
    let position = polar.coordToPoint([radius + labelMargin, coord])
    let horizontalRatio = radius == 0 ? 0 : abs(position[0] - polar.cx) / radius
    let verticalRatio = radius == 0 ? 0 : abs(position[1] - polar.cy) / radius
    let align: ZRTextAlign = horizontalRatio < 0.3
        ? .center
        : (position[0] > polar.cx ? .left : .right)
    let verticalAlign: ZRTextVerticalAlign = verticalRatio < 0.3
        ? .middle
        : (position[1] > polar.cy ? .top : .bottom)
    return viewHelper.LabelPos(align: align, verticalAlign: verticalAlign, position: position)
}

private func makePolarLinePointer(
    _ axis: Axis,
    _ polar: Polar,
    _ coordValue: Double,
    _ otherExtent: [Double]
) -> PointerElementOption {
    if axis.dim == "angle" {
        return PointerElementOption(
            type: "Line",
            shape: viewHelper.makeLineShape(
                polar.coordToPoint([otherExtent[0], coordValue]),
                polar.coordToPoint([otherExtent[1], coordValue])
            )
        )
    }

    var shape = CircleShape()
    shape.cx = polar.cx
    shape.cy = polar.cy
    shape.r = coordValue
    return PointerElementOption(type: "Circle", shape: shape)
}

private func makePolarShadowPointer(
    _ axis: Axis,
    _ polar: Polar,
    _ coordValue: Double,
    _ thisExtent: [Double],
    _ otherExtent: [Double],
    _ seriesDataIndices: [AxisTriggerDataIndex]?,
    _ ecModel: GlobalModel
) -> PointerElementOption {
    let radian = Double.pi / 180
    let bandWidth = viewHelper.calcAxisPointerShadowBandWidth(axis, seriesDataIndices, ecModel)
    let shape: SectorShape
    if axis.dim == "angle" {
        shape = viewHelper.makeSectorShape(
            polar.cx,
            polar.cy,
            otherExtent[0],
            otherExtent[1],
            (-coordValue - bandWidth / 2) * radian,
            (-coordValue + bandWidth / 2) * radian
        )
    }
    else {
        let ends = viewHelper.calcAxisPointerShadowEnds(coordValue, thisExtent, bandWidth)
        shape = viewHelper.makeSectorShape(
            polar.cx,
            polar.cy,
            ends[0],
            ends[1],
            0,
            Double.pi * 2
        )
    }
    return PointerElementOption(type: "Sector", shape: shape)
}

private func polarAxisPointerDouble(_ value: Any?) -> Double? {
    if let value = value as? Double { return value }
    if let value = value as? Int { return Double(value) }
    if let value = value as? NSNumber { return value.doubleValue }
    return nil
}
