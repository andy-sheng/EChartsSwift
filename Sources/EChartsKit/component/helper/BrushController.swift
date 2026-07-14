// Ported from echarts/src/component/helper/BrushController.ts — keep in sync with upstream
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

// import {curry, each, map, bind, merge, clone, defaults, assert} from 'zrender/src/core/util';
//   -> ZRenderKit `util` (each/map/clone/merge/defaults). `curry`/`bind` are Swift closures.
// import Eventful from 'zrender/src/core/Eventful';   -> ZRenderKit `Eventful` (COMPOSED, see below)
// import * as graphic from '../../util/graphic';      -> Group / Rect / Polyline / Polygon (ZRenderKit)
//                                                        + getTransform / transformDirection / clipPointsByRect
// import * as interactionMutex from './interactionMutex';  -> `interactionMutex` (interactionMutex.swift)
// import DataDiffer from '../../data/DataDiffer';     -> `DataDiffer` (data/DataDiffer.swift)
// import { ZRenderType } from 'zrender/src/zrender';  -> ZRenderKit `ZRenderType` (= ZRender)
// import { ElementEvent } from 'zrender/src/Element'; -> ZRenderKit `ElementEvent`
// import * as matrix from 'zrender/src/core/matrix';  -> ZRenderKit `matrix` / `MatrixArray`
// import tokens from '../../visual/tokens';           -> `tokens` (visual/tokens.swift)


/**
 * BrushController is not only used in "brush component",
 * but is also used in "tooltip DataZoom", and other possible
 * further brush behavior related scenarios.
 * So `BrushController` should not depend on "brush component model".
 */


// export type BrushType = 'polygon' | 'rect' | 'lineX' | 'lineY';
//   PORT-NOTE: TS string-literal unions become `String` (CONVENTIONS §2); the four legal values are
//   the keys of `selector` / `coverRenderers`, and an unknown value simply matches no renderer.
public typealias BrushType = String

/**
 * Only for drawing (after enabledBrush).
 * 'line', 'rect', 'polygon' or false
 * If passing false/null/undefined, disable brush.
 * If passing 'auto', determined by panel.defaultBrushType
 */
// export type BrushTypeUncertain = BrushType | false | 'auto';
//   PORT-NOTE: `false` collapses onto `nil` (CONVENTIONS §6) — a nil `brushType` disables the brush,
//   exactly as upstream's falsy check (`brushOption.brushType && this._doEnableBrush(...)`).
public typealias BrushTypeUncertain = String?

// export type BrushMode = 'single' | 'multiple';
public typealias BrushMode = String

// MinMax: Range of linear brush.
// MinMax[]: Range of multi-dimension like rect/polygon, which is a MinMax
//     list for each dimension of the coord sys. For example:
//     cartesian: [[xMin, xMax], [yMin, yMax]]
//     geo: [[lngMin, lngMin], [latMin, latMax]]
// export type BrushDimensionMinMax = number[];
public typealias BrushDimensionMinMax = [Double]
// export type BrushAreaRange = BrushDimensionMinMax | BrushDimensionMinMax[];
//   PORT-NOTE: untagged TS union -> `Any`; read back through `brushDimensionMinMax(_:)` /
//   `brushDimensionMinMaxList(_:)` (selector.swift), which is exactly what upstream's `as` casts do.
public typealias BrushAreaRange = Any

// export interface BrushCoverConfig { brushType; id?; range?; panelId?; brushMode?; brushStyle?;
//                                     transformable?; removeOnClick?; z?; }
//
// PORT-NOTE: upstream this is a plain object literal, MUTATED IN PLACE through the cover
//   (`cover.__brushOption.range = ...` in driftRect/driftPolygon/updateCoverByMouse). A Swift struct
//   would be copied on every access and the mutation lost — so this is a `final class`
//   (CONVENTIONS §4). Field-for-field with upstream; `brushStyle` stays the `[String: Any]` bag
//   produced by `Model#getItemStyle()`.
public final class BrushCoverConfig {
    // Mandatory. determine how to convert to/from coord('rect' or 'polygon' or 'lineX/Y')
    public var brushType: BrushType
    // Can be specified by user to map covers in `updateCovers`
    // in `dispatchAction({type: 'brush', areas: [{id: ...}, ...]})`
    public var id: String?
    // Range in global coordinate (pixel).
    public var range: BrushAreaRange?
    // When create a new area by `updateCovers`, panelId should be specified.
    // If not null/undefined, means global panel.
    // Also see `BrushAreaParam['panelId']`.
    public var panelId: String?

    public var brushMode: BrushMode?
    // `brushStyle`, `transformable` is not mandatory. When the controller is enabled,
    // `updateCovers` inherits from the current brush option first, and then falls back
    // to `DEFAULT_BRUSH_OPT`.
    public var brushStyle: [String: Any]?
    public var transformable: Bool?
    public var removeOnClick: Bool?
    public var z: Double?

    public init(brushType: BrushType) {
        self.brushType = brushType
    }

    // clone(brushOption) — upstream `zrUtil.clone` deep-copies the option literal.
    public func cloned() -> BrushCoverConfig {
        let c = BrushCoverConfig(brushType: brushType)
        c.id = id
        c.range = range   // arrays are value types in Swift -> already a copy
        c.panelId = panelId
        c.brushMode = brushMode
        c.brushStyle = brushStyle
        c.transformable = transformable
        c.removeOnClick = removeOnClick
        c.z = z
        return c
    }

    /// `merge(clone(baseBrushOption), coverConfig, true)` — the per-cover option is the creator config
    /// overridden by the (area-level) cover config bag. `coverConfig` is a `BrushAreaParamInternal`
    /// (`[String: Any]`), i.e. one entry of `BrushModel.areas`.
    static func merged(_ base: BrushCoverCreatorConfig, _ coverConfig: [String: Any]) -> BrushCoverConfig {
        let c = BrushCoverConfig(brushType: (coverConfig["brushType"] as? BrushType) ?? (base.brushType ?? ""))
        c.brushMode = base.brushMode
        c.brushStyle = base.brushStyle
        c.transformable = base.transformable
        c.removeOnClick = base.removeOnClick
        c.z = base.z

        if let v = coverConfig["id"] as? String { c.id = v }
        if let v = coverConfig["range"] { c.range = v }
        if let v = coverConfig["panelId"] as? String { c.panelId = v }
        if let v = coverConfig["brushMode"] as? String { c.brushMode = v }
        if let v = coverConfig["brushStyle"] as? [String: Any] { c.brushStyle = v }
        if let v = coverConfig["transformable"] as? Bool { c.transformable = v }
        if let v = coverConfig["removeOnClick"] as? Bool { c.removeOnClick = v }
        if let v = brushCoerceDouble(coverConfig["z"]) { c.z = v }
        return c
    }
}

/**
 * `BrushAreaCreatorOption` input to brushModel via `setBrushOption`,
 * merge and convert to `BrushCoverCreatorConfig`.
 */
// export interface BrushCoverCreatorConfig extends Pick<BrushCoverConfig,
//     'brushMode' | 'transformable' | 'removeOnClick' | 'brushStyle' | 'z'> { brushType: BrushTypeUncertain; }
public final class BrushCoverCreatorConfig {
    public var brushType: BrushTypeUncertain
    public var brushMode: BrushMode?
    public var brushStyle: [String: Any]?
    public var transformable: Bool?
    public var removeOnClick: Bool?
    public var z: Double?

    public init(brushType: BrushTypeUncertain = nil) {
        self.brushType = brushType
    }

