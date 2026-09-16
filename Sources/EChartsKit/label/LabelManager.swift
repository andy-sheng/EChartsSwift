// Ported from echarts/src/label/LabelManager.ts + label/installLabelLayout.ts — keep in sync with upstream.
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

// PORT SCOPE (L2c — the global label layout stage):
//   This lands the per-frame label layout stage that upstream registers via `installLabelLayout`
//   (the `series:layoutlabels` lifecycle → `LabelManager.updateLayoutConfig` + `.layout`), reduced to
//   what the driver needs:
//     - `addLabelsOfSeries`: collect each series' label textContents when a `labelLayout` option is set.
//     - `updateLayoutConfig`: apply the user `labelLayout` option (x / y / rotate / align / verticalAlign
//        / width / height / fontSize / dx / dy) to each label.
//     - `layout`: resolve overlap globally — `moveOverlap` (shiftX/shiftY → `shiftLayoutOnXY`) and
//        `hideOverlap` (rotated-rect OBB overlap → `labelLayoutHelper.hideOverlap`).
//
//   PORTED (L1a follow-up): the label-layout CALLBACK form (`LabelLayoutOptionCallback`). Upstream
//     carries `LabelDesc.layoutOptionOrCb` (option OR function) and, in `updateLayoutConfig`, resolves
//     the function against `prepareLayoutCallbackParams(labelItem, hostEl)`. The port stores the closure
//     on the series option (`seriesModel.get("labelLayout") as? LabelLayoutOptionCallback`) — options
//     can carry a Swift closure as an `Any` — builds the params (dataIndex/dataType/seriesIndex/text/
//     rect/labelRect/align/verticalAlign/labelLinePoints), and applies the returned `LabelLayoutOption`.
//
//   DEFERRED (documented gaps, faithful to the rest of the port):
//     - `draggable` / drag handlers. Label-line creation/style/geometry and the global label/value/
//        guide-line animation pass are ported below in `processLabelsOverall`.
//     - The `dummyTransformable` global-space decomposition of `defaultAttr` — since the driver
//        renders each label fresh every frame, the label's CURRENT attrs ARE the defaults, so the
//        "restore default" branches of `updateLayoutConfig` reduce to no-ops and are omitted.

/// upstream: `class LabelManager` (LabelManager.ts).
public final class LabelManager {

    // upstream: `private _labelList`. Widened to `internal` (not `private`) so the `@testable` label
    //   layout-callback tests can seed `_labelList` directly — driving `updateLayoutConfig` end-to-end
    //   without standing up a full `SeriesModel` + data pipeline. No behavioural change.
    internal var _labelList: [LabelLayoutData] = []
    private var _chartViewList: [ChartView] = []

    public init() {}

    /// upstream: clearLabels()
    public func clearLabels() {
        self._labelList = []
        self._chartViewList = []
    }

    /// upstream: private _addLabel(dataIndex, dataType, seriesModel, label, layoutOptionOrCb)
    private func _addLabel(
        _ label: ZRText,
        _ layoutOption: LabelLayoutOption?,
        _ layoutCallback: LabelLayoutOptionCallback?,
        _ dataIndex: Double?,
        _ dataType: SeriesDataType?,
        _ seriesIndex: Double
    ) {
        let host = label.__hostTarget

        // Priority: use the host element's transformed bounding-rect area (upstream default). A label
        //   with a larger host wins the overlap contest.
        var priority = 0.0
        if let host = host, let hostRect = host.getBoundingRect() {
            let r = hostRect.clone()
            r.applyTransform(host.getComputedTransform())
            priority = r.width * r.height
        }

        let guide = host?.getTextGuideLine()

        let d = LabelLayoutData(
            label: label,
            labelLine: guide,
            layoutOption: layoutOption,
            layoutCallback: layoutCallback,
            dataIndex: dataIndex,
            dataType: dataType,
            seriesIndex: seriesIndex,
            priority: priority,
            defaultAttr: SavedLabelAttr(
                ignore: label.ignore,
                labelGuideIgnore: guide?.ignore ?? false
            )
        )
        self._labelList.append(d)
    }

