// Ported from echarts/src/component/helper/brushHelper.ts — keep in sync with upstream
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

// import BoundingRect, { RectLike } from 'zrender/src/core/BoundingRect';  -> ZRenderKit BoundingRect / RectLike
// import {onIrrelevantElement} from './cursorHelper';                      -> `onIrrelevantElement` (cursorHelper.swift)
// import * as graphicUtil from '../../util/graphic';                       -> `clipPointsByRect` (util/graphic.swift)
// import ExtensionAPI from '../../core/ExtensionAPI';                      -> ExtensionAPI
// import { ElementEvent } from 'zrender/src/Element';                      -> ZRenderKit ElementEvent
// import ComponentModel from '../../model/Component';                      -> ComponentModel

// export function makeRectPanelClipPath(rect: RectLike)
//   Returns the panel's `clipPath(localPoints, transform)` — clamps a cover's local points into the
//   panel rect (so a drag beyond a grid/geo panel does not paint outside it).
public func makeRectPanelClipPath(_ rectIn: RectLike) -> (_ localPoints: [[Double]], _ transform: MatrixArray?) -> [[Double]] {
    let rect = normalizeRect(rectIn)
    return { localPoints, _ in
        return clipPointsByRect(localPoints, rect)
    }
}

// export function makeLinearBrushOtherExtent(rect: RectLike, specifiedXYIndex?: 0 | 1)
//   Returns the panel's `getLinearBrushOtherExtent(xyIndex)` — the OTHER dimension's [min, max] that a
//   lineX/lineY cover stretches across (the panel's full height / width).
public func makeLinearBrushOtherExtent(
    _ rectIn: RectLike,
    _ specifiedXYIndex: Int? = nil
) -> (_ xyIndex: Int) -> [Double] {
    let rect = normalizeRect(rectIn)
    return { xyIndex in
        // const idx = specifiedXYIndex != null ? specifiedXYIndex : xyIndex;
        let idx = specifiedXYIndex != nil ? specifiedXYIndex! : xyIndex
        // const brushWidth = idx ? rect.width : rect.height;
        let brushWidth = idx != 0 ? rect.width : rect.height
        // const base = idx ? rect.x : rect.y;
        let base = idx != 0 ? rect.x : rect.y
        // return [base, base + (brushWidth || 0)];
        return [base, base + (brushWidth.isNaN ? 0 : brushWidth)]
    }
}

// export function makeRectIsTargetByCursor(rect: RectLike, api: ExtensionAPI, targetModel: ComponentModel)
//   Returns the panel's `isTargetByCursor(e, localCursorPoint, transform)` — whether a pointer press
//   inside this panel should start a brush (and is not on an unrelated element on top of it).
public func makeRectIsTargetByCursor(
    _ rect: RectLike,
    _ api: ExtensionAPI,
    _ targetModel: ComponentModel
) -> (_ e: ElementEvent, _ localCursorPoint: [Double], _ transform: MatrixArray?) -> Bool {
    let boundingRect = normalizeRect(rect)
    return { e, localCursorPoint, _ in
        return boundingRect.contain(localCursorPoint[0], localCursorPoint[1])
            && !onIrrelevantElement(e, api, targetModel)
    }
}

// Consider width/height is negative.
// function normalizeRect(rect: RectLike): BoundingRect
private func normalizeRect(_ rect: RectLike) -> BoundingRect {
    return BoundingRect.create(rect)
}
