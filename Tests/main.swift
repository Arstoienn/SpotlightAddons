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
expect("E=mc^2", nil)
expect("h=0.5gt^2", nil)

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
expect("v_0t=10", nil)
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
expect("1<2<3", nil)
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
expect("x^2-5x+6", nil)
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
expect("ax^2+bx=c", nil)
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
expect("-5", nil)
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
expect("1", nil)
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
expectDetails("ans*2+1", "ans·2 + 1", [("Substituting ans = 40", "= 40·2 + 1"), ("Multiplying", "= 80 + 1"), ("Adding", "= 81")], ["= 81"])
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
with("numberFacts", false) {
    expect("2048", nil)
    expect("2+2", "= 4")
}
with("constant.g", false) {
    expect("x=2g", nil)
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

expectDetails("2n^2+3n+1=0", "2n² + 3n + 1 = 0",
              [("Factorising", "(n + 1)(2n + 1) = 0"), ("Hence", "n = −1 or n = −1/2")],
              ["n = −1", "n = −1/2 ≈ −0.5"])
expectDetails("2x+3=11", "2x + 3 = 11", [("Writing in standard form", "x − 4 = 0"), ("Hence", "x = 4")], ["x = 4"])
expectDetails("3x=2", "3x = 2", [("Writing in standard form", "3x − 2 = 0"), ("Rearranging", "3x = 2"), ("Dividing by 3", "x = 2/3")], ["x = 2/3 ≈ 0.666667"])
expectDetails("2n^2=10", "2n² = 10", [("Writing in standard form", "n² − 5 = 0"), ("Isolating n²", "n² = 5"), ("Taking the square root", "n = ±√5")],
              ["n = −√5 ≈ −2.23607", "n = √5 ≈ 2.23607"])
expectDetails("2x^2+3x-1=0", "2x² + 3x − 1 = 0",
              [("Evaluating the discriminant", "b² − 4ac = 3² − 4·2·(−1) = 17"), ("Applying the quadratic formula", "x = (−b ± √(b² − 4ac))/2a = (−3 ± √17)/4")],
              ["x = (−3 − √17)/4 ≈ −1.78078", "x = (−3 + √17)/4 ≈ 0.280776"])
expectDetails("x^2+2x+5=0", "x² + 2x + 5 = 0",
              [("Evaluating the discriminant", "b² − 4ac = 2² − 4·1·5 = −16"), ("Hence", "b² − 4ac < 0")],
              ["x = −1 ± 2i", "No real solutions"])
expectDetails("x^2-2x+1=0", "x² − 2x + 1 = 0", [("Factorising", "(x − 1)² = 0"), ("Hence", "x = 1")], ["x = 1"])
expectDetails("(x+1)(x-1)=3", "(x + 1)(x − 1) = 3", [("Writing in standard form", "x² − 4 = 0"), ("Factorising", "(x + 2)(x − 2) = 0"), ("Hence", "x = −2 or x = 2")])
expectDetails("x^3-6x^2+11x-6=0", "x³ − 6x² + 11x − 6 = 0", [("Factorising", "(x − 1)(x − 2)(x − 3) = 0")], ["x = 1", "x = 2", "x = 3"])
expectDetails("x^3=2", "x³ = 2", [("Writing in standard form", "x³ − 2 = 0"), ("Solving numerically", "This polynomial of degree 3 is not readily factorised; its real roots are therefore determined numerically.")], ["x ≈ 1.25992"])
expectDetails("sin(n rad)=1", "sin(n) = 1", [("Stating the general solution", "n = π/2 + 2kπ, k ∈ ℤ")], ["n = π/2 ≈ 1.571 (90°)"],
              note: "These are the solutions for 0 ≤ n ≤ 2π; further solutions lie outside this interval.")
expectDetails("sin(x rad)=0.5", "sin(x) = 0.5", [("Stating the general solution", "x = π/6 + 2kπ or x = 5π/6 + 2kπ, k ∈ ℤ")],
              ["x = π/6 ≈ 0.524 (30°)", "x = 5π/6 ≈ 2.618 (150°)"])
expectDetails("(20^2*sin(2x rad))/9.81=20", "(20²·sin(2x))/9.81 = 20",
              [("Isolating sin(2x)", "sin(2x) = 0.4905"),
               ("Stating the general solution", "2x = 0.512663 + 2kπ or 2x = 2.62893 + 2kπ, k ∈ ℤ"),
               ("Hence", "x = 0.256332 + kπ or x = 1.31446 + kπ, k ∈ ℤ")],
              ["x ≈ 0.256332 (14.6867°)", "x ≈ 1.31446 (75.3133°)", "x ≈ 3.39792 (194.687°)", "x ≈ 4.45606 (255.313°)"])
expectDetails("(20^2*sin(2x rad))/g=20", "(20²·sin(2x))/g = 20",
              [("Substituting g = 9.8 m s⁻²", "(20²·sin(2x))/9.8 = 20"), ("Isolating sin(2x)", "sin(2x) = 0.49"),
               ("Stating the general solution", "2x = 0.51209 + 2kπ or 2x = 2.6295 + 2kπ, k ∈ ℤ"),
               ("Hence", "x = 0.256045 + kπ or x = 1.31475 + kπ, k ∈ ℤ")])
expectDetails("2sin(3x+1 rad)-1=0", "2sin(3x + 1) − 1 = 0",
              [("Isolating sin(3x + 1)", "sin(3x + 1) = 0.5"),
               ("Stating the general solution", "3x + 1 = π/6 + 2kπ or 3x + 1 = 5π/6 + 2kπ, k ∈ ℤ"),
               ("Hence", "x = −0.1588 + 2kπ/3 or x = 0.539331 + 2kπ/3, k ∈ ℤ")])
expectDetails("tan(x/2 rad)=1", "tan(x/2) = 1",
              [("Stating the general solution", "x/2 = π/4 + kπ, k ∈ ℤ"), ("Hence", "x = π/2 + 2kπ, k ∈ ℤ")], ["x = π/2 ≈ 1.571 (90°)"])
expectDetails("cos(x rad)=0.5", "cos(x) = 0.5", [("Stating the general solution", "x = ±π/3 + 2kπ, k ∈ ℤ")])
expectDetails("tan(x rad)=1", "tan(x) = 1", [("Stating the general solution", "x = π/4 + kπ, k ∈ ℤ")])
expectDetails("sin(x rad)=2", "sin(x) = 2", [("Stating the general solution", "No solution, since −1 ≤ sin x ≤ 1")], ["No real solutions in the interval −1000 ≤ x ≤ 1000"])
expectDetails("2^x=8", "2^x = 8", [("Expressing both sides as powers of 2", "2^x = 2³"), ("Equating the exponents", "x = 3")], ["x = 3"])
expectDetails("10=0.1^x", "10 = 0.1^x",
              [("Interchanging the sides", "0.1^x = 10"), ("Expressing both sides as powers of 10", "(10^−1)^x = 10¹"),
               ("Multiplying the exponents", "10^−x = 10¹"), ("Equating the exponents", "−x = 1"), ("Hence", "x = −1")], ["x = −1"])
expectDetails("4^x=8", "4^x = 8",
              [("Expressing both sides as powers of 2", "(2²)^x = 2³"), ("Multiplying the exponents", "2^(2x) = 2³"),
               ("Equating the exponents", "2x = 3"), ("Hence", "x = 3/2")])
expectDetails("3^x=10", "3^x = 10",
              [("Taking the logarithm of both sides", "ln(3^x) = ln 10"), ("Applying the power rule for logarithms", "x·ln 3 = ln 10"),
               ("Dividing by ln 3", "x = ln 10/ln 3"), ("Hence", "x ≈ 2.0959")])
expectDetails("e^x=10", "e^x = 10",
              [("Taking the natural logarithm of both sides", "ln(e^x) = ln 10"), ("Simplifying", "x = ln 10"), ("Hence", "x ≈ 2.30259")],
              ["x ≈ 2.30259"])
expectDetails("ln x=1", "ln(x) = 1", [("Rewriting in exponential form", "x = e¹"), ("Hence", "x ≈ 2.71828")])
expectDetails("log x=2", "log(x) = 2", [("Rewriting in exponential form", "x = 10²"), ("Hence", "x = 100")])
expectDetails("√x=3", "√x = 3", [("Squaring both sides", "x = 3²"), ("Hence", "x = 9")], ["x = 9"])
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
expectDetails("F_n=0.4*20cos(35°)", "F_n = 0.4·20·cos(35°)", [("Simplifying", "F_n = 8·0.819152"), ("Multiplying", "F_n = 6.55322")])
expectDetails("3sin(x rad)=0", "3sin(x) = 0", [("Isolating sin(x)", "sin(x) = 0"), ("Stating the general solution", "x = kπ, k ∈ ℤ")],
              ["x = 0 (0°)", "x = π ≈ 3.142 (180°)", "x = 2π ≈ 6.283 (360°)"])
expectDetails("x/3+1=2", "x/3 + 1 = 2", [("Writing in standard form", "x − 3 = 0"), ("Hence", "x = 3")])

expectDetails(#"PES=\frac{\frac{120000-80000}{80000}}{\frac{250-200}{200}}"#,
              "PES = ((120000 − 80000)/80000)/((250 − 200)/200)",
              [("Subtracting", "PES = (40000/80000)/(50/200)"), ("Dividing", "PES = 0.5/0.25"), ("Dividing", "PES = 2")],
              ["PES = 2"])
expectDetails("cost=12*3+4", "cost = 12·3 + 4", [("Multiplying", "cost = 36 + 4"), ("Adding", "cost = 40")])

expectDetails("F_n=20cos(60°)", "F_n = 20cos(60°)",
              [("Evaluating the function", "F_n = 20·0.5"), ("Multiplying", "F_n = 10")])

expectDetails("12*3+4", "12·3 + 4", [("Multiplying", "= 36 + 4"), ("Adding", "= 40")], ["= 40"])

expectDetails("360", "360", [("Dividing by 2 repeatedly", "360 = 2³·45"), ("Dividing by 3 repeatedly", "45 = 3²·5"), ("Hence", "360 = 2³·3²·5")],
              ["360 = 2³·3²·5"])
expectDetails("2048", "2048", [("Dividing by 2 repeatedly", "2048 = 2¹¹")], ["2048 = 2¹¹"])
expectDetails("72", "72", [("Dividing by 2 repeatedly", "72 = 2³·9"), ("Dividing by 3 repeatedly", "9 = 3²"), ("Hence", "72 = 2³·3²")])
expectDetails("97", "97", [("Testing for divisors", "97 is divisible by no prime up to its square root, 9.84886; it is therefore prime.")], ["97 is prime"])
expectDetails("0.375", "0.375", [("Writing as a fraction", "0.375 = 375/1000"), ("Dividing through by 125", "0.375 = 3/8")], ["0.375 = 3/8"])

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
expectDetails("3ab-ab+2b", "3ab − ab + 2b", [("Collecting like terms", "= 2ab + 2b"), ("Taking out the common factor", "= 2b(a + 1)")])
expectDetails("-2x-4", "−2x − 4", [("Taking out the common factor", "= −2(x + 2)")])

expectDetails(#"\frac{1}{7b}=\frac{11x}{y}"#, "1/(7b) = 11x/y",
              [("Collecting the terms in x", "11x/y = 1/(7b)"), ("Hence", "x = y/(77b)")], ["x = y/(77b)"])
expectDetails("E=1/2mv^2, v=?", "E = 1/2·mv²",
              [("Collecting the terms in v", "mv²/2 = E"), ("Isolating v²", "v² = 2E/m"), ("Taking the square root", "v = ±√(2E/m)")])

// A comparison: both sides worked out together, then compared
expectDetails("2^2=4", "2² = 4", [("Evaluating the power", "4 = 4"), ("Comparing the two sides", "4 = 4")], ["True"])
expectDetails("1/3 ~= 0.3333", "1/3 ≈ 0.3333", [("Dividing", "0.333333 ≈ 0.3333"), ("Comparing the two sides", "0.333333 > 0.3333")], ["True"])
expectDetails("9e16=1*!c^2", "9×10¹⁶ = 1c²",
              [("Substituting c = 3.00×10⁸ m s⁻¹", "9×10¹⁶ = 1(3×10⁸)²"), ("Evaluating the power", "9×10¹⁶ = 1·9×10¹⁶"),
               ("Multiplying", "9×10¹⁶ = 9×10¹⁶"), ("Comparing the two sides", "9×10¹⁶ = 9×10¹⁶")], ["True"])
expectDetails("3*4 < 2^3", "3·4 < 2³", [("Simplifying", "12 < 8"), ("Comparing the two sides", "12 > 8")], ["False"])
expectDetails("x=5!/(3!2!)", "x = 5!/(3!·2!)",
              [("Evaluating the factorials", "x = 120/(6·2)"), ("Multiplying", "x = 120/12"), ("Dividing", "x = 10")], ["x = 10"])
expectDetails("x=3!^2", "x = (3!)²", [("Evaluating the factorial", "x = 6²"), ("Evaluating the power", "x = 36")])

// A constant is written in as its value, and what follows is in decimals
expectDetails("h=0.5g*3^2", "h = 0.5g·3²",
              [("Substituting g = 9.8 m s⁻²", "h = 0.5·9.8·3²"), ("Simplifying", "h = 4.9·9"), ("Multiplying", "h = 44.1")], ["h ≈ 44.1"])
expectDetails("E=0.002c^2", "E = 0.002c²",
              [("Substituting c = 3.00×10⁸ m s⁻¹", "E = 0.002(3×10⁸)²"), ("Evaluating the power", "E = 0.002·9×10¹⁶"),
               ("Multiplying", "E = 1.8×10¹⁴")], ["E = 1.8×10¹⁴"])
expectDetails("20=0.5g*t^2", "20 = 0.5g·t²",
              [("Substituting g = 9.8 m s⁻²", "20 = 0.5·9.8·t²"), ("Writing in standard form", "4.9t² − 20 = 0"),
               ("Isolating t²", "t² = 4.08163"), ("Taking the square root", "t ≈ ±2.02031")], ["t ≈ −2.02031", "t ≈ 2.02031"])
expectDetails("100=m*g", "100 = m·g",
              [("Substituting g = 9.8 m s⁻²", "100 = m·9.8"), ("Writing in standard form", "9.8m − 100 = 0"),
               ("Rearranging", "9.8m = 100"), ("Dividing by 9.8", "m ≈ 10.2041")], ["m ≈ 10.2041"])
expectDetails("0=20t-0.5g*t^2", "0 = 20t − 0.5g·t²",
              [("Substituting g = 9.8 m s⁻²", "0 = 20t − 0.5·9.8·t²"), ("Writing in standard form", "4.9t² − 20t = 0"),
               ("Evaluating the discriminant", "b² − 4ac = (−20)² − 4·4.9·0 = 400"),
               ("Applying the quadratic formula", "t = (−b ± √(b² − 4ac))/2a = (20 ± √400)/9.8")], ["t = 0", "t ≈ 4.08163"])
expectDetails("x^2=pi", "x² = π",
              [("Writing in standard form", "x² − 3.14159 = 0"), ("Isolating x²", "x² = 3.14159"), ("Taking the square root", "x ≈ ±1.77245")])
expectDetails("v=-(3-1)", "v = −(3 − 1)", [("Subtracting", "v = −2")])

expectDetails(#"\sum_{k=0}^{10}k20"#, "∑(k = 0…10) k·20",
              [("Writing out the terms", "= 0·20 + 1·20 + 2·20 + … + 9·20 + 10·20"),
               ("Evaluating each term", "= 0 + 20 + 40 + … + 180 + 200"),
               ("Adding the terms", "= 1100")], ["= 1100"])
expectDetails(#"\sum_{k=1}^{100} k"#, "∑(k = 1…100) k",
              [("Writing out the terms", "= 1 + 2 + 3 + … + 99 + 100"), ("Adding the terms", "= 5050")])

expectDetails("2x+y=5, x-y=1", "2x + y = 5,   x − y = 1",
              [("(1)", "2x + y = 5"), ("(2)", "x − y = 1"), ("Eliminating y: (1) + (2)", "3x = 6"),
               ("Hence", "x = 2"), ("Substituting x = 2 into (1)", "2·2 + y = 5"), ("Hence", "y = 1")],
              ["x = 2", "y = 1"])
expectDetails("3x=2, 3x=1", "3x = 2,   3x = 1",
              [("(1)", "3x = 2"), ("(2)", "3x = 1"), ("Solving (1)", "x = 2/3"), ("Solving (2)", "x = 1/3")],
              ["No solution"], note: "The lines are parallel and do not intersect.")
expectDetails("y=2x+1, y=-x+4", "y = 2x + 1,   y = −x + 4",
              [("Writing (1) in standard form", "2x − y = −1"), ("Writing (2) in standard form", "x + y = 4"), ("Eliminating y: (1) + (2)", "3x = 3"),
               ("Hence", "x = 1"), ("Substituting x = 1 into (1)", "2·1 − y = −1"), ("Hence", "y = 3")])

expectDetails("x=2, y=1", "x = 2,   y = 1", [("(1)", "x = 2"), ("(2)", "y = 1")], ["x = 2", "y = 1"])
expectDetails("2x=4, 3y=2", "2x = 4,   3y = 2",
              [("Writing (1) in standard form", "x = 2"), ("(2)", "3y = 2"), ("Solving (2) for y", "y = 2/3")])

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

print(failures == 0 ? "all passed" : "\(failures) failed")
exit(failures == 0 ? 0 : 1)
