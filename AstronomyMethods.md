# Astronomy method reference

The complete specification contains **234 methods in 14 families**. This reference is generated from the executable registry.

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

### `surface_area(body)`

`@ surface_area(earth)`

**Formula:** A = 4πR²

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** area · **Visual:** panel

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

### `orbital_elements(body, center=None, at=J2000)`

`@ orbital_elements(moon, earth)`

**Formula:** h = r × v; e = (v × h)/μ − r/|r|

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** structured data / typed quantities · **Visual:** orbit

[Source](https://docs.astropy.org/en/stable/coordinates/solarsystem.html)

### `state_vector(body, center=None, at=J2000)`

`@ state_vector(earth, sun)`

**Formula:** State = (r_body − r_center, v_body − v_center)

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

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

### `circular_velocity(radius, central_mass)`

`@ circular_velocity(1 AU, sun)`

**Formula:** v_c = √(GM/r)

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** speed · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/coordinates/solarsystem.html)

### `vis_viva(radius, semi_major_axis, central_mass)`

`@ vis_viva(1 AU, 1.2 AU, sun)`

**Formula:** v² = GM(2/r − 1/a)

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** speed · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/coordinates/solarsystem.html)

### `kepler_third_law(semi_major_axis, central_mass)`

`@ kepler_third_law(1 AU, sun)`

**Formula:** P² = 4π²a³/(GM)

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** time · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/coordinates/solarsystem.html)

### `semi_major_axis(orbit)`

`@ semi_major_axis(orbit(earth, sun))`

**Formula:** a = −μ/(2ε)

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** length · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/coordinates/solarsystem.html)

### `eccentricity(orbit)`

`@ eccentricity(orbit(earth, sun))`

**Formula:** e = |(v × h)/μ − r/r|

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** dimensionless · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/coordinates/solarsystem.html)

### `inclination(orbit)`

`@ inclination(orbit(earth, sun))`

**Formula:** i = arccos(h_z/|h|)

**Model:** Inclination to ICRS equator; specify explicit ecliptic orbit for ecliptic inclination

**Returns:** angle · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/coordinates/solarsystem.html)

### `periapsis(orbit)`

`@ periapsis(earth_orbit)`

**Formula:** r_p = a(1−e)

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** length · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/coordinates/solarsystem.html)

### `apoapsis(orbit)`

`@ apoapsis(earth_orbit)`

**Formula:** r_a = a(1+e)

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** length · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/coordinates/solarsystem.html)

### `true_anomaly(orbit, at=None)`

`@ true_anomaly(earth_orbit)`

**Formula:** tan(ν/2) = √((1+e)/(1−e)) tan(E/2)

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** angle · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/coordinates/solarsystem.html)

### `mean_anomaly(orbit, at=None)`

`@ mean_anomaly(earth_orbit)`

**Formula:** M = E − e sin E

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** angle · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/coordinates/solarsystem.html)

### `eccentric_anomaly(orbit, at=None)`

`@ eccentric_anomaly(earth_orbit)`

**Formula:** Solve E − e sin E = M

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** angle · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/coordinates/solarsystem.html)

### `mean_motion(orbit)`

`@ mean_motion(earth_orbit)`

**Formula:** n = √(μ/a³)

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** angular speed · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/coordinates/solarsystem.html)

### `specific_orbital_energy(orbit)`

`@ specific_orbital_energy(earth_orbit)`

**Formula:** ε = −μ/(2a)

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** specific energy · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/coordinates/solarsystem.html)

### `specific_angular_momentum(orbit)`

`@ specific_angular_momentum(earth_orbit)`

**Formula:** h = √(μa(1−e²))

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** specific angular momentum · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/coordinates/solarsystem.html)

### `synodic_period(period1, period2, sense=prograde)`

`@ synodic_period(365.25 day, 686.98 day)`

**Formula:** 1/S = |1/P₁ ∓ 1/P₂|

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** time · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/coordinates/solarsystem.html)

### `hill_sphere(body, primary, semi_major_axis, eccentricity=0)`

`@ hill_sphere(earth, sun, 1 AU)`

**Formula:** r_H ≈ a(1−e)(m/(3M))^(1/3)

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** length · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/coordinates/solarsystem.html)

### `roche_limit(primary, satellite=None, model=fluid)`

`@ roche_limit(earth, moon, model="fluid")`

**Formula:** d = kR₁(ρ₁/ρ₂)^(1/3), k_fluid=2.44, k_rigid=2^(1/3)

**Model:** Strengthless fluid (2.44) or rigid (1.26) satellite approximation

**Returns:** length · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/coordinates/solarsystem.html)

### `lagrange_points(primary, secondary)`

`@ lagrange_points(sun, earth)`

**Formula:** ∂Ω/∂x = 0 in the circular restricted three-body rotating frame

**Model:** Circular restricted three-body; positions in separation units, barycentric rotating frame

**Returns:** structured data / typed quantities · **Visual:** potential

[Source](https://docs.astropy.org/en/stable/coordinates/solarsystem.html)

### `sphere_of_influence(body, primary)`

`@ sphere_of_influence(earth, sun)`

**Formula:** r_SOI = a(m/M)^(2/5)

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** length · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/coordinates/solarsystem.html)

### `propagate_orbit(orbit, duration)`

`@ propagate_orbit(earth_orbit, 30 day)`

**Formula:** Integrate r̈ = −μr/r³; DOP853

**Model:** Newtonian two-body; DOP853 relative tolerance 1e-10

**Returns:** structured data / typed quantities · **Visual:** orbit

