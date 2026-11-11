#!/usr/bin/env python3
"""Local, typed astronomy engine. JSON-lines protocol; no network or expression eval."""
import ast, inspect, json, math, os, re, sys, warnings
from dataclasses import dataclass, field
from pathlib import Path
import numpy as np
import astropy.units as u
from astropy import constants as c
from astropy.time import Time
from astropy.coordinates import (SkyCoord, EarthLocation, AltAz, get_body, get_sun,
    get_body_barycentric_posvel, solar_system_ephemeris, GeocentricTrueEcliptic)
from astropy.cosmology import Planck18, Planck15, WMAP9, FlatLambdaCDM
from astropy.utils import iers
from scipy.integrate import solve_ivp, quad
from scipy.optimize import brentq, minimize_scalar, least_squares
from scipy.ndimage import shift as image_shift
import erfa
warnings.filterwarnings('ignore', category=iers.IERSWarning)
iers.conf.auto_download = False
KERNEL=Path(__file__).with_name('de440s.bsp')
if not KERNEL.exists(): KERNEL=Path(__file__).resolve().parents[2]/'build/astronomy-data/de440s.bsp'
EPHEMERIS_NAME='JPL DE440s' if KERNEL.exists() else 'ERFA builtin (reduced precision)'
solar_system_ephemeris.set(str(KERNEL) if KERNEL.exists() else 'builtin')
EPHEMERIS_NOTE=EPHEMERIS_NAME+'; ICRS; planetary barycenters for Mars through Pluto; Earth/Moon centers; bundled IERS orientation. DE440s covers 1849-12-26 to 2150-01-22.'
G=c.G.value; C=c.c.value; SIGMA=c.sigma_sb.value; KB=c.k_B.value; H=c.h.value
MS=c.M_sun.value; RS=c.R_sun.value; LS=c.L_sun.value; AU=u.au.to(u.m); PC=u.pc.to(u.m)
REGISTRY={}
CATEGORIES=['Celestial Bodies','Orbital Mechanics','Spaceflight & Maneuvers','Astronomy Observation',
 'Astronomical Time','Stellar Astrophysics','Black Holes & Relativity','Exoplanets','Cosmology',
 'Galaxies & Interstellar Medium','Spectroscopy & Photometry','Telescope & Optics',
 'Astronomical Data Analysis','Gravitational Waves']
SOURCES=['https://nssdc.gsfc.nasa.gov/planetary/factsheet/', 'https://docs.astropy.org/en/stable/coordinates/solarsystem.html',
 'https://orbital-mechanics.space/', 'https://docs.astropy.org/en/stable/coordinates/',
 'https://docs.astropy.org/en/stable/time/', 'https://docs.astropy.org/en/stable/modeling/physical_models.html',
 'https://arxiv.org/abs/gr-qc/9712019', 'https://lkreidberg.github.io/batman/docs/html/',
 'https://docs.astropy.org/en/stable/cosmology/', 'https://ned.ipac.caltech.edu/level5/',
 'https://docs.astropy.org/en/stable/units/', 'https://www.stsci.edu/hst/instrumentation/reference-data-for-calibration-and-tools',
 'https://photutils.readthedocs.io/en/stable/', 'https://arxiv.org/abs/1310.1528']
@dataclass
class Output:
    value: object
    plot: dict|None=None
    diagram: dict|None=None
    notes: list=field(default_factory=list)
    uncertainty: object=None

def method(cat, formula, example, *, model='', visual='panel', aliases=(), kinds=None):
    def register(fn):
        sig=inspect.signature(fn)
        params=[]
        for n,p in sig.parameters.items():
            kind=(kinds or {}).get(n, {'body':'body','mass':'mass','radius':'radius','temperature':'temperature',
                'central_mass':'mass','star':'star','planet':'body','distance':'distance','wavelength':'wavelength',
                'velocity':'speed','luminosity':'luminosity','observer':'observer','at':'datetime','datetime':'datetime',
                'orbit':'orbit_object','model':'model','body1':'body','body2':'body','primary':'body','secondary':'body','satellite':'body','origin':'body','target':'body','center':'mass','stellar_mass':'mass','planet_mass':'mass','star_mass':'mass','lens_mass':'mass','final_mass':'mass','mass1':'mass','mass2':'mass','black_hole_mass':'mass','initial_mass':'mass','final_mass':'mass','star_radius':'radius','planet_radius':'radius','semi_major_axis':'distance','orbital_distance':'distance','lens_distance':'distance','source_distance':'distance','separation':'distance','radius':'radius','initial_orbit':'orbit_object','target_orbit':'orbit_object','period':'time','duration':'time','proper_time':'time','flight_time':'time','isp':'time','altitude':'angle','inclination':'angle','angle':'angle','frequency':'frequency','time':'data','times':'data','flux':'data','image':'image','images':'image','property':'property'}.get(n,'value'))
            if kind=='distance': kind='length'
            if n in ('emitted_wavelength','observed_wavelength','delta_wavelength','rest_wavelength','line_width'): kind='wavelength'
            if n in ('focal_length','eyepiece_focal_length','aperture','sensor_size','pixel_size','path_length','impact_parameter','r_emitter','r_observer','proper_length','intermediate_radius'): kind='length'
            if n in ('period1','period2','elapsed_time','reference_time','exposure'): kind='time' if n!='reference_time' else 'datetime'
            if n in ('propellant_mass','star_mass','lens_mass'): kind='mass'
            if n in ('mass_flow_rate','accretion_rate'): kind='mass_flow'
            if n in ('sound_speed','rotation_speed','velocity_dispersion'): kind='speed'
            if n=='density': kind='density'
            if n=='gravity': kind='acceleration'
            if n=='thrust': kind='force'
            if n=='name' and fn.__name__=='body': kind='body'
            if n=='body' and fn.__name__ in ('orbit','orbital_elements','state_vector','orbital_period','orbital_velocity'): kind='satellite'
            if kind=='model': kind='cosmology_model' if cat==8 else 'model_'+fn.__name__
            item={'name':n,'kind':kind,'required':p.default is inspect.Parameter.empty}
            if p.default is not inspect.Parameter.empty: item['default']=str(p.default)
            params.append(item)
        REGISTRY[fn.__name__]={'name':fn.__name__,'category':CATEGORIES[cat], 'description':(fn.__doc__ or formula).strip(),
            'parameters':params,'returns':'typed quantity or structured data','visualization':visual,
            'model':model or 'SI constants (CODATA/IAU); inputs treated as exact unless uncertainties supplied',
            'formula':formula,'source':SOURCES[cat], 'aliases':list(aliases),'example':example,
            'priority':'P0' if fn.__name__ in {'mass','radius','density','surface_gravity','escape_velocity','distance','light_time','orbit','orbital_period','orbital_velocity','kepler_third_law','stellar_luminosity','wien_peak','blackbody_spectrum','hr_position','schwarzschild_radius','lorentz_factor','rest_energy','redshift','sky_map'} else 'P1' if cat<9 or cat in (10,11) else 'P2', 'fn':fn}
        return fn
    return register

# Mass kg, mean radius m, sidereal rotation days, obliquity degrees. NASA fact sheets.
BODY_DATA={
 'sun':(MS,RS,25.38,7.25,5772,LS), 'mercury':(3.3011e23,2.4397e6,58.646,0.034,440,None),
 'venus':(4.8675e24,6.0518e6,-243.025,177.36,737,None), 'earth':(5.9722e24,6.371e6,0.99726968,23.4393,288,None),
 'moon':(7.342e22,1.7374e6,27.321661,6.68,250,None), 'mars':(6.4171e23,3.3895e6,1.025957,25.19,210,None),
 'jupiter':(1.89813e27,6.9911e7,0.41354,3.13,165,None), 'saturn':(5.6834e26,5.8232e7,0.444,26.73,134,None),
 'uranus':(8.681e25,2.5362e7,-0.71833,97.77,76,None), 'neptune':(1.02413e26,2.4622e7,0.67125,28.32,72,None),
 'pluto':(1.303e22,1.1883e6,-6.38723,122.53,44,None), 'sirius':(2.063*MS,1.711*RS,5.5,None,9940,25.4*LS),
 'alpha_centauri':(1.0788*MS,1.2175*RS,22,None,5790,1.519*LS), 'proxima':(0.1221*MS,0.1542*RS,82.6,None,3042,0.00155*LS),
 'vega':(2.135*MS,2.362*RS,0.68,None,9602,40.12*LS),
 'betelgeuse':(16.5*MS,764*RS,2100,None,3600,126000*LS), 'sgr_a':(4.3e6*MS,None,None,None,None,None)}
ALIASES={'sol':'sun','terra':'earth','luna':'moon','sirius_a':'sirius','alpha_centauri_a':'alpha_centauri','sagittarius_a':'sgr_a'}
STAR_COORDS={'sirius':(101.287155,-16.716116,2.637),'alpha_centauri':(219.9021,-60.83399,1.347),
 'vega':(279.234735,38.783689,7.68),
 'proxima':(217.4292,-62.6795,1.301),'betelgeuse':(88.79294,7.40706,168)}
def B(x):
    if not isinstance(x,str): raise ValueError('Expected a named body')
    n=ALIASES.get(x.lower().replace(' ','_'),x.lower().replace(' ','_'))
    if n not in BODY_DATA: raise ValueError(f'Unknown body {x}; provide a quantity or explicit orbit for custom objects')
    return n

def Q(x,unit,prop=None):
    if isinstance(x,str) and ALIASES.get(x,x) in BODY_DATA and prop is not None:
        b=B(x); v=BODY_DATA[b][prop]
        if v is None: raise ValueError(f'{b} has no catalogued value for this property')
        x=v*u.Unit(unit)
    if isinstance(x,(int,float,np.number)): x=float(x)*u.Unit(unit)
    if not isinstance(x,u.Quantity): raise ValueError(f'Expected {unit}, received {x}')
    v=x.to_value(unit)
    if not np.all(np.isfinite(v)): raise ValueError('Non-finite input')
    return v

def M(x):
    v=Q(x,'kg',0)
    if v<0: raise ValueError('Mass must be nonnegative')
    return v
def R(x): return positive(Q(x,'m',1),'radius')
def T(x): return positive(Q(x,'K',4),'absolute temperature')
def L(x): return positive(Q(x,'W',5),'luminosity')
def D(x): return Q(x,'m')
def seconds(x): return Q(x,'s')
def angle(x): return Q(x,'rad')
def positive(x,name='quantity'):
    if np.any(np.asarray(x)<=0): raise ValueError(f'{name} must be positive')
    return x

def fraction(x,name='fraction'):
    v=Q(x,'')
    if not 0<=v<=1: raise ValueError(f'{name} must lie in [0,1]')
    return v

def bounded_spin(x):
    x=float(x)
    if abs(x)>1: raise ValueError('Dimensionless spin must lie in [-1,1]')
    return x

def beta(x):
    b=Q(x,'m/s')/C
    if abs(b)>=1: raise ValueError('Speed must be less than c')
    return b

def date(x='J2000',scale='utc'):
    if isinstance(x,Time): return x
    if isinstance(x,dict): return Time(x['value'],scale=x.get('scale',scale),format=x.get('format'))
    if isinstance(x,(float,int)): return Time(x,format='jd',scale=scale)
    return Time(str(x).removesuffix('Z'),scale=scale)

def observer_location(x):
    if isinstance(x,EarthLocation): return x
    if isinstance(x,(list,tuple)): x=dict(zip(['longitude','latitude','height'],x))
    if not isinstance(x,dict): raise ValueError('observer requires {longitude: 121.56 deg, latitude: 25.03 deg, height: 10 m}')
    return EarthLocation.from_geodetic(angle(x.get('longitude',x.get('lon',0)))*u.rad,
        angle(x.get('latitude',x.get('lat',0)))*u.rad,Q(x.get('height',0),'m')*u.m)

def coord(x,at='J2000',observer=None):
    if isinstance(x,SkyCoord): return x
    if isinstance(x,str) and ALIASES.get(x,x) in BODY_DATA:
        b=B(x)
        if b in STAR_COORDS:
            ra,dec,d=STAR_COORDS[b]; return SkyCoord(ra=ra*u.deg,dec=dec*u.deg,distance=d*u.pc)
        return get_body(b,date(at),observer_location(observer) if observer is not None else None)
    if isinstance(x,(list,tuple)): x={'ra':x[0],'dec':x[1]}
    if isinstance(x,dict):
        return SkyCoord(ra=angle(x['ra'])*u.rad,dec=angle(x['dec'])*u.rad,frame=x.get('frame','icrs'),
                        **({'distance':D(x['distance'])*u.m} if 'distance' in x else {}))
    return SkyCoord(x,unit=(u.hourangle,u.deg))

def xyz(body,at='J2000'):
    if B(body) in STAR_COORDS: return coord(body).icrs.cartesian.xyz.to_value(u.m)
    return get_body_barycentric_posvel(B(body),date(at))[0].xyz.to_value(u.m)

def curve(x,y,xlabel,ylabel,label='Model'):
    xx=np.asarray(x,dtype=float); yy=np.asarray(y,dtype=float)
    mask=np.isfinite(xx)&np.isfinite(yy)
    return {'kind':'curve','x':xx[mask].tolist(),'y':yy[mask].tolist(),'xLabel':xlabel,'yLabel':ylabel,'label':label}

def scalar(v,unit=''): return float(v)*u.Unit(unit)

def norm(v): return float(np.linalg.norm(v))

# Typed orbit object, osculating ICRS Cartesian state, SI; no invented custom-object defaults.
def elements(r,v,mu,epoch='J2000'):
    r=np.array(r,dtype=float); v=np.array(v,dtype=float); rn=norm(r); positive(rn)
    hv=np.cross(r,v); hn=positive(norm(hv),'angular momentum'); ev=np.cross(v,hv)/mu-r/rn
    e=norm(ev); energy=np.dot(v,v)/2-mu/rn
    if energy>=0: raise ValueError('This Orbit API requires a bound elliptic orbit (specific energy < 0)')
    a=-mu/(2*energy); inc=math.acos(np.clip(hv[2]/hn,-1,1)); nv=np.cross([0,0,1],hv); nn=norm(nv)
    node=math.atan2(nv[1],nv[0]) if nn>1e-10 else 0
    arg=math.atan2(np.dot(np.cross(nv,ev),hv)/hn,np.dot(nv,ev)) if nn>1e-10 and e>1e-10 else (math.atan2(ev[1],ev[0]) if e>1e-10 else 0)
    nu=math.atan2(np.dot(np.cross(ev,r),hv)/hn,np.dot(ev,r)) if e>1e-10 else math.atan2(r[1],r[0])
    E=2*math.atan2(math.sqrt(1-e)*math.sin(nu/2),math.sqrt(1+e)*math.cos(nu/2))
    return {'type':'Orbit','a':a,'e':e,'i':inc,'raan':node,'argp':arg,'nu':nu,'mean_anomaly':E-e*math.sin(E),
        'mu':mu,'r':r.tolist(),'v':v.tolist(),'epoch':date(epoch).tdb.isot,'frame':'ICRS','time_scale':'TDB'}

def O(x,center=None,at='J2000'):
    if isinstance(x,Output): x=x.value
    if isinstance(x,dict):
        if x.get('type')=='Orbit': return x
        if 'r' in x and 'v' in x: return elements(vec(x['r'],'m'),vec(x['v'],'m/s'),G*M(x['central_mass']),x.get('epoch',at))
        a=positive(D(x['a']),'semi-major axis'); e=fraction(x.get('e',0),'eccentricity')
        if e>=1: raise ValueError('Elliptic orbit requires e < 1')
        mu=G*M(x['central_mass']); inc=angle(x.get('inclination',0)); nu=angle(x.get('true_anomaly',0))
        node=angle(x.get('raan',0)); w=angle(x.get('argp',0)); p=a*(1-e*e)
        r=np.array([p*math.cos(nu)/(1+e*math.cos(nu)),p*math.sin(nu)/(1+e*math.cos(nu)),0])
        v=np.sqrt(mu/p)*np.array([-math.sin(nu),e+math.cos(nu),0])
        def rz(t): return np.array([[math.cos(t),-math.sin(t),0],[math.sin(t),math.cos(t),0],[0,0,1]])
        rx=np.array([[1,0,0],[0,math.cos(inc),-math.sin(inc)],[0,math.sin(inc),math.cos(inc)]])
        rot=rz(node)@rx@rz(w); return elements(rot@r,rot@v,mu,x.get('epoch',at))
    b=B(x); center=B(center or ('earth' if b=='moon' else 'sun'))
    if b==center: raise ValueError('Orbit body and center must differ')
    rb,vb=get_body_barycentric_posvel(b,date(at)); rc,vc=get_body_barycentric_posvel(center,date(at))
    out=elements((rb.xyz-rc.xyz).to_value(u.m),(vb.xyz-vc.xyz).to_value(u.m/u.s),G*(M(b)+M(center)),at)
    out.update(body=b,center=center,source=EPHEMERIS_NOTE)
    return out

def vec(x,unit): return np.array([Q(i,unit) for i in x],dtype=float)

def orbit_plot(o):
    nu=np.linspace(0,2*np.pi,241); rr=o['a']*(1-o['e']**2)/(1+o['e']*np.cos(nu))
    return {'kind':'orbit','x':(rr*np.cos(nu)/AU).tolist(),'y':(rr*np.sin(nu)/AU).tolist(),
        'xLabel':'Orbital plane x / AU','yLabel':'Orbital plane y / AU','label':'Osculating ellipse; focus at (0,0)'}

@method(0,'Catalogue lookup: mass in SI kilograms','mass(earth)',kinds={'body':'mass'})
def mass(body): return M(body)*u.kg
@method(0,'Catalogue lookup: mean volumetric radius','radius(earth)')
def radius(body): return R(body)*u.m
@method(0,'d = 2R','diameter(jupiter)')
def diameter(body): return 2*R(body)*u.m
@method(0,'V = 4πR³/3','volume(earth)')
def volume(body): return 4*np.pi/3*R(body)**3*u.m**3
@method(0,'ρ = 3M/(4πR³)','density(earth)')
def density(body): return M(body)/(4*np.pi/3*R(body)**3)*u.kg/u.m**3
@method(0,'A = 4πR²','surface_area(earth)')
def surface_area(body): return 4*np.pi*R(body)**2*u.m**2
@method(0,'g = GM/R²','surface_gravity(earth)',aliases=['gravity','field_strength'])
def surface_gravity(body,radius=None): return G*positive(M(body))/positive(R(radius if radius is not None else body))**2*u.m/u.s**2
@method(0,'v_esc = √(2GM/R)','escape_velocity(earth)',aliases=['escape_speed','v_esc','earth escape speed'])
def escape_velocity(body,radius=None): return math.sqrt(2*G*positive(M(body))/positive(R(radius if radius is not None else body)))*u.m/u.s
@method(0,'Catalogue sidereal rotation period; negative is retrograde','rotation_period(venus)')
def rotation_period(body):
    p=BODY_DATA[B(body)][2]
    if p is None: raise ValueError('No measured rotation period in the local catalogue')
    return p*u.day
@method(0,'Catalogue axial obliquity','axial_tilt(earth)')
def axial_tilt(body):
    p=BODY_DATA[B(body)][3]
    if p is None: raise ValueError('No measured axial tilt in the local catalogue')
    return p*u.deg
