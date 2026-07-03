// Ported from echarts/src/data/helper/linkSeriesData.ts — keep in sync with upstream
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


/**
 * Link lists and struct (graph or tree)
 */

import Foundation
import ZRenderKit

// upstream imports:
//   import { curry, each, assert, extend, map, keys } from 'zrender/src/core/util';  -> ZRenderKit.util
//   import SeriesData from '../SeriesData';                                           -> data/SeriesData.swift
//   import { makeInner } from '../../util/model';                                     -> model.makeInner
//   import { SeriesDataType } from '../../util/types';                                -> util/types.swift

// That is: { dataType: data },
// like: { node: nodeList, edge: edgeList }.
// Should contain mainData.
// type Datas = { [key in SeriesDataType]?: SeriesData };
public typealias Datas = [SeriesDataType: SeriesData]
// type StructReferDataAttr = 'data' | 'edgeData';
// type StructAttr = 'tree' | 'graph';

// inner<{ datas: Datas; mainData: SeriesData; }, SeriesData>()
private final class LinkInner {
    var datas: Datas = [:]
    var mainData: SeriesData?
}
private let inner: (SeriesData) -> LinkInner = model.makeInner { LinkInner() }


// Caution:
// In most case, either seriesData or its shallow clones (see seriesData.cloneShallow)
// is active in echarts process. So considering heap memory consumption,
// we do not clone tree or graph, but share them among seriesData and its shallow clones.
// But in some rare case, we have to keep old seriesData (like do animation in chart). So
// please take care that both the old seriesData and the new seriesData share the same tree/graph.

// type LinkSeriesDataOpt = {
//     mainData: SeriesData;
//     struct: { update: () => void } & { [key in StructReferDataAttr]?: SeriesData };
//     structAttr: StructAttr;
//     datas?: Datas;
//     datasAttr?: { [key in SeriesDataType]?: StructReferDataAttr };
// };
public struct LinkSeriesDataOpt {
    public var mainData: SeriesData?
    // For example, instance of Graph or Tree.
    // PORT-TODO: upstream `struct` is `Graph | Tree` (both expose `update()`); only `Tree` is
    //   ported so far, so this is typed as `Tree?`. When `Graph` lands, widen to a shared protocol.
    public var `struct`: Tree?
    // Will designate: `mainData[structAttr] = struct;`
    public var structAttr: String
    public var datas: Datas?
    // { dataType: attr }
    // Will designate: `struct[datasAttr[dataType]] = list;`
    public var datasAttr: [SeriesDataType: String]?

    public init(
        mainData: SeriesData? = nil,
        struct structVal: Tree? = nil,
        structAttr: String,
        datas: Datas? = nil,
        datasAttr: [SeriesDataType: String]? = nil
    ) {
        self.mainData = mainData
        self.struct = structVal
        self.structAttr = structAttr
        self.datas = datas
        self.datasAttr = datasAttr
    }
}

// Free-function module `linkSeriesData.ts` -> caseless enum namespace `linkSeriesData`
// (CONVENTIONS §2). The default export is `linkSeriesData`; call site:
//   upstream `linkSeriesData({...})` -> `linkSeriesData.linkSeriesData(...)`.
public enum linkSeriesData {

    public static func linkSeriesData(_ opt: LinkSeriesDataOpt) {
        var opt = opt
        let mainData = opt.mainData!
        var datas = opt.datas

        if datas == nil {
            datas = [.main: mainData]
            opt.datasAttr = [.main: "data"]
        }
        opt.datas = nil
        opt.mainData = nil

        linkAll(mainData, datas!, &opt)

        // Porxy data original methods.
        // PORT NOTE(linkSeriesData.ts:78-92): upstream rebinds each transferable/changable method
        //   via `wrapMethod` + `curry` so the injection runs after the original method. Swift cannot
        //   replace a method by name, so `SeriesData.wrapMethod` STORES the injection keyed by method
        //   name and the ported wrappable methods fire it explicitly (in registration order, matching
        //   upstream's outer-most-last wrap chain). `cloneShallow` fires today (it is what re-links the
        //   shared tree/graph struct onto the clone produced by `dataTaskReset`, so a hierarchical
        //   series' `getData().tree` survives). The other transferable methods (downSample/map) and the
        //   changable methods (filterSelf/selectRange) record their injections here but do not yet fire
        //   them — PORT-TODO: invoke the stored injections from those methods when data-zoom/sampling
        //   lands (they are unreachable in the current static render path).
        for (_, data) in datas! {
            for methodName in mainData.TRANSFERABLE_METHODS {
                data.wrapMethod(methodName) { args in
                    transferInjection(data, opt, (args.first as? SeriesData) ?? data)
                }
            }
        }

        // Beyond transfer, additional features should be added to `cloneShallow`.
        mainData.wrapMethod("cloneShallow") { args in
            cloneShallowInjection(opt, (args.first as? SeriesData) ?? mainData)
        }

        // Only mainData trigger change, because struct.update may trigger
        // another changable methods, which may bring about dead lock.
        for methodName in mainData.CHANGABLE_METHODS {
            mainData.wrapMethod(methodName) { args in
                changeInjection(opt, args.first ?? nil)
            }
        }

        // Make sure datas contains mainData.
        util.assert(datas![mainData.dataType!] === mainData)
    }

