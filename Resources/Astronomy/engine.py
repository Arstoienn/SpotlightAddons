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
    intermediates: dict=field(default_factory=dict)

# Arguments that are one of a few words: completion offers exactly these, and the function refuses others.
CHOICES={
 ('compare','property'):['mass','radius','diameter','volume','density','surface_gravity','escape_velocity','luminosity'],
}
COSMOLOGY_MODELS=['Planck18','Planck15','WMAP9']

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
            if n=='epoch' and fn.__name__=='phase_fold': kind='time'
            if n=='opacity': kind='opacity'
            if n=='name' and fn.__name__=='body': kind='body'
            if n=='body' and fn.__name__ in ('orbit','orbital_elements','state_vector','orbital_period','orbital_velocity'): kind='satellite'
            if kind=='model': kind='cosmology_model' if cat==8 else 'model_'+fn.__name__
            item={'name':n,'kind':kind,'required':p.default is inspect.Parameter.empty}
            if p.default is not inspect.Parameter.empty: item['default']=str(p.default)
            choices=CHOICES.get((fn.__name__,n)) or (COSMOLOGY_MODELS if kind=='cosmology_model' else None)
            if choices: item['choices']=list(choices)
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


# The values a method looks up as it works, kept for the working: each body's property or each input,
# in SI, with what it is, as every lookup passes through Q, and every orbit through O. Reset for each
# calculation by run().
USED=[]
_lookup=Q
def Q(x,unit,prop=None):
    v=_lookup(x,unit,prop)
    if np.ndim(v)==0:
        body=B(x) if isinstance(x,str) and ALIASES.get(x,x) in BODY_DATA else None
        entry={'unit':unit if isinstance(unit,str) else u.Unit(unit).to_string(),'body':body,'prop':prop,'value':float(v)}
        if entry not in USED: USED.append(entry)
    return v
_orbit=O
def O(*args,**kwargs):
    o=_orbit(*args,**kwargs)
    if isinstance(o,dict) and o.get('type')=='Orbit':
        for key,unit in (('a','m'),('mu','m3/s2'),('e','')):
            entry={'unit':unit,'body':None,'prop':'orbit_'+key,'value':float(o[key])}
            if entry not in USED: USED.append(entry)
    return o

# A scalar quantity in SI, or None where its unit has no SI form, as pixels have not.
def in_si(q):
    try: return q.si if isinstance(q,u.Quantity) and q.isscalar else None
    except Exception: return None

# What each value used is, for the working: Mass of earth, Semi-major axis.
def used_values():
    kinds={'kg':'mass','K':'temperature','W':'luminosity','s':'time','rad':'angle','m/s':'speed','m3/s2':'mu','':'number',
           'N':'force','kg/s':'massflow','m/s2':'acceleration','Hz':'frequency','J':'energy','kg/m3':'density','W/m2':'flux','m2/kg':'opacity'}
    labels={'mass':'Mass','radius':'Radius','length':'Length','temperature':'Temperature','luminosity':'Luminosity','time':'Time',
            'angle':'Angle','speed':'Speed','mu':'Gravitational parameter GM','a':'Semi-major axis','number':'Number','force':'Force',
            'massflow':'Mass flow rate','acceleration':'Acceleration','frequency':'Frequency','energy':'Energy','density':'Density',
            'flux':'Flux','opacity':'Opacity','e':'Eccentricity'}
    units={'kg':'kg','m':'m','K':'K','W':'W','s':'s','rad':'rad','m/s':'m/s','m3/s2':'m³/s²'}
    out=[]
    for e in USED:
        kind='a' if e['prop']=='orbit_a' else 'radius' if e['unit']=='m' and e['prop']==1 else 'length' if e['unit']=='m' else kinds.get(e['unit'],'value')
        label=e.get('label') or (labels['e'] if e['prop']=='orbit_e' else labels.get(kind,'Value'))+(' of '+e['body'] if e['body'] else '')
        out.append({'kind':kind,'label':label,'value':e['value'],'unit':units.get(e['unit'],e['unit'])})
    return [v for v in out if math.isfinite(v['value'])][:16]

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
def light_time(body1,body2,at='J2000'):
    separation = distance(body1,body2,at)
    return Output(separation/c.c,intermediates={'Geometric distance':separation})
@method(0,'Property ratio = p₁ / p₂','compare(earth, jupiter, radius)',visual='comparison')
def compare(body1,body2,property='radius'):
    allowed={name:globals()[name] for name in CHOICES[('compare','property')]}
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
@method(1,'P = 2π√(a³/μ)','orbital_period(earth)',aliases=['kepler','period'])
def orbital_period(body,center=None):
    if isinstance(body,u.Quantity): return kepler_third_law(body,center)
    o=O(body,center); return 2*np.pi*np.sqrt(o['a']**3/o['mu'])*u.s
