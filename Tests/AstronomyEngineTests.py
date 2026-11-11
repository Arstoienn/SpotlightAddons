"""Acceptance tests for every method Astronomy offers, reference values and input boundaries."""
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
        self.assertEqual(wanted,set(e.REGISTRY)); self.assertEqual(len(wanted),31)
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
          ('wien_peak(5772 K)',5.0203949324e-7,1e-9),('parallax_distance(100 mas)',10,1e-12),
          ('apparent_magnitude(4.83,100 pc)',9.83,1e-12),('absolute_magnitude(9.83,100 pc)',4.83,1e-12)]
        for query,expected,tol in checks:
            with self.subTest(query=query): self.assertTrue(math.isclose(self.value(query),expected,rel_tol=tol,abs_tol=tol*1e-5))
        self.assertAlmostEqual(self.value('surface_gravity(earth)'),9.820302293,places=6)
    def test_physical_invariants(self):
        self.assertAlmostEqual(self.value('escape_velocity(earth)')**2,2*e.G*e.M('earth')/e.R('earth'),places=6)
        p=self.value('kepler_third_law(1 AU,sun)'); self.assertAlmostEqual(p/86400,365.256898384,places=5)
        self.assertGreater(e.orbit('pluto','sun').value['a'],20*e.AU)
        self.assertAlmostEqual(self.value('light_time(earth, sun, at="2026-11-11")'),self.value('distance(earth, sun, at="2026-11-11")')/e.C,places=9)
        self.assertAlmostEqual(self.value('density(earth)'),e.M('earth')/(4*math.pi/3*e.R('earth')**3),places=6)
    def test_invalid_domains_and_safe_grammar(self):
        cases=['lorentz_factor(1 c)','lorentz_factor(2 c)','rest_energy(-1 kg)','wien_peak(0 K)',
          'schwarzschild_radius(10 K)','parallax_distance(0 mas)','escape_velocity(custom_object)',
          'orbital_period(custom_object)','compare(earth,jupiter,colour)',
          'rest_energy(__import__("os").system("true"))','rest_energy([x for x in range(10)])',
          'transit_depth(1 R_earth,1 R_sun)']
        for text in cases:
            with self.subTest(query=text):
                with self.assertRaises(Exception): e.run(text)
    def test_overflow_is_an_answer_not_a_stopped_worker(self):
        import subprocess
        lines=[json.dumps({'text':'parallax_distance(1e-300 mas)'}),json.dumps({'text':'redshift(500 nm,601 nm)'})]
        p=subprocess.run([sys.executable,'-I','-u',str(ROOT/'Resources/Astronomy/engine.py')],input='\n'.join(lines)+'\n',text=True,capture_output=True,timeout=60)
        out=[json.loads(l) for l in p.stdout.splitlines()]
        self.assertEqual(p.returncode,0); self.assertEqual(len(out),2); self.assertTrue(out[1]['ok']); self.assertAlmostEqual(out[1]['value'],0.202,places=9)
    def test_json_protocol_does_not_die_on_bad_input(self):
        import subprocess
        p=subprocess.run([sys.executable,'-I','-u',str(ROOT/'Resources/Astronomy/engine.py')],input='not json\n'+json.dumps({'text':'redshift(500 nm,600 nm)'})+'\n',text=True,capture_output=True,timeout=20)
        lines=p.stdout.splitlines(); self.assertEqual(len(lines),2); self.assertFalse(json.loads(lines[0])['ok']); self.assertTrue(json.loads(lines[1])['ok'])
if __name__=='__main__': unittest.main(verbosity=2)
