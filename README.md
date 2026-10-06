# Spotlight Plus

Type an equation into Spotlight and the answer appears on a glass card just above it, as you type,
the way Spotlight's own calculator answers 2+2. Rest the pointer on the card and it grows into a
panel with the working, every solution and a graph; move the pointer off and it shrinks back.

Type `clipboard` or `history`, choose Clipboard History in Spotlight's list and press Return, and
Spotlight comes back open on its clipboard history, the view that ⌘Space and then ⌘4 gives.
Clipboard History is an entry Spotlight Plus puts in Spotlight's list itself, through Core
Spotlight; there is no second app. Spotlight Plus Settings is another, and opens the settings.

## What it solves

- **One equation, one unknown**: `2n^2=10` gives `n = ±√5`. Linear and quadratic equations are
  solved exactly; higher degrees, exponentials, logarithms and trigonometry numerically, with the
  general solution where there is one (`sin(n)=1` gives `n = π/2 + 2kπ`). An angle, an unknown
  that is only inside sin, cos and tan, is answered for one turn from zero, in radians and in
  degrees: `sin(x)=0.5` gives `x = π/6, 5π/6`, and 30°, 150° beneath.
- **Working it out**: arithmetic, `12*3+4`, or a name and arithmetic, `PES = ...`, is evaluated
  stage by stage. Factorials are worked out too: `5!/(3!2!)`.
- **As arithmetic is typed**: percentages, `10*10%` as 1, `15% of 80` as 12, and `200+10%` as 220
  where the percentage is of what it is added to; the remainder, `17%5` as 2; thousands
  separators, `1,000+250`; `2**8`; `3x4` or `3 x 4` as a product; `0xFF` and `0b1010`;
  `log2(8)`; and a leading or trailing `=`, as `2+2=`.
- **What it leaves alone**: words, prices and dates are no mathematics. `r2d2`, `wi-fi 6`,
  `5 ft 10`, `$100`, `2026-10-06` and `007` bring up no card.
- **Letters with no equals sign** are tidied: like terms are collected, `2x+3x` to 5x, and what
  every term has in common is taken out, `xb+xc` to x(b + c). Nothing is multiplied out, and a
  quadratic is not factorised: `x^2-5x+6=0` does that in its working.
- **A formula turned round**: with several letters in it, an equation is rearranged to give x,
  `1/(7b)=11x/y` as x = y/(77b), or the letter asked for after it, `F=ma, a=?` as a = F/m and
  `1/f=1/u+1/v, f=?` as f = uv/(v + u), `F=kq/r^2, r=?` as r = ±√(kq/F). A formula already written for one letter, `y=mx+b`, is
  left alone unless another is asked for.
- **A number by itself** is given as its primes, `2048` as 2¹¹ and `360` as 2³·3²·5, or said to
  be prime; a decimal is given as a fraction, `0.375` as 3/8.
- **Digests**: `SHA256("hello")` and `SHA1("hello")`, in capitals or not, give the digest of
  the text in hexadecimal. `sha256("hello", decimal)` and `sha256("hello", binary)` give it as
  a whole number, which, unlike the hexadecimal, can go into a sum.
- **The answer before, and the clipboard**: `ans` is the last answer, once it has been copied or
  Spotlight closed on it, so `ans*2` carries on from it. After an equation with several answers
  they are `ans1`, `ans2` and so on. `clip` is the number on the clipboard, as in `20*clip`.
- **True or false**: with numbers alone on both sides, the two are compared. `2^2=4` is True
  and `1/3=0.3333` is False; `1/3~=0.3333` is True, `~=` or `≈` allowing a tenth of a percent.
  Also `!=`, `<`, `>`, `<=`, `>=` and their signs `≠`, `≤`, `≥`. (`5!=120` is five factorial;
  not equal is written with a space before it, `5 != 120`.) `==` is the same as `=`. `===` is
  exact: `0.5===1/2` is True, and `1/3===0.3333333333333333` is False however many threes are
  written. Statements join with `&&` or `and`, `||` or `or`, and are negated with `!( )` or `not`,
  with brackets to group: `3+1=4 || 3=1` is True, `&&` going first, and `not (1=1 and 2=3)` is True.
- **Physics**: `g`, `G` and `c` are the physical constants (9.8, 6.67×10⁻¹¹ and
  3.00×10⁸) whenever the equation has another letter to solve for. `h=0.5g*3^2` gives `h ≈ 44.1`
  and `x=2g` gives 19.6, while `2g=10` is still solved for `g`. The card says what was taken, and
  the working writes it in. Large and small numbers are typed as `5.97e24` and `1.6e-19`.
  A `!` before one of these letters reads it the other way round: `9e16=!c^2` is True, where
  `9e16=c^2` is solved for `c`; and `c=2*!g` is solved for `g`, where `c=2g` takes `g` as 9.8.