@method(1,'v = |v(t)| from osculating state','orbital_velocity(earth, at="2026-11-11")')
def orbital_velocity(body,at='J2000'): return norm(O(body,at=at)['v'])*u.m/u.s
@method(1,'P² = 4π²a³/(GM)','kepler_third_law(1 AU, sun)')
def kepler_third_law(semi_major_axis,central_mass): return 2*np.pi*np.sqrt(positive(D(semi_major_axis))**3/(G*positive(M(central_mass))))*u.s
def semi_major_axis(orbit): return O(orbit)['a']*u.m

def anomaly_at(o,at):
    o=O(o); m=o['mean_anomaly']
    if at is not None: m+=np.sqrt(o['mu']/o['a']**3)*(date(at).tdb-date(o['epoch'],'tdb')).to_value(u.s)
    m=(m+np.pi)%(2*np.pi)-np.pi; e=o['e']; E=brentq(lambda x:x-e*np.sin(x)-m,-2*np.pi,2*np.pi)
    nu=2*np.arctan2(np.sqrt(1+e)*np.sin(E/2),np.sqrt(1-e)*np.cos(E/2)); return nu,m,E
# Transfers: ideal Keplerian maneuvers. Structured inputs retain center μ.
def transfer_orbits(a,b):
    a=O(a); b=O(b)
    if not np.isclose(a['mu'],b['mu'],rtol=1e-3): raise ValueError('Transfer orbits must have the same central mass')
    if a['e']>1e-3 or b['e']>1e-3: raise ValueError('Ideal transfer requires circular orbits (e ≤ 0.001); supply explicit circular Orbit objects')
    if abs(a['i']-b['i'])>1e-6: raise ValueError('Ideal transfer requires coplanar orbits')
    return a['a'],b['a'],a['mu']

# Observing: all times UTC unless explicit Time object, angles are quantities (bare = radians).
def position(body,at,observer):
    q=coord(body,at,observer); aa=q.transform_to(AltAz(obstime=date(at),location=observer_location(observer),pressure=0*u.hPa))
    return {'ra':q.ra,'dec':q.dec,'altitude':aa.alt,'azimuth':aa.az,'at_UTC':date(at).utc.isot,'equatorial_frame':q.frame.name,'horizontal_frame':'AltAz, vacuum'}

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
@method(3,'Geocentric ecliptic longitude difference (Moon − Sun) mod 360°','moon_phase("2026-11-11")')
def moon_phase(at):
    frame=GeocentricTrueEcliptic(equinox=date(at)); m=coord('moon',at).transform_to(frame); s=coord('sun',at).transform_to(frame)
    return (m.lon-s.lon).wrap_at(360*u.deg)

@method(3,'d_pc = 1/p_arcsec','parallax_distance(100 mas)',kinds={'parallax':'parallax'})
def parallax_distance(parallax):
    if isinstance(parallax,str) and B(parallax) in STAR_COORDS: return STAR_COORDS[B(parallax)][2]*u.pc
    return (1/positive(Q(parallax,'arcsec')))*u.pc

@method(5,'L = 4πR²σT⁴','stellar_luminosity(1 R_sun,5772 K)')
def stellar_luminosity(radius,temperature): return 4*np.pi*positive(R(radius))**2*SIGMA*positive(T(temperature))**4*u.W
@method(5,'λ_max T = 2.897771955×10⁻³ m K','wien_peak(5772 K)',visual='blackbody',aliases=['wien','peak_wavelength'])
def wien_peak(temperature): return Output(c.b_wien/positive(T(temperature))/u.K,plot=blackbody_spectrum(temperature).plot)
@method(5,'Sample Planck B_λ across 0.1–10 times the Wien wavelength','blackbody_spectrum(5772 K)',visual='blackbody',aliases=['blackbody'])
def blackbody_spectrum(temperature):
    t=positive(T(temperature)); peak=c.b_wien.value/t; x=np.geomspace(peak/10,peak*10,300); y=2*H*C*C/(x**5*np.expm1(H*C/(x*KB*t)))
    return Output({'peak_wavelength':peak*u.m,'wavelength':x*u.m,'radiance':y*u.W/u.m**3/u.sr},plot=curve(x/1e-9,y,'Wavelength / nm','Bλ / W m⁻³ sr⁻¹','Planck spectrum'))
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
def distance_modulus(distance): return 5*np.log10(positive(D(distance))/(10*PC))
@method(5,'Place (T_eff, L/L☉) in H–R diagram','hr_position(sun)',visual='hr',model='Catalogue estimates; schematic main-sequence reference, not a stellar evolution track')
def hr_position(star):
    t=T(star); l=L(star)/LS; return Output({'temperature':t*u.K,'luminosity_solar':l},diagram={'kind':'hr','name':B(star),'temperature':t,'luminosity':l})

