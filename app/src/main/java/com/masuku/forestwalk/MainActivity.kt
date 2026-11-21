package com.masuku.forestwalk

import android.app.Activity
import android.os.Bundle
import android.opengl.GLSurfaceView
import android.view.MotionEvent
import android.view.View
import android.widget.FrameLayout
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Color
import android.view.Gravity
import android.widget.TextView
import kotlin.math.*

class MainActivity : Activity() {
    private lateinit var game: ForestView
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.decorView.systemUiVisibility = (View.SYSTEM_UI_FLAG_FULLSCREEN or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY or View.SYSTEM_UI_FLAG_LAYOUT_STABLE or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN)
        val root = FrameLayout(this)
        game = ForestView(this)
        root.addView(game)
        val pad = Joystick(this) { x, y -> game.moveX = x; game.moveY = y }
        val p = FrameLayout.LayoutParams(260,260, Gravity.BOTTOM or Gravity.LEFT)
        p.leftMargin = 34; p.bottomMargin = 28
        root.addView(pad,p)
        val hint = TextView(this).apply { text="FOREST WALK"; setTextColor(Color.WHITE); textSize=13f; alpha=.72f; setPadding(24,16,24,16) }
        root.addView(hint, FrameLayout.LayoutParams(-2,-2,Gravity.TOP or Gravity.LEFT))
        setContentView(root)
    }
    override fun onPause(){ super.onPause(); game.onPause() }
    override fun onResume(){ super.onResume(); game.onResume() }
}

class Joystick(ctx: android.content.Context, val changed:(Float,Float)->Unit): View(ctx) {
    private val p=Paint(3)
    private var dx=0f; private var dy=0f
    override fun onDraw(c:Canvas) {
        val r=min(width,height)*.43f; val cx=width/2f; val cy=height/2f
        p.color=0x55333333; c.drawCircle(cx,cy,r,p)
        p.color=0x88FFFFFF.toInt(); c.drawCircle(cx,cy,r*.48f,p)
        p.color=0xCCFFFFFF.toInt(); c.drawCircle(cx+dx*r*.58f,cy+dy*r*.58f,r*.24f,p)
    }
    override fun onTouchEvent(e:MotionEvent):Boolean {
        val r=min(width,height)*.43f; val cx=width/2f; val cy=height/2f
        if(e.action==MotionEvent.ACTION_UP || e.action==MotionEvent.ACTION_CANCEL){dx=0f;dy=0f;changed(0f,0f)}
        else { dx=((e.x-cx)/r).coerceIn(-1f,1f); dy=((e.y-cy)/r).coerceIn(-1f,1f); val l=sqrt(dx*dx+dy*dy); if(l>1){dx/=l;dy/=l}; changed(dx,-dy) }
        invalidate(); return true
    }
}

class ForestView(ctx:android.content.Context): GLSurfaceView(ctx) {
    val renderer3d=ForestRenderer()
    @Volatile var moveX=0f
    @Volatile var moveY=0f
    init { setEGLContextClientVersion(2); setRenderer(renderer3d); renderMode=RENDERMODE_CONTINUOUSLY }
    override fun onDrawFrameDummy() {}
    override fun onTouchEvent(e:MotionEvent)=super.onTouchEvent(e)
    override fun onResume(){super.onResume()}
    override fun onPause(){super.onPause()}
}

