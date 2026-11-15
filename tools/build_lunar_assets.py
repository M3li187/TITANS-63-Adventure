"""Derive a real Fra Mauro terrain crop from the NASA LROC Apollo 14 DTM.
Usage: python tools/build_lunar_assets.py /path/to/downloaded_dem.tif /path/to/ortho.tif /path/to/user_moon.glb
The originals remain unchanged. This script uses Pillow/numpy/scipy only.
"""
from pathlib import Path
import json,struct,sys,hashlib,math,shutil
import numpy as np
from PIL import Image,TiffImagePlugin
from scipy.ndimage import uniform_filter
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'assets/moon';OUT.mkdir(exist_ok=True,parents=True)
dem_path=Path(sys.argv[1]);ortho_path=Path(sys.argv[2]);user_path=Path(sys.argv[3])
lat,lon=-3.64530,342.52864;radius=1737400.0
im=Image.open(dem_path);tags=im.tag_v2;dx,dy,_=tags[33550];_,_,_,x0,y0,_=tags[33922]
# The source label and GeoTIFF specify Equirectangular Moon: standard parallel -3,
# central meridian 180, spherical radius 1737400m; northing is R*latitude.
x=radius*math.cos(math.radians(-3))*math.radians(lon-180);y=radius*math.radians(lat)
col=round((x-x0)/dx-.5);row=round((y0-y)/dy-.5);half=256;box=(col-half,row-half,col+half+1,row+half+1)
assert box[0]>=0 and box[1]>=0 and box[2]<=im.width and box[3]<=im.height
crop=im.crop(box);h=np.asarray(crop,dtype='<f4');assert np.isfinite(h).all() and h.min()>-10000
ref=float(h[half,half]);relative=h-ref
(OUT/'fra_mauro_heights.f32').write_bytes(relative.astype('<f4').tobytes())
gz,gx=np.gradient(h,dy,dx);slope=np.degrees(np.arctan(np.hypot(gx,gz)))
(OUT/'fra_mauro_slopes.f32').write_bytes(slope.astype('<f4').tobytes())
# Store a small georeferenced source subset for traceability, not the 119MB source.
newtags=TiffImagePlugin.ImageFileDirectory_v2()
for k in [33550,34735,34736,34737,42113]:
 if k in tags:newtags[k]=tags[k]
newtags[33922]=(0.,0.,0.,x0+box[0]*dx,y0-box[1]*dy,0.)
crop.save(OUT/'fra_mauro_source_crop.tif',tiffinfo=newtags,compression='tiff_deflate')
o=Image.open(ortho_path);oscale=o.tag_v2[33550];otie=o.tag_v2[33922]
assert abs(oscale[0]-dx)<1e-5 and abs(otie[3]-x0)<.01 and abs(otie[4]-y0)<.01, 'Orthophoto must use matching grid'
texture=o.crop(box).convert('RGB');texture.save(OUT/'fra_mauro_ortho.png')
# Color visualization only; numeric slopes remain in the .f32 file.
r=np.clip(slope/18,0,1);rgb=np.stack([r,.7*(1-r)+.12,.32*(1-r)+.12],axis=-1);Image.fromarray((rgb*255).astype('uint8')).save(OUT/'fra_mauro_slope_preview.png')
# Extract supplied surface detail and repair missing UVs by using it in a
# world-space material in Godot. The supplied model is not asserted as NASA data.
b=user_path.read_bytes();jlen=struct.unpack_from('<I',b,12)[0];glb=json.loads(b[20:20+jlen]);blob=b[jlen+28:];view=glb['bufferViews'][glb['images'][0]['bufferView']];off=view.get('byteOffset',0);(OUT/'user_moon_surface.jpg').write_bytes(blob[off:off+view['byteLength']])
# Pick a low-slope 16m neighborhood within the authored clear-zone region.
score=uniform_filter(slope,size=9,mode='nearest');mask=np.zeros_like(score,dtype=bool);mask[half-50:half,half+20:half+55]=True
best=np.unravel_index(np.argmin(np.where(mask,score,np.inf)),score.shape);clear=[float((best[1]-half)*dx),float((best[0]-half)*dy)]
meta={'dataset':'NAC_DTM_APOLLO14','product_version':'v1.9','source_url':'https://data.lroc.im-ldi.com/lroc/view_rdr/NAC_DTM_APOLLO14','download_url':'https://pds.mcp.nasa.gov/data/store/img/lunar_reconnaissance_orbiter/pds4/lroc/lro-l-lroc-5-rdr/LROLRC_2001/DATA/SDP/NAC_DTM/APOLLO14/NAC_DTM_APOLLO14.TIF','source_sha256':hashlib.sha256(dem_path.read_bytes()).hexdigest(),'orthophoto_product':'NAC_DTM_APOLLO14_M150633128_2M','orthophoto_source_sha256':hashlib.sha256(ortho_path.read_bytes()).hexdigest(),'retrieved_date':'2026-11-15','crop_pixel_box':list(box),'grid_size':513,'sample_spacing_m':dx,'width_between_samples_m':512*dx,'center_reported_lat_deg':lat,'center_lon_east_deg':lon,'reference_elevation_m':ref,'source_elevation_min_m':float(h.min()),'source_elevation_max_m':float(h.max()),'slope_min_deg':float(slope.min()),'slope_max_deg':float(slope.max()),'slope_median_deg':float(np.median(slope)),'height_encoding':'Little-endian float32, row-major, north at first row. Relative to reference_elevation_m.','axis_mapping':'X east, Y relative elevation, Z south; centered at crop middle sample.','clear_zone_local_xz_m':clear,'clear_zone_mean_slope_deg':float(score[best]),'visual_extensions':'Background outside the measured crop and individual rocks are authored procedural scenery. User texture is blended only as decorative surface detail.','safety_note':'Clear-zone selection is a gameplay illustration, not a validated spacecraft landing assessment. Historic landing coordinates may differ from modern cartographic solutions.'}
(OUT/'terrain_metadata.json').write_text(json.dumps(meta,indent=2))
print(json.dumps(meta,indent=2))
