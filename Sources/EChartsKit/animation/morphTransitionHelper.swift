// Ported from echarts/src/animation/morphTransitionHelper.ts — keep in sync with upstream
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

// upstream:
//   import { separateMorph, combineMorph, morphPath, DividePath, isCombineMorphing, SeparateConfig }
//       from 'zrender/src/tool/morphPath';                → ZRenderKit/Tool/morphPath.swift (same names)
//   import { Path } from '../util/graphic';               → ZRenderKit.Path
//   import SeriesModel from '../model/Series';            → model/Series.swift
//   import Element, { ElementAnimateConfig } from 'zrender/src/Element';   → ZRenderKit.Element
//   import { defaults, extend, isArray } from 'zrender/src/core/util';     → see notes inline
//   import { getAnimationConfig } from './basicTransition';                → sibling basicTransition.swift
//   import { ECElement, UniversalTransitionOption } from '../util/types';  → util/types.swift
//   import { clonePath } from 'zrender/src/tool/path';    → ZRenderKit.clonePath
//   import Model from '../model/Model';                   → model/Model.swift
import Foundation
import ZRenderKit

// type DescendentElements = Element[];
// type DescendentPaths = Path[];
typealias DescendentElements = [Element]
typealias DescendentPaths = [Path]

// upstream types the morph endpoints as the union `DescendentPaths | DescendentPaths[]`
//   and discriminates it at runtime with `isMultiple(elements)` (`isArray(elements[0])`). Swift has no
//   untagged union, so the union is modeled as this two-case enum and `isMultiple` collapses into the
//   `case .multiple` pattern match (the enum tag IS the runtime discriminator upstream computes).
//   `getPathList`'s two overloads (Element → DescendentPaths, [Element] → [DescendentPaths]) produce
//   the two cases respectively — see `getPathList` below.
enum MorphPathEndpoint {
    case single(DescendentPaths)      // upstream: DescendentPaths
    case multiple([DescendentPaths])  // upstream: DescendentPaths[]

    // upstream `!from.length || !to.length` (the union's `.length` reads either the path count or the
    //   group count — both are the same `length` in JS).
    var count: Int {
        switch self {
        case .single(let list): return list.count
        case .multiple(let lists): return lists.count
        }
    }
    var asSingle: DescendentPaths {
        switch self {
        case .single(let list): return list
        // upstream `to as DescendentPaths` — an unchecked cast that is only reached when the other
        //   endpoint is the multiple one, so this branch is unreachable in practice.
        case .multiple(let lists): return lists.first ?? []
        }
    }
}

// function isMultiple(elements): elements is DescendentElements[] { return isArray(elements[0]); }
//   → collapsed into the `MorphPathEndpoint` tag above (see note).

// interface MorphingBatch { one: Path; many: Path[]; }
struct MorphingBatch {
    var one: Path
    var many: [Path]
}

func prepareMorphBatches(_ one: DescendentPaths, _ many: [DescendentPaths]) -> [MorphingBatch] {
    var batches: [MorphingBatch] = []
    let batchCount = one.count
    for i in 0..<batchCount {
        batches.append(MorphingBatch(
            one: one[i],
            many: []
        ))
    }

    for i in 0..<many.count {
        let len = many[i].count
        var k = 0
        while k < len {
            batches[k % batchCount].many.append(many[i][k])
            k += 1
        }
    }

    var off = 0
    // If one has more paths than each one of many. average them.
    var i = batchCount - 1
    while i >= 0 {
        if batches[i].many.isEmpty {
            let moveFrom = batches[off].many
            if moveFrom.count <= 1 { // Not enough
                // Start from the first one.
                if off != 0 {
                    off = 0
                }
                else {
                    return batches
                }
            }
            // note (faithful quirk): upstream captures `moveFrom` BEFORE the `off = 0` reset
            //   above, so when the reset fires it still splits the array it captured (`batches[<old
            //   off>].many`) but writes the first half back into `batches[0]`. `moveFrom` is bound
            //   before the reset here too, reproducing that exactly.
            let len = moveFrom.count
            let mid = Int(ceil(Double(len) / 2))
            batches[i].many = Array(moveFrom[mid..<len])
            batches[off].many = Array(moveFrom[0..<mid])

            off += 1
        }
        i -= 1
    }

    return batches
}