@method(6,'r_s = 2GM/c²','schwarzschild_radius(10 M_sun)',visual='black_hole',model='Schwarzschild: nonrotating, uncharged, isolated black hole',aliases=['schwarzschild','event_horizon','black_hole'])
def schwarzschild_radius(mass):
    rs=2*G*positive(M(mass))/C**2
    return Output(rs*u.m,diagram={'kind':'black_hole','mass':M(mass),'horizon':rs,'photon':1.5*rs,'isco':3*rs,'spin':0})
def isco_radius(mass,spin=0):
    a=bounded_spin(spin); z1=1+np.cbrt(1-a*a)*(np.cbrt(1+a)+np.cbrt(1-a)); z2=np.sqrt(3*a*a+z1*z1)
    return G*positive(M(mass))/C**2*(3+z2-np.sign(a)*np.sqrt((3-z1)*(3+z1+2*z2)))*u.m

def schwarz_factor(mass,r):
    rs=2*G*positive(M(mass))/C**2; r=positive(D(r))
    if r<=rs: raise ValueError('Static Schwarzschild observer must lie outside event horizon')
    return np.sqrt(1-rs/r)
@method(6,'γ = 1/√(1−v²/c²)','lorentz_factor(0.8 c)')
def lorentz_factor(velocity): return 1/np.sqrt(1-beta(velocity)**2)
@method(6,'E₀ = mc²','rest_energy(1 kg)')
def rest_energy(mass): return positive(M(mass))*C**2*u.J

# Exoplanets: use supplied observer inclination, not the ICRS orbit inclination as transit geometry.
def transit_parameters(planet,star,o,geometry=None):
    import batman
    o=O(o); g=geometry or {}; p=batman.TransitParams(); p.t0=seconds(g.get('epoch',0))/86400; p.per=2*np.pi*np.sqrt(o['a']**3/o['mu'])/86400; p.rp=R(planet)/R(star); p.a=o['a']/R(star)
    p.inc=Q(g.get('inclination',90*u.deg),'deg');
    if not 0<=p.inc<=90: raise ValueError('Transit observer inclination must lie in [0,90] degrees')
    p.ecc=o['e']; p.w=Q(g.get('argp',o.get('argp',0)*u.rad),'deg'); p.limb_dark='quadratic'; p.u=g.get('limb_darkening',[0.3,0.2]); return p

# Cosmology: model choice is explicit in every result; no user-blocking first-use dialog.
def cosmo(model='Planck18'):
    if isinstance(model,dict): return FlatLambdaCDM(H0=Q(model['H0'],'km/s/Mpc')*u.km/u.s/u.Mpc,Om0=float(model['Om0']),Tcmb0=T(model.get('Tcmb0',2.7255))*u.K,name='Custom flat ΛCDM')
    if model not in ('Planck18','Planck15','WMAP9'): raise ValueError('model must be Planck18, Planck15, WMAP9, or {H0,Om0,Tcmb0}')
    return {'Planck18':Planck18,'Planck15':Planck15,'WMAP9':WMAP9}[model]
def Z(z):
    z=float(z)
    if z<0 or not np.isfinite(z): raise ValueError('Cosmological redshift must be finite and ≥ 0')
    return z
def cosmology(model='Planck18'):
    m=cosmo(model); return {'name':m.name,'H0':m.H0,'Om0':m.Om0,'Ode0':m.Ode0,'Tcmb0':m.Tcmb0,'Ob0':m.Ob0}

@method(10,'z = (λ_observed − λ_emitted)/λ_emitted','redshift(500 nm,600 nm)',visual='spectrum',model='Dimensionless spectral redshift; not automatically a recession velocity')
def redshift(emitted_wavelength,observed_wavelength):
    em=positive(Q(emitted_wavelength,'m')); ob=positive(Q(observed_wavelength,'m')); z=ob/em-1
    return Output(z,diagram={'kind':'spectrum','emitted':em,'observed':ob,'z':z})