    /// Build from the `[String: Any]` bag `BrushModel.brushOption` carries (generateBrushOption).
    public convenience init(_ bag: [String: Any]) {
        self.init(brushType: bag["brushType"] as? String)
        self.brushMode = bag["brushMode"] as? String
        self.brushStyle = bag["brushStyle"] as? [String: Any]
        self.transformable = bag["transformable"] as? Bool
        self.removeOnClick = bag["removeOnClick"] as? Bool
        self.z = brushCoerceDouble(bag["z"])
    }

    // merge(clone(DEFAULT_BRUSH_OPT), brushOption, true)
    static func mergedWithDefault(_ brushOption: BrushCoverCreatorConfig) -> BrushCoverCreatorConfig {
        let c = BrushCoverCreatorConfig(brushType: brushOption.brushType)
        // DEFAULT_BRUSH_OPT
        c.brushStyle = brushOption.brushStyle ?? DEFAULT_BRUSH_OPT_brushStyle
        c.transformable = brushOption.transformable ?? true
        c.brushMode = brushOption.brushMode ?? "single"
        c.removeOnClick = brushOption.removeOnClick ?? false
        c.z = brushOption.z
        return c
    }
}

// type BrushStyleKey = 'fill' | 'stroke' | 'lineWidth' | 'opacity' | 'shadowBlur'
//     | 'shadowOffsetX' | 'shadowOffsetY' | 'shadowColor';


// const BRUSH_PANEL_GLOBAL = true as const;
//   PORT-NOTE: upstream overloads `true` as "the global panel" inside a `BrushPanelConfig | true`
//   union. Swift models the union as an enum, so `.global` IS `BRUSH_PANEL_GLOBAL`.
enum BrushPanelConfigOrGlobal {
    case panel(BrushPanelConfig)
    case global          // BRUSH_PANEL_GLOBAL
}

// export interface BrushPanelConfig { panelId; clipPath(localPoints, transform); isTargetByCursor(e,
//     localCursorPoint, transform); defaultBrushType?; getLinearBrushOtherExtent?(xyIndex); }
public struct BrushPanelConfig {
    // mandatory.
    public var panelId: String
    // mandatory.
    public var clipPath: (_ localPoints: [[Double]], _ transform: MatrixArray?) -> [[Double]]
    // mandatory.
    public var isTargetByCursor: (_ e: ElementEvent, _ localCursorPoint: [Double], _ transform: MatrixArray?) -> Bool
    // optional, only used when brushType is 'auto'.
    public var defaultBrushType: BrushType?
    // optional.
    public var getLinearBrushOtherExtent: ((_ xyIndex: Int) -> [Double])?

    public init(
        panelId: String,
        clipPath: @escaping (_ localPoints: [[Double]], _ transform: MatrixArray?) -> [[Double]],
        isTargetByCursor: @escaping (_ e: ElementEvent, _ localCursorPoint: [Double], _ transform: MatrixArray?) -> Bool,
        defaultBrushType: BrushType? = nil,
        getLinearBrushOtherExtent: ((_ xyIndex: Int) -> [Double])? = nil
    ) {
        self.panelId = panelId
        self.clipPath = clipPath
        self.isTargetByCursor = isTargetByCursor
        self.defaultBrushType = defaultBrushType
        self.getLinearBrushOtherExtent = getLinearBrushOtherExtent
    }
}

// interface BrushCover extends graphic.Group { __brushOption: BrushCoverConfig; }
//   Upstream augments the Group instance with `__brushOption`; `Group` is `open` here, so the
//   augmentation is a subclass (same effect, typed).
private final class BrushCover: Group {
    var __brushOption: BrushCoverConfig!
}

// type Point = number[];
//   PORT-NOTE: file-private — ZRenderKit already exports a `Point` CLASS at module scope.
private typealias Point = [Double]

// const mathMin = Math.min; const mathMax = Math.max; const mathPow = Math.pow;
//   -> Swift.min / Swift.max / pow

private let COVER_Z: Double = 10000
private let UNSELECT_THRESHOLD: Double = 6
private let MIN_RESIZE_LINE_WIDTH: Double = 6
private let MUTEX_RESOURCE_KEY = "globalPan"

// type DirectionName = 'w' | 'e' | 'n' | 's';
private typealias DirectionName = String
// type DirectionNameSequence = DirectionName[];
private typealias DirectionNameSequence = [DirectionName]

// const DIRECTION_MAP = { w: [0, 0], e: [0, 1], n: [1, 0], s: [1, 1] } as const;
private let DIRECTION_MAP: [DirectionName: [Int]] = [
    "w": [0, 0],
    "e": [0, 1],
    "n": [1, 0],
    "s": [1, 1]
]
// const CURSOR_MAP = { w: 'ew', e: 'ew', n: 'ns', s: 'ns', ne: 'nesw', sw: 'nesw', nw: 'nwse', se: 'nwse' } as const;
private let CURSOR_MAP: [String: String] = [
    "w": "ew",
    "e": "ew",
    "n": "ns",
    "s": "ns",
    "ne": "nesw",
    "sw": "nesw",
    "nw": "nwse",
    "se": "nwse"
]
// const DEFAULT_BRUSH_OPT = { brushStyle: {lineWidth: 2, stroke: ..., fill: ...}, transformable: true,
//     brushMode: 'single', removeOnClick: false };
//   (the scalar defaults are applied in `BrushCoverCreatorConfig.mergedWithDefault` above.)
private let DEFAULT_BRUSH_OPT_brushStyle: [String: Any] = [
    "lineWidth": 2.0,
    "stroke": tokens.color.backgroundTint,
    "fill": tokens.color.borderTint
]

// let baseUID = 0;
private var baseUID: Int = 0

// export interface BrushControllerEvents {
//     brush: { areas: {brushType; panelId; range}[]; isEnd: boolean; removeOnClick: boolean; }
// }
public struct BrushControllerBrushArea {
    public var brushType: BrushType
    public var panelId: String?
    public var range: BrushAreaRange?
}
public struct BrushControllerBrushEvent {
    public var areas: [BrushControllerBrushArea]
    public var isEnd: Bool
    public var removeOnClick: Bool
}

/**
 * params:
 *     areas: Array.<Array>, coord relates to container group,
 *                             If no container specified, to global.
 *     opt {
 *         isEnd: boolean,
 *         removeOnClick: boolean
 *     }
 */
// class BrushController extends Eventful<{brush: (params) => void}>
//
// PORT-NOTE: ZRenderKit's `Eventful` is a `final class`, so it cannot be sub-classed. It is COMPOSED
//   instead and `on`/`off`/`trigger` forward to it — the same adaptation `ZRenderKit.Handler` already
//   makes for its own Eventful base.
public final class BrushController {

    // readonly group: graphic.Group;
    public let group: Group

    // @internal _zr: ZRenderType;
    let _zr: ZRenderType

    // @internal _brushType: BrushTypeUncertain;
    //   (an explicit `= nil`: `BrushTypeUncertain` is a typealias to Optional, which Swift does not
    //    implicitly default-initialize.)
    var _brushType: BrushTypeUncertain = nil

    // @internal Only for drawing (after enabledBrush). _brushOption: BrushCoverCreatorConfig;
    var _brushOption: BrushCoverCreatorConfig?

    // @internal Key: panelId.  _panels: Dictionary<BrushPanelConfig>;
    var _panels: [String: BrushPanelConfig]?

    // @internal _track: number[][] = [];
    fileprivate var _track: [Point] = []