@method(0,'Catalogue bolometric luminosity','luminosity(sun)')
def luminosity(body,temperature=None): return L(body)*u.W if temperature is None else stellar_luminosity(body,temperature)
@method(0,'d = |r₂(t) − r₁(t)|','distance(earth, moon, at="2026-11-11")',model='Simultaneous geometric ICRS positions; JPL DE440s ephemeris; no light-time iteration')
def distance(body1,body2,at='J2000'): return norm(xyz(body2,at)-xyz(body1,at))*u.m
@method(0,'t = d/c','light_time(earth, sun, at="2026-11-11")',model='Geometric distance / c; no Shapiro delay')
def light_time(body1,body2,at='J2000'): return distance(body1,body2,at)/c.c
@method(0,'Property ratio = p₁ / p₂','compare(earth, jupiter, radius)',visual='comparison')
def compare(body1,body2,property='radius'):
    allowed={'mass':mass,'radius':radius,'diameter':diameter,'volume':volume,'density':density,'surface_gravity':surface_gravity,'escape_velocity':escape_velocity,'luminosity':luminosity}
    if property not in allowed: raise ValueError('property must be '+', '.join(allowed))
    a=allowed[property](body1); b=allowed[property](body2)
    return Output({'first':a,'second':b,'ratio':(a/b).value},diagram={'kind':'comparison','labels':[B(body1),B(body2)],'values':[float(a.value),float(b.value)],'property':property,'unit':str(a.unit)})
@method(0,'Catalogue mass, radius, density, rotation, obliquity and luminosity','body(earth)')
def body(name):
    b=B(name); m,r,p,i,t,l=BODY_DATA[b]
    return {k:v for k,v in {'name':b,'mass':m*u.kg,'radius':None if r is None else r*u.m,
        'rotation':None if p is None else p*u.day,'axial_tilt':None if i is None else i*u.deg,
        'temperature':None if t is None else t*u.K,'luminosity':None if l is None else l*u.W}.items() if v is not None}

@method(1,'Osculating Kepler ellipse from r, v: ε = v²/2 − μ/r, a = −μ/2ε','orbit(earth, sun, at="2026-11-11")',visual='orbit',model='Newtonian two-body osculating elements; ICRS/TDB; JPL DE440s ephemeris')
def orbit(body,center=None,at='J2000'):
    o=O(body,center,at); return Output(o,plot=orbit_plot(o))
@method(1,'h = r × v; e = (v × h)/μ − r/|r|','orbital_elements(moon, earth)',visual='orbit')
def orbital_elements(body,center=None,at='J2000'): return orbit(body,center,at)
@method(1,'State = (r_body − r_center, v_body − v_center)','state_vector(earth, sun)',visual='orbit')
def state_vector(body,center=None,at='J2000'):
    o=O(body,center,at); return {'position':np.array(o['r'])*u.m,'velocity':np.array(o['v'])*u.m/u.s,'frame':'ICRS','epoch':o['epoch'],'scale':'TDB'}
@method(1,'P = 2π√(a³/μ)','orbital_period(earth)',aliases=['kepler','period'])
def orbital_period(body,center=None):
    if isinstance(body,u.Quantity): return kepler_third_law(body,center)
    o=O(body,center); return 2*np.pi*np.sqrt(o['a']**3/o['mu'])*u.s
@method(1,'v = |v(t)| from osculating state','orbital_velocity(earth, at="2026-11-11")')
def orbital_velocity(body,at='J2000'): return norm(O(body,at=at)['v'])*u.m/u.s
@method(1,'v_c = √(GM/r)','circular_velocity(1 AU, sun)')
def circular_velocity(radius,central_mass): return np.sqrt(G*positive(M(central_mass))/positive(D(radius)))*u.m/u.s
@method(1,'v² = GM(2/r − 1/a)','vis_viva(1 AU, 1.2 AU, sun)')
def vis_viva(radius,semi_major_axis,central_mass): return np.sqrt(positive(G*M(central_mass)*(2/positive(D(radius))-1/positive(D(semi_major_axis))),'v²'))*u.m/u.s
@method(1,'P² = 4π²a³/(GM)','kepler_third_law(1 AU, sun)')
def kepler_third_law(semi_major_axis,central_mass): return 2*np.pi*np.sqrt(positive(D(semi_major_axis))**3/(G*positive(M(central_mass))))*u.s
@method(1,'a = −μ/(2ε)','semi_major_axis(orbit(earth, sun))')
def semi_major_axis(orbit): return O(orbit)['a']*u.m
@method(1,'e = |(v × h)/μ − r/r|','eccentricity(orbit(earth, sun))')
def eccentricity(orbit): return O(orbit)['e']
@method(1,'i = arccos(h_z/|h|)','inclination(orbit(earth, sun))',model='Inclination to ICRS equator; specify explicit ecliptic orbit for ecliptic inclination')
def inclination(orbit): return O(orbit)['i']*u.rad
@method(1,'r_p = a(1−e)','periapsis(earth_orbit)')
def periapsis(orbit):
    o=O(orbit); return o['a']*(1-o['e'])*u.m
@method(1,'r_a = a(1+e)','apoapsis(earth_orbit)')
def apoapsis(orbit):
    o=O(orbit); return o['a']*(1+o['e'])*u.m
@method(1,'tan(ν/2) = √((1+e)/(1−e)) tan(E/2)','true_anomaly(earth_orbit)')
def true_anomaly(orbit,at=None): return anomaly_at(orbit,at)[0]*u.rad
@method(1,'M = E − e sin E','mean_anomaly(earth_orbit)')
def mean_anomaly(orbit,at=None): return anomaly_at(orbit,at)[1]*u.rad
@method(1,'Solve E − e sin E = M','eccentric_anomaly(earth_orbit)')
def eccentric_anomaly(orbit,at=None): return anomaly_at(orbit,at)[2]*u.rad

def anomaly_at(o,at):
    o=O(o); m=o['mean_anomaly']
    if at is not None: m+=np.sqrt(o['mu']/o['a']**3)*(date(at).tdb-date(o['epoch'],'tdb')).to_value(u.s)
    m=(m+np.pi)%(2*np.pi)-np.pi; e=o['e']; E=brentq(lambda x:x-e*np.sin(x)-m,-2*np.pi,2*np.pi)
    nu=2*np.arctan2(np.sqrt(1+e)*np.sin(E/2),np.sqrt(1-e)*np.cos(E/2)); return nu,m,E
@method(1,'n = √(μ/a³)','mean_motion(earth_orbit)')
def mean_motion(orbit):
    o=O(orbit); return np.sqrt(o['mu']/o['a']**3)*u.rad/u.s
@method(1,'ε = −μ/(2a)','specific_orbital_energy(earth_orbit)')
def specific_orbital_energy(orbit):
    o=O(orbit); return -o['mu']/(2*o['a'])*u.J/u.kg
@method(1,'h = √(μa(1−e²))','specific_angular_momentum(earth_orbit)')
def specific_angular_momentum(orbit):
    o=O(orbit); return np.sqrt(o['mu']*o['a']*(1-o['e']**2))*u.m**2/u.s
@method(1,'1/S = |1/P₁ ∓ 1/P₂|','synodic_period(365.25 day, 686.98 day)')
def synodic_period(period1,period2,sense='prograde'):
    if sense not in ('prograde','retrograde'): raise ValueError('sense must be prograde or retrograde')
    a=positive(seconds(period1)); b=positive(seconds(period2)); f=abs(1/a+(-1 if sense=='prograde' else 1)/b)
    if f==0: return {'period':'infinite','reason':'Equal prograde periods; no relative phase drift'}
    return 1/f*u.s
@method(1,'r_H ≈ a(1−e)(m/(3M))^(1/3)','hill_sphere(earth, sun, 1 AU)')
def hill_sphere(body,primary,semi_major_axis,eccentricity=0): return positive(D(semi_major_axis))*(1-fraction(eccentricity))*np.cbrt(M(body)/(3*positive(M(primary))))*u.m
@method(1,'d = kR₁(ρ₁/ρ₂)^(1/3), k_fluid=2.44, k_rigid=2^(1/3)','roche_limit(earth, moon, model="fluid")',model='Strengthless fluid (2.44) or rigid (1.26) satellite approximation')
def roche_limit(primary,satellite=None,model='fluid'):
    if satellite is None: satellite=primary; primary='earth' if B(satellite)=='moon' else 'sun'
    if model not in ('fluid','rigid'): raise ValueError('model must be fluid or rigid')
    k=2.44 if model=='fluid' else 2**(1/3)
    return k*R(primary)*np.cbrt(density(primary).value/density(satellite).value)*u.m
@method(1,'∂Ω/∂x = 0 in the circular restricted three-body rotating frame','lagrange_points(sun, earth)',visual='potential',model='Circular restricted three-body; positions in separation units, barycentric rotating frame')
def lagrange_points(primary,secondary):
    m1=M(primary); m2=M(secondary); mu=m2/(m1+m2)
    def f(x): return x-(1-mu)*(x+mu)/abs(x+mu)**3-mu*(x-1+mu)/abs(x-1+mu)**3
    eps=1e-10; l1=brentq(f,-mu+eps,1-mu-eps); l2=brentq(f,1-mu+eps,3); l3=brentq(f,-3,-mu-eps)
    points=[[l1,0],[l2,0],[l3,0],[0.5-mu,np.sqrt(3)/2],[0.5-mu,-np.sqrt(3)/2]]
    return Output({'L1':points[0],'L2':points[1],'L3':points[2],'L4':points[3],'L5':points[4],'mass_fraction':mu},diagram={'kind':'potential','points':points,'mu':mu})
@method(1,'r_SOI = a(m/M)^(2/5)','sphere_of_influence(earth, sun)')
def sphere_of_influence(body,primary): return O(body,primary)['a']*(M(body)/M(primary))**0.4*u.m
@method(1,'Integrate r̈ = −μr/r³; DOP853','propagate_orbit(earth_orbit, 30 day)',visual='orbit',model='Newtonian two-body; DOP853 relative tolerance 1e-10')
def propagate_orbit(orbit,duration):
    o=O(orbit); dt=seconds(duration)
    if dt==0: return Output(o,plot=orbit_plot(o))
    sol=solve_ivp(lambda t,y:np.r_[y[3:],-o['mu']*y[:3]/norm(y[:3])**3],(0,dt),o['r']+o['v'],rtol=1e-10,atol=1e-4,method='DOP853',t_eval=np.linspace(0,dt,201))
    if not sol.success: raise ValueError(sol.message)
    v=elements(sol.y[:3,-1],sol.y[3:,-1],o['mu'],(date(o['epoch'],'tdb')+dt*u.s).isot)
    return Output(v,plot=curve(sol.y[0]/AU,sol.y[1]/AU,'ICRS x / AU','ICRS y / AU','Propagated trajectory'))
@method(1,'r̈ᵢ = Σⱼ Gmⱼ(rⱼ−rᵢ)/|rⱼ−rᵢ|³','two_body_simulation(sun, earth, {positions: [[0,0,0],[1 AU,0,0]], velocities: [[0,0,0],[0,29.78 km/s,0]], duration: 365 day})',visual='orbit',model='Newtonian point masses; numerical DOP853; collision singularities rejected')
def two_body_simulation(body1,body2,initial_state): return n_body_simulation([body1,body2],initial_state,initial_state.get('duration',86400))
@method(1,'Newtonian N-body integration; report relative energy drift','n_body_simulation([sun,earth], {positions:[[0,0,0],[1 AU,0,0]],velocities:[[0,0,0],[0,29.78 km/s,0]]}, 365 day)',visual='orbit',model='Newtonian point masses; no relativity, tides or physical collisions')
def n_body_simulation(bodies,initial_states,duration):
    n=len(bodies)
    if not 2<=n<=32: raise ValueError('N-body requires 2–32 bodies')
    masses=np.array([positive(M(x)) for x in bodies]); pos=np.array([vec(x,'m') for x in initial_states['positions']]); vel=np.array([vec(x,'m/s') for x in initial_states['velocities']]); dt=positive(seconds(duration))
    if pos.shape!=(n,3) or vel.shape!=(n,3): raise ValueError('positions and velocities must each have shape N×3')
    def rhs(t,y):
        p=y[:3*n].reshape(n,3); v=y[3*n:].reshape(n,3); d=p[None,:,:]-p[:,None,:]; dist=np.linalg.norm(d,axis=2); np.fill_diagonal(dist,np.inf)
        if np.min(dist)<1: raise ValueError('Point masses approach within 1 m; collision model required')
        return np.r_[v.ravel(),(G*np.sum(d*masses[None,:,None]/dist[:,:,None]**3,axis=1)).ravel()]
    y0=np.r_[pos.ravel(),vel.ravel()]; sol=solve_ivp(rhs,(0,dt),y0,t_eval=np.linspace(0,dt,201),method='DOP853',rtol=1e-10,atol=1e-4)
    if not sol.success: raise ValueError(sol.message)
    def energy(y):
        p=y[:3*n].reshape(n,3); v=y[3*n:].reshape(n,3)
        return np.sum(masses*np.sum(v*v,axis=1))/2-sum(G*masses[i]*masses[j]/norm(p[i]-p[j]) for i in range(n) for j in range(i))
    drift=(energy(sol.y[:,-1])-energy(y0))/max(abs(energy(y0)),1)
    return Output({'times':sol.t*u.s,'positions':sol.y[:3*n].T.reshape(-1,n,3)*u.m,'velocities':sol.y[3*n:].T.reshape(-1,n,3)*u.m/u.s,'relative_energy_drift':drift},plot=curve(sol.y[3]/AU,sol.y[4]/AU,'ICRS x / AU','ICRS y / AU','Body 2 trajectory'))
# Transfers: ideal Keplerian maneuvers. Structured inputs retain center μ.
def transfer_orbits(a,b):
    a=O(a); b=O(b)
    if not np.isclose(a['mu'],b['mu'],rtol=1e-3): raise ValueError('Transfer orbits must have the same central mass')
    if a['e']>1e-3 or b['e']>1e-3: raise ValueError('Ideal transfer requires circular orbits (e ≤ 0.001); supply explicit circular Orbit objects')
    if abs(a['i']-b['i'])>1e-6: raise ValueError('Ideal transfer requires coplanar orbits')
    return a['a'],b['a'],a['mu']
@method(2,'Δv₁ = √(μ/r₁)(√(2r₂/(r₁+r₂))−1); Δv₂ = √(μ/r₂)(1−√(2r₁/(r₁+r₂)))','hohmann_transfer({a:1 AU,central_mass:sun},{a:1.524 AU,central_mass:sun})',visual='transfer',model='Two coplanar circular orbits; impulsive burns; no launch or capture costs')
def hohmann_transfer(initial_orbit,target_orbit):
    a,b,mu=transfer_orbits(initial_orbit,target_orbit); dv1=np.sqrt(mu/a)*(np.sqrt(2*b/(a+b))-1); dv2=np.sqrt(mu/b)*(1-np.sqrt(2*a/(a+b))); t=np.pi*np.sqrt(((a+b)/2)**3/mu)
    theta=np.linspace(0,np.pi,181); e=abs(b-a)/(a+b); rr=((a+b)/2)*(1-e*e)/(1+e*np.cos(theta))
    return Output({'type':'Maneuver','delta_v':(abs(dv1)+abs(dv2))*u.m/u.s,'burns':np.array([dv1,dv2])*u.m/u.s,'transfer_time':t*u.s},plot=curve(rr*np.cos(theta)/AU,rr*np.sin(theta)/AU,'Transfer plane x / AU','Transfer plane y / AU','Hohmann transfer'))
@method(2,'Sum three vis-viva burns across two transfer ellipses','bielliptic_transfer({a:1 AU,central_mass:sun},{a:2 AU,central_mass:sun},10 AU)',visual='transfer',model='Coplanar circular endpoints; intermediate radius above both endpoints')
def bielliptic_transfer(initial_orbit,target_orbit,intermediate_radius):
    a,b,mu=transfer_orbits(initial_orbit,target_orbit); r=positive(D(intermediate_radius))
    if r<=max(a,b): raise ValueError('Intermediate radius must exceed both orbit radii')
    v=lambda rr,aa:np.sqrt(mu*(2/rr-1/aa)); a1=(a+r)/2; a2=(b+r)/2
    dvs=[v(a,a1)-np.sqrt(mu/a),v(r,a2)-v(r,a1),np.sqrt(mu/b)-v(b,a2)]
    return {'type':'Maneuver','burns':np.array(dvs)*u.m/u.s,'delta_v':sum(abs(d) for d in dvs)*u.m/u.s,'transfer_time':np.pi*(np.sqrt(a1**3/mu)+np.sqrt(a2**3/mu))*u.s}
@method(2,'Universal-variable Lambert equation; Lagrange f,g coefficients','lambert_transfer([1 AU,0,0],[0,1 AU,0],90 day,sun)',model='Zero-revolution, prograde short-way transfer; positions relative to common center',visual='transfer')
def lambert_transfer(position1,position2,flight_time,central_mass):
    r1=vec(position1,'m'); r2=vec(position2,'m'); n1=positive(norm(r1)); n2=positive(norm(r2)); dt=positive(seconds(flight_time)); mu=G*positive(M(central_mass)); ct=np.clip(np.dot(r1,r2)/n1/n2,-1,1); st=np.sqrt(1-ct*ct)
    if st<1e-8: raise ValueError('Collinear endpoints are singular for this Lambert solver')
    A=st*np.sqrt(n1*n2/(1-ct))
    def stump(z):
        if abs(z)<1e-7: return 0.5-z/24,1/6-z/120
        if z>0:
            q=np.sqrt(z); return (1-np.cos(q))/z,(q-np.sin(q))/q**3
        q=np.sqrt(-z); return (np.cosh(q)-1)/(-z),(np.sinh(q)-q)/q**3
    def terms(z):
        cc,ss=stump(z); y=n1+n2+A*(z*ss-1)/np.sqrt(cc)
        if y<0: return None
        return (y/cc)**1.5*ss+A*np.sqrt(y),y
    zs=np.linspace(-4*np.pi*np.pi+1e-4,4*np.pi*np.pi-1e-4,1001); last=None; root=None
    for z in zs:
        val=terms(z)
        if val is None: continue
        f=val[0]-np.sqrt(mu)*dt
        if last and f*last[1]<=0:
            root=brentq(lambda zz:terms(zz)[0]-np.sqrt(mu)*dt,last[0],z); break
        last=(z,f)
    if root is None: raise ValueError('No zero-revolution short-way solution bracketed')
    _,y=terms(root); f=1-y/n1; g=A*np.sqrt(y/mu); gd=1-y/n2
    return {'type':'Maneuver','departure_velocity':(r2-f*r1)/g*u.m/u.s,'arrival_velocity':(gd*r2-r1)/g*u.m/u.s,'transfer_time':dt*u.s,'note':'delta_v requires initial and target velocities'}
@method(2,'Δv = Σ|Δvᵢ|','delta_v(hohmann_transfer({a:1 AU,central_mass:sun},{a:2 AU,central_mass:sun}))')
def delta_v(maneuver):
    if isinstance(maneuver,Output): maneuver=maneuver.value
    if 'delta_v' not in maneuver: raise ValueError('Maneuver needs burn vectors or endpoint velocities to determine delta-v')
    return maneuver['delta_v']
@method(2,'Transfer duration from maneuver object','transfer_time(hohmann_transfer({a:1 AU,central_mass:sun},{a:2 AU,central_mass:sun}))')
def transfer_time(maneuver): return (maneuver.value if isinstance(maneuver,Output) else maneuver)['transfer_time']
@method(2,'Δv = 2v sin(θ/2)','plane_change_delta_v(7.8 km/s,30 deg)')
def plane_change_delta_v(velocity,angle): return 2*positive(Q(velocity,'m/s'))*abs(np.sin(Q(angle,'rad')/2))*u.m/u.s
@method(2,'Δv = I_sp g₀ ln(m₀/m_f)','rocket_equation(1000 kg,500 kg,300 s)')
def rocket_equation(initial_mass,final_mass,isp):
    a=positive(M(initial_mass)); b=positive(M(final_mass))
    if b>a: raise ValueError('Final mass must not exceed initial mass')
    return positive(seconds(isp))*c.g0*np.log(a/b)
