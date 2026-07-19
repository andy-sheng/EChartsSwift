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
// upstream `struct` is `Graph | Tree` — both expose `update()`. Swift models the union as a shared
// protocol both concrete structs conform to (see Tree/Graph `: LinkableStruct` conformances).
public protocol LinkableStruct: AnyObject {
    func update()
}

public struct LinkSeriesDataOpt {
    public var mainData: SeriesData?
    // For example, instance of Graph or Tree.
    public var `struct`: LinkableStruct?
    // Will designate: `mainData[structAttr] = struct;`
    public var structAttr: String
    public var datas: Datas?
    // { dataType: attr }
    // Will designate: `struct[datasAttr[dataType]] = list;`
    public var datasAttr: [SeriesDataType: String]?

    public init(
        mainData: SeriesData? = nil,
        struct structVal: LinkableStruct? = nil,
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
        //   upstream's outer-most-last wrap chain). All wrappable methods fire their stored injections —
        //   but only on the SeriesData instances registered here: `SeriesData.transferProperties` does
        //   NOT copy `_wrappedMethodInjections` onto derived/cloned lists (upstream does, implicitly, by
        //   copying the wrapped FUNCTION for each name in `__wrappedMethods`), so a clone-of-a-clone
        //   fires nothing. Safe today because `dataTaskReset` always clones from `getRawData()`, i.e. the
        //   registered original. // PORT-TODO: copy `_wrappedMethodInjections` in `transferProperties` if
        //   a derived list ever needs re-linking (note the ported injections capture the registered `data`
        //   explicitly where upstream re-binds `this`, so a naive copy would fire against the wrong list).
        //   The individual methods: `cloneShallow` is itself in TRANSFERABLE_METHODS, so it is registered
        //   TWICE and fires transferInjection (re-link the sibling datas) followed by cloneShallowInjection
        //   (clone the sibling datas) in registration order — together this is what re-links the shared
        //   tree/graph struct onto the clone produced by `dataTaskReset` (so a hierarchical series'
        //   `getData().tree` survives). The remaining transferable methods (`map`/`downSample`/
        //   `minmaxDownSample`/`lttbDownSample`) and the changable methods (`filterSelf`/`selectRange`)
        //   fire via `SeriesData.fireWrappedMethodInjections`: the transferable methods fire the transfer
        //   injection on the derived list they produce, while `filterSelf`/`selectRange` fire the change
        //   injection (`struct.update()`) after filtering `self` in place.
        // PORT NOTE(ARC): the receiver is captured WEAKLY below — the closure is stored back onto that
        //   same object's `_wrappedMethodInjections`, which in JS is collectable but under ARC would be a
        //   direct self-retain cycle. NOTE this alone does not fully break the cycle: the captured `opt`
        //   still reaches the data transitively via `opt.struct.data` (Tree/Graph hold `SeriesData`
        //   strongly, and `SeriesData.tree`/`.graph` hold the struct strongly in return).
        //   // PORT-TODO: make `Tree.data` / `Graph.data` / `Graph.edgeData` weak back-references so a
        //   linked tree/graph/sankey/treemap/sunburst SeriesData actually deallocates with its host model.
        for (_, data) in datas! {
            for methodName in mainData.TRANSFERABLE_METHODS {
                data.wrapMethod(methodName) { [weak data] args in
                    guard let data else { return nil }
                    return transferInjection(data, opt, (args.first as? SeriesData) ?? data)
                }
            }
        }

        // Beyond transfer, additional features should be added to `cloneShallow`.
        mainData.wrapMethod("cloneShallow") { [weak mainData] args in
            guard let mainData else { return nil }
            return cloneShallowInjection(opt, (args.first as? SeriesData) ?? mainData)
        }

        // Only mainData trigger change, because struct.update may trigger
        // another changable methods, which may bring about dead lock.
        for methodName in mainData.CHANGABLE_METHODS {
            mainData.wrapMethod(methodName) { [weak mainData] args in
                guard mainData != nil else { return nil }
                return changeInjection(opt, args.first ?? nil)
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
    // PORT-NOTE(linkSeriesData.ts:134): upstream attaches this to `data.getLinkedData`; Swift
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
    // PORT-NOTE(linkSeriesData.ts:144): upstream attaches this to `data.getLinkedDataAll`.
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
            // PORT NOTE: `structAttr` is a dynamic property name in upstream; Swift dispatches on the
            //   two known struct attrs ('tree' / 'graph') and casts the shared LinkableStruct.
            if opt.structAttr == "tree", let treeVal = structVal as? Tree {
                data.tree = treeVal
            }
            else if opt.structAttr == "graph", let graphVal = structVal as? Graph {
                data.graph = graphVal
            }
            // struct[opt.datasAttr[dataType]] = data;
            let attr = opt.datasAttr![dataType]
            if attr == "data" {
                if let treeVal = structVal as? Tree {
                    treeVal.data = data
                }
                else if let graphVal = structVal as? Graph {
                    graphVal.data = data
                }
            }
            else if attr == "edgeData", let graphVal = structVal as? Graph {
                graphVal.edgeData = data
            }
        }

        // Supplement method.
        // PORT-NOTE(linkSeriesData.ts:182-183): `data.getLinkedData` / `data.getLinkedDataAll`
        //   cannot be assigned as instance methods in Swift; use the static helpers above.
    }

}