    // function transferInjection(this: SeriesData, opt, res): unknown
    @discardableResult
    private static func transferInjection(_ thisData: SeriesData, _ opt: LinkSeriesDataOpt, _ res: SeriesData) -> SeriesData {
        if isMainData(thisData) {
            // Transfer datas to new main data.
            // const datas = extend({}, inner(this).datas);
            var datas = inner(thisData).datas
            datas[thisData.dataType!] = res
            var opt = opt
            linkAll(res, datas, &opt)
        }
        else {
            // Modify the reference in main data to point newData.
            var opt = opt
            linkSingle(res, thisData.dataType!, inner(thisData).mainData!, &opt)
        }
        return res
    }

    // function changeInjection(opt, res): unknown
    @discardableResult
    private static func changeInjection(_ opt: LinkSeriesDataOpt, _ res: Any?) -> Any? {
        // opt.struct && opt.struct.update();
        opt.struct?.update()
        return res
    }

    // function cloneShallowInjection(opt, res: SeriesData): SeriesData
    @discardableResult
    private static func cloneShallowInjection(_ opt: LinkSeriesDataOpt, _ res: SeriesData) -> SeriesData {
        // cloneShallow, which brings about some fragilities, may be inappropriate
        // to be exposed as an API. So for implementation simplicity we can make
        // the restriction that cloneShallow of not-mainData should not be invoked
        // outside, but only be invoked here.
        var opt = opt
        for (dataType, data) in inner(res).datas {
            if data !== res {
                linkSingle(data.cloneShallow(), dataType, res, &opt)
            }
        }
        return res
    }

    /**
     * Supplement method to List.
     *
     * @public
     * @param [dataType] If not specified, return mainData.
     */
    // PORT-TODO(linkSeriesData.ts:134): upstream attaches this to `data.getLinkedData`; Swift
    //   cannot add an instance method dynamically, so it is exposed as a static helper.
    static func getLinkedData(_ thisData: SeriesData, _ dataType: SeriesDataType? = nil) -> SeriesData? {
        let mainData = inner(thisData).mainData
        return (dataType == nil || mainData == nil)
            ? mainData
            : inner(mainData!).datas[dataType!]
    }

    /**
     * Get list of all linked data
     */
    // PORT-TODO(linkSeriesData.ts:144): upstream attaches this to `data.getLinkedDataAll`.
    static func getLinkedDataAll(_ thisData: SeriesData) -> [(data: SeriesData?, type: SeriesDataType?)] {
        let mainData = inner(thisData).mainData
        if mainData == nil {
            return [(data: nil, type: nil)]
        }
        // map(keys(inner(mainData).datas), type => ({ type, data: inner(mainData).datas[type] }))
        var result: [(data: SeriesData?, type: SeriesDataType?)] = []
        for (type, _) in inner(mainData!).datas {
            result.append((data: inner(mainData!).datas[type], type: type))
        }
        return result
    }

    private static func isMainData(_ data: SeriesData) -> Bool {
        return inner(data).mainData === data
    }

    private static func linkAll(_ mainData: SeriesData, _ datas: Datas, _ opt: inout LinkSeriesDataOpt) {
        inner(mainData).datas = [:]
        for (dataType, data) in datas {
            linkSingle(data, dataType, mainData, &opt)
        }
    }

    private static func linkSingle(_ data: SeriesData, _ dataType: SeriesDataType, _ mainData: SeriesData, _ opt: inout LinkSeriesDataOpt) {
        inner(mainData).datas[dataType] = data
        inner(data).mainData = mainData

        data.dataType = dataType

        if let structVal = opt.struct {
            // data[opt.structAttr] = struct;
            // PORT-TODO: `structAttr` is a dynamic property name; only 'tree' is wired here.
            if opt.structAttr == "tree" {
                data.tree = structVal
            }
            // struct[opt.datasAttr[dataType]] = data;
            let attr = opt.datasAttr![dataType]
            if attr == "data" {
                structVal.data = data
            }
            // PORT-TODO: 'edgeData' (Graph) attr unhandled until Graph is ported.
        }

        // Supplement method.
        // PORT-TODO(linkSeriesData.ts:182-183): `data.getLinkedData` / `data.getLinkedDataAll`
        //   cannot be assigned as instance methods in Swift; use the static helpers above.
    }

}