[Source](https://docs.astropy.org/en/stable/coordinates/solarsystem.html)

### `two_body_simulation(body1, body2, initial_state)`

`@ two_body_simulation(sun, earth, {positions: [[0,0,0],[1 AU,0,0]], velocities: [[0,0,0],[0,29.78 km/s,0]], duration: 365 day})`

**Formula:** r̈ᵢ = Σⱼ Gmⱼ(rⱼ−rᵢ)/|rⱼ−rᵢ|³

**Model:** Newtonian point masses; numerical DOP853; collision singularities rejected

**Returns:** structured data / typed quantities · **Visual:** orbit

[Source](https://docs.astropy.org/en/stable/coordinates/solarsystem.html)

### `n_body_simulation(bodies, initial_states, duration)`

`@ n_body_simulation([sun,earth], {positions:[[0,0,0],[1 AU,0,0]],velocities:[[0,0,0],[0,29.78 km/s,0]]}, 365 day)`

**Formula:** Newtonian N-body integration; report relative energy drift

**Model:** Newtonian point masses; no relativity, tides or physical collisions

**Returns:** structured data / typed quantities · **Visual:** orbit

[Source](https://docs.astropy.org/en/stable/coordinates/solarsystem.html)

## Spaceflight & Maneuvers

### `hohmann_transfer(initial_orbit, target_orbit)`

`@ hohmann_transfer({a:1 AU,central_mass:sun},{a:1.524 AU,central_mass:sun})`

**Formula:** Δv₁ = √(μ/r₁)(√(2r₂/(r₁+r₂))−1); Δv₂ = √(μ/r₂)(1−√(2r₁/(r₁+r₂)))

**Model:** Two coplanar circular orbits; impulsive burns; no launch or capture costs

**Returns:** structured data / typed quantities · **Visual:** transfer

[Source](https://orbital-mechanics.space/)

### `bielliptic_transfer(initial_orbit, target_orbit, intermediate_radius)`

`@ bielliptic_transfer({a:1 AU,central_mass:sun},{a:2 AU,central_mass:sun},10 AU)`

**Formula:** Sum three vis-viva burns across two transfer ellipses

**Model:** Coplanar circular endpoints; intermediate radius above both endpoints

**Returns:** structured data / typed quantities · **Visual:** transfer

[Source](https://orbital-mechanics.space/)

### `lambert_transfer(position1, position2, flight_time, central_mass)`

`@ lambert_transfer([1 AU,0,0],[0,1 AU,0],90 day,sun)`

**Formula:** Universal-variable Lambert equation; Lagrange f,g coefficients

**Model:** Zero-revolution, prograde short-way transfer; positions relative to common center

**Returns:** structured data / typed quantities · **Visual:** transfer

[Source](https://orbital-mechanics.space/)

### `delta_v(maneuver)`

`@ delta_v(hohmann_transfer({a:1 AU,central_mass:sun},{a:2 AU,central_mass:sun}))`

**Formula:** Δv = Σ|Δvᵢ|

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** speed · **Visual:** panel

[Source](https://orbital-mechanics.space/)

### `transfer_time(maneuver)`

`@ transfer_time(hohmann_transfer({a:1 AU,central_mass:sun},{a:2 AU,central_mass:sun}))`

**Formula:** Transfer duration from maneuver object

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** time · **Visual:** panel

[Source](https://orbital-mechanics.space/)

### `plane_change_delta_v(velocity, angle)`

`@ plane_change_delta_v(7.8 km/s,30 deg)`

**Formula:** Δv = 2v sin(θ/2)

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** speed · **Visual:** panel

[Source](https://orbital-mechanics.space/)

### `rocket_equation(initial_mass, final_mass, isp)`

`@ rocket_equation(1000 kg,500 kg,300 s)`

**Formula:** Δv = I_sp g₀ ln(m₀/m_f)

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** speed · **Visual:** panel

[Source](https://orbital-mechanics.space/)

### `mass_ratio(delta_v, isp)`

`@ mass_ratio(3 km/s,300 s)`

**Formula:** m₀/m_f = exp(Δv/(I_sp g₀))

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** dimensionless · **Visual:** panel

[Source](https://orbital-mechanics.space/)

### `thrust_acceleration(thrust, mass)`

`@ thrust_acceleration(100 N,1000 kg)`

**Formula:** a = F/m

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** acceleration · **Visual:** panel

[Source](https://orbital-mechanics.space/)

### `burn_time(propellant_mass, mass_flow_rate)`

`@ burn_time(100 kg,2 kg/s)`

**Formula:** t = m_propellant / ṁ

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** time · **Visual:** panel

[Source](https://orbital-mechanics.space/)

### `launch_window(origin, target, date_range, model=hohmann)`

`@ launch_window(earth,mars,["2026-01-01","2028-01-01"])`

**Formula:** Find minima of wrapped heliocentric phase error to Hohmann departure phase

**Model:** Coplanar circular Hohmann phase estimate using JPL DE440s heliocentric positions; windows are not launch solutions

**Returns:** structured data / typed quantities · **Visual:** curve

[Source](https://orbital-mechanics.space/)

### `phase_angle(body1, body2, center=sun, at=J2000)`

`@ phase_angle(earth,mars,sun,at="2026-11-11")`

**Formula:** φ = atan2((r₁ × r₂)_z, r₁·r₂)

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** structured data / typed quantities · **Visual:** panel

[Source](https://orbital-mechanics.space/)

### `gravity_assist(encounter_state, planet, flyby_parameters)`

`@ gravity_assist({velocity:[15 km/s,0,0],planet_velocity:[0,13 km/s,0]},jupiter,{periapsis:1e8 m,normal:[0,0,1]})`

**Formula:** δ = 2 asin(1/(1+r_p v∞²/μ)); rotate incoming v∞ in specified flyby plane

**Model:** Unpowered hyperbolic patched-conic flyby; prescribed encounter-plane normal

**Returns:** structured data / typed quantities · **Visual:** panel

[Source](https://orbital-mechanics.space/)

### `patched_conics(trajectory, encounters)`

`@ patched_conics({velocity:[15 km/s,0,0]},[{planet:jupiter,planet_velocity:[0,0,0],periapsis:1e8 m,normal:[0,0,1]}])`

**Formula:** Sequential planet-centered hyperbolic flyby maps

**Model:** Prescribed encounter states; instantaneous sphere-of-influence patches; no ephemeris optimization

**Returns:** structured data / typed quantities · **Visual:** panel

[Source](https://orbital-mechanics.space/)

## Astronomy Observation

### `position(body, at, observer)`

`@ position(moon,"2026-11-11T12:00:00",{longitude:121.56 deg,latitude:25.03 deg})`

**Formula:** Astropy get_body → apparent GCRS → topocentric AltAz

**Model:** JPL DE440s ephemeris; GCRS apparent RA/Dec and unrefracted AltAz; bundled IERS Earth orientation

**Returns:** structured data / typed quantities · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/coordinates/)

### `ra_dec(body, at, observer)`

`@ ra_dec(moon,"2026-11-11",{longitude:0 deg,latitude:51 deg})`

**Formula:** Apparent equatorial right ascension and declination

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** structured data / typed quantities · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/coordinates/)

### `alt_az(body, at, observer)`

`@ alt_az(moon,"2026-11-11",{longitude:121 deg,latitude:25 deg})`

**Formula:** Topocentric horizontal altitude and azimuth

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** structured data / typed quantities · **Visual:** sky

[Source](https://docs.astropy.org/en/stable/coordinates/)

### `angular_separation(body1, body2, at, observer)`

`@ angular_separation(sun,moon,"2026-11-11",{longitude:0 deg,latitude:0 deg})`

**Formula:** cos θ = sin δ₁ sin δ₂ + cos δ₁ cos δ₂ cos(α₁−α₂)

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** angle · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/coordinates/)

### `angular_size(body, observer, at)`

`@ angular_size(moon,{longitude:0 deg,latitude:0 deg},"2026-11-11")`

**Formula:** θ = 2 asin(R/d)

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** angle · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/coordinates/)

### `rise_set(body, date, observer)`

`@ rise_set(moon,"2026-11-11",{longitude:121 deg,latitude:25 deg})`

**Formula:** Bracket and solve vacuum center altitude = 0° across one UTC day

**Model:** Geometric body center; no refraction, horizon dip, limb radius or terrain

**Returns:** structured data / typed quantities · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/coordinates/)

### `transit_time(body, date, observer)`

`@ transit_time(sun,"2026-11-11",{longitude:121 deg,latitude:25 deg})`

**Formula:** Maximize altitude in the specified UTC day

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** structured data / typed quantities · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/coordinates/)

### `hour_angle(body, at, observer)`

`@ hour_angle(moon,"2026-11-11",{longitude:121 deg,latitude:25 deg})`

**Formula:** H = local apparent sidereal time − topocentric CIRS right ascension

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** angle · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/coordinates/)

### `airmass(body, at, observer)`

`@ airmass(moon,"2026-11-11",{longitude:121 deg,latitude:25 deg})`

**Formula:** X = 1/[cos z + 0.50572(96.07995−z_deg)^−1.6364]

**Model:** Kasten–Young 1989 optical relative airmass; vacuum altitude; above horizon only

**Returns:** dimensionless · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/coordinates/)

### `sky_map(observer, at)`

`@ sky_map({longitude:121.56 deg,latitude:25.03 deg},"2026-11-11T12:00:00")`

**Formula:** Project topocentric AltAz positions onto the horizon dome

**Model:** Builtin solar-system ephemeris and five fixed ICRS reference stars; no comprehensive star catalogue

**Returns:** structured data / typed quantities · **Visual:** sky

[Source](https://docs.astropy.org/en/stable/coordinates/)

### `conjunction(body1, body2, date_range)`

`@ conjunction(venus,jupiter,["2026-01-01","2027-01-01"])`

**Formula:** Minimize apparent angular separation over date range

**Model:** Geocentric apparent closest approaches, not exact ecliptic-longitude conjunctions

**Returns:** structured data / typed quantities · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/coordinates/)

### `opposition(body, date_range)`

`@ opposition(mars,["2026-01-01","2028-01-01"])`

**Formula:** Maximize angular separation from Sun

**Model:** Geocentric maximum solar separation; not exact ecliptic-longitude opposition

**Returns:** structured data / typed quantities · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/coordinates/)

### `elongation(body, at, observer)`

`@ elongation(venus,"2026-11-11",{longitude:0 deg,latitude:0 deg})`

**Formula:** Elongation = angular separation from Sun

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** angle · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/coordinates/)

### `moon_phase(at)`

`@ moon_phase("2026-11-11")`

**Formula:** Geocentric ecliptic longitude difference (Moon − Sun) mod 360°

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** angle · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/coordinates/)

### `moon_illumination(at)`

`@ moon_illumination("2026-11-11")`

**Formula:** Illuminated fraction k = (1 + cos phase_angle_at_moon)/2

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** dimensionless · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/coordinates/)

### `solar_eclipse(date_range, observer)`

`@ solar_eclipse(["2026-08-12","2026-08-13"],{longitude:-20 deg,latitude:65 deg})`

**Formula:** Compare topocentric Sun–Moon separation with their angular radii

**Model:** Geometric candidate screening with JPL DE440s ephemeris; no Besselian elements, limb profile, ΔT prediction or certified contact times

**Returns:** structured data / typed quantities · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/coordinates/)

### `lunar_eclipse(date_range, observer)`

`@ lunar_eclipse(["2026-03-03","2026-03-04"],{longitude:121 deg,latitude:25 deg})`

**Formula:** Moon distance from anti-solar Earth shadow axis versus umbral radius

**Model:** Spherical Earth geometric umbra/penumbra screening; no atmospheric enlargement; approximate ephemerides

**Returns:** structured data / typed quantities · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/coordinates/)

### `coordinate_transform(coordinates, from_frame, to_frame, at=J2000)`

`@ coordinate_transform({ra:266.4 deg,dec:-28.94 deg},icrs,galactic)`

**Formula:** Astropy coordinate frame transform

**Model:** Astropy/ERFA frame transforms; time required for time-dependent frames

**Returns:** structured data / typed quantities · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/coordinates/)

### `proper_motion(position, motion, elapsed_time)`

`@ proper_motion({ra:10 deg,dec:20 deg},{pm_ra_cosdec:100 mas/yr,pm_dec:50 mas/yr},10 yr)`

**Formula:** Propagate ICRS position with proper motion and optional radial velocity

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** structured data / typed quantities · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/coordinates/)

### `parallax_distance(parallax)`

`@ parallax_distance(100 mas)`

**Formula:** d_pc = 1/p_arcsec

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** length · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/coordinates/)

## Astronomical Time

### `julian_date(datetime)`

`@ julian_date("2000-01-01T12:00:00")`

**Formula:** UTC Julian Date using Astropy Time

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** dimensionless · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/time/)

