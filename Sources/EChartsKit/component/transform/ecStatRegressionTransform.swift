// ecStatRegressionTransform — faithful Swift port of echarts-stat (ecomfe/echarts-stat):
//   src/regression.js + src/util/dataProcess.js (dataPreprocess) + src/transform/regression.js.
//
// echarts-stat is a SEPARATE plugin (not part of the echarts source tree the rest of this repo ports),
// but several official examples (`scatter-linear-regression`, `-exponential-`, `-logarithmic-`,
// `-polynomial-`) declare `dataset[].transform: { type: 'ecStat:regression', config }`. Without a Swift
// registration `applyDataTransform` throws `Can not find transform on type "ecStat:regression"` and the
// whole chart fails to build. This registers a `ecStat:regression` external transform (via
// `transformInstall`) so those demos render natively; it mirrors the plugin line-for-line, including the
// `Math.round(x*100)/100` expression rounding and the `formulaOn:'end'` default (expression on the last
// fitted point's dim 2).
import Foundation

// number | numeric-string -> Double, else nil (ecStat/dataProcess `isNumber` + coercion).
private func ecStatNum(_ v: Any?) -> Double? {
    switch v {
    case let d as Double: return d
    case let i as Int: return Double(i)
    case let n as NSNumber: return n.doubleValue
    case let s as String: return Double(s)
    default: return nil
    }
}

// `Math.round(x * 10^p) / 10^p`.
private func ecStatRound(_ x: Double, _ p: Int) -> Double {
    let f = pow(10.0, Double(p))
    return (x * f).rounded() / f
}

private struct EcStatRegResult { var points: [[Any]]; var expression: String }

// upstream src/regression.js `regreMethods`. `predata` rows carry their original values; only the
// x/y dims are read as numbers and the y dim is overwritten with the fitted value.
private func ecStatRegress(_ method: String, _ predata: [[Any]], _ dims: [Int], _ order: Int) -> EcStatRegResult {
    let xi = dims[0], yi = dims[1]
    func x(_ row: [Any]) -> Double { ecStatNum(row[xi]) ?? 0 }
    func y(_ row: [Any]) -> Double { ecStatNum(row[yi]) ?? 0 }
    func fit(_ predata: [[Any]], _ yOf: (Double) -> Double) -> [[Any]] {
        return predata.map { row -> [Any] in
            var item = row
            item[yi] = yOf(x(row))
            return item
        }
    }

    switch method {
    case "exponential":
        var sumX = 0.0, sumY = 0.0, sumXXY = 0.0, sumYlny = 0.0, sumXYlny = 0.0, sumXY = 0.0
        for row in predata {
            let xv = x(row), yv = y(row)
            sumX += xv; sumY += yv; sumXY += xv * yv
            sumXXY += xv * xv * yv
            sumYlny += yv * Foundation.log(yv)
            sumXYlny += xv * yv * Foundation.log(yv)
        }
        let denom = (sumY * sumXXY) - (sumXY * sumXY)
        let coefficient = pow(M_E, (sumXXY * sumYlny - sumXY * sumXYlny) / denom)
        let index = (sumY * sumXYlny - sumXY * sumYlny) / denom
        let points = fit(predata) { coefficient * pow(M_E, index * $0) }
        let expr = "y = " + number.jsNumberString(ecStatRound(coefficient, 2)) + "e^("
                 + number.jsNumberString(ecStatRound(index, 2)) + "x)"
        return EcStatRegResult(points: points, expression: expr)

    case "logarithmic":
        var sumlnx = 0.0, sumYlnx = 0.0, sumY = 0.0, sumlnxlnx = 0.0
        let n = Double(predata.count)
        for row in predata {
            let xv = x(row), yv = y(row)
            sumlnx += Foundation.log(xv)
            sumYlnx += yv * Foundation.log(xv)
            sumY += yv
            sumlnxlnx += pow(Foundation.log(xv), 2)
        }
        let gradient = (n * sumYlnx - sumY * sumlnx) / (n * sumlnxlnx - sumlnx * sumlnx)
        let intercept = (sumY - gradient * sumlnx) / n
        let points = fit(predata) { gradient * Foundation.log($0) + intercept }
        let expr = "y = " + number.jsNumberString(ecStatRound(intercept, 2)) + " + "
                 + number.jsNumberString(ecStatRound(gradient, 2)) + "ln(x)"
        return EcStatRegResult(points: points, expression: expr)

    case "polynomial":
        let k = order + 1
        var coeMatrix: [[Double]] = []
        var lhs: [Double] = []
        for i in 0..<k {
            var sumA = 0.0
            for row in predata { sumA += y(row) * pow(x(row), Double(i)) }
            lhs.append(sumA)
            var temp: [Double] = []
            for j in 0..<k {
                var sumB = 0.0
                for row in predata { sumB += pow(x(row), Double(i + j)) }
                temp.append(sumB)
            }
            coeMatrix.append(temp)
        }
        coeMatrix.append(lhs)
        let coe = ecStatGaussianElimination(&coeMatrix, k)
        let points = fit(predata) { xv in
            var value = 0.0
            for n in 0..<coe.count { value += coe[n] * pow(xv, Double(n)) }
            return value
        }
        var expr = "y = "
        for i in stride(from: coe.count - 1, through: 0, by: -1) {
            if i > 1 {
                expr += number.jsNumberString(ecStatRound(coe[i], i + 1)) + "x^" + String(i) + " + "
            } else if i == 1 {
                expr += number.jsNumberString(ecStatRound(coe[i], 2)) + "x" + " + "
            } else {
                expr += number.jsNumberString(ecStatRound(coe[i], 2))
            }
        }
        return EcStatRegResult(points: points, expression: expr)

    default: // "linear"
        var sumX = 0.0, sumY = 0.0, sumXY = 0.0, sumXX = 0.0
        let len = Double(predata.count)
        for row in predata {
            let xv = x(row), yv = y(row)
            sumX += xv; sumY += yv; sumXY += xv * yv; sumXX += xv * xv
        }
        let gradient = ((len * sumXY) - (sumX * sumY)) / ((len * sumXX) - (sumX * sumX))
        let intercept = (sumY / len) - ((gradient * sumX) / len)
        let points = fit(predata) { gradient * $0 + intercept }
        let expr = "y = " + number.jsNumberString(ecStatRound(gradient, 2)) + "x + "
                 + number.jsNumberString(ecStatRound(intercept, 2))
        return EcStatRegResult(points: points, expression: expr)
    }
}