    // @internal _dragging: boolean;
    var _dragging: Bool = false

    // @internal _covers: BrushCover[] = [];
    fileprivate var _covers: [BrushCover] = []

    // @internal _creatingCover: BrushCover;
    fileprivate var _creatingCover: BrushCover?

    // @internal _creatingPanel: BrushPanelConfigOrGlobal;
    fileprivate var _creatingPanel: BrushPanelConfigOrGlobal?

    // private _enableGlobalPan: boolean;
    private var _enableGlobalPan: Bool = false

    // private _mounted: boolean;
    private var _mounted: Bool = false

    // @internal _transform: matrix.MatrixArray;
    var _transform: MatrixArray?

    // private _uid: string;
    private var _uid: String = ""

    // private _handlers: {[eventName: string]: (this: BrushController, e: ElementEvent) => void} = {};
    //   PORT-NOTE (Eventful.off closure-identity gap): ZRenderKit's `Eventful.off(event, handler)` cannot
    //   remove ONE handler (Swift closures are not comparable — see the POTENTIAL-BUG note in
    //   Core/Eventful.swift), and `zr.off(event)` would nuke every other listener of that event
    //   (Draggable's, the host's). So the three pointer handlers are registered on the zr ONCE (on the
    //   first `_doEnableBrush`) and each one early-returns while the brush is disabled — `_brushType`
    //   is the same "is the brush active" gate upstream uses in `resetCursor`. Observable behavior is
    //   identical; only the (inert) listener registration outlives a `disableBrush`.
    private var _handlersMounted: Bool = false

    // The composed event bus (upstream: `extends Eventful`).
    private let _eventful = Eventful()

    // constructor(zr: ZRenderType)
    public init(_ zr: ZRenderType) {
        // if (__DEV__) { assert(zr); }
        self._zr = zr

        // this.group = new graphic.Group();
        self.group = Group()

        // this._uid = 'brushController_' + baseUID++;
        self._uid = "brushController_" + String(baseUID)
        baseUID += 1

        // each(pointerHandlers, (handler, eventName) => { this._handlers[eventName] = bind(handler, this); });
        //   -> `_mountHandlers()` below (bound lazily, see the `_handlers` PORT-NOTE).
    }

    // ---- the composed Eventful surface (upstream: inherited from Eventful) ----
    @discardableResult
    public func on(_ event: String, _ handler: @escaping EventCallback) -> BrushController {
        _ = self._eventful.on(event, handler)
        return self
    }
    @discardableResult
    public func off(_ event: String? = nil) -> BrushController {
        _ = self._eventful.off(event)
        return self
    }
    func trigger(_ event: String, _ params: BrushControllerBrushEvent) {
        _ = self._eventful.trigger(event, params)
    }

    /**
     * If set to `false`, select disabled.
     */
    // enableBrush(brushOption: Partial<BrushCoverCreatorConfig> | false): BrushController
    @discardableResult
    public func enableBrush(_ brushOption: BrushCoverCreatorConfig?) -> BrushController {
        // if (__DEV__) { assert(this._mounted); }

        // this._brushType && this._doDisableBrush();
        if self._brushType != nil {
            self._doDisableBrush()
        }
        // brushOption.brushType && this._doEnableBrush(brushOption);
        if let brushOption = brushOption, let bt = brushOption.brushType, !bt.isEmpty {
            self._doEnableBrush(brushOption)
        }

        return self
    }

    // private _doEnableBrush(brushOption: Partial<BrushCoverCreatorConfig>): void
    private func _doEnableBrush(_ brushOption: BrushCoverCreatorConfig) {
        let zr = self._zr

        // Consider roam, which takes globalPan too.
        if !self._enableGlobalPan {
            interactionMutex.take(zr, MUTEX_RESOURCE_KEY, self._uid)
        }

        // each(this._handlers, (handler, eventName) => { zr.on(eventName, handler); });
        self._mountHandlers()

        // this._brushType = brushOption.brushType;
        self._brushType = brushOption.brushType
        // this._brushOption = merge(clone(DEFAULT_BRUSH_OPT), brushOption, true);
        self._brushOption = BrushCoverCreatorConfig.mergedWithDefault(brushOption)
    }

    // private _doDisableBrush(): void
    private func _doDisableBrush() {
        let zr = self._zr

        interactionMutex.release(zr, MUTEX_RESOURCE_KEY, self._uid)

        // each(this._handlers, (handler, eventName) => { zr.off(eventName, handler); });
        //   -> see the `_handlers` PORT-NOTE: the listeners stay registered but go inert once
        //      `_brushType` is nil (each one checks it first).

        // this._brushType = this._brushOption = null;
        self._brushType = nil
        self._brushOption = nil
    }

    /**
     * @param panelOpts If not pass, it is global brush.
     */
    // setPanels(panelOpts?: BrushPanelConfig[]): BrushController
    @discardableResult
    public func setPanels(_ panelOpts: [BrushPanelConfig]?) -> BrushController {
        if let panelOpts = panelOpts, !panelOpts.isEmpty {
            var panels: [String: BrushPanelConfig] = [:]
            util.each(panelOpts) { panelOpt, _ in
                // panels[panelOpts.panelId] = clone(panelOpts);
                panels[panelOpt.panelId] = panelOpt
            }
            self._panels = panels
        }
        else {
            self._panels = nil
        }
        return self
    }

    // mount(opt?: {enableGlobalPan?; x?; y?; rotation?; scaleX?; scaleY?}): BrushController
    @discardableResult
    public func mount(
        enableGlobalPan: Bool = false,
        x: Double = 0,
        y: Double = 0,
        rotation: Double = 0,
        scaleX: Double = 1,
        scaleY: Double = 1
    ) -> BrushController {
        // if (__DEV__) { this._mounted = true; }  // should be at first.
        self._mounted = true

        self._enableGlobalPan = enableGlobalPan

        let thisGroup = self.group
        self._zr.add(thisGroup)

        // thisGroup.attr({x, y, rotation, scaleX, scaleY});
        thisGroup.x = x
        thisGroup.y = y
        thisGroup.rotation = rotation
        thisGroup.scaleX = scaleX
        thisGroup.scaleY = scaleY

        // this._transform = thisGroup.getLocalTransform();
        self._transform = thisGroup.getLocalTransform()

        return self
    }

