// Ported from echarts/src/coord/geo/GeoSVGResource.ts — keep in sync with upstream
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

// upstream imports mapped:
//   import { parseSVG, makeViewBoxTransform, SVGNodeTagLower, SVGParserResultNamedItem }
//       from 'zrender/src/tool/parseSVG';   -> ZRenderKit (tool/parseSVG.swift).
//   import Group / Rect                      -> ZRenderKit graphics.
//   import { assert, createHashMap, each, HashMap } from 'zrender/src/core/util';
//                                            -> createHashMap / HashMap (modelUtil.swift shim); each -> loops.
//   import BoundingRect                      -> ZRenderKit.
//   import { GeoResource, GeoSVGGraphicRoot, GeoSVGSourceInput } from './geoTypes';  -> geoTypes.swift.
//   import { parseXML } from 'zrender/src/tool/parseXML';  -> parseXML (ZRenderKit, tool/parseSVG.swift).
//   import { GeoSVGRegion } from './Region';  -> Region.swift.
//   import Element                            -> ZRenderKit.

// upstream: interface GeoSVGGraphicRecord { root; boundingRect; named; }
//   Modeled as a `final class` (reference) so the pooled record is shared by identity (the freed/used
//   graphic pools hold the same instance), matching the upstream object.
public final class GeoSVGGraphicRecord {
    public var root: Group
    public var boundingRect: BoundingRect
    public var named: [SVGParserResultNamedItem]
    init(root: Group, boundingRect: BoundingRect, named: [SVGParserResultNamedItem]) {
        self.root = root
        self.boundingRect = boundingRect
        self.named = named
    }
}

// upstream: `(root as GeoSVGGraphicRoot).isGeoSVGGraphicRoot = true`. Group is `open`, so mark the extra
//   wrapper root via a subclass that conforms to `GeoSVGGraphicRoot` (geoTypes.swift). `GeoSVGRegion`'s
//   `calcCenter` walks up the parent chain until it hits this node.
public final class GeoSVGGraphicRootGroup: Group, GeoSVGGraphicRoot {
    public var isGeoSVGGraphicRoot: Bool = true
}

// "region available" means that: enable users to set attribute `name="xxx"` on those tags to make it be a
// region. (upstream uses a HashMap<number, SVGNodeTagLower>; a Set of tag names is the same lookup.)
private let REGION_AVAILABLE_SVG_TAG_MAP: Set<SVGNodeTagLower> = [
    "rect", "circle", "line", "ellipse", "polygon", "polyline", "path",
    // <text> <tspan> are also enabled because some SVG might paint text itself.
    "text", "tspan",
    // <g> is also enabled so multiple tags can share one name with a single label at the <g> center.
    "g"
]

// export class GeoSVGResource implements GeoResource
public final class GeoSVGResource: GeoResource {

    // readonly type = 'geoSVG';
    public let type: String = "geoSVG"
    private let _mapName: String
    private let _parsedXML: ZRXMLNode?

    private var _firstGraphic: GeoSVGGraphicRecord?
    private var _boundingRect: BoundingRect?
    private var _regions: [GeoSVGRegion] = []
    // Key: region.name
    private var _regionsMap: HashMap<GeoSVGRegion> = createHashMap()

    // All used graphics. key: hostKey, value: root
    private var _usedGraphicMap: HashMap<GeoSVGGraphicRecord> = createHashMap()
    // All unused graphics.
    private var _freedGraphics: [GeoSVGGraphicRecord] = []

    // constructor(mapName, svg: GeoSVGSourceInput)
    public init(_ mapName: String, _ svg: GeoSVGSourceInput) {
        self._mapName = mapName
        // Only perform parse to XML object here (might be time consuming for large SVG). Converting XML
        //   to zrender elements is done once per geo instance (see `_buildGraphic`).
        self._parsedXML = parseXML(svg)
    }

    // load(/* nameMap */) — build the first graphic to get the boundingRect for the geo coord system.
    public func load(_ nameMap: NameMap?, _ nameProperty: String?) -> GeoResourceLoadResult {
        var firstGraphic = self._firstGraphic

        if firstGraphic == nil {
            firstGraphic = self._buildGraphic(self._parsedXML)
            self._firstGraphic = firstGraphic

            self._freedGraphics.append(firstGraphic!)

            self._boundingRect = firstGraphic!.boundingRect.clone()

            // PENDING: `nameMap` will not be supported until some real requirement come.
            let created = createRegions(firstGraphic!.named)
            self._regions = created.regions
            self._regionsMap = created.regionsMap
        }

        return GeoResourceLoadResult(
            boundingRect: self._boundingRect!,
            regions: self._regions.map { $0 as Region },
            regionsMap: geoSVGRegionsMapToRegionsMap(self._regionsMap)
        )
    }

