import Foundation

// Units made of others, converted where both sides are of the same dimensions; letters run together
// read whichever way fits the other side. Run from Tests/main.swift.
func compoundUnitTests() {
    expect("17cms^-1 to ms^-1", "= 0.17 m s⁻¹", "17 cm s⁻¹")
    expect("17 cm s^-1 to m s^-1", "= 0.17 m s⁻¹", "17 cm s⁻¹")
    expect("17 cm/s to m/s", "= 0.17 m/s", "17 cm/s")
    expect("3 m s⁻¹ to km h⁻¹", "= 10.8 km h⁻¹", "3 m s⁻¹")
    expect("9.8 ms^-2 to cms^-2", "= 980 cm s⁻²", "9.8 m s⁻²")
    expect("1000 kg m^-3 to g/cm3", "= 1 g/cm3", "1000 kg m⁻³")
    // ms alone is still a millisecond, and a unit of another kind is still no conversion.
    expect("5 ms to s", "= 0.005 s", "5 ms")
    expect("60 km/h to m/s", "= 16.6667 m/s", "60 km/h")
    workingCheck(Units.compound("kg", "m") == nil, "a mass was converted to a length")
}

// A sum to a power that is not a whole number of nought or more: its binomial series, to the fourth
// term, with when it holds; and the name of the operation after what it works on. Letters with a minus
// between them are algebra, but for the few words written so.
func seriesAndLetterTests() {
    expect("(1+qx)^-1 expand", "1 − qx + q²x² − q³x³ + …", "Valid for |qx| < 1.")
    expect("(1+qx)^-1) expand", "1 − qx + q²x² − q³x³ + …", "Valid for |qx| < 1.")
    expect("expand((1+x)^-2)", "1 − 2x + 3x² − 4x³ + …", "Valid for |x| < 1.")
    expect("(4-x)^(1/2) expand", "2 − x/4 − x²/64 − x³/512 + …", "Valid for |x/4| < 1.")
    expect("(2+3x)^-1 expand", "1/2 − 3x/4 + 9x²/8 − 27x³/16 + …", "Valid for |3x/2| < 1.")
    expect("(1+x)^3 expand", "x³ + 3x² + 3x + 1")
    expect("px-qx", "= x(p − q)")
    expect("x-qx", "= x(1 − q)")
    expect("wi-fi", nil)
    expect("x-ray", nil)
    expect("ls -la", nil)
    expect("px - qx", "= x(p − q)")
}

