// Ported from echarts/src/visual/LegendVisualProvider.ts — keep in sync with upstream
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

// The bridge the legend uses to read DATA-driven legend items (pie/radar/funnel/… whose legend lists the
// data item names, not the series names). Extends the minimal `getAllNames` surface (declared in
// LegendModel) with the accessors LegendView's data-legend branch needs.
public protocol LegendVisualProviderLike {
    func getAllNames() -> [String]
    func containName(_ name: String) -> Bool
    func indexOfName(_ name: String) -> Int
    func getItemVisual(_ dataIndex: Int, _ key: String) -> Any?
}

/// LegendVisualProvider is a bridge that picks the encoded color/icon from a series' data and provides
/// it to the legend component.
public final class LegendVisualProvider: LegendVisualProviderLike {

    private let _getDataWithEncodedVisual: () -> SeriesData
    private let _getRawData: () -> SeriesData

    public init(
        // Function to get data after filtered. It stores all the encoding info.
        _ getDataWithEncodedVisual: @escaping () -> SeriesData,
        // Function to get raw data before filtered.
        _ getRawData: @escaping () -> SeriesData
    ) {
        self._getDataWithEncodedVisual = getDataWithEncodedVisual
        self._getRawData = getRawData
    }

    public func getAllNames() -> [String] {
        // We find the name from the raw data. In case it's filtered by the legend component.
        let rawData = self._getRawData()
        var names: [String] = []
        for i in 0..<rawData.count() { names.append(rawData.getName(i)) }
        return names
    }

    public func containName(_ name: String) -> Bool {
        let rawData = self._getRawData()
        return rawData.indexOfName(name) >= 0
    }

    public func indexOfName(_ name: String) -> Int {
        // Only get data when necessary (data may not be prepared at construction time).
        let dataWithEncodedVisual = self._getDataWithEncodedVisual()
        return dataWithEncodedVisual.indexOfName(name)
    }

    public func getItemVisual(_ dataIndex: Int, _ key: String) -> Any? {
        let dataWithEncodedVisual = self._getDataWithEncodedVisual()
        return dataWithEncodedVisual.getItemVisual(dataIndex, key)
    }
}
