import Foundation

// Curves to draw: an equation in x and y alone, or f(x) = …, is drawn and its shape described, and a
// formula in other letters is still turned round. Run from Tests/main.swift.
func relationTests() {
    expect("y=x^2", "Parabola with vertex (0, 0), opening upwards", "x-intercept 0; y-intercept 0")
    expect("f(x)=x", "Straight line with gradient 1 and y-intercept 0", "x-intercept 0; y-intercept 0")
    expect("f(x)=x^2-1", "Parabola with vertex (0, −1), opening upwards", "x-intercepts −1, 1; y-intercept −1")
    expect("g(t)=t^2-4t", "Parabola with vertex (2, −4), opening upwards", "x-intercepts 0, 4; y-intercept 0")
    expect("y=2x+1", "Straight line with gradient 2 and y-intercept 1", "x-intercept −1/2; y-intercept 1")
    expect("x+y=5", "Straight line with gradient −1 and y-intercept 5", "x-intercept 5; y-intercept 5")
    expect("x^2+y^2=5", "Circle with centre (0, 0) and radius √5", "radius ≈ 2.23607; x-intercepts −√5, √5; y-intercepts −√5, √5")
    expect("(x-1)^2+(y+2)^2=9", "Circle with centre (1, −2) and radius 3", "x-intercepts 1 − √5, 1 + √5; y-intercepts −2 − 2√2, −2 + 2√2")
    expect("x^2/4+y^2=1", "Ellipse centred at (0, 0), with semi-axes 2 and 1", "x-intercepts −2, 2; y-intercepts −1, 1")
    expect("y^2=x", "Parabola with vertex (0, 0), opening to the right", "x-intercept 0; y-intercept 0")
    expect("x^2-y^2=1", "Hyperbola centred at (0, 0)", "x-intercepts −1, 1")
    expect("y=x^3-3x", "Curve with a maximum at (−1, 2) and a minimum at (1, −2)", "x-intercepts −√3, 0, √3; y-intercept 0")
    expect("y=sin x", "Curve through (0, 0)", "x-intercepts 0, π, 2π; y-intercept 0")
    expect("y=e^x", "Curve through (0, 1)", "y-intercept 1")
    expect("y=1/x", "Curve not meeting the y-axis", nil)
    for input in ["y=x^2", "f(x)=x", "x^2+y^2=5", "y=sin x", "xy=1", "y=1/x"] {
        let d = Solver.details(input)
        workingCheck(d?.graph != nil, "\(input) was not drawn")
        workingCheck(d?.presentation.solutionTitle == "Features", "\(input) did not head its findings Features")
    }
    // A circle is drawn as the circle, its centre and the axes' crossings marked.
    workingCheck(Solver.details("x^2+y^2=5")?.graph?.points.count == 5, "the circle's centre and four intercepts were not all marked")
    // Values given to a formula that leave a curve: the formula, as before, and its graph.
    expect("y=mx+c, m=2, c=21", "y = 2x + 21", "Taking m = 2, c = 21")
    workingCheck(Solver.details("y=mx+c, m=2, c=21")?.graph != nil, "the line left by y = mx + c with m and c given was not drawn")
    // A letter asked for: the equation turned round to give it, not drawn.
    expect("x+y=3, y=?", "y = 3 − x")
    // Letters besides x and y: a formula, turned round as before, and no curve.
    workingCheck(Solver.answer("v=u+at").map { !$0.solution.exact.hasPrefix("Straight") } ?? true, "a formula was taken for a curve")
    workingCheck(Solver.answer("x^2-5x+6=0")?.solution.exact == "x = 2, 3", "an equation in x alone was no longer solved")
}