// An expression with the one equation that settles a letter in it: the equation solved, its value put
// into the expression. And a power with only a number beside it, solved by its root, exactly.
func conditionedTests() {
    expect(#"\[ \binom{11}{4}x^7k^4 \],330k^4=1320"#, "k = ±√2", "Hence 1320x⁷")
    expect("x^2+3x, x^2=4", "x = ±2", "Hence x = −2 gives −2;  x = 2 gives 10")
    expect("2a+b, a+1=3", "a = 2", "Hence b + 4")
    // Values given are still values given, and two equations still a system.
    expect("v=u+at, u=2, a=3", "v = 3t + 2", "Taking u = 2, a = 3")
    expect("330k^4=1320", "k = ±√2", "≈ ±1.41421")
    expect("x^3=-8", "x = −2")
    expect("x^4=-1", "No real solutions", "An even power of a real number is never negative.")
    expect("x^4=16", "x = ±2")
    workingCheck(Solver.details("330k^4=1320")?.steps.map(\.label).contains("Taking the fourth root") == true, "a fourth power was not solved by its root")
}

// A number over a number and a letter, 84/21a⁶, is (84/21)a⁶, as 1/2x is; the reading is said, with what
// the other reading, two fractions, gives. Roots that are simple fractions are written as fractions.
func twoReadingsTests() {
    expect("84/21a^6=8/7a^5", "a = 0, 2/7", "≈ 0, 0.285714")
    workingCheck(Analyzer.read("84/21a^6=8/7a^5")?.notes == ["84/21a⁶ is read as (84/21)·a⁶; written 84/(21a⁶) = 8/(7a⁵), it gives a = 7/2."],
                 "the other reading was not given: \(Analyzer.read("84/21a^6=8/7a^5")?.notes ?? [])")
    expect("84/(21a^6)=8/(7a^5)", "a = 7/2", "≈ 3.5")
    expect("2x^4-x^3=0", "x = 0, 1/2", "≈ 0, 0.5")
}

// From the hardening report of 2026-11-11: work that would run for minutes is given up at once and
// said so; an order of derivative is what was typed or refused; a colour is only numbers; a translucent
// colour is laid over what it is seen on, and mixed as Sass mixes it.
func robustnessTests() {
    func quick(_ input: String, _ seconds: Double = 2) -> Solution? {
        let start = Date()
        let answer = Solver.answer(input)?.solution
        workingCheck(Date().timeIntervalSince(start) < seconds, "\(input) took \(Date().timeIntervalSince(start)) s")
        return answer
    }
    workingCheck(quick("sum(k,1,100000,sum(j,1,100000,k+j))")?.exact == "Too much to work out", "nested sums were not given up")
    workingCheck(quick("sum(k,1,1000,sum(j,1,1000,k+j))")?.exact == "= 1.001×10⁹", "a nested sum within the budget was given up")
    workingCheck(quick("d1000000000/dx1000000000 x^2")?.exact == "0", "a derivative was taken a thousand million times")
    workingCheck(quick("d100/dx100 sin(exp(x))")?.exact == "Too large to write out", "a growing derivative was not given up")
    workingCheck(quick("integrate(sin(1000000000*x^2),0,1)")?.exact == "Too much to work out", "an integral that cannot settle was not given up")
    workingCheck(quick(String(repeating: "2^", count: 32) + "1")?.exact == "Too large", "a tower of powers was not answered quickly")
    workingCheck(quick("d999999999999999999999/dx999999999999999999999 x^2")?.exact == "Order too large", "an order too large for a number was taken as 1")
    workingCheck(quick("d0/dx0 x^2")?.exact == "x²", "the derivative of order 0 was not the function itself")
    for input in ["color(display-p3 1e300 0 0)", "lab(50,1e300,0)", "xyY(0.3,0.3,1e308)"] {
        workingCheck(Solver.answer(input)?.solution.exact == "Not a colour", "\(input) was shown as a colour")
    }
    for input in ["hsl(nan,50%,50%)", "hsl(1e309,50%,50%)"] {
        workingCheck(Solver.answer(input).map { $0.solution.exact == "Not a colour" } ?? true, "\(input) was shown as a colour")
    }
    expect("contrast(rgba(0,0,0,0),white)", "1 : 1", "Contrast ratio. Fails every WCAG level for text.")
    expect("contrast(rgba(0,0,0,0.5),white)", "3.98 : 1", "Contrast ratio. Meets AA for large text only.")
    expect("contrast(black,white)", "21 : 1", "Contrast ratio. Meets AAA for all text.")
    expect("mix(rgba(255,0,0,0),blue,0.5)", "#0000FF80", "50% and 50% mixed: rgba(0, 0, 255, 0.5), which is blue")
    expect("mix(red,blue)", "#800080", "50% and 50% mixed: rgb(128, 0, 128), which is purple")
}

// Statements about whole numbers proved, by contradiction or directly, or shown false by an example.
func proofTests() {
    expect("p^2-8q-11=0 has no integer solutions", "No integer solutions", "Proved by contradiction, modulo 4")
    expect("prove p^2-8q-11=0, p,q ∈ ℤ", "No integer solutions", "Proved by contradiction, modulo 4")
    expect("x^2+y^2=3 has no integer solutions", "No integer solutions", "Proved by contradiction, modulo 4")
    expect("x^2-2y^2=1 has no integer solutions", "False", "x = 1, y = 0 is a solution")
    expect("n^3-n is divisible by 6", "6 | n³ − n", "Proved directly, by cases on n modulo 6")
    expect("n^2+n is even", "n² + n is even", "Proved directly, by cases on n modulo 2")
    expect("prove (2a+1)+(2b+1) is even", "2a + 1 + 2b + 1 is even", "Proved directly")
    expect("n^2+n+1 is even", "False", "For n = 0, n² + n + 1 = 1, which is odd")
    expect("3 divides n^3+2n", "3 | n³ + 2n", "Proved directly, by cases on n modulo 3")
    expect("prove √2 is irrational", "√2 is irrational", "Proved by contradiction")
    expect("sqrt(12) is irrational", "√12 is irrational", "Proved by contradiction")
    expect("sqrt(9) is irrational", "False", "√9 = 3, a whole number")
    // What the panel copies, as LaTeX and as text, read back gives the same verdict.
    for input in ["p^2-8q-11=0 has no integer solutions", "x^2-2y^2=1 has no integer solutions", "n^3-n is divisible by 6",
                  "n^2+n is even", "n^2+n+1 is even", "prove √2 is irrational", "3 divides n^3+2n"] {
        guard let answer = Solver.answer(input), let d = Solver.details(input) else { workingCheck(false, "\(input) was not answered"); continue }
        for line in [d.equation] + d.solutions where !line.plain.hasPrefix("False") {
            for copied in [line.latex, line.plain] {
                workingCheck(Solver.answer(copied)?.solution.exact == answer.solution.exact,
                             "\(copied), copied from \(input), read back as \(Solver.answer(copied)?.solution.exact ?? "nothing")")
            }
        }
    }
    let steps = Solver.details("p^2-8q-11=0 has no integer solutions")?.steps.map(\.label) ?? []
    workingCheck(steps.starts(with: ["Supposing the contrary", "Reducing modulo 4", "Listing every remainder of p", "Reaching a contradiction"]),
                 "the proof by contradiction was not set out in its steps: \(steps)")
}