@method(2,'m₀/m_f = exp(Δv/(I_sp g₀))','mass_ratio(3 km/s,300 s)')
def mass_ratio(delta_v,isp): return np.exp(Q(delta_v,'m/s')/(positive(seconds(isp))*c.g0.value))
@method(2,'a = F/m','thrust_acceleration(100 N,1000 kg)')
def thrust_acceleration(thrust,mass): return Q(thrust,'N')/positive(M(mass))*u.m/u.s**2
@method(2,'t = m_propellant / ṁ','burn_time(100 kg,2 kg/s)')
def burn_time(propellant_mass,mass_flow_rate): return positive(M(propellant_mass))/positive(Q(mass_flow_rate,'kg/s'))*u.s
@method(2,'Find minima of wrapped heliocentric phase error to Hohmann departure phase','launch_window(earth,mars,["2026-01-01","2028-01-01"])',model='Coplanar circular Hohmann phase estimate using JPL DE440s heliocentric positions; windows are not launch solutions',visual='curve')
def launch_window(origin,target,date_range,model='hohmann'):
    if model!='hohmann': raise ValueError('Supported model: hohmann')
    start,end=datespan(date_range); a=O(origin)['a']; b=O(target)['a']; mu=G*MS; t=np.pi*np.sqrt(((a+b)/2)**3/mu); desired=np.pi-np.sqrt(mu/b**3)*t
    grid=np.linspace(start.jd,end.jd,401)
    def err(jd):
        r1=xyz(origin,jd)-xyz('sun',jd); r2=xyz(target,jd)-xyz('sun',jd)
        q=np.arctan2(np.cross(r1,r2)[2],np.dot(r1,r2))-desired; return np.arctan2(np.sin(q),np.cos(q))
    ys=np.array([err(x) for x in grid]); roots=[]
    for a,b,f,g in zip(grid[:-1],grid[1:],ys[:-1],ys[1:]):
        if f*g<0 and abs(f-g)<np.pi: roots.append(date(brentq(err,a,b)).isot)
    return Output({'departure_estimates_UTC':roots,'transfer_time':t*u.s,'required_phase':desired*u.rad},plot=curve(grid-start.jd,ys*180/np.pi,'Days since '+start.isot,'Phase error / deg'))
@method(2,'φ = atan2((r₁ × r₂)_z, r₁·r₂)','phase_angle(earth,mars,sun,at="2026-11-11")')
def phase_angle(body1,body2,center='sun',at='J2000'):
    r1=xyz(body1,at)-xyz(center,at); r2=xyz(body2,at)-xyz(center,at)
    return np.arctan2(np.cross(r1,r2)[2],np.dot(r1,r2))*u.rad
@method(2,'δ = 2 asin(1/(1+r_p v∞²/μ)); rotate incoming v∞ in specified flyby plane','gravity_assist({velocity:[15 km/s,0,0],planet_velocity:[0,13 km/s,0]},jupiter,{periapsis:1e8 m,normal:[0,0,1]})',model='Unpowered hyperbolic patched-conic flyby; prescribed encounter-plane normal')
def gravity_assist(encounter_state,planet,flyby_parameters):
    vp=vec(encounter_state.get('planet_velocity',[0,0,0]),'m/s'); vin=vec(encounter_state['velocity'],'m/s')-vp; speed=positive(norm(vin)); rp=positive(D(flyby_parameters['periapsis']))
    if rp<R(planet): raise ValueError('Flyby periapsis is inside the planet')
    n=np.array(flyby_parameters.get('normal',[0,0,1]),float); n/=positive(norm(n))
    if abs(np.dot(n,vin)/speed)>1e-5: raise ValueError('Flyby normal must be perpendicular to incoming relative velocity')
    delta=2*np.arcsin(1/(1+rp*speed**2/(G*M(planet)))); vout=vin*np.cos(delta)+np.cross(n,vin)*np.sin(delta)+n*np.dot(n,vin)*(1-np.cos(delta))
    return {'outgoing_velocity':(vout+vp)*u.m/u.s,'turn_angle':delta*u.rad,'v_infinity':speed*u.m/u.s}
@method(2,'Sequential planet-centered hyperbolic flyby maps','patched_conics({velocity:[15 km/s,0,0]},[{planet:jupiter,planet_velocity:[0,0,0],periapsis:1e8 m,normal:[0,0,1]}])',model='Prescribed encounter states; instantaneous sphere-of-influence patches; no ephemeris optimization')
def patched_conics(trajectory,encounters):
    v=trajectory['velocity']; results=[]
    for e in encounters:
        out=gravity_assist({'velocity':v,'planet_velocity':e.get('planet_velocity',[0,0,0])},e['planet'],e); results.append(out); v=out['outgoing_velocity']
    return {'encounters':results,'outgoing_velocity':v}

# Observing: all times UTC unless explicit Time object, angles are quantities (bare = radians).
@method(3,'Astropy get_body → apparent GCRS → topocentric AltAz','position(moon,"2026-11-11T12:00:00",{longitude:121.56 deg,latitude:25.03 deg})',model='JPL DE440s ephemeris; GCRS apparent RA/Dec and unrefracted AltAz; bundled IERS Earth orientation')
def position(body,at,observer):
    q=coord(body,at,observer); aa=q.transform_to(AltAz(obstime=date(at),location=observer_location(observer),pressure=0*u.hPa))
    return {'ra':q.ra,'dec':q.dec,'altitude':aa.alt,'azimuth':aa.az,'at_UTC':date(at).utc.isot,'equatorial_frame':q.frame.name,'horizontal_frame':'AltAz, vacuum'}
@method(3,'Apparent equatorial right ascension and declination','ra_dec(moon,"2026-11-11",{longitude:0 deg,latitude:51 deg})')
def ra_dec(body,at,observer):
    p=position(body,at,observer); return {k:p[k] for k in ('ra','dec','at_UTC','equatorial_frame')}
@method(3,'Topocentric horizontal altitude and azimuth','alt_az(moon,"2026-11-11",{longitude:121 deg,latitude:25 deg})',visual='sky')
def alt_az(body,at,observer):
    p=position(body,at,observer); return Output(p,diagram={'kind':'sky','points':[{'label':str(body),'az':p['azimuth'].to_value(u.rad),'alt':p['altitude'].to_value(u.rad)}]})
@method(3,'cos θ = sin δ₁ sin δ₂ + cos δ₁ cos δ₂ cos(α₁−α₂)','angular_separation(sun,moon,"2026-11-11",{longitude:0 deg,latitude:0 deg})')
def angular_separation(body1,body2,at,observer): return coord(body1,at,observer).separation(coord(body2,at,observer))
@method(3,'θ = 2 asin(R/d)','angular_size(moon,{longitude:0 deg,latitude:0 deg},"2026-11-11")')
def angular_size(body,observer,at): return 2*np.arcsin(R(body)/coord(body,at,observer).distance.to_value(u.m))*u.rad

def datespan(x):
    a,b=map(date,x)
    if b<=a: raise ValueError('Date range end must follow start')
    if (b-a).to_value(u.day)>36525: raise ValueError('Search interval is limited to 100 years')
    return a,b

def events_alt(body,day,observer):
    t=date(day); grid=np.linspace(t.jd,t.jd+1,145); loc=observer_location(observer)
    def alt(jd): return coord(body,jd,observer).transform_to(AltAz(obstime=date(jd),location=loc,pressure=0*u.hPa)).alt.deg
    ys=np.array([alt(j) for j in grid]); rise=[]; setting=[]
    for a,b,f,g in zip(grid[:-1],grid[1:],ys[:-1],ys[1:]):
        if f*g<0: (rise if g>f else setting).append(date(brentq(alt,a,b,xtol=1e-9)).isot)
    i=int(np.argmax(ys)); left=grid[max(0,i-1)]; right=grid[min(len(grid)-1,i+1)]; tr=minimize_scalar(lambda j:-alt(j),bounds=(left,right),method='bounded',options={'xatol':1e-9})
    return {'rise_UTC':rise,'set_UTC':setting,'upper_transit_UTC':date(tr.x).isot,'status':'circumpolar above horizon' if np.all(ys>0) else 'always below horizon' if np.all(ys<0) else 'horizon crossings','peak_altitude':(-tr.fun)*u.deg}
@method(3,'Bracket and solve vacuum center altitude = 0° across one UTC day','rise_set(moon,"2026-11-11",{longitude:121 deg,latitude:25 deg})',model='Geometric body center; no refraction, horizon dip, limb radius or terrain')
def rise_set(body,date,observer): return events_alt(body,date,observer)
@method(3,'Maximize altitude in the specified UTC day','transit_time(sun,"2026-11-11",{longitude:121 deg,latitude:25 deg})')
def transit_time(body,date,observer): return events_alt(body,date,observer)
@method(3,'H = local apparent sidereal time − topocentric CIRS right ascension','hour_angle(moon,"2026-11-11",{longitude:121 deg,latitude:25 deg})')
def hour_angle(body,at,observer):
    from astropy.coordinates import CIRS
    t=date(at); loc=observer_location(observer); q=coord(body,at,observer).transform_to(CIRS(obstime=t,location=loc))
    return (t.sidereal_time('apparent',longitude=loc.lon)-q.ra).wrap_at(180*u.deg)
@method(3,'X = 1/[cos z + 0.50572(96.07995−z_deg)^−1.6364]','airmass(moon,"2026-11-11",{longitude:121 deg,latitude:25 deg})',model='Kasten–Young 1989 optical relative airmass; vacuum altitude; above horizon only')
def airmass(body,at,observer):
    alt=position(body,at,observer)['altitude'].deg
    if alt<=0: raise ValueError('Airmass undefined below horizon')
    z=90-alt; return 1/(np.cos(np.deg2rad(z))+0.50572*(96.07995-z)**-1.6364)
@method(3,'Project topocentric AltAz positions onto the horizon dome','sky_map({longitude:121.56 deg,latitude:25.03 deg},"2026-11-11T12:00:00")',visual='sky',model='Builtin solar-system ephemeris and five fixed ICRS reference stars; no comprehensive star catalogue')
def sky_map(observer,at):
    points=[]
    for b in ['sun','moon','mercury','venus','mars','jupiter','saturn','uranus','neptune']+list(STAR_COORDS):
        p=position(b,at,observer); points.append({'label':b,'az':p['azimuth'].rad,'alt':p['altitude'].rad})
    return Output({'at_UTC':date(at).isot,'frame':'Topocentric vacuum AltAz','objects':points},diagram={'kind':'sky','points':points})

def separation_events(b1,b2,span,opposite=False):
    start,end=datespan(span); grid=np.linspace(start.jd,end.jd,min(1200,max(40,int((end-start).jd*4))))
    def f(j):
        q=coord(b1,j).separation(coord(b2,j)).rad; return np.pi-q if opposite else q
    yy=[f(j) for j in grid]; events=[]
    for i in range(1,len(grid)-1):
        if yy[i]<yy[i-1] and yy[i]<yy[i+1]:
            z=minimize_scalar(f,bounds=(grid[i-1],grid[i+1]),method='bounded',options={'xatol':1e-8}); events.append({'at_UTC':date(z.x).isot,'separation':((np.pi-z.fun) if opposite else z.fun)*u.rad})
    return events
@method(3,'Minimize apparent angular separation over date range','conjunction(venus,jupiter,["2026-01-01","2027-01-01"])',model='Geocentric apparent closest approaches, not exact ecliptic-longitude conjunctions')
def conjunction(body1,body2,date_range): return separation_events(body1,body2,date_range)
@method(3,'Maximize angular separation from Sun','opposition(mars,["2026-01-01","2028-01-01"])',model='Geocentric maximum solar separation; not exact ecliptic-longitude opposition')
def opposition(body,date_range): return separation_events(body,'sun',date_range,True)
@method(3,'Elongation = angular separation from Sun','elongation(venus,"2026-11-11",{longitude:0 deg,latitude:0 deg})')
def elongation(body,at,observer): return angular_separation(body,'sun',at,observer)
@method(3,'Geocentric ecliptic longitude difference (Moon − Sun) mod 360°','moon_phase("2026-11-11")')
def moon_phase(at):
    frame=GeocentricTrueEcliptic(equinox=date(at)); m=coord('moon',at).transform_to(frame); s=coord('sun',at).transform_to(frame)
    return (m.lon-s.lon).wrap_at(360*u.deg)
@method(3,'Illuminated fraction k = (1 + cos phase_angle_at_moon)/2','moon_illumination("2026-11-11")')
def moon_illumination(at):
    sm=xyz('sun',at)-xyz('moon',at); em=xyz('earth',at)-xyz('moon',at)
    return (1+np.dot(sm,em)/norm(sm)/norm(em))/2
@method(3,'Compare topocentric Sun–Moon separation with their angular radii','solar_eclipse(["2026-08-12","2026-08-13"],{longitude:-20 deg,latitude:65 deg})',model='Geometric candidate screening with JPL DE440s ephemeris; no Besselian elements, limb profile, ΔT prediction or certified contact times')
def solar_eclipse(date_range,observer):
    start,end=datespan(date_range); grid=np.linspace(start.jd,end.jd,min(2000,max(30,int((end-start).jd*96))))
    def f(j): return angular_separation('sun','moon',j,observer).rad
    ys=[f(j) for j in grid]; candidates=[]
    for i in range(1,len(grid)-1):
        if ys[i]<ys[i-1] and ys[i]<ys[i+1]:
            z=minimize_scalar(f,bounds=(grid[i-1],grid[i+1]),method='bounded',options={'xatol':1e-9}); sr=angular_size('sun',observer,z.x).value/2; mr=angular_size('moon',observer,z.x).value/2
            if z.fun<sr+mr:
                above=position('sun',z.x,observer)['altitude'].deg>0
                candidates.append({'maximum_UTC':date(z.x).isot,'separation':z.fun*u.rad,'type':'partial' if z.fun>abs(sr-mr) else 'total' if mr>sr else 'annular','above_horizon':above})
    return {'candidates':candidates,'precision':'screening only; verify contacts with JPL/Besselian ephemerides'}
@method(3,'Moon distance from anti-solar Earth shadow axis versus umbral radius','lunar_eclipse(["2026-03-03","2026-03-04"],{longitude:121 deg,latitude:25 deg})',model='Spherical Earth geometric umbra/penumbra screening; no atmospheric enlargement; approximate ephemerides')
def lunar_eclipse(date_range,observer):
    start,end=datespan(date_range); grid=np.linspace(start.jd,end.jd,min(2000,max(30,int((end-start).jd*96))))
    def shadow(j):
        es=xyz('earth',j)-xyz('sun',j); em=xyz('moon',j)-xyz('earth',j); axis=es/norm(es); along=np.dot(em,axis); perp=norm(em-along*axis)
        return perp,along,R('earth')-along*(R('sun')-R('earth'))/norm(es),R('earth')+along*(R('sun')+R('earth'))/norm(es)
    vals=[shadow(j)[0] if shadow(j)[1]>0 else 1e20 for j in grid]; out=[]
    for i in range(1,len(grid)-1):
        if vals[i]<vals[i-1] and vals[i]<vals[i+1]:
            z=minimize_scalar(lambda j:shadow(j)[0],bounds=(grid[i-1],grid[i+1]),method='bounded',options={'xatol':1e-9}); p,along,umb,pen=shadow(z.x)
            if along>0 and p<pen+R('moon'): out.append({'maximum_UTC':date(z.x).isot,'type':'total' if p+R('moon')<umb else 'partial' if p-R('moon')<umb else 'penumbral','above_horizon':position('moon',z.x,observer)['altitude'].deg>0})
    return {'candidates':out,'precision':'geometric screening only'}
@method(3,'Astropy coordinate frame transform','coordinate_transform({ra:266.4 deg,dec:-28.94 deg},icrs,galactic)',model='Astropy/ERFA frame transforms; time required for time-dependent frames')
def coordinate_transform(coordinates,from_frame,to_frame,at='J2000'):
    if from_frame=='altaz':
        if 'observer' not in coordinates: raise ValueError('AltAz coordinates require an observer object')
        q=SkyCoord(az=angle(coordinates['az'])*u.rad,alt=angle(coordinates['alt'])*u.rad,frame=AltAz(obstime=date(at),location=observer_location(coordinates['observer'])))
    elif from_frame in ('galactic','barycentrictrueecliptic','geocentrictrueecliptic'):
        keys=('l','b') if from_frame=='galactic' else ('lon','lat'); q=SkyCoord(**{keys[0]:angle(coordinates[keys[0]])*u.rad,keys[1]:angle(coordinates[keys[1]])*u.rad},frame=from_frame)
    else: q=coord(dict(coordinates,frame=from_frame))
    frame=to_frame
    if to_frame=='geocentrictrueecliptic': frame=GeocentricTrueEcliptic(equinox=date(at))
    if to_frame=='altaz':
        if 'observer' not in coordinates: raise ValueError('AltAz output requires observer in coordinates object')
        frame=AltAz(obstime=date(at),location=observer_location(coordinates['observer']))
    v=q.transform_to(frame); return {'longitude':v.spherical.lon,'latitude':v.spherical.lat,'frame':v.frame.name,'at':date(at).isot}

@method(3,'Propagate ICRS position with proper motion and optional radial velocity','proper_motion({ra:10 deg,dec:20 deg},{pm_ra_cosdec:100 mas/yr,pm_dec:50 mas/yr},10 yr)')
def proper_motion(position,motion,elapsed_time):
    kw={'ra':angle(position['ra'])*u.rad,'dec':angle(position['dec'])*u.rad,'pm_ra_cosdec':Q(motion['pm_ra_cosdec'],'rad/s')*u.rad/u.s,'pm_dec':Q(motion['pm_dec'],'rad/s')*u.rad/u.s,'obstime':date('J2000')}
    if 'distance' in position: kw['distance']=D(position['distance'])*u.m
    if 'radial_velocity' in motion: kw['radial_velocity']=Q(motion['radial_velocity'],'m/s')*u.m/u.s
    q=SkyCoord(**kw).apply_space_motion(dt=seconds(elapsed_time)*u.s); return {'ra':q.ra,'dec':q.dec}
@method(3,'d_pc = 1/p_arcsec','parallax_distance(100 mas)',kinds={'parallax':'parallax'})
def parallax_distance(parallax):
    if isinstance(parallax,str) and B(parallax) in STAR_COORDS: return STAR_COORDS[B(parallax)][2]*u.pc
    return (1/positive(Q(parallax,'arcsec')))*u.pc

