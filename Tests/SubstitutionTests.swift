import Foundation

// Astronomy's working with its numbers in: each letter of the formula given a value the method used
// or a constant, and shown only where the formula then gives the engine's answer. Run from Tests/main.swift.
func substitutionTests() {
    func working(_ formula: String, _ values: [(String, String, Double, String)], si: Double, unit: String) -> AstronomyWorking? {
        let raw: [String: Any] = ["working": ["formula": formula, "inputs": [], "constants": [], "intermediates": [], "results": [],
                                              "values": values.map { ["kind": $0.0, "label": $0.1, "value": $0.2, "unit": $0.3] },
                                              "si": si, "si_unit": unit]]
        return AstronomyWorking(raw, notes: [])
    }
    // The typeset line's thin spaces, between m and s⁻¹, read as spaces.
    func plain(_ w: AstronomySubstitution.Worked?) -> String { w?.line.plain.replacingOccurrences(of: "\u{2009}", with: " ") ?? "nil" }
    // v_esc = √(2GM/R) for the Earth: M and R found among the values used, G a constant.
    let earth = [("mass", "Mass of earth", 5.9722e24, "kg"), ("radius", "Radius of earth", 6.371e6, "m")]
    let escape = working("v_esc = √(2GM/R)", earth, si: 11186.165197346223, unit: "m s⁻¹").flatMap(AstronomySubstitution.work)
    workingCheck(escape?.assigned.map(\.symbol) == ["M", "R"], "escape velocity's letters were not given the Earth's mass and radius: \(String(describing: escape?.assigned.map(\.symbol)))")
    workingCheck(plain(escape).contains("6.6743 × 10⁻¹¹") && plain(escape).contains("5.9722 × 10²⁴") && plain(escape).hasSuffix("= 11186.2 m s⁻¹"),
                 "escape velocity was not written with its numbers: \(plain(escape))")
    // A substitution that does not give the answer is not shown.
    workingCheck(working("v_esc = √(2GM/R)", earth, si: 12000, unit: "m s⁻¹").flatMap(AstronomySubstitution.work) == nil,
                 "a substitution that does not reach the answer was shown")
    // m and M, two masses: each way of giving them is tried, and the one that gives the answer kept.
    let hill = working("r_H ≈ a(m/(3M))^(1/3)", [("mass", "Mass of sun", 1.988409870698051e30, "kg"), ("mass", "Mass of earth", 5.9722e24, "kg"),
                                                  ("length", "Semi major axis", 1.495978707e11, "m")],
                       si: 1.495978707e11 * pow(5.9722e24 / (3 * 1.988409870698051e30), 1.0 / 3), unit: "m").flatMap(AstronomySubstitution.work)
    workingCheck(hill.map { $0.assigned.first { $0.symbol == "m" }?.used.label } == "Mass of earth", "the Hill sphere took the Sun for the small mass")
    // v² = …: the square worked out, and then v.
    let visViva = working("v² = GM(2/r − 1/a)", [("mass", "Mass of sun", 1.988409870698051e30, "kg"), ("length", "Radius", 1.495978707e11, "m"),
                                                ("length", "Semi major axis", 1.7951744484e11, "m")],
                          si: 32171.144088353893, unit: "m s⁻¹").flatMap(AstronomySubstitution.work)
    workingCheck(plain(visViva).hasSuffix("v = 32171.1 m s⁻¹"), "v² was not worked through to v: \(plain(visViva))")
    // Δv is one letter, and g₀ a constant.
    let rocket = working("Δv = I_sp g₀ ln(m₀/m_f)", [("mass", "Initial mass", 1000, "kg"), ("mass", "Final mass", 500, "kg"), ("time", "Isp", 300, "s")],
                         si: 300 * 9.80665 * log(2), unit: "m s⁻¹").flatMap(AstronomySubstitution.work)
    workingCheck(rocket?.assigned.map(\.symbol) == ["I_sp", "m₀", "m_f"], "the rocket equation was not substituted: \(String(describing: rocket?.assigned.map(\.symbol)))")
    workingCheck(AstronomySubstitution.written(200000) == "200000" && AstronomySubstitution.written(6.6743e-11) == "6.6743 × 10⁻¹¹",
                 "numbers were not written as they are read")
}