- **Greek letters**: `theta`, `omega`, `lambda`, `alpha`, `beta`, `phi`, `rho` and `tau` are
  each one unknown, shown as θ, ω and so on; pasted as themselves or as `\theta` they are too.
  `mu` is μ as well.
- **Systems**: equations separated by commas, `2x+y=5, x-y=1`. Linear ones are solved by
  elimination, written out as by hand; nonlinear ones (`x^2+y^2=25, x+y=7`) numerically, with
  simple values written exactly (`1 − √2`).
- **Sums and products**: `\sum_{k=0}^{10} 20k`.
- **LaTeX** as it is usually copied: `\frac`, `\sqrt`, `^{}`, `\cdot`, `\left( \right)`, `\[ \]`,
  `\begin{cases}`, `\quad`.

Implicit multiplication reads as on paper: `2n`, `2(x+1)`, `(x+1)(x-1)`, `3sin x`. A function
written without brackets is of what follows it, `sin 2x` of 2x; `sin^2 x` is its square, and
`tan^-1 x`, as `\tan^{-1}` comes from LaTeX, is the angle whose tangent is x. Capitals are
letters of their own: `G` is not `g`, and `E` is a letter where `e` is Euler's number. So is a
letter with a subscript, `F_n` or `v_0`. Angles are in radians unless marked `deg` or `°`:
`cos(35°)` is of 35 degrees, and `sin(x deg)=0.5` is answered in degrees, `x = 30°, 150°`.

## The panel

The top of the panel is the card itself, so opening it moves nothing. Below it:

- **Working**: the key steps, typeset in SF Pro: stacked fractions, roots under a bar, raised
  powers. Right-click a line to copy it as text.
- **Copying the answer**: the button at the end of the card copies the answer as a number,
  2.5 for `10/4` and for `4x=10`. So does Return, while the pointer rests on the card or the
  panel; at any other time Return is Spotlight's.
- **Solutions**: exact and decimal.
- **Graph**: each side of an equation, or each equation of a system, as its own line, crossing at
  the solutions. Drag to move, scroll or pinch to zoom, double-click to reset.

The card follows Spotlight when it is dragged, and goes when Spotlight closes. Nothing takes the
keyboard, so typing carries on going to Spotlight.

## Settings

Choose Spotlight Plus Settings in Spotlight's list, or press the gear at the foot of the panel.
Each setting has under it what it does, by example. (Choosing Spotlight Plus itself only starts
it, if it is not already running.)

- **Answers**: angles in radians or degrees; how many significant figures a decimal is given to,
  from three to ten; and whether an answer is exact where it can be (5/2, √5, π/6) or always a
  decimal.
- **What brings up a card**: arithmetic with no equals sign, and a number typed by itself, each
  of which can be turned off.
- **Physical constants**: g, G and c each on or off, and their values as a data booklet
  rounds them (9.8, 6.67×10⁻¹¹, 3.00×10⁸) or as measured (9.80665, 6.6743×10⁻¹¹, 299 792 458).
- **Copying**: whether the copy button gives a decimal or the answer as shown, and whether
  Return copies while the pointer is on the card.
- **General**: opening at login, keeping the log, and a button to quit.

## How it reads Spotlight

There is no public way to give Spotlight an answer that changes with each key. Spotlight Plus runs
in the background and reads Spotlight's search field through Accessibility, so it needs that
permission: System Settings ›
Privacy & Security › Accessibility. It never types into Spotlight or changes what is in it. The
keys it presses are the two for the clipboard history, ⌘Space and ⌘4, when Clipboard History is
chosen: Spotlight has no public way to be opened on that view either.

While a card is up it watches for Return, and nothing else: Return copies the answer when the
pointer is on the card, and at any other time is Spotlight's.

## Build and install

```bash
./build.sh   # builds, signs, installs into /Applications and restarts it
./test.sh    # the solver's tests
```

Requires macOS 26 (it uses Liquid Glass and Swift Charts), Swift 6 and Xcode's command-line tools.
It is signed with your Apple Development identity when there is one, so the Accessibility
permission survives a rebuild.

Built and used on macOS 26.5.1 (25F80) with Xcode 26.5 and Swift 6.3.2, on Apple silicon. It has
not been tried on anything else. It leans on how Spotlight happens to behave in that version: the
window it draws itself in, the search field as Accessibility gives it, and ⌘4 for the clipboard
history. A later macOS may change any of these, and the card or the clipboard history would then
need looking at again.

Spotlight's own calculator answers arithmetic as well. With both on, a sum gets two answers; turn
one off, Spotlight's in System Settings › Spotlight, or this one's in its settings.

## License

MIT; see [LICENSE](LICENSE).