// const pathDividers: Record<UniversalTransitionOption['divideShape'], DividePath> = {
//     clone(params) { ... },
//     // Use the default divider
//     split: null
// };
// `divideShape` is `'clone' | 'split'`; the record is a `[String: DividePath?]` here.
//   `split: null` means "use zrender's default divider" (morphPath falls back to `defaultDividePath`
//   when `dividePath` is nil), so the nil is meaningful and must be preserved.
let pathDividers: [String: DividePath?] = [
    "clone": { (params: DividePathParams) -> [Path] in
        var ret: [Path] = []
        // Fitting the alpha
        // upstream reads `params.path.style.opacity` which is `undefined` when unset;
        //   `1 - Math.pow(1 - undefined, ...)` is NaN there. Our `PathStyleProps.opacity` is
        //   `Double?`; defaulted to 1 (zrender's `DEFAULT_COMMON_STYLE.opacity`), which is what the
        //   painter would use anyway — no NaN opacity is ever written.
        let opacity = params.path.pathStyle?.opacity ?? 1
        let approxOpacity = 1 - pow(1 - opacity, 1 / params.count)
        var i = 0
        while Double(i) < params.count {
            let cloned = clonePath(params.path)
            _ = cloned.setStyle("opacity", approxOpacity)
            ret.append(cloned)
            i += 1
        }
        return ret
    },
    // Use the default divider
    "split": DividePath?.none
]

