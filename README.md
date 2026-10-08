# Spotlight Add-ons

Type an equation into Spotlight and the answer appears on a glass card just above it, as you type,
the way Spotlight's own calculator answers 2+2. Rest the pointer on the card and it grows into a
panel with the working, every solution and a graph; move the pointer off and it shrinks back.

Type `clipboard` or `history`, choose Clipboard History in Spotlight's list and press Return, and
Spotlight comes back open on its clipboard history, the view that ⌘Space and then ⌘4 gives.
Clipboard History is an entry Spotlight Add-ons puts in Spotlight's list itself, through Core
Spotlight; there is no second app. Spotlight Add-ons Preferences is another, and opens the preferences.

## What it does

- **Equations**: one unknown or several, exactly where that can be done, with the working and a graph:
  linear, quadratic and higher, exponential, logarithmic and trigonometric (in radians and in degrees, over
  one turn or a range you give), rational (`1/x+1/(x+1)=1`), systems, and formulas turned round or with
  values given. A quadratic with no real root gives its complex roots.
- **Inequalities** in one letter, alone or together: `x^2>4`, `1<x<5`, `x>1 && x<5`.
- **Arithmetic**, with the functions of a calculator, percentages, whole numbers written out in full,
  complex numbers, statistics and distributions, matrices and vectors, and sequences.
- **Units, bases and money**: `5 km to miles`, `255 in hex`, `0.75 to fraction`, `2024 to roman`, `750 USD to NTD`.
- **Algebra by name**: `expand`, `factor`, `derivative`, `integrate`, `limit`; and trigonometric
  identities, `sin(x)^2+cos(x)^2` as 1. A sum to a power is multiplied out as it is typed: `(a+b)^2`.
- **True or false** for statements with numbers alone, joined with `&&`, `||` and `not`.
- **Digests**, a **path** to a file, `ans` for the last answer and `clip` for the clipboard.
- **LaTeX** is read for all of it, as it is usually copied.
- What is no mathematics is left alone: `r2d2`, `wi-fi 6`, `5 ft 10`, `$100`, `2026-10-06`, `007`.

The next section is every syntax there is, each with its LaTeX where it has one.

## Syntax

Everything is typed into Spotlight's search field. Each row gives what is typed, and the same in LaTeX.

### Numbers and arithmetic