    private func _buildGraphic(_ svgXML: ZRXMLNode?) -> GeoSVGGraphicRecord {
        // try {
        //     result = svgXML && parseSVG(svgXML, { ignoreViewBox: true, ignoreRootClip: true }) || {};
        //     rootFromParse = result.root;
        //     assert(rootFromParse != null);
        // } catch (e) { throw new Error('Invalid svg format\n' + e.message); }
        // `parseXML` (in init) returns nil for a malformed SVG, so a nil `svgXML` here IS upstream's
        //   `{}` / parse-failure branch: assert the root is present, matching upstream's thrown error.
        let parsed: SVGParserResult? = svgXML.map {
            parseSVG($0, SVGParserOption(ignoreViewBox: true, ignoreRootClip: true))
        }
        util.assert(parsed?.root != nil, "Invalid svg format")
        let result = parsed!
        let rootFromParse = result.root

        // Note: we keep the covenant that the root has no transform. So always add an extra root.
        let root = GeoSVGGraphicRootGroup()
        _ = root.add(rootFromParse)
        // (root as GeoSVGGraphicRoot).isGeoSVGGraphicRoot = true  — set by the subclass default.

        // [THE_RULE_OF_VIEWPORT_AND_VIEWBOX] — see the long upstream comment. Determine boundingRect from
        //   svgWidth/svgHeight, else viewBox, else the calculated content bounding rect.
        let svgWidth = result.width
        let svgHeight = result.height
        let viewBoxRect = result.viewBoxRect

        var boundingRect = self._boundingRect
        if boundingRect == nil {
            var bRectX: Double?
            var bRectY: Double?
            var bRectWidth: Double = 0
            var bRectHeight: Double = 0

            if let svgWidth = svgWidth {
                bRectX = 0
                bRectWidth = svgWidth
            }
            else if let viewBoxRect = viewBoxRect {
                bRectX = viewBoxRect.x
                bRectWidth = viewBoxRect.width
            }

            if let svgHeight = svgHeight {
                bRectY = 0
                bRectHeight = svgHeight
            }
            else if let viewBoxRect = viewBoxRect {
                bRectY = viewBoxRect.y
                bRectHeight = viewBoxRect.height
            }

            // If both viewBox and svgWidth/svgHeight not specified, use the content bounding rect.
            if bRectX == nil || bRectY == nil {
                let calculatedBoundingRect = rootFromParse.getBoundingRect() ?? BoundingRect(0, 0, 0, 0)
                if bRectX == nil {
                    bRectX = calculatedBoundingRect.x
                    bRectWidth = calculatedBoundingRect.width
                }
                if bRectY == nil {
                    bRectY = calculatedBoundingRect.y
                    bRectHeight = calculatedBoundingRect.height
                }
            }

            boundingRect = BoundingRect(bRectX!, bRectY!, bRectWidth, bRectHeight)
            self._boundingRect = boundingRect
        }

        if let viewBoxRect = viewBoxRect {
            let viewBoxTransform = makeViewBoxTransform(viewBoxRect, boundingRect!)
            // Only support `preserveAspectRatio 'xMidYMid'`.
            rootFromParse.scaleX = viewBoxTransform.scale
            rootFromParse.scaleY = viewBoxTransform.scale
            rootFromParse.x = viewBoxTransform.x
            rootFromParse.y = viewBoxTransform.y
        }

        // SVG needs to clip based on `viewBox`. And some SVG files really rely on this feature.
        var clipShape = RectShape()
        clipShape.x = boundingRect!.x
        clipShape.y = boundingRect!.y
        clipShape.width = boundingRect!.width
        clipShape.height = boundingRect!.height
        root.setClipPath(Rect(["shape": clipShape as PathShape]))

        var named: [SVGParserResultNamedItem] = []
        for namedItem in result.named {
            if REGION_AVAILABLE_SVG_TAG_MAP.contains(namedItem.svgNodeTagLower) {
                named.append(namedItem)
                setSilent(namedItem.el)
            }
        }

        return GeoSVGGraphicRecord(root: root, boundingRect: boundingRect!, named: named)
    }

    // useGraphic(hostKey) — hand a pooled graphic to a `view`, keyed by its uid.
    public func useGraphic(_ hostKey: String) -> GeoSVGGraphicRecord {
        let usedRootMap = self._usedGraphicMap

        if let svgGraphic = usedRootMap.get(hostKey) {
            return svgGraphic
        }

        // use the first boundingRect to avoid duplicated boundingRect calculation.
        let svgGraphic = self._freedGraphics.popLast() ?? self._buildGraphic(self._parsedXML)

        usedRootMap.set(hostKey, svgGraphic)

        // PENDING: `nameMap` will not be supported until some real requirement come.
        return svgGraphic
    }

    // freeGraphic(hostKey) — return a graphic to the pool.
    public func freeGraphic(_ hostKey: String) {
        let usedRootMap = self._usedGraphicMap
        if let svgGraphic = usedRootMap.get(hostKey) {
            usedRootMap.removeKey(hostKey)
            self._freedGraphics.append(svgGraphic)
        }
    }
}

// upstream: function setSilent(el) — only named elements are interactive.
private func setSilent(_ el: Element) {
    el.silent = false
    // text|tspan will be converted to group.
    if el.isGroup, let g = el as? Group {
        g.traverse { child in
            child.silent = false
        }
    }
}

// upstream: function createRegions(named): { regions, regionsMap }
private func createRegions(
    _ named: [SVGParserResultNamedItem]
) -> (regions: [GeoSVGRegion], regionsMap: HashMap<GeoSVGRegion>) {
    var regions: [GeoSVGRegion] = []
    let regionsMap: HashMap<GeoSVGRegion> = createHashMap()

    // Create regions only for the first graphic.
    for namedItem in named {
        // If there is a <g name="xxx">, the center should be the center of the g bounding rect.
        if namedItem.namedFrom != nil {
            continue
        }
        let region = GeoSVGRegion(namedItem.name, namedItem.el)
        regions.append(region)
        // If multiple tags named with the same name, only one will be found by `_regionsMap`.
        regionsMap.set(namedItem.name, region)
    }

    return (regions, regionsMap)
}

// Bridge `HashMap<GeoSVGRegion>` -> `HashMap<Region>` (the load-result type). The shim `HashMap` is not
//   covariant, so copy entries preserving insertion order.
private func geoSVGRegionsMapToRegionsMap(_ src: HashMap<GeoSVGRegion>) -> HashMap<Region> {
    let out: HashMap<Region> = createHashMap()
    src.each { region, key in
        out.set(key, region)
    }
    return out
}
