# 8 кадров удара -> 24 кадра: промежуточные по оптическому потоку (OpenCV DIS).
import json, re, numpy as np, cv2
from PIL import Image
SRC="tools/atk8/"; OUT="art/atk/"
GAPS=[2,2,3,3,2,2,2]      # сколько промежуточных между ключевыми кадрами (итого 8+16=24)
DOWN=0.75                 # уменьшение: на экране всё равно меньше 1 px на px исходника
txt=open(SRC+"atk_data.gd").read()
data=json.loads(txt[txt.index("{"):])
dis=cv2.DISOpticalFlow_create(cv2.DISOPTICAL_FLOW_PRESET_MEDIUM)
def gray(p):
    a=p[...,3:4]
    return np.clip(p[...,3]*200+0.3*p[...,:3].mean(axis=2),0,255).astype(np.uint8)
out={}
for v,info in data.items():
    fr=info["frames"]; ims=[Image.open(SRC+f[0]).convert("RGBA") for f in fr]
    L=int(max(f[1] for f in fr))+8; U=int(max(f[2] for f in fr))+8
    R=int(max(i.width-f[1] for i,f in zip(ims,fr)))+8; D=int(max(i.height-f[2] for i,f in zip(ims,fr)))+8
    W,H=L+R,U+D
    P=[]
    for im,f in zip(ims,fr):
        c=Image.new("RGBA",(W,H),(0,0,0,0)); c.paste(im,(int(round(L-f[1])),int(round(U-f[2]))))
        a=np.array(c).astype(np.float32); a[...,:3]*=a[...,3:4]/255.0; a[...,3]/=255.0
        P.append(a)       # premultiplied: rgb 0..255*alpha, a 0..1
    seq=[P[0]]; key=[0]
    gx,gy=np.meshgrid(np.arange(W,dtype=np.float32),np.arange(H,dtype=np.float32))
    for k in range(7):
        a0,a1=P[k],P[k+1]
        f01=dis.calc(gray(a0),gray(a1),None); f10=dis.calc(gray(a1),gray(a0),None)
        n=GAPS[k]
        for j in range(1,n+1):
            t=j/(n+1)
            w0=cv2.remap(a0,gx-t*f01[...,0],gy-t*f01[...,1],cv2.INTER_LINEAR,borderMode=cv2.BORDER_CONSTANT)
            w1=cv2.remap(a1,gx-(1-t)*f10[...,0],gy-(1-t)*f10[...,1],cv2.INTER_LINEAR,borderMode=cv2.BORDER_CONSTANT)
            seq.append((1-t)*w0+t*w1)
        seq.append(a1); key.append(len(seq)-1)
    frames=[]
    for i,p in enumerate(seq):
        al=np.clip(p[...,3],0,1)
        rgb=np.where(al[...,None]>0.02,p[...,:3]/np.maximum(al[...,None],0.02),0)
        al=np.where(al<0.08,0,al)
        rgba=np.dstack([rgb.clip(0,255),al*255]).astype(np.uint8)
        ys,xs=np.where(rgba[...,3]>8)
        x0,x1,y0,y1=xs.min(),xs.max()+1,ys.min(),ys.max()+1
        im=Image.fromarray(rgba[y0:y1,x0:x1],"RGBA")
        px,py=L-x0,U-y0
        im=im.resize((max(1,round(im.width*DOWN)),max(1,round(im.height*DOWN))),Image.LANCZOS)
        name=f"slash_{v}_{i}.png"; im.save(OUT+name)
        frames.append([name,float(round(px*DOWN,1)),float(round(py*DOWN,1))])
    out[v]={"scale":float(round(info["scale"]/DOWN,4)),"frames":frames,"key":key}
    print(v,len(frames),key)
import glob,os
for f in glob.glob(OUT+"slash_*.png"):
    n=int(re.search(r"_(\d+)\.png",f).group(1))
open(OUT+"atk_data.gd","w").write("# сгенерировано tools/interp.py\nconst DATA := "+json.dumps(out)+"\n")
