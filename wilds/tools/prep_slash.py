# Нарезка листов ударов art/source/slash_<вид>.png (4x2 кадра на белом) -> art/atk/
import numpy as np, json, sys
from PIL import Image
from scipy import ndimage as ndi
VIEWS=["e","se","s","ne","n"]
out={}
for v in VIEWS:
    im=Image.open(f"art/source/slash_{v}.png").convert("RGB"); a=np.array(im).astype(float)
    H,W=a.shape[:2]; mn=a.min(axis=2)
    lab,n=ndi.label(mn>=238); sizes=ndi.sum(np.ones_like(mn),lab,range(1,n+1))
    bg=np.isin(lab,[i+1 for i,s in enumerate(sizes) if s>40])
    fg=~bg
    fg=ndi.binary_opening(fg,iterations=1)|ndi.binary_closing(fg,iterations=1)&fg
    blobs=None
    for sz in (31,21,13,9,5,3):
        d=ndi.maximum_filter(fg.astype(np.uint8),size=sz)>0
        l2,n2=ndi.label(d)
        areas=ndi.sum(fg,l2,range(1,n2+1))
        idx=[i+1 for i,s in enumerate(areas) if s>4000]
        if len(idx)==8: blobs=(l2,idx); break
    if blobs is None:
        # соприкасающиеся кадры: разрываем контакт эрозией, остальное отдаём ближайшему ядру
        l2,n2=ndi.label(ndi.maximum_filter(fg.astype(np.uint8),size=3)>0)
        for it in range(1,12):
            core=ndi.binary_erosion(fg,iterations=it)
            lc,nc=ndi.label(core); ar=ndi.sum(core,lc,range(1,nc+1))
            keep=[i+1 for i,s in enumerate(ar) if s>3000]
            if len(keep)==8: break
        else:
            print("FAIL",v,len(keep)); sys.exit(1)
        lc=np.where(np.isin(lc,keep),lc,0)
        _,(iy,ix)=ndi.distance_transform_edt(lc==0,return_indices=True)
        l2=np.where(fg,lc[iy,ix],0); idx=keep
        print(v,"split by erosion",it)
    else:
        l2,idx=blobs
    cm={i:ndi.center_of_mass(l2==i) for i in idx}
    top=sorted([i for i in idx if cm[i][0]<H/2],key=lambda i:cm[i][1])
    bot=sorted([i for i in idx if cm[i][0]>=H/2],key=lambda i:cm[i][1])
    order=top+bot
    assert len(top)==4 and len(bot)==4,(v,len(top),len(bot))
    def box(i):
        ys,xs=np.where((l2==i)&fg); return xs.min(),ys.min(),xs.max(),ys.max()
    b0=box(order[0]); b7=box(order[7])
    h1=b0[3]-b0[1]
    def foot(i,b):
        ys,xs=np.where((l2==i)&fg); lo=ys>b[3]-0.12*(b[3]-b[1]); return xs[lo].mean()
    fx0=foot(order[0],b0); fx7=foot(order[7],b7)
    CW=W/4
    # опорная точка в координатах клетки
    ref=[(fx0-0*CW,b0[3]),(fx7-3*CW,b7[3])]
    dist=ndi.distance_transform_edt(fg)  # внутри фигуры: расстояние до фона
    frames=[]
    for k,i in enumerate(order):
        col=k%4; row=k//4
        px_abs=col*CW+ref[row][0]; py_abs=ref[row][1]
        m=(l2==i)&fg
        ys,xs=np.where(m); x0,x1,y0,y1=xs.min()-4,xs.max()+5,ys.min()-4,ys.max()+5
        x0=max(x0,0);y0=max(y0,0);x1=min(x1,W);y1=min(y1,H)
        # учесть опорную точку в обрезке
        c=a[y0:y1,x0:x1].copy(); mm=m[y0:y1,x0:x1]; dd=dist[y0:y1,x0:x1]
        al=np.where(mm,1.0,0.0)
        band=mm&(dd<=2.5)
        al[band]=np.clip((250-c.min(axis=2)[band])/60.0,0,1)
        low=band&(al<0.95)
        for ch,vv in enumerate((16,16,38)):
            c[...,ch][low]=c[...,ch][low]*0.4+vv*0.6
        rgba=np.dstack([c,al*255]).clip(0,255).astype(np.uint8)
        name=f"slash_{v}_{k}.png"
        Image.fromarray(rgba,"RGBA").save("art/atk/"+name)
        frames.append([name,float(round(px_abs-x0,1)),float(round(py_abs-y0,1))])
    out[v]={"scale":float(round(120.0/h1,4)),"frames":frames}
    print(v,"h1",h1,"scale",out[v]["scale"])
with open("art/atk/atk_data.gd","w") as f:
    f.write("# сгенерировано tools/prep_slash.py\nconst DATA := "+json.dumps(out)+"\n")