    /// upstream: addLabelsOfSeries(chartView)
    /// Gate: only collect when the series specifies a non-empty `labelLayout` option (upstream checks
    /// `isFunction(layoutOption) || keys(layoutOption).length`). This keeps charts without a
    /// `labelLayout` option completely unaffected by the stage.
    public func addLabelsOfSeries(_ chartView: ChartView) {
        self._chartViewList.append(chartView)

        guard let seriesModel = chartView.__model else { return }
        let rawOption = seriesModel.get("labelLayout")
        // upstream gate: `isFunction(layoutOption) || keys(layoutOption).length` — the CALLBACK form
        //   (a Swift closure stored on the option, `LabelLayoutOptionCallback`) OR a non-empty option
        //   object. Callbacks are resolved per-label at `updateLayoutConfig` (they need each label's
        //   geometry), so here we only detect+carry them.
        let layoutCallback = rawOption as? LabelLayoutOptionCallback
        let layoutOption = LabelManager.parseLayoutOption(rawOption)
        guard layoutCallback != nil || layoutOption != nil else {
            // No option (or an empty option object) → skip.
            return
        }
        let seriesIndex = seriesModel.seriesIndex

        _ = chartView.group.traverse({ child -> Bool in
            if child.ignore && innerStore.getECElementProps(child).forceLabelAnimation != true {
                return true    // Stop traverse descendants.
            }
            // Only support label being hosted on graphic elements.
            if let textEl = child.getTextContent() {
                // Can only attach the text on the element with dataIndex — mirrors upstream (the ECData
                //   is read for dataIndex/dataType, which the callback-params builder needs).
                let ecData = innerStore.getECData(child)
                self._addLabel(textEl, layoutOption, layoutCallback, ecData.dataIndex, ecData.dataType, seriesIndex)
            }
            return false
        })
    }

    /// upstream: prepareLayoutCallbackParams(labelItem, hostEl) — builds the params passed to a
    /// `labelLayout` callback from the label's current (already-attached) geometry.
    private func prepareLayoutCallbackParams(_ labelItem: LabelLayoutData) -> LabelLayoutOptionCallbackParams {
        let label = labelItem.label
        let hostEl = label.__hostTarget
        let labelLine = hostEl?.getTextGuideLine()

        // labelRect: the label's own bounding rect in global space.
        let labelRect: RectLike = LabelManager.globalRect(label)
        // rect (host rect): the host element's bounding rect in global space (upstream `labelItem.hostRect`).
        let hostRect: RectLike = hostEl.map { LabelManager.globalRect($0) } ?? BoundingRect(0, 0, 0, 0)

        return LabelLayoutOptionCallbackParams(
            dataIndex: labelItem.dataIndex,
            dataType: labelItem.dataType,
            seriesIndex: labelItem.seriesIndex,
            text: label.textStyle?.text,
            align: label.textStyle?.align,
            verticalAlign: label.textStyle?.verticalAlign,
            rect: hostRect,
            labelRect: labelRect,
            labelLinePoints: LabelManager.cloneLinePoints(labelLine)
        )
    }

    /// upstream: `el.getBoundingRect().plain()` then `BoundingRect.applyTransform` by the computed
    ///   transform — the element's rect in global space.
    private static func globalRect(_ el: Element) -> RectLike {
        guard let r = el.getBoundingRect() else { return BoundingRect(0, 0, 0, 0) }
        let rect = r.clone()
        rect.applyTransform(el.getComputedTransform())
        return rect
    }

    /// upstream `cloneArr(labelLine && labelLine.shape.points)` — the guide line's points as `[[x, y]]`.
    private static func cloneLinePoints(_ labelLine: Polyline?) -> [[Double]]? {
        // `Path.shape` is the type-erased `any PathShape`; narrow to `PolylineShape` for `.points`.
        guard let shape = labelLine?.shape as? PolylineShape, let points = shape.points else { return nil }
        return points.map { [$0.x, $0.y] }
    }

