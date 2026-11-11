import Foundation

// Astronomy mode, after @: completion (matching, where the caret is, what a choice writes) and the
// functions worked out. Run from Tests/main.swift.
func astronomyTests() {
    struct LegacyCatalogue: Catalogue {
        let mark: Character = "@"
        var functions: [Completion.Function] { AstronomyCatalogue.table.map(\.function) }
        func candidates(for p: Completion.Parameter, typed: String) -> [Completion.Item] {
            Astronomy.catalogue.candidates(for:p,typed:typed).filter { !$0.detail.hasPrefix("Example") }
        }
    }
    let sky = LegacyCatalogue()
    func list(_ text: String, caret: Int? = nil) -> Completion.List? { Completion.list(text, caret: caret, in: sky) }
    func titles(_ text: String, caret: Int? = nil) -> [String] { list(text, caret: caret)?.items.map(\.title) ?? [] }
    func applied(_ text: String, caret: Int? = nil, choosing: Int = 0) -> Completion.Edit? {
        list(text, caret: caret).flatMap { Completion.apply($0, in: sky, choosing: choosing) }
    }
    func edit(_ text: String, _ location: Int, _ length: Int) -> Completion.Edit { Completion.Edit(text: text, selection: NSRange(location: location, length: length)) }
    // The choice of a given title from the list, wherever it stands in it.
    func choosing(_ title: String, in text: String, caret: Int? = nil) -> Completion.Edit? {
        guard let i = titles(text, caret: caret).firstIndex(of: title) else { return nil }
        return applied(text, caret: caret, choosing: i)
    }
    // Counted choices from earlier runs are put aside, so that the order is alphabetical.
    UserDefaults.standard.removeObject(forKey: Completion.usesKey)

    // Matching loosely: the start of the name, the starts of its words, or its letters in order.
    workingCheck(Completion.score("escape vel", "escape_velocity") != nil, "escape vel did not match escape_velocity")
    workingCheck(Completion.score("orb per", "orbital_period") != nil, "orb per did not match orbital_period")
    workingCheck(Completion.score("schw", "schwarzschild") != nil, "schw did not match schwarzschild")
    workingCheck(Completion.score("ear", "near") == nil, "ear matched near, whose word it does not begin")
    workingCheck(Completion.score("xyz", "earth") == nil, "xyz matched earth")
    workingCheck((Completion.score("schwarzschild", "schwarzschild") ?? 0) > (Completion.score("schw", "schwarzschild") ?? 0), "a name typed in full did not match best")

    // The functions while the name is typed, best first; every one after @ alone.
    workingCheck(titles("@ escape vel").first == "escape_velocity(body)", "escape vel did not find escape_velocity: \(titles("@ escape vel"))")
    workingCheck(titles("@ schw").first == "schwarzschild(body)", "schw did not find schwarzschild")
    workingCheck(titles("@kepler").first == "orbital_period(body)", "kepler did not find the orbital period by its alias")
    workingCheck(titles("@ wien").first == "wien_peak(T)", "wien did not find wien_peak")
    workingCheck(titles("@").count == AstronomyCatalogue.table.count, "@ alone did not offer every function")
    workingCheck(titles("@") == titles("@").sorted { $0.localizedStandardCompare($1) == .orderedAscending }, "@ alone did not list the functions alphabetically: \(titles("@"))")
    workingCheck(titles("@ orbital") == ["orbital_period(body)", "orbital_speed(body)"], "names beginning alike were not alphabetical")
    workingCheck(list("@ schw")?.stage == .function, "the name was not taken as a name")

    // Inside the brackets, what fits the argument and never a function.
    let ear = list("@ schwarzschild(ear")
    workingCheck(ear?.items.first?.title == "earth" && ear?.fragment == "ear", "ear inside schwarzschild did not offer earth first: \(titles("@ schwarzschild(ear"))")
    workingCheck(!(ear?.items.contains { $0.function != nil } ?? true), "a function was offered as an argument")
    if case .argument(let function, let index, let parameter)? = ear?.stage {
        workingCheck(function == "schwarzschild" && index == 0 && parameter.kind == "mass", "schwarzschild's argument was not read as its mass")
    } else { workingCheck(false, "inside the brackets was not taken as an argument") }
    // A placeholder still standing is nothing typed: everything that fits is offered.
    let placeholder = list("@ schwarzschild(body)", caret: 16)
    workingCheck(placeholder?.fragment == "" && placeholder?.items.first?.title == "alpha_centauri", "the placeholder body was taken as typed, or not listed alphabetically: \(titles("@ schwarzschild(body)", caret: 16))")
    // Bodies for the one-body form first; then those that are only a mass, for escape_velocity(M, r),
    // whose radius is then still to be typed.
    let escape = titles("@ escape_velocity(")
    workingCheck(escape.prefix(while: { Body.named($0)?.radius != nil }).count == escape.count - 1 && escape.last == "sgr_a",
                 "escape_velocity offered bodies in the wrong order: \(escape)")
    workingCheck(applied("@ escape_velocity(sgr", choosing: 0) == edit("@ escape_velocity(sgr_a, r)", 25, 1), "a mass alone did not leave its radius to be typed: \(String(describing: applied("@ escape_velocity(sgr")))")
    workingCheck(titles("@ orbital_period(").prefix(10).allSatisfy { Body.named($0)?.orbit != nil }, "orbital_period offered a body in no orbit first")
    // A number where the one-body form has none: the value of the form that takes one.
    workingCheck(titles("@ orbital_period(1.5").first == "1.5 AU", "a distance was not offered as the first argument of orbital_period(a, M)")
    workingCheck(list("@ orbital_period(1.5")?.parameter?.name == "a", "the list did not say it was choosing a")
    // A number typed: that number in each unit that fits, and no bodies.
    workingCheck(Set(titles("@ schwarzschild(10")) == ["10 M☉", "10 M⊕", "10 M_J", "10 kg"] && titles("@ schwarzschild(10").first == "10 kg",
                 "masses were not offered for 10, alphabetically: \(titles("@ schwarzschild(10"))")
    workingCheck(titles("@ schwarzschild(10 Msun").first == "10 M☉", "10 Msun did not find 10 M☉")
    workingCheck(titles("@ wien_peak(5778") == ["5778 °C", "5778 K"] && list("@ wien_peak(5778 K") == nil, "a temperature was not offered in kelvin and Celsius")
    workingCheck(titles("@ parallax_distance(0.3").first == "0.3 arcsec", "a parallax was not offered in arcseconds")
    // The second argument of the other form: escape_velocity(M, r).
    workingCheck(titles("@ escape_velocity(5.97e24 kg, 6.37e6").first == "6.37e6 km", "the radius of escape_velocity(M, r) was not offered lengths")
    // Nothing to offer: no @, the call closed, an argument typed in full, a function not known.
    workingCheck(list("schw") == nil && list("2+2") == nil, "a list was offered without @")
    workingCheck(list("@ schwarzschild(earth)") == nil, "a list was offered after the call was closed")
    workingCheck(list("@ schwarzschild(earth") == nil, "a list was offered for an argument typed in full")
    workingCheck(list("@ nosuch(ea") == nil, "a list was offered inside an unknown function")
    workingCheck(list("@ 2+2") == nil, "a list was offered for a sum")

    // Choosing: a function written with its placeholders, the first selected; an argument in its
    // place, the call closed, and the caret past it; the next placeholder selected where there is one.
    workingCheck(applied("@ schw") == edit("@ schwarzschild(body)", 16, 4), "choosing schwarzschild: \(String(describing: applied("@ schw")))")
    workingCheck(applied("@") == edit("@ absolute_magnitude(body)", 21, 4), "choosing straight after @ left no space: \(String(describing: applied("@")))")
    workingCheck(applied("@ escape vel") == edit("@ escape_velocity(body)", 18, 4), "choosing escape_velocity")
    workingCheck(applied("@ schwarzschild(ear") == edit("@ schwarzschild(earth)", 22, 0), "choosing earth: \(String(describing: applied("@ schwarzschild(ear")))")
    workingCheck(choosing("earth", in: "@ schwarzschild(body)", caret: 16) == edit("@ schwarzschild(earth)", 22, 0),
                 "typing over the placeholder: \(String(describing: choosing("earth", in: "@ schwarzschild(body)", caret: 16)))")
    workingCheck(choosing("sun", in: "@ apparent_magnitude(M, d)", caret: 21) == edit("@ apparent_magnitude(sun, d)", 26, 1),
                 "the next placeholder was not selected: \(String(describing: choosing("sun", in: "@ apparent_magnitude(M, d)", caret: 21)))")
    workingCheck(choosing("10 M☉", in: "@ schwarzschild(10") == edit("@ schwarzschild(10 M☉)", 22, 0), "choosing a unit")
    workingCheck(applied("@ escape_velocity(ear") == edit("@ escape_velocity(earth)", 24, 0), "the call was not closed: \(String(describing: applied("@ escape_velocity(ear")))")
    workingCheck(applied("@ orbital_period(1 AU") == nil && applied("@ orbital_period(1.5 A")?.text == "@ orbital_period(1.5 AU, M)", "the next placeholder was not written in: \(String(describing: applied("@ orbital_period(1.5 A")))")
    workingCheck(titles("@ kepler(ear").first == "earth", "inside an alias's brackets, its arguments were not offered")
    // Brackets already there are kept.
    workingCheck(applied("@ schw(earth)", caret: 6) == edit("@ schwarzschild(earth)", 16, 0), "a name corrected kept its brackets: \(String(describing: applied("@ schw(earth)", caret: 6)))")

    // What is chosen most comes first: among the functions with nothing typed, among those that
    // match as well, and among bodies; a unit is counted whatever number it came with.
    func choose(_ title: String, in text: String, caret: Int? = nil) {
        guard var l = list(text, caret: caret), let i = l.items.firstIndex(where: { $0.title == title }) else { return workingCheck(false, "\(title) was not offered for \(text)") }
        l.selected = i
        _ = Completion.choose(l, in: sky)
    }
    choose("wien_peak(T)", in: "@")
    workingCheck(titles("@").first == "wien_peak(T)", "the function chosen was not offered first: \(titles("@").prefix(3))")
    choose("orbital_speed(body)", in: "@ orb")
    choose("orbital_speed(body)", in: "@ orb")
    workingCheck(titles("@ orbital") == ["orbital_speed(body)", "orbital_period(body)"], "the function chosen more often did not come first among those matching")
    workingCheck(titles("@ escape vel").first == "escape_velocity(body)", "a better match was put below one chosen more often")
    choose("earth", in: "@ schwarzschild(body)", caret: 16)
    workingCheck(list("@ escape_velocity(body)", caret: 18)?.items.first?.title == "earth", "the body chosen was not offered first in another function")
    choose("3 M☉", in: "@ schwarzschild(3")
    workingCheck(titles("@ schwarzschild(25").first == "25 M☉", "the unit chosen was not offered first for another number: \(titles("@ schwarzschild(25"))")
    workingCheck(Completion.uses["@f:orbital_speed"] == 2 && Completion.uses["@a:unit M☉"] == 1, "the choices were not counted: \(Completion.uses)")
    // Reset All Settings forgets them, and the order is alphabetical again.
    UserDefaults.standard.removeObject(forKey: Completion.usesKey)
    workingCheck(titles("@").first == "absolute_magnitude(body)" && titles("@ orbital").first == "orbital_period(body)", "forgetting the choices did not restore the order")

    // Values with units.
    func si(_ s: String) -> Double? { AstroUnit.quantity(s).map { $0.value * ($0.unit?.factor ?? 1) } }
    workingCheck(si("1.5×10^11 m") == 1.5e11 && si("1.5e11m") == 1.5e11 && si("1.5×10¹¹ m") == 1.5e11, "standard form was misread")
    workingCheck(si("2*10^30 kg") == 2e30, "2*10^30 kg was misread")
    workingCheck(si("10 M☉") == 10 * Body.solarMass && si("10 msun") == 10 * Body.solarMass, "solar masses were misread")
    workingCheck(AstroUnit.quantity("3 Mpc")?.unit?.symbol == "Mpc" && AstroUnit.quantity("3 mpc") == nil, "Mpc was read without its case")
    workingCheck(AstroUnit.quantity("earth") == nil, "a body was read as a quantity")
    workingCheck(Format.number(2952.7) == "2950" && Format.number(11186) == "1.12×10⁴" && Format.number(0.00885) == "8.85×10⁻³" && Format.number(1) == "1.00",
                 "numbers were not written to three figures: \(Format.number(2952.7)) \(Format.number(11186)) \(Format.number(0.00885)) \(Format.number(1))")

    astronomyRegistryTests()
}

private func astronomyRegistryTests() {
    AstronomyEngine.synchronous = true
    defer { AstronomyEngine.synchronous = false }
    let registry = AstronomyEngine.methods
    workingCheck(registry.count == 234, "Full astronomy registry must contain 234 methods")
    let catalogue = Astronomy.catalogue
    for method in registry {
        workingCheck(catalogue.functions.contains { $0.name == method.name }, "Missing completion for " + method.name)
    }
    for method in registry {
        let query = "@" + method.example
        let answer = Solver.answer(query)
        workingCheck((answer?.details?.steps.count ?? 0) >= 3, "Registry method failed through Swift parser/worker: " + method.name + " / " + (answer?.solution.exact ?? "nil"))
        workingCheck(answer?.details?.diagram != nil, "Registry method has no presentation: " + method.name)
    }
    func number(_ text: String, _ expected: Double, tolerance: Double = 1e-6) {
        let result = Solver.answer(text)
        workingCheck(result?.values.first.map { abs($0-expected) <= tolerance * max(abs(expected),1) } == true, text + " wrong value: " + (result?.solution.exact ?? "nil"))
        workingCheck(result?.details?.steps.count ?? 0 >= 3, text + " missing working")
        workingCheck(result?.details?.diagram != nil, text + " missing visualization")
    }
    number("@ redshift(500 nm, 600 nm)",0.2)
    number("@ lorentz_factor(0.8 c)",5.0/3.0)
    number("@ radius(earth)",6371000)
    number("@ rest_energy(1 kg)",8.987551787368176e16)
    number("@ eccentricity(orbit(earth, sun))",0.01715,tolerance:0.001)
    workingCheck(Solver.details("@ sky_map({longitude:121 deg,latitude:25 deg},\"2026-11-11\")")?.diagram != nil,"Sky map missing")
    for text in ["@ orbit(earth,sun)", "@ hr_position(sun)", "@ blackbody_spectrum(5772 K)", "@ schwarzschild_radius(sun)"] {
        workingCheck(Solver.details(text)?.diagram != nil,text + " missing diagram")
    }
    workingCheck(Solver.answer("@ redshift(500 nm,600 nm)")?.symbol == "moon.stars", "Astronomy sign missing")
    workingCheck(Completion.list("@ eccentricity(orbit(ear", in: catalogue)?.items.contains { $0.title == "earth" } == true, "Nested orbit completion missing")
    workingCheck(Completion.list("@ transit_light_curve(earth,sun,earth_orbit,[0 day,1 day], geometry={inclination:90 deg}",in: catalogue) == nil,"Object commas confused completion")
    UserDefaults.standard.set(["@f:redshift_velocity":100],forKey:Completion.usesKey)
    workingCheck(Completion.list("@ redshift",in:catalogue)?.items.first?.function == "redshift","A legacy alias outranked the canonical spectral redshift")
    UserDefaults.standard.removeObject(forKey:Completion.usesKey)
    let full = Completion.list("@ sch",in:catalogue)
    workingCheck(full?.items.contains { $0.function == "schwarzschild_radius" } == true,"Canonical Schwarzschild method missing")
    let units = Completion.list("@ plane_change_delta_v(7.8",in:catalogue)?.items ?? []
    workingCheck(units.contains { $0.insertion == "7.8 km/s" },"Speed unit completion missing")
    let noArguments = Completion.list("@ hubble_time",in:catalogue).flatMap { Completion.apply($0,in:catalogue) }
    workingCheck(noArguments?.selection.location == (noArguments?.text.utf16.count ?? -1),"Zero-argument completion left the caret inside brackets")
    AstronomyEngine.synchronous = false
    let query = "  @rest_energy(1.23456789 kg)"
    var changed = false
    let token = NotificationCenter.default.addObserver(forName:AstronomyEngine.changed,object:nil,queue:.main) { notice in
        if notice.object as? String == query { changed = true }
    }
    let pending = Astronomy.parse(query)
    workingCheck(pending?.copy == nil,"Pending calculation exposed a value to copy")
    let deadline=Date().addingTimeInterval(10)
    while !changed && Date() < deadline { RunLoop.current.run(until:Date().addingTimeInterval(0.02)) }
    NotificationCenter.default.removeObserver(token)
    workingCheck(changed && AstronomyEngine.shared.answer(query).value != nil,"Background calculation did not refresh its result")
    with("astronomy",false) { expect("@ redshift(500 nm,600 nm)",nil) }
}
