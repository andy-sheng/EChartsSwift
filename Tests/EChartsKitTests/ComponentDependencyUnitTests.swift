// Ported from echarts/test/ut/spec/model/componentDependency.test.ts — keep in sync with upstream
// Behavioral oracle for ComponentModel's registry + topological travel
// (echarts/src/model/Component.ts + util/component.ts topologicalTravel).
//
// PORTING NOTES (faithful divergences):
//   * Upstream generates component subclasses at RUNTIME (`extendModel('type_' + idx++, deps)`).
//     Swift has no runtime class generation, so each logical component is a fixed file-scope
//     `ComponentModel` subclass whose `type` / `dependencies` are compile-time class-var overrides.
//     The upstream sequential type-name strings are irrelevant (only uniqueness matters); we use
//     stable descriptive names and compare against those same constants.
//   * The callback ORDER produced by `topologicalTravel` depends on `getAllClassMainTypes()`,
//     which returns Swift `Dictionary` keys in UNSPECIFIED order (documented PORT-TODO in
//     clazz.swift). Upstream relies on JS insertion-order iteration. We therefore assert the
//     (componentType -> dependencies) MAPPING rather than the emission order. The dependency
//     list per type is still asserted exactly (for single-class main types it is deterministic:
//     ['dataset', ...declaredDeps]); the multi-subType case (a1) is order-normalized.
//   * The global ComponentModel registry is process-wide static state. Each test uses uniquely
//     named types so accumulation across tests forms disconnected graph components that never
//     enter the traversed target set (verified against the algorithm).

import XCTest
@testable import EChartsKit

// MARK: - topologicalTravel_base
private let B_m1 = "cdB_m1", B_a1 = "cdB_a1", B_a2 = "cdB_a2"
private final class CDB_M1: ComponentModel { override class var type: ComponentFullType { B_m1 }
    override class var dependencies: [String] { [B_a1, B_a2] } }
private final class CDB_A1: ComponentModel { override class var type: ComponentFullType { B_a1 } }
private final class CDB_A2: ComponentModel { override class var type: ComponentFullType { B_a2 } }

// MARK: - topologicalTravel_diamond
private let D_m1 = "cdD_m1", D_a1 = "cdD_a1", D_a2 = "cdD_a2", D_a3 = "cdD_a3"
private final class CDD_A1: ComponentModel { override class var type: ComponentFullType { D_a1 }
    override class var dependencies: [String] { [] } }
private final class CDD_A2: ComponentModel { override class var type: ComponentFullType { D_a2 }
    override class var dependencies: [String] { [D_a1] } }
private final class CDD_A3: ComponentModel { override class var type: ComponentFullType { D_a3 }
    override class var dependencies: [String] { [D_a1] } }
private final class CDD_M1: ComponentModel { override class var type: ComponentFullType { D_m1 }
    override class var dependencies: [String] { [D_a2, D_a3] } }

// MARK: - topologicalTravel_isolate
private let I_m1 = "cdI_m1", I_a1 = "cdI_a1", I_a2 = "cdI_a2"
private final class CDI_A2: ComponentModel { override class var type: ComponentFullType { I_a2 } }
private final class CDI_A1: ComponentModel { override class var type: ComponentFullType { I_a1 } }
private final class CDI_M1: ComponentModel { override class var type: ComponentFullType { I_m1 }
    override class var dependencies: [String] { [I_a2] } }

// MARK: - topologicalTravel_loop
private let L_m1 = "cdL_m1", L_m2 = "cdL_m2", L_a1 = "cdL_a1", L_a2 = "cdL_a2", L_a3 = "cdL_a3"
private final class CDL_M1: ComponentModel { override class var type: ComponentFullType { L_m1 }
    override class var dependencies: [String] { [L_a1, L_a2] } }
private final class CDL_M2: ComponentModel { override class var type: ComponentFullType { L_m2 }
    override class var dependencies: [String] { [L_m1, L_a2] } }
private final class CDL_A1: ComponentModel { override class var type: ComponentFullType { L_a1 }
    override class var dependencies: [String] { [L_m2, L_a2, L_a3] } }
private final class CDL_A2: ComponentModel { override class var type: ComponentFullType { L_a2 } }
private final class CDL_A3: ComponentModel { override class var type: ComponentFullType { L_a3 } }

// MARK: - topologicalTravel_missingSomeNodeButHasDependencies
private let N_m1 = "cdN_m1", N_a1 = "cdN_a1", N_a2 = "cdN_a2", N_a3 = "cdN_a3", N_a4 = "cdN_a4"
private final class CDN_M1: ComponentModel { override class var type: ComponentFullType { N_m1 }
    override class var dependencies: [String] { [N_a1, N_a2] } }
private final class CDN_A2: ComponentModel { override class var type: ComponentFullType { N_a2 }
    override class var dependencies: [String] { [N_a3] } }
private final class CDN_A3: ComponentModel { override class var type: ComponentFullType { N_a3 } }
private final class CDN_A4: ComponentModel { override class var type: ComponentFullType { N_a4 } }

// MARK: - topologicalTravel_subType
private let S_m1 = "cdS_m1", S_a1 = "cdS_a1", S_a2 = "cdS_a2", S_a3 = "cdS_a3", S_a4 = "cdS_a4"
private final class CDS_M1: ComponentModel { override class var type: ComponentFullType { S_m1 }
    override class var dependencies: [String] { [S_a1, S_a2] } }