    /// upstream: updateLayoutConfig(api) — applies the user `labelLayout` option to each label.
    /// only the override branches are applied (the "restore default" else-branches are
    /// no-ops on a fresh render, see the DEFERRED note). `draggable` / `labelLinePoints` deferred.
    public func updateLayoutConfig(_ width: Double, _ height: Double) {
        let degreeToRadian = Double.pi / 180
        for labelItem in self._labelList {
            // upstream: `isFunction(layoutOptionOrCb) ? layoutOptionOrCb(prepareLayoutCallbackParams(...))
            //   : layoutOptionOrCb`. Resolve the callback form to a concrete option here, and cache it
            //   back on the item so the later overlap `layout()` stage reads the resolved option too.
            if let cb = labelItem.layoutCallback {
                labelItem.layoutOption = cb(self.prepareLayoutCallbackParams(labelItem))
            }
            guard let layoutOption = labelItem.layoutOption else { continue }
            let label = labelItem.label
            let hostEl = label.__hostTarget

            // Host textConfig: force local:false; drop position config when x/y override it and rotation
            //   config when rotate overrides it (else keep the host's default); carry dx/dy as offset.
            //   upstream `hostEl.setTextConfig({...})` relies on zrender's field-MERGE
            //   (`extend(this.textConfig, cfg)`), preserving unrelated fields like `inside`. The port's
            //   `setTextConfig` is a wholesale REPLACE stub, so start `cfg` from a COPY of the existing
            //   textConfig to reproduce the merge (keeps `inside`, and keeps `position`/`rotation` when
            //   not overridden — which, on the driver's fresh-per-frame render, equal the saved
            //   `attachedPos`/`attachedRot` defaults upstream restores).
            if let hostEl = hostEl {
                var cfg = hostEl.textConfig ?? ElementTextConfig()
                cfg.local = false
                if layoutOption.x != nil || layoutOption.y != nil {
                    cfg.position = nil
                }
                if let rotate = layoutOption.rotate {
                    cfg.rotation = rotate * degreeToRadian
                }
                cfg.offset = [layoutOption.dx ?? 0, layoutOption.dy ?? 0]
                hostEl.setTextConfig(cfg)
            }

            if let x = layoutOption.x {
                label.x = number.parsePercent(x, width)
                _ = label.setStyle("x", 0)   // Ignore movement in style.
            }
            if let y = layoutOption.y {
                label.y = number.parsePercent(y, height)
                _ = label.setStyle("y", 0)
            }

            // upstream: if (layoutOption.labelLinePoints) { const guideLine = hostEl.getTextGuideLine();
            //   if (guideLine) { guideLine.setShape({ points: layoutOption.labelLinePoints }); ... } }
            //   Override the label guide line's geometry with the user-supplied points. The upstream
            //   `needsUpdateLabelLine = false` bookkeeping feeds `processLabelsOverall` (deferred), so
            //   only the observable `setShape` is applied here. `PolylineShape.animationSet` accepts the
            //   `[[Double]]` point form directly.
            if let linePoints = layoutOption.labelLinePoints, let guideLine = hostEl?.getTextGuideLine() {
                _ = guideLine.setShape("points", linePoints)
            }

            if let rotate = layoutOption.rotate {
                label.rotation = rotate * degreeToRadian
            }

            // LABEL_OPTION_TO_STYLE_KEYS = ['align', 'verticalAlign', 'width', 'height', 'fontSize'].
            // A ZRText keeps these fields in `textStyle`, not Displayable's common `style` bag.
            // Calling the inherited `setStyle(key:value:)` silently ignores text-only keys.
            if layoutOption.align != nil || layoutOption.verticalAlign != nil
                || layoutOption.width != nil || layoutOption.height != nil
                || layoutOption.fontSize != nil {
                var textStyle = label.textStyle ?? TextStyleProps()
                if let align = layoutOption.align { textStyle.align = align }
                if let verticalAlign = layoutOption.verticalAlign { textStyle.verticalAlign = verticalAlign }
                if let w = layoutOption.width { textStyle.width = w }
                if let h = layoutOption.height { textStyle.height = h }
                if let fs = layoutOption.fontSize { textStyle.fontSize = .number(fs) }
                label.useStyle(textStyle)
            }
        }
    }