@method(4,'UTC Julian Date using Astropy Time','julian_date("2000-01-01T12:00:00")')
def julian_date(datetime): return date(datetime).jd
@method(4,'MJD = JD − 2400000.5','modified_julian_date("2000-01-01T12:00:00")')
def modified_julian_date(datetime): return date(datetime).mjd
@method(4,'T = (JD_TT − 2451545.0)/36525','julian_centuries("2000-01-01T12:00:00")')
def julian_centuries(datetime): return (date(datetime).tt.jd-2451545)/36525
@method(4,'IAU 2006 apparent sidereal time at longitude','sidereal_time("2026-11-11T12:00:00",121 deg)',model='ERFA IAU 2006/2000A; UT1 from bundled IERS')
def sidereal_time(datetime,longitude): return date(datetime).sidereal_time('apparent',longitude=angle(longitude)*u.rad,model='IAU2006A')
@method(4,'Local apparent sidereal time from geodetic longitude','local_sidereal_time("2026-11-11",{longitude:121 deg,latitude:25 deg})')
def local_sidereal_time(datetime,observer): return sidereal_time(datetime,observer_location(observer).lon)
@method(4,'ERFA conversion between UTC, TAI, TT, TDB, UT1, TCG and TCB','time_scale_convert("2017-01-01T00:00:00",utc,tt)',model='Astropy Time leap-second-aware conversions; TDB geocenter unless observer specified separately')
def time_scale_convert(datetime,from_scale,to_scale):
    if from_scale not in Time.SCALES or to_scale not in Time.SCALES: raise ValueError('Unknown time scale')
    t=getattr(date(datetime,from_scale),to_scale); return {'datetime':t.isot,'scale':t.scale,'jd':t.jd}
@method(4,'BJD_TDB = JD_TDB + r_observer,bary · n/c','barycentric_julian_date("2026-11-11",sirius,{longitude:121 deg,latitude:25 deg})')
def barycentric_julian_date(datetime,target,observer):
    t=Time(date(datetime),location=observer_location(observer)); return {'jd':(t.tdb+t.light_travel_time(coord(target),kind='barycentric')).jd,'scale':'TDB','reference':'Solar-system barycenter'}
@method(4,'HJD_TDB = JD_TDB + r_observer,helio · n/c','heliocentric_julian_date("2026-11-11",sirius,{longitude:121 deg,latitude:25 deg})')
def heliocentric_julian_date(datetime,target,observer):
    t=Time(date(datetime),location=observer_location(observer)); return {'jd':(t.tdb+t.light_travel_time(coord(target),kind='heliocentric')).jd,'scale':'TDB','reference':'Heliocenter'}
@method(4,'P(epoch₂) P(epoch₁)ᵀ, IAU 2006 precession-bias matrices','precession_matrix("J2000","J2050")')
def precession_matrix(epoch1,epoch2):
    a=date(epoch1).tt; b=date(epoch2).tt; return erfa.pmat06(b.jd1,b.jd2)@erfa.pmat06(a.jd1,a.jd2).T
@method(4,'IAU 2000A nutation with IAU 2006 adjustments','nutation_angles("2026-11-11")')
def nutation_angles(datetime):
    t=date(datetime).tt; p,e=erfa.nut06a(t.jd1,t.jd2); return {'delta_psi':p*u.rad,'delta_epsilon':e*u.rad}
@method(4,'R_arcmin = 1.02/tan(h+10.3/(h+5.11)) × (P/1010) × 283/(273+T_C)','atmospheric_refraction(30 deg,{pressure:1010 hPa,temperature:283.15 K})',model='Saemundsson optical approximation; geometric altitude > −1°; weather dependent')
def atmospheric_refraction(altitude,conditions):
    alt=Q(altitude,'deg')
    if not -1<alt<=90: raise ValueError('Refraction approximation requires −1° < altitude ≤ 90°')
    return max(0,1.02/np.tan(np.deg2rad(alt+10.3/(alt+5.11))))*(Q(conditions.get('pressure',1010*u.hPa),'hPa')/1010)*(283/T(conditions.get('temperature',283.15*u.K)))*u.arcmin
@method(4,'Astropy barycentric radial-velocity correction','barycentric_velocity_correction(sirius,"2026-11-11",{longitude:121 deg,latitude:25 deg})',model='Optical-convention barycentric correction; JPL DE440s ephemeris and IERS')
def barycentric_velocity_correction(target,datetime,observer): return coord(target).radial_velocity_correction(obstime=date(datetime),location=observer_location(observer)).to(u.m/u.s)
@method(5,'L = 4πR²σT⁴','stellar_luminosity(1 R_sun,5772 K)')
def stellar_luminosity(radius,temperature): return 4*np.pi*positive(R(radius))**2*SIGMA*positive(T(temperature))**4*u.W
@method(5,'R = √(L/(4πσT⁴))','stellar_radius(1 L_sun,5772 K)')
def stellar_radius(luminosity,temperature): return np.sqrt(positive(L(luminosity))/(4*np.pi*SIGMA*positive(T(temperature))**4))*u.m
@method(5,'T_eff = (L/(4πσR²))^(1/4)','effective_temperature(1 L_sun,1 R_sun)')
def effective_temperature(luminosity,radius): return (positive(L(luminosity))/(4*np.pi*SIGMA*positive(R(radius))**2))**0.25*u.K
@method(5,'ρ = 3M/(4πR³)','stellar_density(1 M_sun,1 R_sun)')
def stellar_density(mass,radius): return positive(M(mass))/(4*np.pi/3*positive(R(radius))**3)*u.kg/u.m**3
@method(5,'λ_max T = 2.897771955×10⁻³ m K','wien_peak(5772 K)',visual='blackbody',aliases=['wien','peak_wavelength'])
def wien_peak(temperature): return Output(c.b_wien/positive(T(temperature))/u.K,plot=blackbody_spectrum(temperature).plot)
@method(5,'B_λ = 2hc²/[λ⁵(expm1(hc/(λkT)))]','blackbody_radiance(500 nm,5772 K)',model='Planck spectral radiance per wavelength per steradian; not observer flux')
def blackbody_radiance(wavelength,temperature):
    lam=positive(Q(wavelength,'m')); t=positive(T(temperature)); ex=H*C/(lam*KB*t)
    return (0 if ex>700 else 2*H*C*C/(lam**5*np.expm1(ex)))*u.W/u.m**3/u.sr
@method(5,'Sample Planck B_λ across 0.1–10 times the Wien wavelength','blackbody_spectrum(5772 K)',visual='blackbody',aliases=['blackbody'])
def blackbody_spectrum(temperature):
    t=positive(T(temperature)); peak=c.b_wien.value/t; x=np.geomspace(peak/10,peak*10,300); y=2*H*C*C/(x**5*np.expm1(H*C/(x*KB*t)))
    return Output({'peak_wavelength':peak*u.m,'wavelength':x*u.m,'radiance':y*u.W/u.m**3/u.sr},plot=curve(x/1e-9,y,'Wavelength / nm','Bλ / W m⁻³ sr⁻¹','Planck spectrum'))
@method(5,'F = σT⁴','stefan_boltzmann_flux(5772 K)')
def stefan_boltzmann_flux(temperature): return SIGMA*positive(T(temperature))**4*u.W/u.m**2
@method(5,'F = L/(4πd²)','flux_from_luminosity(1 L_sun,1 AU)',aliases=['brightness','flux'])
def flux_from_luminosity(luminosity,distance): return positive(L(luminosity))/(4*np.pi*positive(D(distance))**2)*u.W/u.m**2
@method(5,'m = M + 5 log₁₀(d/10pc) + A','apparent_magnitude(4.83,10 pc)')
def apparent_magnitude(absolute_mag,distance,extinction=0): return float(absolute_mag)+distance_modulus(distance)+float(extinction)
@method(5,'M = m − 5 log₁₀(d/10pc) − A','absolute_magnitude(9.83,100 pc)',model='Distance modulus in the supplied passband; named stars use approximate static V-band catalogue magnitudes')
def absolute_magnitude(apparent_mag,distance=None,extinction=0):
    if isinstance(apparent_mag,str):
        b=B(apparent_mag); magnitudes={'sun':-26.74,'sirius':-1.46,'alpha_centauri':0.01,'proxima':11.13,'vega':0.03,'betelgeuse':0.42}
        if b not in magnitudes: raise ValueError('No apparent V magnitude in the local stellar catalogue')
        d=AU if b=='sun' else STAR_COORDS[b][2]*PC
        return magnitudes[b]-distance_modulus(d*u.m)-float(extinction)
    if distance is None: raise ValueError('distance is required for a supplied apparent magnitude')
    return float(apparent_mag)-distance_modulus(distance)-float(extinction)
@method(5,'μ = 5 log₁₀(d/10pc)','distance_modulus(100 pc)')
def distance_modulus(distance): return 5*np.log10(positive(D(distance))/(10*PC))
@method(5,'M_bol = 4.74 − 2.5 log₁₀(L/L☉)','bolometric_magnitude(1 L_sun)',model='IAU bolometric zero point, solar M_bol=4.74')
def bolometric_magnitude(luminosity): return 4.74-2.5*np.log10(positive(L(luminosity))/LS)
@method(5,'Color index = m₁ − m₂','color_index(1.2,0.5)')
def color_index(magnitude1,magnitude2): return float(magnitude1)-float(magnitude2)
@method(5,'Place (T_eff, L/L☉) in H–R diagram','hr_position(sun)',visual='hr',model='Catalogue estimates; schematic main-sequence reference, not a stellar evolution track')
def hr_position(star):
    t=T(star); l=L(star)/LS; return Output({'temperature':t*u.K,'luminosity_solar':l},diagram={'kind':'hr','name':B(star),'temperature':t,'luminosity':l})
@method(5,'L/L☉ ≈ 0.23m^2.3 (m<0.43), m⁴ (m<2), 1.4m^3.5 (m<55), 32000m','main_sequence_luminosity(1 M_sun)',model='Piecewise empirical main-sequence mass–luminosity scaling; approximate solar metallicity')
def main_sequence_luminosity(mass,model='piecewise'):
    if model!='piecewise': raise ValueError('Supported model: piecewise')
    m=positive(M(mass))/MS
    if not 0.08<=m<=150: raise ValueError('Main-sequence scaling valid for 0.08–150 M_sun')
    return (0.23*m**2.3 if m<0.43 else m**4 if m<2 else 1.4*m**3.5 if m<55 else 32000*m)*LS*u.W
@method(5,'t_MS ≈ 10¹⁰ yr (M/M☉)/(L/L☉)','stellar_lifetime(1 M_sun,0.014)',model='Solar-metallicity main-sequence fuel/luminosity scaling; not evolutionary tracks')
def stellar_lifetime(mass,metallicity,model='fuel_scaling'):
    if model!='fuel_scaling' or not 0<=float(metallicity)<=0.1: raise ValueError('fuel_scaling requires 0 ≤ metallicity ≤ 0.1')
    return Output(1e10*(M(mass)/MS)/(main_sequence_luminosity(mass).value/LS)*u.yr,notes=[f'Input metallicity Z={metallicity}; fuel_scaling has no metallicity dependence. Use evolutionary tracks for metallicity-dependent lifetimes.'])
@method(5,'r_inner = √(L/L☉ / 1.107) AU; r_outer = √(L/L☉ / 0.356) AU','habitable_zone(1 L_sun)',model='Solar-spectrum conservative runaway-greenhouse / maximum-greenhouse flux thresholds; luminosity scaling only',visual='habitable')
def habitable_zone(luminosity,model='solar_flux'):
    if model!='solar_flux': raise ValueError('Supported model: solar_flux (solar-like spectrum only)')
    l=positive(L(luminosity))/LS; inner=np.sqrt(l/1.107); outer=np.sqrt(l/0.356)
    return Output({'inner':inner*u.au,'outer':outer*u.au},diagram={'kind':'habitable','inner':inner,'outer':outer})
@method(5,'v_esc = √(2GM/R)','stellar_escape_velocity(1 M_sun,1 R_sun)')
def stellar_escape_velocity(mass,radius): return escape_velocity(mass,radius)
@method(5,'g = GM/R²','stellar_surface_gravity(1 M_sun,1 R_sun)')
def stellar_surface_gravity(mass,radius): return surface_gravity(mass,radius)

@method(6,'r_s = 2GM/c²','schwarzschild_radius(10 M_sun)',visual='black_hole',model='Schwarzschild: nonrotating, uncharged, isolated black hole',aliases=['schwarzschild','event_horizon','black_hole'])
def schwarzschild_radius(mass):
    rs=2*G*positive(M(mass))/C**2
    return Output(rs*u.m,diagram={'kind':'black_hole','mass':M(mass),'horizon':rs,'photon':1.5*rs,'isco':3*rs,'spin':0})
@method(6,'r_ph = 3GM/c² = 1.5r_s','photon_sphere_radius(10 M_sun)',model='Schwarzschild only; Kerr has no single spherical photon orbit')
def photon_sphere_radius(mass): return 3*G*positive(M(mass))/C**2*u.m
@method(6,'r_ISCO = (GM/c²)[3+Z₂−sgn(a*)√((3−Z₁)(3+Z₁+2Z₂))]','isco_radius(10 M_sun,0.5)',model='Kerr equatorial test-particle ISCO; positive spin prograde, negative retrograde',visual='black_hole')
def isco_radius(mass,spin=0):
    a=bounded_spin(spin); z1=1+np.cbrt(1-a*a)*(np.cbrt(1+a)+np.cbrt(1-a)); z2=np.sqrt(3*a*a+z1*z1)
    return G*positive(M(mass))/C**2*(3+z2-np.sign(a)*np.sqrt((3-z1)*(3+z1+2*z2)))*u.m
@method(6,'r₊ = (GM/c²)(1+√(1−a*²))','kerr_horizon_radius(10 M_sun,0.9)',model='Kerr Boyer–Lindquist outer horizon radius; no single photon sphere',visual='black_hole')
def kerr_horizon_radius(mass,spin):
    a=bounded_spin(spin); r=G*positive(M(mass))/C**2*(1+np.sqrt(1-a*a))
    return Output(r*u.m,diagram={'kind':'black_hole','mass':M(mass),'horizon':r,'isco':isco_radius(mass,a).value,'spin':a})

def schwarz_factor(mass,r):
    rs=2*G*positive(M(mass))/C**2; r=positive(D(r))
    if r<=rs: raise ValueError('Static Schwarzschild observer must lie outside event horizon')
    return np.sqrt(1-rs/r)
@method(6,'1+z = √[(1−r_s/r_observer)/(1−r_s/r_emitter)]','gravitational_redshift(sun,1 R_sun,1 AU)',model='Static observers in Schwarzschild exterior; positive z is redshift')
def gravitational_redshift(mass,r_emitter,r_observer): return schwarz_factor(mass,r_observer)/schwarz_factor(mass,r_emitter)-1
@method(6,'dτ/dt = √(1−2GM/(rc²))','gravitational_time_dilation(sun,1 R_sun)',model='Static Schwarzschild observer relative to infinity')
def gravitational_time_dilation(mass,radius): return schwarz_factor(mass,radius)
@method(6,'α = 4GM/(bc²)','gravitational_lensing_angle(sun,1 R_sun)',model='Weak-field point lens, b ≫ r_s')
def gravitational_lensing_angle(mass,impact_parameter):
    b=positive(D(impact_parameter)); rs=2*G*M(mass)/C**2
    if b<20*rs: raise ValueError('Weak-lensing approximation requires impact parameter ≥ 20 r_s')
    return 2*rs/b*u.rad
@method(6,'θ_E = √[(4GM/c²)(D_s−D_l)/(D_l D_s)]','einstein_radius(1 M_sun,1 kpc,8 kpc)',model='Thin point lens, Euclidean angular-diameter distances')
def einstein_radius(lens_mass,lens_distance,source_distance):
    dl=positive(D(lens_distance)); ds=positive(D(source_distance))
    if ds<=dl: raise ValueError('Source must be farther away than lens')
    return np.sqrt(4*G*positive(M(lens_mass))/C**2*(ds-dl)/(dl*ds))*u.rad
@method(6,'γ = 1/√(1−v²/c²)','lorentz_factor(0.8 c)')
def lorentz_factor(velocity): return 1/np.sqrt(1-beta(velocity)**2)
@method(6,'Δt = γ Δτ','special_relativistic_time_dilation(1 s,0.8 c)')
def special_relativistic_time_dilation(proper_time,velocity): return positive(seconds(proper_time))*lorentz_factor(velocity)*u.s
@method(6,'L = L₀/γ','length_contraction(1 m,0.8 c)')
def length_contraction(proper_length,velocity): return positive(D(proper_length))/lorentz_factor(velocity)*u.m
@method(6,'K = (γ−1)mc², evaluated stably at low velocity','relativistic_kinetic_energy(1 kg,0.8 c)')
def relativistic_kinetic_energy(mass,velocity):
    b=beta(velocity); g=lorentz_factor(velocity); return positive(M(mass))*C*C*(g*g*b*b/(g+1))*u.J
@method(6,'E₀ = mc²','rest_energy(1 kg)')
def rest_energy(mass): return positive(M(mass))*C**2*u.J
@method(6,'ν_observer = ν_source/[γ(1+β cos θ)]','relativistic_doppler(500 THz,0.1 c,0 deg)',model='θ between recession velocity and source-to-observer line, source emission-angle convention; θ=0 receding')
def relativistic_doppler(frequency,velocity,angle): return positive(Q(frequency,'Hz'))/(lorentz_factor(velocity)*(1+beta(velocity)*np.cos(Q(angle,'rad'))))*u.Hz
@method(6,'T_H = ℏc³/(8πGMk_B)','hawking_temperature(1 M_sun)',model='Nonrotating uncharged black hole; semiclassical Hawking temperature')
def hawking_temperature(mass): return c.hbar.value*C**3/(8*np.pi*G*positive(M(mass))*KB)*u.K
@method(6,'S = 4πk_B GM²/(ℏc)','black_hole_entropy(1 M_sun)',model='Schwarzschild Bekenstein–Hawking entropy')
def black_hole_entropy(mass): return 4*np.pi*KB*G*positive(M(mass))**2/(c.hbar.value*C)*u.J/u.K
@method(6,'t_evap = 5120πG²M³/(ℏc⁴)','black_hole_evaporation_time(1 M_sun)',model='Idealized isolated Schwarzschild black hole; no accretion or greybody/species corrections')
def black_hole_evaporation_time(mass): return 5120*np.pi*G**2*positive(M(mass))**3/(c.hbar.value*C**4)*u.s
@method(6,'Δa ≈ 2GMℓ/r³','tidal_acceleration(10 M_sun,100 km,2 m)',model='Newtonian radial linear tidal gradient, ℓ ≪ r; no strong-field relativistic correction')
def tidal_acceleration(mass,radius,separation):
    r=positive(D(radius)); l=positive(D(separation))
    if l>r*0.1: raise ValueError('Linear tidal approximation requires separation ≤ 0.1 radius')
    return 2*G*positive(M(mass))*l/r**3*u.m/u.s**2

# Exoplanets: use supplied observer inclination, not the ICRS orbit inclination as transit geometry.
def transit_parameters(planet,star,o,geometry=None):
    import batman
    o=O(o); g=geometry or {}; p=batman.TransitParams(); p.t0=seconds(g.get('epoch',0))/86400; p.per=2*np.pi*np.sqrt(o['a']**3/o['mu'])/86400; p.rp=R(planet)/R(star); p.a=o['a']/R(star)
    p.inc=Q(g.get('inclination',90*u.deg),'deg');
    if not 0<=p.inc<=90: raise ValueError('Transit observer inclination must lie in [0,90] degrees')
    p.ecc=o['e']; p.w=Q(g.get('argp',o.get('argp',0)*u.rad),'deg'); p.limb_dark='quadratic'; p.u=g.get('limb_darkening',[0.3,0.2]); return p
