import sys; sys.path.insert(0,'.')
import numpy as np
from rig import Rig
from solver import *
from animator import Animator
from render_pose import Renderer
import matplotlib; matplotlib.use('Agg'); import matplotlib.pyplot as plt
glb='/home/claude/proj/assets/mita_rig.glb'
rig=Rig(glb); rd=Renderer(glb); an=Animator(rig)
dt=1/60
frames=[]; log=[]
def run(T, dirv, spd):
    for _ in range(int(T/dt)):
        P=an.update(dt, dirv, spd); D,Pp=an.sv.solve(P); frames.append((an.pos.copy(), an.sv.skin_matrices(D,Pp), an.vel.copy())); log.append((an.pos[2],np.linalg.norm(an.vel),an.pel.x[1],an.feet['L'].planted,an.feet['R'].planted, an.feet['L'].pos[2], an.feet['R'].pos[2]))
run(1.0,None,0)
run(4.0,(0,1),1.4)
run(3.5,(0,1),5.0)
run(2.5,None,0)
log=np.array(log)
sel=[0.9,1.9,2.2,2.5,3.0,4.0,6.0,7.0,8.0,9.0,9.5,10.5]
fig,ax=plt.subplots(2,6,figsize=(24,9))
for a,t in zip(ax.ravel(),sel):
    k=min(int(t/dt),len(frames)-1); pos,M,vel=frames[k]
    v=rd.skin(M)
    rd.draw(a,v,'side',title=f't={t:.1f}s v={np.linalg.norm(vel):.1f}')
    a.set_xlim(pos[2]-1.0,pos[2]+1.0); a.set_ylim(-0.05,2.1)
plt.tight_layout(); plt.savefig('/home/claude/work/walk_seq.png',dpi=45)
# foot sliding check: planted foot speed
import collections
slide=[]
for k in range(1,len(log)):
    for fi,pl in ((5,3),(6,4)):
        if log[k][pl] and log[k-1][pl]: slide.append(abs(log[k][fi]-log[k-1][fi])/dt)
print('max planted foot slide', max(slide) if slide else 0)
print('speed at t=3',log[int(3/dt)][1],'t=7',log[int(7/dt)][1], 'hips y range walk', log[int(2/dt):int(5/dt),2].min(), log[int(2/dt):int(5/dt),2].max(),' run', log[int(6/dt):int(8/dt),2].min(), log[int(6/dt):int(8/dt),2].max())
