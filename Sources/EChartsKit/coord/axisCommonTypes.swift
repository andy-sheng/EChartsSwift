// Ported from echarts/src/coord/axisCommonTypes.ts — keep in sync with upstream
//
// PORT-NOTE: only `AxisScaleType` is ported here (it is needed by scale/Scale.swift). The rest of
//   this module (AxisBaseOption and the axis option interfaces) is modeled as dynamic option bags in
//   the coordinate-system layer (e.g. `AxisBaseOption` = `[String: Any]` in axisModelCreator.swift).

import Foundation

// upstream: export type AxisScaleType = 'value' | 'category' | 'time' | 'log' | 'ordinal';
//   No string unions in Swift → a `String` alias (faithful enough for the scale layer; a tighter
//   enum can replace it when the coord/axis option layer lands).
public typealias AxisScaleType = String