@method(7,'δ = (R_p/R_s)²','transit_depth(earth,sun)',model='Uniform stellar disk, small opaque planet, central transit; ignores limb darkening')
def transit_depth(planet_radius,star_radius): return (positive(R(planet_radius))/positive(R(star_radius)))**2
@method(7,'T₁₄ ≈ (P/π) asin[(R_s/a)√((1+k)²−b²)/sin i] √(1−e²)/(1+e sin ω)','transit_duration(earth_orbit,earth,sun,{inclination:90 deg})',model='Keplerian transit duration approximation; projected chord geometry')
def transit_duration(orbit,planet,star,geometry):
    p=transit_parameters(planet,star,orbit,geometry); i=np.deg2rad(p.inc); w=np.deg2rad(p.w); b=p.a*np.cos(i)*(1-p.ecc**2)/(1+p.ecc*np.sin(w)); chord=(1+p.rp)**2-b*b
    if chord<=0: raise ValueError('Orbit geometry does not transit')
    return p.per/np.pi*np.arcsin(np.clip(np.sqrt(chord)/(p.a*np.sin(i)),-1,1))*np.sqrt(1-p.ecc**2)/(1+p.ecc*np.sin(w))*u.day
@method(7,'P_tr = (R_s+R_p)/a × (1+e sin ω)/(1−e²)','transit_probability(earth_orbit,sun,earth)',model='Random viewing orientation; eccentric Keplerian orbit')
def transit_probability(orbit,star_radius,planet_radius):
    o=O(orbit); return min(1,(R(star_radius)+R(planet_radius))/o['a']*(1+o['e']*np.sin(o['argp']))/(1-o['e']**2))
@method(7,'batman quadratic-limb-darkened Keplerian occultation model','transit_light_curve(earth,sun,earth_orbit,[-0.3 day,-0.1 day,0 day,0.1 day,0.3 day])',visual='transit',model='batman analytic occultation; default i=90°, u=[0.3,0.2], epoch=0; explicit observer geometry')
def transit_light_curve(planet,star,orbit,times,geometry=None):
    import batman
    p=transit_parameters(planet,star,orbit,geometry); t=samples(times,'s')/86400; flux=batman.TransitModel(p,t).light_curve(p)
    return Output({'time':t*u.day,'flux':flux},plot=curve(t,flux,'Time / days','Relative flux','Transit'),diagram={'kind':'transit_controls','planet_radius':R(planet),'star_radius':R(star),'a':O(orbit)['a'],'period':p.per,'e':p.ecc,'argp':p.w,'times':t.tolist(),'inclination':p.inc,'limb_darkening':p.u})
@method(7,'t_n = t_ref + nP','transit_times(earth_orbit,"2026-01-01",3)')
def transit_times(orbit,reference_time,count):
    if not 1<=int(count)<=10000: raise ValueError('count must lie in [1,10000]')
    o=O(orbit); p=2*np.pi*np.sqrt(o['a']**3/o['mu']); return [ (date(reference_time)+j*p*u.s).isot for j in range(int(count)) ]
@method(7,'b = a cos i / R_s × (1−e²)/(1+e sin ω)','impact_parameter(earth_orbit,89.9 deg,sun)')
def impact_parameter(orbit,inclination,star_radius):
    o=O(orbit); return abs(o['a']*np.cos(angle(inclination))/R(star_radius)*(1-o['e']**2)/(1+o['e']*np.sin(o['argp'])))
@method(7,'K = (2πG/P)^(1/3) M_p sin i / [(M_s+M_p)^(2/3)√(1−e²)]','radial_velocity_amplitude({a:1 AU,central_mass:sun,inclination:90 deg},earth,sun)',model='Keplerian reflex RV; explicit Orbit inclination is interpreted to sky plane')
def radial_velocity_amplitude(orbit,planet_mass,star_mass):
    o=O(orbit); mp=positive(M(planet_mass)); ms=positive(M(star_mass)); p=2*np.pi*np.sqrt(o['a']**3/(G*(ms+mp)))
    return (2*np.pi*G/p)**(1/3)*mp*abs(np.sin(o['i']))/(ms+mp)**(2/3)/np.sqrt(1-o['e']**2)*u.m/u.s
@method(7,'RV(t) = K[cos(ν+ω)+e cos ω]','radial_velocity_curve({a:1 AU,central_mass:sun,inclination:90 deg},earth,sun,[0 day,90 day,180 day,270 day])',visual='radial_velocity')
def radial_velocity_curve(orbit,planet,star,times):
    o=O(orbit); k=radial_velocity_amplitude(o,planet,star).value; ts=samples(times,'s'); ys=[]
    for t in ts:
        nu=anomaly_at(o,date(o['epoch'],'tdb')+t*u.s)[0]; ys.append(k*(np.cos(nu+o['argp'])+o['e']*np.cos(o['argp'])))
    return Output({'time':ts*u.s,'velocity':np.array(ys)*u.m/u.s},plot=curve(ts/86400,ys,'Time / days','Radial velocity / m s⁻¹'))
@method(7,'Fit sinusoidal RV at fixed period; solve K=(2πG/P)^(1/3)m/(M+m)^(2/3)','minimum_planet_mass({time:[0 day,90 day,180 day,270 day],velocity:[0 m/s,10 m/s,0 m/s,-10 m/s]},sun,360 day)',model='Circular orbit sinusoidal fit, sin i=1; no eccentric RV fitting')
def minimum_planet_mass(rv_data,stellar_mass,period):
    t=np.array([seconds(x) for x in rv_data['time']]); y=np.array([Q(x,'m/s') for x in rv_data['velocity']]); p=positive(seconds(period)); w=2*np.pi/p
    design=np.column_stack([np.sin(w*t),np.cos(w*t),np.ones(len(t))]); coef=np.linalg.lstsq(design,y,rcond=None)[0]; k=np.hypot(*coef[:2]); ms=positive(M(stellar_mass)); mp=brentq(lambda m:(2*np.pi*G/p)**(1/3)*m/(ms+m)**(2/3)-k,0,100*ms,xtol=1e-10)
    return {'minimum_mass':mp*u.kg,'semiamplitude':k*u.m/u.s,'systemic_velocity':coef[2]*u.m/u.s}
@method(7,'R_p = R_s √δ','planet_radius_from_transit(0.000084,sun)')
def planet_radius_from_transit(depth,star_radius): return R(star_radius)*np.sqrt(fraction(depth,'depth'))*u.m
@method(7,'T_eq = T_s √(R_s/(2a)) (1−A)^(1/4)','equilibrium_temperature(sun,earth_orbit,0.3)',model='Full heat redistribution, blackbody emitter, no greenhouse; uses semimajor axis')
def equilibrium_temperature(star,orbit,albedo): return T(star)*np.sqrt(R(star)/(2*O(orbit)['a']))*(1-fraction(albedo,'Bond albedo'))**0.25*u.K
@method(7,'S = L/(4πr²)','orbital_insolation(sun,1 AU)')
def orbital_insolation(star,orbital_distance): return flux_from_luminosity(star,orbital_distance)
@method(7,'ρ = 3M/(4πR³)','planet_density(1 M_earth,1 R_earth)')
def planet_density(mass,radius): return stellar_density(mass,radius)
@method(7,'H = k_B T/(m̄ g)','atmospheric_scale_height(288 K,9.81 m/s2,28.97 u)')
def atmospheric_scale_height(temperature,gravity,mean_molecular_mass): return KB*positive(T(temperature))/(positive(Q(mean_molecular_mass,'kg'))*positive(Q(gravity,'m/s2')))*u.m
@method(7,'Δδ ≈ 2 N_H R_p H / R_s²','transmission_signal(earth,sun,{temperature:288 K,mean_molecular_mass:28.97 u,scale_heights:5})',model='Thin isothermal atmosphere, effective absorbing height N_H H')
def transmission_signal(planet,star,atmosphere):
    h=atmospheric_scale_height(atmosphere['temperature'],surface_gravity(planet),atmosphere['mean_molecular_mass']).value; return 2*positive(float(atmosphere.get('scale_heights',5)))*R(planet)*h/R(star)**2
@method(7,'F_p/F_s = A_g(R_p/a)² [sin α + (π−α) cos α]/π','planet_phase_curve(earth,sun,earth_orbit)',model='Lambertian reflected light only; geometric albedo 0.3, edge-on circular phase; thermal emission excluded',visual='phase')
def planet_phase_curve(planet,star,orbit):
    o=O(orbit); phase=np.linspace(0,1,201); alpha=np.arccos(-np.cos(2*np.pi*phase)); f=0.3*(R(planet)/o['a'])**2*(np.sin(alpha)+(np.pi-alpha)*np.cos(alpha))/np.pi
    return Output({'phase':phase,'relative_flux':f},plot=curve(phase,f,'Orbital phase','Planet/star reflected flux'))

# Cosmology: model choice is explicit in every result; no user-blocking first-use dialog.
def cosmo(model='Planck18'):
    if isinstance(model,dict): return FlatLambdaCDM(H0=Q(model['H0'],'km/s/Mpc')*u.km/u.s/u.Mpc,Om0=float(model['Om0']),Tcmb0=T(model.get('Tcmb0',2.7255))*u.K,name='Custom flat ΛCDM')
    if model not in ('Planck18','Planck15','WMAP9'): raise ValueError('model must be Planck18, Planck15, WMAP9, or {H0,Om0,Tcmb0}')
    return {'Planck18':Planck18,'Planck15':Planck15,'WMAP9':WMAP9}[model]
def Z(z):
    z=float(z)
    if z<0 or not np.isfinite(z): raise ValueError('Cosmological redshift must be finite and ≥ 0')
    return z
@method(8,'FLRW cosmology parameters, including H₀, Ωm, ΩΛ, T_CMB','cosmology(model="Planck18")',model='Astropy FLRW; default Planck18 explicitly reported')
def cosmology(model='Planck18'):
    m=cosmo(model); return {'name':m.name,'H0':m.H0,'Om0':m.Om0,'Ode0':m.Ode0,'Tcmb0':m.Tcmb0,'Ob0':m.Ob0}
@method(8,'t₀ = ∫₀∞ dz/[(1+z)H(z)]','age_of_universe(model="Planck18")')
def age_of_universe(model='Planck18'): return cosmo(model).age(0)
@method(8,'t(z) = ∫z∞ dz′/[(1+z′)H(z′)]','cosmic_age(3)')
def cosmic_age(z,model='Planck18'): return cosmo(model).age(Z(z))
@method(8,'H(z) = H₀ E(z)','hubble_parameter(1)')
def hubble_parameter(z,model='Planck18'): return cosmo(model).H(Z(z))
@method(8,'t_H = 1/H₀','hubble_time()')
def hubble_time(model='Planck18'): return cosmo(model).hubble_time
@method(8,'t_L = ∫₀z dz′/[(1+z′)H(z′)]','lookback_time(1)')
def lookback_time(z,model='Planck18'): return cosmo(model).lookback_time(Z(z))
@method(8,'D_C = c ∫₀z dz′/H(z′)','comoving_distance(1)',visual='cosmology')
def comoving_distance(z,model='Planck18'): return cosmo(model).comoving_distance(Z(z))
@method(8,'D_L = (1+z)D_M','luminosity_distance(1)',visual='cosmology')
def luminosity_distance(z,model='Planck18'): return cosmo(model).luminosity_distance(Z(z))
@method(8,'D_A = D_M/(1+z)','angular_diameter_distance(1)',visual='cosmology')
def angular_diameter_distance(z,model='Planck18'): return cosmo(model).angular_diameter_distance(Z(z))
@method(8,'D_LT = c t_L','light_travel_distance(1)')
def light_travel_distance(z,model='Planck18'): return (cosmo(model).lookback_time(Z(z))*c.c).to(u.Mpc)
@method(8,'ΔD_C = |D_C(z₂) − D_C(z₁)|','distance_between_redshifts(0.5,1)',model='Radial comoving separation on same sightline; not angular-diameter lens distance')
def distance_between_redshifts(z1,z2,model='Planck18'): return abs(cosmo(model).comoving_distance(Z(z2))-cosmo(model).comoving_distance(Z(z1)))
@method(8,'V_C(z) = full-sky comoving volume enclosed by z','comoving_volume(1)')
def comoving_volume(z,model='Planck18'): return cosmo(model).comoving_volume(Z(z))
@method(8,'ρ_c = 3H(z)²/(8πG)','critical_density(0)')
def critical_density(z,model='Planck18'): return cosmo(model).critical_density(Z(z)).to(u.kg/u.m**3)
@method(8,'ρ_m = Ω_m(z)ρ_c(z)','matter_density(1)')
def matter_density(z,model='Planck18'): return cosmo(model).Om(Z(z))*critical_density(z,model)
@method(8,'ρ_DE = Ω_DE(z)ρ_c(z)','dark_energy_density(1)')
def dark_energy_density(z,model='Planck18'): return cosmo(model).Ode(Z(z))*critical_density(z,model)
@method(8,'Ω_i(z) from FLRW model','density_parameters(1)')
def density_parameters(z,model='Planck18'):
    m=cosmo(model); z=Z(z); return {'matter':m.Om(z),'dark_energy':m.Ode(z),'curvature':m.Ok(z),'photons':m.Ogamma(z),'neutrinos':m.Onu(z)}
@method(8,'a = 1/(1+z)','scale_factor(2)')
def scale_factor(z): return 1/(1+Z(z))
@method(8,'z = 1/a − 1','redshift_from_scale_factor(0.5)')
def redshift_from_scale_factor(scale_factor): return 1/positive(float(scale_factor))-1
@method(8,'T_CMB(z) = T_CMB,0 (1+z)','cmb_temperature(10)')
def cmb_temperature(z,model='Planck18'): return cosmo(model).Tcmb(Z(z))
@method(8,'μ = 5 log₁₀(D_L/10pc)','cosmological_distance_modulus(1)')
def cosmological_distance_modulus(z,model='Planck18'): return cosmo(model).distmod(Z(z)).value
@method(8,'v = H₀d','hubble_law_velocity(10 Mpc,70 km/s/Mpc)',model='Low-redshift linear Hubble approximation only; reject implied |v| > 0.1c')
def hubble_law_velocity(distance,H0):
    v=Q(H0,'1/s')*positive(D(distance))
    if abs(v)>0.1*C: raise ValueError('Linear Hubble approximation restricted to |H₀d| ≤ 0.1c; use FLRW distances')
    return v*u.m/u.s
@method(8,'D_particle = c ∫₀∞ dz/H(z)','particle_horizon()')
def particle_horizon(model='Planck18'):
    m=cosmo(model); val,err=quad(lambda a:1/(a*a*m.efunc(1/a-1)),0,1,epsabs=1e-9,limit=300)
    return Output((val*c.c/m.H0).to(u.Mpc),uncertainty=(err*c.c/m.H0).to(u.Mpc),notes=['Uncertainty is quadrature error only; cosmology parameter uncertainty excluded'])
@method(9,'v_c(r) = √[G M_enclosed(r)/r]','galaxy_rotation_curve([1 kpc,5 kpc,10 kpc],{model:plummer,mass:1e11 M_sun,scale:3 kpc})',visual='rotation',model='Spherical Plummer or point mass; explicit enclosed-mass profile supported')
def galaxy_rotation_curve(radius,mass_model):
    rr=np.array([positive(D(x)) for x in ([radius] if isinstance(radius,(u.Quantity,int,float)) and np.ndim(radius)==0 else radius)]); model=mass_model.get('model','plummer'); m=positive(M(mass_model['mass']))
    if model=='plummer': enclosed=m*rr**3/(rr*rr+positive(D(mass_model['scale']))**2)**1.5
    elif model=='point': enclosed=np.full_like(rr,m)
    elif model=='nfw':
        x=rr/positive(D(mass_model['scale'])); cc=positive(float(mass_model['concentration'])); enclosed=m*(np.log1p(x)-x/(1+x))/(np.log1p(cc)-cc/(1+cc))
    else: raise ValueError('Supported mass models: plummer, point, nfw')
    vv=np.sqrt(G*enclosed/rr); return Output({'radius':rr*u.m,'velocity':vv*u.m/u.s},plot=curve(rr/u.kpc.to(u.m),vv/1000,'Radius / kpc','Circular velocity / km s⁻¹'))
@method(9,'M(<r) = v²r/G','dynamical_mass(200 km/s,10 kpc)',model='Spherical mass distribution, circular orbit')
def dynamical_mass(velocity,radius): return Q(velocity,'m/s')**2*positive(D(radius))/G*u.kg
@method(9,'M_vir = k σ²R/G','virial_mass(100 km/s,1 kpc)',model='Uniform spherical system k=5, isotropic 1D dispersion; explicit k object allowed')
def virial_mass(velocity_dispersion,radius,model='uniform_sphere'):
    k=5 if model=='uniform_sphere' else positive(float(model['coefficient'])) if isinstance(model,dict) else None
    if k is None: raise ValueError('Provide uniform_sphere or {coefficient:k}')
    return k*dynamical_mass(velocity_dispersion,radius)
@method(9,'σ = √[Σ(v_i−v̄)²/(N−1)]','velocity_dispersion([10 km/s,20 km/s,30 km/s])')
def velocity_dispersion(velocities):
    if len(velocities)<2: raise ValueError('Sample dispersion requires at least two velocities')
    return np.std([Q(x,'m/s') for x in velocities],ddof=1)*u.m/u.s
@method(9,'I = F/Ω','surface_brightness(1e-15 W/m2,10 arcsec2)')
def surface_brightness(flux,angular_area): return Q(flux,'W/m2')/positive(Q(angular_area,'sr'))*u.W/u.m**2/u.sr
@method(9,'M = a log₁₀(v/v_ref)+b; d=10pc × 10^[(m−M−A)/5]','tully_fisher_distance(200 km/s,12,{slope:-10,intercept:-21,reference_speed:200 km/s,extinction:0})',model='User-supplied passband calibration; intrinsic scatter not automatically assumed')
def tully_fisher_distance(rotation_speed,magnitude,calibration):
    absolute=float(calibration['slope'])*np.log10(positive(Q(rotation_speed,'m/s'))/positive(Q(calibration['reference_speed'],'m/s')))+float(calibration['intercept']); return 10*10**((float(magnitude)-absolute-float(calibration.get('extinction',0)))/5)*u.pc
@method(9,'SFR = C_Hα L_Hα','star_formation_rate_halpha(1e34 W,{coefficient:7.9e-42})',model='Coefficient in (M_sun/yr)/(erg/s), e.g. Kennicutt 1998 Salpeter 7.9e-42; extinction correction required externally')
def star_formation_rate_halpha(luminosity,calibration): return positive(float(calibration['coefficient']))*positive(Q(luminosity,'erg/s'))*u.M_sun/u.yr
@method(9,'12+log(O/H) = a + b N2 or a + b O3N2','metallicity_from_lines({NII:0.1,Halpha:1,OIII:1,Hbeta:0.35},{index:N2,intercept:8.90,slope:0.57})',model='Explicit strong-line calibration; N2=log[NII]/Hα, O3N2=log(([OIII]/Hβ)/([NII]/Hα))')
def metallicity_from_lines(line_fluxes,calibration):
    f=line_fluxes; n2=np.log10(positive(float(f['NII']))/positive(float(f['Halpha']))); kind=calibration['index']
    if kind not in ('N2','O3N2'): raise ValueError('Calibration index must be N2 or O3N2')
    idx=n2 if kind=='N2' else np.log10(positive(float(f['OIII']))/positive(float(f['Hbeta'])))-n2
    return float(calibration['intercept'])+float(calibration['slope'])*idx
@method(9,'M_J = π^(5/2)c_s³/(6G^(3/2)ρ^(1/2)); c_s²=kT/(μm_p)','jeans_mass(10 K,1e-17 kg/m3,2.33)',model='Homogeneous isothermal ideal gas, dimensionless mean molecular weight')
def jeans_mass(temperature,density,mean_molecular_weight):
    cs=np.sqrt(KB*positive(T(temperature))/(positive(float(mean_molecular_weight))*c.m_p.value)); return np.pi**2.5*cs**3/(6*G**1.5*np.sqrt(positive(Q(density,'kg/m3'))))*u.kg
