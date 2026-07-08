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
//   what the slim driver needs:
//     - `addLabelsOfSeries`: collect each series' label textContents when a `labelLayout` option is set.
//     - `updateLayoutConfig`: apply the user `labelLayout` option (x / y / rotate / align / verticalAlign
//        / width / height / fontSize / dx / dy) to each label.
//     - `layout`: resolve overlap globally — `moveOverlap` (shiftX/shiftY → `shiftLayoutOnXY`) and
//        `hideOverlap` (rotated-rect OBB overlap → `labelLayoutHelper.hideOverlap`).
//
//   DEFERRED (documented gaps, faithful to the rest of the port):
//     - The label-layout callback form (`LabelLayoutOptionCallback`) — only the option-object form is read.
//     - `draggable` / drag handlers, `labelLinePoints`, and `processLabelsOverall` (label-line update +
//        label value/fade animation) — the slim driver draws a static frame and has no per-frame label
//        animation loop, and label lines are drawn by each chart view.
//     - The `dummyTransformable` global-space decomposition of `defaultAttr` — since the slim driver
//        renders each label fresh every frame, the label's CURRENT attrs ARE the defaults, so the
//        "restore default" branches of `updateLayoutConfig` reduce to no-ops and are omitted.

/// upstream: `class LabelManager` (LabelManager.ts).
public final class LabelManager {

    private var _labelList: [LabelLayoutData] = []
    private var _chartViewList: [ChartView] = []

    public init() {}

    /// upstream: clearLabels()
    public func clearLabels() {
        self._labelList = []
        self._chartViewList = []
    }

    /// upstream: private _addLabel(dataIndex, dataType, seriesModel, label, layoutOptionOrCb)
    private func _addLabel(_ label: ZRText, _ layoutOption: LabelLayoutOption?) {
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
        guard let layoutOption = LabelManager.parseLayoutOption(rawOption) else {
            // No option (or an empty option object / an unsupported callback form) → skip.
            return
        }

        _ = chartView.group.traverse({ child -> Bool in
            if child.ignore {
                return true    // Stop traverse descendants.
            }
            // Only support label being hosted on graphic elements.
            if let textEl = child.getTextContent() {
                // Can only attach the text on the element with dataIndex — mirrors upstream (the ECData
                //   is read for dataIndex/dataType; here only the label + option are needed downstream).
                _ = innerStore.getECData(child)
                self._addLabel(textEl, layoutOption)
            }
            return false
        })
    }

    /// upstream: updateLayoutConfig(api) — applies the user `labelLayout` option to each label.
    /// PORT-NOTE: only the override branches are applied (the "restore default" else-branches are
    /// no-ops on a fresh render, see the DEFERRED note). `draggable` / `labelLinePoints` deferred.
    public func updateLayoutConfig(_ width: Double, _ height: Double) {
        let degreeToRadian = Double.pi / 180
        for labelItem in self._labelList {
            guard let layoutOption = labelItem.layoutOption else { continue }
            let label = labelItem.label
            let hostEl = label.__hostTarget

            // Host textConfig: force local:false; drop position config when x/y override it and rotation
            //   config when rotate overrides it (else keep the host's default); carry dx/dy as offset.
            //   PORT-NOTE: upstream `hostEl.setTextConfig({...})` relies on zrender's field-MERGE
            //   (`extend(this.textConfig, cfg)`), preserving unrelated fields like `inside`. The port's
            //   `setTextConfig` is a wholesale REPLACE stub, so start `cfg` from a COPY of the existing
            //   textConfig to reproduce the merge (keeps `inside`, and keeps `position`/`rotation` when
            //   not overridden — which, on the slim driver's fresh-per-frame render, equal the saved
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

            if let rotate = layoutOption.rotate {
                label.rotation = rotate * degreeToRadian
            }

            // LABEL_OPTION_TO_STYLE_KEYS = ['align', 'verticalAlign', 'width', 'height', 'fontSize']
            if let align = layoutOption.align { _ = label.setStyle("align", align) }
            if let verticalAlign = layoutOption.verticalAlign { _ = label.setStyle("verticalAlign", verticalAlign) }
            if let w = layoutOption.width { _ = label.setStyle("width", w) }
            if let h = layoutOption.height { _ = label.setStyle("height", h) }
            if let fs = layoutOption.fontSize { _ = label.setStyle("fontSize", fs) }
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
    /// The slim driver calls this ONCE per render, AFTER `renderSeries` (so every series has attached
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
    }

    // ─────────────────────── labelLayout option parsing ───────────────────────

    /// Parse the raw `labelLayout` option (already a `LabelLayoutOption`, or an option `[String: Any]`
    /// dict) into a `LabelLayoutOption`. Returns `nil` for an absent / empty option (the collection
    /// gate) or an unsupported callback form (PORT-TODO).
    static func parseLayoutOption(_ raw: Any?) -> LabelLayoutOption? {
        guard let raw = raw else { return nil }
        if let opt = raw as? LabelLayoutOption {
            return opt
        }
        guard let dict = raw as? [String: Any], !dict.isEmpty else {
            // Callback form (LabelLayoutOptionCallback) is a documented gap; empty dict → skip.
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