class ForestRenderer: android.opengl.GLSurfaceView.Renderer {
    @Volatile var mx=0f
    @Volatile var my=0f
    private var program=0
    private var pos=0
    private var col=0
    private var angle=0f
    private var px=0f
    private var pz=0f
    private var last=System.nanoTime()
    private val objects=ArrayList<Obj>()
    data class Obj(val x:Float,val z:Float,val type:Int,val scale:Float,val seed:Float)
    private val vShader="""attribute vec3 aPos; uniform mat4 uMVP; void main(){ gl_Position=uMVP*vec4(aPos,1.0); }"""
    private val fShader="""precision mediump float; uniform vec4 uColor; void main(){ gl_FragColor=uColor; }"""
    override fun onSurfaceCreated(gl:javax.microedition.khronos.opengles.GL10?, cfg:javax.microedition.khronos.egl.EGLConfig?) {
        android.opengl.GLES20.glClearColor(.48f,.68f,.76f,1f)
        android.opengl.GLES20.glEnable(android.opengl.GLES20.GL_DEPTH_TEST)
        program=link(vShader,fShader); pos=android.opengl.GLES20.glGetAttribLocation(program,"aPos"); col=android.opengl.GLES20.glGetUniformLocation(program,"uColor")
        for(z in -12..22) for(x in -16..16) {
            val h=((x*17+z*31+4000)%13)
            if(h%3!=0 && (x*x+z*z)>5) objects.add(Obj(x*1.65f,z*1.8f, if(h%5==0) 1 else 0, .78f+(h%4)*.13f,h.toFloat()))
        }
        for(i in 0..90) { val x=sin(i*12.31)*25; val z=cos(i*7.17)*28; objects.add(Obj(x.toFloat(),z.toFloat(),2,.55f+(i%4)*.15f,i.toFloat())) }
    }
    private fun shader(type:Int,src:String):Int { val s=android.opengl.GLES20.glCreateShader(type); android.opengl.GLES20.glShaderSource(s,src); android.opengl.GLES20.glCompileShader(s); return s }
    private fun link(v:String,f:String):Int { val p=android.opengl.GLES20.glCreateProgram(); android.opengl.GLES20.glAttachShader(p,shader(android.opengl.GLES20.GL_VERTEX_SHADER,v)); android.opengl.GLES20.glAttachShader(p,shader(android.opengl.GLES20.GL_FRAGMENT_SHADER,f)); android.opengl.GLES20.glLinkProgram(p); return p }
    override fun onSurfaceChanged(gl:javax.microedition.khronos.opengles.GL10?,w:Int,h:Int) { android.opengl.GLES20.glViewport(0,0,w,h) }
    override fun onDrawFrame(gl:javax.microedition.khronos.opengles.GL10?) {
        val now=System.nanoTime(); val dt=((now-last)/1e9).toFloat().coerceAtMost(.05f); last=now
        val speed=3.1f
        px += mx*speed*dt; pz += my*speed*dt
        if(abs(mx)+abs(my)>.08f) angle=atan2(mx,my)
        android.opengl.GLES20.glClear(android.opengl.GLES20.GL_COLOR_BUFFER_BIT or android.opengl.GLES20.GL_DEPTH_BUFFER_BIT)
        android.opengl.GLES20.glUseProgram(program)
        val aspect=1.78f
        val proj=perspective(58f,aspect,.1f,100f)
        val view=lookAt(px,4.8f,pz-7.5f,px,0f,pz+2.4f,0f,1f,0f)
        val vp=mul(proj,view)
        draw(vp,0f,-.18f,0f,90f,.12f,.12f,.12f,0xFF496B3B.toInt())
        for(o in objects) {
            val dx=o.x-px; val dz=o.z-pz
            if(dx*dx+dz*dz>850) continue
            if(o.type==0) {
                draw(vp,o.x,.85f*o.scale,o.z,.28f*o.scale,1.7f*o.scale,.28f*o.scale,0xFF65472F.toInt())
                draw(vp,o.x,2.15f*o.scale,o.z,1.08f*o.scale,1.35f*o.scale,1.08f*o.scale,if(o.seed.toInt()%2==0) 0xFF285B32.toInt() else 0xFF356D3B.toInt())
                draw(vp,o.x+.22f,2.8f*o.scale,o.z-.12f,.72f*o.scale,.85f*o.scale,.72f*o.scale,0xFF477F43.toInt())
            } else if(o.type==1) {
                draw(vp,o.x,.48f*o.scale,o.z,.68f*o.scale,.55f*o.scale,.62f*o.scale,0xFF315D32.toInt())
                draw(vp,o.x-.3f,.58f*o.scale,o.z+.12f,.42f*o.scale,.42f*o.scale,.4f*o.scale,0xFF477B3B.toInt())
            } else {
                draw(vp,o.x,.17f,o.z,.23f*o.scale,.28f*o.scale,.23f*o.scale,0xFF5C783B.toInt())
            }
        }
        // stylized articulated human silhouette
        val bob=if(abs(mx)+abs(my)>.08f) sin(now/85000000.0).toFloat()*.055f else 0f
        val fx=px; val fz=pz
        draw(vp,fx,.9f+bob,fz,.25f,.48f,.19f,0xFF354D61.toInt())
        draw(vp,fx,1.48f+bob,fz,.20f,.20f,.19f,0xFFD5A477.toInt())
        draw(vp,fx,1.68f+bob,fz,.24f,.09f,.22f,0xFF59422D.toInt())
        val swing=if(abs(mx)+abs(my)>.08f) sin(now/90000000.0).toFloat()*.22f else 0f
        draw(vp,fx-.14f,.36f+bob,fz+swing,.09f,.36f,.10f,0xFF293849.toInt())
        draw(vp,fx+.14f,.36f-bob,fz-swing,.09f,.36f,.10f,0xFF293849.toInt())
        draw(vp,fx-.31f,.91f+bob,fz-swing,.08f,.34f,.09f,0xFFD5A477.toInt())
        draw(vp,fx+.31f,.91f+bob,fz+swing,.08f,.34f,.09f,0xFFD5A477.toInt())
    }
    private fun draw(vp:FloatArray,x:Float,y:Float,z:Float,sx:Float,sy:Float,sz:Float,color:Int) {
        val model=identity(); model[0]=sx; model[5]=sy; model[10]=sz; model[12]=x; model[13]=y; model[14]=z
        val m=mul(vp,model)
        val verts=floatArrayOf(-1f,-1f,-1f,1f,-1f,-1f,1f,1f,-1f,-1f,1f,-1f,-1f,-1f,1f,1f,-1f,1f,1f,1f,1f,-1f,1f,1f)
        val idx=shortArrayOf(0,1,2,0,2,3,4,6,5,4,7,6,0,4,5,0,5,1,3,2,6,3,6,7,1,5,6,1,6,2,0,3,7,0,7,4)
        val vb=java.nio.ByteBuffer.allocateDirect(verts.size*4).order(java.nio.ByteOrder.nativeOrder()).asFloatBuffer(); vb.put(verts).position(0)
        val ib=java.nio.ByteBuffer.allocateDirect(idx.size*2).order(java.nio.ByteOrder.nativeOrder()).asShortBuffer(); ib.put(idx).position(0)
        android.opengl.GLES20.glUniformMatrix4fv(android.opengl.GLES20.glGetUniformLocation(program,"uMVP"),1,false,m,0)
        val rr=((color shr 16) and 255)/255f; val gg=((color shr 8) and 255)/255f; val bb=(color and 255)/255f
        android.opengl.GLES20.glUniform4f(col,rr,gg,bb,1f)
        android.opengl.GLES20.glEnableVertexAttribArray(pos); android.opengl.GLES20.glVertexAttribPointer(pos,3,android.opengl.GLES20.GL_FLOAT,false,0,vb)
        android.opengl.GLES20.glDrawElements(android.opengl.GLES20.GL_TRIANGLES,idx.size,android.opengl.GLES20.GL_UNSIGNED_SHORT,ib)
    }
    private fun identity()=FloatArray(16).also { android.opengl.Matrix.setIdentityM(it,0) }
    private fun perspective(f:Float,a:Float,n:Float,fa:Float):FloatArray { val m=FloatArray(16); android.opengl.Matrix.perspectiveM(m,0,f,a,n,fa); return m }
    private fun lookAt(ex:Float,ey:Float,ez:Float,cx:Float,cy:Float,cz:Float,ux:Float,uy:Float,uz:Float):FloatArray { val m=FloatArray(16); android.opengl.Matrix.setLookAtM(m,0,ex,ey,ez,cx,cy,cz,ux,uy,uz); return m }
    private fun mul(a:FloatArray,b:FloatArray):FloatArray { val o=FloatArray(16); android.opengl.Matrix.multiplyMM(o,0,a,0,b,0); return o }
}
