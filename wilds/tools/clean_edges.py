import sys, glob, numpy as np
from PIL import Image
from scipy import ndimage as ndi
BAND=float(sys.argv[1]); 
for pat in sys.argv[2:]:
    for f in glob.glob(pat):
        a=np.array(Image.open(f).convert("RGBA")).astype(float)
        solid=a[...,3]>200
        dd=ndi.distance_transform_edt(solid)
        interior=dd>BAND
        if interior.sum()<50: continue
        _,(iy,ix)=ndi.distance_transform_edt(~interior,return_indices=True)
        band=(a[...,3]>0)&~interior
        for c in range(3):
            near=a[...,c][iy,ix]
            a[...,c][band]=np.minimum(a[...,c][band],near[band]+10)
        Image.fromarray(a.clip(0,255).astype(np.uint8),"RGBA").save(f)