    /// upstream: layout(api) — global overlap resolution.
    public func layout(_ width: Double, _ height: Double) {
        var labelList: [LabelLayoutData] = []
        for inputItem in self._labelList {
            if !inputItem.defaultAttr.ignore {
                // upstream `newLabelLayoutWithGeometry({}, inputItem)` — here the collected item IS the
                //   base+geometry union; just ensure its geometry is computed.
                labelLayoutHelper.ensureLabelLayoutWithGeometry(inputItem)
                labelList.append(inputItem)
            }
        }

        let labelsNeedsAdjustOnX = labelList.filter { $0.layoutOption?.moveOverlap == "shiftX" }
        let labelsNeedsAdjustOnY = labelList.filter { $0.layoutOption?.moveOverlap == "shiftY" }

        labelLayoutHelper.shiftLayoutOnXY(labelsNeedsAdjustOnX, 0, 0, width)
        labelLayoutHelper.shiftLayoutOnXY(labelsNeedsAdjustOnY, 1, 0, height)

        let labelsNeedsHideOverlap = labelList.filter { $0.layoutOption?.hideOverlap == true }

        labelLayoutHelper.restoreIgnore(labelsNeedsHideOverlap)
        labelLayoutHelper.hideOverlap(labelsNeedsHideOverlap)
    }

    /// upstream: registerUpdateLifecycle('series:layoutlabels', ...) in `installLabelLayout`.
    /// The driver calls this ONCE per render, AFTER `renderSeries` (so every series has attached
    /// its label textContents). No-op unless some series set a `labelLayout` option.
    public static func runLabelLayoutStage(_ chartViews: [ChartView], _ api: ExtensionAPI) {
        let manager = LabelManager()
        manager.clearLabels()
        for chartView in chartViews {
            manager.addLabelsOfSeries(chartView)
        }
        let width = api.getWidth()
        let height = api.getHeight()
        manager.updateLayoutConfig(width, height)
        manager.layout(width, height)
        manager.processLabelsOverall()
    }

    /// Upstream `processLabelsOverall`: create/style generic series guide lines after labelLayout has
    /// moved labels, calculate their geometry, then animate every hosted label and guide line. The
    /// animation pass intentionally runs for every chart view, including views without a `labelLayout`
    /// option: this is what fades pie/sunburst labels and draws pie guide lines on chart entrance.
    private func processLabelsOverall() {
        for chartView in self._chartViewList {
            // Pie and funnel own their guide-line geometry and default item-colour styling. Upstream
            // excludes views with `ignoreLabelLineUpdate` from the generic label-line pass; without
            // this gate the empty generic default style replaced their resolved coloured stroke with
            // nil after the chart view had finished rendering it.
            guard let seriesModel = chartView.__model else { continue }
            _ = chartView.group.traverse { child -> Bool in
                if child.ignore && innerStore.getECElementProps(child).forceLabelAnimation != true {
                    return true
                }
                guard let text = child.getTextContent() else { return false }
                if !chartView.ignoreLabelLineUpdate {
                    let ecData = innerStore.getECData(child)
                    let hostModel: Model
                    if let dataIndex = ecData.dataIndex {
                        hostModel = seriesModel.getData(ecData.dataType).getItemModel(Int(dataIndex))
                    }
                    else {
                        // Some SymbolDraw hosts carry ECData on their parent group rather than the
                        // concrete path. Their label still belongs to this series and inherits its line.
                        hostModel = seriesModel
                    }
                    let statesModels = labelGuideHelper.getLabelLineStatesModels(hostModel)
                    let labelLineModel = hostModel.getModel("labelLine")
                    let seriesLabelLineModel = seriesModel.getModel("labelLine")
                    if child.getTextGuideLine() == nil,
                       ((labelLineModel.get("show") as? Bool) == true
                        || (seriesLabelLineModel.get("show") as? Bool) == true) {
                        child.setTextGuideLine(Polyline())
                    }
                    labelGuideHelper.setLabelLineStyle(child, statesModels, PathStyleProps())
                    labelGuideHelper.updateLabelLinePoints(child, labelLineModel)
                    // Keep the guide in lockstep with the label visibility chosen by overlap layout.
                    child.getTextGuideLine()?.ignore = text.ignore
                }

                self.animateLabels(child, seriesModel)
                return false
            }
        }
    }

