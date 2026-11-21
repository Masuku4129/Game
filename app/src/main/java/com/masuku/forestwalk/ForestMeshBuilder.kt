package com.masuku.forestwalk

import kotlin.math.*
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer

/**
 * CPU-side geometry accumulator for Forest Walk's batched GLES renderer.
 * Components are merged into one mesh to avoid one draw call per primitive.
 */
internal class ForestMeshBuilder {
    private val vertices = ArrayList<Float>(8192)
    private val indices = ArrayList<Short>(12288)
    private var vertexCount = 0

    fun clear() { vertices.clear(); indices.clear(); vertexCount = 0 }

    private fun vertex(x:Float,y:Float,z:Float,nx:Float,ny:Float,nz:Float,color:Int) {
        val r=((color ushr 16) and 255)/255f
        val g=((color ushr 8) and 255)/255f
        val b=(color and 255)/255f
        vertices.add(x); vertices.add(y); vertices.add(z)
        vertices.add(nx); vertices.add(ny); vertices.add(nz)
        vertices.add(r); vertices.add(g); vertices.add(b)
        vertexCount++
    }

    fun triangle(a:FloatArray,b:FloatArray,c:FloatArray,color:Int) {
        val ux=b[0]-a[0]; val uy=b[1]-a[1]; val uz=b[2]-a[2]
        val vx=c[0]-a[0]; val vy=c[1]-a[1]; val vz=c[2]-a[2]
        var nx=uy*vz-uz*vy; var ny=uz*vx-ux*vz; var nz=ux*vy-uy*vx
        val l=sqrt(nx*nx+ny*ny+nz*nz).coerceAtLeast(1e-6f); nx/=l; ny/=l; nz/=l
        val base=vertexCount
        vertex(a[0],a[1],a[2],nx,ny,nz,color)
        vertex(b[0],b[1],b[2],nx,ny,nz,color)
        vertex(c[0],c[1],c[2],nx,ny,nz,color)
        indices.add(base.toShort()); indices.add((base+1).toShort()); indices.add((base+2).toShort())
    }

    /** UV-less latitude/longitude ellipsoid; smooth per-vertex normals. */
    fun ellipsoid(cx:Float,cy:Float,cz:Float,rx:Float,ry:Float,rz:Float,color:Int,segments:Int=12,rings:Int=8) {
        val start=vertexCount
        for(r in 0..rings) {
            val phi=PI*r/rings
            val sy=cos(phi).toFloat()
            val ring=sin(phi).toFloat()
            for(s in 0..segments) {
                val theta=2.0*PI*s/segments
                val sx=(ring*cos(theta)).toFloat(); val sz=(ring*sin(theta)).toFloat()
                val nx=sx/rx.coerceAtLeast(1e-4f); val ny=sy/ry.coerceAtLeast(1e-4f); val nz=sz/rz.coerceAtLeast(1e-4f
                val nl=sqrt(nx*nx+ny*ny+nz*nz).coerceAtLeast(1e-6f)
                vertex(cx+sx*rx,cy+sy*ry,cz+sz*rz,nx/nl,ny/nl,nz/nl,color)
            }
        }
        for(r in 0 until rings) for(s in 0 until segments) {
            val a=start+r*(segments+1)+s
            val b=a+segments+1
            indices.add(a.toShort()); indices.add(b.toShort()); indices.add((a+1).toShort())
            indices.add((a+1).toShort()); indices.add(b.toShort()); indices.add((b+1).toShort())
        }
    }

    /** Tapered branch/trunk with smooth radial normals. */
    fun taperedCylinder(ax:Float,ay:Float,az:Float,bx:Float,by:Float,bz:Float,r0:Float,r1:Float,color:Int,segments:Int=9) {
        val vx=bx-ax; val vy=by-ay; val vz=bz-az
        val len=sqrt(vx*vx+vy*vy+vz*vz).coerceAtLeast(1e-5f)
        val ux=vx/len; val uy=vy/len; val uz=vz/len
        val refX=if(abs(uy)<.9f) 0f else 1f; val refY=if(abs(uy)<.9f) 1f else 0f; val refZ=0f
        var nx=uy*refZ-uz*refY; var ny=uz*refX-ux*refZ; var nz=ux*refY-uy*refX
        val nl=sqrt(nx*nx+ny*ny+nz*nz).coerceAtLeast(1e-5f); nx/=nl; ny/=nl; nz/=nl
        val tx=uy*nz-uz*ny; val ty=uz*nx-ux*nz; val tz=ux*ny-uy*nx
        val start=vertexCount
        for(end in 0..1) for(s in 0..segments) {
            val ang=2.0*PI*s/segments; val cs=cos(ang).toFloat(); val sn=sin(ang).toFloat()
            val qx=nx*cs+tx*sn; val qy=ny*cs+ty*sn; val qz=nz*cs+tz*sn
            val radius=if(end==0) r0 else r1
            vertex((if(end==0)ax else bx)+qx*radius,(if(end==0)ay else by)+qy*radius,(if(end==0)az else bz)+qz*radius,qx,qy,qz,color)
        }
        for(s in 0 until segments) {
            val a=start+s; val b=start+segments+1+s
            indices.add(a.toShort()); indices.add(b.toShort()); indices.add((a+1).toShort())
            indices.add((a+1).toShort()); indices.add(b.toShort()); indices.add((b+1).toShort())
        }
    }

    fun snapshot(): ForestMesh {
        val v=ByteBuffer.allocateDirect(vertices.size*4).order(ByteOrder.nativeOrder()).asFloatBuffer()
        for(f in vertices) v.put(f)
        v.position(0)
        val ix=ShortArray(indices.size) { indices[it] }
        val ib=ByteBuffer.allocateDirect(ix.size*2).order(ByteOrder.nativeOrder()).asShortBuffer()
        ib.put(ix); ib.position(0)
        return ForestMesh(v,ib,vertexCount,ix.size)
    }
}

internal data class ForestMesh(val vertexBuffer:FloatBuffer,val indexBuffer:java.nio.ShortBuffer,val vertexCount:Int,val indexCount:Int)