| Asked | Typed | LaTeX |
| --- | --- | --- |
| Sum, product, quotient | `2+3*4`, `10/4`, `5 x 5`, `5×5`, `5÷5` | `2+3\times 4`, `\frac{10}{4}`, `5\cdot 5`, `5\div 5` |
| Power, root | `2^10`, `2**8`, `x²`, `x⁴`, `sqrt(2)`, `√2`, `cbrt(27)`, `root(27,3)` | `2^{10}`, `\sqrt{2}`, `\sqrt[3]{27}` |
| Brackets, juxtaposition | `2(3+4)`, `(x+1)(x-1)`, `3sin x` | `\left( \right)` |
| Factorial | `5!`, `(n-1)!`, `10!/(3!7!)` | `5!` |
| Percentage | `10*10%`, `200+10%`, `200-10%`, `15% of 80`, `20% off 80` | `10\%`, `15\% \text{ of } 80` |
| Remainder | `17%5`, `17 mod 5`, `mod(17,5)` | `17 \bmod 5`, `17 \pmod{5}` |
| Scientific notation | `5.97e24`, `1.6E-19`, `3e8*2` | the same |
| Grouped digits | `1,000+250` | |
| Money | `$12.50*3`, `€10+5` | |
| Constants | `pi`, `π`, `e^2`; `g`, `G`, `c` when another letter is the unknown | `\pi`, `e^{2}` |
| Degrees and radians | `sin(30°)`, `sin(x deg)`, `sin(x rad)`; radians where nothing is said | `\sin 30^\circ` |
| Rounding | `floor(3.7)`, `ceil(3.2)`, `round(3.14159,2)`, `trunc(3.9)`, `frac(3.75)`, `sign(-5)` | `\lfloor 3.7 \rfloor`, `\lceil 3.2 \rceil` |
| Size | `abs(-5)`, `\|3-7\|` | `\left\| 3-7 \right\|`, `\lvert x \rvert` |
| Greatest, least | `max(3,5,9)`, `min(3,5)` | `\max(3,5,9)` |
| Divisors | `gcd(12,18)`, `lcm(4,6)`, `totient(36)`, `nextprime(100)`, `fib(10)` | `\gcd(12,18)`, `\operatorname{lcm}(4,6)` |
| Choosing, arranging | `nCr(5,2)`, `5C2`, `comb(5,2)`, `nPr(5,2)`, `5P2` | `\binom{5}{2}`, `{5 \choose 2}` |
| Bits | `1<<4`, `256>>2`, `12&10`, `xor(12,10)`, `bor(12,10)`, `0xFF`, `0b1010` | |
| Logarithms | `ln(e)`, `log(1000)`, `log(8,2)`, `log2(8)`, `log10(1000)`, `lg(8)`, `lb(8)` | `\ln e`, `\log 1000`, `\log_2 8`, `\log_{10} 1000` |
| Trigonometry | `sin`, `cos`, `tan`, `sec`, `csc`, `cot`, `asin`/`arcsin`/`sin^-1`, `sinh`, `asinh`, `atan2(1,1)`, `hypot(3,4)` | `\sin`, `\sec`, `\arcsin`, `\tan^{-1}`, `\sinh` |
| Exponential | `exp(2)`, `e^x` | `\exp(2)`, `e^{x}` |
| Sum, product | `sum(k,1,10,k^2)`, `prod(k,1,5,k)` | `\sum_{k=1}^{10} k^2`, `\prod_{k=1}^{5} k` |
| Whole numbers in full | `2^64`, `20!`, `30!`, `3^50` are written out to 60 figures | |
| Mixed numbers | `1 1/2 + 2 3/4` | |
| A run of terms | `1+2+...+100`, `2+4+6+…+20`, `1*2*...*5`, `sum of 1 to 100` | |
| Words in front | `solve 2x+3=7`, `find x: 2x=6`, `2x+3=7 solve for x`, `what is 15% of 80`, `calculate 5*5` | |
| Function names | `SIN(30°)`, `Sqrt(16)`, `NCR(5,2)` are the same in capitals | |
| The last answer, the clipboard | `ans`, `ans1`, `ans2`, `clip` | |

### Equations and inequalities

| Asked | Typed | LaTeX |
| --- | --- | --- |
| One unknown | `2n^2=10`, `x^2-5x+6=0`, `2^x=8`, `log(n)=2`, `sqrt(x)=3`, `20=0.5g*t^2`; with the unknown in a denominator, `1/x+1/(x+1)=1` (exact, and what makes a denominator zero struck out) | `\frac{x}{2}+1=3`, `x^{2}-5x+6=0` |
| Trigonometric | `sin(x)=0.5`, `2sin(3x+1)=1`, `sin(x deg)=0.5`; answered from 0 to 2π, in radians and in degrees | `\sin x=\frac12` |
| In a range | `sin(x)=sqrt(3)/2, 0°<=x<360°`, `cos(x)=1/2, x in [0,2π)` (or `x∈[0,2π)`), `x^2=4, x>0`; degrees where the range is in them | `\sin x=\frac{\sqrt{3}}{2},\quad 0^\circ\le x<360^\circ`, `x\in[0,2\pi)` |
| Systems | `x+y=3, x-y=1`; nonlinear ones too | `\begin{cases} x+y=3 \\ x-y=1 \end{cases}` |
| A sequence from some terms | nothing is said until it is asked: `u_1=12, u_5=29, d` gives the common difference, `…, r` the common ratio (`±√2`, `±(29/12)^(1/4)`), and `u_1=12, u_5=29, u_10=?` or `S_5=?` a term or a sum; `u_1=2, d=3, u_10=?`, `u_1=2, r=3, S_5=?`. A slip for the subscript, `u+1`, `u1`, is read as `u_1` beside `u_5`. The panel draws the terms | `u_{1}=12, u_{5}=29, d` |
| A formula with values given | `v=u+at, u=2, a=3, t=4`, `E=1/2*m*v^2, m=2, v=3`, `PV=nRT, P=2, V=3, n=1, R=8.314` | |
| A formula turned round | `1/(7b)=11x/y`, `F=ma, a=?`, `F=kq/r^2, r=?` | `\frac{1}{7b}=\frac{11x}{y}, x=?` |
| Which letter | the unknown is the one letter; `!c` reads c the other way round; Greek names, `theta`, `omega`, …, and subscripts, `F_n`, are letters | `\theta`, `F_{n}` |
| Inequalities | `x^2>4`, `x^2-4<=0`, `x^3-x>0`, `x^2 != 4`, `\|2x+1\|<3`, `exp(x)>1`; together, `1<x<5`, `x>1 && x<5`, `x<1 or x>5`, `x^2>4 && x<10` | `x^2 \ge 4`, `x \ne 2`, `\left\| x \right\| < 3` |
| Complex roots | `x^2+x+1=0` gives x = (−1 ± √3 i)/2 | |
| Tidying | `2x+3x`, `xb+xc`, `(m^4q^4z^-1)(mq^5z^3)`; a sum to a power, or sums multiplied, is multiplied out: `(a+b)^2`, `(x+1)(x-1)`, `(a+b)^1` | |
| Trigonometric identities | `sin(x)^2+cos(x)^2` is 1, `sin(x)/cos(x)` is tan(x), `2sin(x)cos(x)` is sin(2x), `1-2sin(x)^2` is cos(2x), `1+tan(x)^2` is sec(x)² | `\sin^2 x + \cos^2 x`, `\frac{\sin x}{\cos x}` |