def noise_rates(source,instrument,conditions):
    # Inputs in detected electrons/s; throughput maps incident source to detected source.
    s=positive(Q(source['rate'] if isinstance(source,dict) else source,'1/s'))*fraction(instrument.get('throughput',1)); n=positive(float(instrument.get('pixels',1))); sky=Q(conditions.get('sky_rate',0),'1/s'); dark=Q(instrument.get('dark_rate',0),'1/s'); read=float(instrument.get('read_noise',0)); exposures=int(instrument.get('exposures',1))
    if sky<0 or dark<0 or read<0 or exposures<1: raise ValueError('Noise rates must be nonnegative and exposure count positive')
    return s,n*(sky+dark),n*read**2*exposures
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
def wcs_object(wcs):
    from astropy.wcs import WCS
    if isinstance(wcs,str):
        from astropy.io import fits
        return WCS(fits.getheader(wcs))
    return WCS(wcs)
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

# Gravitational waves: deliberately model-labelled leading-order predictions.
def binary(b):
    m1=positive(M(b['mass1'])); m2=positive(M(b['mass2'])); a=positive(D(b['separation'])); return m1,m2,a

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

# Many values, as how many and between what: 451 values from 0.0001 to 0.03 Hz.
def span(values,unit=None):
    a=np.asarray(values,dtype=float).ravel(); finite=a[np.isfinite(a)]
    if not finite.size: return f'{a.size} values'
    tail=f' {unit}' if unit is not None and str(unit) else ''
    return f'{a.size} values from {finite.min():.6g} to {finite.max():.6g}{tail}'

def summary(v):
    if isinstance(v,u.Quantity):
        if v.isscalar: return f'{v.value:.8g} {v.unit}'
        return span(v.value,v.unit)
    if isinstance(v,(float,np.floating)): return f'{v:.8g}'
    if isinstance(v,np.ndarray): return span(v) if v.ndim==1 and np.issubdtype(v.dtype,np.number) else f'Array {v.shape}'
    if isinstance(v,dict):
        if v.get('type')=='Orbit': return f"Orbit: a={v['a']/AU:.7g} AU, e={v['e']:.6g}, i={v['i']*180/np.pi:.6g} deg (ICRS)"
        return '; '.join(f'{k}: {summary(x)}' for k,x in list(v.items())[:6])
    if isinstance(v,list): return f'{len(v)} entries' if len(v)>5 else ', '.join(summary(x) for x in v)
    return str(v)

def working_value(value):
    if isinstance(value, u.Quantity) and value.isscalar:
        return summary(value)
    if isinstance(value, (np.ndarray, u.Quantity)) and value.ndim == 1:
        if value.size <= 6:
            return '[' + ', '.join(summary(item) for item in value) + ']'
        return summary(value) if isinstance(value, u.Quantity) else span(value)
    return summary(value)

def worked_inputs(bound):
    rows=[]
    for key,value in bound.arguments.items():
        if value is None:
            continue
        detail=''
        if isinstance(value,u.Quantity):
            shown=summary(value)
            si=summary(value.decompose())
            if si!=shown:
                detail=si
        elif isinstance(value,list) and value and all(isinstance(row,list) for row in value):
            width=len(value[0])
            if not all(len(row)==width for row in value):
                shown=f'{len(value)} rows'
            elif key=='image':
                shown=f'{width} × {len(value)} pixels'
            else:
                shown=f'{len(value)} × {width}'
        elif isinstance(value,dict) and value.get('type')=='Orbit':
            shown=summary(value)
            detail=f"μ = {value['mu']:.10g} m³/s² · {value['epoch']} TDB"
        elif isinstance(value,dict):
            shown='\n'.join(f'{name} = {working_value(item)}' for name,item in list(value.items())[:6])
            if len(value)>6:
                detail=f'{len(value)-6} more fields in the query'
        else:
            shown=working_value(value)
        rows.append({'name':key,'value':shown,'detail':detail})
    return rows

def constants_used(formula):
    symbols={'G':f'{G:.10g} m³ kg⁻¹ s⁻²','c':f'{C:.10g} m/s','σ':f'{SIGMA:.10g} W m⁻² K⁻⁴',
        'k_B':f'{KB:.10g} J/K','ℏ':f'{c.hbar.value:.10g} J s','h':f'{H:.10g} J s'}
    return [{'name':key,'value':value} for key,value in symbols.items()
            if re.search(r'(?<![A-Za-z_])'+re.escape(key)+r'(?![A-Za-z_]|\s*=)',formula)
            and not re.search(r'(?<![A-Za-z_])'+re.escape(key)+r'\s*=',formula)]