    /**
     * Update covers.
     * @param coverConfigList
     *        If coverConfigList is null/undefined, all covers removed.
     */
    // updateCovers(coverConfigList: BrushCoverConfig[])
    //   PORT-NOTE: the input is `brushModel.areas.slice()` — the `[String: Any]` area bags. Upstream
    //   merges each with the base brush option in-place; done in `BrushCoverConfig.merged`.
    @discardableResult
    public func updateCovers(_ coverConfigListIn: [[String: Any]]) -> BrushController {
        // if (__DEV__) { assert(this._mounted); }

        // const baseBrushOption = this._brushOption || DEFAULT_BRUSH_OPT;
        let baseBrushOption = self._brushOption
            ?? BrushCoverCreatorConfig.mergedWithDefault(BrushCoverCreatorConfig())

        // coverConfigList = map(coverConfigList, coverConfig => merge(clone(baseBrushOption), coverConfig, true));
        let coverConfigList: [BrushCoverConfig] = util.map(coverConfigListIn) { coverConfig, _ in
            return BrushCoverConfig.merged(baseBrushOption, coverConfig)
        }

        // const tmpIdPrefix = '\0-brush-index-';
        let tmpIdPrefix = "\0-brush-index-"
        let oldCovers = self._covers
        var newCovers: [BrushCover?] = Array(repeating: nil, count: coverConfigList.count)
        let controller = self
        let creatingCover = self._creatingCover

        // function getKey(brushOption, index) { return (id != null ? id : tmpIdPrefix + index) + '-' + brushType; }
        func getKey(_ brushOption: BrushCoverConfig, _ index: Int) -> String {
            return (brushOption.id != nil ? brushOption.id! : tmpIdPrefix + String(index))
                + "-" + brushOption.brushType
        }
        // function oldGetKey(cover, index) { return getKey(cover.__brushOption, index); }
        func oldGetKey(_ cover: BrushCover, _ index: Int) -> String {
            return getKey(cover.__brushOption, index)
        }

        // function addOrUpdate(newIndex, oldIndex?) { ... }
        func addOrUpdate(_ newIndex: Int, _ oldIndex: Int?) {
            let newBrushInternal = coverConfigList[newIndex]
            // Consider setOption in event listener of brushSelect,
            // where updating cover when creating should be forbidden.
            if let oldIndex = oldIndex, oldCovers[oldIndex] === creatingCover {
                newCovers[newIndex] = oldCovers[oldIndex]
            }
            else {
                let cover: BrushCover
                if let oldIndex = oldIndex {
                    oldCovers[oldIndex].__brushOption = newBrushInternal
                    cover = oldCovers[oldIndex]
                }
                else {
                    cover = endCreating(controller, createCover(controller, newBrushInternal))
                }
                newCovers[newIndex] = cover
                updateCoverAfterCreation(controller, cover)
            }
        }

        // function remove(oldIndex) { if (oldCovers[oldIndex] !== creatingCover) { group.remove(...); } }
        func removeCover(_ oldIndex: Int) {
            if oldCovers[oldIndex] !== creatingCover {
                _ = controller.group.remove(oldCovers[oldIndex])
            }
        }

        // (new DataDiffer(oldCovers, coverConfigList, oldGetKey, getKey)).add(addOrUpdate).update(addOrUpdate)
        //     .remove(remove).execute();
        _ = DataDiffer<Any>(
            oldCovers,
            coverConfigList,
            { value, index in
                guard let cover = value as? BrushCover else { return "" }
                return oldGetKey(cover, index)
            },
            { value, index in
                guard let cfg = value as? BrushCoverConfig else { return "" }
                return getKey(cfg, index)
            }
        )
        .add { newIndex in addOrUpdate(newIndex, nil) }
        .update { newIndex, oldIndex in addOrUpdate(newIndex, oldIndex) }
        .remove { oldIndex in removeCover(oldIndex) }
        .execute()

        // this._covers = newCovers  (assigned up-front upstream; the DataDiffer fills it densely)
        self._covers = newCovers.compactMap { $0 }

        return self
    }

    // unmount()
    @discardableResult
    public func unmount() -> BrushController {
        // if (__DEV__) { if (!this._mounted) { return; } }
        if !self._mounted {
            return self
        }

        self.enableBrush(nil)   // enableBrush(false)

        // container may 'removeAll' outside.
        _ = clearCovers(self)
        self._zr.remove(self.group)

        self._mounted = false   // should be at last.

        return self
    }

    // dispose()
    public func dispose() {
        self.unmount()
        self.off()
    }

    // ------------------------------------------------------------------
    // The zr pointer listeners (upstream `pointerHandlers` + `_handlers`).
    // ------------------------------------------------------------------
    private func _mountHandlers() {
        if self._handlersMounted { return }
        self._handlersMounted = true

        let zr = self._zr

        // mousedown
        _ = zr.on("mousedown", { [weak self] _, args in
            guard let self = self, let e = args.first as? ElementEvent else { return nil }
            guard self._brushType != nil else { return nil }   // see the `_handlers` PORT-NOTE
            pointerHandlerMousedown(self, e)
            return nil
        })

        // mousemove
        _ = zr.on("mousemove", { [weak self] _, args in
            guard let self = self, let e = args.first as? ElementEvent else { return nil }
            guard self._brushType != nil else { return nil }
            pointerHandlerMousemove(self, e)
            return nil
        })

        // mouseup
        _ = zr.on("mouseup", { [weak self] _, args in
            guard let self = self, let e = args.first as? ElementEvent else { return nil }
            guard self._brushType != nil else { return nil }
            pointerHandlerMouseup(self, e)
            return nil
        })
    }
}


// function createCover(controller, brushOption): BrushCover
private func createCover(_ controller: BrushController, _ brushOption: BrushCoverConfig) -> BrushCover {
    let cover = coverRenderers[brushOption.brushType]!.createCover(controller, brushOption)
    cover.__brushOption = brushOption
    updateZ(cover, brushOption)
    _ = controller.group.add(cover)
    return cover
}

// function endCreating(controller, creatingCover): BrushCover
@discardableResult
private func endCreating(_ controller: BrushController, _ creatingCover: BrushCover) -> BrushCover {
    let coverRenderer = getCoverRenderer(creatingCover)
    if let endCreatingFn = coverRenderer.endCreating {
        endCreatingFn(controller, creatingCover)
        updateZ(creatingCover, creatingCover.__brushOption)
    }
    return creatingCover
}

// function updateCoverShape(controller, cover): void
private func updateCoverShape(_ controller: BrushController, _ cover: BrushCover) {
    let brushOption = cover.__brushOption!
    getCoverRenderer(cover).updateCoverShape(controller, cover, brushOption.range, brushOption)
}

// function updateZ(cover, brushOption): void
private func updateZ(_ cover: BrushCover, _ brushOption: BrushCoverConfig) {
    // let z = brushOption.z; z == null && (z = COVER_Z);
    let z = brushOption.z ?? COVER_Z
    _ = cover.traverse { el in
        if let d = el as? Displayable {
            d.z = z
            d.z2 = z   // Consider in given container.
        }
        return false
    }
}

// function updateCoverAfterCreation(controller, cover): void
private func updateCoverAfterCreation(_ controller: BrushController, _ cover: BrushCover) {
    getCoverRenderer(cover).updateCommon(controller, cover)
    updateCoverShape(controller, cover)
}

// function getCoverRenderer(cover): CoverRenderer
private func getCoverRenderer(_ cover: BrushCover) -> CoverRenderer {
    return coverRenderers[cover.__brushOption.brushType]!
}

// return target panel or `true` (means global panel)
// function getPanelByPoint(controller, e, localCursorPoint): BrushPanelConfigOrGlobal
private func getPanelByPoint(
    _ controller: BrushController,
    _ e: ElementEvent,
    _ localCursorPoint: Point
) -> BrushPanelConfigOrGlobal? {
    guard let panels = controller._panels else {
        return .global   // Global panel
    }
    var panel: BrushPanelConfig?
    let transform = controller._transform
    util.each(Array(panels.values)) { pn, _ in
        if pn.isTargetByCursor(e, localCursorPoint, transform) {
            panel = pn
        }
    }
    // upstream returns `undefined` when no panel matched.
    return panel.map { .panel($0) }
}

// Return a panel or true
// function getPanelByCover(controller, cover): BrushPanelConfigOrGlobal
private func getPanelByCover(_ controller: BrushController, _ cover: BrushCover) -> BrushPanelConfigOrGlobal? {
    guard let panels = controller._panels else {
        return .global   // Global panel
    }
    let panelId = cover.__brushOption.panelId
    // User may give cover without coord sys info,
    // which is then treated as global panel.
    if let panelId = panelId {
        return panels[panelId].map { .panel($0) }
    }
    return .global
}