### Statistics

`mean`, `median`, `mode`, `stdev` (sample), `stdevp`, `var`, `varp`, `geomean`, `rms`, `range`, `total`,
each of a list: `mean(1,2,3,4)` or `mean([1,2,3,4])`; `quartile([…],1)`, `percentile([…],90)`, `iqr([…])`,
`corr([…],[…])`, `cov([…],[…])`, `linreg([…],[…])` (the line, y = 2x + 1), `zscore(x,mu,sigma)`. Distributions: `binompdf(n,p,k)`, `binomcdf(n,p,k)`,
`normpdf(x[,mu,sigma])`, `normcdf(x[,mu,sigma])`, `normalcdf(lo,hi[,mu,sigma])`, `invnorm(p[,mu,sigma])`,
`poissonpdf(λ,k)`, `poissoncdf(λ,k)`. In LaTeX, `\operatorname{mean}(1,2,3,4)`.

### Complex numbers

`i` stands by itself in a sum: `(1+2i)*(3-i)`, `i^2`, `e^(i*pi)`, `|3+4i|`, `conj(3+4i)`, `arg(1+i)`,
`sqrt(-4)`, `ln(-1)`. In LaTeX: `(1+2i)(3-i)`, `e^{i\pi}`, `\overline{3+4i}`.

### Matrices and vectors

`[[1,2],[3,4]]` is a matrix and `[1,2,3]` a vector: `det([[1,2],[3,4]])`, `inv(…)`, `transpose(…)`,
`trace(…)`, `rank(…)`, `identity(3)`, `dot([1,2,3],[4,5,6])`, `cross([1,0,0],[0,1,0])`, `norm([3,4])`,
`[[1,2],[3,4]]*[[0,1],[1,0]]`, `[[1,2],[3,4]]+[[1,1],[1,1]]`, `2*[[1,2],[3,4]]`, `[[1,2],[3,4]]^2`,
`[[1,2],[3,4]]^-1`, `[[1,2],[3,4]]*[1,1]`. In LaTeX, `\begin{pmatrix} 1 & 2 \\ 3 & 4 \end{pmatrix}`
(also `bmatrix`; `vmatrix` is its determinant), `\det`, `^{-1}`, `^T`, `\left\| v \right\|`.

### Units and bases

