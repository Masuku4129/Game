import sys; sys.path.insert(0,'/home/claude/proj/tools')
from retarget_clips import *
from render_pose import Renderer
import matplotlib; matplotlib.use('Agg'); import matplotlib.pyplot as plt
A='/home/claude/proj/assets/'
src=Src(SRC); rig=Rig(A+'mita_rig.glb'); rd=Renderer(A+'mita_rig.glb'); sv=Solver(rig)
def sheet(clip,loop,fn,nshow=8,view='side'):
    fr,info=retarget(src,rig,clip,loop)
    idx=np.linspace(0,len(fr)-1,nshow).astype(int)
    fig,ax=plt.subplots(1,nshow,figsize=(2.6*nshow,5.2))
    for a,k in zip(ax,idx):
        D,P=sv.solve(fr[k]); v=rd.skin(sv.skin_matrices(D,P))
        rd.draw(a,v,view,title=f'{clip} {k}/{len(fr)}')
        c=fr[k].hips_pos; a.set_xlim((c[2] if view=='side' else c[0])-1.2,(c[2] if view=='side' else c[0])+1.2); a.set_ylim(-0.05,2.0)
    plt.tight_layout(); plt.savefig(fn,dpi=50); plt.close(); print(clip,info)
if __name__=='__main__':
    for c,l in [('walk-loop',1),('run-loop',1),('idle-loop',1),('jump',0),('dodge',0)]:
        sheet(c,bool(l),f'/home/claude/work/c_{c}.png')
