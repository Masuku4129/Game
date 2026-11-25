import json,struct,numpy as np
def load(p):
    b=open(p,'rb').read()
    cl,_=struct.unpack('<II',b[12:20]); j=json.loads(b[20:20+cl])
    off=20+cl; bl,_=struct.unpack('<II',b[off:off+8]); bin_=b[off+8:off+8+bl]
    def acc(i):
        a=j['accessors'][i]; bv=j['bufferViews'][a['bufferView']]
        n={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}[a['type']]
        dt={5126:'<f4',5123:'<u2',5125:'<u4',5121:'u1',5120:'i1',5122:'<i2'}[a['componentType']]
        o=bv.get('byteOffset',0)+a.get('byteOffset',0)
        return np.frombuffer(bin_,dtype=dt,count=a['count']*n,offset=o).reshape(a['count'],n)
    def image(k):
        bv=j['bufferViews'][j['images'][k]['bufferView']]
        o=bv.get('byteOffset',0); return bin_[o:o+bv['byteLength']]
    return j,acc,image