`5 km to miles`, `5 km in mi`, `100 F to C`, `72 kg to lb`, `60 mph to km/h`, `1 GiB to MB`,
`1 atm to psi`: length, mass, volume, time, speed, area, data, energy, power, pressure, force, angle,
frequency and temperature. `255 in hex` (FF), `3 in binary` (11), `255 to octal`, `255 in base 7`, `hex(255)`,
`bin(10)`, `oct(64)`: the same number written in base 16, 2, 8 or another; the prefixes 0x, 0b, 0o are only
added where the setting for them is on, and are always understood when typed (`0xFF + 1`). Sums of quantities, `5 km + 300 m`, `5 ft 10 in`, `1 h 30 min to s`. Other forms of a number,
`0.75 to fraction`, `1/3 to decimal`, `12345 to scientific`, `0.25 to percent`, `2024 to roman`, `MCMXCIV to number`. In LaTeX, `5\,\mathrm{km} \text{ to } \mathrm{mi}`.

### Money

`750 USD to NTD`, `750USD=NTD?`, `jpy 10 to ntd`, `$20 in yen`, `100 euro to gbp`, `usd to twd` (one dollar): an amount in
another currency. Every currency the source has (about 160) may be named by its code, in any case (`usd`, `Usd`, `USD`,
since a currency has one name whatever the case), before the amount or after it, or by a symbol (`$`, `€`, `£`, `¥`, `₩`,
`₹`, `NT$`, `R$` and the like) or a name (`yen`, `sterling`, `ntd`). The amount may be a sum, `750*2 usd to ntd`, with
commas between the thousands. `=` is read as "to" only between an amount of money and a currency.

Coins and metals are the same: `0.5 btc to usd`, `1 eth to btc`, `₿1 to ntd`, `100 usd to btc`; `2 oz gold to usd`,
`1 xau to jpy`, `10 g gold to ntd`, `1 kg of silver to usd`. A metal (gold, silver, platinum, palladium; XAU, XAG, XPT,
XPD) is priced by the troy ounce, of 31.1035 g; the coins are the thirty or so best known (BTC, ETH, USDT, USDC, BNB, XRP,
SOL, ADA, DOGE, DOT, LTC, and so on).

The rates are fetched as the card is made, in the background, each against the US dollar, and the card is made again
when they arrive: currencies from open.er-api.com (they are those of the day, as that is the finest it gives), coins from
api.coinbase.com and metals from api.gold-api.com (as they trade). The last rates had are kept, and with no connection they
are used, and the card then says when they were recorded: `1 BTC = 82645.1 USD · offline, rates of 8 Oct 2026, 14:01`.
With a connection it says nothing of the time. With neither a connection nor rates saved, there is no value to give, and
the card says so.

### Algebra, asked for by name

| Asked | Typed | LaTeX |
| --- | --- | --- |
| Multiply out | `expand((x+1)^2)`, `expand (x+1)(x-1)` | |
| Factorise | `factor(x^2-5x+6)`, `factor 360` | |
| Differentiate | `derivative(x^3+2x)`, `d/dx sin(x)`, `diff(x^2, 3)`, `derivative(x^3) at 2`; higher, `d2/dx2 x^3`, `second derivative of x^3` | `\frac{d}{dx}\left( x^3 \right)`, `\frac{\mathrm{d}}{\mathrm{d}x} \sin x` |
| Integrate | `integrate(x^2)`, `integrate(x^2, 0, 1)`, `∫ x^2 dx`, `∫_0^1 x^2 dx` | `\int_0^1 x^2 \, dx`, `\int x^2 \, \mathrm{d}x` |
| Limit | `limit(sin(x)/x, x, 0)`, `limit((1+1/x)^x, x, inf)`, `limit(1/x, x, 0+)` | `\lim_{x \to 0} \frac{\sin x}{x}`, `\lim_{x \to \infty}`, `\lim_{x \to 0^+}` |

### Letters and constants

- The unknown is the one letter in an equation. Capitals are letters of their own: `G` is not `g`, and `E`
  is a letter where `e` is Euler's number. So is a letter with a subscript, `F_n` or `v_0`.
- `theta`, `omega`, `lambda`, `alpha`, `beta`, `phi`, `rho`, `tau` and `mu` are each one unknown, shown as θ, ω
  and so on; pasted as themselves or as `\theta` they are too.
