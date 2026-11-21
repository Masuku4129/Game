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
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import java.nio.ShortBuffer
import javax.microedition.khronos.opengles.GL10
import javax.microedition.khronos.egl.EGLConfig

class MainActivity : Activity() {
    private lateinit var game: ForestView
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.decorView.systemUiVisibility = (View.SYSTEM_UI_FLAG_FULLSCREEN or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY)
        val root=FrameLayout(this)
        game=ForestView(this)
        root.addView(game)
        val pad=Joystick(this){x,y->game.moveX=x;game.moveY=y}
        val params=FrameLayout.LayoutParams(250,250,Gravity.BOTTOM or Gravity.LEFT).apply{leftMargin=30;bottomMargin=26}
        root.addView(pad,params)
        val title=TextView(this).apply{text="FOREST WALK";setTextColor(Color.WHITE);textSize=12f;alpha=.7f;setPadding(20,12,20,12)}
        root.addView(title,FrameLayout.LayoutParams(-2,-2,Gravity.TOP or Gravity.LEFT))
        setContentView(root)
    }
    override fun onPause(){super.onPause();game.onPause()}
    override fun onResume(){super.onResume();game.onResume()}
}

class Joystick(ctx:android.content.Context,val changed:(Float,Float)->Unit):View(ctx){
    private val paint=Paint(3)
    private var dx=0f;private var dy=0f
    override fun onDraw(c:Canvas){val r=min(width,height)*.43f;val cx=width/2f;val cy=height/2f
        paint.color=0x55333333;c.drawCircle(cx,cy,r,paint)
        paint.color=0x88FFFFFF.toInt();c.drawCircle(cx,cy,r*.48f,paint)
        paint.color=0xCCFFFFFF.toInt();c.drawCircle(cx+dx*r*.58f,cy+dy*r*.58f,r*.24f,paint)}
    override fun onTouchEvent(e:MotionEvent):Boolean{val r=min(width,height)*.43f;val cx=width/2f;val cy=height/2f
        if(e.action==MotionEvent.ACTION_UP||e.action==MotionEvent.ACTION_CANCEL){dx=0f;dy=0f;changed(0f,0f)}
        else{dx=((e.x-cx)/r).coerceIn(-1f,1f);dy=((e.y-cy)/r).coerceIn(-1f,1f);val l=sqrt(dx*dx+dy*dy);if(l>1){dx/=l;dy/=l};changed(dx,-dy)}
        invalidate();return true}
}

class ForestView(ctx:android.content.Context):GLSurfaceView(ctx){
    val renderer=ForestRenderer()
    var moveX:Float get()=renderer.mx;set(v){renderer.mx=v}
    var moveY:Float get()=renderer.my;set(v){renderer.my=v}
    init{setEGLContextClientVersion(2);setRenderer(renderer);renderMode=RENDERMODE_CONTINUOUSLY}
}

private data class GpuMesh(val vertices:FloatBuffer,val indices:ShortBuffer,val count:Int)
private data class TreeChunk(val x:Float,val z:Float,val mesh:GpuMesh)

