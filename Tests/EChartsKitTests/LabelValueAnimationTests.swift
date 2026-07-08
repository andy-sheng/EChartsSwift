// Tests for the label "number roll-up" value animation — label/labelStyle.ts
//   (`setLabelValueAnimation` + `animateLabelValue`) ported to label/labelStyle.swift, plus the
//   `model.interpolateRawValues` helper that drives each intermediate frame.
//
// STATIC-ORACLE NOTE (see labelStyle.swift PORT-NOTE): with animation DISABLED (or an animator
//   advanced to completion), the label settles to the FINAL formatted value in one `during(1)` call —
//   the live host renders the intermediate frames. These headless tests drive the settle path.
import XCTest
import ZRenderKit
@testable import EChartsKit

final class LabelValueAnimationTests: XCTestCase {

    // Numeric interpolation from 0 → 100 at t = 0 / 0.5 / 1 (auto precision).
    func testInterpolateRawValuesNumericAtThreeStops() {
        let data = SeriesData(["x", "y"], nil)
        // precision nil ⇒ auto (max of the two operands' precisions; both integers ⇒ 0).
        XCTAssertEqual((model.interpolateRawValues(data, nil, 0.0, 100.0, 0.0) as? Double) ?? .nan, 0.0, accuracy: 1e-9)
        XCTAssertEqual((model.interpolateRawValues(data, nil, 0.0, 100.0, 0.5) as? Double) ?? .nan, 50.0, accuracy: 1e-9)
        XCTAssertEqual((model.interpolateRawValues(data, nil, 0.0, 100.0, 1.0) as? Double) ?? .nan, 100.0, accuracy: 1e-9)
    }

    // Explicit precision is honoured (round the midpoint to 2 dp).
    func testInterpolateRawValuesExplicitPrecision() {
        let data = SeriesData(["x", "y"], nil)
        // 0 → 1 at t = 1/3 ⇒ 0.3333… → round to 2 ⇒ 0.33.
        XCTAssertEqual((model.interpolateRawValues(data, 2.0, 0.0, 1.0, 1.0 / 3.0) as? Double) ?? .nan, 0.33, accuracy: 1e-9)
    }

    // A string target is not interpolated — it snaps to source until percent==1 (upstream).
    func testInterpolateRawValuesStringSnaps() {
        let data = SeriesData(["x", "y"], nil)
        XCTAssertEqual(model.interpolateRawValues(data, nil, "a", "b", 0.4) as? String, "a")
        XCTAssertEqual(model.interpolateRawValues(data, nil, "a", "b", 1.0) as? String, "b")
    }

    // setLabelValueAnimation stores the value + valueAnimation flag; a second call rolls the previous
    //   value into `prevValue` (the source of the next animation).
    func testSetLabelValueAnimationStoresValueAndPrev() {
        let label = ZRText()
        let itemModel = Model(["label": ["show": true, "valueAnimation": true] as [String: Any]] as [String: Any])
        let models = labelStyle.getLabelStatesModels(itemModel)

        labelStyle.setLabelValueAnimation(label, models, 100.0, { v in "\(v)" })
        let store1 = labelStyle.labelInner(label)
        XCTAssertEqual(store1.value as? Double, 100.0)
        XCTAssertNil(store1.prevValue, "first set ⇒ prevValue is the (unset) previous value")
        XCTAssertEqual(store1.valueAnimation, true)
        XCTAssertNotNil(store1.statesModels, "valueAnimation on ⇒ statesModels snapshotted")

        labelStyle.setLabelValueAnimation(label, models, 200.0, { v in "\(v)" })
        let store2 = labelStyle.labelInner(label)
        XCTAssertEqual(store2.prevValue as? Double, 100.0, "second set ⇒ prevValue is the first value")
        XCTAssertEqual(store2.value as? Double, 200.0)
    }

    // valueAnimation OFF ⇒ the snapshot fields are NOT populated (nothing to animate).
    func testSetLabelValueAnimationDisabledSkipsSnapshot() {
        let label = ZRText()
        let itemModel = Model(["label": ["show": true] as [String: Any]] as [String: Any])
        let models = labelStyle.getLabelStatesModels(itemModel)

        labelStyle.setLabelValueAnimation(label, models, 42.0, { v in "\(v)" })
        let store = labelStyle.labelInner(label)
        XCTAssertEqual(store.value as? Double, 42.0)
        XCTAssertNotEqual(store.valueAnimation, true)
        XCTAssertNil(store.statesModels, "valueAnimation off ⇒ no snapshot")
    }

    // End-to-end (entrance): with animation disabled, `animateLabelValue` settles the label's TEXT to
    //   the final formatted number via the single `during(1)` call.
    func testAnimateLabelValueSettlesToFinalTextOnEntrance() {
        let label = ZRText()
        label.useStyle(TextStyleProps())
        let itemModel = Model(["label": ["show": true, "valueAnimation": true] as [String: Any]] as [String: Any])
        let models = labelStyle.getLabelStatesModels(itemModel)

        // Default-text getter formats the interpolated numeric value with a "$" prefix.
        labelStyle.setLabelValueAnimation(label, models, 100.0, { v in
            "$" + String(Int((v as? Double) ?? 0))
        })

        let data = SeriesData(["x", "y"], nil)
        let animModel = Model(["animation": false] as [String: Any])   // ⇒ synchronous settle
        labelStyle.animateLabelValue(label, 0, data, animModel, nil)

        XCTAssertEqual(label.textStyle.text, "$100", "label text should settle to the final formatted value")
    }

    // End-to-end (update): a value change from 100 → 200 settles to the new formatted number.
    func testAnimateLabelValueSettlesAfterValueChange() {
        let label = ZRText()
        label.useStyle(TextStyleProps())
        let itemModel = Model(["label": ["show": true, "valueAnimation": true] as [String: Any]] as [String: Any])
        let models = labelStyle.getLabelStatesModels(itemModel)
        let fmt: (InterpolatableValue) -> String = { v in String(Int((v as? Double) ?? 0)) }

        labelStyle.setLabelValueAnimation(label, models, 100.0, fmt)
        labelStyle.setLabelValueAnimation(label, models, 200.0, fmt)

        let data = SeriesData(["x", "y"], nil)
        let animModel = Model(["animation": false] as [String: Any])
        labelStyle.animateLabelValue(label, 0, data, animModel, nil)

        XCTAssertEqual(label.textStyle.text, "200")
    }

    // No animation when the value did not change (prevValue === value) — the label text is untouched.
    func testAnimateLabelValueNoOpWhenValueUnchanged() {
        let label = ZRText()
        var seed = TextStyleProps()
        seed.text = "seed"
        label.useStyle(seed)
        let itemModel = Model(["label": ["show": true, "valueAnimation": true] as [String: Any]] as [String: Any])
        let models = labelStyle.getLabelStatesModels(itemModel)
        let fmt: (InterpolatableValue) -> String = { v in String(Int((v as? Double) ?? 0)) }

        // Same value twice ⇒ prevValue == value ⇒ early-out.
        labelStyle.setLabelValueAnimation(label, models, 50.0, fmt)
        labelStyle.setLabelValueAnimation(label, models, 50.0, fmt)

        let data = SeriesData(["x", "y"], nil)
        let animModel = Model(["animation": false] as [String: Any])
        labelStyle.animateLabelValue(label, 0, data, animModel, nil)

        XCTAssertEqual(label.textStyle.text, "seed", "unchanged value ⇒ no re-format, text left as-is")
    }
}