- `g`, `G` and `c` are the physical constants (9.8, 6.67×10⁻¹¹ and 3.00×10⁸) whenever the equation has
  another letter to solve for: `h=0.5g*3^2` gives `h ≈ 44.1` and `x=2g` gives 19.6, while `2g=10` is still solved
  for `g`. The card says what was taken, and the working writes it in.
- A `!` before one of these letters reads it the other way round: `9e16=!c^2` is True, where `9e16=c^2` is
  solved for `c`; and `c=2*!g` is solved for `g`, where `c=2g` takes `g` as 9.8.
- Implicit multiplication reads as on paper: `2n`, `2(x+1)`, `(x+1)(x-1)`, `3sin x`. A function written
  without brackets is of what follows it, `sin 2x` of 2x; `sin^2 x` is its square, and `tan^-1 x`, as
  `\tan^{-1}` comes from LaTeX, is the angle whose tangent is x.
- Angles are in radians unless marked `deg` or `°`: `cos(35°)` is of 35 degrees, and `sin(x deg)=0.5` is
  answered in degrees, `x = 30°, 150°`.

### Reading what is typed

- A bracket that closes what was never opened, `29-12)/5`, is read as if it had been opened at the start,
  `(29-12)/5`. One left open is not closed: it is not finished.
- Spaces do not matter, and the full-width characters a Chinese input method types, `（ｘ＋１）＾２`, are read as
  the ordinary ones.
- A name given a value, `cost = 12*3+4`, is worked out and not solved. A number by itself is given as its primes,
  or as a fraction if it has a decimal point.
- Words, prices and dates are left alone.

### Notations of its own

Some of what is typed is not standard mathematics, but short to type. All of it is listed here, and each is
explained where it belongs above.

| Typed | Means |
| --- | --- |
| `1/3~=0.3333`, `≈` | approximately equal: within a tenth of a percent |
| `1/3===1/3` | exactly equal, as fractions; `1/3===0.3333333333333333` is False |
| `==` | the same as `=` |
| `5 != 120`, `≠` | not equal; with a space before it, since `5!=120` is five factorial |
| `<=`, `>=`, `≤`, `≥` | at most, at least |
| `&&` or `and`, `\|\|` or `or`, `!( )` or `not` | both, either, not, for statements |
| `x=?`, `F=ma, a=?` | the letter asked for, after a formula |
| `!c` | read the letter c the other way round: the unknown, not the speed of light |
| `x deg`, `35°`, `x rad` | an angle in degrees, or in radians |
| `5C2`, `5P2` | the ways of choosing, and of arranging |
| `1+2+...+100`, `1*2*...*5`, `sum of 1 to 100` | a run of terms, written with dots |
| `20% off 80`, `15% of 80`, `200+10%` | percentages as people say them; the last is of the 200 |
| `17 mod 5`, `17%5` | the remainder |
| `d/dx x^3`, `d2/dx2 x^3`, `second derivative of x^3` | the derivative, and higher ones |
| `limit(1/x, x, 0+)` | a limit from the right; `0-` from the left; `inf` for infinity |
| `u_1=12, u_5=29, d` | the common difference of a sequence; `r` its ratio; `u+1` and `u1` slips for `u_1` |
| `x in [0,2π)`, `x∈[0,2π)` | how far x goes, with `[` including the end and `(` leaving it out |
| `u_5`, `F_n`, `v_0` | one letter with a subscript |
| `29-12)/5` | a bracket that closes what was never opened: `(29-12)/5` |
| `solve …`, `find x: …`, `what is …` | words in front, which are ignored |
| `ans`, `ans1`, `clip` | the last answer, the several answers of the last, the clipboard |

### True or false

`2^2=4` is True and `1/3=0.3333` is False (equal to within rounding); `1/3~=0.3333` or `≈` is True, allowing a
tenth of a percent; `1/3===0.3333333333333333` is False however many threes are written, `===` being
exact, and `0.5===1/2` is True. `==` is the same as `=`. Also `!=`, `<`, `>`, `<=`, `>=` and `≠`, `≤`, `≥`.
(`5!=120` is five factorial; not equal is written with a space before it, `5 != 120`.) Statements join with
`&&` or `and`, `||` or `or`, and are negated with `!( )` or `not`, with brackets to group: `3+1=4 || 3=1` is
True, `&&` going first, and `not (1=1 and 2=3)` is True. In LaTeX: `\approx`, `\ne`, `\le`, `\ge`, `\land`, `\lor`, `\lnot`.