// function clearCovers(controller): boolean
@discardableResult
private func clearCovers(_ controller: BrushController) -> Bool {
    let covers = controller._covers
    let originalLength = covers.count
    util.each(covers) { cover, _ in
        _ = controller.group.remove(cover)
    }
    controller._covers = []   // covers.length = 0;

    return originalLength != 0
}

// function trigger(controller, opt: {isEnd?, removeOnClick?}): void
private func triggerBrush(_ controller: BrushController, isEnd: Bool = false, removeOnClick: Bool = false) {
    let areas: [BrushControllerBrushArea] = util.map(controller._covers) { cover, _ in
        let brushOption = cover.__brushOption!
        // const range = clone(brushOption.range);   (arrays are value types -> already copies)
        return BrushControllerBrushArea(
            brushType: brushOption.brushType,
            panelId: brushOption.panelId,
            range: brushOption.range
        )
    }

    controller.trigger("brush", BrushControllerBrushEvent(
        areas: areas,
        isEnd: isEnd,
        removeOnClick: removeOnClick
    ))
}

// function shouldShowCover(controller): boolean
private func shouldShowCover(_ controller: BrushController) -> Bool {
    let track = controller._track

    if track.isEmpty {
        return false
    }

    let p2 = track[track.count - 1]
    let p1 = track[0]
    let dx = p2[0] - p1[0]
    let dy = p2[1] - p1[1]
    let dist = pow(dx * dx + dy * dy, 0.5)

    return dist > UNSELECT_THRESHOLD
}

// function getTrackEnds(track: Point[]): Point[]
private func getTrackEnds(_ track: [Point]) -> [Point] {
    var tail = track.count - 1
    if tail < 0 { tail = 0 }
    return [track[0], track[tail]]
}

// interface RectRangeConverter { toRectRange(range): BrushDimensionMinMax[]; fromRectRange(areaRange): BrushAreaRange; }
private struct RectRangeConverter {
    let toRectRange: (_ range: BrushAreaRange?) -> [BrushDimensionMinMax]
    let fromRectRange: (_ areaRange: [BrushDimensionMinMax]) -> BrushAreaRange
}

// function createBaseRectCover(rectRangeConverter, controller, brushOption, edgeNameSequences): BrushCover
private func createBaseRectCover(
    _ rectRangeConverter: RectRangeConverter,
    _ controller: BrushController,
    _ brushOption: BrushCoverConfig,
    _ edgeNameSequences: [DirectionNameSequence]
) -> BrushCover {
    let cover = BrushCover()

    // cover.add(new graphic.Rect({name: 'main', style: makeStyle(brushOption), silent: true,
    //     draggable: true, cursor: 'move', drift: curry(driftRect, ...), ondragend: curry(trigger, ...)}));
    let mainRect = Rect()
    mainRect.name = "main"
    mainRect.pathStyle = makeStyle(brushOption)   // upstream: `style: makeStyle(brushOption)`
    mainRect.silent = true
    mainRect.draggable = .true
    mainRect.cursor = "move"
    mainRect.driftHandler = { [weak controller, weak cover] dx, dy, _ in
        guard let controller = controller, let cover = cover else { return }
        driftRect(rectRangeConverter, controller, cover, ["n", "s", "w", "e"], dx, dy)
    }
    // ondragend: curry(trigger, controller, {isEnd: true})
    //   PORT-NOTE: `ElementEventHandlerProps` (`onXxx` props) are not modeled on ZRenderKit's Element
    //   (native event seam, CONVENTIONS §9). `Handler.dispatchToElement` triggers the event by name on
    //   the element, so the equivalent registration is `el.on("dragend", ...)`.
    _ = mainRect.on("dragend", { [weak controller] _, _ in
        guard let controller = controller else { return nil }
        triggerBrush(controller, isEnd: true)
        return nil
    })
    _ = cover.add(mainRect)

    util.each(edgeNameSequences) { nameSequence, _ in
        // cover.add(new graphic.Rect({name: nameSequence.join(''), style: {opacity: 0}, draggable: true,
        //     silent: true, invisible: true, drift: ..., ondragend: ...}));
        let el = Rect()
        el.name = nameSequence.joined()
        var st = PathStyleProps()
        st.opacity = 0
        el.pathStyle = st
        el.draggable = .true
        el.silent = true
        el.invisible = true
        el.driftHandler = { [weak controller, weak cover] dx, dy, _ in
            guard let controller = controller, let cover = cover else { return }
            driftRect(rectRangeConverter, controller, cover, nameSequence, dx, dy)
        }
        _ = el.on("dragend", { [weak controller] _, _ in
            guard let controller = controller else { return nil }
            triggerBrush(controller, isEnd: true)
            return nil
        })
        _ = cover.add(el)
    }

    return cover
}

// function updateBaseRect(controller, cover, localRange: BrushDimensionMinMax[], brushOption): void
private func updateBaseRect(
    _ controller: BrushController,
    _ cover: BrushCover,
    _ localRange: [BrushDimensionMinMax],
    _ brushOption: BrushCoverConfig
) {
    // const lineWidth = brushOption.brushStyle.lineWidth || 0;
    let lineWidth = brushCoerceDouble(brushOption.brushStyle?["lineWidth"]) ?? 0
    let handleSize = Swift.max(lineWidth, MIN_RESIZE_LINE_WIDTH)
    let x = localRange[0][0]
    let y = localRange[1][0]
    let xa = x - lineWidth / 2
    let ya = y - lineWidth / 2
    let x2 = localRange[0][1]
    let y2 = localRange[1][1]
    let x2a = x2 - handleSize + lineWidth / 2
    let y2a = y2 - handleSize + lineWidth / 2
    let width = x2 - x
    let height = y2 - y
    let widtha = width + lineWidth
    let heighta = height + lineWidth

    updateRectShape(controller, cover, "main", x, y, width, height)

    if brushOption.transformable == true {
        updateRectShape(controller, cover, "w", xa, ya, handleSize, heighta)
        updateRectShape(controller, cover, "e", x2a, ya, handleSize, heighta)
        updateRectShape(controller, cover, "n", xa, ya, widtha, handleSize)
        updateRectShape(controller, cover, "s", xa, y2a, widtha, handleSize)

        updateRectShape(controller, cover, "nw", xa, ya, handleSize, handleSize)
        updateRectShape(controller, cover, "ne", x2a, ya, handleSize, handleSize)
        updateRectShape(controller, cover, "sw", xa, y2a, handleSize, handleSize)
        updateRectShape(controller, cover, "se", x2a, y2a, handleSize, handleSize)
    }
}

// function updateCommon(controller, cover): void
private func updateCommonCover(_ controller: BrushController, _ cover: BrushCover) {
    let brushOption = cover.__brushOption!
    let transformable = brushOption.transformable == true

    // const mainEl = cover.childAt(0) as Displayable;
    // mainEl.useStyle(makeStyle(brushOption));
    // mainEl.attr({silent: !transformable, cursor: transformable ? 'move' : 'default'});
    if let mainEl = cover.childAt(0) as? Path {
        mainEl.pathStyle = makeStyle(brushOption)
        mainEl.dirtyStyle()
        mainEl.silent = !transformable
        mainEl.cursor = transformable ? "move" : "default"
    }

    util.each([["w"], ["e"], ["n"], ["s"], ["s", "e"], ["s", "w"], ["n", "e"], ["n", "w"]]) { nameSequence, _ in
        let el = cover.childOfName(nameSequence.joined()) as? Displayable
        let globalDir = nameSequence.count == 1
            ? getGlobalDirection1(controller, nameSequence[0])
            : getGlobalDirection2(controller, nameSequence)

        // el && el.attr({silent: !transformable, invisible: !transformable,
        //     cursor: transformable ? CURSOR_MAP[globalDir] + '-resize' : null});
        if let el = el {
            el.silent = !transformable
            el.invisible = !transformable
            el.cursor = transformable ? (CURSOR_MAP[globalDir] ?? "") + "-resize" : ""
        }
    }
}

