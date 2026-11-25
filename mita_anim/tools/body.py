"""Body proxy capsules (used for cloak classification and collision). Radii in metres."""
import numpy as np
# (name, bone_a, bone_b, radius)  -- segment from bone_a head to bone_b head (rest pose)
CAPS = [
 ('thighL','LeftUpLeg','LeftLeg',0.105),
 ('shinL','LeftLeg','LeftFoot',0.078),
 ('thighR','RightUpLeg','RightLeg',0.105),
 ('shinR','RightLeg','RightFoot',0.078),
 ('pelvis','Hips','Spine02',0.145),
 ('abdomen','Spine02','Spine01',0.135),
 ('chest','Spine01','Spine',0.14),
 ('upper','Spine','neck',0.14),
 ('armL','LeftArm','LeftForeArm',0.07),
 ('forearmL','LeftForeArm','LeftHand',0.055),
 ('armR','RightArm','RightForeArm',0.07),
 ('forearmR','RightForeArm','RightHand',0.055),
 ('head','neck','Head',0.12),
]
def seg_dist(P, a, b):
    ab = b - a
    t = np.clip(((P - a) @ ab) / (ab @ ab), 0, 1)
    c = a + t[:, None] * ab
    return np.linalg.norm(P - c, axis=1)