### Systems

Equations separated by commas, `2x+y=5, x-y=1`. Linear ones are solved by elimination, written out as by
hand; nonlinear ones (`x^2+y^2=25, x+y=7`) numerically, with simple values written exactly (`1 − √2`).

### Digests, paths, the answer before

- `SHA256("hello")`, `SHA1`, `SHA384`, `SHA512`, `MD5`, in capitals or not, give the digest of the text in
  hexadecimal; `sha256("hello", decimal)` and `sha256("hello", binary)` give it as a whole number, which,
  unlike the hexadecimal, can go into a sum.
- An absolute path that exists, `/Users/me/Code/app.jar`, brings up a card with the name and where it is.
  Clicking the card's folder sign, or Return with the pointer on it, shows the file selected in Finder; a
  folder is opened. A path from the home folder, `~/Code`, is left to Spotlight. macOS may ask once for
  access to Desktop, Documents or Downloads.
- `ans` is the last answer, once it has been copied or Spotlight closed on it, so `ans*2` carries on from it.
  After an equation with several answers they are `ans1`, `ans2` and so on. `clip` is the number on the
  clipboard, as in `20*clip`.

### LaTeX commands read

`\frac \dfrac \tfrac \sqrt \sqrt[n] \binom \choose \sum \prod \int \lim \left \right \cdot \times \div \pi \theta
(and the other Greek letters) \sin \cos \tan \sec \csc \cot \arcsin \arccos \arctan \sinh \cosh \tanh \ln \log
\log_b \exp \lg \max \min \gcd \det \arg \lfloor \rfloor \lceil \rceil \lvert \rvert \| \overline \bar \vec \hat
\mathrm \mathbf \operatorname \text (a unit, or to, in, of, off) \circ \% \le \ge \ne \approx \leqslant \geqslant
\land \lor \lnot \bmod \pmod \infty \to \begin{cases} \begin{aligned} \begin{array} \begin{pmatrix}
\begin{bmatrix} \begin{vmatrix}`, with `^{…}` and `_{…}` for powers and subscripts, and spacing
commands (`\,` `\;` `\quad`) ignored.

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

## Preferences

Choosing **Spotlight Add-ons Preferences** in Spotlight (or the gear at the foot of the panel) opens the preferences,
with the five pages in a sidebar: **General**, **Calculation**, **Cards**, **Constants** and **Clipboard**. Under
each setting there is what it does, and a card at the top of the page shows the examples for the one the pointer is
on, or that was last changed, with what it gives now: turning one off shows its card going ("No card"). A
trackpad with haptics gives a tap for each switch or choice, and a firmer one for a change of page. The page last
looked at is the one it opens on.

- **General**: opening at login, the note shown when it is opened, the log (and a button to show it in Finder),
  resetting every setting, and a button to quit.
- **Calculation**: angles in radians or degrees; how many significant figures a decimal is given to, from three to
  ten; whether an answer is exact where it can be (5/2, √5, π/6) or always a decimal; and whether a sum is
  answered as a decimal first (`10/4` gives 2.5, with 5/2 beneath: the default) or as a fraction first.
- **Cards**: what brings up a card: arithmetic with no equals sign, a number by itself, a path to a file, units
  and number bases (and whether a base is marked 0x, 0b, 0o), inequalities, algebra by name, matrices and vectors.
- **Constants**: g, G and c each on or off, and their values as a data booklet rounds them (9.8, 6.67×10⁻¹¹,
  3.00×10⁸) or as measured (9.80665, 6.6743×10⁻¹¹, 299 792 458).
- **Clipboard**: whether the copy button gives a decimal or the answer as shown, and whether Return copies while
  the pointer is on the card.

## How it reads Spotlight

There is no public way to give Spotlight an answer that changes with each key. Spotlight Add-ons runs
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
