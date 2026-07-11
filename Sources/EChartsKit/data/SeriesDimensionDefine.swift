// Ported from echarts/src/data/SeriesDimensionDefine.ts — keep in sync with upstream

// import * as zrUtil from 'zrender/src/core/util';
// import OrdinalMeta from './OrdinalMeta';
// import { DataVisualDimensions, DimensionType } from '../util/types';

public final class SeriesDimensionDefine {

    /**
     * Dimension type. The enumerable values are the key of
     * Optional.
     */
    public var type: DimensionType?

    /**
     * Dimension name.
     * Mandatory.
     */
    public var name: String = ""

    /**
     * The origin name in dimsDef, see source helper.
     * If displayName given, the tooltip will displayed vertically.
     * Optional.
     */
    public var displayName: String?

    // FIXME: check whether it is still used.
    // See Series.ts#formatArrayValue
    public var tooltip: Bool?

    /**
     * This dimension maps to the the dimension in dataStore by `storeDimIndex`.
     * Notice the facts:
     * 1. When there are too many dimensions in data store, seriesData only save the
     * used store dimensions.
     * 2. We use dimensionIndex but not name to reference store dimension
     * because the dataset dimension definition might has no name specified by users,
     * or names in series dimension definition might be different from dataset.
     */
    public var storeDimIndex: Double?

    /**
     * Which coordSys dimension this dimension mapped to.
     * A `coordDim` can be a "coordSysDim" that the coordSys required
     * (for example, an item in `coordSysDims` of `model/referHelper#CoordSysInfo`),
     * or an generated "extra coord name" if does not mapped to any "coordSysDim"
     * (That is determined by whether `isExtraCoord` is `true`).
     * Mandatory.
     */
    public var coordDim: String?

    /**
     * The index of this dimension in `series.encode[coordDim]`.
     * Mandatory.
     *
     * For example,
     *  Suppose
     *      - encode option:
     *          ```js
     *          encode: {
     *              x: [1, 3, 5],
     *              y: [0, 2],
     *          }
     *          ```
     *      - This `seriesDimensionDefine` corresponds to series dimension index `3`,
     *      - `coordDim` is `x`
     *  Then
     *      coordDimIndex should be `1`, where `encode[coordDim][coordDimIndex] === 3`
     */
    public var coordDimIndex: Double?

    /**
     * The term "other" means "other than coord".
     * The format of `otherDims` is:
     * ```js
     * {
     *     tooltip?: number
     *     label?: number
     *     itemName?: number
     *     seriesName?: number
     * }
     * ```
     *
     * A `series.encode` can specified these fields:
     * ```js
     * encode: {
     *     // "3, 1, 5" is the index of data dimension.
     *     tooltip: [3, 1, 5],
     *     label: [0, 3],
     *     ...
     * }
     * ```
     * `otherDims` is the parse result of the `series.encode` above, like:
     * ```js
     * // Suppose the index of this data dimension is `3`.
     * this.otherDims = {
     *     // `3` is at the index `0` of the `encode.tooltip`
     *     tooltip: 0,
     *     // `3` is at the index `1` of the `encode.label`
     *     label: 1
     * };
     * ```
     *
     * This prop should never be `null`/`undefined` after initialized.
     */
    public var otherDims: DataVisualDimensions? = DataVisualDimensions()

    /**
     * Be `true` if this dimension is not mapped to any "coordSysDim" that the
     * "coordSys" required.
     * Mandatory.
     */
    public var isExtraCoord: Bool?

    /**
     * If this dimension if for calculated value like stacking
     */
    public var isCalculationCoord: Bool?

    public var defaultTooltip: Bool?

    public var ordinalMeta: OrdinalMeta?

    /**
     * Whether to create inverted indices.
     */
    public var createInvertedIndices: Bool?

    /**
     * @param opt All of the fields will be shallow copied.
     */
    // PORT-NOTE: upstream `opt?: object | SeriesDimensionDefine` + `zrUtil.extend(this, opt)`.
    // Swift has typed properties, so we shallow-copy each known field from another
    // SeriesDimensionDefine rather than a generic object extend.
    public init(_ opt: SeriesDimensionDefine? = nil) {
        if let opt = opt {
            extendSeriesDimensionDefine(self, opt)
        }
    }
}

// PORT-NOTE: replicate `zrUtil.extend(this, opt)` for the typed `SeriesDimensionDefine`
// shape. Mirrors a shallow field-by-field copy of all defined properties.
private func extendSeriesDimensionDefine(_ target: SeriesDimensionDefine, _ source: SeriesDimensionDefine) {
    target.type = source.type
    target.name = source.name
    target.displayName = source.displayName
    target.tooltip = source.tooltip
    target.storeDimIndex = source.storeDimIndex
    target.coordDim = source.coordDim
    target.coordDimIndex = source.coordDimIndex
    target.otherDims = source.otherDims
    target.isExtraCoord = source.isExtraCoord
    target.isCalculationCoord = source.isCalculationCoord
    target.defaultTooltip = source.defaultTooltip
    target.ordinalMeta = source.ordinalMeta
    target.createInvertedIndices = source.createInvertedIndices
}
