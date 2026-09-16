// Ported from echarts/src/util/innerStore.ts — keep in sync with upstream
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

import ZRenderKit
// upstream:
//   import Element from 'zrender/src/Element';        → ZRenderKit.Element
//   import { DataModel, ECEventData, BlurScope, InnerFocus, SeriesDataType,
//            ComponentMainType, ComponentItemTooltipOption } from './types';  → sibling types.swift
//   import { makeInner } from './model';              → sibling model.swift (`model.makeInner`)

public enum SSRItemType: String {   // upstream: type SSRItemType = 'chart' | 'legend'
    case chart = "chart"
    case legend = "legend"
}

/**
 * ECData stored on graphic element
 */
// upstream: `interface ECData`. Modeled as a `final class` (reference semantics) because
// `getECData(el)` returns this bag and callers mutate it in place (e.g. `ecData.dataIndex = ...`);
// those mutations must persist on the host element, so value semantics would be wrong (CONVENTIONS §4).
public final class ECData {
    public var dataIndex: Double?
    // `weak` (upstream relies on GC). This is a BACK-reference from a graphic element to
    //   the model that owns it, and a strong edge closes a permanent retain cycle: `makeInner`'s
    //   backing `WeakMap` is an NSMapTable with weak KEYS but STRONG VALUES, so this bag is retained
    //   while its Element key lives; the marker views assign `dataModel = mlModel/mpModel/maModel`,
    //   and `markerModel.setData(data)` makes the model own the `SeriesData`, whose `_graphicEls`
    //   strongly holds those same Elements. The weak key would then never be cleared. The referenced
    //   models are owned by `GlobalModel` (component/series maps) for their whole lifetime, so `weak`
    //   does not shorten the useful lifetime; if the model IS torn down, readers fall back to the
    //   `ecModel.getSeriesByIndex(...)` arm (ECharts.swift packEventData) rather than resurrecting it.
    //   `DataModel: DataHost, DataFormatMixin` and `DataFormatMixin: DataHost, AnyObject`, so the
    //   existential is class-bound and `weak` is legal.
    public weak var dataModel: DataModel?
    public var eventData: ECEventData?
    public var seriesIndex: Double?
    public var dataType: SeriesDataType?
    public var focus: InnerFocus?
    public var blurScope: BlurScope?
    public var ssrType: SSRItemType?

    // Required by `tooltipConfig` and `focus`.
    public var componentMainType: ComponentMainType?
    public var componentIndex: Double?
    public var componentHighDownName: String?

    // To make a tooltipConfig, seach `setTooltipConfig`.
    // Used to find component tooltip option, which is used as
    // the parent of tooltipConfig.option for cascading.
    // If not provided, do not use component as its parent.
    // (Set manatary to make developers not to forget them).
    // upstream inline interface; modeled as a nested data struct (no identity reliance, CONVENTIONS §4).
    public struct TooltipConfig {
        // Target item name to locate tooltip.
        public var name: String
        // upstream `ComponentItemTooltipOption<unknown>`; depends on sibling
        //   types.swift modeling `ComponentItemTooltipOption` as a generic.
        public var option: ComponentItemTooltipOption<Any>
        public init(name: String, option: ComponentItemTooltipOption<Any>) {
            self.name = name
            self.option = option
        }
    }
    public var tooltipConfig: TooltipConfig?

    public init() {}
}

// Free-function module → caseless enum namespace named after the file (CONVENTIONS §2).
// upstream call sites `getECData(el)` / `setCommonECData(...)` → `innerStore.getECData(el)` / `innerStore.setCommonECData(...)`.
public enum innerStore {

    // upstream `makeInner<ECData, Element>()` lazily creates an empty `{}` bag per host.
    //   Swift generics cannot construct `T` without a factory, so we assume the sibling
    //   `model.makeInner(_:)` API takes a factory closure: `(@escaping () -> T) -> (Host) -> T`.
    public static let getECData: (Element) -> ECData = model.makeInner { ECData() }

