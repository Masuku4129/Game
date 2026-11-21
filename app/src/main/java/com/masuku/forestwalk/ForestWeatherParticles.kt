package com.masuku.forestwalk

import android.opengl.GLES20
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import java.util.Random
import javax.microedition.khronos.opengles.GL10
import javax.microedition.khronos.egl.EGLConfig

/** Bounded, reusable weather particles. Coordinates are player-relative to keep effects centered. */
internal class ForestWeatherParticles {
    private data class P(var x:Float,var y:Float,var z:Float,var speed:Float,var phase:Float)
    private val rng=Random(5128)
    private val rain=ArrayList<P>(240)
    private val snow=ArrayList<P>(160)
    private var program=0
    private var posAttr=0
    private var colorUniform=0
    private var vpUniform=0
    private lateinit var rainBuffer:FloatBuffer
    private lateinit var snowBuffer:FloatBuffer
    private val shaderV="""attribute vec3 aPos;uniform mat4 uVP;void main(){gl_Position=uVP*vec4(aPos,1.0);gl_PointSize=3.0;}"""
    private val shaderF="""precision mediump float;uniform vec4 uColor;void main(){gl_FragColor=uColor;}"""
    fun init(){
        for(i in 0 until 240)rain.add(P(rng.nextFloat()*30f-15f,3f+rng.nextFloat()*19f,rng.nextFloat()*30f-15f,9f+rng.nextFloat()*5f,rng.nextFloat()))
        for(i in 0 until 160)snow.add(P(rng.nextFloat()*30f-15f,2f+rng.nextFloat()*20f,rng.nextFloat()*30f-15f,1f+rng.nextFloat()*2.2f,rng.nextFloat()))
        rainBuffer=directFloat(240*2*3);snowBuffer=directFloat(160*3)
        program=link(shaderV,shaderF);posAttr=GLES20.glGetAttribLocation(program,"aPos");colorUniform=GLES20.glGetUniformLocation(program,"uColor");vpUniform=GLES20.glGetUniformLocation(program,"uVP")
    }
    fun render(vp:FloatArray,px:Float,pz:Float,dt:Float,mode:Int){
        if(mode!=1&&mode!=2)return
        GLES20.glUseProgram(program);GLES20.glUniformMatrix4fv(vpUniform,1,false,vp,0)
        GLES20.glEnable(GLES20.GL_BLEND);GLES20.glBlendFunc(GLES20.GL_SRC_ALPHA,GLES20.GL_ONE_MINUS_SRC_ALPHA)
        if(mode==1){
            var k=0
            for(p in rain){p.y-=p.speed*dt;p.x+=.7f*dt;if(p.y<0){p.y=16f+rng.nextFloat()*8f;p.x=rng.nextFloat()*30f-15f;p.z=rng.nextFloat()*30f-15f}
                rainBuffer.put(k++,px+p.x);rainBuffer.put(k++,p.y);rainBuffer.put(k++,pz+p.z
                );rainBuffer.put(k++,px+p.x+.025f);rainBuffer.put(k++,p.y+.45f);rainBuffer.put(k++,pz+p.z}
            rainBuffer.position(0);GLES20.glUniform4f(colorUniform,.63f,.72f,.82f,.65f);GLES20.glEnableVertexAttribArray(posAttr);GLES20.glVertexAttribPointer(posAttr,3,GLES20.GL_FLOAT,false,0,rainBuffer);GLES20.glDrawArrays(GLES20.GL_LINES,0,480)
        }else{
            var k=0
            for(p in snow){p.y-=p.speed*dt;p.x+=sin(p.phase+p.y)*.3f*dt;p.z+=cos(p.phase+p.y)*.2f*dt;if(p.y<0){p.y=17f+rng.nextFloat()*7f;p.x=rng.nextFloat()*30f-15f;p.z=rng.nextFloat()*30f-15f}
                snowBuffer.put(k++,px+p.x);snowBuffer.put(k++,p.y);snowBuffer.put(k++,pz+p.z}
            snowBuffer.position(0);GLES20.glUniform4f(colorUniform,.94f,.96f,1f,.92f);GLES20.glEnableVertexAttribArray(posAttr);GLES20.glVertexAttribPointer(posAttr,3,GLES20.GL_FLOAT,false,0,snowBuffer);GLES20.glDrawArrays(GLES20.GL_POINTS,0,160)
        }
        GLES20.glDisableVertexAttribArray(posAttr);GLES20.glDisable(GLES20.GL_BLEND)
    }
    private fun directFloat(size:Int)=ByteBuffer.allocateDirect(size*4).order(ByteOrder.nativeOrder()).asFloatBuffer()
    private fun compile(type:Int,src:String):Int{val s=GLES20.glCreateShader(type);GLES20.glShaderSource(s,src);GLES20.glCompileShader(s);val ok=IntArray(1);GLES20.glGetShaderiv(s,GLES20.GL_COMPILE_STATUS,ok,0);if(ok[0]==0)throw RuntimeException(GLES20.glGetShaderInfoLog(s));return s}
    private fun link(v:String,f:String):Int{val p=GLES20.glCreateProgram();GLES20.glAttachShader(p,compile(GLES20.GL_VERTEX_SHADER,v));GLES20.glAttachShader(p,compile(GLES20.GL_FRAGMENT_SHADER,f));GLES20.glLinkProgram(p);val ok=IntArray(1);GLES20.glGetProgramiv(p,GLES20.GL_LINK_STATUS,ok,0);if(ok[0]==0)throw RuntimeException(GLES20.glGetProgramInfoLog(p));return p}
}