// upstream src/regression.js `gaussianElimination` — operates on the TRANSPOSE of the augmented matrix.
private func ecStatGaussianElimination(_ matrix: inout [[Double]], _ number: Int) -> [Double] {
    for i in 0..<(matrix.count - 1) {
        var maxColumn = i
        for j in (i + 1)..<(matrix.count - 1) {
            if abs(matrix[i][j]) > abs(matrix[i][maxColumn]) { maxColumn = j }
        }
        for k in i..<matrix.count {
            let temp = matrix[k][i]; matrix[k][i] = matrix[k][maxColumn]; matrix[k][maxColumn] = temp
        }
        for n in (i + 1)..<(matrix.count - 1) {
            for m in stride(from: matrix.count - 1, through: i, by: -1) {
                matrix[m][n] -= matrix[m][i] / matrix[i][i] * matrix[i][n]
            }
        }
    }
    var data = [Double](repeating: 0, count: number)
    let len = matrix.count - 1
    for j in stride(from: matrix.count - 2, through: 0, by: -1) {
        var temp = 0.0
        for i in (j + 1)..<(matrix.count - 1) { temp += matrix[i][j] * data[i] }
        data[j] = (matrix[len][j] - temp) / matrix[j][j]
    }
    return data
}

// upstream src/transform/regression.js. `formulaOn:'end'` default => expression on the last point's dim 2.
let ecStatRegressionTransform = ExternalDataTransform(
    type: "ecStat:regression",
    transform: { params in
        let config = (params.config as? [String: Any]) ?? [:]
        let method = (config["method"] as? String) ?? "linear"
        let order = (config["order"] as? Double).map { Int($0) } ?? (config["order"] as? Int) ?? 2
        // config.dimensions default [0, 1] (the demos don't override it).
        let dims: [Int] = {
            if let d = config["dimensions"] as? [Any] { return d.compactMap { ecStatNum($0).map { Int($0) } } }
            if let d = ecStatNum(config["dimensions"]) { return [Int(d)] }
            return [0, 1]
        }()

        // dataPreprocess: keep rows that are number arrays at the target dims.
        let raw = (try? params.upstream.cloneRawData()) as? [[Any]] ?? []
        let predata = raw.filter { row in dims.allSatisfy { $0 < row.count && ecStatNum(row[$0]) != nil } }

        var result = ecStatRegress(method, predata, dims, order)
        // Sort for line chart (by the x dimension).
        let xi = dims[0]
        result.points.sort { (ecStatNum($0[xi]) ?? 0) < (ecStatNum($1[xi]) ?? 0) }

        // formulaOn (default 'end'): write the expression into dim 2 of the target point(s), '' elsewhere.
        let formulaOn = (config["formulaOn"] as? String) ?? "end"
        var dimensions: [DimensionDefinitionLoose]? = nil
        if formulaOn != "none" {
            for i in 0..<result.points.count {
                let onIt = (formulaOn == "start" && i == 0)
                    || (formulaOn == "all")
                    || (formulaOn == "end" && i == result.points.count - 1)
                let val: Any = onIt ? result.expression : ""
                if result.points[i].count > 2 { result.points[i][2] = val }
                else { while result.points[i].count < 2 { result.points[i].append(0) }; result.points[i].append(val) }
            }
            // Inherit the upstream dims and add an empty dim 2 for the formula string (FORMULA_DIMENSION).
            var dd: [DimensionDefinitionLoose] = params.upstream.cloneAllDimensionInfo().map { ext -> DimensionDefinitionLoose in
                var d = DimensionDefinition(); d.name = ext.name; d.type = ext.type; d.displayName = ext.displayName
                return d
            }
            while dd.count < 2 { dd.append(DimensionDefinition()) }
            if dd.count > 2 { dd[2] = DimensionDefinition() } else { dd.append(DimensionDefinition()) }
            dimensions = dd
        }

        return ExternalDataTransformResultItem(data: result.points, dimensions: dimensions)
    }
)
