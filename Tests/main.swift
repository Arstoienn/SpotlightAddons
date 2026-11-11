import Foundation

// Run with ./test.sh. Each case is what Spotlight's field would hold and what the card should say.

var failures = 0
// The expectations below are of a sum answered as a fraction first; decimals first is tried further down.
UserDefaults.standard.set(false, forKey: "decimalFirst")

func expect(_ input: String, _ exact: String?, _ approx: String? = nil, approxAny: Bool = false) {
    let got = Solver.solve(input)
    let ok = got?.exact == exact && (approxAny || got?.approx == approx)
    if !ok {
        failures += 1
        print("FAIL \(input)\n  want \(exact ?? "nil") / \(approx ?? "nil")\n  got  \(got?.exact ?? "nil") / \(got?.approx ?? "nil")")
    }
}

// Quadratics, exactly
expect("2n^2=10", "n = ±√5", "≈ ±2.23607")
expect("2N²=10", "N = ±√5", "≈ ±2.23607")
expect("x^2-5x+6=0", "x = 2, 3")
expect("x^2=2x+1", "x = 1 ± √2", "≈ −0.414214, 2.41421")
expect("2x^2+3x-1=0", "x = (−3 ± √17)/4", "≈ −1.78078, 0.280776")
expect("4x^2=9", "x = ±3/2", "≈ ±1.5")
expect("x^2+1=0", "x = ±i", "No real solutions; the roots are complex")
expect("x^2+2x+5=0", "x = −1 ± 2i", "No real solutions; the roots are complex")
expect("x^2-2x+1=0", "x = 1")
expect("(x+1)(x-1)=3", "x = ±2")
expect("x^2/2=8", "x = ±4")
expect("0.5x^2=2", "x = ±2")

// Linear
expect("3x+2=11", "x = 3")
expect("2x=1", "x = 1/2", "≈ 0.5")
expect("x/3+1=2", "x = 3")
expect("x=x", "x ∈ ℝ", "Every real number satisfies the equation.")
expect("x+1=x", "No solution")

// Higher degree and irrational coefficients, numerically
expect("x^3-6x^2+11x-6=0", "x = 1, 2, 3")
expect("x^3=2", "x ≈ 1.25992")
expect("x^2=pi", "x ≈ ±1.77245")
expect("x^4=16", "x = ±2")

// Not polynomials
expect("2^x=8", "x = 3")
expect("e^x=10", "x ≈ 2.30259")
expect("sqrt(x)=3", "x = 9")
expect("√x=3", "x = 9")
expect("ln x=1", "x ≈ 2.71828")
expect("sin(x rad)=0.5", "x = π/6, 5π/6", "≈ 0.524, 2.618 = 30°, 150°, for 0 ≤ x ≤ 2π")
expect("1/x=4", "x = 1/4", "≈ 0.25")
expect("tan(x rad)=x", "x ≈ −7.72525, −4.49341, 0, 4.49341, 7.72525, …", approxAny: true)
expect("sin(x rad)^2=0", "x = 0, π, 2π", "≈ 0, 3.142, 6.283 = 0°, 180°, 360°, for 0 ≤ x ≤ 2π")
expect("sin(x^2 rad)=0", "x ≈ −2.50663, −1.77245, 0, 1.77245, 2.50663, …", approxAny: true)
expect("e^x=-1", "No real solutions found", "The interval −1000 ≤ x ≤ 1000 was searched.")

// An angle is given from 0 to 2π, and in degrees: the unknown only inside sin, cos and tan
expect("(20^2*sin(2x rad))/9.81=20", "x ≈ 0.256332, 1.31446, 3.39792, 4.45606", "≈ 14.6867°, 75.3133°, 194.687°, 255.313°, for 0 ≤ x ≤ 2π")
expect("0.5=cos(x rad)", "x = π/3, 5π/3", "≈ 1.047, 5.236 = 60°, 300°, for 0 ≤ x ≤ 2π")
expect("cos(x rad)=-1", "x = π", "≈ 3.142 = 180°, for 0 ≤ x ≤ 2π")
expect("sin(x rad)=cos(x rad)", "x = π/4, 5π/4", "≈ 0.785, 3.927 = 45°, 225°, for 0 ≤ x ≤ 2π")
expect("sin(10x rad)=0.5", "x = π/60, π/12, 13π/60, 17π/60, …", "≈ 0.052, 0.262, 0.681, 0.890, … = 3°, 15°, 39°, 51°, …, for 0 ≤ x ≤ 2π")
expect("sin(x/100 rad)=1", "x ≈ −471.239, 157.08, 785.398")
expect("x^2+sin(x rad)=1", "x ≈ −1.40962, 0.636733")