func applyMorphAnimation(
    _ from: MorphPathEndpoint,
    _ to: MorphPathEndpoint,
    _ divideShape: String?,                 // upstream: UniversalTransitionOption['divideShape']
    _ seriesModel: SeriesModel,
    _ dataIndex: Int,
    _ animateOtherProps: (
        _ fromIndividual: Path?,
        _ toIndividual: Path?,
        _ rawFrom: Path?,
        _ rawTo: Path?,
        _ animationCfg: ElementAnimateConfig
    ) -> Void
) {
    if from.count == 0 || to.count == 0 {
        return
    }

    let updateAnimationCfg = getAnimationConfig(.update, seriesModel, dataIndex, nil)
    guard let updateAnimationCfg = updateAnimationCfg, updateAnimationCfg.duration > 0 else {
        return
    }
    // const animationDelay = (seriesModel.getModel('universalTransition') as Model<UniversalTransitionOption>)
    //     .get('delay');
    // upstream `delay` is a user JS function `(index, count) => number`. The option bag here is
    //   `[String: Any]`, so a Swift closure of the same shape can be (and, in the demos, is) stored in it —
    //   read back with an `as?` cast. A delay expressed in JSON (impossible upstream too) is not supported.
    let animationDelay = seriesModel.getModel("universalTransition").get("delay")
        as? UniversalTransitionDelayFn

    // const animationCfg = extend({ setToFinal: true } as SeparateConfig, updateAnimationCfg);
    //   Need to setToFinal so the further calculation based on the style can be correct.
    //   Like emphasis color.
    var animationCfg = ElementAnimateConfig()
    animationCfg.setToFinal = true
    animationCfg.duration = updateAnimationCfg.duration
    animationCfg.delay = updateAnimationCfg.delay
    animationCfg.easing = updateAnimationCfg.easing

    var many: [DescendentPaths]?
    var one: DescendentPaths?
    // upstream additionally relies on the object IDENTITY `many === from` below to decide
    //   `fromIsMany`. The enum has no identity, so the same fact is recorded here as `manyIsFrom` —
    //   assigned in exactly the same two branches, in the same order (so a hypothetical
    //   multiple/multiple pair resolves to `false`, exactly as upstream's second assignment would).
    var manyIsFrom = false
    if case .multiple(let m) = from {    // manyToOne
        many = m
        one = to.asSingle
        manyIsFrom = true
    }
    if case .multiple(let m) = to {      // oneToMany
        many = m
        one = from.asSingle
        manyIsFrom = false
    }

    func morphOneBatch(
        _ batch: MorphingBatch,
        _ fromIsMany: Bool,
        _ animateIndex: Int,
        _ animateCount: Int,
        _ forceManyOne: Bool = false
    ) {
        let batchMany = batch.many
        let batchOne = batch.one
        if batchMany.count == 1 && !forceManyOne {
            // Is one to one
            let batchFrom: Path = fromIsMany ? batchMany[0] : batchOne
            let batchTo: Path = fromIsMany ? batchOne : batchMany[0]

            if isCombineMorphing(batchFrom) {
                // Keep doing combine animation.
                morphOneBatch(MorphingBatch(
                    one: batchTo,
                    many: [batchFrom]
                ), true, animateIndex, animateCount, true)
            }
            else {
                // const individualAnimationCfg = animationDelay ? defaults({
                //     delay: animationDelay(animateIndex, animateCount)
                // } as ElementAnimateConfig, animationCfg) : animationCfg;
                var individualAnimationCfg = animationCfg
                if let animationDelay = animationDelay {
                    individualAnimationCfg.delay = animationDelay(Double(animateIndex), Double(animateCount))
                }
                _ = morphPath(batchFrom, batchTo, individualAnimationCfg)
                animateOtherProps(batchFrom, batchTo, batchFrom, batchTo, individualAnimationCfg)
            }
        }
        else {
            // const separateAnimationCfg = defaults({
            //     dividePath: pathDividers[divideShape],
            //     individualDelay: animationDelay && function (idx, count, fromPath, toPath) {
            //         return animationDelay(idx + animateIndex, animateCount);
            //     }
            // } as SeparateConfig, animationCfg);
            //
            // `pathDividers[divideShape]` is `undefined` for an absent/unknown divideShape
            //   (and explicitly `null` for 'split'); both mean "let zrender use its default divider",
            //   which is what a nil `dividePath` does — so the double-optional collapses to one nil.
            let dividePath: DividePath? = divideShape.flatMap { pathDividers[$0] ?? nil }
            let individualDelay: IndividualDelay? = animationDelay.map { animationDelay in
                { (idx: Double, count: Double, fromPath: Path, toPath: Path) -> Double in
                    _ = count; _ = fromPath; _ = toPath
                    return animationDelay(idx + Double(animateIndex), Double(animateCount))
                }
            }

            // const { fromIndividuals, toIndividuals } = fromIsMany
            //     ? combineMorph(batchMany, batchOne, separateAnimationCfg)
            //     : separateMorph(batchOne, batchMany, separateAnimationCfg);
            //
            // zrender's `CombineConfig` / `SeparateConfig` are distinct Swift structs (they
            //   compose, rather than extend, `ElementAnimateConfig` as `base`), so the single upstream
            //   `separateAnimationCfg` object is built twice — same fields, same values.
            let result: MorphResult = fromIsMany
                ? combineMorph(batchMany, batchOne,
                               CombineConfig(base: animationCfg,
                                             dividePath: dividePath,
                                             individualDelay: individualDelay))
                : separateMorph(batchOne, batchMany,
                                SeparateConfig(base: animationCfg,
                                               dividePath: dividePath,
                                               individualDelay: individualDelay))
            let fromIndividuals = result.fromIndividuals
            let toIndividuals = result.toIndividuals

            let count = fromIndividuals.count
            for k in 0..<count {
                var individualAnimationCfg = animationCfg
                if let animationDelay = animationDelay {
                    individualAnimationCfg.delay = animationDelay(Double(k), Double(count))
                }
                // note (JS-OOB → Swift crash): `batchMany[k]` / `toIndividuals[k]` are read past
                //   the end upstream when the divider produced more individuals than the batch had
                //   members (JS yields `undefined`, and `updateMorphingPathProps` guards with
                //   `if (rawFrom || from)`). Indexed defensively here — out of range becomes `nil`,
                //   which is exactly the `undefined` the callback already handles.
                animateOtherProps(
                    fromIndividuals[k],
                    k < toIndividuals.count ? toIndividuals[k] : nil,
                    fromIsMany ? (k < batchMany.count ? batchMany[k] : nil) : batch.one,
                    fromIsMany ? batch.one : (k < batchMany.count ? batchMany[k] : nil),
                    individualAnimationCfg
                )
            }
        }
    }

    // const fromIsMany = many ? many === from
    //     // Is one to one. If the path number not match. also needs do merge and separate morphing.
    //     : from.length > to.length;
    let fromIsMany = many != nil
        ? manyIsFrom
        : from.count > to.count

    let morphBatches = many != nil
        ? prepareMorphBatches(one!, many!)
        : prepareMorphBatches(
            (fromIsMany ? to : from).asSingle,
            [(fromIsMany ? from : to).asSingle]
        )
    var animateCount = 0
    for i in 0..<morphBatches.count {
        animateCount += morphBatches[i].many.count
    }
    var animateIndex = 0
    for i in 0..<morphBatches.count {
        morphOneBatch(morphBatches[i], fromIsMany, animateIndex, animateCount)
        animateIndex += morphBatches[i].many.count
    }
}

