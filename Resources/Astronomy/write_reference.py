"""Generate the user reference from the exported executable registry."""
import json
from pathlib import Path
root=Path(__file__).resolve().parents[2]
methods=json.loads((Path(__file__).with_name('methods.json')).read_text())
rows=['# Astronomy method reference','',
'The complete specification contains **234 methods in 14 families**. This reference is generated from the executable registry.', '',
'Bare numbers use SI units, including radians. Parallax is the explicit exception: a bare parallax is in arcseconds. Prefer units such as `30 deg`, `1 AU`, `10 M_sun` and `100 mas`. Astronomical units follow Astropy/IAU definitions; `R_earth` is the nominal equatorial radius, while `radius(earth)` returns the mean volumetric radius.', '',
'Dates default to UTC. An omitted astronomical epoch is **J2000**, never silently the current time. Orbits use ICRS axes and TDB epochs. Inclination is to the ICRS equatorial plane, unless an explicit orbit is provided; transit geometry supplies its own observer inclination.', '',
'The app bundles [JPL DE440s](https://ssd.jpl.nasa.gov/doc/Park.2021.AJ.DE440.pdf), covering 1849-12-26 through 2150-01-22, verified by SHA-256 during setup. Astropy returns planetary barycenters for Mars through Pluto, and Earth/Moon centers. Earth orientation uses the pinned bundled IERS tables, and extrapolation/leap-second warnings are preserved in the working. Fixed stellar coordinates are approximate reference positions, not a complete proper-motion catalogue.', '',
'Nested calls retain typed objects: `eccentricity(orbit(earth,sun))`. `earth_orbit` is shorthand for the J2000 Earth osculating orbit. Ideal circular transfers require explicit circular, coplanar orbits, e.g. `{a:1 AU,central_mass:sun}`; their assumptions are checked.', '',
'Object fields use `key:value`; named function arguments use `key=value`. Quote ISO dates, file paths and model names. Observers use `{longitude:121.56 deg,latitude:25.03 deg,height:10 m}`. Numeric data accept arrays, or `{start:0 day,stop:10 day,count:500}` for a sampled model interval.', '',
'Images accept nested arrays or quoted FITS/CSV paths. Time/flux data accept arrays or quoted CSV column paths (`"/path/curve.csv#time"`, `"/path/curve.csv#flux"`); numeric CSV times are seconds. A data object `{file:"/path/curve.csv",column:"time",unit:"day"}` preserves explicit units. WCS methods also accept a FITS path. Files are read only.', '',
'Model estimates are labelled. Eclipse functions screen geometric candidates; they do not certify contact times. Fuel-scaling stellar lifetimes record input metallicity but have no metallicity dependence. Gravitational-wave models are quadrupole inspirals or named ISCO/ringdown proxies, not full numerical-relativity waveforms. Cosmology defaults to explicitly reported Planck18; pass `model="Planck15"`, `model="WMAP9"`, or `{H0:70 km/s/Mpc,Om0:0.3,Tcmb0:2.7255 K}`.', '',
'Inputs are treated as exact unless an uncertainty-aware method is used. Catalogue/model uncertainty is not fabricated. `propagate_uncertainty` supports quantity-valued independent errors or a covariance matrix in the stated input-unit products. `particle_horizon` reports quadrature error only. Calibration-dependent methods require explicit calibration objects in their examples.', '',
'Every result includes working, formula, numerical inputs and conversions, model, source and a domain diagram, sampled curve or quantity/data panel. Copying a structured result exports its JSON. Transit charts expose radius and inclination controls; sky maps can be rotated.', '']
for category in dict.fromkeys(m['category'] for m in methods):
    rows+=['## '+category,'']
    for m in [m for m in methods if m['category']==category]:
        params=', '.join(p['name']+('='+p['default'] if not p['required'] else '') for p in m['parameters'])
        rows+=['### `'+m['name']+'('+params+')`','', '`@ '+m['example']+'`','',
          '**Formula:** '+m['formula'],'', '**Model:** '+m['model'],'',
          '**Returns:** '+m['returns']+' · **Visual:** '+m['visualization'],'', '[Source]('+m['source']+')','']
(root/'AstronomyMethods.md').write_text('\n'.join(rows))