// function updateRectShape(controller, cover, name, x, y, w, h): void
private func updateRectShape(
    _ controller: BrushController,
    _ cover: BrushCover,
    _ name: String,
    _ x: Double, _ y: Double, _ w: Double, _ h: Double
) {
    // const el = cover.childOfName(name) as graphic.Rect;
    // el && el.setShape(pointsToRect(clipByPanel(controller, cover, [[x, y], [x + w, y + h]])));
    guard let el = cover.childOfName(name) as? Rect else { return }
    _ = el.setShape(pointsToRect(
        clipByPanel(controller, cover, [[x, y], [x + w, y + h]])
    ))
}

// function makeStyle(brushOption) { return defaults({strokeNoScale: true}, brushOption.brushStyle); }
//   PORT-NOTE: `Path.style` is `pathStyle: PathStyleProps` in ZRenderKit (see Path's STYLE DECISION),
//   so the `[String: Any]` brushStyle bag (the output of `Model#getItemStyle()`) is decoded into it here.
private func makeStyle(_ brushOption: BrushCoverConfig) -> PathStyleProps {
    var style = PathStyleProps()
    style.strokeNoScale = true

    let bag = brushOption.brushStyle ?? [:]
    // The BrushStyleKey set: fill | stroke | lineWidth | opacity | shadowBlur | shadowOffsetX
    //   | shadowOffsetY | shadowColor.
    if let fill = bag["fill"] { style.fill = brushZRColor(fill) }
    if let stroke = bag["stroke"] { style.stroke = brushZRColor(stroke) }
    if let lw = brushCoerceDouble(bag["lineWidth"]) { style.lineWidth = lw }
    if let op = brushCoerceDouble(bag["opacity"]) { style.opacity = op }
    if let v = brushCoerceDouble(bag["shadowBlur"]) { style.shadowBlur = v }
    if let v = brushCoerceDouble(bag["shadowOffsetX"]) { style.shadowOffsetX = v }
    if let v = brushCoerceDouble(bag["shadowOffsetY"]) { style.shadowOffsetY = v }
    if let v = bag["shadowColor"] as? String { style.shadowColor = v }
    return style
}

// PORT-NOTE: `ZRColor` is declared in BOTH modules (EChartsKit re-declares its own); the Path style
//   field is ZRenderKit's, so qualify.
private func brushZRColor(_ v: Any?) -> ZRenderKit.ZRColor? {
    if let c = v as? ZRenderKit.ZRColor { return c }
    if let c = v as? EChartsKit.ZRColor, case let .color(str) = c { return ZRenderKit.ZRColor.string(str) }
    if let s = v as? String { return ZRenderKit.ZRColor.string(s) }
    return nil
}

// function formatRectRange(x, y, x2, y2): BrushDimensionMinMax[]
private func formatRectRange(_ x: Double, _ y: Double, _ x2: Double, _ y2: Double) -> [BrushDimensionMinMax] {
    let minV = [Swift.min(x, x2), Swift.min(y, y2)]
    let maxV = [Swift.max(x, x2), Swift.max(y, y2)]

    return [
        [minV[0], maxV[0]],   // x range
        [minV[1], maxV[1]]    // y range
    ]
}

// function getTransform(controller): matrix.MatrixArray  { return graphic.getTransform(controller.group); }
private func getControllerTransform(_ controller: BrushController) -> MatrixArray {
    return getTransform(controller.group)
}

// function getGlobalDirection1(controller, localDirName): keyof typeof CURSOR_MAP
private func getGlobalDirection1(_ controller: BrushController, _ localDirName: DirectionName) -> String {
    let map: [String: String] = ["w": "left", "e": "right", "n": "top", "s": "bottom"]
    let inverseMap: [String: String] = ["left": "w", "right": "e", "top": "n", "bottom": "s"]
    let dir = transformDirection(map[localDirName] ?? "left", getControllerTransform(controller))
    return inverseMap[dir] ?? "w"
}
// function getGlobalDirection2(controller, localDirNameSeq): keyof typeof CURSOR_MAP
private func getGlobalDirection2(_ controller: BrushController, _ localDirNameSeq: DirectionNameSequence) -> String {
    var globalDir = [
        getGlobalDirection1(controller, localDirNameSeq[0]),
        getGlobalDirection1(controller, localDirNameSeq[1])
    ]
    // (globalDir[0] === 'e' || globalDir[0] === 'w') && globalDir.reverse();
    if globalDir[0] == "e" || globalDir[0] == "w" {
        globalDir.reverse()
    }
    return globalDir.joined()
}

// function driftRect(rectRangeConverter, controller, cover, dirNameSequence, dx, dy): void
private func driftRect(
    _ rectRangeConverter: RectRangeConverter,
    _ controller: BrushController,
    _ cover: BrushCover,
    _ dirNameSequence: DirectionNameSequence,
    _ dx: Double,
    _ dy: Double
) {
    let brushOption = cover.__brushOption!
    var rectRange = rectRangeConverter.toRectRange(brushOption.range)
    let localDelta = toLocalDelta(controller, dx, dy)

    util.each(dirNameSequence) { dirName, _ in
        guard let ind = DIRECTION_MAP[dirName] else { return }
        rectRange[ind[0]][ind[1]] += localDelta[ind[0]]
    }

    brushOption.range = rectRangeConverter.fromRectRange(formatRectRange(
        rectRange[0][0], rectRange[1][0], rectRange[0][1], rectRange[1][1]
    ))

    updateCoverAfterCreation(controller, cover)
    triggerBrush(controller, isEnd: false)
}

// function driftPolygon(controller, cover, dx, dy): void
private func driftPolygon(
    _ controller: BrushController,
    _ cover: BrushCover,
    _ dx: Double,
    _ dy: Double
) {
    guard var range = brushDimensionMinMaxList(cover.__brushOption.range) else { return }
    let localDelta = toLocalDelta(controller, dx, dy)

    for i in range.indices {
        range[i][0] += localDelta[0]
        range[i][1] += localDelta[1]
    }
    cover.__brushOption.range = range

    updateCoverAfterCreation(controller, cover)
    triggerBrush(controller, isEnd: false)
}

// function toLocalDelta(controller, dx, dy): BrushDimensionMinMax
private func toLocalDelta(_ controller: BrushController, _ dx: Double, _ dy: Double) -> BrushDimensionMinMax {
    let thisGroup = controller.group
    let localD = thisGroup.transformCoordToLocal(dx, dy)
    let localZero = thisGroup.transformCoordToLocal(0, 0)

    return [localD[0] - localZero[0], localD[1] - localZero[1]]
}

// function clipByPanel(controller, cover, data: Point[]): Point[]
private func clipByPanel(_ controller: BrushController, _ cover: BrushCover, _ data: [Point]) -> [Point] {
    let panel = getPanelByCover(controller, cover)

    if case .panel(let p)? = panel {
        return p.clipPath(data, controller._transform)
    }
    return data   // clone(data) — Swift arrays are value types.
}