class ForestRenderer:GLSurfaceView.Renderer{
    @Volatile var mx=0f;@Volatile var my=0f
    private var program=0
    private var aPosition=0;private var aNormal=0;private var aColor=0
    private var uMvp=0;private var uModel=0;private var uPlayer=0;private var uTime=0;private var uWeather=0;private var uFoliage=0;private var uWalk=0
    private var width=1;private var height=1
    private var playerX=0f;private var playerZ=0f;private var heading=0f;private var last=System.nanoTime()
    private val treeChunks=ArrayList<TreeChunk>()
    private lateinit var playerMesh:GpuMesh
    private lateinit var groundMesh:GpuMesh
    private lateinit var shrubMesh:GpuMesh
    private val vShader="""attribute vec3 aPos;attribute vec3 aNormal;attribute vec3 aColor;uniform mat4 uMVP;uniform mat4 uModel;uniform float uTime;uniform float uWalk;varying vec3 vWorld;varying vec3 vNormal;varying vec3 vColor;void main(){vec4 w=uModel*vec4(aPos,1.0);vWorld=w.xyz;vNormal=mat3(uModel)*aNormal;vColor=aColor;vec3 p=aPos;if(p.y<0.72){p.z+=sin(uTime*8.5+sign(p.x)*3.14159)*uWalk*.16;p.y+=abs(sin(uTime*8.5))*uWalk*.035;}else if(p.y>0.72&&p.y<1.25){p.z+=sin(uTime*8.5+sign(p.x)*3.14159+3.14159)*uWalk*.12;}gl_Position=uMVP*vec4(p,1.0);}"""
    private val fShader="""precision mediump float;varying vec3 vWorld;varying vec3 vNormal;varying vec3 vColor;uniform vec3 uPlayer;uniform float uTime;uniform float uWeather;uniform float uFoliage;
        float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
        float noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.0-2.0);return mix(mix(hash(i),hash(i+vec2(1.,0.)),f.x),mix(hash(i+vec2(0.,1.)),hash(i+vec2(1.,1.)),f.x),f.y);}
        void main(){float n=noise(vWorld.xz*2.8)*.12+noise(vWorld.xz*13.0)*.045;vec3 base=vColor*(.90+n);vec3 N=normalize(vNormal);vec3 L=normalize(vec3(-.42,.86,.3));float diffuse=max(dot(N,L),0.0);float ambient=.38;float shade=ambient+diffuse*.68;float wet=clamp(uWeather,0.0,1.0);base=mix(base,base*.72+vec3(.035,.045,.05),wet*.55);vec3 viewDir=normalize(vec3(0.0,1.0,0.0));float spec=pow(max(dot(reflect(-L,N),viewDir),0.0),22.0)*wet*.22;float fade=1.0;if(uFoliage>0.5&&vWorld.y>2.3){float d=distance(vWorld.xz,uPlayer.xz);fade=mix(1.0,.18,1.0-smoothstep(.55,3.4,d));}gl_FragColor=vec4(base*shade+spec,fade);}"""
    override fun onSurfaceCreated(gl:GL10?,cfg:EGLConfig?){
        android.opengl.GLES20.glClearColor(.48f,.62f,.72f,1f)
        android.opengl.GLES20.glEnable(android.opengl.GLES20.GL_DEPTH_TEST)
        android.opengl.GLES20.glDisable(android.opengl.GLES20.GL_CULL_FACE)
        program=link(vShader,fShader)
        aPosition=android.opengl.GLES20.glGetAttribLocation(program,"aPos");aNormal=android.opengl.GLES20.glGetAttribLocation(program,"aNormal");aColor=android.opengl.GLES20.glGetAttribLocation(program,"aColor")
        uMvp=android.opengl.GLES20.glGetUniformLocation(program,"uMVP");uModel=android.opengl.GLES20.glGetUniformLocation(program,"uModel");uPlayer=android.opengl.GLES20.glGetUniformLocation(program,"uPlayer");uTime=android.opengl.GLES20.glGetUniformLocation(program,"uTime");uWeather=android.opengl.GLES20.glGetUniformLocation(program,"uWeather");uFoliage=android.opengl.GLES20.glGetUniformLocation(program,"uFoliage");uWalk=android.opengl.GLES20.glGetUniformLocation(program,"uWalk")
        groundMesh=makeGround();playerMesh=upload(ForestModels.character(123));shrubMesh=makeShrub()
        val speciesMeshes=ArrayList<ForestMesh>()
        for(i in 0 until 10)speciesMeshes.add(ForestModels.tree(300+i,4.4f+(i%4)*.55f).mesh)
        // Static trees are CPU-merged into bounded chunks to reduce hundreds of draw calls.
        val rnd=java.util.Random(87129)
        val chunkSize=34f
        for(cz in -2..2)for(cx in -2..2){
            val batch=ForestMeshBuilder()
            val count=5+rnd.nextInt(4)
            repeat(count){
                val sx=cx*chunkSize+(rnd.nextFloat()-.5f)*chunkSize*.82f
                val sz=cz*chunkSize+(rnd.nextFloat()-.5f)*chunkSize*.82f
                val sp=rnd.nextInt(speciesMeshes.size)
                val sc=.78f+rnd.nextFloat()*.75f
                val rot=rnd.nextFloat()*6.28318f
                batch.append(speciesMeshes[sp],sx,0f,sz,sc,rot)
            }
            treeChunks.add(TreeChunk(cx*chunkSize,cz*chunkSize,upload(batch.snapshot())))
        }
    }
    override fun onSurfaceChanged(gl:GL10?,w:Int,h:Int){width=w.coerceAtLeast(1);height=h.coerceAtLeast(1);android.opengl.GLES20.glViewport(0,0,width,height)}
    override fun onDrawFrame(gl:GL10?){
        val now=System.nanoTime();val dt=((now-last)/1e9).toFloat().coerceIn(0f,.05f);last=now
        playerX+=mx*3.5f*dt;playerZ-=my*3.5f*dt
        if(abs(mx)+abs(my)>.06f)heading=atan2(mx,my)
        android.opengl.GLES20.glClear(android.opengl.GLES20.GL_COLOR_BUFFER_BIT or android.opengl.GLES20.GL_DEPTH_BUFFER_BIT)
        android.opengl.GLES20.glUseProgram(program)
        val aspect=width.toFloat()/height.toFloat()
        val view=lookAt(playerX,22f,playerZ+6f,playerX,0f,playerZ,0f,1f,0f)
        val projection=ortho(-11f*aspect,11f*aspect,-11f,11f,.1f,70f)
        val vp=mul(projection,view)
        android.opengl.GLES20.glUniform3f(uPlayer,playerX,0f,playerZ)
        android.opengl.GLES20.glUniform1f(uTime,now/1e9f);android.opengl.GLES20.glUniform1f(uWeather,0f)
        draw(groundMesh,vp,identity())
        for(chunk in treeChunks){val dx=chunk.x-playerX;val dz=chunk.z-playerZ;if(dx*dx+dz*dz>1400f)continue
            val model=identity();android.opengl.Matrix.translateM(model,0,chunk.x,0f,chunk.z)
            android.opengl.GLES20.glEnable(android.opengl.GLES20.GL_BLEND);android.opengl.GLES20.glBlendFunc(android.opengl.GLES20.GL_SRC_ALPHA,android.opengl.GLES20.GL_ONE_MINUS_SRC_ALPHA);android.opengl.GLES20.glDepthMask(false);draw(chunk.mesh,vp,model,true);android.opengl.GLES20.glDepthMask(true);android.opengl.GLES20.glDisable(android.opengl.GLES20.GL_BLEND)}
        // Softly bobbing and turning toward travel direction (visual base animation).
        val moving=abs(mx)+abs(my)>.06f;val bob=if(moving)sin(now/95000000.0).toFloat()*.035f else 0f
        val pm=identity();android.opengl.Matrix.translateM(pm,0,playerX,.0f+bob,playerZ);android.opengl.Matrix.rotateM(pm,0,heading*180f/PI.toFloat(),0f,1f,0f)
        draw(playerMesh,vp,pm,false,if(moving)1f else 0f)
    }
    private fun draw(mesh:GpuMesh,vp:FloatArray,model:FloatArray,foliage:Boolean=false,walking:Float=0f){\n        android.opengl.GLES20.glUniform1f(uFoliage,if(foliage)1f else 0f);android.opengl.GLES20.glUniform1f(uWalk,walking)
        val m=mul(vp,model);android.opengl.GLES20.glUniformMatrix4fv(uMvp,1,false,m,0);android.opengl.GLES20.glUniformMatrix4fv(uModel,1,false,model,0)
        val stride=9*4
        mesh.vertices.position(0);android.opengl.GLES20.glEnableVertexAttribArray(aPosition);android.opengl.GLES20.glVertexAttribPointer(aPosition,3,android.opengl.GLES20.GL_FLOAT,false,stride,mesh.vertices)
        mesh.vertices.position(3);android.opengl.GLES20.glEnableVertexAttribArray(aNormal);android.opengl.GLES20.glVertexAttribPointer(aNormal,3,android.opengl.GLES20.GL_FLOAT,false,stride,mesh.vertices)
        mesh.vertices.position(6);android.opengl.GLES20.glEnableVertexAttribArray(aColor);android.opengl.GLES20.glVertexAttribPointer(aColor,3,android.opengl.GLES20.GL_FLOAT,false,stride,mesh.vertices)
        android.opengl.GLES20.glDrawElements(android.opengl.GLES20.GL_TRIANGLES,mesh.count,android.opengl.GLES20.GL_UNSIGNED_SHORT,mesh.indices)
    }
    private fun makeGround():GpuMesh{val b=ForestMeshBuilder();val c=0xFF546C42.toInt();b.triangle(floatArrayOf(-90f,0f,-90f),floatArrayOf(90f,0f,90f),floatArrayOf(90f,0f,-90f),c);b.triangle(floatArrayOf(-90f,0f,-90f),floatArrayOf(-90f,0f,90f),floatArrayOf(90f,0f,90f),c);return upload(b.snapshot())}
    private fun makeShrub():GpuMesh{val b=ForestMeshBuilder();for(i in 0..5){val a=i*PI/3;val r=.35f;b.ellipsoid((cos(a)*r).toFloat(),.3f,(sin(a)*r).toFloat(),.42f,.35f,.42f,0xFF386B3C.toInt()+i*0x000201,9,6)};return upload(b.snapshot())}
    private fun upload(m:ForestMesh):GpuMesh=GpuMesh(m.vertexBuffer,m.indexBuffer,m.indexCount)
    private fun shader(type:Int,src:String):Int{val s=android.opengl.GLES20.glCreateShader(type);android.opengl.GLES20.glShaderSource(s,src);android.opengl.GLES20.glCompileShader(s);val ok=IntArray(1);android.opengl.GLES20.glGetShaderiv(s,android.opengl.GLES20.GL_COMPILE_STATUS,ok,0);if(ok[0]==0)throw RuntimeException(android.opengl.GLES20.glGetShaderInfoLog(s));return s}
    private fun link(v:String,f:String):Int{val p=android.opengl.GLES20.glCreateProgram();android.opengl.GLES20.glAttachShader(p,shader(android.opengl.GLES20.GL_VERTEX_SHADER,v));android.opengl.GLES20.glAttachShader(p,shader(android.opengl.GLES20.GL_FRAGMENT_SHADER,f));android.opengl.GLES20.glLinkProgram(p);val ok=IntArray(1);android.opengl.GLES20.glGetProgramiv(p,android.opengl.GLES20.GL_LINK_STATUS,ok,0);if(ok[0]==0)throw RuntimeException(android.opengl.GLES20.glGetProgramInfoLog(p));return p}
    private fun identity()=FloatArray(16).also{android.opengl.Matrix.setIdentityM(it,0)}
    private fun ortho(l:Float,r:Float,b:Float,t:Float,n:Float,f:Float):FloatArray{val m=FloatArray(16);android.opengl.Matrix.orthoM(m,0,l,r,b,t,n,f);return m}
    private fun lookAt(ex:Float,ey:Float,ez:Float,cx:Float,cy:Float,cz:Float,ux:Float,uy:Float,uz:Float):FloatArray{val m=FloatArray(16);android.opengl.Matrix.setLookAtM(m,0,ex,ey,ez,cx,cy,cz,ux,uy,uz);return m}
    private fun mul(a:FloatArray,b:FloatArray):FloatArray{val o=FloatArray(16);android.opengl.Matrix.multiplyMM(o,0,a,0,b,0);return o}
}