// Angles are in radians unless marked deg or °
expect("sin(x)=0.5", "x = π/6, 5π/6", "≈ 0.524, 2.618 = 30°, 150°, for 0 ≤ x ≤ 2π")
expect("sin(x deg)=0.5", "x = 30°, 150°", "= π/6, 5π/6 rad, for 0° ≤ x ≤ 360°")
expect("(20^2*sin(2x deg))/9.81=20", "x ≈ 14.6867°, 75.3133°, 194.687°, 255.313°", "≈ 0.256, 1.314, 3.398, 4.456 rad, for 0° ≤ x ≤ 360°")
expect("cos(x°)=-1", "x = 180°", "= π rad, for 0° ≤ x ≤ 360°")
expect("3sin(x deg)=0", "x = 0°, 180°, 360°", "= 0, π, 2π rad, for 0° ≤ x ≤ 360°")
expect("sin(10x deg)=0.5", "x = 3°, 15°, 39°, 51°, …", "= π/60, π/12, 13π/60, 17π/60, … rad, for 0° ≤ x ≤ 360°")
expect("sin(30 deg)=0.5", "True", "0.5 = 0.5")
expect("sin(30)=0.5", "False", approxAny: true)
expect("sin(pi/6)=0.5", "True", "0.5 = 0.5")
expect("x=asin(0.5)", "x = π/6", "= 30°")
expect("x=asin(0.5) deg", "x = 30°", "= π/6 rad")
expect(#"\tan^{-1}24/21"#, "≈ 0.851966", "≈ 48.8141°")
expect("x=tan^-1(1)", "x = π/4", "= 45°")
expect("x=atan(24/21) deg", "x ≈ 48.8141°", "≈ 0.851966 rad")
expect("sin 2x=1", "x = π/4, 5π/4", approxAny: true)
expect("x=sin^2(pi/6)", "x = 1/4", "≈ 0.25")
expect("sin x cos x=0.25", "x = π/12, 5π/12, 13π/12, 17π/12", approxAny: true)
expect("x=sin 1/2", "x ≈ 0.479426")
expect("x=asin(0.5) rad", "x = π/6", "= 30°")
expect("x=sin(2rad)", "x ≈ 0.909297")
expect("sin(pi*x)=0", "x = 0, 1, 2, 3, …", approxAny: true)

// Implicit multiplication and functions
expect("2(x+1)=10", "x = 4")
expect("3sin(x rad)=0", "x = 0, π, 2π", "≈ 0, 3.142, 6.283 = 0°, 180°, 360°, for 0 ≤ x ≤ 2π")
expect("xx=4", "x = ±2")

// LaTeX, as formulas are often copied
expect(#"PES=\frac{\frac{120000-80000}{80000}}{\frac{250-200}{200}}"#, "PES = 2")
expect(#"\frac{1}{3}"#, "= 1/3", "≈ 0.333333")
expect(#"\frac{x}{2}+1=3"#, "x = 4")
expect(#"x^{2}=4"#, "x = ±2")
expect(#"\sqrt{x}=3"#, "x = 9")
expect(#"2\cdot x=6"#, "x = 3")
expect(#"\left(x+1\right)^{2}=9"#, "x = −4, 2")
expect(#"\sqrt[3]{x}=2"#, "x = 8")
expect(#"\(x^2 - 4x + 1 = 0\)"#, "x = 2 ± √3", "≈ 0.267949, 3.73205")
expect(#"$\frac12 x = 3$"#, "x = 6")
expect(#"x \le 3"#, nil)

// Sums and products
expect(#"\sum_{k=0}^{10}k20"#, "= 1100")
expect(#"\sum_{k=1}^{10} k"#, "= 55")
expect(#"\sum_{k=1}^{4} k^{2} + 1"#, "= 31")
expect(#"\prod_{k=1}^{5} k"#, "= 120")
expect(#"\sum_{k=1}^{3} kx = 12"#, "x = 2")
expect(#"S=\sum_{n=1}^{100}\frac{1}{n^2}"#, "S ≈ 1.63498")
expect("sum(k,1,3,k)=x", "x = 6")

// Systems of equations, including as LaTeX writes them
expect(#"\[\#n2x+3y=12,\quad 5x-y=7\#n\]"#, "x = 33/17, y = 46/17", "≈ 1.94118, 2.70588")
expect(#"\begin{cases} x+y=3 \\ x-y=1 \end{cases}"#, "x = 2, y = 1")
expect(#"\left\{ \begin{aligned} 2x &= 4 \\ x + y &= 5 \end{aligned} \right."#, "x = 2, y = 3")
expect("x+y=3,\tx-y=1", "x = 2, y = 1")
expect("2x+y=5, x-y=1", "x = 2, y = 1")
expect("3x=2, 3x=1", "No solution", "The lines are parallel and do not intersect.")
expect("x+y=2, 2x+2y=4", "Infinitely many solutions", "The equations represent the same line.")
expect("x+2y=1; 3x-y=2", "x = 5/7, y = 1/7", "≈ 0.714286, 0.142857")
expect("y=2x+1, y=-x+4", "x = 1, y = 3")
expect("a+b+c=6, a-b=0, 2c=6", "a = 3/2, b = 3/2, c = 3", "≈ 1.5, 1.5, 3")
expect("x^2+y=1, x-y=2", "(x, y) = ((−1 − √13)/2, (−5 − √13)/2), ((−1 + √13)/2, (−5 + √13)/2)", "2 real solutions")

// Systems that are not linear, solved numerically, exact where the values are simple
expect(#"\[\#n\begin{cases}\#nx^2+y+z=3\\\#nx+y^2+z=3\\\#nx+y+z^2=3\#n\end{cases}\#n\]"#,
       "(x, y, z) = (−3, −3, −3), (−√2, −√2, 1 + √2), …", "8 real solutions")
expect("x^2+y^2=25, x+y=7", "(x, y) = (3, 4), (4, 3)", "2 real solutions")
expect("x^3=8, y=x+1", "x = 2, y = 3")
expect("x^2+y^2=-1, x=y", "No real solutions found", "The search was conducted from numerous starting points about the origin.")

// Capitals are letters of their own, and E is not Euler's number
expect("X^2=4", "X = ±2")
expect("E=0.5*2*3^2", "E = 9")
expect("E=e^2", "E ≈ 7.38906")

// Powers of ten, and numbers of any size
expect("m=5.97e24*2", "m = 1.194×10²⁵")
expect("x=1.6e-19*2", "x = 3.2×10⁻¹⁹")
expect("x=1.6*10^-19*2", "x = 3.2×10⁻¹⁹")
expect("x=3E8*2", "x = 6×10⁸")
expect("x=12345678*2", "x = 24691356")
expect("x=1/3*10^-19", "x ≈ 3.33333×10⁻²⁰")
expect("3e-19=6.63e-34*f", "f ≈ 4.52489×10¹⁴")
expect("2e - 3=1", "e = 2")
expect("x=0.1+0.2-0.3", "x = 0")
expect("x=sin(pi)", "x = 0")
expect("0.1x+0.2x-0.3x=5", "No solution")

// Physical constants, where there is another letter to solve for
expect("x=2g", "x ≈ 19.6", "Taking g = 9.8 m s⁻²")
expect("h=0.5g*3^2", "h ≈ 44.1", "Taking g = 9.8 m s⁻²")
expect("E=0.002c^2", "E = 1.8×10¹⁴", "Taking c = 3.00×10⁸ m s⁻¹")
expect("F=G*5.97e24*70/6.37e6^2", "F ≈ 686.941", "Taking G = 6.67×10⁻¹¹ N m² kg⁻²")
expect("20=0.5g*t^2", "t ≈ ±2.02031", "Taking g = 9.8 m s⁻²")
expect("9.8=G*M/6.37e6^2", "M ≈ 5.96182×10²⁴", "Taking G = 6.67×10⁻¹¹ N m² kg⁻²")
expect("c=2g", "c ≈ 19.6", "Taking g = 9.8 m s⁻²")
expect("2c=g", "g = 6×10⁸", "Taking c = 3.00×10⁸ m s⁻¹")
expect("2g=10", "g = 5")
expect("2c=6", "c = 3")
expect("2G=10", "G = 5")
expect("g=2g", "g = 0")
expect("e=2g", "g ≈ 1.35914")
expect("F=mg", nil)
expect("E=mc^2", "Insufficient information", "A value is required for E or m.")
expect("h=0.5gt^2", "Insufficient information", "A value is required for h or t.")

// A letter marked with ! is read the other way round: the constant where it would have been
// the unknown, and the unknown where it would have been the constant
expect("9e16=1*c^2", "c = ±3×10⁸")
expect("9e16=1* !c^2", "True", "9×10¹⁶ = 9×10¹⁶")
expect("9e16=!c^2", "True", "9×10¹⁶ = 9×10¹⁶")
expect("!g=9.8", "True", "9.8 = 9.8")
expect("!g ≈ 9.81", "False", approxAny: true)
expect("c=2g", "c ≈ 19.6", "Taking g = 9.8 m s⁻²")
expect("c=2*!g", "g = 1.5×10⁸", "Taking c = 3.00×10⁸ m s⁻¹")
expect("!c=2g", "g = 1.5×10⁸", "Taking c = 3.00×10⁸ m s⁻¹")
expect("!c=2*!g", "g = 1.5×10⁸", "Taking c = 3.00×10⁸ m s⁻¹")
expect("x=2*!g", nil)
expect("20=0.5*!g*t^2", nil)
expect("!x=2", nil)
expect("2!g=10", "g = 5")
expect("e ≈ 2.718", "True", approxAny: true)

// Greek letters, by name, as themselves and from LaTeX
expect("2omega=10", "ω = 5")
expect("2ω=10", "ω = 5")
expect("rho*2=5", "ρ = 5/2", "≈ 2.5")
expect("sin(theta rad)=0.5", "θ = π/6, 5π/6", "≈ 0.524, 2.618 = 30°, 150°, for 0 ≤ θ ≤ 2π")
expect("cos(theta rad)=0.5", "θ = π/3, 5π/3", "≈ 1.047, 5.236 = 60°, 300°, for 0 ≤ θ ≤ 2π")
expect(#"\sin(2\theta rad)=0.5"#, "θ = π/12, 5π/12, 13π/12, 17π/12", "≈ 0.262, 1.309, 3.403, 4.451 = 15°, 75°, 195°, 255°, for 0 ≤ θ ≤ 2π")
expect("(20^2*sin(2theta rad))/g=20", "θ ≈ 0.256045, 1.31475, 3.39764, 4.45634", approxAny: true)
expect("lambda=c/5e14", "λ = 6×10⁻⁷", "Taking c = 3.00×10⁸ m s⁻¹")
expect("phi^2=phi+1", "φ = (1 ± √5)/2", "≈ −0.618034, 1.61803")
expect("alpha+beta=3, alpha-beta=1", "α = 2, β = 1")
expect("v=omega*r", nil)
expect("3mu=6", "μ = 2")
expect("3μ=6", "μ = 2")
expect(#"\mu=0.5*2"#, "μ = 1")

// A subscript makes a letter of its own, and ° or deg an angle in degrees
expect("F_n=0.4*20cos(35°)", "F_n ≈ 6.55322")
expect("F_n=0.4*20cos(35deg)", "F_n ≈ 6.55322")
expect("F_n=0.4*20cos(35)", "F_n ≈ −7.22954")
expect("F_n=0.4*20cos(35 rad)", "F_n ≈ −7.22954")
expect("20=F_n*2", "F_n = 10")
expect(#"F_{net}=2*3"#, "F_net = 6")
expect("mu_k=6/20", "μ_k = 3/10", "≈ 0.3")
expect("x_1+x_2=3, x_1-x_2=1", "x_1 = 2, x_2 = 1")
expect("v_y=3-g*2", "v_y ≈ −16.6", "Taking g = 9.8 m s⁻²")
expect("v_0t=10", "Insufficient information", "A value is required for v_0 or t.")
expect("x_1=10", "x_1 = 10")
expect("theta=30", "θ = 30")
expect("x=10", nil)
expect("x_=3", nil)
expect("sin(30°)=0.5", "True", "0.5 = 0.5")

// Factorials
expect("x=5!", "x = 120")
expect("x=5!/(3!2!)", "x = 10")
expect(#"x=\frac{10!}{7!3!}"#, "x = 120")
expect("x=2^3!", "x = 64")
expect("x=-3!", "x = −6")
expect("n!=120", "n = 5")
expect("n!=1", "n = 0, 1")
expect("x=(-2)!", "Undefined", "It has no real value.")

// Repeated roots
expect("x^3-3x^2+3x-1=0", "x = 1")
expect("(x-1)^2(x+2)=0", "x = −2, 1")

// Numbers alone on both sides are compared: = exactly, ≈ to a tenth of a percent
expect("2=2", "True", "2 = 2")
expect("2^2=4", "True", "4 = 4")
expect("0.1+0.2=0.3", "True", "0.3 = 0.3")
expect("1/3 = 0.3333", "False", "0.333333 > 0.3333")
expect("1/3 ~= 0.3333", "True", "The two sides differ by 0.01%, which is within the tolerance of 0.1%.")
expect("1/3 ≈ 0.3", "False", "The two sides differ by 10%, which exceeds the tolerance of 0.1%.")
expect("1.6e-19 ≈ 1.7e-19", "False", approxAny: true)
expect("1e-10 ≈ 0", "True", approxAny: true)
expect("1/3 != 0.3333", "True", "0.333333 > 0.3333")
expect("2 ≠ 3", "True", "2 < 3")
expect("2 != 2", "False", "2 = 2")
expect("2!=2", "True", "2 = 2")
expect("5!=120", "True", "120 = 120")
expect("5 > 3", "True", "5 > 3")
expect("3>5", "False", "3 < 5")
expect("3 < 5", "True", "3 < 5")
expect("5 >= 5", "True", "5 = 5")
expect("4 <= 5", "True", "4 < 5")
expect("5 ≥ 5", "True", "5 = 5")
expect("4 ≤ 5", "True", "4 < 5")
expect("pi=3.14", "False", "3.14159 > 3.14")
expect("1/3=1/3+1e-7", "False", "The two sides are not equal: they differ by 1×10⁻⁷.")
expect(#"\frac{1}{3} \approx 0.3333"#, "True", approxAny: true)
expect(#"2^{10} \ge 1000"#, "True", "1024 > 1000")
// A chain holds where each of its links does, as in mathematics: 1 > 1 > 1 is 1 > 1 and 1 > 1.
expect("1<2<3", "True", "1 < 2 is True; 2 < 3 is True.")
expect("2=2=2", "True", "2 = 2 is True; 2 = 2 is True.")
expect("0=0=0", "True", "0 = 0 is True; 0 = 0 is True.")
expect("2=2=3", "False", "2 = 2 is True; 2 = 3 is False.")
expect("1>1>1", "False", "1 > 1 is False; 1 > 1 is False.")
expect("1+1=2=4/2", "True", "1 + 1 = 2 is True; 2 = 4/2 is True.")
expect("1<2<=3", "True", "1 < 2 is True; 2 ≤ 3 is True.")
// A statement in brackets used as a number is 1 or 0; without brackets, the same is a chain.
expect("(0=0)=0", "False", approxAny: true)
expect("(0=0)=1", "True", approxAny: true)
expect("(1>1)=0", "True", approxAny: true)
expect("(2<3)+5", "= 6")
expect("((0=0)=0)=0", "True", approxAny: true)
expect("(x=2)=1", nil)
// Brackets round statements joined by && or ||, or after !, are statements still.
expect("!(3=1)", "True", approxAny: true)
expect("(1=1) && (2=3)", "False", approxAny: true)
if Solver.details("(0=0)=0")?.steps.first?.note != "(0 = 0) is True, taken as 1. A true statement counts as 1, and a false one as 0." {
    failures += 1; print("FAIL (0=0)=0: the working does not begin by taking (0 = 0) as 1")
}
expect("x>3", nil)
expect("g=9.8", nil)
expect("1/0=1", nil)

// Digests, of the text as typed; in hexadecimal they are not numbers to do sums with
expect(#"SHA256("hello")"#, "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824", "SHA-256 digest of 5 bytes, in hexadecimal")
expect(#"sha256("hello")"#, "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824", approxAny: true)
expect("Sha256(hello)", "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824", approxAny: true)
expect(#"sha256("")"#, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "SHA-256 digest of 0 bytes, in hexadecimal")
expect(#"sha256("abc")"#, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", approxAny: true)
expect(#"SHA1("hello")"#, "aaf4c61ddcc5e8a2dabede0f3b482cd9aea9434d", "SHA-1 digest of 5 bytes, in hexadecimal")
expect(#"sha256("hello", decimal)"#, "20329878786436204988385760252021328656300425018755239228739303522659023427620", "SHA-256 digest of 5 bytes, in decimal")
expect(#"sha1("hello", binary)"#, "101010101111010011000110000111011101110011000101…", "SHA-1 digest of 5 bytes, in binary")
expect(#"sha256("a, b")"#, "4a479db6af79906e7200f9560d9af890f0077e394e3ae44cbd2a2bb3ba5c2c2d", "SHA-256 digest of 4 bytes, in hexadecimal")
expect(#"sha256("f(x) = 1")"#, "44daafd1796bff53b436eef5ef7b02b05ad41dd04e12ab3846978b49c9afe270", approxAny: true)
expect(#"sha256(2+2)"#, "1acf86226c68c1485ca3939884c43ed99abeea344e806548af7ee813c1c0cff3", approxAny: true)
expect(#"sha256("hello")+1"#, nil)
expect(#"x=sha256("hello")"#, nil)
expect(#"sha256("hello", decimal)/10^76"#, "≈ 2.03299")
expect(#"x=sha256("hello", binary)/sha256("hello", decimal)"#, "x = 1")
expect(#"sha256("hello""#, nil)

// Letters with no = are tidied: like terms collected, and what is common to them taken out
expect("xb+xc", "= x(b + c)")
expect("2x+3x", "= 5x")
expect("x+x", "= 2x")
expect("2x+4", "= 2(x + 2)")
expect("x^2+x", "= x(x + 1)")
expect("ab+ba", "= 2ab")
expect("2x+3x+y", "= 5x + y")
expect("3ab-ab+2b", "= 2b(a + 1)")
expect("6x^2y+9xy^2", "= 3xy(2x + 3y)")
expect("2(x+1)+3(x+1)", "= 5(x + 1)")
expect("-2x-4", "= −2(x + 2)")
expect("x/2+x/2", "= x")
expect("theta+2theta", "= 3θ")
expect("2x*3x", "= 6x²")
expect("(m^4*q^4*z^-1)(mq^5*z^3)", "= m⁵q⁹z²")
expect("x^3/x", "= x²")
expect("6x^2y/(3x)", "= 2xy")
expect("2x/y+3x/y", "= 5x/y")
expect("a^2b^-1*b^3", "= a²b²")
// Nothing where there is nothing simpler to say, or it is not algebra at all
expect("a+b", nil)
expect("x(b+c)", nil)
expect("(a+b)^2", "= a² + 2ab + b²")
// A polynomial in one letter that factorises is factorised; one that does not, x² + 1, shows nothing.
expect("x^2-5x+6", "= (x − 2)(x − 3)", "Factorised")
expect("x^6-7x^4+14x^2-8", "= (x + 2)(x + 1)(x − 1)(x − 2)(x² − 2)", "Factorised")
expect("2x^2-8", "= 2(x + 2)(x − 2)", "Factorised")
expect("x^2+1", nil)
expect("x^2", nil)
expect("ab+ac+d", nil)
expect("wi-fi", nil)
expect("rock+roll", nil)
expect("c++", nil)
expect("2x+3x=10", "x = 2")

// A formula turned round to give one letter: x, or the one asked for with "x=?"
expect(#"\frac{1}{7b}=\frac{11x}{y}"#, "x = y/(77b)")
expect("\\frac{1}{7b}=\\frac{11x}{y}\nx=?", "x = y/(77b)")
expect(#"\frac{1}{7b}=\frac{11x}{y}, y=?"#, "y = 77bx")
expect("x+y=3", "x = 3 − y")
expect("ax+bx=c", "x = c/(a + b)")
expect("F=ma, a=?", "a = F/m")
expect("v=u+at, t=?", "t = (v − u)/a")
expect("1/f=1/u+1/v, f=?", "f = uv/(v + u)")
expect("E=1/2mv^2, v=?", "v = ±√(2E/m)")
expect("PV=nRT, T=?", "T = PV/(nR)")
expect("2x+3=11, x=?", "x = 4")
expect("ax^2+bx=c", "Insufficient information", "Values are required for two of a, x and b.")
expect("F=ma, z=?", nil)

// A number by itself: its primes, or that it is one; a decimal as a fraction
expect("2048", "2048 = 2¹¹")
expect("360", "360 = 2³·3²·5")
expect("144", "144 = 2⁴·3²", "= 12²")
expect("1296", "1296 = 2⁴·3⁴", "= 6⁴")
expect("97", "97 is prime")
expect("2", "2 is prime")
expect("2024", "2024 = 2³·11·23")
expect("999999999989", "999999999989 is prime")
expect("0.375", "0.375 = 3/8")
expect("2.50", "2.50 = 5/2")
expect("3.0", nil)
// Found by a stress test, 2026-11-10: each stopped the app, gave a wrong answer, or took seconds.
expect("lcm(10000000000,10000000001)", "= 100000000010000000000", approxAny: true)
expect("lcm(99999999999999,100000000000000)", "= 9999999999999900000000000000", approxAny: true)
expect(#"\operatorname{lcm}(10000000000,10000000001)"#, "= 100000000010000000000", approxAny: true)
expect("root(-8,1e20)", "Undefined", approxAny: true)
expect("root(-8,1e309)", "Undefined", approxAny: true)
expect(#"\sqrt[3]{-8}"#, "= −2")
expect(#"\sqrt[5]{-32}"#, "= −2")
expect("root(-8,3)", "= −2")
expect(#"1+2+\cdots+100"#, "= 5050", approxAny: true)
expect(#"1+2+\ldots+100"#, "= 5050", approxAny: true)
expect(#"\int_{-1}^{1}\frac{1}{x^2}dx"#, "Does not converge", approxAny: true)
expect("integrate(1/x,-1,1)", "Does not converge", approxAny: true)
expect("integrate(1/sqrt(x),0,1)", "= 2", approxAny: true)
expect("integrate(1/x^2,1,2)", "= 1/2", approxAny: true)
expect("binomcdf(999999999,0.5,999999999)", "= 1", approxAny: true)
expect("poissoncdf(1,999999999)", "= 1", approxAny: true)
expect("poissonpdf(0,0)", "= 1", approxAny: true)
expect("poissoncdf(0,5)", "= 1", approxAny: true)
expect("mean(1e308,1e308)", "= 1×10³⁰⁸", approxAny: true)
expect("hypot(1e308,1e308)", "≈ 1.41421×10³⁰⁸", approxAny: true)
expect("rms(1e308,1e308)", "= 1×10³⁰⁸", approxAny: true)
expect("-5", "−5 = −1·5")
expect("-12", "−12 = −1·2²·3")
expect("-1.5", "−1.5 = −3/2")
expect("0", "0 is neither prime nor composite", "Every whole number divides it")
expect("1", "1 is neither prime nor composite", "Its only divisor is 1")
expect("-1", "−1 is neither prime nor composite", "Its only divisors are 1 and −1")
expect("1e6", "= 1000000")

// Arithmetic with no = is worked out as it stands
expect("2+2", "= 4")
expect("10/4", "= 5/2", "≈ 2.5")
expect("2^10", "= 1024")
expect("5!/(3!2!)", "= 10")
expect("sqrt(2)", "≈ 1.41421")
expect("2pi", "≈ 6.28319")
expect("sin(30°)", "= 1/2", "≈ 0.5")
expect("1.6e-19*2", "= 3.2×10⁻¹⁹")
expect("2+", nil)
expect("2026 10", nil)
expect("(2+3", nil)

// A name and some arithmetic is a value to work out
expect("cost=12*3+4", "cost = 40")
expect("r=22/7", "r = 22/7", "≈ 3.14286")
expect("a=1", nil)
expect("a=b", nil)
expect("sin=2", nil)

// Not equations, or not one unknown: Spotlight's own results are left alone
expect("hello", nil)
expect("2048 report", nil)
expect("pie", nil)
expect("c", nil)
expect("5g", nil)
expect("F=ma", nil)
expect("y=mx+b", nil)
expect("weather today", nil)
expect("a=b", nil)
expect("x=", nil)
expect("=3", nil)
expect("x==3", nil)
expect("2x+", nil)
expect("x^2=4 apple", nil)

// Solved directly where there is a formula for it: the search only reaches ±1000
expect("log(n)=5", "n = 100000")
expect("ln(x)=10", "x ≈ 22026.5")
expect("sqrt(x)=50", "x = 2500")
expect("log(n)=499", "n = 10⁴⁹⁹", "Too large to be written out as a decimal.")
expect("log(x)=-400", "x = 10^−400", "Too small to be written out as a decimal.")
expect("ln(x)=800", "x = e⁸⁰⁰", "Too large to be written out as a decimal.")

// ans, the answer before, and clip, the number on the clipboard
expect("ans*2", nil)
expect("20*clip", nil)
Memory.answers = [40]
Memory.clip = 9.81
expect("ans*2", "= 80", "Taking ans = 40")
expect("ans", "= 40", "Taking ans = 40")
expect("Ans+1", "= 41", "Taking ans = 40")
expect("x=ans/3", "x ≈ 13.3333", "Taking ans = 40")
expect("20*clip", "≈ 196.2", "Taking clip = 9.81")
expect("2x=ans", "x = 20", "Taking ans = 40")
expect("h=0.5clip*3^2", "h ≈ 44.145", "Taking clip = 9.81")
expect("ans=40", "True", "40 = 40")
expectDetails("ans*2+1", "ans·2 + 1", [("Substituting ans = 40", "= 40·2 + 1"),
               ("Multiplying", "= 80 + 1"),
               ("Adding", "= 81")], ["= 81"])
if Solver.values("12*3+4") != [40] || Solver.values("2x=10") != [5] || Solver.values("x^2=4") != [-2, 2]
    || Solver.values("2048") != [] || Solver.values("xb+xc") != [] || Solver.values("x^2-5x+6=0") != [2, 3] {
    failures += 1
    print("FAIL the values an answer leaves for ans")
}
// After several answers ans is no one number: ans1 and ans2 are
Memory.answers = [2, 3]
expect("ans*2", "ans has 2 values", "Write ans1 = 2, ans2 = 3.")
expect("ans1*2", "= 4", "Taking ans_1 = 2")
expect("ans2+ans1", "= 5", "Taking ans_2 = 3, ans_1 = 2")
expect("x=10ans2", "x = 30", "Taking ans_2 = 3")
expect("ans3", nil)
Memory.answers = []
Memory.clip = nil

// What the settings change. (Each is put back as it was.)
func with(_ key: String, _ value: Any, _ body: () -> Void) {
    UserDefaults.standard.set(value, forKey: key)
    body()
    UserDefaults.standard.removeObject(forKey: key)
}
with("degrees", true) {
    expect("sin(x)=0.5", "x = 30°, 150°", "= π/6, 5π/6 rad, for 0° ≤ x ≤ 360°")
    expect("sin(x rad)=0.5", "x = π/6, 5π/6", approxAny: true)
    expect("sin(pi/6)=0.5", "True", "0.5 = 0.5")
    expect("F_n=0.4*20cos(35)", "F_n ≈ 6.55322")
    expect("x=asin(0.5)", "x = 30°", "= π/6 rad")
    expect("x=asin(0.5) rad", "x = π/6", "= 30°")
}
with("constant.g", false) {
    expect("x=2g", "Insufficient information", "A value is required for x or g.")
    expect("2g=10", "g = 5")
    expect("E=0.002c^2", "E = 1.8×10¹⁴", "Taking c = 3.00×10⁸ m s⁻¹")
}
with("constant.c", false) {
    expect("9e16=!c^2", nil)
    expect("x=2g", "x ≈ 19.6", "Taking g = 9.8 m s⁻²")
}
with("precise", true) {
    expect("x=2g", "x ≈ 19.6133", "Taking g = 9.80665 m s⁻²")
    expect("E=0.002c^2", "E ≈ 1.79751×10¹⁴", "Taking c = 299 792 458 m s⁻¹")
}
// A value typed in the settings for g, as 10 is in many a question; the others are as before
with("constantValue.g", 10.0) {
    expect("x=2g", "x = 20", "Taking g = 10 m s⁻²")
    expect("h=0.5g*3^2", "h = 45", "Taking g = 10 m s⁻²")
    expect("20=0.5g*t^2", "t = ±2", "Taking g = 10 m s⁻²")
    expect("2g=10", "g = 5")
    expect("!g=10", "True", "10 = 10")
    expect("E=0.002c^2", "E = 1.8×10¹⁴", "Taking c = 3.00×10⁸ m s⁻¹")
    with("precise", true) { expect("x=2g", "x = 20", "Taking g = 10 m s⁻²") }
    with("constant.g", false) { expect("x=2g", "Insufficient information", "A value is required for x or g.") }
}
with("constantValue.g", 9.81) { expect("x=2g", "x ≈ 19.62", "Taking g = 9.81 m s⁻²") }
with("constantValue.c", 3e8) { expect("E=0.002c^2", "E = 1.8×10¹⁴", "Taking c = 3×10⁸ m s⁻¹") }
with("constantValue.G", 6.674e-11) { expect("F=G*5*6/2^2", "F = 5.0055×10⁻¹⁰", "Taking G = 6.674×10⁻¹¹ N m² kg⁻²") }

// Constants added in the settings are used as g is
Constants.custom = [Constants.Custom(name: "R", value: 8.314, unit: "J K⁻¹ mol⁻¹"),
                    Constants.Custom(name: "k_e", value: 8.99e9, unit: "N m² C⁻²"),
                    Constants.Custom(name: "μ_0", value: 4e-7 * .pi, unit: "T m A⁻¹"),
                    Constants.Custom(name: "h", value: 6.63e-34)]
expect("PV=nRT, P=2, V=3, n=1", "T ≈ 0.721674", "Taking P = 2, V = 3, n = 1, R = 8.314 J K⁻¹ mol⁻¹")
expect("F=k_e*2*3/4^2", "F = 3371250000", "Taking k_e = 8.99×10⁹ N m² C⁻²")
expect("B=mu_0*2/(2pi*0.1)", "B ≈ 0.000004", "Taking μ_0 = 1.25664×10⁻⁶ T m A⁻¹")
expect("E=h*5e14", "E = 3.315×10⁻¹⁹", "Taking h = 6.63×10⁻³⁴")
expect("2R=10", "R = 5")
expect("!R=8.314", "True", "8.314 = 8.314")
expect("8.314=!R*x", nil)
expect("R=2*!k_e", "k_e ≈ 4.157", "Taking R = 8.314 J K⁻¹ mol⁻¹")
expect("R=2*!mu_0", "μ_0 ≈ 4.157", approxAny: true)
expect("x=2k_e", "x = 1.798×10¹⁰", "Taking k_e = 8.99×10⁹ N m² C⁻²")
expect("x=2k", "Insufficient information", "A value is required for x or k.")
Constants.custom[0].off = true
expect("x=2R", "Insufficient information", "A value is required for x or R.")
expect("2R=10", "R = 5")
Constants.custom[0].off = nil
for (typed, want) in [("R", "R"), ("k_e", "k_e"), ("mu_0", "μ_0"), ("epsilon_0", "ε_0"), ("sigma", "σ"), (" N_A ", "N_A")] {
    if (try? Constants.letter(typed).get()) != want { failures += 1; print("FAIL letter \(typed)") }
}
for (typed, want) in [("8.314", 8.314), ("6.022*10^23", 6.022e23), ("8.99e9", 8.99e9), ("1/(4pi*8.85e-12)", 1 / (4 * .pi * 8.85e-12))] {
    if abs((Constants.number(typed) ?? 0) / want - 1) > 1e-12 { failures += 1; print("FAIL number \(typed)") }
}
for typed in ["", "x", "R", "2+"] where Constants.number(typed) != nil { failures += 1; print("FAIL number \(typed) should be refused") }
for typed in ["", "ab", "e", "i", "g", "G", "c", "x", "pi", "sin", "2", "k_"] {
    if (try? Constants.letter(typed).get()) != nil { failures += 1; print("FAIL letter \(typed) should be refused") }
}
Constants.custom = []
expect("x=2R", "Insufficient information", "A value is required for x or R.")
expect("h=0.5g*3^2", "h ≈ 44.1", "Taking g = 9.8 m s⁻²")

with("figures", 3) {
    expect("x=1/3", "x = 1/3", "≈ 0.333")
    expect("2n^2=10", "n = ±√5", "≈ ±2.24")
    expect("F=G*5.97e24*70/6.37e6^2", "F ≈ 687", "Taking G = 6.67×10⁻¹¹ N m² kg⁻²")
}
with("figures", 10) {
    expect("x=1/3", "x = 1/3", "≈ 0.3333333333")
}
with("exact", false) {
    expect("10/4", "= 2.5")
    expect("x=1/3", "x ≈ 0.333333")
    expect("2x=1", "x ≈ 0.5")
    expect("2n^2=10", "n ≈ ±2.23607")
    expect("x^2-5x+6=0", "x = 2, 3")
    expect("sin(x)=0.5", "x ≈ 0.523599, 2.61799", "= 30°, 150°, for 0 ≤ x ≤ 2π")
    expect("2x+3y=12, 5x-y=7", "x = 1.94118, y = 2.70588")
}
with("arithmetic", false) {
    expect("2+2", nil)
    expect("x=2+2", "x = 4")
    expect("2x=4", "x = 2")
}
with("copyAsShown", true) {
    expectCopy("10/4", "5/2")
    expectCopy("4x=10", "5/2")
    expectCopy("2n^2=10", "±√5")
    expectCopy("2x+y=5, x-y=1", "x = 2, y = 1")
}
expect("sin(x)=0.5", "x = π/6, 5π/6", approxAny: true)
expect("x=2g", "x ≈ 19.6", "Taking g = 9.8 m s⁻²")

// What is copied: the answer as a number another program can read
func expectCopy(_ input: String, _ want: String?) {
    let got = Solver.copy(input)
    if got != want { failures += 1; print("FAIL copy \(input)\n  want \(want ?? "nil")\n  got  \(got ?? "nil")") }
}
expectCopy("12*3+4", "40")
expectCopy("10/4", "2.5")
expectCopy("cost=10/4", "2.5")
expectCopy("2x+3=11", "4")
expectCopy("4x=10", "2.5")
expectCopy("x^2-5x+6=0", "2, 3")
expectCopy("2n^2=10", "-2.2360679775, 2.2360679775")
expectCopy("x=1.6e-19*2", "3.2e-19")
expectCopy("h=0.5g*3^2", "44.1")
expectCopy("sin(x deg)=0.5", "30, 150")
expectCopy("log(n)=5", "100000")
expectCopy("log(n)=499", "n = 10⁴⁹⁹")
expectCopy("2x+y=5, x-y=1", "x = 2, y = 1")
expectCopy("1/3 ~= 0.3333", "True")
expectCopy(#"SHA1("hello")"#, "aaf4c61ddcc5e8a2dabede0f3b482cd9aea9434d")
expectCopy("2048", nil)
expectCopy("xb+xc", "x(b + c)")
expectCopy("hello", nil)

// What the card opens into: the equation typeset, the key steps, and every solution.
// Steps compare as (label, the maths on one line, or the note when the step has no maths).
func expectDetails(_ input: String, _ equation: String, _ steps: [(String, String)], _ solutions: [String]? = nil, note: String? = nil) {
    guard let d = Solver.details(input) else { failures += 1; print("FAIL \(input): no details"); return }
    let got = d.steps.map { "\($0.label): \($0.math?.plain ?? $0.note ?? "")" }
    let want = steps.map { "\($0.0): \($0.1)" }
    let gotSolutions = d.solutions.map(\.plain)
    if d.equation.plain != equation || got != want || (solutions != nil && gotSolutions != solutions!) || (note != nil && d.note != note) {
        failures += 1
        print("FAIL details \(input)\n  want \(equation) \(want) \(solutions ?? []) \(note ?? "")\n  got  \(d.equation.plain) \(got) \(gotSolutions) \(d.note ?? "")")
    }
}

expectDetails("factor(2x^2+3x-2)", "2x² + 3x − 2",
              [("Finding two numbers with product ac and sum b", "ac = −4,  b = 3:  4 and −1"),
               ("Splitting the middle term", "2x² + 4x − x − 2"),
               ("Grouping in pairs", "2x(x + 2) − (x + 2)"),
               ("Taking out the common factor (x + 2)", "(x + 2)(2x − 1)")],
              ["(x + 2)(2x − 1)"])
expectDetails("factor(4x^2+6x-4)", "4x² + 6x − 4",
              [("Taking out the common factor", "2 × (2x² + 3x − 2)"),
               ("Finding two numbers with product ac and sum b", "ac = −4,  b = 3:  4 and −1"),
               ("Splitting the middle term", "2x² + 4x − x − 2"),
               ("Grouping in pairs", "2x(x + 2) − (x + 2)"),
               ("Taking out the common factor (x + 2)", "2(x + 2)(2x − 1)")],
              ["2(x + 2)(2x − 1)"])
// Drawn as written: a matrix as one, an integral with its limits on the sign, a root as a root.
// Matrices given by name before the question, as on paper, and in LaTeX; names side by side multiply.
expect(#"A=\begin{pmatrix}2&3\\1&4\end{pmatrix},\ B=\begin{pmatrix}1&5\\2&3\end{pmatrix},\ A+B=?"#, "[[3, 8], [3, 7]]")
expect("A = [[2,3],[1,4]], B = [[1,5],[2,3]], A + B = ?", "[[3, 8], [3, 7]]")
expect("A=[[2,3],[1,4]], B=[[1,5],[2,3]], AB", "[[8, 19], [9, 17]]")
expect("A=[[2,3],[1,4]], B=[[1,5],[2,3]], BA=?", "[[7, 23], [7, 18]]")
expect("A=[[2,3],[1,4]], 2A=?", "[[4, 6], [2, 8]]")
expect("A=[[2,3],[1,4]], B=[[1,5],[2,3]], 3AB - B", "[[23, 52], [25, 48]]")
expect("A=[[2,3],[1,4]], det(A)", "= 5")
expect("u=[1,2,3], v=[4,5,6], dot(u,v)", "= 32")
expect("A+B, A=[[2,3],[1,4]], B=[[1,5],[2,3]]", "[[3, 8], [3, 7]]")
// The question after the values, ranges and names it needs reads as it does before them.
for (first, after) in [("mg*1.2+1/2mv^2, m=55, v=0.9", "m=55, v=0.9, mg*1.2+1/2mv^2=?"), ("F=ma, a=?", "a=?, F=ma"),
                       ("sin(x)=0.5, 0<=x<360°", "0<=x<360°, sin(x)=0.5"), ("v=u+at, u=2, a=3, t=4", "u=2, a=3, t=4, v=u+at"),
                       ("x+y, x=2, y=3", "x=2, y=3, x+y=?"), ("12=1.8+4vcos(theta), theta=30°", "theta=30°, 12=1.8+4vcos(theta)")] {
    let (a, b) = (Solver.solve(first), Solver.solve(after))
    if a == nil || a?.exact != b?.exact || a?.approx != b?.approx { failures += 1; print("FAIL \(after): \(b?.exact ?? "nil"), but \(first): \(a?.exact ?? "nil")") }
}
// Found by the second stress test, 2026-11-10: each stopped the app, took seconds, or showed no value as one.
expect("u_1=1,d=1,u_9223372036854775808=?", nil)
expect("u_{1}=1,d=1,u_{9223372036854775808}=?", nil)
expect("u_1=1,u_3=1,S_1000000000=?", "Arithmetic: S_1000000000 = 1×10⁹", "Geometric: S_1000000000 = 1×10⁹ or 0")
expect("u_1=1,u_3=4,S_1000000000=?", "Arithmetic: S_1000000000 = 7.5×10¹⁷", "Geometric: S_1000000000 is beyond the largest number that can be held")
expect(String(repeating: "1+", count: 8192) + "1", nil)
expect(String(repeating: "1+", count: 499) + "1", "= 500")
if (Solver.details(String(repeating: "1+", count: 499) + "1")?.steps.count ?? 99) > 41 { failures += 1; print("FAIL a 500-term sum: the working was not cut short") }
expect(String(repeating: #"\sqrt{"#, count: 61) + "2" + String(repeating: "}", count: 61), nil)
expect("integrate(1/(x-0.999999),-1,1)", "Does not converge", approxAny: true)
expect(#"\int_{-1}^{1}\frac{1}{x-0.999999}dx"#, "Does not converge", approxAny: true)
expect("integrate(1/(x-0.999999)^2,-1,1)", "Does not converge", approxAny: true)
expect("integrate(1/x,-1,-1e-300)", "≈ −690.776", approxAny: true)
expect("[1,2]/0", "Undefined", "A vector or a matrix cannot be divided by zero.")
expect("[0,0]/0", "Undefined", "A vector or a matrix cannot be divided by zero.")
expect("[[1,2],[3,4]]/0", "Undefined", "A vector or a matrix cannot be divided by zero.")
expect("[1e308,1]*10", "Undefined", "Its entries are beyond the largest number that can be held, about 1.8×10³⁰⁸.")
// The card's sign says what kind of answer it is.
for (typed, sign) in [("2+2", "plus.forwardslash.minus"), ("12", "number"), ("x^2-5x+6=0", "x.squareroot"), ("x^2>4", "lessthan"), ("derivative(x^3)", "function"),
                      ("integrate(x^2,0,1)", "function"), ("factor(x^2-5x+6)", "parentheses"), ("expand((x+1)^2)", "parentheses"),
                      ("det([[1,2],[3,4]])", "square.grid.3x3"), ("u_1=2,d=3,u_10=?", "list.number"), ("5 km to miles", "arrow.left.arrow.right"),
                      ("2=2", "checkmark.circle"), ("2=3", "xmark.circle"), ("/usr/bin", "folder"), ("/bin/ls", "doc"), ("x+y=3, x-y=1", "x.squareroot")] {
    if Solver.answer(typed)?.symbol != sign { failures += 1; print("FAIL \(typed): sign \(Solver.answer(typed)?.symbol ?? "nil"), not \(sign)") }
}
expectDetails("inv([[1,2],[3,4]])", "[[1, 2], [3, 4]]^−1", [("Finding the determinant", "det = 1×4 − 2×3 = −2"),
               ("Swapping the diagonal and changing the signs of the others", "[[4, −2], [−3, 1]]"),
               ("Dividing every entry by the determinant", "[[−2, 1], [3/2, −1/2]]")],
              ["[[−2, 1], [3/2, −1/2]]"])
for (typed, shown) in [("integrate(x^2+1, 0, pi/2)", "∫(0…π/2) (x² + 1) dx"), (#"\sqrt[3]{x}=2"#, "∛x = 2"), ("root(x,3)=2", "∛x = 2"),
                       ("x^(1/3)=2", "∛x = 2"), ("det([[1,2],[3,4]])", "det [[1, 2], [3, 4]]")] {
    if Solver.details(typed)?.equation.plain != shown { failures += 1; print("FAIL \(typed): drawn as \(Solver.details(typed)?.equation.plain ?? "nil")") }
}
expectDetails("-12", "−12", [("Taking out −1", "−12 = −1·12"),
               ("Dividing by 2 repeatedly", "12 = 2²·3")], ["−12 = −1·2²·3"])
expectDetails("4/2", "4/2", [("Reducing the fraction", "= 2")], ["= 2"])
expectDetails("2n^2+3n+1=0", "2n² + 3n + 1 = 0", [("Finding two numbers with product ac and sum b", "ac = 2,  b = 3:  2 and 1"),
               ("Splitting the middle term", "2n² + 2n + n + 1 = 0"),
               ("Grouping in pairs", "2n(n + 1) + (n + 1) = 0"),
               ("Factorising", "(n + 1)(2n + 1) = 0"),
               ("Zero-product property", "n + 1 = 0 or 2n + 1 = 0"),
               ("Solving each linear factor", "n = −1 or n = −1/2")],
              ["n = −1", "n = −1/2 ≈ −0.5"])
expectDetails("2x+3=11", "2x + 3 = 11", [("Subtracting 3 on both sides", "2x = 8"),
               ("Dividing both sides by 2", "x = 8/2 = 4")], ["x = 4"])
expectDetails("3x=2", "3x = 2", [("Dividing both sides by 3", "x = 2/3")], ["x = 2/3 ≈ 0.666667"])
expectDetails("2n^2=10", "2n² = 10", [("Subtracting the right-hand side from both sides", "2n² − (10) = 0"),
               ("Collecting like terms", "2n² − 10 = 0"),
               ("Multiplying both sides by 1/2", "n² − 5 = 0"),
               ("Isolating n²", "n² = 5"),
               ("Taking the square root", "n = ±√5")],
              ["n = −√5 ≈ −2.23607", "n = √5 ≈ 2.23607"])
expectDetails("2x^2+3x-1=0", "2x² + 3x − 1 = 0", [("Identifying the quadratic coefficients", "a = 2,  b = 3,  c = −1"),
               ("Evaluating the discriminant", "b² − 4ac = 3² − 4·2·(−1) = 17"),
               ("Quadratic formula", "x = (−b ± √(b² − 4ac))/2a"),
               ("Substituting the coefficients and discriminant", "x = (−3 ± √17)/4")],
              ["x = (−3 − √17)/4 ≈ −1.78078", "x = (−3 + √17)/4 ≈ 0.280776"])
expectDetails("x^2+2x+5=0", "x² + 2x + 5 = 0", [("Identifying the quadratic coefficients", "a = 1,  b = 2,  c = 5"),
               ("Evaluating the discriminant", "b² − 4ac = 2² − 4·1·5 = −16"),
               ("Hence", "b² − 4ac < 0")],
              ["x = −1 ± 2i", "No real solutions"])
expectDetails("x^2-2x+1=0", "x² − 2x + 1 = 0", [("Finding two numbers with product ac and sum b", "ac = 1,  b = −2:  −1 and −1"),
               ("Splitting the middle term", "x² − x − x + 1 = 0"),
               ("Grouping in pairs", "x(x − 1) − (x − 1) = 0"),
               ("Factorising", "(x − 1)² = 0"),
               ("Zero-product property", "x − 1 = 0"),
               ("Solving each linear factor", "x = 1")], ["x = 1"])
expectDetails("(x+1)(x-1)=3", "(x + 1)(x − 1) = 3", [("Expanding brackets and collecting like terms", "x² − 1 = 3"),
               ("Subtracting the right-hand side from both sides", "x² − 1 − (3) = 0"),
               ("Collecting like terms", "x² − 4 = 0"),
               ("Finding two numbers with product ac and sum b", "ac = −4,  b = 0:  2 and −2"),
               ("Splitting the middle term", "x² + 2x − 2x − 4 = 0"),
               ("Grouping in pairs", "x(x + 2) − 2(x + 2) = 0"),
               ("Factorising", "(x + 2)(x − 2) = 0"),
               ("Zero-product property", "x + 2 = 0 or x − 2 = 0"),
               ("Solving each linear factor", "x = −2 or x = 2")])
expectDetails("x^3-6x^2+11x-6=0", "x³ − 6x² + 11x − 6 = 0", [("Factorising", "(x − 1)(x − 2)(x − 3) = 0")], ["x = 1", "x = 2", "x = 3"])
expectDetails("x^3=2", "x³ = 2", [("Subtracting the right-hand side from both sides", "x³ − (2) = 0"),
               ("Collecting like terms", "x³ − 2 = 0"),
               ("Solving numerically", "This polynomial of degree 3 is not readily factorised; its real roots are therefore determined numerically.")], ["x ≈ 1.25992"])
expectDetails("sin(n rad)=1", "sin(n) = 1", [("Stating the general solution", "n = π/2 + 2kπ, k ∈ ℤ")], ["n = π/2 ≈ 1.571 (90°)"],
              note: "These are the solutions for 0 ≤ n ≤ 2π; further solutions lie outside this interval.")
expectDetails("sin(x rad)=0.5", "sin(x) = 0.5", [("Stating the general solution", "x = π/6 + 2kπ or x = 5π/6 + 2kπ, k ∈ ℤ")],
              ["x = π/6 ≈ 0.524 (30°)", "x = 5π/6 ≈ 2.618 (150°)"])
expectDetails("(20^2*sin(2x rad))/9.81=20", "(20²·sin(2x))/9.81 = 20",
              [("Isolating sin(2x)", "sin(2x) = 0.4905"),
               ("Stating the general solution", "2x = 0.512663 + 2kπ or 2x = 2.62893 + 2kπ, k ∈ ℤ"),
               ("Hence", "x = 0.256332 + kπ or x = 1.31446 + kπ, k ∈ ℤ")],
              ["x ≈ 0.256332 (14.6867°)", "x ≈ 1.31446 (75.3133°)", "x ≈ 3.39792 (194.687°)", "x ≈ 4.45606 (255.313°)"])
expectDetails("(20^2*sin(2x rad))/g=20", "(20²·sin(2x))/g = 20", [("Substituting g = 9.8 m s⁻²", "(20²·sin(2x))/9.8 = 20"),
               ("Isolating sin(2x)", "sin(2x) = 0.49"),
               ("Stating the general solution", "2x = 0.51209 + 2kπ or 2x = 2.6295 + 2kπ, k ∈ ℤ"),
               ("Hence", "x = 0.256045 + kπ or x = 1.31475 + kπ, k ∈ ℤ")])
expectDetails("2sin(3x+1 rad)-1=0", "2sin(3x + 1) − 1 = 0",
              [("Isolating sin(3x + 1)", "sin(3x + 1) = 0.5"),
               ("Stating the general solution", "3x + 1 = π/6 + 2kπ or 3x + 1 = 5π/6 + 2kπ, k ∈ ℤ"),
               ("Hence", "x = −0.1588 + 2kπ/3 or x = 0.539331 + 2kπ/3, k ∈ ℤ")])
expectDetails("tan(x/2 rad)=1", "tan(x/2) = 1", [("Stating the general solution", "x/2 = π/4 + kπ, k ∈ ℤ"),
               ("Hence", "x = π/2 + 2kπ, k ∈ ℤ")], ["x = π/2 ≈ 1.571 (90°)"])
expectDetails("cos(x rad)=0.5", "cos(x) = 0.5", [("Stating the general solution", "x = ±π/3 + 2kπ, k ∈ ℤ")])
expectDetails("tan(x rad)=1", "tan(x) = 1", [("Stating the general solution", "x = π/4 + kπ, k ∈ ℤ")])
expectDetails("sin(x rad)=2", "sin(x) = 2", [("Stating the general solution", "No solution, since −1 ≤ sin x ≤ 1")], ["No real solutions in the interval −1000 ≤ x ≤ 1000"])
expectDetails("2^x=8", "2^x = 8", [("Expressing both sides as powers of 2", "2^x = 2³"),
               ("Equating the exponents", "x = 3")], ["x = 3"])
expectDetails("10=0.1^x", "10 = 0.1^x", [("Interchanging the sides", "0.1^x = 10"),
               ("Expressing both sides as powers of 10", "(10^−1)^x = 10¹"),
               ("Multiplying the exponents", "10^−x = 10¹"),
               ("Equating the exponents", "−x = 1")], ["x = −1"])
expectDetails("4^x=8", "4^x = 8", [("Expressing both sides as powers of 2", "(2²)^x = 2³"),
               ("Multiplying the exponents", "2^(2x) = 2³"),
               ("Equating the exponents", "2x = 3"),
               ("Hence", "x = 3/2")])
expectDetails("3^x=10", "3^x = 10", [("Taking the logarithm of both sides", "ln(3^x) = ln 10"),
               ("Applying the power rule for logarithms", "x·ln 3 = ln 10"),
               ("Dividing by ln 3", "x = ln 10/ln 3")])
expectDetails("e^x=10", "e^x = 10", [("Taking the natural logarithm of both sides", "ln(e^x) = ln 10"),
               ("Simplifying", "x = ln 10")],
              ["x ≈ 2.30259"])
expectDetails("ln x=1", "ln(x) = 1", [("Rewriting in exponential form", "x = e¹")])
expectDetails("log x=2", "log(x) = 2", [("Rewriting in exponential form", "x = 10²")])
expectDetails("√x=3", "√x = 3", [("Squaring both sides", "x = 3²")], ["x = 9"])
expectDetails("x^2+sin(x rad)=1", "x² + sin(x) = 1",
              [("Solving numerically", "x² + sin(x) − 1 = 0")])
expectDetails("sin(x deg)=0.5", "sin(x°) = 0.5", [("Stating the general solution", "x = 30° + 360°k or x = 150° + 360°k, k ∈ ℤ")],
              ["x = 30° (π/6)", "x = 150° (5π/6)"], note: "These are the solutions for 0° ≤ x ≤ 360°; further solutions lie outside this interval.")
expectDetails("(20^2*sin(2x deg))/9.81=20", "(20²·sin(2x°))/9.81 = 20",
              [("Isolating sin(2x°)", "sin(2x°) = 0.4905"),
               ("Stating the general solution", "2x = 29.3735° + 360°k or 2x = 150.627° + 360°k, k ∈ ℤ"),
               ("Hence", "x = 14.6867° + 180°k or x = 75.3133° + 180°k, k ∈ ℤ")],
              ["x ≈ 14.6867° (0.256 rad)", "x ≈ 75.3133° (1.314 rad)", "x ≈ 194.687° (3.398 rad)", "x ≈ 255.313° (4.456 rad)"])
expectDetails("cos(x deg)=0.5", "cos(x°) = 0.5", [("Stating the general solution", "x = ±60° + 360°k, k ∈ ℤ")], ["x = 60° (π/3)", "x = 300° (5π/3)"])
expectDetails("F_n=0.4*20cos(35°)", "F_n = 0.4·20·cos(35°)", [("Simplifying", "F_n = 8·0.819152"),
               ("Multiplying", "F_n = 6.55322")])
expectDetails("3sin(x rad)=0", "3sin(x) = 0", [("Isolating sin(x)", "sin(x) = 0"),
               ("Stating the general solution", "x = kπ, k ∈ ℤ")],
              ["x = 0 (0°)", "x = π ≈ 3.142 (180°)", "x = 2π ≈ 6.283 (360°)"])
expectDetails("x/3+1=2", "x/3 + 1 = 2", [("Expanding brackets and collecting like terms", "1/3x + 1 = 2"),
               ("Subtracting 1 on both sides", "1/3x = 1"),
               ("Dividing both sides by 1/3", "x = 1/(1/3) = 3")])

expectDetails(#"PES=\frac{\frac{120000-80000}{80000}}{\frac{250-200}{200}}"#,
              "PES = ((120000 − 80000)/80000)/((250 − 200)/200)", [("Subtracting", "PES = (40000/80000)/((250 − 200)/200)"),
               ("Reducing the fraction", "PES = (1/2)/((250 − 200)/200)"),
               ("Subtracting", "PES = (1/2)/(50/200)"),
               ("Multiplying by the reciprocal", "PES = 1/2·4"),
               ("Multiplying the fractions", "PES = 2")],
              ["PES = 2"])
expectDetails("cost=12*3+4", "cost = 12·3 + 4", [("Multiplying", "cost = 36 + 4"),
               ("Adding", "cost = 40")])

expectDetails("F_n=20cos(60°)", "F_n = 20cos(60°)", [("Evaluating the function", "F_n = 20·0.5"),
               ("Multiplying", "F_n = 10")])

expectDetails("12*3+4", "12·3 + 4", [("Multiplying", "= 36 + 4"),
               ("Adding", "= 40")], ["= 40"])

expectDetails("360", "360", [("Dividing by 2 repeatedly", "360 = 2³·45"),
               ("Dividing by 3 repeatedly", "45 = 3²·5")],
              ["360 = 2³·3²·5"])
expectDetails("2048", "2048", [("Dividing by 2 repeatedly", "2048 = 2¹¹")], ["2048 = 2¹¹"])
expectDetails("72", "72", [("Dividing by 2 repeatedly", "72 = 2³·9"),
               ("Dividing by 3 repeatedly", "9 = 3²")])
expectDetails("97", "97", [("Testing for divisors", "97 is divisible by no prime up to its square root, 9.84886; it is therefore prime.")], ["97 is prime"])
expectDetails("0.375", "0.375", [("Writing as a fraction", "0.375 = 375/1000"),
               ("Dividing through by 125", "0.375 = 3/8")], ["0.375 = 3/8"])

if let d = Solver.details(#"sha1("hello", binary)"#) {
    let want = ["10101010 11110100 11000110 00011101 11011100 11000101 11101000 10100010",
                "11011010 10111110 11011110 00001111 00111011 01001000 00101100 11011001", "10101110 10101001 01000011 01001101"]
    let whole = "1010101011110100110001100001110111011100110001011110100010100010110110101011111011011110000011110011101101001000001011001101100110101110101010010100001101001101"
    if d.solutions.map(\.plain) != want || d.whole != whole { failures += 1; print("FAIL sha1 binary lines\n  got \(d.solutions.map(\.plain)) \(d.whole ?? "nil")") }
} else { failures += 1; print("FAIL sha1 binary: no details") }
expectDetails(#"SHA256("hello")"#, #"SHA-256("hello")"#,
              [("Encoding the message as UTF-8", "68 65 6c 6c 6f"),
               ("Applying SHA-256", "The message is padded to a multiple of 512 bits and compressed block by block, which gives a digest of 256 bits.")],
              ["2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"])

expectDetails("xb+xc", "xb + xc", [("Taking out the common factor", "= x(b + c)")], ["= x(b + c)"])
expectDetails("2x+3x", "2x + 3x", [("Collecting like terms", "= 5x")], ["= 5x"])
expectDetails("3ab-ab+2b", "3ab − ab + 2b", [("Collecting like terms", "= 2ab + 2b"),
               ("Taking out the common factor", "= 2b(a + 1)")])
expectDetails("-2x-4", "−2x − 4", [("Taking out the common factor", "= −2(x + 2)")])

expectDetails(#"\frac{1}{7b}=\frac{11x}{y}"#, "1/(7b) = 11x/y",
              [("Collecting the terms in x", "11x/y = 1/(7b)")], ["x = y/(77b)"])
expectDetails("E=1/2mv^2, v=?", "E = 1/2·mv²", [("Collecting the terms in v", "mv²/2 = E"),
               ("Isolating v²", "v² = 2E/m"),
               ("Taking the square root", "v = ±√(2E/m)")])

// A comparison: both sides worked out together, then compared
expectDetails("2^2=4", "2² = 4", [("Evaluating the power", "4 = 4")], ["True"])
expectDetails("1/3 ~= 0.3333", "1/3 ≈ 0.3333", [("Dividing", "0.333333 ≈ 0.3333"),
               ("Comparing the two sides", "0.333333 > 0.3333")], ["True"])
expectDetails("9e16=1*!c^2", "9×10¹⁶ = 1c²", [("Substituting c = 3.00×10⁸ m s⁻¹", "9×10¹⁶ = 1(3×10⁸)²"),
               ("Evaluating the power", "9×10¹⁶ = 1·9×10¹⁶"),
               ("Multiplying", "9×10¹⁶ = 9×10¹⁶")], ["True"])
expectDetails("3*4 < 2^3", "3·4 < 2³", [("Simplifying", "12 < 8"),
               ("Comparing the two sides", "12 > 8")], ["False"])
expectDetails("x=5!/(3!2!)", "x = 5!/(3!·2!)", [("Evaluating the factorials", "x = 120/(6·2)"),
               ("Multiplying", "x = 120/12"),
               ("Dividing", "x = 10")], ["x = 10"])
expectDetails("x=3!^2", "x = (3!)²", [("Evaluating the factorial", "x = 6²"),
               ("Evaluating the power", "x = 36")])
// C(n, r) and P(n, r) by the formula: the larger factorial below the line cancels, and what is
// left is multiplied out; with many factors left, the value is given straight away.
expectDetails("nCr(5,2)", "C(5, 2)", [("Applying the formula", "C(n, r) = n!/(r!(n − r)!) = 5!/(2!·3!)"),
               ("Cancelling 3!", "= (5·4)/(2·1)"),
               ("Multiplying", "= 20/2"),
               ("Dividing", "= 10")], ["= 10"])
expectDetails("5C2", "C(5, 2)", [("Applying the formula", "C(n, r) = n!/(r!(n − r)!) = 5!/(2!·3!)"),
               ("Cancelling 3!", "= (5·4)/(2·1)"),
               ("Multiplying", "= 20/2"),
               ("Dividing", "= 10")])
expectDetails("C(10,8)", "C(10, 8)", [("Applying the formula", "C(n, r) = n!/(r!(n − r)!) = 10!/(8!·2!)"),
               ("Cancelling 8!", "= (10·9)/(2·1)"),
               ("Multiplying", "= 90/2"),
               ("Dividing", "= 45")])
expectDetails("nCr(52,5)", "C(52, 5)", [("Applying the formula", "C(n, r) = n!/(r!(n − r)!) = 52!/(5!·47!)"),
               ("Cancelling 47!", "= (52·51·50·49·48)/(5·4·3·2·1)"),
               ("Multiplying", "= 311875200/120"),
               ("Dividing", "= 2598960")])
expectDetails("nCr(5,0)", "C(5, 0)", [("Applying the formula", "C(n, r) = n!/(r!(n − r)!) = 5!/(0!·5!)"),
               ("Cancelling 5!, as 0! = 1", "= 1")])
expectDetails("nCr(5,1)", "C(5, 1)", [("Applying the formula", "C(n, r) = n!/(r!(n − r)!) = 5!/(1!·4!)"),
               ("Cancelling 4!", "= 5")])
expectDetails("nCr(100,50)", "C(100, 50)", [("Applying the formula", "C(n, r) = n!/(r!(n − r)!) = 100!/(50!·50!)"),
               ("Cancelling 50!", "= (100·99·…·51)/50!")])
expectDetails("nPr(5,2)", "P(5, 2)", [("Applying the formula", "P(n, r) = n!/(n − r)! = 5!/3!"),
               ("Cancelling 3!", "= 5·4"),
               ("Multiplying", "= 20")])
expectDetails("nPr(5,5)", "P(5, 5)", [("Applying the formula", "P(n, r) = n!/(n − r)! = 5!/0!"),
               ("Using 0! = 1", "= 5!"),
               ("Evaluating the factorial", "= 120")])
expectDetails("nPr(5,0)", "P(5, 0)", [("Applying the formula", "P(n, r) = n!/(n − r)! = 5!/5!"),
               ("Cancelling 5!", "= 1")])
expectDetails("x=nCr(5,2)", "x = C(5, 2)", [("Applying the formula", "C(n, r) = n!/(r!(n − r)!) = 5!/(2!·3!)"),
               ("Cancelling 3!", "x = (5·4)/(2·1)"),
               ("Multiplying", "x = 20/2"),
               ("Dividing", "x = 10")])
expectDetails("nCr(n,2), n=5", "C(n, 2)", [("Substituting n = 5", "= C(5, 2)"),
               ("Applying the formula", "C(n, r) = n!/(r!(n − r)!) = 5!/(2!·3!)"),
               ("Cancelling 3!", "= (5·4)/(2·1)"),
               ("Multiplying", "= 20/2"),
               ("Dividing", "= 10")])
expectDetails("2*nCr(6,3)+1", "2C(6, 3) + 1", [("Evaluating the combination", "= 2·20 + 1"),
               ("Multiplying", "= 40 + 1"),
               ("Adding", "= 41")])
expectDetails("nPr(4,2)*2", "P(4, 2)·2", [("Evaluating the permutation", "= 12·2"),
               ("Multiplying", "= 24")])

// A constant is written in as its value, and what follows is in decimals
expectDetails("h=0.5g*3^2", "h = 0.5g·3²", [("Substituting g = 9.8 m s⁻²", "h = 0.5·9.8·3²"),
               ("Simplifying", "h = 4.9·9"),
               ("Multiplying", "h = 44.1")], ["h ≈ 44.1"])
expectDetails("E=0.002c^2", "E = 0.002c²", [("Substituting c = 3.00×10⁸ m s⁻¹", "E = 0.002(3×10⁸)²"),
               ("Evaluating the power", "E = 0.002·9×10¹⁶"),
               ("Multiplying", "E = 1.8×10¹⁴")], ["E = 1.8×10¹⁴"])
expectDetails("20=0.5g*t^2", "20 = 0.5g·t²", [("Substituting g = 9.8 m s⁻²", "20 = 0.5·9.8·t²"),
               ("Writing in standard form", "4.9t² − 20 = 0"),
               ("Isolating t²", "t² = 4.08163"),
               ("Taking the square root", "t ≈ ±2.02031")], ["t ≈ −2.02031", "t ≈ 2.02031"])
expectDetails("100=m*g", "100 = m·g", [("Substituting g = 9.8 m s⁻²", "100 = m·9.8"),
               ("Rearranging", "9.8m = 100"),
               ("Dividing by 9.8", "m ≈ 10.2041")], ["m ≈ 10.2041"])
expectDetails("0=20t-0.5g*t^2", "0 = 20t − 0.5g·t²", [("Substituting g = 9.8 m s⁻²", "0 = 20t − 0.5·9.8·t²"),
               ("Writing in standard form", "4.9t² − 20t = 0"),
               ("Evaluating the discriminant", "b² − 4ac = (−20)² − 4·4.9·0 = 400"),
               ("Applying the quadratic formula", "t = (−b ± √(b² − 4ac))/2a = (20 ± √400)/9.8")], ["t = 0", "t ≈ 4.08163"])
expectDetails("x^2=pi", "x² = π", [("Collecting all terms on the left", "x² − 3.14159 = 0"),
               ("Isolating x²", "x² = 3.14159"),
               ("Taking the square root", "x ≈ ±1.77245")])
expectDetails("v=-(3-1)", "v = −(3 − 1)", [("Subtracting", "v = −2")])

expectDetails(#"\sum_{k=0}^{10}k20"#, "∑(k = 0…10) k·20", [("Writing out the terms", "= 0·20 + 1·20 + 2·20 + … + 9·20 + 10·20"),
               ("Evaluating each term", "= 0 + 20 + 40 + … + 180 + 200"),
               ("Adding the terms", "= 1100")], ["= 1100"])
expectDetails(#"\sum_{k=1}^{100} k"#, "∑(k = 1…100) k", [("Writing out the terms", "= 1 + 2 + 3 + … + 99 + 100"),
               ("Adding the terms", "= 5050")])

expectDetails("2x+y=5, x-y=1", "2x + y = 5,   x − y = 1", [("(1)", "2x + y = 5"),
               ("(2)", "x − y = 1"),
               ("Eliminating y: (1) + (2)", "3x = 6"),
               ("Hence", "x = 2"),
               ("Substituting x = 2 into (1)", "2·2 + y = 5"),
               ("Hence", "y = 1")],
              ["x = 2", "y = 1"])
expectDetails("3x=2, 3x=1", "3x = 2,   3x = 1", [("(1)", "3x = 2"),
               ("(2)", "3x = 1"),
               ("Solving (1)", "x = 2/3"),
               ("Solving (2)", "x = 1/3")],
              ["No solution"], note: "The lines are parallel and do not intersect.")
expectDetails("y=2x+1, y=-x+4", "y = 2x + 1,   y = −x + 4", [("Writing (1) in standard form", "2x − y = −1"),
               ("Writing (2) in standard form", "x + y = 4"),
               ("Eliminating y: (1) + (2)", "3x = 3"),
               ("Hence", "x = 1"),
               ("Substituting x = 1 into (1)", "2·1 − y = −1"),
               ("Hence", "y = 3")])

expectDetails("x=2, y=1", "x = 2,   y = 1", [("(1)", "x = 2"),
               ("(2)", "y = 1")], ["x = 2", "y = 1"])
expectDetails("2x=4, 3y=2", "2x = 4,   3y = 2", [("Writing (1) in standard form", "x = 2"),
               ("(2)", "3y = 2"),
               ("Solving (2) for y", "y = 2/3")])

if let d = Solver.details("x^2+y+z=3, x+y^2+z=3, x+y+z^2=3") {
    let lines = d.solutions.map(\.plain)
    let want = ["(−3, −3, −3)", "(−√2, −√2, 1 + √2) ≈ (−1.41421, −1.41421, 2.41421)", "(−√2, 1 + √2, −√2) ≈ (−1.41421, 2.41421, −1.41421)",
                "(1 − √2, √2, √2) ≈ (−0.414214, 1.41421, 1.41421)", "(1, 1, 1)", "(√2, 1 − √2, √2) ≈ (1.41421, −0.414214, 1.41421)",
                "(√2, √2, 1 − √2) ≈ (1.41421, 1.41421, −0.414214)", "(1 + √2, −√2, −√2) ≈ (2.41421, −1.41421, −1.41421)"]
    if lines != want { failures += 1; print("FAIL nonlinear solutions\n  want \(want)\n  got  \(lines)") }
}

// Percentages and remainders, as they are used
expect("10*10%", "= 1")
expect("50%", "= 1/2", "≈ 0.5")
expect("200+10%", "= 220")
expect("200-10%", "= 180")
expect("200+50*10%", "= 205")
expect("15% of 80", "= 12")
expect("15%*80", "= 12")
expect("5%5", "= 0")
expect("10 % 3", "= 1")
expect("-7%3", "= 2")
expect("(10+5)%4", "= 3")

// Words, prices and dates bring up nothing
for typed in ["m1 mac", "r2d2", "9to5mac", "q4 2026", "5 ft 10", "wi-fi 6", "e2e", "2+2=5 meme", "$100", "100$", "2026-10-06", "10/6/2026", "007"] {
    if let got = Solver.solve(typed) { failures += 1; print("FAIL \(typed) should show nothing, got \(got.exact)") }
}
expect("2 x + 3 x", "= 5x")
expect("F=kq/r^2, r=?", "r = ±√(kq/F)")

// Statements joined, and exact equality
for (typed, want) in [("3+1=4 || 3=1", "True"), ("3=1 || 2=5", "False"), ("3=1 && 2=2", "False"), ("2=2 && 3=3", "True"), ("1=1 && 2=3 || 4=4", "True"),
                      ("1<2 && 2<3 && 3<4", "True"), ("1/3===0.33", "False"), ("1/3===0.3333333333333333", "False"), ("1/3===1/3", "True"),
                      ("0.5===1/2", "True"), ("2^10===1024", "True"), ("sqrt(2)^2===2", "True"), ("0.1+0.2==0.3", "True"), ("1/3==0.3333", "False"),
                      ("5 !== 5", nil), ("3=1 and 2=2", "False"), ("3=1 or 2=2", "True"), ("3=1 AND 2=2", "False"), ("not 3=1", "True"), ("!(3=1)", "True"),
                      ("!(3=1 || 2=2)", "False"), ("(1=1 || 2=3) && 3=3", "True"), ("1=1 and not 2=3", "True"), ("not (1=1 and 2=3) or 4=5", "True"),
                      ("2 and 3", nil), ("salt and pepper", nil), ("x or y", nil)] as [(String, String?)] {
    let got = Solver.solve(typed)?.exact
    if got != want { failures += 1; print("FAIL \(typed)\n  want \(want ?? "nil")\n  got  \(got ?? "nil")") }
}
expect("x=2 && 3=3", nil)

// A path that exists is named, and is shown in Finder
expect("/bin/ls", "ls", "In /bin, shown in Finder")
expect("'/bin/ls'", "ls", "In /bin, shown in Finder")
expect("/usr/bin", "bin", "A folder, opened in Finder: /usr/bin")
expect("/usr/bin/", "bin", "A folder, opened in Finder: /usr/bin")
expect("file:///bin/ls", "ls", "In /bin, shown in Finder")
expect("/no/such/place.jar", nil)
expect("/", nil)
expect("/2", nil)
expect("~", nil)
expect("~/Code", nil)
with("paths", false) { expect("/bin/ls", nil) }

// A line for Terminal after >: off unless chosen, kept exactly as typed, and typed in Terminal
// without being run, whatever it is.
let willType = "Press Return, or click, to type it in Terminal without running it"
with("commands", false) { expect("> top", nil) }
let unchanged = ["/bin/ls", "/usr/bin", "2+2", "x^2>4", "x>2", "1<x<5", "2048", "ans*2", "> 5"]
var before: [String: String] = [:]
with("commands", false) { for input in unchanged { before[input] = Solver.solve(input).map { "\($0.exact) / \($0.approx ?? "")" } ?? "nil" } }
with("commands", true) {
    // Nothing but a line after > is changed by the setting.
    for input in unchanged.dropLast() where (Solver.solve(input).map { "\($0.exact) / \($0.approx ?? "")" } ?? "nil") != before[input] {
        failures += 1; print("FAIL \(input): changed by the setting for commands")
    }
    expect("> top", "top", willType)
    expect(">top", "top", willType)
    expect(">ls -la", "ls -la", willType)
    expect(#"> echo "a\"b" 'c' \\ $HOME"#, #"echo "a\"b" 'c' \\ $HOME"#, willType)
    expect("> ls my_file", "ls my_file", willType)
    expect("> echo\ta", "echo\ta", willType)
    expect("> sudo rm x", "sudo rm x", willType)
    expect("> ", nil)
    expect(">", nil)
    expect("> top\nls", nil)
    expect("> top\rls", nil)
    // A command, not arithmetic, and nothing in it put in for ans or clip.
    expect("> 2+2", "2+2", willType)
    expect("> echo ans clip ans1", "echo ans clip ans1", willType)
    expectCopy("> top", nil)
    if Solver.values("> top") != [] { failures += 1; print("FAIL > top: a command gave ans a value") }
    expect("/bin/ls", "ls", "In /bin, shown in Finder")
    expect("2+2", "= 4")
    // > 5 was not a card before, and is a command now.
    expect("> 5", "5", willType)
    // With Return only on the card, the card says so.
    with("commandReturn", false) { expect("> top", "top", "Click, or press Return here, to type it in Terminal without running it") }
    // Every line is given to Terminal inside zsh's print -z, quoted so that zsh reads back exactly
    // the line, whatever quotes, $( ), backquotes, ; or ! are in it, and runs none of it.
    for line in ["top", "sudo ls", "echo 'a'\"b\" \\ $HOME", "ls; echo $(whoami) `id` !! 'it''s'", "rm -rf ~/x", "printf '%s\\n' a\tb"] {
        guard let script = Command.parse("> " + line)?.script, script.hasPrefix(" clear; print -rz -- ") else {
            failures += 1; print("FAIL > \(line): not typed in Terminal"); continue
        }
        let quoted = String(script.dropFirst(" clear; print -rz -- ".count))
        let zsh = Process(), out = Pipe()
        zsh.executableURL = URL(fileURLWithPath: "/bin/zsh")
        zsh.arguments = ["-f", "-c", "print -rn -- " + quoted]
        zsh.standardOutput = out
        try? zsh.run()
        zsh.waitUntilExit()
        let back = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        if back != line { failures += 1; print("FAIL > \(line): zsh read back \(back)") }
    }
}

// What a calculator is for
for (typed, want) in [("mean(1,2,3,4)", "= 5/2"), ("median(3,1,2)", "= 2"), ("mode(1,2,2,3)", "= 2"), ("stdevp(2,4,4,4,5,5,7,9)", "= 2"),
                      ("var(1,2,3,4)", "= 5/3"), ("geomean(1,2,4)", "= 2"), ("binompdf(10,0.5,3)", "= 15/128"), ("binomcdf(10,0.5,3)", "= 11/64"),
                      ("gcd(12,18)", "= 6"), ("lcm(4,6)", "= 12"), ("nCr(5,2)", "= 10"), ("5C2", "= 10"), ("nPr(5,2)", "= 20"), ("5P3", "= 60"),
                      ("17 mod 5", "= 2"), ("mod(17,5)", "= 2"), ("floor(3.7)", "= 3"), ("ceil(3.2)", "= 4"), ("round(79.695,2)", "= 797/10"),
                      ("max(3,5,9)", "= 9"), ("min(3,5)", "= 3"), ("|3-7|+2", "= 6"), ("$5*3", "= 15"), ("20% off 80", "= 64"),
                      ("1<<4", "= 16"), ("256>>2", "= 64"), ("12&10", "= 8"), ("xor(12,10)", "= 6"), ("log(8,2)", "= 3"), ("log2(8)", "= 3"),
                      ("sec(0)", "= 1"), ("cbrt(27)", "= 3"), ("root(-8,3)", "= −2"), ("fib(10)", "= 55"), ("totient(36)", "= 12"),
                      ("nextprime(100)", "= 101"), ("hypot(3,4)", "= 5"), ("sqrt(-4)", "= 2i"), ("1/0", "Undefined"), ("200!", "Too large"),
                      ("5 km to miles", nil), ("255 in hex", "FF"), ("hex(255)", "FF"), ("bin(10)", "1010"), ("3 in binary", "11"), ("5 in base 1", "11111"), ("3 in unary", "111"), ("0xFF in decimal", "255"),
                      ("x^2>4", "x < −2 or x > 2"), ("x^2<4", "−2 < x < 2"), ("x^2>=0", "x ∈ ℝ"), ("x^2<0", "No solution"), ("x^2 != 4", "x ≠ −2, 2"),
                      ("x^3-x>0", "−1 < x < 0 or x > 1"), ("2x+3<7", "x < 2"), ("x^2-5x+6>0", "x < 2 or x > 3"),
                      ("expand((x+1)^2)", "x² + 2x + 1"), ("factor(x^2-5x+6)", "(x − 2)(x − 3)"), ("factor(2x^2-8)", "2(x + 2)(x − 2)"),
                      ("factor(x^3-x)", "x(x + 1)(x − 1)"), ("derivative(x^3+2x)", "3x² + 2"), ("d/dx sin(x)", "cos(x)"), ("expand ((x+1)^2)", "x² + 2x + 1"), ("expand (x+1)^2", "x² + 2x + 1"), ("expand 3(x+2)", "3x + 6"), ("factor x^2-5x+6", "(x − 2)(x − 3)"), ("derivative x^3", "3x²"), ("integrate x^2, 0, 1", "= 1/3"),
                      ("derivative(x^2, 3)", "= 6"), ("integrate(x^2)", "x³/3 + C"), ("integrate(x^2, 0, 1)", "= 1/3"), ("∫_0^1 x^2 dx", "= 1/3"),
                      ("integrate(1/x)", "ln|x| + C"), ("x^2+x+1=0", "x = (−1 ± √3 i)/2")] as [(String, String?)] {
    let got = Solver.solve(typed)?.exact
    if let want, got != want { failures += 1; print("FAIL \(typed)\n  want \(want)\n  got  \(got ?? "nil")") }
    if want == nil, got == nil { failures += 1; print("FAIL \(typed) shows nothing") }
}
expect("5 km to miles", "= 3.10686 miles", "5 km")
expect("100 F to C", "= 37.7778 °C", "100 °F")
expect("12 in to cm", "= 30.48 cm", "12 in")
expect("2.5e-3", "= 1/400", "≈ 0.0025")
expect("pi", "≈ 3.14159")
with("basePrefix", true) { expect("3 in binary", "0b11", approxAny: true); expect("255 in hex", "0xFF", approxAny: true) }
if Solver.copy("5 km to miles") != "3.10685596119" { failures += 1; print("FAIL copy of a conversion: \(Solver.copy("5 km to miles") ?? "nil")") }
if Solver.copy("255 to hex") != "FF" { failures += 1; print("FAIL copy of a base") }
if Solver.copy("mean(1,2,3,4)") != "2.5" { failures += 1; print("FAIL copy of a mean") }

// Complex numbers, matrices, limits, LaTeX, and roots that are repeated
for (typed, want) in [("(1+2i)*(3-i)", "= 5 + 5i"), ("i^2", "= −1"), ("e^(i*pi)", "= −1"), ("|3+4i|", "= 5"), ("sqrt(-1)*sqrt(-1)", "= −1"),
                      ("(2+3i)/(1-i)", "= −1/2 + 5i/2"), ("3i+2i", "= 5i"), ("conj(3+4i)", "= 3 − 4i"), ("ln(-1)", "= 3.14159i"),
                      ("det([[1,2],[3,4]])", "= −2"), ("inv([[1,2],[3,4]])", "[[−2, 1], [3/2, −1/2]]"), ("transpose([[1,2,3],[4,5,6]])", "[[1, 4], [2, 5], [3, 6]]"),
                      ("rank([[1,2],[2,4]])", "= 1"), ("dot([1,2,3],[4,5,6])", "= 32"), ("cross([1,2,3],[4,5,6])", "[−3, 6, −3]"), ("norm([3,4])", "= 5"),
                      ("[[1,2],[3,4]]*[[0,1],[1,0]]", "[[2, 1], [4, 3]]"), ("[[1,2],[3,4]]^2", "[[7, 10], [15, 22]]"), ("[[1,2],[3,4]]*[1,1]", "[3, 7]"),
                      ("inv([[1,2],[2,4]])", "Undefined"), ("limit(sin(x)/x, x, 0)", "= 1"), ("limit((1-cos(x))/x^2, x, 0)", "= 1/2"),
                      ("limit(1/x, x, 0)", "Does not exist"), ("limit(1/x, x, inf)", "= 0"), ("limit(x^2, x, inf)", "∞"), ("lim(x*ln(x), x, 0)", "= 0"),
                      ("|2x+1|<3", "−2 < x < 1"), ("|x|>2", "x < −2 or x > 2"), ("exp(x)>1", "x > 0"),
                      (#"\binom{5}{2}"#, "= 10"), (#"\log_2 8"#, "= 3"), (#"\log_{2}{8}"#, "= 3"), (#"\left|-5\right|"#, "= 5"), (#"\int_0^1 x^2 dx"#, "= 1/3"),
                      (#"\lim_{x\to 0}\frac{\sin x}{x}"#, "= 1"), (#"\frac{d}{dx}(x^3)"#, "3x²"),
                      ("x^4-12x^3+37x^2+30x-200=0", "x = −2, 4, 5"), ("x^6+30x^5+375x^4+2500x^3+9375x^2+18750x+15625=0", "x = −5"),
                      ("(x-5)^2(x+1)(x-4)=0", "x = −1, 4, 5"), ("-x^4+12x^3-37x^2-30x+200>=0", "−2 ≤ x ≤ 4 or x = 5"),
                      ("mean([1,2,3,4])", "= 5/2"), ("2⁵", "= 32"), ("x⁴-1=0", "x = ±1")] as [(String, String?)] {
    let got = Solver.solve(typed)?.exact
    if let want, got != want { failures += 1; print("FAIL \(typed)\n  want \(want)\n  got  \(got ?? "nil")") }
}
if Solver.copy("(1+2i)*(3-i)") != "5+5i" { failures += 1; print("FAIL copy of a complex number: \(Solver.copy("(1+2i)*(3-i)") ?? "nil")") }
if Solver.copy("det([[1,2],[3,4]])") != "-2" { failures += 1; print("FAIL copy of a determinant") }

// LaTeX, for what can be asked
for (typed, want) in [(#"15\% \text{ of } 80"#, "= 12"), (#"20\% \text{ off } 80"#, "= 64"), (#"\sin 30^\circ"#, "= 1/2"), (#"\sec 0"#, "= 1"), (#"\sec^2 0"#, "= 1"),
                      (#"\lfloor 3.7 \rfloor"#, "= 3"), (#"\left\lceil 3.2 \right\rceil"#, "= 4"), (#"\gcd(12,18)"#, "= 6"), (#"17 \bmod 5"#, "= 2"),
                      (#"{5 \choose 2}"#, "= 10"), (#"\operatorname{mean}(1,2,3,4)"#, "= 5/2"), (#"\mathrm{e}^{i\pi}"#, "= −1"), (#"\overline{3+4i}"#, "= 3 − 4i"),
                      (#"5\,\mathrm{km} \text{ to } \mathrm{mi}"#, "= 3.10686 mi"), (#"\det \begin{pmatrix} 1 & 2 \\ 3 & 4 \end{pmatrix}"#, "= −2"),
                      (#"\begin{vmatrix} 1 & 2 \\ 3 & 4 \end{vmatrix}"#, "= −2"), (#"\begin{bmatrix} 1 & 2 \\ 3 & 4 \end{bmatrix}^{-1}"#, "[[−2, 1], [3/2, −1/2]]"),
                      (#"\begin{pmatrix} 1 & 2 \\ 3 & 4 \end{pmatrix}^T"#, "[[1, 3], [2, 4]]"),
                      (#"\begin{pmatrix} 1 & 2 \\ 3 & 4 \end{pmatrix}\begin{pmatrix} 1 \\ 1 \end{pmatrix}"#, "[3, 7]"),
                      (#"\left\| \begin{pmatrix}3\\4\end{pmatrix} \right\|"#, "= 5"), (#"\int_0^1 x^2 \, \mathrm{d}x"#, "= 1/3"), (#"\int x^2 \, dx"#, "x³/3 + C"),
                      (#"\frac{d}{dx}\left( x^3 + 2x \right)"#, "3x² + 2"), (#"\lim_{x \to 0^+} \frac{\sin x}{x}"#, "= 1"), (#"\lim_{x \to \infty} \frac{1}{x}"#, "= 0"),
                      (#"\sum\limits_{k=1}^{5} k^2"#, "= 55"), (#"x \ne 2"#, "x ≠ 2"), (#"3=1 \lor 2=2"#, "True"), (#"\lnot (3=1)"#, "True"),
                      (#"\left\{ \begin{array}{l} x+y=10 \\ x-y=2 \end{array} \right."#, "x = 6, y = 4"), (#"\log_2 8"#, "= 3"), (#"\tan^{-1} 1"#, "= π/4")] as [(String, String?)] {
    let got = Solver.solve(typed)?.exact
    if let want, got != want { failures += 1; print("FAIL \(typed)\n  want \(want)\n  got  \(got ?? "nil")") }
}
expect("（x＋1）＾2=4", "x = −3, 1")
expect(#"\sin x=\frac{\sqrt{3}}{2},\quad 0^\circ\le x<360^\circ"#, "x = 60°, 120°", "= π/3, 2π/3 rad, for 0° ≤ x < 360°")
expect("sin(x)=sqrt(3)/2, 0<=x<=2pi", "x = π/3, 2π/3", approxAny: true)
expect(#"\cos x=\frac12,\quad x\in[0,2\pi)"#, "x = π/3, 5π/3", approxAny: true)
expect("cos(x)=1/2, x in [0, 2π)", "x = π/3, 5π/3", approxAny: true)
expect("2sin(x)=1, 0°<x<720°", "x = 30°, 150°, 390°, 510°", approxAny: true)
expect("x^2=4, x>0", "x = 2", "for x > 0")
expect("x^2=4, x<0", "x = −2", "for x < 0")
expect("sin(x)=2, 0<=x<=360", "No solution", approxAny: true)
expect("expand （（x＋1）＾2）", "x² + 2x + 1")

// What a user would also try
for (typed, want) in [("v=u+at, u=2, a=3, t=4", "v = 14"), ("s=ut+1/2at^2, u=0, a=9.8, t=2", "s = 98/5"), ("v=u+at, v=14, u=2, a=3", "t = 4"), ("F=ma, m=2, a=3", "F = 6"),
                      ("2^64", "= 18446744073709551616"), ("20!", "= 2432902008176640000"), ("2^100", "= 1267650600228229401496703205376"), ("(2^64)/2", "= 9223372036854775808"),
                      ("1 1/2 + 2 3/4", "= 17/4"), ("1+2+...+100", "= 5050"), ("2+4+6+…+20", "= 110"), ("1*2*...*5", "= 120"), ("sum of 1 to 100", "= 5050"),
                      ("5 km + 300 m", "= 5300 m"), ("5 ft 10 in to cm", "= 177.8 cm"), ("1 h 30 min", "= 90 min"),
                      ("md5(\"hello\")", "5d41402abc4b2a76b9719d911017c592"), ("d2/dx2 x^3", "6x"), ("second derivative of x^3", "6x"),
                      ("0.75 to fraction", "= 3/4"), ("12345 to scientific", "= 1.2345×10⁴"), ("0.25 to percent", "= 25%"), ("2024 to roman", "MMXXIV"), ("MCMXCIV to number", "= 1994"),
                      ("quartile([1,2,3,4,5,6,7,8],1)", "= 11/4"), ("percentile([1,2,3,4,5],50)", "= 3"), ("corr([1,2,3],[2,4,6])", "= 1"), ("linreg([1,2,3],[2,4,6])", "y = 2x"),
                      ("1<x<5", "1 < x < 5"), ("x>1 && x<5", "1 < x < 5"), ("x<1 or x>5", "x < 1 or x > 5"), ("x^2>4 && x<10", "x < −2 or 2 < x < 10"), ("x>5 && x<1", "No solution"),
                      ("SIN(30°)", "= 1/2"), ("Sqrt(16)", "= 4"), ("NCR(5,2)", "= 10"), ("solve 2x+3=7", "x = 2"), ("2x+3=7 solve for x", "x = 2"), ("find x: 2x=6", "x = 3"),
                      ("what is 15% of 80", "= 12"), ("2^(x+1)=3^x", "x ≈ 1.70951"), ("1/x+1/(x+1)=1", "x = (1 ± √5)/2"), ("1/x=2", "x = 1/2"), ("(x+1)/(x-1)=2", "x = 3"), ("2/(x-1)=x", "x = −1, 2"), ("x+1/x=3", "x = (3 ± √5)/2"), ("(x^2-1)/(x-1)=2", "No solution"), ("x/x=1", "x ∈ ℝ, x ≠ 0"), ("1/(x-2)+1/(x+2)=1/3", "x = 3 ± √13"), ("e^x=0", "No real solutions found")] as [(String, String?)] {
    let got = Solver.solve(typed)?.exact
    if let want, got != want { failures += 1; print("FAIL \(typed)\n  want \(want)\n  got  \(got ?? "nil")") }
}
// Feet and inches as a height is written; ′ and ″ are still minutes and seconds of arc
for (typed, want) in [("5'7", "= 1.7018 m"), ("5'7\"", "= 1.7018 m"), ("5' 7\" to cm", "= 170.18 cm"), ("5’7”", "= 1.7018 m"), ("5'7 in", "= 1.7018 m"),
                      ("5'7 in cm", "= 170.18 cm"), ("5'7 to meters", "= 1.7018 meters"), ("6'", "= 1.8288 m"), ("6' to in", "= 72 in"), ("5'10.5\" to cm", "= 179.07 cm"),
                      ("5'7 to kg", nil)] as [(String, String?)] {
    let got = Solver.solve(typed)?.exact
    if got != want { failures += 1; print("FAIL \(typed)\n  want \(want ?? "nil")\n  got  \(got ?? "nil")") }
}
if Solver.copy("5'7") != "1.7018" { failures += 1; print("FAIL copy of 5'7: \(Solver.copy("5'7") ?? "nil")") }
if Solver.copy("2^64") != "18446744073709551616" { failures += 1; print("FAIL copy of a big integer: \(Solver.copy("2^64") ?? "nil")") }

// Trigonometric identities
for (typed, want) in [("sin(x)^2+cos(x)^2", "= 1"), ("1-sin(x)^2", "= cos(x)²"), ("sin(x)/cos(x)", "= tan(x)"), ("2sin(x)cos(x)", "= sin(2x)"), ("sin(x)cos(x)", "= sin(2x)/2"),
                      ("cos(x)^2-sin(x)^2", "= cos(2x)"), ("1-2sin(x)^2", "= cos(2x)"), ("(1-cos(2x))/2", "= sin(x)²"), ("tan(x)cos(x)", "= sin(x)"), ("1+tan(x)^2", "= sec(x)²"),
                      ("sin(x+pi/2)", "= cos(x)"), ("1-sin(x)^2-cos(x)^2", "= 0"), ("3sin(x)^2+3cos(x)^2", "= 3"), ("2sin(3x)cos(3x)", "= sin(6x)"),
                      (#"\sin^2 x + \cos^2 x"#, "= 1"), (#"\frac{\sin x}{\cos x}"#, "= tan(x)"), ("sin(x°)^2+cos(x°)^2", "= 1"), ("sin(0.3)*sin(x)/cos(x)", "= sin(0.3)·tan(x)"), ("sin(0.3)/cos(x)", "≈ 0.29552/cos(x)"), ("2*sin(0.3)/cos(x)", "≈ 0.59104/cos(x)")] as [(String, String?)] {
    let got = Solver.solve(typed)?.exact
    if let want, got != want { failures += 1; print("FAIL \(typed)\n  want \(want)\n  got  \(got ?? "nil")") }
}
for typed in ["sin(x)", "tan(x)", "sin(x)+cos(x)", "sin(x)^2", "x+sin(x)", "sin x^2 + cos x^2"] {
    if let got = Solver.solve(typed) { failures += 1; print("FAIL \(typed) should show nothing, shows \(got.exact)") }
}

// A bracket that was meant to start earlier
for (typed, want) in [("29-12)/5", "= 17/5"), ("1+2)*3", "= 9"), ("x=29-12)/5", "x = 17/5"),
                      ("(1+2)+3)", "= 6"), ("2*(1+2))", "= 6")] as [(String, String?)] {
    let got = Solver.solve(typed)?.exact
    if let want, got != want { failures += 1; print("FAIL \(typed)\n  want \(want)\n  got  \(got ?? "nil")") }
}

// Sequences: nothing is said until d, r, a term or a sum is asked for
for (typed, want) in [("u_1=12, u_5=29, d", "d = 17/4"), ("u_{1}=12, u_{5}=29, d", "d = 17/4"), ("u_2=6, u_4=24, d", "d = 9"), ("u_1=3, u_4=24, r", "r = 2"),
                      ("u_1=2, d=3, u_10=?", "u_10 = 29"), ("u_1=2, r=3, u_5=?", "u_5 = 162"), ("u_1=2, u_3=18, S_5=?", "Arithmetic: S_5 = 90"),
                      ("u_1=12, u_5=29, d=?", "d = 17/4"), ("u_1=12, u_5=29, r=?", "r = ±(29/12)^(1/4)"),
                      ("u_1=12, u_5=29", nil), ("u+1=12, u_5=29", nil)] as [(String, String?)] {
    let got = Solver.solve(typed)?.exact
    if let want, got != want { failures += 1; print("FAIL \(typed)\n  want \(want)\n  got  \(got ?? "nil")") }
    if want == nil, let got, got.hasPrefix("Arithmetic") || got.hasPrefix("Geometric") { failures += 1; print("FAIL \(typed) is a sequence before it is asked about: \(got)") }
}
expect("u+1=12, u_5=29, d", "d = 17/4", "u_n = 12 + (17/4)(n − 1)")
expect("u1=12, u_5=29, d", "d = 17/4", "u_n = 12 + (17/4)(n − 1)")
expect("u-1=12, u_5=29, r", "r = ±(29/12)^(1/4)", "≈ ±1.24682, u_n = 12·r^(n − 1)")
expect("u_2=6, u_4=24, r", "r = ±2", "u_n = 6·r^(n − 2)")
expect("d_1=10,d_3=20,r", "r = ±√2", "≈ ±1.41421, d_n = 10·r^(n − 1)")
expect("u_1=3, u_3=7, r", "r = ±√21/3", approxAny: true)
expect("u_1=1, u_2=2, u_3=4, d", "No common difference", approxAny: true)
expect("u_2=6, u_4=24, u_6=?", "Arithmetic: u_6 = 42", "Geometric: u_6 = 96")
expect("u_2=6, u_4=24, u_5=?", "Arithmetic: u_5 = 33", "Geometric: u_5 = 48 or −48")
for typed in ["d_1=10,d_3=20,r", "u_1=12, u_5=29, d", "u_2=6, u_4=24, u_6=?", "u_1=-4, u_2=6, r"] {
    if Solver.details(typed)?.graph == nil { failures += 1; print("FAIL \(typed) has no graph") }
}
// A sum raised to a power, or sums multiplied, is written out
for (typed, want) in [("(a+b)^2", "= a² + 2ab + b²"), ("(a-b)^2", "= a² − 2ab + b²"), ("(x+1)^3", "= x³ + 3x² + 3x + 1"), ("(x+1)(x-1)", "= x² − 1"),
                      ("(a+b)(c+d)", "= ac + ad + bc + bd"), ("2(a+b)^2", "= 2a² + 4ab + 2b²"), ("(a+b)^2-(a-b)^2", "= 4ab"), ("(a+b)^1", "= a + b"), ("(a+b)^0", "= 1"), ("(x-1)^1", "= x − 1"), ("(2a+3b)^2", "= 4a² + 12ab + 9b²"),
                      ("x(b+c)", nil), ("3(x+1)", nil), ("(a+b)", nil)] as [(String, String?)] {
    let got = Solver.solve(typed)?.exact
    if got != want { failures += 1; print("FAIL \(typed)\n  want \(want ?? "nil")\n  got  \(got ?? "nil")") }
}

// A sum answered as a decimal first, the fraction beneath it
UserDefaults.standard.set(true, forKey: "decimalFirst")
expect("10/4", "= 2.5", "= 5/2")
expect("1/3", "≈ 0.333333", "= 1/3")
expect("1/3+1/6", "= 0.5", "= 1/2")
expect("2/3*3", "= 2")
expect("x=10/4", "x = 2.5", "= 5/2")
UserDefaults.standard.set(false, forKey: "decimalFirst")

// A constant of physics alone in a sum: 50*c^2 is worked out, and e = mc^2 read as the energy.
expect("50*c^2", "= 4.5×10¹⁸", "Taking c = 3.00×10⁸ m s⁻¹")
expect("c^2*50", "= 4.5×10¹⁸", "Taking c = 3.00×10⁸ m s⁻¹")
expect("2*c", "= 6×10⁸", "Taking c = 3.00×10⁸ m s⁻¹")
expect("50*g", "= 490", "Taking g = 9.8 m s⁻²")
expect("e=50*c^2", "E = 4.5×10¹⁸", "Taking c = 3.00×10⁸ m s⁻¹")
expect("e=mc^2, m=50", "E = 4.5×10¹⁸", "Taking m = 50, c = 3.00×10⁸ m s⁻¹")
expect("E=mc^2, m=50", "E = 4.5×10¹⁸", "Taking m = 50, c = 3.00×10⁸ m s⁻¹")
// An angle given is given in its unit: 30° as typed, and 30 by itself in radians unless the
// settings say degrees, which the card says. theta = 30 gives the θ of the equation.
// Values given are written into each of several equations, which are then solved together; and
// g is the constant it names in a system with more letters than equations, as with one equation.
expect("5.05=f*1.6, f = mgcos(25deg)*mu,m=1.3", "μ ≈ 0.273355", "Taking m = 1.3, f = 3.15625, g = 9.8 m s⁻²")
expect("5.05=f*1.6, f = 1.3gcos(25deg)*mu", "f = 101/32, μ = 0.273355", "≈ 3.15625, 0.273355")
expect("x+y=g, x-y=1", "x = 27/5, y = 22/5", "≈ 5.4, 4.4")
expect("x+y=10g, x-y=2", "x = 50, y = 48", "Taking g = 9.8 m s⁻²")
expect("c+d=3, c-d=1", "c = 2, d = 1")
// A value that uses another letter given is found once that letter is written in, round by
// round; c given 3 is 3, not the speed of light.
expect("a=2b, b=c+1, c=3", "a = 8", "Taking c = 3, b = 4")
expect("F=ma, a=v/t, v=10, t=2, m=3", "F = 15", "Taking v = 10, t = 2, m = 3, a = 5")
expect("5.05=f*1.6, f=N*mu, N=mgcos(25deg), m=1.3", "μ ≈ 0.273355", "Taking m = 1.3, f = 3.15625, N ≈ 11.5464, g = 9.8 m s⁻²")
// Each equation in turn that has one letter left is solved, with what is known written in.
expectDetails("5.05=f*1.6, f=N*mu, N=mgcos(25deg), m=1.3", "5.05 = f·1.6,   f = Nμ,   N = mg·cos(25°)", [("Solving (1) for f", "5.05 = f·1.6"),
               ("Hence", "f = 101/32 ≈ 3.15625"),
               ("Substituting m = 1.3, g = 9.8 m s⁻² into (3)", "N = 1.3·9.8·cos(25°)"),
               ("Hence", "N ≈ 11.5464"),
               ("Substituting f = 3.15625, N ≈ 11.5464 into (2)", "3.15625 = 11.5464μ"),
               ("Hence", "μ ≈ 0.273355")])
expectCopy("5.05=f*1.6, f=N*mu, N=mgcos(25deg), m=1.3", "0.273354517796")
expectDetails("v=u+at, u=2, a=3, t=4", "v = u + at", [("Substituting u = 2, a = 3, t = 4", "v = 2 + 3·4"),
               ("Multiplying", "v = 2 + 12"),
               ("Adding", "v = 14")])
// A letter that is a factor of both sides divides out; a subscript ends where the parser's does.
expect("mgh=1/2mv^2, h=5", "v ≈ ±9.89949", "Taking h = 5, g = 9.8 m s⁻²")
expectDetails("mgh=1/2mv^2, h=5", "mgh = 1/2·mv²", [("Substituting h = 5", "mg·5 = 1/2·mv²"),
               ("Dividing both sides by m", "g·5 = 1/2·v²"),
               ("Substituting g = 9.8 m s⁻²", "9.8·5 = 1/2·v²"),
               ("Writing in standard form", "0.5v² − 49 = 0"),
               ("Isolating v²", "v² = 98"),
               ("Taking the square root", "v ≈ ±9.89949")])
expect("ma=mg, a=?", "a = g")
expect("mgh=1/2mv^2,v=2", "h ≈ 0.204082", "Taking v = 2, g = 9.8 m s⁻²")
expect("F=kq_1q_2/r^2, k=8.99e9, q_1=2e-6, q_2=3e-6, r=0.05", "F = 2697/125", "≈ 21.576")
// An expression is written out as it is on paper, g with the values given.
expectDetails("mg*1.2+1/2mv^2,m=55,v=0.9", "mg·1.2 + 1/2·mv²", [("Substituting m = 55, v = 0.9, g = 9.8 m s⁻²", "= 55·9.8·1.2 + 1/2·55·0.9²"),
               ("Simplifying", "= 539·1.2 + 0.5·55·0.81"),
               ("Multiplying", "= 646.8 + 27.5·0.81"),
               ("Multiplying", "= 646.8 + 22.275"),
               ("Adding", "= 669.075")])
// A linear equation in short decimals is rearranged as it stands, not multiplied up to whole numbers.
expectDetails("12=1.8+4vcos(theta)", "12 = 1.8 + 4v cos(θ)", [("Expanding brackets and collecting like terms", "12 = 4v cos(θ) + 9/5"),
               ("Subtracting 4v cos(θ) on both sides", "−4v cos(θ) + 12 = 9/5"),
               ("Subtracting 12 on both sides", "−4v cos(θ) = −51/5"),
               ("Dividing both sides by −4", "v cos(θ) = (−51/5)/(−4) = 51/20")],
              note: "v and θ cannot be found separately from one equation.")
expectDetails("2x+3=7", "2x + 3 = 7", [("Subtracting 3 on both sides", "2x = 4"),
               ("Dividing both sides by 2", "x = 4/2 = 2")])
// Too few equations for the unknowns: the card says so, and which values are wanted. An
// unknown that one equation settles is not wanted, and m divides out of mgh = ½mv².
expect("mgh=1/2mv^2", "Insufficient information", "A value is required for h or v.")
expect("2a+3b=7", "Insufficient information", "A value is required for a or b.")
expect("5.05=f*1.6, f=N*mu", "Insufficient information", "A value is required for N or μ.")
expect("s=ut+1/2at^2, u=0", "Insufficient information", "Values are required for two of s, t and a.")
expect("x+y+z, z=1", "= x + y + 1", "Taking z = 1")
expectCopy("mgh=1/2mv^2", nil)
// Each unknown in terms of the others, where one equation is left: on one line √(2gh), not √2gh.
expectDetails("mgh=1/2mv^2", "m·gh = 1/2·mv²", [("Dividing both sides by m", "gh = 1/2·v²"),
               ("Identifying the unknowns", "h, v"),
               ("Expressing h in terms of v", "h = v²/(2g)"),
               ("Expressing v in terms of h", "v = ±√(2gh)")],
              ["h = v²/(2g)", "v = ±√(2gh)"], note: "A value is required for h or v.")
expectDetails("5.05=f*1.6, f=N*mu", "5.05 = f·1.6,   f = Nμ", [("Identifying the unknowns", "N, μ"),
               ("Expressing N in terms of μ", "N = 101/(32μ)"),
               ("Expressing μ in terms of N", "μ = 101/(32N)")],
              ["N = 101/(32μ)", "μ = 101/(32N)"], note: "A value is required for N or μ.")
for typed in ["x=5", "a=b", "x+y", "hello world"] where Solver.solve(typed) != nil { failures += 1; print("FAIL \(typed) should show nothing") }
// An expression, with no = in it, is worked out with the values given written in.
expect("mg*1.2+1/2mv^2,m=55,v=0.9", "≈ 669.075", "Taking m = 55, v = 0.9, g = 9.8 m s⁻²")
expect("1/2mv^2, m=2, v=3", "= 9", "Taking m = 2, v = 3")
expect("x^2+1, x=3", "= 10", "Taking x = 3")
expect("x+y, x=2", "= y + 2", "Taking x = 2")
expect("n*x, n=2", "= 2x", "Taking n = 2")
expect("mg*1.2+1/2mv^2, m=55", "= 55v²/2 + 646.8", "Taking m = 55, g = 9.8 m s⁻²")
expect("x>1, x=3", nil)
// A factorial is part of the expression, and a letter left in it is tidied: the term of a binomial
// expansion with n given. A fraction given is shown, and written in, as it was typed.
expect("(n(n-1)(n-3))/3!*(-2x)^3,n=1/2", "= −5x³/6", "Taking n = 1/2")
expect("(n(n-1)(n-2))/3!*(-2x)^3, n=1/2", "= −x³/2", "Taking n = 1/2")
expect("n(n-1)/2!*x^2, n=1/3", "= −x²/9", "Taking n = 1/3")
expect("n(n-1)/2*(3x)^2, n=-1/3", "= 2x²", "Taking n = −1/3")
expect("n(n-1)(n-2)/3!*(2x)^3+n*2x+1, n=1/2", "= x³/2 + x + 1", "Taking n = 1/2")
expect("(n(n-1)(n-3))/3!,n=1/2", "= 5/48", "≈ 0.104167")
expect("n!/(r!(n-r)!), n=5, r=2", "= 10", "Taking n = 5, r = 2")
expect("y=mx+c, m=2/3, c=1, x=3", "y = 3", "Taking m = 2/3, c = 1, x = 3")
expect("12=1.8+4vcos(theta), theta=1/2", "v ≈ 2.90571", "Taking θ = 1/2 rad")
expect("(n(n-1)(n-3))/3!*-2x^,n=1/2", nil)
expect("!c*2, c=3", nil)
expectDetails("(n(n-1)(n-3))/3!*(-2x)^3,n=1/2", "(n(n − 1)(n − 3))/(3!)(−2x)³", [("Substituting n = 1/2", "= (1/2(1/2 − 1)(1/2 − 3))/(3!)(−2x)³"),
               ("Combining the powers", "= −5x³/6")])
expect("2x*3!+x", "= 13x")
// What is asked is read first, with the part each letter plays, and anything worth knowing about
// how it was read: 1/ax² taken as (1/a)x², and where the unknown cannot go.
func expectReading(_ typed: String, _ intent: String, unknowns: [String] = [], parameters: [String] = [], constants: [String] = [], given: [String] = [], notes: [String] = []) {
    guard let r = Analyzer.read(typed), let a = Solver.answer(for: r) else { failures += 1; print("FAIL reading \(typed): nothing"); return }
    let got = (r.intent.name, r.roles?.unknowns ?? [], r.roles?.parameters ?? [], r.roles?.constants ?? [], r.roles?.given ?? [], a.notes)
    if got.0 != intent || got.1 != unknowns || got.2 != parameters || got.3 != constants || got.4 != given || got.5 != notes {
        failures += 1; print("FAIL reading \(typed)\n  want \(intent) \(unknowns) \(parameters) \(constants) \(given) \(notes)\n  got  \(got)")
    }
}
expectReading("x^2-5x+6=0", "Solving an equation", unknowns: ["x"])
expectReading("h=0.5g*3^2", "Evaluating", unknowns: ["h"], constants: ["g"])
expectReading("ax+by=1, bx+ay=2", "Solving simultaneous equations in letters", unknowns: ["x", "y"], parameters: ["a", "b"])
expectReading("1/2mv^2, m=2, v=3", "Writing in the values given", given: ["m", "v"])
expectReading("dy/dx+2xy=2x", "Solving a differential equation", unknowns: ["y"])
expectReading(#"T_5(x),\quad f(x)=\ln(1+x)\cos(x)"#, "Finding a Taylor polynomial", unknowns: ["x"])
expectReading("(2x^2+1/ax^2)^9", "Simplifying", notes: ["1/ax² is read as (1/a)·x²; for 1/(ax²), write the brackets."])
expectReading("1/(x-2)=3", "Solving an equation", unknowns: ["x"], notes: ["Where x ≠ 2"])
expectReading("sqrt(x-1)=2", "Solving an equation", unknowns: ["x"], notes: ["Where x ≥ 1"])
expectReading("ln(2x-4)=1", "Solving an equation", unknowns: ["x"], notes: ["Where x > 2"])
expectReading("1/2mv^2, m=2, v=3", "Writing in the values given", given: ["m", "v"])
// A long expansion's coefficients are whole numbers in full: ⁶⁰C₃₀ is 118264581564861424.
expect("(1+x)^60", "= x⁶⁰ + 60x⁵⁹ + 1770x⁵⁸ + 34220x⁵⁷ + 487635x⁵⁶ + 5461512x⁵⁵ + 50063860x⁵⁴ + 386206920x⁵³ + 2558620845x⁵² + 14783142660x⁵¹ + 75394027566x⁵⁰ + 342700125300x⁴⁹ + 1399358844975x⁴⁸ + 5166863427600x⁴⁷ + 17345898649800x⁴⁶ + 53194089192720x⁴⁵ + 149608375854525x⁴⁴ + 387221678682300x⁴³ + 925029565741050x⁴² + 2044802197953900x⁴¹ + 4191844505805495x⁴⁰ + 7984465725343800x³⁹ + 14154280149473100x³⁸ + 23385332420868600x³⁷ + 36052387482172425x³⁶ + 51915437974328292x³⁵ + 69886166503903470x³⁴ + 88004802264174740x³³ + 103719945525634515x³² + 114449595062769120x³¹ + 118264581564861424x³⁰ + 114449595062769120x²⁹ + 103719945525634515x²⁸ + 88004802264174740x²⁷ + 69886166503903470x²⁶ + 51915437974328292x²⁵ + 36052387482172425x²⁴ + 23385332420868600x²³ + 14154280149473100x²² + 7984465725343800x²¹ + 4191844505805495x²⁰ + 2044802197953900x¹⁹ + 925029565741050x¹⁸ + 387221678682300x¹⁷ + 149608375854525x¹⁶ + 53194089192720x¹⁵ + 17345898649800x¹⁴ + 5166863427600x¹³ + 1399358844975x¹² + 342700125300x¹¹ + 75394027566x¹⁰ + 14783142660x⁹ + 2558620845x⁸ + 386206920x⁷ + 50063860x⁶ + 5461512x⁵ + 487635x⁴ + 34220x³ + 1770x² + 60x + 1")
// The card shows first what was typed as it was understood, with the values given after it.
for (typed, want) in [("(n(n-1)(n-3))/3!*(-2x)^3,n=1/2", "(n(n − 1)(n − 3))/(3!)(−2x)³,   n = 1/2"), ("2+2", "2 + 2"),
                      ("5 km to miles", "5 km → miles"), ("x+y=3, x-y=1", "x + y = 3,   x − y = 1"),
                      ("12=1.8+4vcos(theta), theta=30°", "12 = 1.8 + 4v·cos(θ),   θ = 30°")]
    where Solver.answer(typed)?.interpretation?.plain != want {
    failures += 1; print("FAIL interpretation \(typed): want \(want), got \(Solver.answer(typed)?.interpretation?.plain ?? "nil")")
}
// A coefficient is a fraction where it is one to twelve figures, with a lower half above 1000 where
// the decimal would be rounded; a decimal of many figures typed is not taken for a fraction near it.
expect("(n(n-1)(n-2)(n-3))/4!*(x/2)^4, n=1/2", "= −5x⁴/2048", "Taking n = 1/2")
expect("(n(n-1)(n-2)(n-3))/4!*(3x)^4, n=5/4", "= 2835x⁴/2048", "Taking n = 5/4")
expect("0.1234567891x+x", "= 1.12346x")
expect("0.333333x+x", "= 1.33333x")
expect("0.142857142857x+x", "= 8x/7")
expect("123456.789x+x", "= 123457789x/1000")
expect("pi*x+x", "= 4.14159x")
// Numbers are worked exactly: a fraction is never guessed back from a decimal, and a decimal as
// typed stays one. C(n, r) is n(n − 1)⋯(n − r + 1)/r! for any n, nought where a whole n is below r.
expect("1/1024+1", "= 1025/1024", "≈ 1.00098")
expect("35/2048", "= 35/2048", "≈ 0.0170898")
expect("3.14159*2", "= 6.28318")
expect("nCr(1/2,3)", "= 1/16", "≈ 0.0625")
expect("nPr(1/2,3)", "= 3/8", "≈ 0.375")
expect("nCr(-1,2)", "= 1")
expect("nCr(2,5)", "= 0")
expect("nCr(8,3)*(2x)^3", "= 448x³")
expect("nCr(n,3)*(-2x)^3, n=1/2", "= −x³/2", "Taking n = 1/2")
expect("pi === 3.14159265358979", "True", approxAny: true)
expectDetails("nCr(1/2,3)", "C(1/2, 3)", [("Applying the formula", "C(n, r) = (n(n − 1)⋯(n − r + 1))/r! = (1/2·(−1/2)·(−3/2))/3!"),
               ("Multiplying", "= (3/8)/6"),
               ("Dividing", "= 1/16")])
// A single term may be raised to any whole power, and a sum to any that does not multiply out to
// more than 400 terms; a function of the letters is one thing among them.
expect("x^12/x^3", "= x⁹")
expect("168*64x^12 * 1/ (a^3*x^3)", "= 10752x⁹/a³")
expect("(2x^3)^12", "= 4096x³⁶")
expect("(a+b)^10", "= a¹⁰ + 10a⁹b + 45a⁸b² + 120a⁷b³ + 210a⁶b⁴ + 252a⁵b⁵ + 210a⁴b⁶ + 120a³b⁷ + 45a²b⁸ + 10ab⁹ + b¹⁰")
expect("sqrt(x)+sqrt(x)", "= 2√x")
// A Taylor polynomial, from the series of each function, exact; asked for as T_n(x), f(x) = …, or taylor( … ).
expect(#"T_5(x),\quad f(x)=\ln(1+x)\cos(x)"#, "T_5(x) = x − x²/2 − x³/6 + 3x⁵/40", "The Taylor polynomial of degree 5 about x = 0")
expect("taylor(e^x sin(x), 4)", "T_4(x) = x + x² + x³/3", "The Taylor polynomial of degree 4 about x = 0")
expect("series(cos(x), x, 6)", "T_6(x) = 1 − x²/2 + x⁴/24 − x⁶/720", "The Taylor polynomial of degree 6 about x = 0")
// The formula booklets: a subscripted letter given whole (f_s is not f), statistics of a frequency table,
// Euler's method, and identities in two angles proved.
expect("f_s=f*v/(v-u_s),f=440,v=340,u_s=20", "f_s = 935/2", "≈ 467.5")
expect("mean([1,2,3],[2,1,1])", "= 7/4", "≈ 1.75")
expect("euler(x+y, 0, 1, 0.1, 3)", "y(0.3) = 1.362", "By Euler's method, in 3 steps of h = 0.1")
expect("sin(A+B)=sin(A)*cos(B)+cos(A)*sin(B)", "A, B ∈ ℝ", "An identity: the two sides are equal for every A and B.")
expect("cos(A-B)=cos(A)*cos(B)+sin(A)*sin(B)", "A, B ∈ ℝ", "An identity: the two sides are equal for every A and B.")
// Colours: read in any of the ways they are written, converted, added as light, mixed, measured apart.
expect("#FF5733", "rgb(255, 87, 51)", "#FF5733, near tomato")
expect("rgb(255, 87, 51)", "#FF5733", "hsl(10.6, 100%, 60%), near tomato")
expect("hsb(10.6, 80%, 100%)", "#FF5733", "rgb(255, 87, 51), near tomato")
expect("cmyk(0%, 66%, 80%, 0%)", "#FF5733", "rgb(255, 87, 51), near tomato")
expect("#FF5733 to hsl", "hsl(10.6, 100%, 60%)", "#FF5733, near tomato")
expect("colour tomato", "#FF6347", "rgb(255, 99, 71), which is tomato")
expect("red + blue", "#FF00FF", "rgb(255, 0, 255), which is fuchsia or magenta")
expect("#FFFFFF - #FF0000", "#00FFFF", "rgb(0, 255, 255), which is aqua or cyan")
expect("mix(#FF0000, #0000FF)", "#800080", "50% and 50% mixed: rgb(128, 0, 128), which is purple")
expect("gradient(#FF0000, #0000FF, 5)", "#FF0000, #BF0040, #800080, #4000BF, #0000FF", "5 colours, evenly from #FF0000 to #0000FF")
expect("deltaE(#FF0000, #FE0000)", "ΔE = 0.38", "Not perceptible to the eye")
expect("contrast(#FFFFFF, #767676)", "4.54 : 1", "Contrast ratio. Meets AA for all text, and AAA for large text.")
expect("rgb(300, 0, 0)", "Not a colour", "Each channel of rgb( ) is from 0 to 255.")
expect("red", "#FF0000", "rgb(255, 0, 0), which is red")
expect("red / 2", "#800000", "rgb(128, 0, 0), which is maroon")
expect("red * blue", "#000000", "rgb(0, 0, 0), which is black")
expect("(red + blue) / 2", "#800080", "rgb(128, 0, 128), which is purple")
expect("red / blue", "Not a colour", "Dividing by a colour has no meaning in light, and a channel of 0 would be division by nought.")
expect("red + 2", "Not a colour", "A number cannot be added to or taken from a colour; multiply or divide it instead: red × 2.")
expect("color(display-p3 1 0 0)", "#FF0000", "xyY(0.6800, 0.3200, 0.2290); outside sRGB, within Display P3, so the hex is the nearest sRGB can show")
expect("#FF5733 to xyy", "xyY(0.5671, 0.3550, 0.2832)", "#FF5733, near tomato")
expect("2*3", "= 6")
expect("tan + 1", nil)
// A limit with a letter in it, read from the series; a\sin x is a times sin x, not the arcsine.
expect(#"\lim_{x\to0}\frac{\sin(ax)-a\sin(x)}{x^3}"#, "= a/6 − a³/6")
expect("limit((1-cos(ax))/x^2, x, 0)", "= a²/2")
// Products integrated: e^(ax) with a sine, a polynomial by parts, and by substitution.
expect(#"\int e^{2x}\sin(3x)\,dx"#, "(e^(2x)(2sin(3x) − 3cos(3x)))/13 + C", "The integral with respect to x, up to a constant C")
expect("integrate(x^2 e^(3x))", "((9x² − 6x + 2)·e^(3x))/27 + C", "The integral with respect to x, up to a constant C")
expect("integrate(x cos(3x))", "(cos(3x) + 3x·sin(3x))/9 + C", "The integral with respect to x, up to a constant C")
expect("integrate(2x e^(x^2))", "e^x² + C", "The integral with respect to x, up to a constant C")
// A first-order linear differential equation, by the integrating factor, checked before it is shown;
// one it cannot solve, dy/dx = y², shows nothing rather than something wrong.
expect(#"\frac{dy}{dx}+2xy=2x"#, "y = 1 + C·e^−x²", "The general solution; C is any constant")
expect("dy/dx+2y=e^(3x)", "y = e^(3x)/5 + C·e^−2x", "The general solution; C is any constant")
expect("x dy/dx + y = x^3", "y = x³/4 + C/x", "The general solution; C is any constant")
expect("y'=cos(x)", "y = sin(x) + C", "The general solution; C is any constant")
expect("dy/dx=y^2", nil)
expect("dy/dx+2xy=2x", "y = 1 + C·e^−x²", "The general solution; C is any constant")
// Linear equations in x and y with letters for coefficients, by Cramer's rule, shared factors cancelled.
expect(#"\begin{cases}ax+by=1\\bx+ay=2\end{cases}"#, "x = (a − 2b)/(a² − b²), y = (2a − b)/(a² − b²)", "Where a² − b² ≠ 0")
expect("ax+y+z=1, x+ay+z=1, x+y+az=1", "x = 1/(a + 2), y = 1/(a + 2), z = 1/(a + 2)", "Where a³ − 3a + 2 ≠ 0")
// A matrix given by name, a derivative at a point in LaTeX, a probability by its name, sums to infinity.
expect(#"A^{-1},\quad A=\begin{pmatrix}2&1&0\\1&2&1\\0&1&2\end{pmatrix}"#, "[[3/4, −1/2, 1/4], [−1/2, 1, −1/2], [1/4, −1/2, 3/4]]")
expect(#"\left.\frac{d}{dx}\left(\frac{e^{x^2}\sin(3x)}{1+x^4}\right)\right|_{x=1}"#, "≈ −4.03662", approxAny: true)
expect(#"P(X\geq 8)=\sum_{k=8}^{12}\binom{12}{k}(0.37)^k(0.63)^{12-k}"#, "P(X≥ 8) ≈ 0.0359393", approxAny: true)
expect(#"\sum_{n=1}^{\infty}\frac{n}{3^n}"#, "= 3/4", "≈ 0.75")
expect("sum(n,1,inf,1/n^2)", "≈ 1.64493")
expect("sum(n,1,inf,1/n)", "Does not converge", "The terms do not get small fast enough for the sum to settle.")
// Two terms to a whole power are worked by the binomial theorem: the row of Pascal's triangle,
// the terms written with it, and each worked out; a part in brackets only where it needs them.
expectDetails("(x+1)^4", "(x + 1)⁴", [("Applying the binomial theorem", "(a + b)^n = ∑(k=0…n)  ^nC_k a^(n−k)b^k"),
               ("Writing the coefficients ⁴C_k, row 4 of Pascal's triangle", "1, 4, 6, 4, 1"),
               ("Substituting a = x, b = 1", "= x⁴ + 4x³ + 6x² + 4x + 1")])
expectDetails("(2x^2+1/(ax^2))^9", "(2x² + 1/(ax²))⁹", [("Applying the binomial theorem", "(a + b)^n = ∑(k=0…n)  ^nC_k a^(n−k)b^k"),
               ("Writing the coefficients ⁹C_k, row 9 of Pascal's triangle", "1, 9, 36, 84, 126, 126, 84, 36, 9, 1"),
               ("Substituting a = 2x², b = 1/(ax²)", "= (2x²)⁹ + 9·(2x²)⁸·(1/(ax²)) + 36·(2x²)⁷·(1/(ax²))² + … + (1/(ax²))⁹"),
               ("Working out each term", "= 512x¹⁸ + 2304x¹⁴/a + 4608x¹⁰/a² + 5376x⁶/a³ + 4032x²/a⁴ + 2016/(x²a⁵) + 672/(x⁶a⁶) + 144/(x¹⁰a⁷) + 18/(x¹⁴a⁸) + 1/(x¹⁸a⁹)")])
expect("sin x^2 + cos x^2", nil)
expect("E=h*5e14", "Insufficient information", "A value is required for E or h.")
expectCopy("mg*1.2+1/2mv^2,m=55,v=0.9", "669.075")
expect("12=1.8+4vcos(theta), theta=30°", "v ≈ 2.94449", "Taking θ = 30°")
expect("12=1.8+4vcos(θ), θ=30°", "v ≈ 2.94449", "Taking θ = 30°")
expect("12=1.8+4vcos(theta), theta=pi/6", "v ≈ 2.94449", "Taking θ = π/6")
expect("12=1.8+4vcos(theta), theta=30deg", "v ≈ 2.94449", "Taking θ = 30°")
expect("12=1.8+4vcos(theta), theta=30", "v ≈ 16.5314", "Taking θ = 30 rad")
expect("s=r*theta, theta=2, r=3", "s = 6", "Taking θ = 2, r = 3")
// One equation in letters that always stand together gives them together: neither v nor θ, but v cos(θ).
expect("12=1.8+4vcos(theta)", "v cos(θ) = 51/20", "≈ 2.55")
expect("0.5mv^2=100", "mv² = 200", "m and v cannot be found separately from one equation.")
expect("6/(ab)=2", "ab = 3", "a and b cannot be found separately from one equation.")
expect("-ab=4", "ab = −4", "a and b cannot be found separately from one equation.")
expect("ab/2+1=4", "ab = 6", "a and b cannot be found separately from one equation.")
expect("vcos(theta)=2.55", "Insufficient information", "A value is required for v or θ.")
expect("vcos(theta)+v=3", "Insufficient information", "A value is required for v or θ.")
expect("ab + 1 = a", "Insufficient information", "A value is required for a or b.")
expectDetails("(ab)^2=16", "(ab)² = 16", [("Subtracting the right-hand side from both sides", "(ab)² − (16) = 0"),
               ("Collecting like terms", "(ab)² − 16 = 0"),
               ("Finding two numbers with product ac and sum b", "ac = −16,  b = 0:  4 and −4"),
               ("Splitting the middle term", "(ab)² + 4ab − 4ab − 16 = 0"),
               ("Grouping in pairs", "ab(ab + 4) − 4(ab + 4) = 0"),
               ("Factorising", "(ab + 4)(ab − 4) = 0"),
               ("Zero-product property", "ab + 4 = 0 or ab − 4 = 0"),
               ("Solving each linear factor", "ab = −4 or ab = 4")],
              note: "a and b cannot be found separately from one equation.")
expectCopy("12=1.8+4vcos(theta)", "2.55")
expect("5g", nil)
expect("c", nil)
expect("m*c^2", nil)

// Money: rates against the US dollar, fixed here; the card is answered from them. Case means
// nothing in a currency, and the time the rates were recorded is said only with no connection.
do {
    let recorded = Date(timeIntervalSince1970: 1791417751)
    let stamp = Currency.stamp(recorded)
    Rates.install(["USD": 1, "TWD": 31.5523, "EUR": 0.86, "JPY": 150.2, "BTC": 0.00001, "ETH": 0.0004, "USDT": 1, "XMR": 0.002, "NEAR": 0.5,
                   "XAU": 1 / 4000.0, "XAG": 1 / 50.0], recorded: recorded, offline: false)
    expect("750 USD to NTD", "= 23,664.23 TWD", "1 USD = 31.5523 TWD")
    expect("750USD=NTD?", "= 23,664.23 TWD", "1 USD = 31.5523 TWD")
    expect("750usd=ntd", "= 23,664.23 TWD", "1 USD = 31.5523 TWD")
    expect("750 Usd in twd", "= 23,664.23 TWD", "1 USD = 31.5523 TWD")
    expect("$750 to ntd", "= 23,664.23 TWD", "1 USD = 31.5523 TWD")
    expect("1,000 USD = TWD", "= 31,552.30 TWD", "1 USD = 31.5523 TWD")
    expect("jpy 10 to ntd", "= 2.10 TWD", "1 JPY = 0.210069 TWD")
    expect("¥1000 to ntd", "= 210.07 TWD", "1 JPY = 0.210069 TWD")
    expect("€100 to usd", "= 116.28 USD", "1 EUR = 1.16279 USD")
    expect("USD 750 to Ntd", "= 23,664.23 TWD", "1 USD = 31.5523 TWD")
    expect("20 yen to usd", "= 0.1332 USD", "1 JPY = 0.00665779 USD")
    expect("5 kwd to jpy", "No rate", "open.er-api.com has no rate for KWD.")
    expect("1000 JPY to EUR", "= 5.73 EUR", "1 JPY = 0.0057257 EUR")
    expect("usd to twd", "= 31.55 TWD", "1 USD = 31.5523 TWD")
    expect("1000 USD to JPY", "= 150,200 JPY", "1 USD = 150.2 JPY")
    expectCopy("750 USD to NTD", "23664.23")
    expectDetails("750 USD to NTD", "750.00 USD → TWD", [("Taking the rate", "1 USD = 31.5523 TWD"),
               ("Multiplying", "750.00 × 31.5523 = 23,664.23 TWD"),
               ("Hence", "750.00 USD ≈ 23,664.23 TWD")])
    // Coins and metals, in the same way: a coin by its code, a metal by the troy ounce.
    expect("1 btc to usd", "= 100,000.00 USD", "1 BTC = 100000 USD")
    expect("0.5 BTC to twd", "= 1,577,615.00 TWD", "1 BTC = 3155230 TWD")
    expect("100 usd to btc", "= 0.001 BTC", "1 USD = 0.00001 BTC")
    expect("2 oz gold to usd", "= 8,000.00 USD", "1 XAU = 4000 USD")
    expect("2oz gold to usd", "= 8,000.00 USD", "1 XAU = 4000 USD")
    expect("2oz gold to ntd", "= 252,418.40 TWD", "1 XAU = 126209 TWD")
    expect("2 troy ounces of gold to usd", "= 8,000.00 USD", "1 XAU = 4000 USD")
    expect("10g gold to usd", "= 1,286.03 USD", "1 XAU = 4000 USD")
    expect("1ntd to glod", "= 0.00000792 XAU", "1 TWD = 0.00000792335 XAU")
    expect("1 usd to sliver", "= 0.02 XAG", "1 USD = 0.02 XAG")
    expect("1 usd to bitcon", "= 0.00001 BTC", "1 USD = 0.00001 BTC")
    expect("1 usd to abcd", nil)
    expect("4000 usd to gold g", "= 31.1035 g gold", "1 USD = 0.00777587 g gold")
    expect("4000 usd to g gold", "= 31.1035 g gold", "1 USD = 0.00777587 g gold")
    expect("4000 usd to grams of gold", "= 31.1035 g gold", "1 USD = 0.00777587 g gold")
    expect("4000 usd to gold oz", "= 1.00 oz gold", "1 USD = 0.00025 oz gold")
    expect("1000 ntd to gold g", "= 0.2464 g gold", "1 TWD = 0.000246444 g gold")
    expect("1000 ntd to oz", "= 0.0079 oz gold", "1 TWD = 0.00000792335 oz gold")
    expect("1000 ntd to gold oz", "= 0.0079 oz gold", "1 TWD = 0.00000792335 oz gold")
    expect("gold oz to usd", "= 4,000.00 USD", "1 XAU = 4000 USD")
    expect("2 gold oz to usd", "= 8,000.00 USD", "1 XAU = 4000 USD")
    expect("1 oz to usd", "= 4,000.00 USD", "1 XAU = 4000 USD")
    expect("5 oz to g", "= 141.748 g", "5 oz")
    expect("1 xau to usd", "= 4,000.00 USD", "1 XAU = 4000 USD")
    expect("gold to silver", "= 80.00 XAG", "1 XAU = 80 XAG")
    expect("31.1034768 g gold to usd", "= 4,000.00 USD", "1 XAU = 4000 USD")
    expect("1 eth to btc", "= 0.025 BTC", "1 ETH = 0.025 BTC")
    expect("1 bitcoin to ntd", "= 3,155,230.00 TWD", "1 BTC = 3155230 TWD")
    expect("1 sol to usd", "No rate", "api.coinbase.com has no rate for SOL.")
    // Those Coinbase has not, such as Monero, are from Kraken.
    expect("10usdt to xmr", "= 0.02 XMR", "1 USDT = 0.002 XMR")
    expect("10 USDT to XMR", "= 0.02 XMR", "1 USDT = 0.002 XMR")
    expect("1 monero to usd", "= 500.00 USD", "1 XMR = 500 USD")
    expect("1 xmr to btc", "= 0.005 BTC", "1 XMR = 0.005 BTC")
    expect("2 near to ntd", "= 126.21 TWD", "1 NEAR = 63.1046 TWD")
    expect("1 trx to usd", "No rate", "api.kraken.com has no rate for TRX.")
    expectDetails("1 xmr to btc", "1.00 XMR → BTC", [("Taking the rate", "1 XMR = 0.005 BTC"),
               ("Multiplying", "1.00 × 0.005 = 0.005 BTC"),
               ("Hence", "1.00 XMR ≈ 0.005 BTC")])
    // Nothing else is taken for money: units, equations and a name by itself.
    expect("5 km to miles", "= 3.10686 miles", "5 km")
    expect("x=5", nil)
    expect("a=b", nil)
    expect("750 gbp", nil)
    Rates.install(["USD": 1, "TWD": 31.5523], recorded: recorded, offline: true)
    expect("750 USD to NTD", "= 23,664.23 TWD", "1 USD = 31.5523 TWD  ·  offline, rates of \(stamp)")
    expect("750 USD to XYZ", nil)
    Rates.installNothing(offline: true)
    expect("750 USD to NTD", "No rates saved", "There is no connection, and no rates for USD have yet been saved.")
    Rates.installNothing(offline: false)
    expect("750 USD to NTD", "Fetching the rates", "One moment: the card is made again when they arrive.")
}

// Each line of the panel copies as LaTeX: the equation as it was read, a step, or a solution.
func expectLatex(_ input: String, _ equation: String, solutions: [String]? = nil) {
    guard let d = Solver.details(input) else { failures += 1; return print("FAIL latex \(input): no details") }
    let got = d.solutions.map(\.latex)
    if d.equation.latex != equation || (solutions != nil && got != solutions!) {
        failures += 1
        print("FAIL latex \(input)\n  want \(equation) \(solutions ?? [])\n  got  \(d.equation.latex) \(got)")
    }
}
expectLatex("(20/3)", "\\left(\\frac{20}{3}\\right)", solutions: ["= \\frac{20}{3}", "\\approx 6.66667"])
expectLatex("x^2-5x+6=0", "x^{2} - 5x + 6 = 0", solutions: ["x = 2", "x = 3"])
expectLatex("sqrt(2)/2", "\\frac{\\sqrt{2}}{2}")
expectLatex("sin(30°)", "\\sin(30^{\\circ})", solutions: ["= \\frac{1}{2}", "\\approx 0.5"])
expectLatex("asin(0.5)", "\\arcsin(0.5)", solutions: ["= \\frac{\\pi}{6}", "= 30^{\\circ}"])
expectLatex("sum(k,1,10,k^2)", "\\sum_{k = 1}^{10} k^{2}")
expectLatex("3e8*2", "3 \\times 10^{8} \\cdot 2")
expectLatex("F_n=6.55*2", "F_{n} = 6.55 \\cdot 2")
expectLatex("x^2<=4", "x^{2} \\le 4", solutions: ["-2 \\le x \\le 2"])
expectLatex("theta/2=pi", "\\frac{\\theta}{2} = \\pi")
expectLatex("e^(2x)=5", "e^{2x} = 5")
expectLatex("lcm(4,6)", "\\operatorname{lcm}(4, 6)")
expectLatex("x+y=3, x-y=1", "x + y = 3, \\quad x - y = 1")
// Brackets round a fraction grow with it; those round a single line do not.
expectLatex("x=(1/2)^2", "x = \\left(\\frac{1}{2}\\right)^{2}")
expectLatex("((1/2)+1)*3", "\\left(\\frac{1}{2} + 1\\right) \\cdot 3")
expectLatex("sin(30°)", "\\sin(30^{\\circ})")
expectLatex("2x^2+3x-1=0", "2x^{2} + 3x - 1 = 0",
            solutions: ["x = \\frac{-3 - \\sqrt{17}}{4} \\approx -1.78078", "x = \\frac{-3 + \\sqrt{17}}{4} \\approx 0.280776"])

// A sum in another base: each number written in it, then the sum done there.
expectDetails("16-15 in binary", "16-15 in binary", [("Writing 16 in base 2", "16 = 10000 (base 2)"),
               ("Writing 15 in base 2", "15 = 1111 (base 2)"),
               ("Working it out in base 2", "10000 − 1111 = 1 (base 2)"),
               ("Hence", "1 = 1 (base 2)")], ["1", "decimal 1; hexadecimal 1; octal 1"])
expectDetails("255+1 in hex", "255+1 in hex", [("Writing 255 in base 16", "255 = FF (base 16)"),
               ("Writing 1 in base 16", "1 = 1 (base 16)"),
               ("Working it out in base 16", "FF + 1 = 100 (base 16)"),
               ("Hence", "256 = 100 (base 16)")], ["100", "decimal 256; binary 1 0000 0000; octal 400"])
expectDetails("12*12 in hex", "12*12 in hex", [("Writing 12 in base 16", "12 = C (base 16)"),
               ("Working it out in base 16", "C × C = 90 (base 16)"),
               ("Hence", "144 = 90 (base 16)")], ["90", "decimal 144; binary 1001 0000; octal 220"])

// Working must explain the operation and preserve the mathematics, not just end at the right answer.
func workingCheck(_ ok: @autoclosure () -> Bool, _ message: String) {
    if !ok() { failures += 1; print("FAIL working: \(message)") }
}
for typed in ["sin2x+cos2x-1=2sinx(cosx-sinx)", #"\sin 2\theta+\cos 2\theta-1=2\sin\theta(\cos\theta-\sin\theta)"#] {
    let steps = Solver.details(typed)?.steps ?? []
    workingCheck(steps.contains { $0.label == "Double-angle formula" && $0.math?.plain.contains("sin(2") == true }, "sine double-angle formula missing: \(typed)")
    workingCheck(steps.contains { $0.label == "Double-angle formula" && $0.math?.plain.contains("cos(2") == true }, "cosine double-angle formula missing: \(typed)")
    workingCheck(steps.contains { $0.label.hasPrefix("Taking out the common factor") }, "factoring step missing: \(typed)")
    workingCheck(!steps.contains { ($0.note ?? "").contains("values tried") }, "sampling presented as a proof")
}
if let eq = try? Parser.parse("sin2x+cos2x-1=2sinx(cosx-sinx)"), let proof = TrigProof.prove(eq) {
    // Every displayed formula and every line of this left-to-right derivation is checked at
    // independent angles. These checks catch a false intermediate equality, not just a bad answer.
    for step in proof.steps("x") {
        guard let line = step.math?.plain else { continue }
        if line.hasPrefix("= ") {
            if let tokens = try? Parser.tokenize(Latex.plain(String(line.dropFirst(2)))), let expression = try? Parser.expression(tokens, constants: []) {
                for x in [-2.13, -0.83, 0.0, 0.39, 1.27, 3.41] {
                    workingCheck(abs(expression.eval(x) - (sin(2*x) + cos(2*x) - 1)) < 1e-10, "invalid trig intermediate: \(line)")
                }
            } else { workingCheck(false, "unreadable trig intermediate: \(line)") }
        } else if line.contains("="), let equality = try? Parser.parse(Latex.plain(line)) {
            for x in [-2.13, -0.83, 0.0, 0.39, 1.27, 3.41] {
                workingCheck(abs(equality.left.eval(x) - equality.right.eval(x)) < 1e-10, "invalid trig formula: \(line)")
            }
        }
    }
} else { workingCheck(false, "the reported trigonometric identity was not proved") }
for typed in ["sin(x)^2+cos(x)^2=1+0.0000000001*sin(x)", "0.0000000000001*sin(x)=0", "sin(x)/sin(x)=1"] {
    if let eq = try? Parser.parse(typed) { workingCheck(TrigProof.prove(eq) == nil, "false or domain-restricted expression certified: \(typed)") }
}
workingCheck(Solver.details("sin(x)/cos(x)")?.steps.contains { ($0.note ?? "").contains("not a symbolic") } == true, "unproved trig simplification must say it is a numerical check")

for a in -5...5 where a != 0 {
    for c in [-3, 0, 4] where c != a {
        let b = a + 2, d = 7 - c
        let typed = "\(a)*(x+2)+\(b)=\(c)*x+\(d)"
        let reference = Double(d - 2*a - b) / Double(a - c)
        guard let details = Solver.details(typed) else { workingCheck(false, "no linear working: \(typed)"); continue }
        workingCheck(!details.steps.isEmpty, "missing linear operations: \(typed)")
        for step in details.steps {
            guard let line = step.math?.plain else { continue }
            let sides = line.components(separatedBy: " = ")
            for i in 1..<sides.count {
                func expression(_ text: String) -> Expr? {
                    guard let tokens = try? Parser.tokenize(Latex.plain(text)) else { return nil }
                    var parser = Parser.State(tokens: tokens, unknown: "x", constants: [])
                    guard let e = try? parser.expression(), parser.at == tokens.count else { return nil }
                    return e
                }
                guard let left = expression(sides[i-1]), let right = expression(sides[i]),
                      let p = poly(.op("-", left, right)).map(trim) else { workingCheck(false, "unreadable linear step: \(line)"); continue }
                workingCheck(abs(left.eval(reference) - right.eval(reference)) < 1e-9, "linear step lost its solution: \(line)")
                if p.count == 2 { workingCheck(abs(-p[0]/p[1] - reference) < 1e-9, "linear step changed the root: \(line)") }
            }
        }
    }
}
workingCheck(Solver.details("3x=9")?.steps.contains { $0.label == "Dividing both sides by 3" } == true, "the final division was hidden")
workingCheck(Solver.details("x^2-5x+6=0")?.steps.contains { $0.label == "Zero-product property" } == true, "factorising an equation must explain why each factor can be set to zero")
workingCheck(Solver.details("2x^2+3x-1=0")?.steps.contains { $0.label == "Substituting the coefficients and discriminant" } == true, "quadratic formula substitution missing")
for (typed, rule) in [("derivative(sin(x^2))", "sin derivative and chain rule"), ("derivative(x^2*sin(x))", "Product rule"), ("derivative(sin(x)/x)", "Quotient rule")] {
    workingCheck(Solver.details(typed)?.steps.contains { $0.label == rule && $0.note != nil } == true, "specific differentiation rule missing: \(typed)")
}
workingCheck(Solver.details("derivative(x^3,2)")?.steps.last?.math?.plain.contains("2") == true, "derivative point substitution missing")
workingCheck(Solver.details("integrate(x^2,0,1)")?.steps.contains { $0.label == "Fundamental theorem of calculus" } == true, "definite-integral theorem missing")
workingCheck(Solver.details("integrate(sin(3x))")?.steps.contains { $0.label == "Using a linear substitution" } == true, "integration substitution missing")
workingCheck(Solver.details("integrate(x^2)")?.steps.contains { $0.label == "Adding the constant of integration" } == true, "the only integral step was removed")
let fractionWorkingCases = ["2/3+1/6", "3/4-1/6", "(1/2+1/3)/(2/5)", "-2/3+5/6", "(2/3)^2+1/9", "0.25+0.5"]
    + (-3...3).flatMap { a in (2...6).map { b in "(\(a)/\(b)+\(b-2)/\(b+1))*2" } }
for typed in fractionWorkingCases {
    guard let e = try? Parser.constant(typed), let expected = e.number?.rational,
          let steps = Working.arithmetic(e, lead: "= ") else { workingCheck(false, "no exact arithmetic steps: \(typed)"); continue }
    for step in steps {
        guard let line = step.math?.plain, let changed = try? Parser.constant(Latex.plain(String(line.dropFirst(2)))) else { workingCheck(false, "unreadable arithmetic step: \(typed)"); continue }
        workingCheck(changed.number?.rational == expected, "arithmetic step changed its exact value: \(line)")
    }
}
workingCheck(Solver.details("x/3+1=2")?.steps.contains { $0.label == "Dividing both sides by 1/3" } == true, "fractional linear coefficients must remain exact in the working")
for typed in ["x^2", "3x^2+2x+1", "sin(3x)", "1/(2x+1)", "x*exp(x)", "x^2*exp(2x)", "x*sin(x)", "x^2*cos(3x)", "2*x*exp(x^2)", "cos(x)*sin(x)", "2*x*cos(x^2)", "exp(x)*sin(x)", "exp(x)*cos(2x)"] {
    guard let tokens = try? Parser.tokenize(typed) else { workingCheck(false, "unreadable integrand: \(typed)"); continue }
    var parser = Parser.State(tokens: tokens, unknown: "x", constants: [])
    guard let integrand = try? parser.expression(), let primitive = Algebra.integrated(integrand) else { workingCheck(false, "missing primitive: \(typed)"); continue }
    for x in [0.37, 0.81, 1.23] {
        let h = 2e-5
        let derivative = (-primitive.eval(x+2*h) + 8*primitive.eval(x+h) - 8*primitive.eval(x-h) + primitive.eval(x-2*h))/(12*h)
        let expected = integrand.eval(x)
        workingCheck(abs(derivative-expected) <= 2e-7*max(1,abs(expected)), "integration trace primitive fails an independent finite-difference check: \(typed)")
    }
}
workingCheck(Solver.details("integrate(x*exp(x))")?.steps.contains { $0.label == "Applying integration by parts" } == true, "integration by parts must show the transformed integral")
workingCheck(Solver.details("integrate(2*x*exp(x^2))")?.steps.contains { $0.label == "Rewriting the integral in u" } == true, "nonlinear substitution must show the integral in u")
// Agreement at the substitution detector's five points must not be printed as a proof.
let sampledFactor = Expr.op("+", .op("*", .num(2), .unknown), [0.31, 0.73, 1.17, 1.61, 2.29].reduce(Expr.num(1)) { .op("*", $0, .op("-", .unknown, .num($1))) })
let sampledExponential = Expr.call("exp", .op("^", .unknown, .num(2)))
let sampledSteps = Algebra.productSteps(sampledFactor, sampledExponential, name: "x") ?? []
workingCheck(sampledSteps.contains { $0.label == "Numerically suggested substitution" }, "sample-only substitution was presented as an algebraic derivation")
workingCheck(!sampledSteps.contains { $0.label == "Rewriting the integral in u" }, "unproved substitution must not display an equality in u")

// The final operation is retained as the solution's heading, with its result drawn once.
for typed in ["6*7", "2/3+1/6", "factor(2x^2+3x-2)", "integrate(x^2)"] {
    guard let d = Solver.details(typed) else { workingCheck(false, "no presentation: \(typed)"); continue }
    let shown = d.presentation
    workingCheck(shown.solutionTitle.hasPrefix("Solution"), "missing solution heading")
    workingCheck(!shown.steps.contains { step in step.math.map { math in d.solutions.contains { $0.plain == math.plain } } ?? false }, "duplicate result above Solution: \(typed)")
}
if let shown = Solver.details("6*7")?.presentation {
    workingCheck(shown.solutionTitle == "Solution (Multiplying)", "the operation was lost while merging the final answer")
}
if let d = Solver.details("integrate(x^2)") {
    workingCheck(d.presentation.solutionNote?.contains("constant") == true, "the explanation of C was lost while merging the result")
}
if let d = Solver.details("x^2-5x+6=0") { workingCheck(d.solutions.count == 2 && d.presentation.solutionTitle == "Solutions", "distinct roots were merged") }

// i is a constant in comparisons. Principal square roots are not the two roots of an equation.
for (typed, want) in [("i=sqrt(-1)", "True"), ("-i=sqrt(-1)", "False"), ("sqrt(-1)=i", "True"), ("sqrt(-1)=-i", "False"),
                      ("i^2=-1", "True"), ("(-i)^2=-1", "True"), ("sqrt(-4)=2i", "True"), ("sqrt(-4)=-2i", "False"),
                      ("i=i", "True"), ("i=-i", "False"), ("i^0=1", "True"), ("(1+i)^2=2i", "True"),
                      ("1+i=2+i", "False"), ("e^(i*pi)=-1", "True"), ("sqrt(-1)*sqrt(-1)=-1", "True"),
                      ("(-1)^(1/2)=i", "True"), ("1e-13*i=0", "False"), ("i<1", "Undefined"), ("0^(-i)=0", "Undefined"),
                      ("i=sqrt(-1) && -i != sqrt(-1)", "True")] {
    workingCheck(Solver.solve(typed)?.exact == want, "complex comparison \(typed): wanted \(want), got \(Solver.solve(typed)?.exact ?? "nil")")
}
workingCheck(Solver.details("i=sqrt(-1)")?.steps.contains { $0.label == "Principal square root" } == true, "complex square root needs its principal-value explanation")
workingCheck(Solver.solve("z^2=-1")?.exact == "z = ±i", "an equation's two complex roots were confused with the principal square root")
for scale in [1e-100, 1.0, 1e100, 1e308] {
    for (re, im) in [(0.3,0.4), (-0.3,0.4), (-0.3,-0.4), (0.3,-0.4), (-0.5,0)] {
        let z = Complex(re*scale, im*scale), root = Complex.sqrt(z), back = root*root
        workingCheck(root.isFinite && root.re >= 0, "principal square root outside numeric range or wrong branch")
        workingCheck(hypot((back.re-z.re)/scale,(back.im-z.im)/scale) < 1e-12, "complex square root did not square back to its input")
    }
}

// Manual Refresh must bypass the automatic cooldown, survive failure, and avoid duplicate
// in-flight requests. All responses are mocked and nothing is written to saved preferences.
let originalRatesTransport = Rates.transport, originalRatesPersistence = Rates.persist
Rates.installNothing(offline: false)
Rates.fixed = false
Rates.persist = { _ in }
var refreshRequests = 0, refreshStatus = 200, refreshedTWD = 32.0
Rates.transport = { request, complete in
    refreshRequests += 1
    let object: [String: Any] = ["result": "success", "rates": ["USD": 1.0, "TWD": refreshedTWD]]
    complete(try? JSONSerialization.data(withJSONObject: object), HTTPURLResponse(url: request.url!, statusCode: refreshStatus, httpVersion: nil, headerFields: nil), nil)
}
func finishRateRefresh() {
    let deadline = Date().addingTimeInterval(2)
    while Rates.isRefreshing && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.005)) }
    workingCheck(!Rates.isRefreshing, "rate refresh remained stuck")
}
Rates.refresh(.fiat)
Rates.refresh(.fiat, force: true)
workingCheck(refreshRequests == 1, "duplicate in-flight rate requests")
finishRateRefresh()
Rates.refresh(.fiat)
workingCheck(refreshRequests == 1, "automatic refresh ignored its cooldown")
Rates.refresh(.fiat, force: true)
finishRateRefresh()
workingCheck(refreshRequests == 2 && Rates.table?["TWD"] == 32, "manual refresh did not bypass cooldown")
refreshStatus = 503
Rates.refresh(.fiat, force: true)
finishRateRefresh()
workingCheck(Rates.state(.fiat).offline && Rates.state(.fiat).error?.contains("503") == true && Rates.table?["TWD"] == 32, "failed refresh discarded saved rates or hid the error")
refreshStatus = 200; refreshedTWD = 33
Rates.refresh(.fiat, force: true)
finishRateRefresh()
workingCheck(refreshRequests == 4 && !Rates.state(.fiat).offline && Rates.table?["TWD"] == 33, "retry after a failure did not recover")
Rates.transport = originalRatesTransport; Rates.persist = originalRatesPersistence; Rates.fixed = true

print(failures == 0 ? "all passed" : "\(failures) failed")
exit(failures == 0 ? 0 : 1)