@method(9,'λ_J = c_s √(π/(Gρ))','jeans_length(10 K,1e-17 kg/m3,2.33)')
def jeans_length(temperature,density,mean_molecular_weight): return np.sqrt(np.pi*KB*positive(T(temperature))/(G*positive(Q(density,'kg/m3'))*positive(float(mean_molecular_weight))*c.m_p.value))*u.m
@method(9,'t_ff = √(3π/(32Gρ))','free_fall_time(1e-17 kg/m3)',model='Pressureless uniform sphere')
def free_fall_time(density): return np.sqrt(3*np.pi/(32*G*positive(Q(density,'kg/m3'))))*u.s
@method(9,'τ = αℓ','optical_depth(0.01 /m,100 m)')
def optical_depth(absorption_coefficient,path_length): return Q(absorption_coefficient,'1/m')*positive(D(path_length))
@method(9,'T_vir = μm_p GM/(2k_B R)','virial_temperature(1e12 M_sun,200 kpc)',model='Spherical halo; fully ionized primordial gas μ=0.59; explicit μ object supported')
def virial_temperature(mass,radius,model='ionized_primordial'):
    mu=0.59 if model=='ionized_primordial' else positive(float(model['mean_molecular_weight'])) if isinstance(model,dict) else None
    if mu is None: raise ValueError('Supported model: ionized_primordial or {mean_molecular_weight:...}')
    return mu*c.m_p.value*G*positive(M(mass))/(2*KB*positive(R(radius)))*u.K
@method(9,'L_Edd = 4πGMc/κ','eddington_luminosity(10 M_sun)',model='Spherical radiation-pressure equilibrium; κ=0.034 m²/kg electron scattering default')
def eddington_luminosity(mass,opacity=0.034*u.m**2/u.kg): return 4*np.pi*G*positive(M(mass))*C/positive(Q(opacity,'m2/kg'))*u.W
@method(9,'L = η ṁ c²; Eddington ratio also reported','accretion_luminosity(10 M_sun,1e-8 M_sun/yr,0.1)')
def accretion_luminosity(mass,accretion_rate,efficiency):
    l=fraction(efficiency)*positive(Q(accretion_rate,'kg/s'))*C*C; return {'luminosity':l*u.W,'eddington_ratio':l/eddington_luminosity(mass).value}
@method(9,'r_B = 2GM/c_s²','bondi_radius(10 M_sun,10 km/s)',model='Bondi capture radius convention with factor 2')
def bondi_radius(mass,sound_speed): return 2*G*positive(M(mass))/positive(Q(sound_speed,'m/s'))**2*u.m
@method(9,'r_t ≈ R_s(M_BH/M_s)^(1/3)','tidal_disruption_radius(1e6 M_sun,sun,sun)',model='Newtonian disruption estimate; capture may occur inside horizon')
def tidal_disruption_radius(black_hole_mass,star_mass,star_radius): return positive(R(star_radius))*np.cbrt(positive(M(black_hole_mass))/positive(M(star_mass)))*u.m

@method(10,'ν = c/λ','wavelength_to_frequency(500 nm)')
def wavelength_to_frequency(wavelength): return C/positive(Q(wavelength,'m'))*u.Hz
@method(10,'λ = c/ν','frequency_to_wavelength(600 THz)')
def frequency_to_wavelength(frequency): return C/positive(Q(frequency,'Hz'))*u.m
@method(10,'E = hc/λ','photon_energy(500 nm)')
def photon_energy(wavelength): return H*C/positive(Q(wavelength,'m'))*u.J
@method(10,'z = (λ_observed − λ_emitted)/λ_emitted','redshift(500 nm,600 nm)',visual='spectrum',model='Dimensionless spectral redshift; not automatically a recession velocity')
def redshift(emitted_wavelength,observed_wavelength):
    em=positive(Q(emitted_wavelength,'m')); ob=positive(Q(observed_wavelength,'m')); z=ob/em-1
    return Output(z,diagram={'kind':'spectrum','emitted':em,'observed':ob,'z':z})
@method(10,'λ_obs = λ_emit √[(1+β)/(1−β)] (relativistic) or λ_emit(1+β)','doppler_shift(500 nm,30 km/s)',visual='spectrum',model='Line-of-sight recession positive; relativistic default, classical optional')
def doppler_shift(wavelength,velocity,model='relativistic'):
    b=beta(velocity)
    if model not in ('relativistic','classical'): raise ValueError('model must be relativistic or classical')
    if model=='classical' and abs(b)>0.01: raise ValueError('Classical Doppler model requires |v| ≤ 0.01c')
    em=positive(Q(wavelength,'m')); ob=em*(np.sqrt((1+b)/(1-b)) if model=='relativistic' else 1+b)
    return Output(ob*u.m,diagram={'kind':'spectrum','emitted':em,'observed':ob,'z':ob/em-1})
@method(10,'v/c = [(λ_obs/λ_emit)²−1]/[(λ_obs/λ_emit)²+1]','radial_velocity_from_shift(500 nm,600 nm)',model='Special-relativistic longitudinal Doppler only; cosmological and gravitational shifts excluded')
def radial_velocity_from_shift(emitted_wavelength,observed_wavelength):
    ratio=positive(Q(observed_wavelength,'m'))/positive(Q(emitted_wavelength,'m')); return C*(ratio*ratio-1)/(ratio*ratio+1)*u.m/u.s
@method(10,'R = λ/Δλ','spectral_resolution(500 nm,0.1 nm)')
def spectral_resolution(wavelength,delta_wavelength): return positive(Q(wavelength,'m'))/positive(Q(delta_wavelength,'m'))
@method(10,'EW = ∫(1−Fλ/F_cont) dλ','equivalent_width({wavelength:[499 nm,500 nm,501 nm],flux:[1,0.5,1]},1,[499 nm,501 nm])')
def equivalent_width(spectrum,continuum,interval):
    x=np.array([Q(v,'m') for v in spectrum['wavelength']]); y=np.array(spectrum['flux'],float); cont=np.broadcast_to(np.asarray(continuum,float),y.shape); lo,hi=[Q(v,'m') for v in interval]
    if len(x)<2 or len(x)!=len(y) or not np.all(np.diff(x)>0) or lo<x[0] or hi>x[-1] or hi<=lo or np.any(cont<=0): raise ValueError('Spectrum must be ordered and cover interval; positive continuum required')
    xs=np.r_[lo,x[(x>lo)&(x<hi)],hi]; integrand=1-y/cont
    return np.trapezoid(np.interp(xs,x,integrand),xs)*u.m
@method(10,'Δv_FWHM = c Δλ_FWHM/λ₀','line_broadening(0.1 nm,500 nm)',model='Velocity FWHM or pure thermal Doppler temperature with explicit atomic mass; instrumental width not subtracted')
def line_broadening(line_width,rest_wavelength,model='velocity'):
    v=C*positive(Q(line_width,'m'))/positive(Q(rest_wavelength,'m'))
    if model=='velocity': return v*u.m/u.s
    if isinstance(model,dict) and model.get('type')=='thermal': return Q(model['particle_mass'],'kg')*v*v/(8*np.log(2)*KB)*u.K
    raise ValueError('model must be velocity or {type:thermal,particle_mass:...}')
@method(10,'m = −2.5 log₁₀(F/F₀)','flux_to_magnitude(1e-12 W/m2,1e-8 W/m2)')
def flux_to_magnitude(flux,zero_point):
    f=flux if isinstance(flux,u.Quantity) else float(flux)*u.one; z=zero_point if isinstance(zero_point,u.Quantity) else float(zero_point)*u.one
    return -2.5*np.log10(positive((f/z).to_value(u.one)))
@method(10,'F = F₀ 10^(−0.4m)','magnitude_to_flux(10,1e-8 W/m2)')
def magnitude_to_flux(magnitude,zero_point): return zero_point*10**(-0.4*float(magnitude))
@method(10,'m₁−m₂ = −2.5 log₁₀(F₁/F₂)','magnitude_difference(100,10)')
def magnitude_difference(flux1,flux2): return flux_to_magnitude(flux1,flux2)
@method(10,'F_intrinsic = F_observed 10^(0.4A)','extinction_correct(1e-12 W/m2,0.5)')
def extinction_correct(flux,extinction): return flux*10**(0.4*float(extinction))
@method(10,'SNR = signal / noise','signal_to_noise(100,10)')
def signal_to_noise(signal,noise): return signal/positive(noise)

@method(11,'M = f_objective/f_eyepiece','telescope_magnification(1000 mm,25 mm)')
def telescope_magnification(focal_length,eyepiece_focal_length): return positive(D(focal_length))/positive(D(eyepiece_focal_length))
@method(11,'f-number = f/D','focal_ratio(1000 mm,200 mm)')
def focal_ratio(focal_length,aperture): return positive(D(focal_length))/positive(D(aperture))
@method(11,'A = πD²/4','aperture_area(200 mm)')
def aperture_area(diameter): return np.pi/4*positive(D(diameter))**2*u.m**2
@method(11,'θ = 1.22 λ/D','rayleigh_resolution(200 mm,550 nm)',model='Circular unobstructed aperture, Rayleigh first-minimum criterion')
def rayleigh_resolution(aperture,wavelength): return 1.22*positive(Q(wavelength,'m'))/positive(D(aperture))*u.rad
@method(11,'θ = 1.22 λ/D','diffraction_limit(200 mm,550 nm)',model='Rayleigh criterion, circular unobstructed aperture')
def diffraction_limit(aperture,wavelength): return rayleigh_resolution(aperture,wavelength)
@method(11,'FOV = 2 atan(s/(2f))','field_of_view(1000 mm,36 mm)')
def field_of_view(focal_length,sensor_size): return 2*np.arctan(positive(D(sensor_size))/(2*positive(D(focal_length))))*u.rad
@method(11,'Pixel scale = p/f radians per pixel','pixel_scale(3.76 um,1000 mm)')
def pixel_scale(pixel_size,focal_length): return positive(D(pixel_size))/positive(D(focal_length))*u.rad/u.pixel
@method(11,'Plate scale = 1/f radians per meter','plate_scale(1000 mm)')
def plate_scale(focal_length): return 1/positive(D(focal_length))*u.rad/u.m
@method(11,'Light gathering ratio = (D/D_ref)²','light_gathering_power(200 mm,7 mm)')
def light_gathering_power(aperture,reference_aperture): return (positive(D(aperture))/positive(D(reference_aperture)))**2
@method(11,'m_lim ≈ 2 + 5 log₁₀(D_mm) − extinction','limiting_magnitude(200 mm,{extinction:0.2})',model='Empirical visual dark-sky estimate; observer, seeing, magnification and sky brightness not independently fitted')
def limiting_magnitude(aperture,conditions,model='visual_dark_sky'):
    if model!='visual_dark_sky': raise ValueError('Supported model: visual_dark_sky')
    return 2+5*np.log10(positive(D(aperture))*1000)-float(conditions.get('extinction',0))
def noise_rates(source,instrument,conditions):
    # Inputs in detected electrons/s; throughput maps incident source to detected source.
    s=positive(Q(source['rate'] if isinstance(source,dict) else source,'1/s'))*fraction(instrument.get('throughput',1)); n=positive(float(instrument.get('pixels',1))); sky=Q(conditions.get('sky_rate',0),'1/s'); dark=Q(instrument.get('dark_rate',0),'1/s'); read=float(instrument.get('read_noise',0)); exposures=int(instrument.get('exposures',1))
    if sky<0 or dark<0 or read<0 or exposures<1: raise ValueError('Noise rates must be nonnegative and exposure count positive')
    return s,n*(sky+dark),n*read**2*exposures
@method(11,'SNR = St/√[(S+B)t+N_pix N_exp RN²]; solve quadratic for t','exposure_time(10,{rate:10 /s},{pixels:10,read_noise:3},{sky_rate:1 /s})',model='Poisson source + sky + dark, independent read noise; rates are electron counts per second')
def exposure_time(target_snr,source,instrument,conditions):
    s,b,r=noise_rates(source,instrument,conditions); q=positive(float(target_snr))**2
    return (q*(s+b)+np.sqrt(q*q*(s+b)**2+4*s*s*q*r))/(2*s*s)*u.s
@method(11,'SNR = St / √[(S+B)t + N_pix N_exp RN²]','telescope_snr({rate:10 /s},{pixels:10,read_noise:3},100 s,{sky_rate:1 /s})',model='Poisson source, sky and dark current plus independent read noise')
def telescope_snr(source,instrument,exposure,conditions):
    s,b,r=noise_rates(source,instrument,conditions); t=positive(seconds(exposure)); return s*t/np.sqrt((s+b)*t+r)
@method(11,'Sampling = FWHM/pixel_scale; Nyquist requires ≥ 2 pixels','nyquist_sampling(2 arcsec,1 arcsec/pixel)')
def nyquist_sampling(fwhm,pixel_scale):
    n=positive(Q(fwhm,'rad'))/positive(Q(pixel_scale,'rad/pixel')); return {'pixels_per_FWHM':n,'nyquist_satisfied':bool(n>=2)}
# Data imports are read-only. Paths are explicit; no automatic directory scans or network access.
def image_data(image):
    if isinstance(image,str):
        p=Path(image).expanduser()
        if p.stat().st_size>128*1024*1024: raise ValueError('Input file exceeds 128 MiB')
        if p.suffix.lower() in ('.fits','.fit','.fts'):
            from astropy.io import fits
            image=fits.getdata(p)
        else: image=np.loadtxt(p,delimiter=',' if p.suffix.lower()=='.csv' else None)
    a=np.asarray(image,float)
    if a.ndim!=2 or a.size>4_000_000 or not np.all(np.isfinite(a)): raise ValueError('Image must be finite 2D data, at most 4 million pixels')
    return a

def image_picture(a):
    # Preview downsampling never changes the data used in a calculation.
    stride=max(1,int(np.ceil(max(a.shape)/128))); data=a[::stride,::stride]; lo,hi=np.percentile(a,[1,99]); return {'kind':'image','pixels':data.tolist(),'low':float(lo),'high':float(hi),'width':a.shape[1],'height':a.shape[0]}
def samples(x,unit=None):
    if isinstance(x,dict):
        if 'file' in x:
            data=samples(str(x['file'])+('#'+str(x['column']) if 'column' in x else ''))
            return (data*u.Unit(x.get('unit',''))).to_value(unit) if unit else data
        count=int(x['count'])
        if not 2<=count<=10000: raise ValueError('Sample count must lie in [2,10000]')
        start=Q(x['start'],unit or ''); stop=Q(x['stop'],unit or '')
        return np.linspace(start,stop,count)
    if isinstance(x,str):
        # A quoted CSV path may select a named column: "/path/curve.csv#time".
        path,sep,column=x.partition('#')
        if Path(path).stat().st_size>128*1024*1024: raise ValueError('Input file exceeds 128 MiB')
        if sep:
            data=np.genfromtxt(path,delimiter=',',names=True,dtype=float)
            if column not in data.dtype.names: raise ValueError('CSV column not found: '+column)
            x=data[column]
        else: x=np.loadtxt(path,delimiter=',')
    if isinstance(x,u.Quantity): return np.atleast_1d(x.to_value(unit)) if unit else np.atleast_1d(x.value)
    values=x if isinstance(x,(list,tuple)) else np.atleast_1d(x)
    return np.array([Q(v,unit) for v in values]) if unit else np.asarray(values,float)
def paired(x,y):
    x=samples(x); y=samples(y)
    if x.ndim!=1 or y.shape!=x.shape or len(x)<3 or not np.all(np.isfinite(x)) or not np.all(np.isfinite(y)): raise ValueError('At least three finite paired samples are required')
    return x,y
@method(12,'DAOStarFinder detects local peaks after Gaussian convolution','detect_sources([[0,0,0,0,0],[0,1,3,1,0],[0,3,10,3,0],[0,1,3,1,0],[0,0,0,0,0]],2)',model='DAOStarFinder Gaussian FWHM=3px; background should be removed first',visual='image')
def detect_sources(image,threshold,method='dao'):
    from photutils.detection import DAOStarFinder
    if method!='dao': raise ValueError('Supported method: dao')
    a=image_data(image); table=DAOStarFinder(positive(float(threshold)),3,exclude_border=False)(a)
    out=[] if table is None else [{k:float(row[k]) for k in ('x_centroid','y_centroid','flux','peak')} for row in table]
    return Output({'sources':out,'count':len(out)},diagram=image_picture(a))
