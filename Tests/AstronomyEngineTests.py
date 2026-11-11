"""Acceptance tests for all 234 specified methods, reference values and input boundaries."""
import importlib.util, json, math, os, sys, tempfile, unittest
from pathlib import Path
import numpy as np
import astropy.units as u
from astropy.io import fits
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('astronomy_engine',ROOT/'Resources/Astronomy/engine.py')
e=importlib.util.module_from_spec(spec); sys.modules[spec.name]=e; spec.loader.exec_module(e)
class AstronomyEngineTests(unittest.TestCase):
    def value(self,text): return e.run(text)['value']
    def test_complete_spec_registry_and_examples(self):
        wanted=set((ROOT/'Tests/AstronomyMethods.txt').read_text().split())
        self.assertEqual(wanted,set(e.REGISTRY)); self.assertEqual(len(wanted),234)
        for name,meta in e.REGISTRY.items():
            with self.subTest(method=name):
                result=e.run(meta['example'])
                self.assertTrue(result['ok']); self.assertEqual(name,result['method'])
                self.assertGreaterEqual(len(result['steps']),3)
                for field in ('summary','source','model'): self.assertTrue(result[field],field)
                json.dumps(result,allow_nan=False)
    def test_reference_values_and_units(self):
        checks=[('redshift(500 nm,600 nm)',0.2,1e-12),('lorentz_factor(0.8 c)',5/3,1e-12),
          ('schwarzschild_radius(1 M_sun)',2953.250076,1e-5),('rest_energy(1 kg)',89875517873681764,1e-12),
          ('wien_peak(5772 K)',5.0203949324e-7,1e-9),('julian_date("2000-01-01T12:00:00")',2451545,0),
          ('modified_julian_date("2000-01-01T12:00:00")',51544.5,0),('transit_depth(1 R_earth,1 R_sun)',(u.earthRad.to(u.m)/u.solRad.to(u.m))**2,1e-12),
          ('parallax_distance(100 mas)',10,1e-12),('apparent_magnitude(4.83,100 pc)',9.83,1e-12),
          ('distance_modulus(10 pc)',0,1e-12),('hawking_temperature(1 M_sun)',6.17007383e-8,1e-6)]
        for query,expected,tol in checks:
            with self.subTest(query=query): self.assertTrue(math.isclose(self.value(query),expected,rel_tol=tol,abs_tol=tol*1e-5))
        self.assertAlmostEqual(self.value('surface_gravity(earth)'),9.820302293,places=6)
        self.assertAlmostEqual(self.value('age_of_universe()'),13.786885302,places=6)
        self.assertAlmostEqual(self.value('time_scale_convert("2017-01-01",utc,tt)') or e.run('time_scale_convert("2017-01-01",utc,tt)')['result']['jd'],2457754.500800741,places=8)
    def test_sample_ranges_and_interactive_transit_parameters(self):
        times={'start':-0.2*u.day,'stop':0.2*u.day,'count':301}; orbit={'a':0.05*u.au,'central_mass':'sun'}
        a=e.transit_light_curve('jupiter','sun',orbit,times,{'inclination':90*u.deg,'limb_darkening':[0,0]}).value
        b=e.transit_light_curve(2*e.R('jupiter')*u.m,'sun',orbit,times,{'inclination':90*u.deg,'limb_darkening':[0,0]}).value
        self.assertEqual(len(a['flux']),301)
        self.assertAlmostEqual((1-min(b['flux']))/(1-min(a['flux'])),4,places=8)
        c=e.transit_light_curve('jupiter','sun',orbit,times,{'inclination':80*u.deg,'limb_darkening':[0,0]}).value
        self.assertLess(1-min(c['flux']),1-min(a['flux']))
        self.assertGreater(e.merger_frequency(30*u.M_sun,30*u.M_sun,[0.5,0.5]).value,e.merger_frequency(30*u.M_sun,30*u.M_sun,[0,0]).value)
        self.assertGreater(e.orbit('pluto','sun').value['a'],20*e.AU)
    def test_physical_invariants(self):
        self.assertAlmostEqual(self.value('escape_velocity(earth)')**2,2*e.G*e.M('earth')/e.R('earth'),places=6)
        self.assertAlmostEqual(self.value('redshift(500 nm,doppler_shift(500 nm,30 km/s))'),math.sqrt((1+30000/e.C)/(1-30000/e.C))-1,places=12)
        shifted=e.doppler_shift(500*u.nm,30000*u.m/u.s).value
        self.assertAlmostEqual(e.radial_velocity_from_shift(500*u.nm,shifted).value,30000,places=6)
        self.assertAlmostEqual(self.value('circular_velocity(1 AU,sun)'),self.value('vis_viva(1 AU,1 AU,sun)'),places=9)
        p=self.value('kepler_third_law(1 AU,sun)'); self.assertAlmostEqual(p/86400,365.256898384,places=5)
        orbit={'a':1*u.au,'central_mass':'sun'}; before=e.O(orbit); after=e.propagate_orbit(before,p).value
        self.assertLess(np.linalg.norm(np.array(after['r'])-before['r'])/before['a'],1e-8)
        self.assertAlmostEqual(e.cosmic_age(1).value+e.lookback_time(1).value,e.age_of_universe().value,places=10)
        self.assertAlmostEqual(e.luminosity_distance(1).value/e.angular_diameter_distance(1).value,4,places=10)
        self.assertAlmostEqual(e.isco_radius('sun',0).value/e.photon_sphere_radius('sun').value,2,places=10)
        self.assertAlmostEqual(e.kerr_horizon_radius('sun',0).value.value,e.schwarzschild_radius('sun').value.value,places=10)
        self.assertAlmostEqual(e.signal_to_noise(100,10),10)
        source={'rate':10}; instr={'pixels':10,'read_noise':3}; cond={'sky_rate':1}; t=e.exposure_time(10,source,instr,cond)
        self.assertAlmostEqual(e.telescope_snr(source,instr,t,cond),10,places=10)
        flux=e.magnitude_to_flux(10,1e-8*u.W/u.m**2); self.assertAlmostEqual(e.flux_to_magnitude(flux,1e-8*u.W/u.m**2),10)
    def test_time_coordinate_and_lambert_consistency(self):
        a=e.time_scale_convert('2016-12-31T23:59:60','utc','tai'); self.assertEqual(a['datetime'],'2017-01-01T00:00:36.000')
        p=e.precession_matrix('J2000','J2050'); np.testing.assert_allclose(p@p.T,np.eye(3),atol=1e-12)
        w={'CTYPE1':'RA---TAN','CTYPE2':'DEC--TAN','CRPIX1':1,'CRPIX2':1,'CRVAL1':10,'CRVAL2':20,'CDELT1':-0.001,'CDELT2':0.001}
        pixel=e.world_to_pixel({'ra':10*u.deg,'dec':20*u.deg},w); self.assertAlmostEqual(pixel['x'],0,places=7); self.assertAlmostEqual(pixel['y'],0,places=7)
        sky=e.pixel_to_world([10,20],w); back=e.world_to_pixel(sky,w); self.assertAlmostEqual(back['x'],10,places=7); self.assertAlmostEqual(back['y'],20,places=7)
        dt=e.kepler_third_law(1*u.au,'sun')/4
        transfer=e.lambert_transfer([1*u.au,0,0],[0,1*u.au,0],dt,'sun'); self.assertAlmostEqual(transfer['departure_velocity'][1].value,e.circular_velocity(1*u.au,'sun').value,places=5)
    def test_actual_image_data_and_period_analysis(self):
        with tempfile.TemporaryDirectory() as directory:
            a=np.zeros((21,21)); a[10,10]=100
            f=Path(directory)/'frame.fits'; fits.writeto(f,a)
            csv=Path(directory)/'frame.csv'; np.savetxt(csv,a,delimiter=',')
            curve=Path(directory)/'curve.csv'; curve.write_text('time,flux\n0,1\n1,0.9\n2,1\n')
            imported=e.light_curve(str(curve)+'#time',str(curve)+'#flux').value
            np.testing.assert_allclose(imported['flux'],[1,0.9,1])
            for path in (str(f),str(csv)):
                centroid=e.centroid(path,{'x':5,'y':5,'width':11,'height':11}).value
                self.assertAlmostEqual(centroid['x'],10); self.assertAlmostEqual(centroid['y'],10)
                result=e.aperture_photometry(path,{'x':10,'y':10,'radius':3}).value
                self.assertAlmostEqual(result['flux'],100,places=8)
        rng=np.random.default_rng(7); t=np.sort(rng.uniform(0,100,300)); y=np.sin(2*np.pi*t/7.3)+rng.normal(0,0.02,len(t))
        p=e.periodogram(t,y,np.full(len(t),0.02)).value['best_period'].value
        self.assertLess(abs(p-7.3),0.06)
        expected=10/4*math.sqrt((1/10)**2+(2*0.1/2)**2)
        unc=e.propagate_uncertainty('m/r^2',{'m':{'value':10*u.kg,'sigma':1*u.kg},'r':{'value':2*u.m,'sigma':0.1*u.m}})
        self.assertAlmostEqual(unc.uncertainty.value,expected,places=7)
    def test_invalid_domains_and_safe_grammar(self):
        cases=['lorentz_factor(1 c)','lorentz_factor(2 c)','rest_energy(-1 kg)','wien_peak(0 K)',
          'schwarzschild_radius(10 K)','kerr_horizon_radius(sun,2)','gravitational_time_dilation(sun,1 m)',
          'scale_factor(-1)','parallax_distance(0 mas)','escape_velocity(custom_object)',
          'orbital_period(custom_object)','synodic_period(1 s,2 s,sense=wrong)',
          'roche_limit(earth,moon,model=unknown)','cosmology(model=unknown)',
          'transit_light_curve(earth,sun,earth_orbit,[0 day],geometry={inclination:1000 deg})',
          'rest_energy(__import__("os").system("true"))','rest_energy([x for x in range(10)])',
          'propagate_uncertainty("__import__(1)",{x:{value:1,sigma:0.1}})']
        for text in cases:
            with self.subTest(query=text):
                with self.assertRaises(Exception): e.run(text)
    def test_json_protocol_does_not_die_on_bad_input(self):
        import subprocess
        p=subprocess.run([sys.executable,'-I','-u',str(ROOT/'Resources/Astronomy/engine.py')],input='not json\n'+json.dumps({'text':'redshift(500 nm,600 nm)'})+'\n',text=True,capture_output=True,timeout=20)
        lines=p.stdout.splitlines(); self.assertEqual(len(lines),2); self.assertFalse(json.loads(lines[0])['ok']); self.assertTrue(json.loads(lines[1])['ok'])
if __name__=='__main__': unittest.main(verbosity=2)
