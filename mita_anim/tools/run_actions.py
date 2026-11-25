import sys; sys.path.insert(0,'.')
import numpy as np
from rig import Rig
from solver import *
from anim_actions import ActionAnimator
from render_pose import Renderer
import matplotlib; matplotlib.use('Agg'); import matplotlib.pyplot as plt
A='/home/claude/proj/assets/'
rig=Rig(A+'mita_rig.glb'); rd=Renderer(A+'mita_rig.glb'); an=ActionAnimator(rig,A+'actions.json')
dt=1/60; fr=[]
def tick(dirv=None,spd=0):
    P=an.update(dt,dirv,spd); D,Pp=an.sv.solve(P)
    fr.append((an.pos.copy(),rd.skin(an.sv.skin_matrices(D,Pp)),an.act['phase'] if an.act else '-',an.root_y))
def seq(name,T,dirv=None,spd=0):
    n0=len(fr); an.start(name)
    for _ in range(int(T/dt)): tick(dirv,spd)
    return n0
for _ in range(60): tick()
res={}
res['punch']=seq('punch',0.7)
for _ in range(40): tick()
res['spinkick']=seq('spinkick',1.2)
for _ in range(40): tick()
res['roll']=seq('roll',1.0,(0,1),3.0)
for _ in range(60): tick((0,1),4.5)
def sheet(name,times,fn,hmax=2.2):
    fig,ax=plt.subplots(1,len(times),figsize=(4.2*len(times),8))
    for a,t in zip(ax,times):
        k=res[name]+int(t/dt); pos,v,ph,ry=fr[k]
        rd.draw(a,v,'side',title=f'{name} t={t:.2f} {ph}')
        a.set_xlim(pos[2]-1.3,pos[2]+1.3); a.set_ylim(-0.05,hmax)
    plt.tight_layout(); plt.savefig(fn,dpi=55); plt.close()
sheet('punch',[0.05,0.13,0.2,0.26,0.4,0.6],'/home/claude/work/punch.png')
sheet('spinkick',[0.1,0.25,0.4,0.52,0.6,0.7,0.9],'/home/claude/work/kick.png')
sheet('roll',[0.05,0.15,0.25,0.35,0.45,0.55,0.65,0.8],'/home/claude/work/roll.png')
print('ok')
