# Astronomy method reference

Astronomy offers **31 everyday methods in 6 families**. This reference is generated from the executable registry.

Bare numbers use SI units, including radians. Parallax is the explicit exception: a bare parallax is in arcseconds. Prefer units such as `30 deg`, `1 AU`, `10 M_sun` and `100 mas`. Astronomical units follow Astropy/IAU definitions; `R_earth` is the nominal equatorial radius, while `radius(earth)` returns the mean volumetric radius.

Dates default to UTC. An omitted astronomical epoch is **J2000**, never silently the current time. Orbits use ICRS axes and TDB epochs. Inclination is to the ICRS equatorial plane, unless an explicit orbit is provided; transit geometry supplies its own observer inclination.

The app bundles [JPL DE440s](https://ssd.jpl.nasa.gov/doc/Park.2021.AJ.DE440.pdf), covering 1849-12-26 through 2150-01-22, verified by SHA-256 during setup. Astropy returns planetary barycenters for Mars through Pluto, and Earth/Moon centers. Earth orientation uses the pinned bundled IERS tables, and extrapolation/leap-second warnings are preserved in the working. Fixed stellar coordinates are approximate reference positions, not a complete proper-motion catalogue.

Nested calls retain typed objects: `eccentricity(orbit(earth,sun))`. `earth_orbit` is shorthand for the J2000 Earth osculating orbit. Ideal circular transfers require explicit circular, coplanar orbits, e.g. `{a:1 AU,central_mass:sun}`; their assumptions are checked.

Object fields use `key:value`; named function arguments use `key=value`. Quote ISO dates, file paths and model names. Observers use `{longitude:121.56 deg,latitude:25.03 deg,height:10 m}`. Numeric data accept arrays, or `{start:0 day,stop:10 day,count:500}` for a sampled model interval.

Images accept nested arrays or quoted FITS/CSV paths. Time/flux data accept arrays or quoted CSV column paths (`"/path/curve.csv#time"`, `"/path/curve.csv#flux"`); numeric CSV times are seconds. A data object `{file:"/path/curve.csv",column:"time",unit:"day"}` preserves explicit units. WCS methods also accept a FITS path. Files are read only.

Model estimates are labelled. Eclipse functions screen geometric candidates; they do not certify contact times. Fuel-scaling stellar lifetimes record input metallicity but have no metallicity dependence. Gravitational-wave models are quadrupole inspirals or named ISCO/ringdown proxies, not full numerical-relativity waveforms. Cosmology defaults to explicitly reported Planck18; pass `model="Planck15"`, `model="WMAP9"`, or `{H0:70 km/s/Mpc,Om0:0.3,Tcmb0:2.7255 K}`.

Inputs are treated as exact unless an uncertainty-aware method is used. Catalogue/model uncertainty is not fabricated. `propagate_uncertainty` supports quantity-valued independent errors or a covariance matrix in the stated input-unit products. `particle_horizon` reports quadrature error only. Calibration-dependent methods require explicit calibration objects in their examples.

Every result includes working, formula, numerical inputs and conversions, model, source and a domain diagram, sampled curve or quantity/data panel. Copying a structured result exports its JSON. Transit charts expose radius and inclination controls; sky maps can be rotated.

## Celestial Bodies

### `mass(body)`

`@ mass(earth)`

**Formula:** Catalogue lookup: mass in SI kilograms

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** mass · **Visual:** panel

[Source](https://nssdc.gsfc.nasa.gov/planetary/factsheet/)

### `radius(body)`

`@ radius(earth)`

**Formula:** Catalogue lookup: mean volumetric radius

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** length · **Visual:** panel

[Source](https://nssdc.gsfc.nasa.gov/planetary/factsheet/)

### `diameter(body)`

`@ diameter(jupiter)`

**Formula:** d = 2R

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** length · **Visual:** panel

[Source](https://nssdc.gsfc.nasa.gov/planetary/factsheet/)

### `volume(body)`

`@ volume(earth)`

**Formula:** V = 4πR³/3

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** volume · **Visual:** panel

[Source](https://nssdc.gsfc.nasa.gov/planetary/factsheet/)

### `density(body)`

`@ density(earth)`

**Formula:** ρ = 3M/(4πR³)

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** density · **Visual:** panel

[Source](https://nssdc.gsfc.nasa.gov/planetary/factsheet/)

### `surface_gravity(body, radius=None)`

`@ surface_gravity(earth)`

**Formula:** g = GM/R²

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** acceleration · **Visual:** panel

[Source](https://nssdc.gsfc.nasa.gov/planetary/factsheet/)

### `escape_velocity(body, radius=None)`

`@ escape_velocity(earth)`

**Formula:** v_esc = √(2GM/R)

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** speed · **Visual:** panel

[Source](https://nssdc.gsfc.nasa.gov/planetary/factsheet/)

### `rotation_period(body)`

`@ rotation_period(venus)`

**Formula:** Catalogue sidereal rotation period; negative is retrograde

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** time · **Visual:** panel

[Source](https://nssdc.gsfc.nasa.gov/planetary/factsheet/)

### `axial_tilt(body)`

`@ axial_tilt(earth)`

**Formula:** Catalogue axial obliquity

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** angle · **Visual:** panel

[Source](https://nssdc.gsfc.nasa.gov/planetary/factsheet/)

### `luminosity(body, temperature=None)`

`@ luminosity(sun)`

**Formula:** Catalogue bolometric luminosity

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** power · **Visual:** panel

[Source](https://nssdc.gsfc.nasa.gov/planetary/factsheet/)

### `distance(body1, body2, at=J2000)`

`@ distance(earth, moon, at="2026-11-11")`

**Formula:** d = |r₂(t) − r₁(t)|

**Model:** Simultaneous geometric ICRS positions; JPL DE440s ephemeris; no light-time iteration

**Returns:** length · **Visual:** panel

[Source](https://nssdc.gsfc.nasa.gov/planetary/factsheet/)

### `light_time(body1, body2, at=J2000)`

`@ light_time(earth, sun, at="2026-11-11")`

**Formula:** t = d/c

**Model:** Geometric distance / c; no Shapiro delay

**Returns:** time · **Visual:** panel

[Source](https://nssdc.gsfc.nasa.gov/planetary/factsheet/)

### `compare(body1, body2, property=radius)`

`@ compare(earth, jupiter, radius)`

**Formula:** Property ratio = p₁ / p₂

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** structured data / typed quantities · **Visual:** comparison

[Source](https://nssdc.gsfc.nasa.gov/planetary/factsheet/)

### `body(name)`

`@ body(earth)`

**Formula:** Catalogue mass, radius, density, rotation, obliquity and luminosity

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** structured data / typed quantities · **Visual:** panel

[Source](https://nssdc.gsfc.nasa.gov/planetary/factsheet/)

## Orbital Mechanics

### `orbit(body, center=None, at=J2000)`

`@ orbit(earth, sun, at="2026-11-11")`

**Formula:** Osculating Kepler ellipse from r, v: ε = v²/2 − μ/r, a = −μ/2ε

**Model:** Newtonian two-body osculating elements; ICRS/TDB; JPL DE440s ephemeris

**Returns:** structured data / typed quantities · **Visual:** orbit

[Source](https://docs.astropy.org/en/stable/coordinates/solarsystem.html)

### `orbital_period(body, center=None)`

`@ orbital_period(earth)`

**Formula:** P = 2π√(a³/μ)

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** time · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/coordinates/solarsystem.html)

### `orbital_velocity(body, at=J2000)`

`@ orbital_velocity(earth, at="2026-11-11")`

**Formula:** v = |v(t)| from osculating state

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** speed · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/coordinates/solarsystem.html)

### `kepler_third_law(semi_major_axis, central_mass)`

`@ kepler_third_law(1 AU, sun)`

**Formula:** P² = 4π²a³/(GM)

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** time · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/coordinates/solarsystem.html)

## Astronomy Observation

### `sky_map(observer, at)`

`@ sky_map({longitude:121.56 deg,latitude:25.03 deg},"2026-11-11T12:00:00")`

**Formula:** Project topocentric AltAz positions onto the horizon dome

**Model:** Builtin solar-system ephemeris and five fixed ICRS reference stars; no comprehensive star catalogue

**Returns:** structured data / typed quantities · **Visual:** sky

[Source](https://docs.astropy.org/en/stable/coordinates/)

### `moon_phase(at)`

`@ moon_phase("2026-11-11")`

**Formula:** Geocentric ecliptic longitude difference (Moon − Sun) mod 360°

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** angle · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/coordinates/)

### `parallax_distance(parallax)`

`@ parallax_distance(100 mas)`

**Formula:** d_pc = 1/p_arcsec

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** length · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/coordinates/)

## Stellar Astrophysics

### `stellar_luminosity(radius, temperature)`

`@ stellar_luminosity(1 R_sun,5772 K)`

**Formula:** L = 4πR²σT⁴

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** power · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/modeling/physical_models.html)

### `wien_peak(temperature)`

`@ wien_peak(5772 K)`

**Formula:** λ_max T = 2.897771955×10⁻³ m K

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** length · **Visual:** blackbody

[Source](https://docs.astropy.org/en/stable/modeling/physical_models.html)

### `blackbody_spectrum(temperature)`

`@ blackbody_spectrum(5772 K)`

**Formula:** Sample Planck B_λ across 0.1–10 times the Wien wavelength

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** structured data / typed quantities · **Visual:** blackbody

[Source](https://docs.astropy.org/en/stable/modeling/physical_models.html)

### `apparent_magnitude(absolute_mag, distance, extinction=0)`

`@ apparent_magnitude(4.83,10 pc)`

**Formula:** m = M + 5 log₁₀(d/10pc) + A

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** dimensionless · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/modeling/physical_models.html)

### `absolute_magnitude(apparent_mag, distance=None, extinction=0)`

`@ absolute_magnitude(9.83,100 pc)`

**Formula:** M = m − 5 log₁₀(d/10pc) − A

**Model:** Distance modulus in the supplied passband; named stars use approximate static V-band catalogue magnitudes

**Returns:** dimensionless · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/modeling/physical_models.html)

### `hr_position(star)`

`@ hr_position(sun)`

**Formula:** Place (T_eff, L/L☉) in H–R diagram

**Model:** Catalogue estimates; schematic main-sequence reference, not a stellar evolution track

**Returns:** structured data / typed quantities · **Visual:** hr

[Source](https://docs.astropy.org/en/stable/modeling/physical_models.html)

## Black Holes & Relativity

### `schwarzschild_radius(mass)`

`@ schwarzschild_radius(10 M_sun)`

**Formula:** r_s = 2GM/c²

**Model:** Schwarzschild: nonrotating, uncharged, isolated black hole

**Returns:** length · **Visual:** black_hole

[Source](https://arxiv.org/abs/gr-qc/9712019)

### `lorentz_factor(velocity)`

`@ lorentz_factor(0.8 c)`

**Formula:** γ = 1/√(1−v²/c²)

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** dimensionless · **Visual:** panel

[Source](https://arxiv.org/abs/gr-qc/9712019)

### `rest_energy(mass)`

`@ rest_energy(1 kg)`

**Formula:** E₀ = mc²

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** energy · **Visual:** panel

[Source](https://arxiv.org/abs/gr-qc/9712019)

## Spectroscopy & Photometry

### `redshift(emitted_wavelength, observed_wavelength)`

`@ redshift(500 nm,600 nm)`

**Formula:** z = (λ_observed − λ_emitted)/λ_emitted

**Model:** Dimensionless spectral redshift; not automatically a recession velocity

**Returns:** dimensionless · **Visual:** spectrum

[Source](https://docs.astropy.org/en/stable/units/)