// function pointsToRect(points: Point[]): graphic.Rect['shape']
private func pointsToRect(_ points: [Point]) -> RectShape {
    let xmin = Swift.min(points[0][0], points[1][0])
    let ymin = Swift.min(points[0][1], points[1][1])
    let xmax = Swift.max(points[0][0], points[1][0])
    let ymax = Swift.max(points[0][1], points[1][1])

    var shape = RectShape()
    shape.x = xmin
    shape.y = ymin
    shape.width = xmax - xmin
    shape.height = ymax - ymin
    return shape
}

// function resetCursor(controller, e, localCursorPoint): void
private func resetCursor(_ controller: BrushController, _ e: ElementEvent, _ localCursorPoint: Point) {
    if
        // Check active
        controller._brushType == nil
        // resetCursor should be always called when mouse is in zr area,
        // but not called when mouse is out of zr area to avoid bad influence
        // if `mousemove`, `mouseup` are triggered from `document` event.
        || isOutsideZrArea(controller, e.offsetX, e.offsetY)
    {
        return
    }

    let zr = controller._zr
    let covers = controller._covers
    let currPanel = getPanelByPoint(controller, e, localCursorPoint)

    // Check whether in covers.
    if !controller._dragging {
        for i in 0..<covers.count {
            let brushOption = covers[i].__brushOption!
            var panelMatches = false
            switch currPanel {
            case .some(.global): panelMatches = true
            case .some(.panel(let p)): panelMatches = (brushOption.panelId == p.panelId)
            case .none: panelMatches = false
            }
            if panelMatches
                && coverRenderers[brushOption.brushType]!.contain(
                    covers[i], localCursorPoint[0], localCursorPoint[1]
                )
            {
                // Use cursor style set on cover.
                return
            }
        }
    }

    // currPanel && zr.setCursorStyle('crosshair');
    if currPanel != nil {
        zr.setCursorStyle("crosshair")
    }
}

// function preventDefault(e: ElementEvent): void
//   PORT-NOTE: `e.event.preventDefault()` is the DOM raw-event seam (CONVENTIONS §9); there is no
//   browser default action to suppress on the native host, so this is a no-op.
private func preventDefault(_ e: ElementEvent) {
    _ = e
}

// function mainShapeContain(cover, x, y): boolean
private func mainShapeContain(_ cover: BrushCover, _ x: Double, _ y: Double) -> Bool {
    guard let main = cover.childOfName("main") as? Displayable else { return false }
    return main.contain(x, y)
}

// function updateCoverByMouse(controller, e, localCursorPoint, isEnd): {isEnd, removeOnClick?}
private func updateCoverByMouse(
    _ controller: BrushController,
    _ e: ElementEvent,
    _ localCursorPoint: Point,
    _ isEnd: Bool
) -> (isEnd: Bool, removeOnClick: Bool)? {
    var creatingCover = controller._creatingCover
    let panel = controller._creatingPanel
    guard let thisBrushOption = controller._brushOption else { return nil }
    var eventParams: (isEnd: Bool, removeOnClick: Bool)?

    controller._track.append(localCursorPoint)

    if shouldShowCover(controller) || creatingCover != nil {

        if let panel = panel, creatingCover == nil {
            // thisBrushOption.brushMode === 'single' && clearCovers(controller);
            if thisBrushOption.brushMode == "single" {
                clearCovers(controller)
            }
            // const brushOption = clone(thisBrushOption) as BrushCoverConfig;
            let brushOption = BrushCoverConfig(brushType: thisBrushOption.brushType ?? "")
            brushOption.brushMode = thisBrushOption.brushMode
            brushOption.brushStyle = thisBrushOption.brushStyle
            brushOption.transformable = thisBrushOption.transformable
            brushOption.removeOnClick = thisBrushOption.removeOnClick
            brushOption.z = thisBrushOption.z
            // brushOption.brushType = determineBrushType(brushOption.brushType, panel);
            brushOption.brushType = determineBrushType(thisBrushOption.brushType, panel)
            // brushOption.panelId = panel === BRUSH_PANEL_GLOBAL ? null : panel.panelId;
            if case .panel(let p) = panel { brushOption.panelId = p.panelId } else { brushOption.panelId = nil }

            let cover = createCover(controller, brushOption)
            controller._creatingCover = cover
            creatingCover = cover
            controller._covers.append(cover)
        }

        if let creatingCover = creatingCover {
            let coverRenderer = coverRenderers[
                determineBrushType(controller._brushType, panel)
            ]!
            let coverBrushOption = creatingCover.__brushOption!

            coverBrushOption.range = coverRenderer.getCreatingRange(
                clipByPanel(controller, creatingCover, controller._track)
            )

            if isEnd {
                endCreating(controller, creatingCover)
                coverRenderer.updateCommon(controller, creatingCover)
            }

            updateCoverShape(controller, creatingCover)

            eventParams = (isEnd: isEnd, removeOnClick: false)
        }
    }
    else if
        isEnd
        && thisBrushOption.brushMode == "single"
        && thisBrushOption.removeOnClick == true
    {
        // Help user to remove covers easily, only by a tiny drag, in 'single' mode.
        // But a single click do not clear covers, because user may have casual
        // clicks (for example, click on other component and do not expect covers
        // disappear).
        // Only some cover removed, trigger action, but not every click trigger action.
        if getPanelByPoint(controller, e, localCursorPoint) != nil && clearCovers(controller) {
            eventParams = (isEnd: isEnd, removeOnClick: true)
        }
    }

    return eventParams
}

// function determineBrushType(brushType: BrushTypeUncertain, panel: BrushPanelConfig): BrushType
private func determineBrushType(_ brushType: BrushTypeUncertain, _ panel: BrushPanelConfigOrGlobal?) -> BrushType {
    if brushType == "auto" {
        // if (__DEV__) { assert(panel && panel.defaultBrushType, 'MUST have defaultBrushType when brushType is "atuo"'); }
        if case .panel(let p)? = panel, let dbt = p.defaultBrushType {
            return dbt
        }
        return ""
    }
    return brushType ?? ""
}

// const pointerHandlers: Dictionary<(this: BrushController, e: ElementEvent) => void> = { ... }
//   (bound onto the zr in `_mountHandlers`.)

// mousedown
private func pointerHandlerMousedown(_ controller: BrushController, _ e: ElementEvent) {
    if controller._dragging {
        // In case some browser do not support globalOut,
        // and release mouse out side the browser.
        handleDragEnd(controller, e)
    }
    else if e.target == nil || e.target!.draggable == .false {

        preventDefault(e)

        let localCursorPoint = controller.group.transformCoordToLocal(e.offsetX, e.offsetY)

        controller._creatingCover = nil
        let panel = getPanelByPoint(controller, e, localCursorPoint)
        controller._creatingPanel = panel

        if panel != nil {
            controller._dragging = true
            controller._track = [localCursorPoint]
        }
    }
}

// mousemove
private func pointerHandlerMousemove(_ controller: BrushController, _ e: ElementEvent) {
    let x = e.offsetX
    let y = e.offsetY

    let localCursorPoint = controller.group.transformCoordToLocal(x, y)

    resetCursor(controller, e, localCursorPoint)

    if controller._dragging {
        preventDefault(e)
        let eventParams = updateCoverByMouse(controller, e, localCursorPoint, false)
        if let eventParams = eventParams {
            triggerBrush(controller, isEnd: eventParams.isEnd, removeOnClick: eventParams.removeOnClick)
        }
    }
}

