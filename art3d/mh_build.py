import json, numpy as np, struct, sys
from pygltflib import *
SC=0.1
# --- obj
V=[];F=[];G={};cur=None
for l in open('/tmp/mh/base.obj'):
    if l.startswith('v '): V.append([float(x) for x in l.split()[1:4]])
    elif l.startswith('g '): cur=l.split()[1]; G[cur]=[]
    elif l.startswith('f '):
        f=[int(p.split('/')[0])-1 for p in l.split()[1:]]
        G[cur].append(f)
V=np.array(V)*SC
# цели: женская грудь (необязательно)
def apply_target(path,w=1.0):
    n=0
    for l in open(path):
        if l.startswith('#') or not l.strip(): continue
        p=l.split()
        if len(p)>=4:
            V[int(p[0])]+=np.array([float(p[1]),float(p[2]),float(p[3])])*SC*w; n+=1
    return n
print('breast',apply_target('/tmp/mh/female-young-averagemuscle-averageweight-maxcup-averagefirmness.target',0.2))
V[:,1]-=V[:13380,1].min()
# спрямляем «песочные часы»: бёдра и ягодицы уже, талия плотнее
yy=V[:,1]
k=np.exp(-((yy-0.92)/0.16)**2)
V[:,0]*=1-0.17*k
V[:,2]=V[:,2]*(1-0.10*k)
kw=np.exp(-((yy-1.12)/0.1)**2)
V[:,0]*=1+0.05*kw
print('bbox',V[:13380].min(0),V[:13380].max(0))
# тело + глаза (если есть), зубы без
used=['body']
tris=[]
for g in used:
    for f in G[g]:
        if len(f)==4: tris+= [[f[0],f[1],f[2]],[f[0],f[2],f[3]]]
        else: tris.append(f)
tris=np.array(tris)
# --- скелет
sk=json.load(open('/tmp/mh/default.mhskel'))
bones=sk['bones']; joints=sk['joints']
def jp(name): return V[joints[name]].mean(0)
order=[]
def add(b):
    if b in order: return
    p=bones[b]['parent']
    if p: add(p)
    order.append(b)
for b in bones: add(b)
bi={b:i for i,b in enumerate(order)}
head={b:jp(bones[b]['head']) for b in order}
tail={b:jp(bones[b]['tail']) for b in order}
# --- веса
W=json.load(open('/tmp/mh/default_weights.mhw'))['weights']
nv=len(V)
infl=[[] for _ in range(nv)]
for b,lst in W.items():
    if b not in bi: continue
    for v,w in lst: infl[v].append((bi[b],w))
J=np.zeros((nv,4),np.uint16); WT=np.zeros((nv,4),np.float32)
for v in range(nv):
    l=sorted(infl[v],key=lambda x:-x[1])[:4]
    if not l: l=[(bi[order[0]],1.0)]
    s=sum(w for _,w in l)
    for k,(j,w) in enumerate(l): J[v,k]=j; WT[v,k]=w/s
# --- перенумерация вершин, только используемые
uv=np.unique(tris); remap=-np.ones(nv,int); remap[uv]=np.arange(len(uv))
P=V[uv]; Jn=J[uv]; Wn=WT[uv]; T=remap[tris]
# доминирующая кость -> регион
names=np.array(order)
dom=names[Jn[np.arange(len(uv)),0]]
def region(b):
    if any(k in b for k in ['head','neck','jaw','eye','tongue','oculi','orbicularis','levator','oris','temporalis','risorius','special']): return 'skin'
    if 'finger' in b or 'metacarpal' in b or b.startswith('hand') or b.startswith('wrist') : return 'skin'
    if 'toe' in b or 'foot' in b: return 'boot'
    return 'cloth'
reg=np.array([region(b) for b in dom])
print({r:int((reg==r).sum()) for r in set(reg)})
# нормали
N=np.zeros_like(P)
for a,b,c in T:
    n=np.cross(P[b]-P[a],P[c]-P[a]); N[a]+=n;N[b]+=n;N[c]+=n
