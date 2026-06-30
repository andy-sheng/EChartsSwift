// Ported from echarts/src/coord/axisCommonTypes.ts — keep in sync with upstream
//
// PORT-TODO: only `AxisScaleType` is ported here (it is needed by scale/Scale.swift). The rest of
//   this module (AxisBaseOption and the axis option interfaces) is translated in the
//   coordinate-system phase. Kept at its upstream path so that phase fills the file in.

import Foundation

// upstream: export type AxisScaleType = 'value' | 'category' | 'time' | 'log' | 'ordinal';
//   No string unions in Swift → a `String` alias (faithful enough for the scale layer; a tighter
//   enum can replace it when the coord/axis option layer lands).
public typealias AxisScaleType = String