// mouseup
private func pointerHandlerMouseup(_ controller: BrushController, _ e: ElementEvent) {
    handleDragEnd(controller, e)
}

// function handleDragEnd(controller, e)
private func handleDragEnd(_ controller: BrushController, _ e: ElementEvent) {
    if controller._dragging {
        preventDefault(e)

        let x = e.offsetX
        let y = e.offsetY

        let localCursorPoint = controller.group.transformCoordToLocal(x, y)
        let eventParams = updateCoverByMouse(controller, e, localCursorPoint, true)

        controller._dragging = false
        controller._track = []
        controller._creatingCover = nil

        // trigger event should be at final, after procedure will be nested.
        if let eventParams = eventParams {
            triggerBrush(controller, isEnd: eventParams.isEnd, removeOnClick: eventParams.removeOnClick)
        }
    }
}

// function isOutsideZrArea(controller, x, y): boolean
private func isOutsideZrArea(_ controller: BrushController, _ x: Double, _ y: Double) -> Bool {
    let zr = controller._zr
    return x < 0 || x > (zr.getWidth() ?? 0) || y < 0 || y > (zr.getHeight() ?? 0)
}


// interface CoverRenderer { createCover; getCreatingRange; updateCoverShape; updateCommon; contain; endCreating?; }
private struct CoverRenderer {
    let createCover: (_ controller: BrushController, _ brushOption: BrushCoverConfig) -> BrushCover
    let getCreatingRange: (_ localTrack: [Point]) -> BrushAreaRange
    let updateCoverShape: (
        _ controller: BrushController, _ cover: BrushCover, _ localRange: BrushAreaRange?,
        _ brushOption: BrushCoverConfig
    ) -> Void
    let updateCommon: (_ controller: BrushController, _ cover: BrushCover) -> Void
    let contain: (_ cover: BrushCover, _ x: Double, _ y: Double) -> Bool
    var endCreating: ((_ controller: BrushController, _ creatingCover: BrushCover) -> Void)?
}

/**
 * key: brushType
 */
// const coverRenderers: Record<BrushType, CoverRenderer> = { ... }
private let coverRenderers: [BrushType: CoverRenderer] = [

    // lineX: getLineRenderer(0),
    "lineX": getLineRenderer(0),

    // lineY: getLineRenderer(1),
    "lineY": getLineRenderer(1),

    "rect": CoverRenderer(
        createCover: { controller, brushOption in
            // function returnInput(range) { return range; }
            return createBaseRectCover(
                RectRangeConverter(
                    toRectRange: { range in brushDimensionMinMaxList(range) ?? [[0, 0], [0, 0]] },
                    fromRectRange: { areaRange in areaRange }
                ),
                controller,
                brushOption,
                [["w"], ["e"], ["n"], ["s"], ["s", "e"], ["s", "w"], ["n", "e"], ["n", "w"]]
            )
        },
        getCreatingRange: { localTrack in
            let ends = getTrackEnds(localTrack)
            return formatRectRange(ends[1][0], ends[1][1], ends[0][0], ends[0][1])
        },
        updateCoverShape: { controller, cover, localRange, brushOption in
            guard let range = brushDimensionMinMaxList(localRange) else { return }
            updateBaseRect(controller, cover, range, brushOption)
        },
        updateCommon: updateCommonCover,
        contain: mainShapeContain
    ),

    "polygon": CoverRenderer(
        createCover: { controller, brushOption in
            let cover = BrushCover()

            // Do not use graphic.Polygon because graphic.Polyline do not close the
            // border of the shape when drawing, which is a better experience for user.
            let polyline = Polyline()
            polyline.name = "main"
            polyline.pathStyle = makeStyle(brushOption)
            polyline.silent = true
            _ = cover.add(polyline)

            return cover
        },
        getCreatingRange: { localTrack in
            return localTrack
        },
        updateCoverShape: { controller, cover, localRange, _ in
            // (cover.childAt(0) as graphic.Polygon).setShape({points: clipByPanel(controller, cover, localRange)});
            guard let range = brushDimensionMinMaxList(localRange) else { return }
            let clipped = clipByPanel(controller, cover, range)
            if let poly = cover.childAt(0) as? Polygon {
                var shape = PolygonShape()
                shape.points = toVectorArrayList(clipped)
                _ = poly.setShape(shape)
            }
            else if let poly = cover.childAt(0) as? Polyline {
                // While still creating (before `endCreating`), the cover's main element is a Polyline.
                var shape = PolylineShape()
                shape.points = toVectorArrayList(clipped)
                _ = poly.setShape(shape)
            }
        },
        updateCommon: updateCommonCover,
        contain: mainShapeContain,
        endCreating: { controller, cover in
            // cover.remove(cover.childAt(0));
            if let first = cover.childAt(0) {
                _ = cover.remove(first)
            }
            // Use graphic.Polygon close the shape.
            let poly = Polygon()
            poly.name = "main"
            poly.draggable = .true
            poly.driftHandler = { [weak controller, weak cover] dx, dy, _ in
                guard let controller = controller, let cover = cover else { return }
                driftPolygon(controller, cover, dx, dy)
            }
            _ = poly.on("dragend", { [weak controller] _, _ in
                guard let controller = controller else { return nil }
                triggerBrush(controller, isEnd: true)
                return nil
            })
            _ = cover.add(poly)
        }
    )
]

// function getLineRenderer(xyIndex: 0 | 1)
private func getLineRenderer(_ xyIndex: Int) -> CoverRenderer {
    return CoverRenderer(
        createCover: { controller, brushOption in
            return createBaseRectCover(
                RectRangeConverter(
                    toRectRange: { range in
                        // const rectRange = [range, [0, 100]];  xyIndex && rectRange.reverse();
                        let r = brushDimensionMinMax(range) ?? [0, 0]
                        var rectRange: [BrushDimensionMinMax] = [r, [0, 100]]
                        if xyIndex != 0 { rectRange.reverse() }
                        return rectRange
                    },
                    fromRectRange: { rectRange in
                        // return rectRange[xyIndex];
                        return rectRange[xyIndex]
                    }
                ),
                controller,
                brushOption,
                ([[["w"], ["e"]], [["n"], ["s"]]] as [[DirectionNameSequence]])[xyIndex]
            )
        },
        getCreatingRange: { localTrack in
            let ends = getTrackEnds(localTrack)
            let minV = Swift.min(ends[0][xyIndex], ends[1][xyIndex])
            let maxV = Swift.max(ends[0][xyIndex], ends[1][xyIndex])

            return [minV, maxV] as BrushDimensionMinMax
        },
        updateCoverShape: { controller, cover, localRange, brushOption in
            var otherExtent: [Double]
            // If brushWidth not specified, fit the panel.
            let panel = getPanelByCover(controller, cover)
            if case .panel(let p)? = panel, let getOther = p.getLinearBrushOtherExtent {
                otherExtent = getOther(xyIndex)
            }
            else {
                let zr = controller._zr
                otherExtent = [0, [zr.getWidth() ?? 0, zr.getHeight() ?? 0][1 - xyIndex]]
            }
            guard let lr = brushDimensionMinMax(localRange) else { return }
            var rectRange: [BrushDimensionMinMax] = [lr, otherExtent]
            if xyIndex != 0 { rectRange.reverse() }

            updateBaseRect(controller, cover, rectRange, brushOption)
        },
        updateCommon: updateCommonCover,
        contain: mainShapeContain
    )
}

// export default BrushController;  -> `public final class BrushController` above.