    // ------------------------------------------------------------------------
    // note (adaptation, NO upstream symbol — nothing to grep for upstream). Upstream augments
    //   zrender's `Element` IN PLACE (`(el as ECElement).tooltipDisabled = true`, CustomView.ts:1052)
    //   because TS declaration-merges `interface ECElement extends Element`. In THIS port `ECElement`
    //   (util/types.swift) is a plain protocol that NO concrete scene-graph type conforms to, so its
    //   props have to live in a per-element side store — the same idiom `states.getHighDownInner`
    //   already uses for the high-down half of that same interface.
    //   Only the props actually READ at runtime are modeled; add more here as they go live (the rest
    //   are still marked `// upstream: (el as ECElement).<prop>` + DEFERRED at their call sites).
    //
    //   WHICH BAG? (the rule, stated once on `ECElement` itself — util/types.swift — and mirrored on
    //     `states.HighDownInner`; there are exactly TWO bags for the one upstream interface and a third
    //     must not be invented):
    //       • high-down props — `hoverState`, `selected`, `onHoverStateChange`, `z2EmphasisLift`,
    //         `z2SelectLift`, `highDownSilentOnTouch` → `states.getHighDownInner` (util/states.swift),
    //         which also carries upstream's `ExtendedProps`.
    //       • EVERYTHING ELSE — `tooltipDisabled` (live, below) and, when they land,
    //         `disableLabelAnimation` / `forceLabelAnimation` / `disableLabelLayout` /
    //         `disableMorphing` → HERE.
    //   PLACEMENT: upstream `util/innerStore.ts` contains only `ECData` + `setCommonECData`, so this
    //     store is an ADDITION to the file (it is the file that already owns the `makeInner`-on-Element
    //     idiom); it has no upstream line to diff against — see the rule above instead.
    // ------------------------------------------------------------------------
    public final class ECElementProps {
        /// upstream `ECElement['tooltipDisabled']` — "Force disable triggering tooltip".
        ///   SET by `doCreateOrUpdateEl` from a custom-series `elOption.tooltipDisabled`
        ///   (chart/custom/CustomView.swift, upstream CustomView.ts:1051).
        ///   READ by `TooltipView._tryShow`'s `findEventDispatcher` walk (TooltipView.ts:483): the flag
        ///   on the hovered element OR on ANY of its ancestors cancels the tooltip entirely.
        public var tooltipDisabled: Bool?
        /// Upstream `ECElement.forceLabelAnimation` / `disableLabelAnimation`.
        /// `forceLabelAnimation` wins when both are present.
        public var forceLabelAnimation: Bool?
        public var disableLabelAnimation: Bool?

        /// Per-element stores used by LabelManager._animateLabels. Upstream keeps these in
        /// `labelLayoutInnerStore(textEl)` / `labelLineAnimationStore(guideLine)` WeakMaps.
        /// They live in the already-designated ECElement side store in Swift.
        public var labelOldLayout: [String: Double]?
        public var labelLineOldPoints: [[Double]]?
        public init() {}
    }
    public static let getECElementProps: (Element) -> ECElementProps = model.makeInner { ECElementProps() }

    // upstream: `const setCommonECData = (seriesIndex, dataType, dataIdx, el) => {...}`.
    // `el` typed `Element?` to honor the upstream `if (el)` truthiness guard.
    public static func setCommonECData(
        _ seriesIndex: Double, _ dataType: SeriesDataType, _ dataIdx: Double, _ el: Element?
    ) {
        if let el = el {
            let ecData = getECData(el)
            // Add data index and series index for indexing the data by element
            // Useful in tooltip
            ecData.dataIndex = dataIdx
            ecData.dataType = dataType
            ecData.seriesIndex = seriesIndex
            ecData.ssrType = .chart

            // TODO: not store dataIndex on children.
            if el.type == "group" {
                el.traverse({ (child: Element) -> Void in
                    let childECData = getECData(child)
                    childECData.seriesIndex = seriesIndex
                    childECData.dataIndex = dataIdx
                    childECData.dataType = dataType
                    childECData.ssrType = .chart
                })
            }
        }
    }
}