@method(12,'Sigma-clipped median and robust MAD RMS or Background2D mesh','estimate_background([[1,1,1],[1,100,1],[1,1,1]])',visual='image',model='Sigma-clipped scalar background or median mesh; 3σ clipping')
def estimate_background(image,method='sigma_clip'):
    from astropy.stats import sigma_clipped_stats
    a=image_data(image)
    if method=='sigma_clip':
        mean,med,std=sigma_clipped_stats(a,sigma=3); out={'mean':mean,'median':med,'rms':std}
    elif method=='mesh':
        from photutils.background import Background2D, MedianBackground
        b=Background2D(a,box_size=(max(2,a.shape[0]//4),max(2,a.shape[1]//4)),bkg_estimator=MedianBackground()); out={'background':b.background,'rms':b.background_rms}
    else: raise ValueError('Supported methods: sigma_clip, mesh')
    return Output(out,diagram=image_picture(a))
@method(12,'Centroid = Σ xI/ΣI, Σ yI/ΣI after regional median subtraction','centroid([[0,0,0],[0,10,0],[0,0,0]],{x:0,y:0,width:3,height:3})',visual='image',model='Positive center-of-mass estimator after median background subtraction')
def centroid(image,region):
    from photutils.centroids import centroid_com
    a=image_data(image); x=int(region['x']); y=int(region['y']); w=int(region['width']); h=int(region['height'])
    if x<0 or y<0 or w<1 or h<1 or x+w>a.shape[1] or y+h>a.shape[0]: raise ValueError('Region lies outside image')
    sub=a[y:y+h,x:x+w]; sub=np.maximum(sub-np.median(sub),0)
    if sub.sum()==0: raise ValueError('Region has no positive source above median')
    cx,cy=centroid_com(sub); return Output({'x':cx+x,'y':cy+y},diagram=image_picture(a))
@method(12,'Flux = Σ w_i(I_i−background); exact circular overlap weights','aperture_photometry([[0,0,0],[0,10,0],[0,0,0]],{x:1,y:1,radius:1},background=0)',visual='image')
def aperture_photometry(image,aperture,background=0):
    from photutils.aperture import CircularAperture, aperture_photometry as photo
    a=image_data(image); ap=CircularAperture((float(aperture['x']),float(aperture['y'])),positive(float(aperture['radius']))); tab=photo(a-np.asarray(background),ap,method='exact')
    return Output({'flux':float(tab['aperture_sum'][0]),'aperture_area':ap.area},diagram=image_picture(a))
@method(12,'Fit circular Gaussian PSF simultaneously in local source cutouts','psf_photometry([[0,0,0,0,0],[0,1,3,1,0],[0,3,10,3,0],[0,1,3,1,0],[0,0,0,0,0]],{fwhm:2,fit_size:5},[[2,2]])',visual='image',model='photutils CircularGaussianPRF; fixed FWHM, fitted x,y and integrated flux')
def psf_photometry(image,psf_model,positions):
    from photutils.psf import PSFPhotometry, CircularGaussianPRF
    from astropy.table import Table
    a=image_data(image); fwhm=positive(float(psf_model['fwhm'])); size=int(psf_model.get('fit_size',7))
    if size<3 or size%2==0: raise ValueError('fit_size must be odd and ≥ 3')
    init=Table({'x_init':[float(p[0]) for p in positions],'y_init':[float(p[1]) for p in positions]})
    fitter=PSFPhotometry(CircularGaussianPRF(fwhm=fwhm),fit_shape=(size,size),aperture_radius=fwhm)
    tab=fitter(a,init_params=init); out=[{k:float(row[k]) for k in ('x_fit','y_fit','flux_fit','flux_err','flags')} for row in tab]
    return Output({'sources':out},diagram=image_picture(a))
@method(12,'Zero point = weighted mean(m_ref + 2.5log₁₀ F)','photometric_calibration([1000,100,10],[10,12.5,15])',model='Matched reference stars in same passband, no color/airmass term; scatter reported')
def photometric_calibration(measurements,reference_catalog):
    flux=np.asarray(measurements,float); mag=np.asarray(reference_catalog,float)
    if flux.shape!=mag.shape or len(flux)<2 or np.any(flux<=0): raise ValueError('Need at least two matched positive fluxes and reference magnitudes')
    zp=mag+2.5*np.log10(flux); return Output({'zero_point':np.mean(zp),'calibrated_magnitudes':np.mean(zp)-2.5*np.log10(flux),'scatter':np.std(zp,ddof=1)},uncertainty=np.std(zp,ddof=1)/np.sqrt(len(zp)))
def wcs_object(wcs):
    from astropy.wcs import WCS
    if isinstance(wcs,str):
        from astropy.io import fits
        return WCS(fits.getheader(wcs))
    return WCS(wcs)
@method(12,'FITS WCS all_world2pix, zero-based pixels','world_to_pixel({ra:10 deg,dec:20 deg},{CTYPE1:"RA---TAN",CTYPE2:"DEC--TAN",CRPIX1:1,CRPIX2:1,CRVAL1:10,CRVAL2:20,CDELT1:-0.001,CDELT2:0.001})',model='FITS WCS, zero-based pixel output')
def world_to_pixel(sky_coordinate,wcs):
    q=coord(sky_coordinate).icrs; x,y=wcs_object(wcs).all_world2pix(q.ra.deg,q.dec.deg,0); return {'x':float(x),'y':float(y)}
@method(12,'FITS WCS all_pix2world, zero-based input pixels','pixel_to_world([0,0],{CTYPE1:"RA---TAN",CTYPE2:"DEC--TAN",CRPIX1:1,CRPIX2:1,CRVAL1:10,CRVAL2:20,CDELT1:-0.001,CDELT2:0.001})')
def pixel_to_world(pixel_coordinate,wcs):
    ra,dec=wcs_object(wcs).all_pix2world(float(pixel_coordinate[0]),float(pixel_coordinate[1]),0); return {'ra':ra*u.deg,'dec':dec*u.deg}
@method(12,'FFT phase correlation estimates translation; spline resampling aligns frames','align_images([[[0,0,0],[0,1,0],[0,0,0]],[[0,0,0],[0,0,1],[0,0,0]]],0)',model='Translation-only integer phase correlation; constant-zero fill, cubic interpolation; no rotation or distortion',visual='image')
def align_images(images,reference):
    arrays=[image_data(x) for x in images]; ref=arrays[int(reference)] if isinstance(reference,(int,float)) else image_data(reference); aligned=[]; shifts=[]
    for a in arrays:
        if a.shape!=ref.shape: raise ValueError('Image shapes must match')
        cross=np.fft.fft2(ref)*np.conj(np.fft.fft2(a)); cross/=np.maximum(abs(cross),1e-15); corr=np.fft.ifft2(cross).real; idx=np.array(np.unravel_index(np.argmax(corr),corr.shape)); shape=np.array(a.shape); idx=np.where(idx>shape//2,idx-shape,idx); shifts.append(idx.tolist()); aligned.append(image_shift(a,idx,mode='constant',cval=0))
    return Output({'images':np.array(aligned),'shifts_yx':shifts},diagram=image_picture(np.median(aligned,axis=0)))
@method(12,'Pixelwise median or mean over aligned images','stack_images([[[1,2],[3,4]],[[3,4],[5,6]]])',model='Requires aligned equal-size frames; median or mean; no automatic registration',visual='image')
def stack_images(images,method='median'):
    a=np.array([image_data(x) for x in images])
    if method not in ('median','mean'): raise ValueError('Supported methods: median, mean')
    out=(np.median if method=='median' else np.mean)(a,axis=0); return Output(out,diagram=image_picture(out))
@method(12,'Sort paired observation time and flux; preserve measured flux','light_curve([0 day,1 day,2 day],[1,0.99,1])',visual='light_curve')
def light_curve(time,flux):
    t,f=paired(samples(time,'s'),flux); idx=np.argsort(t); return Output({'time':t[idx]*u.s,'flux':f[idx]},plot=curve(t[idx]/86400,f[idx],'Time / days','Flux'))
@method(12,'Generalized weighted floating-mean Lomb–Scargle periodogram','periodogram([0 day,0.2 day,0.5 day,0.7 day,1 day,1.3 day],[0,1,0,-1,0,1])',visual='periodogram',model='Astropy LombScargle automatic frequency grid; uncertainties optional, false-alarm probability reported')
def periodogram(time,flux,errors=None):
    from astropy.timeseries import LombScargle
    t,f=paired(samples(time,'s'),flux)
    if len(np.unique(t))<3 or np.ptp(t)==0 or np.std(f)==0: raise ValueError('Periodogram needs variable flux at distinct times')
    ls=LombScargle(t,f,dy=errors); freq,power=ls.autopower(); idx=np.argmax(power)
    return Output({'best_period':1/freq[idx]*u.s,'frequency':freq*u.Hz,'power':power,'false_alarm_probability':(lambda p: float(p) if np.isfinite(p) else None)(ls.false_alarm_probability(power[idx]))},plot=curve(freq*86400,power,'Frequency / day⁻¹','Lomb–Scargle power'))
@method(12,'φ = ((t−epoch)/P) mod 1','phase_fold([0 day,1 day,2 day],[1,0.9,1],2 day)',visual='phase')
def phase_fold(time,flux,period,epoch=0):
    t,f=paired(samples(time,'s'),flux); phase=((t-seconds(epoch))/positive(seconds(period)))%1; idx=np.argsort(phase)
    return Output({'phase':phase[idx],'flux':f[idx]},plot=curve(phase[idx],f[idx],'Phase','Flux'))
@method(12,'Least-squares batman transit fit in radius ratio, epoch and inclination','fit_transit([-0.3 day,-0.1 day,0 day,0.1 day,0.3 day],[1,0.99,0.99,0.99,1],{period:3 day,a_over_rstar:8},{radius_ratio:0.1,epoch:0 day,inclination:90 deg})',model='Quadratic limb-darkened batman, fixed period and a/Rstar; bounded least squares',visual='transit')
def fit_transit(time,flux,model,parameters):
    import batman
    ts,y=paired(samples(time,'s')/86400,flux); p=batman.TransitParams(); p.per=positive(seconds(model['period']))/86400; p.a=positive(float(model['a_over_rstar'])); p.ecc=fraction(model.get('eccentricity',0)); p.w=Q(model.get('argp',90*u.deg),'deg'); p.limb_dark='quadratic'; p.u=model.get('limb_darkening',[0.3,0.2])
    def predict(x):
        p.rp,p.t0,p.inc=x; return batman.TransitModel(p,ts).light_curve(p)
    initial=[float(parameters['radius_ratio']),seconds(parameters.get('epoch',0))/86400,Q(parameters.get('inclination',89*u.deg),'deg')]
    fit=least_squares(lambda x:predict(x)-y,initial,bounds=([1e-5,min(ts)-p.per,60],[1,max(ts)+p.per,90]))
    return Output({'radius_ratio':fit.x[0],'epoch':fit.x[1]*u.day,'inclination':fit.x[2]*u.deg,'residual_rms':np.sqrt(np.mean(fit.fun**2)),'success':bool(fit.success)},plot=curve(ts,predict(fit.x),'Time / days','Relative flux','Fitted transit'))
@method(12,'Fit Gaussian line + constant continuum, or scaled Planck continuum','fit_spectrum([499 nm,499.5 nm,500 nm,500.5 nm,501 nm],[1,2,3,2,1],gaussian)',model='Unweighted least squares; Gaussian line or scaled blackbody; no instrument response correction',visual='spectrum_curve')
def fit_spectrum(wavelengths,fluxes,model):
    x,y=paired(samples(wavelengths,'m'),fluxes); scale=np.median(x); xx=x/scale
    if model=='gaussian':
        init=[np.ptp(y),xx[np.argmax(y)],max(np.ptp(xx)/5,1e-6),np.min(y)]
        pred=lambda p:p[0]*np.exp(-0.5*((xx-p[1])/p[2])**2)+p[3]
        fit=least_squares(lambda p:pred(p)-y,init,bounds=([-np.inf,min(xx),1e-9,-np.inf],[np.inf,max(xx),np.ptp(xx)*10,np.inf])); out={'amplitude':fit.x[0],'center':fit.x[1]*scale*u.m,'sigma':fit.x[2]*scale*u.m,'continuum':fit.x[3]}
    elif model=='blackbody':
        def pred(p):
            ex=np.clip(H*C/(x*KB*p[0]),1e-10,700); bb=2*H*C*C/(x**5*np.expm1(ex)); return p[1]*bb/max(bb)
        fit=least_squares(lambda p:pred(p)-y,[5772,max(y)],bounds=([1,0],[1e8,np.inf]),x_scale='jac'); out={'temperature':fit.x[0]*u.K,'amplitude':fit.x[1]}
    else: raise ValueError('Supported spectral models: gaussian, blackbody')
    out['residual_rms']=np.sqrt(np.mean(fit.fun**2)); return Output(out,plot=curve(x/1e-9,pred(fit.x),'Wavelength / nm','Flux','Fitted spectrum'))
@method(12,'Fit initial Cartesian r,v to 3D timed positions under two-body dynamics','fit_orbit({time:[0 s,100 s,200 s],positions:[[7000000,0,0],[6995930,749855,0],[6983720,1498840,0]]},{r:[7000000,0,0],v:[0,7500,0],central_mass:earth})',model='Newtonian Cartesian least squares, central mass fixed; input positions in m, times in s, initial epoch t=0',visual='orbit')
def fit_orbit(observations,initial_model):
    o=O(initial_model); ts=samples(observations['time'],'s'); positions=np.array([vec(x,'m') for x in observations['positions']]); order=np.argsort(ts); ts=ts[order]; positions=positions[order]
    if len(ts)<3 or len(np.unique(ts))!=len(ts) or np.min(ts)<0 or positions.shape!=(len(ts),3): raise ValueError('Need ≥3 distinct nonnegative times and N×3 Cartesian positions')
    def pred(p):
        if ts[-1]==0: return p[:3][None,:]
        sol=solve_ivp(lambda t,y:np.r_[y[3:],-o['mu']*y[:3]/norm(y[:3])**3],(0,ts[-1]),p,t_eval=ts,rtol=1e-9,atol=1e-3,method='DOP853'); return sol.y[:3].T
    fit=least_squares(lambda p:(pred(p)-positions).ravel(),np.r_[o['r'],o['v']],x_scale='jac'); out=elements(fit.x[:3],fit.x[3:],o['mu']); out['residual_rms_m']=np.sqrt(np.mean(fit.fun**2)); return Output(out,plot=orbit_plot(out))
@method(12,'Nearest-neighbor spherical catalogue match within tolerance','cross_match_catalog([{ra:10 deg,dec:20 deg}],[{ra:10.0001 deg,dec:20 deg}],1 arcsec)',model='ICRS nearest-neighbor angular match, many-to-one; epochs/proper motion must be aligned first')
def cross_match_catalog(catalog1,catalog2,tolerance):
    a=SkyCoord([coord(x).icrs for x in catalog1]); b=SkyCoord([coord(x).icrs for x in catalog2]); idx,sep,_=a.match_to_catalog_sky(b); return [{'first':i,'second':int(j),'separation':s} for i,(j,s) in enumerate(zip(idx,sep)) if s.rad<=angle(tolerance)]
# Restricted mathematical AST for expressions; never Python eval, attributes, indexing, comprehensions or arbitrary functions.
def expression_value(expression,values):
    funcs={'sqrt':np.sqrt,'sin':np.sin,'cos':np.cos,'exp':np.exp,'log':np.log,'log10':np.log10,'abs':np.abs}
    tree=ast.parse(expression.replace('^','**'),mode='eval')
    def walk(n):
        if isinstance(n,ast.Expression): return walk(n.body)
        if isinstance(n,ast.Constant) and isinstance(n.value,(int,float)): return n.value
        if isinstance(n,ast.Name) and n.id in values: return values[n.id]
        if isinstance(n,ast.UnaryOp) and isinstance(n.op,(ast.USub,ast.UAdd)): return -walk(n.operand) if isinstance(n.op,ast.USub) else walk(n.operand)
        if isinstance(n,ast.BinOp):
            a,b=walk(n.left),walk(n.right)
            if isinstance(n.op,ast.Add): return a+b
            if isinstance(n.op,ast.Sub): return a-b
            if isinstance(n.op,ast.Mult): return a*b
            if isinstance(n.op,ast.Div): return a/b
            if isinstance(n.op,ast.Pow):
                if np.ndim(b)!=0 or abs(b)>100: raise ValueError('Exponent out of range')
                return a**b
        if isinstance(n,ast.Call) and isinstance(n.func,ast.Name) and n.func.id in funcs and len(n.args)==1: return funcs[n.func.id](walk(n.args[0]))
        raise ValueError('Expression permits only arithmetic and sqrt,sin,cos,exp,log,log10,abs')
    return walk(tree)
@method(12,'σ_f² = J C Jᵀ; central numerical derivatives, optional full covariance','propagate_uncertainty("m/r^2",{m:{value:10 kg,sigma:1 kg},r:{value:2 m,sigma:0.1 m}})',model='First-order Gaussian propagation; independent inputs unless covariance supplied; nonlinear large-error cases may require Monte Carlo')
def propagate_uncertainty(expression,measurements):
    names=[k for k in measurements if k!='covariance']; values={k:measurements[k]['value'] for k in names}; base=expression_value(expression,values); unit=base.unit if isinstance(base,u.Quantity) else u.one; jac=[]; sigmas=[]
    for k in names:
        v=values[k]; vu=v.unit if isinstance(v,u.Quantity) else u.one; raw=Q(v,vu); sigma=Q(measurements[k]['sigma'],vu)
        if sigma<0: raise ValueError('Measurement sigma must be nonnegative')
        step=max(abs(raw)*1e-5,abs(sigma)*1e-4,1e-30); plus=dict(values); minus=dict(values); plus[k]=(raw+step)*vu; minus[k]=(raw-step)*vu
        derivative=(expression_value(expression,plus)-expression_value(expression,minus))/(2*step); jac.append(Q(derivative,unit)); sigmas.append(sigma)
    cov=np.array(measurements.get('covariance',np.diag(np.array(sigmas)**2)),float)
    if cov.shape!=(len(names),len(names)) or not np.allclose(cov,cov.T) or np.min(np.linalg.eigvalsh(cov)) < -1e-12: raise ValueError('Covariance must be symmetric positive semidefinite in input-unit products')
    err=np.sqrt(max(0,np.array(jac)@cov@np.array(jac)))*unit
    return Output(base,uncertainty=err,notes=['Covariance order: '+', '.join(names)])

# Gravitational waves: deliberately model-labelled leading-order predictions.
def binary(b):
    m1=positive(M(b['mass1'])); m2=positive(M(b['mass2'])); a=positive(D(b['separation'])); return m1,m2,a
@method(13,'M_chirp = (m₁m₂)^(3/5)/(m₁+m₂)^(1/5)','chirp_mass(30 M_sun,30 M_sun)')
def chirp_mass(mass1,mass2):
    a=positive(M(mass1)); b=positive(M(mass2)); return (a*b)**0.6/(a+b)**0.2*u.kg
@method(13,'f_GW = 2/P_orbit','gravitational_wave_frequency(earth_orbit)',model='Dominant quadrupole harmonic of a circular Newtonian binary')
def gravitational_wave_frequency(orbit): return (2/orbital_period(orbit)).to(u.Hz)
@method(13,'h₀ = 4G²m₁m₂/(c⁴ad)','gravitational_wave_strain({mass1:30 M_sun,mass2:30 M_sun,separation:1000 km},100 Mpc)',model='Leading quadrupole circular binary, face-on optimal strain amplitude; local source-frame parameters')
def gravitational_wave_strain(binary,distance,model='quadrupole'):
    if model!='quadrupole': raise ValueError('Supported model: quadrupole')
    a,b,r=globals()['binary'](binary); return 4*G**2*a*b/(C**4*r*positive(D(distance)))
@method(13,'Peters 1964 eccentric inspiral integral; circular t = 5c⁵a⁴/[256G³m₁m₂(m₁+m₂)]','inspiral_time(30 M_sun,30 M_sun,1000 km,0.2)',model='Orbit-averaged quadrupole radiation reaction, point masses; no spin or merger dynamics')
def inspiral_time(mass1,mass2,separation,eccentricity=0):
    m1=positive(M(mass1)); m2=positive(M(mass2)); a=positive(D(separation)); e=fraction(eccentricity,'eccentricity')
    if e>=1: raise ValueError('Inspiral requires bound e < 1')
    b=64/5*G**3*m1*m2*(m1+m2)/C**5
    if e<1e-5: t=a**4/(4*b)
    else:
        c0=a*(1-e*e)*e**(-12/19)*(1+121/304*e*e)**(-870/2299)
        integral=quad(lambda x:x**(29/19)*(1+121/304*x*x)**(1181/2299)/(1-x*x)**1.5,0,e)[0]; t=12/19*c0**4/b*integral
    return t*u.s
@method(13,'P = (32/5)G⁴ m₁²m₂²(m₁+m₂)/(c⁵a⁵)','gravitational_wave_energy_loss({mass1:30 M_sun,mass2:30 M_sun,separation:1000 km})',model='Circular Newtonian quadrupole emitted power, positive energy loss rate')
def gravitational_wave_energy_loss(binary):
    a,b,r=globals()['binary'](binary); return 32/5*G**4*a*a*b*b*(a+b)/(C**5*r**5)*u.W
@method(13,'f_GW,ISCO = c³/[πGM(r_ISCO^(3/2)+χ_eff)]; χ_eff=(m₁χ₁+m₂χ₂)/M','merger_frequency(30 M_sun,30 M_sun,[0,0])',model='Effective-spin Kerr ISCO proxy, aligned spin components; not a calibrated full-GR merger-peak frequency')
def merger_frequency(mass1,mass2,spins,model='kerr_isco'):
    if len(spins)!=2: raise ValueError('Provide two aligned dimensionless spin components')
    m1=positive(M(mass1)); m2=positive(M(mass2)); chi=(m1*bounded_spin(spins[0])+m2*bounded_spin(spins[1]))/(m1+m2)
    if model=='schwarzschild_isco':
        if chi!=0: raise ValueError('schwarzschild_isco requires zero effective spin')
    elif model!='kerr_isco': raise ValueError('Supported ISCO proxy models: kerr_isco, schwarzschild_isco')
    radius=isco_radius(m1+m2,chi).value/(G*(m1+m2)/C**2)
    return C**3/(np.pi*G*(m1+m2)*(radius**1.5+chi))*u.Hz
@method(13,'f_220 = c³/(2πGM) [1.5251−1.1568(1−a*)^0.1292]','ringdown_frequency(60 M_sun,0.7)',model='Berti et al. fundamental Kerr l=m=2,n=0 fit; 0 ≤ spin < 0.99')
def ringdown_frequency(final_mass,final_spin,mode='220'):
    a=float(final_spin)
    if mode not in ('220',220) or not 0<=a<0.99: raise ValueError('Supported mode 220 with 0 ≤ final spin < 0.99')
    return C**3/(2*np.pi*G*positive(M(final_mass)))*(1.5251-1.1568*(1-a)**0.1292)*u.Hz
@method(13,'Leading chirp f(t), h_+(t)=A(t) cos φ(t), dφ/dt=2πf(t)','gravitational_waveform({mass1:30 M_sun,mass2:30 M_sun,separation:1000 km,distance:100 Mpc},[0 s,0.01 s,0.02 s,0.03 s])',visual='waveform',model='Leading Newtonian circular face-on inspiral only, terminated at Schwarzschild ISCO; no merger, ringdown or detector response')
def gravitational_waveform(binary,times,model='quadrupole'):
    if model!='quadrupole': raise ValueError('Supported model: quadrupole')
    m1,m2,a=globals()['binary'](binary); d=positive(D(binary['distance'])); ts=samples(times,'s')
    if len(ts)<2 or np.any(np.diff(ts)<=0) or ts[0]<0: raise ValueError('Waveform requires increasing nonnegative times')
    tc=inspiral_time(m1,m2,a).value; mc=chirp_mass(m1,m2).value
    if ts[-1]>=tc: raise ValueError('Requested time reaches formal coalescence; inspiral-only model')
    f=(5/(256*(tc-ts)))**(3/8)/np.pi*(G*mc/C**3)**(-5/8); limit=merger_frequency(m1,m2,[0,0]).value
    if np.any(f>=limit): raise ValueError('Requested waveform reaches ISCO; need full GR merger model')
    # Exact antiderivative of leading chirp avoids aliasing-induced phase integration errors.
    coeff=(5/256)**(3/8)/np.pi*(G*mc/C**3)**(-5/8); phase=2*np.pi*coeff*8/5*(tc**(5/8)-(tc-ts)**(5/8)); amp=4*(G*mc)**(5/3)*(np.pi*f)**(2/3)/(C**4*d); strain=amp*np.cos(phase)
    notes=[]
    if np.max(np.diff(ts))*max(f)>0.5: notes.append('Sample spacing undersamples the highest frequency; use finer times for faithful waveform rendering')
    return Output({'time':ts*u.s,'strain':strain,'frequency':f*u.Hz},plot=curve(ts,strain,'Time / s','Strain h₊','Newtonian quadrupole inspiral'),notes=notes)

# Grammar: nested calls, typed quantities, named args, lists, dictionaries and quoted file paths.
# No Python eval, code execution, URLs, or implicit catalogue queries.
UNIT_ALIASES={'M_sun':'solMass','Mearth':'earthMass','Rearth':'earthRad','Lsun':'solLum','Msun':'solMass','M☉':'solMass','M_earth':'earthMass','M⊕':'earthMass','M_J':'jupiterMass',
 'R_sun':'solRad','Rsun':'solRad','R☉':'solRad','R_earth':'earthRad','R⊕':'earthRad','R_J':'jupiterRad','L_sun':'solLum','L☉':'solLum','AU':'au','ly':'lyr','years':'yr','days':'day','°':'deg','μm':'um','µm':'um','°C':'deg_C','km s⁻¹':'km/s','m s⁻¹':'m/s'}
def split_top(s,separator=','):
    out=[]; start=0; stack=[]; quote=None; escaped=False
    for i,ch in enumerate(s):
        if quote:
            if escaped: escaped=False
            elif ch=='\\': escaped=True
            elif ch==quote: quote=None
        elif ch in "\"'": quote=ch
        elif ch in '([{': stack.append(ch)
        elif ch in ')]}':
            if not stack or '([{'.index(stack.pop())!=')]}'.index(ch): raise ValueError('Mismatched brackets')
        elif ch==separator and not stack: out.append(s[start:i].strip()); start=i+1
    if quote or stack: raise ValueError('Incomplete quoted string or brackets')
    out.append(s[start:].strip()); return out

def unit_quantity(s):
    s=s.replace('−','-').replace('×10^','e').replace('×10','e')
    # Unicode scientific notation in copied values.
    s=s.translate(str.maketrans('⁰¹²³⁴⁵⁶⁷⁸⁹⁻','0123456789-'))
    m=re.fullmatch(r'([+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?)\s*(.*)',s)
    if not m: return None
    n=float(m[1]); unit=m[2].strip()
    if not np.isfinite(n): raise ValueError('Input must be finite')
    if not unit: return n
    if unit=='c': return n*C*u.m/u.s
    for key in sorted(UNIT_ALIASES,key=len,reverse=True):
        unit=re.sub(r'(?<![A-Za-z_])'+re.escape(key)+r'(?![A-Za-z_])',UNIT_ALIASES[key],unit)
    try:
        q=n*u.Unit(unit)
        if q.unit==u.deg_C: q=q.to(u.K,equivalencies=u.temperature())
        return q
    except (ValueError,TypeError): return None

def parse_value(s,depth=0):
    if depth>24: raise ValueError('Nesting exceeds 24 levels')
    s=s.strip()
    if not s: raise ValueError('Missing argument')
    if s[0] in "\"'":
        out=ast.literal_eval(s)
        if not isinstance(out,str): raise ValueError('Expected string')
        return out
    if s.startswith('[') and s.endswith(']'): return [] if s=='[]' else [parse_value(v,depth+1) for v in split_top(s[1:-1])]
    if s.startswith('{') and s.endswith('}'):
        out={}
        for part in ([] if s=='{}' else split_top(s[1:-1])):
            pair=split_top(part,':')
            if len(pair)<2: raise ValueError('Object fields require key:value')
            key=pair[0].strip('"\' '); value=':'.join(pair[1:]); out[key]=parse_value(value,depth+1)
        return out
    call=re.fullmatch(r'([A-Za-z_][A-Za-z_0-9]*)\s*\((.*)\)',s,re.S)
    if call: return evaluate_call(call[1],call[2],depth+1)[0].value
    if s.lower() in BODY_DATA: return s.lower()
    if s in ('true','false'): return s=='true'
    if s in ('null','None'): return None
    if s=='pi': return np.pi
    if s.endswith('_orbit') and s[:-6] in BODY_DATA: return O(s[:-6])
    q=unit_quantity(s)
    if q is not None: return q
    if re.fullmatch(r'[A-Za-z_][A-Za-z_0-9 /-]*',s) or re.fullmatch(r'\d{4}-\d\d-\d\d(?:T[0-9:.]+Z?)?',s): return s
    # Permit only arithmetic numeric constants with safe AST.
    try: return expression_value(s,{'pi':np.pi})
    except Exception: raise ValueError('Cannot read argument: '+s[:100]) from None

def evaluate_call(name,inside,depth=0):
    name=name.lower().replace(' ','_'); key=name if name in REGISTRY else next((k for k,v in REGISTRY.items() if name in v['aliases']),None)
    if key is None: raise ValueError('Unknown astronomy method: '+name)
    meta=REGISTRY[key]; args=[]; kwargs={}
    for token in ([] if not inside.strip() else split_top(inside)):
        pair=split_top(token,'=')
        if len(pair)==2:
            k=pair[0]
            if k in kwargs: raise ValueError('Duplicate argument: '+k)
            kwargs[k]=parse_value(pair[1],depth+1)
        elif len(pair)==1:
            if kwargs: raise ValueError('Positional arguments must precede named arguments')
            args.append(parse_value(token,depth+1))
        else: raise ValueError('Invalid named argument')
    bound=inspect.signature(meta['fn']).bind(*args,**kwargs); bound.apply_defaults()
    with warnings.catch_warnings(record=True) as caught:
        warnings.simplefilter('always'); result=meta['fn'](*bound.args,**bound.kwargs)
    if not isinstance(result,Output): result=Output(result)
    result.notes += list(dict.fromkeys(str(w.message)[:500] for w in caught))
    if key in ('photon_sphere_radius','isco_radius'):
        mass_arg=bound.arguments['mass']; spin=bound.arguments.get('spin',0); rplus=G*M(mass_arg)/C**2*(1+np.sqrt(1-spin*spin))
        result.diagram={'kind':'black_hole','mass':M(mass_arg),'horizon':rplus,'isco':isco_radius(mass_arg,spin).value,'spin':spin}
        if spin==0: result.diagram['photon']=3*G*M(mass_arg)/C**2
    if key in ('orbital_period','orbital_velocity','kepler_third_law','circular_velocity','vis_viva'):
        if key in ('orbital_period','orbital_velocity') and not isinstance(bound.arguments['body'],u.Quantity):
            oo=O(bound.arguments['body'],bound.arguments.get('center'),bound.arguments.get('at','J2000'))
        else:
            aa=bound.arguments.get('semi_major_axis',bound.arguments.get('radius',bound.arguments.get('body')))
            cm=bound.arguments.get('central_mass',bound.arguments.get('center'))
            oo=O({'a':aa,'central_mass':cm})
        result.plot=orbit_plot(oo)
    if key=='stellar_luminosity':
        result.diagram={'kind':'hr','name':'Model star','temperature':T(bound.arguments['temperature']),'luminosity':result.value.to_value(u.W)/LS}
    if meta['category']==CATEGORIES[8]: result.notes.insert(0,'Cosmology: '+str(cosmology(bound.arguments.get('model','Planck18'))))
    if meta['category'] in (CATEGORIES[1],CATEGORIES[3],CATEGORIES[4]):
        result.notes.append('Epoch: '+str(bound.arguments.get('at',bound.arguments.get('datetime','J2000')))+'; '+EPHEMERIS_NOTE)
    if meta['visualization']=='cosmology' and 'z' in bound.arguments:
        z=Z(bound.arguments['z']); grid=np.linspace(0,max(z,0.1),160); model=bound.arguments.get('model','Planck18'); y=meta['fn'](grid,model) if False else [meta['fn'](float(v),model).to_value(u.Mpc) for v in grid]; result.plot=curve(grid,y,'Redshift z','Distance / Mpc',key)
    return result,meta,bound

def clean(value):
    if isinstance(value,Output): return clean(value.value)
    if isinstance(value,u.Quantity): return {'value':clean(value.value),'unit':str(value.unit)}
    if isinstance(value,Time): return {'datetime':value.isot,'scale':value.scale}
    if isinstance(value,np.ndarray): return clean(value.tolist())
    if isinstance(value,np.generic): return clean(value.item())
    if isinstance(value,dict): return {str(k):clean(v) for k,v in value.items()}
    if isinstance(value,(list,tuple)): return [clean(v) for v in value]
    if isinstance(value,float) and not np.isfinite(value): raise ValueError('Calculation produced non-finite value; check physical domain and input data')
    return value

def summary(v):
    if isinstance(v,u.Quantity):
        if v.isscalar: return f'{v.value:.8g} {v.unit}'
        return f'{v.size} samples / {v.unit}'
    if isinstance(v,(float,np.floating)): return f'{v:.8g}'
    if isinstance(v,np.ndarray): return f'Array {v.shape}'
    if isinstance(v,dict):
        if v.get('type')=='Orbit': return f"Orbit: a={v['a']/AU:.7g} AU, e={v['e']:.6g}, i={v['i']*180/np.pi:.6g} deg (ICRS)"
        return '; '.join(f'{k}: {summary(x)}' for k,x in list(v.items())[:6])
    if isinstance(v,list): return f'{len(v)} entries' if len(v)>5 else ', '.join(summary(x) for x in v)
    return str(v)

def worked_inputs(bound):
    lines=[]
    for key,value in bound.arguments.items():
        line=key+' = '+summary(value)
        if isinstance(value,u.Quantity): line+=' = '+summary(value.decompose())
        elif isinstance(value,str) and value in BODY_DATA:
            m,r,p,i,t,l=BODY_DATA[value]
            fields=[f'M={m:.9g} kg']
            if r is not None: fields.append(f'R={r:.9g} m')
            if t is not None: fields.append(f'T={t:.9g} K')
            if l is not None: fields.append(f'L={l:.9g} W')
            line+=' ('+', '.join(fields)+')'
        elif isinstance(value,dict) and value.get('type')=='Orbit':
            line+=f"; μ={value['mu']:.10g} m³/s²; epoch={value['epoch']} TDB"
        lines.append(line)
    return '; '.join(lines)

def constants_used(formula):
    symbols={'G':f'G={G:.10g} m³ kg⁻¹ s⁻²','c':f'c={C:.10g} m/s','σ':f'σ={SIGMA:.10g} W m⁻² K⁻⁴',
        'k_B':f'k_B={KB:.10g} J/K','ℏ':f'ℏ={c.hbar.value:.10g} J s','h':f'h={H:.10g} J s'}
    return '; '.join(value for key,value in symbols.items() if re.search(r'(?<![A-Za-z])'+re.escape(key)+r'(?![A-Za-z])',formula))

def run(text):
    if len(text)>32000: raise ValueError('Input exceeds 32000 characters; use FITS/CSV files for large data sets')
    text=text.strip().removeprefix('@').strip()
    # Supported natural-language shorthand retains typed inputs.
    text=re.sub(r'^([a-z_]+)\s+escape\s+(?:speed|velocity)$',r'escape_velocity(\1)',text,flags=re.I)
    call=re.fullmatch(r'([A-Za-z_ ]+)\s*\((.*)\)',text,re.S)
    if not call: raise ValueError('Expected method(arguments); type @ for the registry')
    result,meta,bound=evaluate_call(call[1].strip(),call[2])
    if meta['category'] in (CATEGORIES[0],CATEGORIES[1],CATEGORIES[3],CATEGORIES[4]): result.notes.append(EPHEMERIS_NOTE)
    shown=summary(result.value); value=None; unit=''
    if isinstance(result.value,u.Quantity) and result.value.isscalar: value=float(result.value.value); unit=str(result.value.unit)
    elif isinstance(result.value,(float,int,np.number)): value=float(result.value)
    payload={'ok':True,'method':meta['name'],'summary':shown,'value':value,'unit':unit,'result':clean(result.value),
      'uncertainty':clean(result.uncertainty),'model':meta['model'].replace('JPL DE440s',EPHEMERIS_NAME),'source':meta['source'],'notes':result.notes,
      'steps':[{'label':'Inputs and unit conversion','text':worked_inputs(bound)},
               {'label':'Physical model and formula','text':meta['formula'] + (('; '+constants_used(meta['formula'])) if constants_used(meta['formula']) else '')},
               {'label':'Evaluate with supplied values','text':'With '+worked_inputs(bound)+': '+meta['formula']+' → '+shown}],
      'plot':clean(result.plot),'diagram':clean(result.diagram)}
    if result.uncertainty is not None: payload['summary'] += ' ± '+summary(result.uncertainty)
    return payload

def public_registry():
    result=[]
    dimensions={
      'length':'radius diameter distance semi_major_axis periapsis apoapsis hill_sphere roche_limit sphere_of_influence stellar_radius wien_peak schwarzschild_radius photon_sphere_radius isco_radius kerr_horizon_radius einstein_radius length_contraction planet_radius_from_transit atmospheric_scale_height comoving_distance luminosity_distance angular_diameter_distance light_travel_distance distance_between_redshifts jeans_length bondi_radius tidal_disruption_radius frequency_to_wavelength particle_horizon parallax_distance',
      'mass':'mass minimum_planet_mass dynamical_mass virial_mass jeans_mass chirp_mass',
      'speed':'escape_velocity orbital_velocity circular_velocity vis_viva delta_v plane_change_delta_v rocket_equation stellar_escape_velocity radial_velocity_amplitude radial_velocity_from_shift hubble_law_velocity velocity_dispersion',
      'time':'light_time rotation_period orbital_period kepler_third_law synodic_period transfer_time burn_time stellar_lifetime special_relativistic_time_dilation black_hole_evaporation_time transit_duration exposure_time age_of_universe cosmic_age hubble_time lookback_time free_fall_time inspiral_time',
      'temperature':'effective_temperature hawking_temperature equilibrium_temperature cmb_temperature virial_temperature',
      'power':'luminosity stellar_luminosity eddington_luminosity gravitational_wave_energy_loss',
      'angle':'axial_tilt inclination true_anomaly mean_anomaly eccentric_anomaly angular_separation angular_size hour_angle elongation moon_phase sidereal_time local_sidereal_time atmospheric_refraction gravitational_lensing_angle rayleigh_resolution diffraction_limit field_of_view',
      'energy':'rest_energy relativistic_kinetic_energy photon_energy',
      'frequency':'wavelength_to_frequency gravitational_wave_frequency merger_frequency ringdown_frequency relativistic_doppler',
      'density':'density stellar_density planet_density critical_density matter_density dark_energy_density',
      'dimensionless':'eccentricity mass_ratio airmass moon_illumination apparent_magnitude absolute_magnitude distance_modulus bolometric_magnitude color_index lorentz_factor gravitational_redshift gravitational_time_dilation transit_depth transit_probability impact_parameter transmission_signal scale_factor redshift_from_scale_factor cosmological_distance_modulus metallicity_from_lines optical_depth redshift spectral_resolution flux_to_magnitude magnitude_difference signal_to_noise telescope_magnification focal_ratio light_gathering_power limiting_magnitude telescope_snr gravitational_wave_strain julian_date modified_julian_date julian_centuries'}
    for meta in REGISTRY.values():
        item={k:v for k,v in meta.items() if k!='fn'}
        item['returns']=next((kind for kind,names in dimensions.items() if meta['name'] in names.split()),'structured data / typed quantities')
        special={
          'einstein_radius':'angle','volume':'volume','surface_area':'area','surface_gravity':'acceleration',
          'thrust_acceleration':'acceleration','tidal_acceleration':'acceleration','stellar_surface_gravity':'acceleration',
          'mean_motion':'angular speed','specific_orbital_energy':'specific energy','specific_angular_momentum':'specific angular momentum',
          'blackbody_radiance':'spectral radiance per wavelength','stefan_boltzmann_flux':'energy flux','flux_from_luminosity':'energy flux',
          'orbital_insolation':'energy flux','black_hole_entropy':'entropy','hubble_parameter':'inverse time / Hubble rate',
          'comoving_volume':'volume','surface_brightness':'energy flux per solid angle','star_formation_rate_halpha':'mass flow rate',
          'equivalent_width':'length','line_broadening':'speed or temperature, by model','magnitude_to_flux':'same unit as zero_point',
          'extinction_correct':'same unit as flux','aperture_area':'area','pixel_scale':'angle per pixel','plate_scale':'angle per length',
          'minimum_planet_mass':'structured data: minimum mass, RV amplitude and systemic velocity'}
        if meta['name'] in special: item['returns']=special[meta['name']]
        result.append(item)
    return result

def main():
    if '--registry' in sys.argv: print(json.dumps(public_registry(),ensure_ascii=False,indent=2)); return
    for line in sys.stdin:
        try:
            request=json.loads(line)
            if not isinstance(request,dict): raise ValueError('Request must be a JSON object')
            response=run(str(request['text']))
        except Exception as e: response={'ok':False,'error':str(e),'type':type(e).__name__}
        print(json.dumps(response,ensure_ascii=False,allow_nan=False),flush=True)
if __name__=='__main__': main()