### `modified_julian_date(datetime)`

`@ modified_julian_date("2000-01-01T12:00:00")`

**Formula:** MJD = JD − 2400000.5

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** dimensionless · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/time/)

### `julian_centuries(datetime)`

`@ julian_centuries("2000-01-01T12:00:00")`

**Formula:** T = (JD_TT − 2451545.0)/36525

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** dimensionless · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/time/)

### `sidereal_time(datetime, longitude)`

`@ sidereal_time("2026-11-11T12:00:00",121 deg)`

**Formula:** IAU 2006 apparent sidereal time at longitude

**Model:** ERFA IAU 2006/2000A; UT1 from bundled IERS

**Returns:** angle · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/time/)

### `local_sidereal_time(datetime, observer)`

`@ local_sidereal_time("2026-11-11",{longitude:121 deg,latitude:25 deg})`

**Formula:** Local apparent sidereal time from geodetic longitude

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** angle · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/time/)

### `time_scale_convert(datetime, from_scale, to_scale)`

`@ time_scale_convert("2017-01-01T00:00:00",utc,tt)`

**Formula:** ERFA conversion between UTC, TAI, TT, TDB, UT1, TCG and TCB

**Model:** Astropy Time leap-second-aware conversions; TDB geocenter unless observer specified separately

**Returns:** structured data / typed quantities · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/time/)

### `barycentric_julian_date(datetime, target, observer)`

`@ barycentric_julian_date("2026-11-11",sirius,{longitude:121 deg,latitude:25 deg})`

**Formula:** BJD_TDB = JD_TDB + r_observer,bary · n/c

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** structured data / typed quantities · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/time/)

### `heliocentric_julian_date(datetime, target, observer)`

`@ heliocentric_julian_date("2026-11-11",sirius,{longitude:121 deg,latitude:25 deg})`

**Formula:** HJD_TDB = JD_TDB + r_observer,helio · n/c

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** structured data / typed quantities · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/time/)

### `precession_matrix(epoch1, epoch2)`

`@ precession_matrix("J2000","J2050")`

**Formula:** P(epoch₂) P(epoch₁)ᵀ, IAU 2006 precession-bias matrices

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** structured data / typed quantities · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/time/)

### `nutation_angles(datetime)`

`@ nutation_angles("2026-11-11")`

**Formula:** IAU 2000A nutation with IAU 2006 adjustments

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** structured data / typed quantities · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/time/)

### `atmospheric_refraction(altitude, conditions)`

`@ atmospheric_refraction(30 deg,{pressure:1010 hPa,temperature:283.15 K})`

**Formula:** R_arcmin = 1.02/tan(h+10.3/(h+5.11)) × (P/1010) × 283/(273+T_C)

**Model:** Saemundsson optical approximation; geometric altitude > −1°; weather dependent

**Returns:** angle · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/time/)

### `barycentric_velocity_correction(target, datetime, observer)`

`@ barycentric_velocity_correction(sirius,"2026-11-11",{longitude:121 deg,latitude:25 deg})`

**Formula:** Astropy barycentric radial-velocity correction

**Model:** Optical-convention barycentric correction; JPL DE440s ephemeris and IERS

**Returns:** structured data / typed quantities · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/time/)

## Stellar Astrophysics

### `stellar_luminosity(radius, temperature)`

`@ stellar_luminosity(1 R_sun,5772 K)`

**Formula:** L = 4πR²σT⁴

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** power · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/modeling/physical_models.html)

### `stellar_radius(luminosity, temperature)`

`@ stellar_radius(1 L_sun,5772 K)`

**Formula:** R = √(L/(4πσT⁴))

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** length · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/modeling/physical_models.html)

### `effective_temperature(luminosity, radius)`

`@ effective_temperature(1 L_sun,1 R_sun)`

**Formula:** T_eff = (L/(4πσR²))^(1/4)

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** temperature · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/modeling/physical_models.html)

### `stellar_density(mass, radius)`

`@ stellar_density(1 M_sun,1 R_sun)`

**Formula:** ρ = 3M/(4πR³)

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** density · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/modeling/physical_models.html)

### `wien_peak(temperature)`

`@ wien_peak(5772 K)`

**Formula:** λ_max T = 2.897771955×10⁻³ m K

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** length · **Visual:** blackbody

[Source](https://docs.astropy.org/en/stable/modeling/physical_models.html)

### `blackbody_radiance(wavelength, temperature)`

`@ blackbody_radiance(500 nm,5772 K)`

**Formula:** B_λ = 2hc²/[λ⁵(expm1(hc/(λkT)))]

**Model:** Planck spectral radiance per wavelength per steradian; not observer flux

**Returns:** spectral radiance per wavelength · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/modeling/physical_models.html)

### `blackbody_spectrum(temperature)`

`@ blackbody_spectrum(5772 K)`

**Formula:** Sample Planck B_λ across 0.1–10 times the Wien wavelength

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** structured data / typed quantities · **Visual:** blackbody

[Source](https://docs.astropy.org/en/stable/modeling/physical_models.html)

### `stefan_boltzmann_flux(temperature)`

`@ stefan_boltzmann_flux(5772 K)`

**Formula:** F = σT⁴

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** energy flux · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/modeling/physical_models.html)

### `flux_from_luminosity(luminosity, distance)`

`@ flux_from_luminosity(1 L_sun,1 AU)`

**Formula:** F = L/(4πd²)

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** energy flux · **Visual:** panel

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

### `distance_modulus(distance)`

`@ distance_modulus(100 pc)`

**Formula:** μ = 5 log₁₀(d/10pc)

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** dimensionless · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/modeling/physical_models.html)

### `bolometric_magnitude(luminosity)`

`@ bolometric_magnitude(1 L_sun)`

**Formula:** M_bol = 4.74 − 2.5 log₁₀(L/L☉)

**Model:** IAU bolometric zero point, solar M_bol=4.74

**Returns:** dimensionless · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/modeling/physical_models.html)

### `color_index(magnitude1, magnitude2)`

`@ color_index(1.2,0.5)`

**Formula:** Color index = m₁ − m₂

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** dimensionless · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/modeling/physical_models.html)

### `hr_position(star)`

`@ hr_position(sun)`

**Formula:** Place (T_eff, L/L☉) in H–R diagram

**Model:** Catalogue estimates; schematic main-sequence reference, not a stellar evolution track

**Returns:** structured data / typed quantities · **Visual:** hr

[Source](https://docs.astropy.org/en/stable/modeling/physical_models.html)

### `main_sequence_luminosity(mass, model=piecewise)`

`@ main_sequence_luminosity(1 M_sun)`

**Formula:** L/L☉ ≈ 0.23m^2.3 (m<0.43), m⁴ (m<2), 1.4m^3.5 (m<55), 32000m

**Model:** Piecewise empirical main-sequence mass–luminosity scaling; approximate solar metallicity

**Returns:** structured data / typed quantities · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/modeling/physical_models.html)

### `stellar_lifetime(mass, metallicity, model=fuel_scaling)`

`@ stellar_lifetime(1 M_sun,0.014)`

**Formula:** t_MS ≈ 10¹⁰ yr (M/M☉)/(L/L☉)

**Model:** Solar-metallicity main-sequence fuel/luminosity scaling; not evolutionary tracks

**Returns:** time · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/modeling/physical_models.html)

### `habitable_zone(luminosity, model=solar_flux)`

`@ habitable_zone(1 L_sun)`

**Formula:** r_inner = √(L/L☉ / 1.107) AU; r_outer = √(L/L☉ / 0.356) AU

**Model:** Solar-spectrum conservative runaway-greenhouse / maximum-greenhouse flux thresholds; luminosity scaling only

**Returns:** structured data / typed quantities · **Visual:** habitable

[Source](https://docs.astropy.org/en/stable/modeling/physical_models.html)

### `stellar_escape_velocity(mass, radius)`

`@ stellar_escape_velocity(1 M_sun,1 R_sun)`

**Formula:** v_esc = √(2GM/R)

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** speed · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/modeling/physical_models.html)

### `stellar_surface_gravity(mass, radius)`

`@ stellar_surface_gravity(1 M_sun,1 R_sun)`

**Formula:** g = GM/R²

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** acceleration · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/modeling/physical_models.html)

## Black Holes & Relativity

### `schwarzschild_radius(mass)`