N/=np.linalg.norm(N,axis=1,keepdims=True)+1e-9
# объём одежды: смещение по нормали
hips_y=head[order[bi['spine05']] if 'spine05' in bi else order[0]][1] if False else head['root'][1] if 'root' in head else 0.95
off=np.zeros(len(P))
y=P[:,1]
for i,r in enumerate(reg):
    if r=='cloth':
        b=dom[i]
        if 'leg' in b or 'upperleg' in b:
            t=np.clip((0.95-y[i])/0.9,0,1)
            off[i]=0.016+0.04*t   # штаны расширяются вниз
        elif 'arm' in b or 'shoulder' in b or 'clavicle' in b:
            off[i]=0.012+0.012*np.clip((abs(P[i,0])-0.2)/0.4,0,1)  # рукава
        else:
            off[i]=0.02
    elif r=='boot': off[i]=0.012
P=P+N*off[:,None]
col={'skin':[1.0,0.84,0.74],'cloth':[0.075,0.062,0.15],'boot':[0.05,0.04,0.09]}
C=np.array([col[r]+[1.0] for r in reg],np.float32)
# --- glTF
bin=bytearray()
def bv(arr,target=None):
    global bin
    while len(bin)%4: bin.append(0)
    off=len(bin); bin.extend(arr.tobytes())
    return BufferView(buffer=0,byteOffset=off,byteLength=arr.nbytes,target=target)
g=GLTF2()
g.scenes=[Scene(nodes=[0])]
nodes=[]
# узел 0: корень сцены с мешем и скином; кости идут следом
root=Node(name='MitaBody',mesh=0,skin=0,children=[])
nodes.append(root)
bone_nodes=[]
for b in order:
    p=bones[b]['parent']
    loc=head[b]-(head[p] if p else np.zeros(3))
    nodes.append(Node(name=b,translation=[float(x) for x in loc],children=[]))
for b in order:
    p=bones[b]['parent']
    if p: nodes[1+bi[p]].children.append(1+bi[b])
    else: root_bones=1+bi[b]
nodes[0].children=[1+i for i,b in enumerate(order) if not bones[b]['parent']]
g.nodes=nodes
# IBM
ibm=np.zeros((len(order),16),np.float32)
for b in order:
    m=np.eye(4); m[:3,3]=-head[b]
    ibm[bi[b]]=m.T.reshape(16)
g.skins=[Skin(joints=[1+i for i in range(len(order))],inverseBindMatrices=3+0,skeleton=nodes[0].children[0])]
bvs=[]
def addbv(arr,target=None):
    bvs.append(bv(arr,target)); return len(bvs)-1
Pf=P.astype(np.float32)
ib=T.astype(np.uint32).reshape(-1)
a_pos=addbv(Pf,34962); a_nor=addbv(N.astype(np.float32),34962); a_col=addbv(C,34962)
a_j=addbv(Jn.astype(np.uint16),34962); a_w=addbv(Wn,34962); a_i=addbv(ib,34963); a_ibm=addbv(ibm)
g.bufferViews=bvs
g.accessors=[
 Accessor(bufferView=a_pos,componentType=5126,count=len(Pf),type='VEC3',min=Pf.min(0).tolist(),max=Pf.max(0).tolist()),
 Accessor(bufferView=a_nor,componentType=5126,count=len(Pf),type='VEC3'),
 Accessor(bufferView=a_col,componentType=5126,count=len(Pf),type='VEC4'),
 Accessor(bufferView=a_j,componentType=5123,count=len(Pf),type='VEC4'),
 Accessor(bufferView=a_w,componentType=5126,count=len(Pf),type='VEC4'),
 Accessor(bufferView=a_i,componentType=5125,count=len(ib),type='SCALAR'),
 Accessor(bufferView=a_ibm,componentType=5126,count=len(order),type='MAT4'),
]
g.skins[0].inverseBindMatrices=6
g.materials=[Material(name='body',pbrMetallicRoughness=PbrMetallicRoughness(baseColorFactor=[1,1,1,1],metallicFactor=0.0,roughnessFactor=0.8))]
g.meshes=[Mesh(primitives=[Primitive(attributes=Attributes(POSITION=0,NORMAL=1,COLOR_0=2,JOINTS_0=3,WEIGHTS_0=4),indices=5,material=0)])]
g.buffers=[Buffer(byteLength=len(bin))]
g.set_binary_blob(bytes(bin))
g.save_binary('/home/claude/game/mita3d/models/MhBody.glb')
json.dump({'order':order,'head':{b:head[b].tolist() for b in order},'tail':{b:tail[b].tolist() for b in order}},open('/home/claude/game/mita3d/models/mh_bones.json','w'))
print('bones',len(order),'verts',len(P),'tris',len(T))