    /// Faithful port of LabelManager._animateLabels. First appearance fades text opacity 0→configured
    /// opacity and draws guide lines with strokePercent 0→1. Retained labels morph x/y/rotation and
    /// retained guide lines morph their points. Stores live on the graphic elements, matching the two
    /// upstream WeakMaps and preventing a fresh fade on ordinary setOption updates.
    private func animateLabels(_ host: Element, _ seriesModel: SeriesModel) {
        let text = host.getTextContent()
        let guideLine = host.getTextGuideLine()
        let hostProps = innerStore.getECElementProps(host)

        if let text = text,
           hostProps.forceLabelAnimation == true
            || (!text.ignore && !text.invisible
                && hostProps.disableLabelAnimation != true && !isElementRemoved(host)) {
            let store = innerStore.getECElementProps(text)
            let newLayout: [String: Double] = ["x": text.x, "y": text.y, "rotation": text.rotation]
            let ecData = innerStore.getECData(host)
            let dataIndex = ecData.dataIndex.map(Int.init)

            if let oldLayout = store.labelOldLayout {
                _ = text.attr(oldLayout)
                updateProps(text, newLayout, seriesModel, dataIndex)
            }
            else {
                _ = text.attr(newLayout)
                // Value-animation owns the same label animator and suppresses the ordinary fade.
                if labelStyle.labelInner(text).valueAnimation != true {
                    let targetOpacity = text.textStyle?.opacity ?? 1
                    if text.textStyle == nil { text.useStyle(TextStyleProps()) }
                    text.textStyle.opacity = 0
                    text.dirtyStyle()
                    initProps(text, ["style": ["opacity": targetOpacity] as [String: Any]],
                              seriesModel, dataIndex)
                }
            }
            store.labelOldLayout = newLayout

            let data = seriesModel.getData(ecData.dataType)
            labelStyle.animateLabelValue(text, ecData.dataIndex, data, seriesModel, seriesModel)
        }

        if let guideLine = guideLine, !guideLine.ignore, !guideLine.invisible,
           let shape = guideLine.shape as? PolylineShape, let points = shape.points {
            let store = innerStore.getECElementProps(guideLine)
            let newPoints = points.map { [$0.x, $0.y] }
            if let oldPoints = store.labelLineOldPoints {
                _ = guideLine.setShape("points", oldPoints)
                updateProps(guideLine, ["shape": ["points": newPoints] as [String: Any]], seriesModel)
            }
            else {
                _ = guideLine.setShape("points", newPoints)
                guideLine.pathStyle.strokePercent = 0
                initProps(guideLine, ["style": ["strokePercent": 1.0] as [String: Any]], seriesModel)
            }
            store.labelLineOldPoints = newPoints
        }
    }

    // ─────────────────────── labelLayout option parsing ───────────────────────

    /// Parse the raw `labelLayout` option (already a `LabelLayoutOption`, or an option `[String: Any]`
    /// dict) into a `LabelLayoutOption`. Returns `nil` for an absent / empty option (the collection
    /// gate) or a callback form (which is handled separately by `addLabelsOfSeries`).
    static func parseLayoutOption(_ raw: Any?) -> LabelLayoutOption? {
        guard let raw = raw else { return nil }
        if let opt = raw as? LabelLayoutOption {
            return opt
        }
        guard let dict = raw as? [String: Any], !dict.isEmpty else {
            // Callback form (LabelLayoutOptionCallback) is handled separately by `addLabelsOfSeries`
            //   (it needs per-label geometry, resolved in `updateLayoutConfig`); empty dict → skip.
            return nil
        }
        var opt = LabelLayoutOption()
        opt.moveOverlap = dict["moveOverlap"] as? String
        opt.hideOverlap = dict["hideOverlap"] as? Bool
        opt.draggable = dict["draggable"] as? Bool
        opt.x = dict["x"]
        opt.y = dict["y"]
        opt.dx = LabelManager.asDouble(dict["dx"])
        opt.dy = LabelManager.asDouble(dict["dy"])
        opt.rotate = LabelManager.asDouble(dict["rotate"])
        opt.align = dict["align"] as? ZRTextAlign
        opt.verticalAlign = dict["verticalAlign"] as? ZRTextVerticalAlign
        opt.width = LabelManager.asDouble(dict["width"])
        opt.height = LabelManager.asDouble(dict["height"])
        opt.fontSize = LabelManager.asDouble(dict["fontSize"])
        opt.labelLinePoints = dict["labelLinePoints"] as? [[Double]]
        return opt
    }

    // Int-vs-Double coercion helper (option numbers box as Int OR Double; `as? Double` returns nil on
    //   an Int literal — see MEMORY int-vs-double-option-read-trap).
    private static func asDouble(_ v: Any?) -> Double? {
        if let d = v as? Double { return d }
        if let i = v as? Int { return Double(i) }
        return nil
    }
}