private final class CDS_A1aaa: ComponentModel { override class var type: ComponentFullType { S_a1 + ".aaa" }
    override class var dependencies: [String] { [S_a2] } }
private final class CDS_A1bbb: ComponentModel { override class var type: ComponentFullType { S_a1 + ".bbb" }
    override class var dependencies: [String] { [S_a3, S_a4] } }
private final class CDS_A2: ComponentModel { override class var type: ComponentFullType { S_a2 } }
private final class CDS_A3: ComponentModel { override class var type: ComponentFullType { S_a3 } }
private final class CDS_A4: ComponentModel { override class var type: ComponentFullType { S_a4 } }

final class ComponentDependencyUnitTests: XCTestCase {

    /// Run topologicalTravel over `targets` (fullNameList = all registered main types), returning
    /// the emitted (componentType -> dependencies) mapping. Emission order is intentionally NOT
    /// captured (see file header).
    private func travel(_ targets: [String]) throws -> [String: [String]] {
        var result: [String: [String]] = [:]
        try ComponentModel.topologicalTravel(
            targets,
            ComponentModel.getAllClassMainTypes(),
            { type, deps in result[type] = deps }
        )
        return result
    }

    private func assertMapping(_ actual: [String: [String]], _ expected: [String: [String]],
                               file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(Set(actual.keys), Set(expected.keys), "traversed types", file: file, line: line)
        for (k, v) in expected {
            XCTAssertEqual(actual[k], v, "deps of \(k)", file: file, line: line)
        }
    }

    func test_topologicalTravel_base() throws {
        ComponentModel.registerClass(CDB_M1.self)
        ComponentModel.registerClass(CDB_A1.self)
        ComponentModel.registerClass(CDB_A2.self)
        let result = try travel([B_m1, B_a1, B_a2])
        assertMapping(result, [
            B_a2: ["dataset"],
            B_a1: ["dataset"],
            B_m1: ["dataset", B_a1, B_a2],
        ])
    }

    func test_topologicalTravel_empty() throws {
        // travel of [] returns immediately with no callbacks.
        let result = try travel([])
        XCTAssertTrue(result.isEmpty)
    }

    func test_topologicalTravel_isolate() throws {
        ComponentModel.registerClass(CDI_A2.self)
        ComponentModel.registerClass(CDI_A1.self)
        ComponentModel.registerClass(CDI_M1.self)
        let result = try travel([I_a1, I_a2, I_m1])
        assertMapping(result, [
            I_a1: ["dataset"],
            I_a2: ["dataset"],
            I_m1: ["dataset", I_a2],
        ])
    }

    func test_topologicalTravel_diamond() throws {
        ComponentModel.registerClass(CDD_A1.self)
        ComponentModel.registerClass(CDD_A2.self)
        ComponentModel.registerClass(CDD_A3.self)
        ComponentModel.registerClass(CDD_M1.self)
        let result = try travel([D_m1, D_a1, D_a2, D_a3])
        assertMapping(result, [
            D_a1: ["dataset"],
            D_a3: ["dataset", D_a1],
            D_a2: ["dataset", D_a1],
            D_m1: ["dataset", D_a2, D_a3],
        ])
    }

    func test_topologicalTravel_loop() throws {
        ComponentModel.registerClass(CDL_M1.self)
        ComponentModel.registerClass(CDL_M2.self)
        ComponentModel.registerClass(CDL_A1.self)
        ComponentModel.registerClass(CDL_A2.self)
        ComponentModel.registerClass(CDL_A3.self)
        XCTAssertThrowsError(try travel([L_m1, L_m2, L_a1])) { error in
            let msg = (error as? EChartsError)?.message ?? ""
            XCTAssertTrue(msg.contains("Circular"), "expected /Circular/, got: \(msg)")
        }
    }

    func test_topologicalTravel_missingSomeNodeButHasDependencies() throws {
        ComponentModel.registerClass(CDN_M1.self)
        ComponentModel.registerClass(CDN_A2.self)
        ComponentModel.registerClass(CDN_A3.self)
        ComponentModel.registerClass(CDN_A4.self)
        let expected: [String: [String]] = [
            N_a3: ["dataset"],
            N_a2: ["dataset", N_a3],
            N_m1: ["dataset", N_a1, N_a2],
        ]
        assertMapping(try travel([N_a3, N_m1]), expected)
        assertMapping(try travel([N_m1, N_a3]), expected)
    }

    func test_topologicalTravel_subType() throws {
        ComponentModel.registerClass(CDS_M1.self)
        ComponentModel.registerClass(CDS_A1aaa.self)
        ComponentModel.registerClass(CDS_A1bbb.self)
        ComponentModel.registerClass(CDS_A2.self)
        ComponentModel.registerClass(CDS_A3.self)
        ComponentModel.registerClass(CDS_A4.self)
        let result = try travel([S_m1, S_a1, S_a2, S_a4])
        // a4 / a2 / m1 deps are deterministic; a1 aggregates its two subTypes' deps whose ORDER is
        // dictionary-dependent (container iteration) -> compared as a set.
        XCTAssertEqual(result[S_a4], ["dataset"])
        XCTAssertEqual(result[S_a2], ["dataset"])
        XCTAssertEqual(result[S_m1], ["dataset", S_a1, S_a2])
        XCTAssertEqual(Set(result[S_a1] ?? []), Set(["dataset", S_a2, S_a3, S_a4]))
        XCTAssertEqual(Set(result.keys), Set([S_a4, S_a2, S_a1, S_m1]))
    }
}