`@ schwarzschild_radius(10 M_sun)`

**Formula:** r_s = 2GM/c²

**Model:** Schwarzschild: nonrotating, uncharged, isolated black hole

**Returns:** length · **Visual:** black_hole

[Source](https://arxiv.org/abs/gr-qc/9712019)

### `photon_sphere_radius(mass)`

`@ photon_sphere_radius(10 M_sun)`

**Formula:** r_ph = 3GM/c² = 1.5r_s

**Model:** Schwarzschild only; Kerr has no single spherical photon orbit

**Returns:** length · **Visual:** panel

[Source](https://arxiv.org/abs/gr-qc/9712019)

### `isco_radius(mass, spin=0)`

`@ isco_radius(10 M_sun,0.5)`

**Formula:** r_ISCO = (GM/c²)[3+Z₂−sgn(a*)√((3−Z₁)(3+Z₁+2Z₂))]

**Model:** Kerr equatorial test-particle ISCO; positive spin prograde, negative retrograde

**Returns:** length · **Visual:** black_hole

[Source](https://arxiv.org/abs/gr-qc/9712019)

### `kerr_horizon_radius(mass, spin)`

`@ kerr_horizon_radius(10 M_sun,0.9)`

**Formula:** r₊ = (GM/c²)(1+√(1−a*²))

**Model:** Kerr Boyer–Lindquist outer horizon radius; no single photon sphere

**Returns:** length · **Visual:** black_hole

[Source](https://arxiv.org/abs/gr-qc/9712019)

### `gravitational_redshift(mass, r_emitter, r_observer)`

`@ gravitational_redshift(sun,1 R_sun,1 AU)`

**Formula:** 1+z = √[(1−r_s/r_observer)/(1−r_s/r_emitter)]

**Model:** Static observers in Schwarzschild exterior; positive z is redshift

**Returns:** dimensionless · **Visual:** panel

[Source](https://arxiv.org/abs/gr-qc/9712019)

### `gravitational_time_dilation(mass, radius)`

`@ gravitational_time_dilation(sun,1 R_sun)`

**Formula:** dτ/dt = √(1−2GM/(rc²))

**Model:** Static Schwarzschild observer relative to infinity

**Returns:** dimensionless · **Visual:** panel

[Source](https://arxiv.org/abs/gr-qc/9712019)

### `gravitational_lensing_angle(mass, impact_parameter)`

`@ gravitational_lensing_angle(sun,1 R_sun)`

**Formula:** α = 4GM/(bc²)

**Model:** Weak-field point lens, b ≫ r_s

**Returns:** angle · **Visual:** panel

[Source](https://arxiv.org/abs/gr-qc/9712019)

### `einstein_radius(lens_mass, lens_distance, source_distance)`

`@ einstein_radius(1 M_sun,1 kpc,8 kpc)`

**Formula:** θ_E = √[(4GM/c²)(D_s−D_l)/(D_l D_s)]

**Model:** Thin point lens, Euclidean angular-diameter distances

**Returns:** angle · **Visual:** panel

[Source](https://arxiv.org/abs/gr-qc/9712019)

### `lorentz_factor(velocity)`

`@ lorentz_factor(0.8 c)`

**Formula:** γ = 1/√(1−v²/c²)

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** dimensionless · **Visual:** panel

[Source](https://arxiv.org/abs/gr-qc/9712019)

### `special_relativistic_time_dilation(proper_time, velocity)`

`@ special_relativistic_time_dilation(1 s,0.8 c)`

**Formula:** Δt = γ Δτ

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** time · **Visual:** panel

[Source](https://arxiv.org/abs/gr-qc/9712019)

### `length_contraction(proper_length, velocity)`

`@ length_contraction(1 m,0.8 c)`

**Formula:** L = L₀/γ

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** length · **Visual:** panel

[Source](https://arxiv.org/abs/gr-qc/9712019)

### `relativistic_kinetic_energy(mass, velocity)`

`@ relativistic_kinetic_energy(1 kg,0.8 c)`

**Formula:** K = (γ−1)mc², evaluated stably at low velocity

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** energy · **Visual:** panel

[Source](https://arxiv.org/abs/gr-qc/9712019)

### `rest_energy(mass)`

`@ rest_energy(1 kg)`

**Formula:** E₀ = mc²

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** energy · **Visual:** panel

[Source](https://arxiv.org/abs/gr-qc/9712019)

### `relativistic_doppler(frequency, velocity, angle)`

`@ relativistic_doppler(500 THz,0.1 c,0 deg)`

**Formula:** ν_observer = ν_source/[γ(1+β cos θ)]

**Model:** θ between recession velocity and source-to-observer line, source emission-angle convention; θ=0 receding

**Returns:** frequency · **Visual:** panel

[Source](https://arxiv.org/abs/gr-qc/9712019)

### `hawking_temperature(mass)`

`@ hawking_temperature(1 M_sun)`

**Formula:** T_H = ℏc³/(8πGMk_B)

**Model:** Nonrotating uncharged black hole; semiclassical Hawking temperature

**Returns:** temperature · **Visual:** panel

[Source](https://arxiv.org/abs/gr-qc/9712019)

### `black_hole_entropy(mass)`

`@ black_hole_entropy(1 M_sun)`

**Formula:** S = 4πk_B GM²/(ℏc)

**Model:** Schwarzschild Bekenstein–Hawking entropy

**Returns:** entropy · **Visual:** panel

[Source](https://arxiv.org/abs/gr-qc/9712019)

### `black_hole_evaporation_time(mass)`

`@ black_hole_evaporation_time(1 M_sun)`

**Formula:** t_evap = 5120πG²M³/(ℏc⁴)

**Model:** Idealized isolated Schwarzschild black hole; no accretion or greybody/species corrections

**Returns:** time · **Visual:** panel

[Source](https://arxiv.org/abs/gr-qc/9712019)

### `tidal_acceleration(mass, radius, separation)`

`@ tidal_acceleration(10 M_sun,100 km,2 m)`

**Formula:** Δa ≈ 2GMℓ/r³

**Model:** Newtonian radial linear tidal gradient, ℓ ≪ r; no strong-field relativistic correction

**Returns:** acceleration · **Visual:** panel

[Source](https://arxiv.org/abs/gr-qc/9712019)

## Exoplanets

### `transit_depth(planet_radius, star_radius)`

`@ transit_depth(earth,sun)`

**Formula:** δ = (R_p/R_s)²

**Model:** Uniform stellar disk, small opaque planet, central transit; ignores limb darkening

**Returns:** dimensionless · **Visual:** panel

[Source](https://lkreidberg.github.io/batman/docs/html/)

### `transit_duration(orbit, planet, star, geometry)`

`@ transit_duration(earth_orbit,earth,sun,{inclination:90 deg})`

**Formula:** T₁₄ ≈ (P/π) asin[(R_s/a)√((1+k)²−b²)/sin i] √(1−e²)/(1+e sin ω)

**Model:** Keplerian transit duration approximation; projected chord geometry

**Returns:** time · **Visual:** panel

[Source](https://lkreidberg.github.io/batman/docs/html/)

### `transit_probability(orbit, star_radius, planet_radius)`

`@ transit_probability(earth_orbit,sun,earth)`

**Formula:** P_tr = (R_s+R_p)/a × (1+e sin ω)/(1−e²)

**Model:** Random viewing orientation; eccentric Keplerian orbit

**Returns:** dimensionless · **Visual:** panel

[Source](https://lkreidberg.github.io/batman/docs/html/)

### `transit_light_curve(planet, star, orbit, times, geometry=None)`

`@ transit_light_curve(earth,sun,earth_orbit,[-0.3 day,-0.1 day,0 day,0.1 day,0.3 day])`

**Formula:** batman quadratic-limb-darkened Keplerian occultation model

**Model:** batman analytic occultation; default i=90°, u=[0.3,0.2], epoch=0; explicit observer geometry

**Returns:** structured data / typed quantities · **Visual:** transit

[Source](https://lkreidberg.github.io/batman/docs/html/)

### `transit_times(orbit, reference_time, count)`

`@ transit_times(earth_orbit,"2026-01-01",3)`

**Formula:** t_n = t_ref + nP

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** structured data / typed quantities · **Visual:** panel

[Source](https://lkreidberg.github.io/batman/docs/html/)

### `impact_parameter(orbit, inclination, star_radius)`

`@ impact_parameter(earth_orbit,89.9 deg,sun)`

**Formula:** b = a cos i / R_s × (1−e²)/(1+e sin ω)

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** dimensionless · **Visual:** panel

[Source](https://lkreidberg.github.io/batman/docs/html/)

### `radial_velocity_amplitude(orbit, planet_mass, star_mass)`

`@ radial_velocity_amplitude({a:1 AU,central_mass:sun,inclination:90 deg},earth,sun)`

**Formula:** K = (2πG/P)^(1/3) M_p sin i / [(M_s+M_p)^(2/3)√(1−e²)]

**Model:** Keplerian reflex RV; explicit Orbit inclination is interpreted to sky plane

**Returns:** speed · **Visual:** panel

[Source](https://lkreidberg.github.io/batman/docs/html/)

### `radial_velocity_curve(orbit, planet, star, times)`

`@ radial_velocity_curve({a:1 AU,central_mass:sun,inclination:90 deg},earth,sun,[0 day,90 day,180 day,270 day])`

**Formula:** RV(t) = K[cos(ν+ω)+e cos ω]

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** structured data / typed quantities · **Visual:** radial_velocity

[Source](https://lkreidberg.github.io/batman/docs/html/)

### `minimum_planet_mass(rv_data, stellar_mass, period)`

`@ minimum_planet_mass({time:[0 day,90 day,180 day,270 day],velocity:[0 m/s,10 m/s,0 m/s,-10 m/s]},sun,360 day)`

**Formula:** Fit sinusoidal RV at fixed period; solve K=(2πG/P)^(1/3)m/(M+m)^(2/3)

**Model:** Circular orbit sinusoidal fit, sin i=1; no eccentric RV fitting

**Returns:** structured data: minimum mass, RV amplitude and systemic velocity · **Visual:** panel

[Source](https://lkreidberg.github.io/batman/docs/html/)

### `planet_radius_from_transit(depth, star_radius)`

`@ planet_radius_from_transit(0.000084,sun)`

**Formula:** R_p = R_s √δ

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** length · **Visual:** panel

[Source](https://lkreidberg.github.io/batman/docs/html/)

### `equilibrium_temperature(star, orbit, albedo)`

`@ equilibrium_temperature(sun,earth_orbit,0.3)`

**Formula:** T_eq = T_s √(R_s/(2a)) (1−A)^(1/4)

**Model:** Full heat redistribution, blackbody emitter, no greenhouse; uses semimajor axis

**Returns:** temperature · **Visual:** panel

[Source](https://lkreidberg.github.io/batman/docs/html/)

### `orbital_insolation(star, orbital_distance)`

`@ orbital_insolation(sun,1 AU)`

**Formula:** S = L/(4πr²)

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** energy flux · **Visual:** panel

[Source](https://lkreidberg.github.io/batman/docs/html/)

### `planet_density(mass, radius)`

`@ planet_density(1 M_earth,1 R_earth)`

**Formula:** ρ = 3M/(4πR³)

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** density · **Visual:** panel

[Source](https://lkreidberg.github.io/batman/docs/html/)

### `atmospheric_scale_height(temperature, gravity, mean_molecular_mass)`

`@ atmospheric_scale_height(288 K,9.81 m/s2,28.97 u)`

**Formula:** H = k_B T/(m̄ g)

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** length · **Visual:** panel

[Source](https://lkreidberg.github.io/batman/docs/html/)

### `transmission_signal(planet, star, atmosphere)`

`@ transmission_signal(earth,sun,{temperature:288 K,mean_molecular_mass:28.97 u,scale_heights:5})`

**Formula:** Δδ ≈ 2 N_H R_p H / R_s²

**Model:** Thin isothermal atmosphere, effective absorbing height N_H H

**Returns:** dimensionless · **Visual:** panel

[Source](https://lkreidberg.github.io/batman/docs/html/)

### `planet_phase_curve(planet, star, orbit)`

`@ planet_phase_curve(earth,sun,earth_orbit)`

**Formula:** F_p/F_s = A_g(R_p/a)² [sin α + (π−α) cos α]/π

**Model:** Lambertian reflected light only; geometric albedo 0.3, edge-on circular phase; thermal emission excluded

**Returns:** structured data / typed quantities · **Visual:** phase

[Source](https://lkreidberg.github.io/batman/docs/html/)

## Cosmology

### `cosmology(model=Planck18)`

`@ cosmology(model="Planck18")`

**Formula:** FLRW cosmology parameters, including H₀, Ωm, ΩΛ, T_CMB

**Model:** Astropy FLRW; default Planck18 explicitly reported

**Returns:** structured data / typed quantities · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/cosmology/)

### `age_of_universe(model=Planck18)`

`@ age_of_universe(model="Planck18")`

**Formula:** t₀ = ∫₀∞ dz/[(1+z)H(z)]

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** time · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/cosmology/)

### `cosmic_age(z, model=Planck18)`

`@ cosmic_age(3)`

**Formula:** t(z) = ∫z∞ dz′/[(1+z′)H(z′)]

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** time · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/cosmology/)

### `hubble_parameter(z, model=Planck18)`

`@ hubble_parameter(1)`

**Formula:** H(z) = H₀ E(z)

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** inverse time / Hubble rate · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/cosmology/)

### `hubble_time(model=Planck18)`

`@ hubble_time()`

**Formula:** t_H = 1/H₀

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** time · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/cosmology/)

### `lookback_time(z, model=Planck18)`

`@ lookback_time(1)`

**Formula:** t_L = ∫₀z dz′/[(1+z′)H(z′)]

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** time · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/cosmology/)

### `comoving_distance(z, model=Planck18)`

`@ comoving_distance(1)`

**Formula:** D_C = c ∫₀z dz′/H(z′)

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** length · **Visual:** cosmology

[Source](https://docs.astropy.org/en/stable/cosmology/)

### `luminosity_distance(z, model=Planck18)`

`@ luminosity_distance(1)`

**Formula:** D_L = (1+z)D_M

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** length · **Visual:** cosmology

[Source](https://docs.astropy.org/en/stable/cosmology/)

### `angular_diameter_distance(z, model=Planck18)`

`@ angular_diameter_distance(1)`

**Formula:** D_A = D_M/(1+z)

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** length · **Visual:** cosmology

[Source](https://docs.astropy.org/en/stable/cosmology/)

### `light_travel_distance(z, model=Planck18)`

`@ light_travel_distance(1)`

**Formula:** D_LT = c t_L

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** length · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/cosmology/)

### `distance_between_redshifts(z1, z2, model=Planck18)`

`@ distance_between_redshifts(0.5,1)`

**Formula:** ΔD_C = |D_C(z₂) − D_C(z₁)|

**Model:** Radial comoving separation on same sightline; not angular-diameter lens distance

**Returns:** length · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/cosmology/)

### `comoving_volume(z, model=Planck18)`

`@ comoving_volume(1)`

**Formula:** V_C(z) = full-sky comoving volume enclosed by z

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** volume · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/cosmology/)

### `critical_density(z, model=Planck18)`

`@ critical_density(0)`

**Formula:** ρ_c = 3H(z)²/(8πG)

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** density · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/cosmology/)

### `matter_density(z, model=Planck18)`

`@ matter_density(1)`

**Formula:** ρ_m = Ω_m(z)ρ_c(z)

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** density · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/cosmology/)

### `dark_energy_density(z, model=Planck18)`

`@ dark_energy_density(1)`

**Formula:** ρ_DE = Ω_DE(z)ρ_c(z)

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** density · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/cosmology/)

### `density_parameters(z, model=Planck18)`

`@ density_parameters(1)`

**Formula:** Ω_i(z) from FLRW model

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** structured data / typed quantities · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/cosmology/)

### `scale_factor(z)`

`@ scale_factor(2)`

**Formula:** a = 1/(1+z)

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** dimensionless · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/cosmology/)

### `redshift_from_scale_factor(scale_factor)`

`@ redshift_from_scale_factor(0.5)`

**Formula:** z = 1/a − 1

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** dimensionless · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/cosmology/)

### `cmb_temperature(z, model=Planck18)`

`@ cmb_temperature(10)`

**Formula:** T_CMB(z) = T_CMB,0 (1+z)

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** temperature · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/cosmology/)

### `cosmological_distance_modulus(z, model=Planck18)`

`@ cosmological_distance_modulus(1)`

**Formula:** μ = 5 log₁₀(D_L/10pc)

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** dimensionless · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/cosmology/)

### `hubble_law_velocity(distance, H0)`

`@ hubble_law_velocity(10 Mpc,70 km/s/Mpc)`

**Formula:** v = H₀d

**Model:** Low-redshift linear Hubble approximation only; reject implied |v| > 0.1c

**Returns:** speed · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/cosmology/)

### `particle_horizon(model=Planck18)`

`@ particle_horizon()`

**Formula:** D_particle = c ∫₀∞ dz/H(z)

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** length · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/cosmology/)

## Galaxies & Interstellar Medium

### `galaxy_rotation_curve(radius, mass_model)`

`@ galaxy_rotation_curve([1 kpc,5 kpc,10 kpc],{model:plummer,mass:1e11 M_sun,scale:3 kpc})`

**Formula:** v_c(r) = √[G M_enclosed(r)/r]

**Model:** Spherical Plummer or point mass; explicit enclosed-mass profile supported

**Returns:** structured data / typed quantities · **Visual:** rotation

[Source](https://ned.ipac.caltech.edu/level5/)

### `dynamical_mass(velocity, radius)`

`@ dynamical_mass(200 km/s,10 kpc)`

**Formula:** M(<r) = v²r/G

**Model:** Spherical mass distribution, circular orbit

**Returns:** mass · **Visual:** panel

[Source](https://ned.ipac.caltech.edu/level5/)

### `virial_mass(velocity_dispersion, radius, model=uniform_sphere)`

`@ virial_mass(100 km/s,1 kpc)`

**Formula:** M_vir = k σ²R/G

**Model:** Uniform spherical system k=5, isotropic 1D dispersion; explicit k object allowed

**Returns:** mass · **Visual:** panel

[Source](https://ned.ipac.caltech.edu/level5/)

### `velocity_dispersion(velocities)`

`@ velocity_dispersion([10 km/s,20 km/s,30 km/s])`

**Formula:** σ = √[Σ(v_i−v̄)²/(N−1)]

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** speed · **Visual:** panel

[Source](https://ned.ipac.caltech.edu/level5/)

### `surface_brightness(flux, angular_area)`

`@ surface_brightness(1e-15 W/m2,10 arcsec2)`

**Formula:** I = F/Ω

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** energy flux per solid angle · **Visual:** panel

[Source](https://ned.ipac.caltech.edu/level5/)

### `tully_fisher_distance(rotation_speed, magnitude, calibration)`

`@ tully_fisher_distance(200 km/s,12,{slope:-10,intercept:-21,reference_speed:200 km/s,extinction:0})`

**Formula:** M = a log₁₀(v/v_ref)+b; d=10pc × 10^[(m−M−A)/5]

**Model:** User-supplied passband calibration; intrinsic scatter not automatically assumed

**Returns:** structured data / typed quantities · **Visual:** panel

[Source](https://ned.ipac.caltech.edu/level5/)

### `star_formation_rate_halpha(luminosity, calibration)`

`@ star_formation_rate_halpha(1e34 W,{coefficient:7.9e-42})`

**Formula:** SFR = C_Hα L_Hα

**Model:** Coefficient in (M_sun/yr)/(erg/s), e.g. Kennicutt 1998 Salpeter 7.9e-42; extinction correction required externally

**Returns:** mass flow rate · **Visual:** panel

[Source](https://ned.ipac.caltech.edu/level5/)

### `metallicity_from_lines(line_fluxes, calibration)`

`@ metallicity_from_lines({NII:0.1,Halpha:1,OIII:1,Hbeta:0.35},{index:N2,intercept:8.90,slope:0.57})`

**Formula:** 12+log(O/H) = a + b N2 or a + b O3N2

**Model:** Explicit strong-line calibration; N2=log[NII]/Hα, O3N2=log(([OIII]/Hβ)/([NII]/Hα))

**Returns:** dimensionless · **Visual:** panel

[Source](https://ned.ipac.caltech.edu/level5/)

### `jeans_mass(temperature, density, mean_molecular_weight)`

`@ jeans_mass(10 K,1e-17 kg/m3,2.33)`

**Formula:** M_J = π^(5/2)c_s³/(6G^(3/2)ρ^(1/2)); c_s²=kT/(μm_p)

**Model:** Homogeneous isothermal ideal gas, dimensionless mean molecular weight

**Returns:** mass · **Visual:** panel

[Source](https://ned.ipac.caltech.edu/level5/)

### `jeans_length(temperature, density, mean_molecular_weight)`

`@ jeans_length(10 K,1e-17 kg/m3,2.33)`

**Formula:** λ_J = c_s √(π/(Gρ))

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** length · **Visual:** panel

[Source](https://ned.ipac.caltech.edu/level5/)

### `free_fall_time(density)`

`@ free_fall_time(1e-17 kg/m3)`

**Formula:** t_ff = √(3π/(32Gρ))

**Model:** Pressureless uniform sphere

**Returns:** time · **Visual:** panel

[Source](https://ned.ipac.caltech.edu/level5/)

### `optical_depth(absorption_coefficient, path_length)`

`@ optical_depth(0.01 /m,100 m)`

**Formula:** τ = αℓ

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** dimensionless · **Visual:** panel

[Source](https://ned.ipac.caltech.edu/level5/)

### `virial_temperature(mass, radius, model=ionized_primordial)`

`@ virial_temperature(1e12 M_sun,200 kpc)`

**Formula:** T_vir = μm_p GM/(2k_B R)

**Model:** Spherical halo; fully ionized primordial gas μ=0.59; explicit μ object supported

**Returns:** temperature · **Visual:** panel

[Source](https://ned.ipac.caltech.edu/level5/)

### `eddington_luminosity(mass, opacity=0.034 m2 / kg)`

`@ eddington_luminosity(10 M_sun)`

**Formula:** L_Edd = 4πGMc/κ

**Model:** Spherical radiation-pressure equilibrium; κ=0.034 m²/kg electron scattering default

**Returns:** power · **Visual:** panel

[Source](https://ned.ipac.caltech.edu/level5/)

### `accretion_luminosity(mass, accretion_rate, efficiency)`

`@ accretion_luminosity(10 M_sun,1e-8 M_sun/yr,0.1)`

**Formula:** L = η ṁ c²; Eddington ratio also reported

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** structured data / typed quantities · **Visual:** panel

[Source](https://ned.ipac.caltech.edu/level5/)

### `bondi_radius(mass, sound_speed)`

`@ bondi_radius(10 M_sun,10 km/s)`

**Formula:** r_B = 2GM/c_s²

**Model:** Bondi capture radius convention with factor 2

**Returns:** length · **Visual:** panel

[Source](https://ned.ipac.caltech.edu/level5/)

### `tidal_disruption_radius(black_hole_mass, star_mass, star_radius)`

`@ tidal_disruption_radius(1e6 M_sun,sun,sun)`

**Formula:** r_t ≈ R_s(M_BH/M_s)^(1/3)

**Model:** Newtonian disruption estimate; capture may occur inside horizon

**Returns:** length · **Visual:** panel

[Source](https://ned.ipac.caltech.edu/level5/)

## Spectroscopy & Photometry

### `wavelength_to_frequency(wavelength)`

`@ wavelength_to_frequency(500 nm)`

**Formula:** ν = c/λ

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** frequency · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/units/)

### `frequency_to_wavelength(frequency)`

`@ frequency_to_wavelength(600 THz)`

**Formula:** λ = c/ν

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** length · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/units/)

### `photon_energy(wavelength)`

`@ photon_energy(500 nm)`

**Formula:** E = hc/λ

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** energy · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/units/)

### `redshift(emitted_wavelength, observed_wavelength)`

`@ redshift(500 nm,600 nm)`

**Formula:** z = (λ_observed − λ_emitted)/λ_emitted

**Model:** Dimensionless spectral redshift; not automatically a recession velocity

**Returns:** dimensionless · **Visual:** spectrum

[Source](https://docs.astropy.org/en/stable/units/)

### `doppler_shift(wavelength, velocity, model=relativistic)`

`@ doppler_shift(500 nm,30 km/s)`

**Formula:** λ_obs = λ_emit √[(1+β)/(1−β)] (relativistic) or λ_emit(1+β)

**Model:** Line-of-sight recession positive; relativistic default, classical optional

**Returns:** structured data / typed quantities · **Visual:** spectrum

[Source](https://docs.astropy.org/en/stable/units/)

### `radial_velocity_from_shift(emitted_wavelength, observed_wavelength)`

`@ radial_velocity_from_shift(500 nm,600 nm)`

**Formula:** v/c = [(λ_obs/λ_emit)²−1]/[(λ_obs/λ_emit)²+1]

**Model:** Special-relativistic longitudinal Doppler only; cosmological and gravitational shifts excluded

**Returns:** speed · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/units/)

### `spectral_resolution(wavelength, delta_wavelength)`

`@ spectral_resolution(500 nm,0.1 nm)`

**Formula:** R = λ/Δλ

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** dimensionless · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/units/)

### `equivalent_width(spectrum, continuum, interval)`

`@ equivalent_width({wavelength:[499 nm,500 nm,501 nm],flux:[1,0.5,1]},1,[499 nm,501 nm])`

**Formula:** EW = ∫(1−Fλ/F_cont) dλ

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** length · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/units/)

### `line_broadening(line_width, rest_wavelength, model=velocity)`

`@ line_broadening(0.1 nm,500 nm)`

**Formula:** Δv_FWHM = c Δλ_FWHM/λ₀

**Model:** Velocity FWHM or pure thermal Doppler temperature with explicit atomic mass; instrumental width not subtracted

**Returns:** speed or temperature, by model · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/units/)

### `flux_to_magnitude(flux, zero_point)`

`@ flux_to_magnitude(1e-12 W/m2,1e-8 W/m2)`

**Formula:** m = −2.5 log₁₀(F/F₀)

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** dimensionless · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/units/)

### `magnitude_to_flux(magnitude, zero_point)`

`@ magnitude_to_flux(10,1e-8 W/m2)`

**Formula:** F = F₀ 10^(−0.4m)

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** same unit as zero_point · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/units/)

### `magnitude_difference(flux1, flux2)`

`@ magnitude_difference(100,10)`

**Formula:** m₁−m₂ = −2.5 log₁₀(F₁/F₂)

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** dimensionless · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/units/)

### `extinction_correct(flux, extinction)`

`@ extinction_correct(1e-12 W/m2,0.5)`

**Formula:** F_intrinsic = F_observed 10^(0.4A)

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** same unit as flux · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/units/)

### `signal_to_noise(signal, noise)`

`@ signal_to_noise(100,10)`

**Formula:** SNR = signal / noise

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** dimensionless · **Visual:** panel

[Source](https://docs.astropy.org/en/stable/units/)

## Telescope & Optics

### `telescope_magnification(focal_length, eyepiece_focal_length)`

`@ telescope_magnification(1000 mm,25 mm)`

**Formula:** M = f_objective/f_eyepiece

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** dimensionless · **Visual:** panel

[Source](https://www.stsci.edu/hst/instrumentation/reference-data-for-calibration-and-tools)

### `focal_ratio(focal_length, aperture)`

`@ focal_ratio(1000 mm,200 mm)`

**Formula:** f-number = f/D

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** dimensionless · **Visual:** panel

[Source](https://www.stsci.edu/hst/instrumentation/reference-data-for-calibration-and-tools)

### `aperture_area(diameter)`

`@ aperture_area(200 mm)`

**Formula:** A = πD²/4

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** area · **Visual:** panel

[Source](https://www.stsci.edu/hst/instrumentation/reference-data-for-calibration-and-tools)

### `rayleigh_resolution(aperture, wavelength)`

`@ rayleigh_resolution(200 mm,550 nm)`

**Formula:** θ = 1.22 λ/D

**Model:** Circular unobstructed aperture, Rayleigh first-minimum criterion

**Returns:** angle · **Visual:** panel

[Source](https://www.stsci.edu/hst/instrumentation/reference-data-for-calibration-and-tools)

### `diffraction_limit(aperture, wavelength)`

`@ diffraction_limit(200 mm,550 nm)`

**Formula:** θ = 1.22 λ/D

**Model:** Rayleigh criterion, circular unobstructed aperture

**Returns:** angle · **Visual:** panel

[Source](https://www.stsci.edu/hst/instrumentation/reference-data-for-calibration-and-tools)

### `field_of_view(focal_length, sensor_size)`

`@ field_of_view(1000 mm,36 mm)`

**Formula:** FOV = 2 atan(s/(2f))

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** angle · **Visual:** panel

[Source](https://www.stsci.edu/hst/instrumentation/reference-data-for-calibration-and-tools)

### `pixel_scale(pixel_size, focal_length)`

`@ pixel_scale(3.76 um,1000 mm)`

**Formula:** Pixel scale = p/f radians per pixel

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** angle per pixel · **Visual:** panel

[Source](https://www.stsci.edu/hst/instrumentation/reference-data-for-calibration-and-tools)

### `plate_scale(focal_length)`

`@ plate_scale(1000 mm)`

**Formula:** Plate scale = 1/f radians per meter

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** angle per length · **Visual:** panel

[Source](https://www.stsci.edu/hst/instrumentation/reference-data-for-calibration-and-tools)

### `light_gathering_power(aperture, reference_aperture)`

`@ light_gathering_power(200 mm,7 mm)`

**Formula:** Light gathering ratio = (D/D_ref)²

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** dimensionless · **Visual:** panel

[Source](https://www.stsci.edu/hst/instrumentation/reference-data-for-calibration-and-tools)

### `limiting_magnitude(aperture, conditions, model=visual_dark_sky)`

`@ limiting_magnitude(200 mm,{extinction:0.2})`

**Formula:** m_lim ≈ 2 + 5 log₁₀(D_mm) − extinction

**Model:** Empirical visual dark-sky estimate; observer, seeing, magnification and sky brightness not independently fitted

**Returns:** dimensionless · **Visual:** panel

[Source](https://www.stsci.edu/hst/instrumentation/reference-data-for-calibration-and-tools)

### `exposure_time(target_snr, source, instrument, conditions)`

`@ exposure_time(10,{rate:10 /s},{pixels:10,read_noise:3},{sky_rate:1 /s})`

**Formula:** SNR = St/√[(S+B)t+N_pix N_exp RN²]; solve quadratic for t

**Model:** Poisson source + sky + dark, independent read noise; rates are electron counts per second

**Returns:** time · **Visual:** panel

[Source](https://www.stsci.edu/hst/instrumentation/reference-data-for-calibration-and-tools)

### `telescope_snr(source, instrument, exposure, conditions)`

`@ telescope_snr({rate:10 /s},{pixels:10,read_noise:3},100 s,{sky_rate:1 /s})`

**Formula:** SNR = St / √[(S+B)t + N_pix N_exp RN²]

**Model:** Poisson source, sky and dark current plus independent read noise

**Returns:** dimensionless · **Visual:** panel

[Source](https://www.stsci.edu/hst/instrumentation/reference-data-for-calibration-and-tools)

### `nyquist_sampling(fwhm, pixel_scale)`

`@ nyquist_sampling(2 arcsec,1 arcsec/pixel)`

**Formula:** Sampling = FWHM/pixel_scale; Nyquist requires ≥ 2 pixels

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** structured data / typed quantities · **Visual:** panel

[Source](https://www.stsci.edu/hst/instrumentation/reference-data-for-calibration-and-tools)

## Astronomical Data Analysis

### `detect_sources(image, threshold, method=dao)`

`@ detect_sources([[0,0,0,0,0],[0,1,3,1,0],[0,3,10,3,0],[0,1,3,1,0],[0,0,0,0,0]],2)`

**Formula:** DAOStarFinder detects local peaks after Gaussian convolution

**Model:** DAOStarFinder Gaussian FWHM=3px; background should be removed first

**Returns:** structured data / typed quantities · **Visual:** image

[Source](https://photutils.readthedocs.io/en/stable/)

### `estimate_background(image, method=sigma_clip)`

`@ estimate_background([[1,1,1],[1,100,1],[1,1,1]])`

**Formula:** Sigma-clipped median and robust MAD RMS or Background2D mesh

**Model:** Sigma-clipped scalar background or median mesh; 3σ clipping

**Returns:** structured data / typed quantities · **Visual:** image

[Source](https://photutils.readthedocs.io/en/stable/)

### `centroid(image, region)`

`@ centroid([[0,0,0],[0,10,0],[0,0,0]],{x:0,y:0,width:3,height:3})`

**Formula:** Centroid = Σ xI/ΣI, Σ yI/ΣI after regional median subtraction

**Model:** Positive center-of-mass estimator after median background subtraction

**Returns:** structured data / typed quantities · **Visual:** image

[Source](https://photutils.readthedocs.io/en/stable/)

### `aperture_photometry(image, aperture, background=0)`

`@ aperture_photometry([[0,0,0],[0,10,0],[0,0,0]],{x:1,y:1,radius:1},background=0)`

**Formula:** Flux = Σ w_i(I_i−background); exact circular overlap weights

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** structured data / typed quantities · **Visual:** image

[Source](https://photutils.readthedocs.io/en/stable/)

### `psf_photometry(image, psf_model, positions)`

`@ psf_photometry([[0,0,0,0,0],[0,1,3,1,0],[0,3,10,3,0],[0,1,3,1,0],[0,0,0,0,0]],{fwhm:2,fit_size:5},[[2,2]])`

**Formula:** Fit circular Gaussian PSF simultaneously in local source cutouts

**Model:** photutils CircularGaussianPRF; fixed FWHM, fitted x,y and integrated flux

**Returns:** structured data / typed quantities · **Visual:** image

[Source](https://photutils.readthedocs.io/en/stable/)

### `photometric_calibration(measurements, reference_catalog)`

`@ photometric_calibration([1000,100,10],[10,12.5,15])`

**Formula:** Zero point = weighted mean(m_ref + 2.5log₁₀ F)

**Model:** Matched reference stars in same passband, no color/airmass term; scatter reported

**Returns:** structured data / typed quantities · **Visual:** panel

[Source](https://photutils.readthedocs.io/en/stable/)

### `world_to_pixel(sky_coordinate, wcs)`

`@ world_to_pixel({ra:10 deg,dec:20 deg},{CTYPE1:"RA---TAN",CTYPE2:"DEC--TAN",CRPIX1:1,CRPIX2:1,CRVAL1:10,CRVAL2:20,CDELT1:-0.001,CDELT2:0.001})`

**Formula:** FITS WCS all_world2pix, zero-based pixels

**Model:** FITS WCS, zero-based pixel output

**Returns:** structured data / typed quantities · **Visual:** panel

[Source](https://photutils.readthedocs.io/en/stable/)

### `pixel_to_world(pixel_coordinate, wcs)`

`@ pixel_to_world([0,0],{CTYPE1:"RA---TAN",CTYPE2:"DEC--TAN",CRPIX1:1,CRPIX2:1,CRVAL1:10,CRVAL2:20,CDELT1:-0.001,CDELT2:0.001})`

**Formula:** FITS WCS all_pix2world, zero-based input pixels

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** structured data / typed quantities · **Visual:** panel

[Source](https://photutils.readthedocs.io/en/stable/)

### `align_images(images, reference)`

`@ align_images([[[0,0,0],[0,1,0],[0,0,0]],[[0,0,0],[0,0,1],[0,0,0]]],0)`

**Formula:** FFT phase correlation estimates translation; spline resampling aligns frames

**Model:** Translation-only integer phase correlation; constant-zero fill, cubic interpolation; no rotation or distortion

**Returns:** structured data / typed quantities · **Visual:** image

[Source](https://photutils.readthedocs.io/en/stable/)

### `stack_images(images, method=median)`

`@ stack_images([[[1,2],[3,4]],[[3,4],[5,6]]])`

**Formula:** Pixelwise median or mean over aligned images

**Model:** Requires aligned equal-size frames; median or mean; no automatic registration

**Returns:** structured data / typed quantities · **Visual:** image

[Source](https://photutils.readthedocs.io/en/stable/)

### `light_curve(time, flux)`

`@ light_curve([0 day,1 day,2 day],[1,0.99,1])`

**Formula:** Sort paired observation time and flux; preserve measured flux

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** structured data / typed quantities · **Visual:** light_curve

[Source](https://photutils.readthedocs.io/en/stable/)

### `periodogram(time, flux, errors=None)`

`@ periodogram([0 day,0.2 day,0.5 day,0.7 day,1 day,1.3 day],[0,1,0,-1,0,1])`

**Formula:** Generalized weighted floating-mean Lomb–Scargle periodogram

**Model:** Astropy LombScargle automatic frequency grid; uncertainties optional, false-alarm probability reported

**Returns:** structured data / typed quantities · **Visual:** periodogram

[Source](https://photutils.readthedocs.io/en/stable/)

### `phase_fold(time, flux, period, epoch=0)`

`@ phase_fold([0 day,1 day,2 day],[1,0.9,1],2 day)`

**Formula:** φ = ((t−epoch)/P) mod 1

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** structured data / typed quantities · **Visual:** phase

[Source](https://photutils.readthedocs.io/en/stable/)

### `fit_transit(time, flux, model, parameters)`

`@ fit_transit([-0.3 day,-0.1 day,0 day,0.1 day,0.3 day],[1,0.99,0.99,0.99,1],{period:3 day,a_over_rstar:8},{radius_ratio:0.1,epoch:0 day,inclination:90 deg})`

**Formula:** Least-squares batman transit fit in radius ratio, epoch and inclination

**Model:** Quadratic limb-darkened batman, fixed period and a/Rstar; bounded least squares

**Returns:** structured data / typed quantities · **Visual:** transit

[Source](https://photutils.readthedocs.io/en/stable/)

### `fit_spectrum(wavelengths, fluxes, model)`

`@ fit_spectrum([499 nm,499.5 nm,500 nm,500.5 nm,501 nm],[1,2,3,2,1],gaussian)`

**Formula:** Fit Gaussian line + constant continuum, or scaled Planck continuum

**Model:** Unweighted least squares; Gaussian line or scaled blackbody; no instrument response correction

**Returns:** structured data / typed quantities · **Visual:** spectrum_curve

[Source](https://photutils.readthedocs.io/en/stable/)

### `fit_orbit(observations, initial_model)`

`@ fit_orbit({time:[0 s,100 s,200 s],positions:[[7000000,0,0],[6995930,749855,0],[6983720,1498840,0]]},{r:[7000000,0,0],v:[0,7500,0],central_mass:earth})`

**Formula:** Fit initial Cartesian r,v to 3D timed positions under two-body dynamics

**Model:** Newtonian Cartesian least squares, central mass fixed; input positions in m, times in s, initial epoch t=0

**Returns:** structured data / typed quantities · **Visual:** orbit

[Source](https://photutils.readthedocs.io/en/stable/)

### `cross_match_catalog(catalog1, catalog2, tolerance)`

`@ cross_match_catalog([{ra:10 deg,dec:20 deg}],[{ra:10.0001 deg,dec:20 deg}],1 arcsec)`

**Formula:** Nearest-neighbor spherical catalogue match within tolerance

**Model:** ICRS nearest-neighbor angular match, many-to-one; epochs/proper motion must be aligned first

**Returns:** structured data / typed quantities · **Visual:** panel

[Source](https://photutils.readthedocs.io/en/stable/)

### `propagate_uncertainty(expression, measurements)`

`@ propagate_uncertainty("m/r^2",{m:{value:10 kg,sigma:1 kg},r:{value:2 m,sigma:0.1 m}})`

**Formula:** σ_f² = J C Jᵀ; central numerical derivatives, optional full covariance

**Model:** First-order Gaussian propagation; independent inputs unless covariance supplied; nonlinear large-error cases may require Monte Carlo

**Returns:** structured data / typed quantities · **Visual:** panel

[Source](https://photutils.readthedocs.io/en/stable/)

## Gravitational Waves

### `chirp_mass(mass1, mass2)`

`@ chirp_mass(30 M_sun,30 M_sun)`

**Formula:** M_chirp = (m₁m₂)^(3/5)/(m₁+m₂)^(1/5)

**Model:** SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied

**Returns:** mass · **Visual:** panel

[Source](https://arxiv.org/abs/1310.1528)

### `gravitational_wave_frequency(orbit)`

`@ gravitational_wave_frequency(earth_orbit)`

**Formula:** f_GW = 2/P_orbit

**Model:** Dominant quadrupole harmonic of a circular Newtonian binary

**Returns:** frequency · **Visual:** panel

[Source](https://arxiv.org/abs/1310.1528)

### `gravitational_wave_strain(binary, distance, model=quadrupole)`

`@ gravitational_wave_strain({mass1:30 M_sun,mass2:30 M_sun,separation:1000 km},100 Mpc)`

**Formula:** h₀ = 4G²m₁m₂/(c⁴ad)

**Model:** Leading quadrupole circular binary, face-on optimal strain amplitude; local source-frame parameters

**Returns:** dimensionless · **Visual:** panel

[Source](https://arxiv.org/abs/1310.1528)

### `inspiral_time(mass1, mass2, separation, eccentricity=0)`

`@ inspiral_time(30 M_sun,30 M_sun,1000 km,0.2)`

**Formula:** Peters 1964 eccentric inspiral integral; circular t = 5c⁵a⁴/[256G³m₁m₂(m₁+m₂)]

**Model:** Orbit-averaged quadrupole radiation reaction, point masses; no spin or merger dynamics

**Returns:** time · **Visual:** panel

[Source](https://arxiv.org/abs/1310.1528)

### `gravitational_wave_energy_loss(binary)`

`@ gravitational_wave_energy_loss({mass1:30 M_sun,mass2:30 M_sun,separation:1000 km})`

**Formula:** P = (32/5)G⁴ m₁²m₂²(m₁+m₂)/(c⁵a⁵)

**Model:** Circular Newtonian quadrupole emitted power, positive energy loss rate

**Returns:** power · **Visual:** panel

[Source](https://arxiv.org/abs/1310.1528)

### `merger_frequency(mass1, mass2, spins, model=kerr_isco)`

`@ merger_frequency(30 M_sun,30 M_sun,[0,0])`

**Formula:** f_GW,ISCO = c³/[πGM(r_ISCO^(3/2)+χ_eff)]; χ_eff=(m₁χ₁+m₂χ₂)/M

**Model:** Effective-spin Kerr ISCO proxy, aligned spin components; not a calibrated full-GR merger-peak frequency

**Returns:** frequency · **Visual:** panel

[Source](https://arxiv.org/abs/1310.1528)

### `ringdown_frequency(final_mass, final_spin, mode=220)`

`@ ringdown_frequency(60 M_sun,0.7)`

**Formula:** f_220 = c³/(2πGM) [1.5251−1.1568(1−a*)^0.1292]

**Model:** Berti et al. fundamental Kerr l=m=2,n=0 fit; 0 ≤ spin < 0.99

**Returns:** frequency · **Visual:** panel

[Source](https://arxiv.org/abs/1310.1528)

### `gravitational_waveform(binary, times, model=quadrupole)`

`@ gravitational_waveform({mass1:30 M_sun,mass2:30 M_sun,separation:1000 km,distance:100 Mpc},[0 s,0.01 s,0.02 s,0.03 s])`

**Formula:** Leading chirp f(t), h_+(t)=A(t) cos φ(t), dφ/dt=2πf(t)

**Model:** Leading Newtonian circular face-on inspiral only, terminated at Schwarzschild ISCO; no merger, ringdown or detector response

**Returns:** structured data / typed quantities · **Visual:** waveform

[Source](https://arxiv.org/abs/1310.1528)
