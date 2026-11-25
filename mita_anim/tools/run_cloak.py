import sys; sys.path.insert(0,'.')
import numpy as np, time
from rig import Rig
from solver import *
from animator import Animator
from cloak import Cloak
from render_pose import Renderer
import matplotlib; matplotlib.use('Agg'); import matplotlib.pyplot as plt
A='/home/claude/proj/assets/'
rig=Rig(A+'mita_rig.glb'); rd=Renderer(A+'mita_rig.glb'); an=Animator(rig); ck=Cloak(rig,A+'cloak.json',A+'cloak_vtx.bin')
dt=1/60; fr=[]; stats=[]
def run(T,dirv,spd):
    for _ in range(int(T/dt)):
        P=an.update(dt,dirv,spd); D,Pp=an.sv.solve(P)
        t0=time.time(); disp=ck.step(dt,D,Pp); t1=time.time()-t0
        v=rd.skin(an.sv.skin_matrices(D,Pp))+ck.vertex_disp(disp)
        fr.append((an.pos.copy(),v,np.linalg.norm(an.vel), np.abs(disp).max(), t1))
run(1.0,None,0); run(3.0,(0,1),1.4); run(3.0,(0,1),6.0); run(2.0,(1,0),6.0); run(2.0,None,0)
print('max disp',max(f[3] for f in fr),'sim ms (numpy)',np.mean([f[4] for f in fr])*1000)
sel=[0.9,3.0,5.0,6.5,8.2,9.5,10.0,10.3,10.6,11.0,12.0]
fig,ax=plt.subplots(2,6,figsize=(26,10))
for a,t in zip(ax.ravel(),sel):
    k=min(int(t/dt),len(fr)-1); pos,v,sp,_,_=fr[k]
    rd.draw(a,v,'side' if t<9.8 else 'front',title=f't={t:.1f} v={sp:.1f}')
    c=pos[2] if t<9.8 else pos[0]
    a.set_xlim(c-1.0,c+1.0); a.set_ylim(-0.05,2.1)
plt.tight_layout(); plt.savefig('/home/claude/work/cloak_seq.png',dpi=42)