// export function getPathList(elements: Element): DescendentPaths;
func getPathList(_ elements: Element?) -> DescendentPaths {
    // if (!elements) { return []; }
    guard let elements = elements else {
        return []
    }

    var pathList: DescendentPaths = []

    // elements.traverse(el => { ... })
    // `Element.traverse` (void cb) is a no-op on the base class; only `Displayable`
    //   overrides it (cb(self)), and `Group` declares an OVERLOAD taking a Bool-returning cb (which
    //   visits children only, exactly like upstream's `Group.traverse`). Dispatching on the static
    //   type would silently skip a Group's subtree, so the two are branched explicitly here.
    let visit: (Element) -> Void = { el in
        // if ((el instanceof Path) && !(el as ECElement).disableMorphing && !el.invisible && !el.ignore)
        if let path = el as? Path,
           !getMorphInner(el).disableMorphing,
           !path.invisible,
           !path.ignore {
            pathList.append(path)
        }
    }
    if let group = elements as? Group {
        _ = group.traverse({ el in visit(el); return false })
    }
    else {
        elements.traverse(visit)
    }
    return pathList
}

// export function getPathList(elements: Element[]): DescendentPaths[];
func getPathList(_ elements: [Element]) -> [DescendentPaths] {
    // if (isArray(elements)) { ... }
    var pathList: [DescendentPaths] = []
    for i in 0..<elements.count {
        pathList.append(getPathList(elements[i]))
    }
    return pathList
}

// ============================================================================
// note (`(el as ECElement).disableMorphing`): `ECElement` (util/types.swift) is an augmentation
// interface upstream — TS widens the plain zrender `Element` with echarts-internal props. Swift cannot
// add stored properties to a class from another module, so — exactly like `states.swift`'s
// `HighDownInner` — the flag lives in a `makeInner` side store keyed by element identity. A view sets
// it via `getMorphInner(el).disableMorphing = true` (upstream `(el as ECElement).disableMorphing = true`).
// ============================================================================
public final class MorphElementInner {
    public var disableMorphing: Bool = false
    public init() {}
}
public let getMorphInner: (Element) -> MorphElementInner = model.makeInner { MorphElementInner() }

// upstream: `UniversalTransitionOption['delay']` — `(index: number, count: number) => number`.
public typealias UniversalTransitionDelayFn = (Double, Double) -> Double