def run(text):
    if len(text)>32000: raise ValueError('Input exceeds 32000 characters; use FITS/CSV files for large data sets')
    text=text.strip().removeprefix('@').strip()
    # Supported natural-language shorthand retains typed inputs.
    text=re.sub(r'^([a-z_]+)\s+escape\s+(?:speed|velocity)$',r'escape_velocity(\1)',text,flags=re.I)
    call=re.fullmatch(r'([A-Za-z_ ]+)\s*\((.*)\)',text,re.S)
    if not call: raise ValueError('Expected method(arguments); type @ for the registry')
    USED.clear()
    result,meta,bound=evaluate_call(call[1].strip(),call[2])
    if meta['category'] in (CATEGORIES[0],CATEGORIES[1],CATEGORIES[3],CATEGORIES[4]) and not any(EPHEMERIS_NOTE in note for note in result.notes):
        result.notes.append(EPHEMERIS_NOTE)
    # A value typed in is named after its argument: Semi major axis, not Length.
    for key,arg in bound.arguments.items():
        if in_si(arg) is not None:
            si=float(in_si(arg).value)
            for entry in USED:
                if entry['body'] is None and 'label' not in entry and abs(entry['value']-si)<=1e-12*max(abs(si),1e-300):
                    entry['label']=key.replace('_',' ').capitalize()
    # What the method worked out on the way, as values used too: light_time's distance.
    for name,item in result.intermediates.items():
        if in_si(item) is not None:
            si=in_si(item); key=si.unit.to_string()
            unit={'m':'m','s':'s','kg':'kg','K':'K','m / s':'m/s','kg m2 / s3':'W'}.get(key,key)
            USED.append({'unit':unit,'body':None,'prop':None,'value':float(si.value),'label':name})
    used=used_values()
    shown=summary(result.value); value=None; unit=''
    if isinstance(result.value,u.Quantity) and result.value.isscalar: value=float(result.value.value); unit=str(result.value.unit)
    elif isinstance(result.value,(float,int,np.number)): value=float(result.value)
    if result.uncertainty is not None:
        shown+=' ± '+summary(result.uncertainty)
    # The answer in SI units, which the formula gives with the values used in SI: what the working's substitution must reach.
    si_value=None; si_unit=''
    if in_si(result.value) is not None and np.isfinite(float(in_si(result.value).value)):
        si=in_si(result.value); si_value=float(si.value)
        # W m⁻², not kg s⁻³: the unit as the method gives it, where it is already SI.
        si_unit=(result.value.unit if abs(result.value.unit.to(si.unit)-1)<1e-12 else si.unit).to_string('unicode')
    elif isinstance(result.value,(float,int,np.number)) and not isinstance(result.value,bool): si_value=float(result.value)
    inputs=worked_inputs(bound)
    formula=meta['formula']
    constants=constants_used(formula)
    intermediate=[{'name':key,'value':summary(item)} for key,item in result.intermediates.items()]
    results=[]
    if isinstance(result.value,dict) and result.value.get('type')!='Orbit':
        results=[{'name':key,'value':working_value(item)} for key,item in list(result.value.items())[:12]]
        if len(result.value)>12:
            results.append({'name':'','value':f'{len(result.value)-12} more fields in the copied result'})
    payload={'ok':True,'method':meta['name'],'summary':shown,'value':value,'unit':unit,'result':clean(result.value),
      'uncertainty':clean(result.uncertainty),'model':meta['model'].replace('JPL DE440s',EPHEMERIS_NAME),'source':meta['source'],'notes':result.notes,
      'working':{'inputs':inputs,'formula':formula,'constants':constants,'intermediates':intermediate,'results':results,'values':used,
                 'si':si_value,'si_unit':si_unit},
      'steps':[{'label':'Inputs and unit conversion','text':'\n'.join(row['name']+' = '+row['value']+('\n'+row['detail'] if row['detail'] else '') for row in inputs)},
               {'label':'Physical model and formula','text':'\n'.join([formula]+[row['name']+' = '+row['value'] for row in constants])},
               {'label':'Result','text':'\n'.join([row['name']+' = '+row['value'] for row in intermediate]+[shown])}],
      'plot':clean(result.plot),'diagram':clean(result.diagram)}
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
        # Written inside the same guard: a value that cannot be written (too large, or not a number)
        # is an answer refused, not a worker gone.
        try: text=json.dumps(response,ensure_ascii=False,allow_nan=False)
        except (ValueError,TypeError):
            text=json.dumps({'ok':False,'error':'The result is beyond the numbers that can be written: too large, or not a number.','type':'OverflowError'})
        print(text,flush=True)
if __name__=='__main__': main()
