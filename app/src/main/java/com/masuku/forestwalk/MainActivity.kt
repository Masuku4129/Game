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
        val weatherButton=TextView(this).apply{text="☀";setTextColor(Color.WHITE);textSize=24f;gravity=Gravity.CENTER;setPadding(24,16,24,16);setBackgroundColor(0x55303030.toInt())}
        weatherButton.setOnClickListener { val mode=game.renderer.nextWeather(); weatherButton.text=when(mode){1->"☔";2->"❄";3->"☁";4->"🍂";else->"☀"} }
        root.addView(weatherButton,FrameLayout.LayoutParams(-2,-2,Gravity.TOP or Gravity.RIGHT).apply{topMargin=18;rightMargin=24})
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
private data class DetailChunk(val x:Float,val z:Float,val mesh:GpuMesh)

class ForestRenderer:GLSurfaceView.Renderer{
    @Volatile var mx=0f;@Volatile var my=0f;@Volatile private var weatherMode=0;private lateinit var weatherFx:ForestWeatherParticles
    fun nextWeather():Int {weatherMode=(weatherMode+1)%5;return weatherMode}
    private var program=0
    private var aPosition=0;private var aNormal=0;private var aColor=0
    private var uMvp=0;private var uModel=0;private var uPlayer=0;private var uTime=0;private var uWeather=0;private var uFoliage=0;private var uWalk=0;private var uGround=0
    private var width=1;private var height=1
    private var playerX=0f;private var playerZ=0f;private var heading=0f;private var last=System.nanoTime()
    private val treeChunks=ArrayList<TreeChunk>()
    private val shrubChunks=ArrayList<DetailChunk>()
    private val groundDetailChunks=ArrayList<DetailChunk>()
    private val rockChunks=ArrayList<DetailChunk>()
    private lateinit var playerBody:GpuMesh;private lateinit var playerArm:GpuMesh;private lateinit var playerTool:GpuMesh;private lateinit var playerUpperLeg:GpuMesh;private lateinit var playerLowerLeg:GpuMesh
    private lateinit var groundMesh:GpuMesh
    private lateinit var shrubMesh:ForestMesh
    private val vShader="""attribute vec3 aPos;attribute vec3 aNormal;attribute vec3 aColor;uniform mat4 uMVP;uniform mat4 uModel;uniform float uTime;uniform float uWalk;uniform float uFoliage;varying vec3 vWorld;varying vec3 vNormal;varying vec3 vColor;void main(){vec4 w=uModel*vec4(aPos,1.0);vWorld=w.xyz;vNormal=mat3(uModel)*aNormal;vColor=aColor;vec3 p=aPos;if(p.y<0.72){p.z+=sin(uTime*8.5+sign(p.x)*3.14159)*uWalk*.16;p.y+=abs(sin(uTime*8.5))*uWalk*.035;}else if(p.y>0.72&&p.y<1.25){p.z+=sin(uTime*8.5+sign(p.x)*3.14159+3.14159)*uWalk*.12;}if(uFoliage>0.5&&p.y>2.1){float wind=sin(uTime*1.35+p.z*.8+p.x*.45)*.045*(p.y/6.0);p.x+=wind;p.z+=cos(uTime*1.1+p.x*.6)*.018*(p.y/6.0);}gl_Position=uMVP*vec4(p,1.0);}"""
    private val fShader="""precision mediump float;varying vec3 vWorld;varying vec3 vNormal;varying vec3 vColor;uniform vec3 uPlayer;uniform float uTime;uniform float uWeather;uniform float uFoliage;uniform float uGround;
        float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
        float noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.0-2.0);return mix(mix(hash(i),hash(i+vec2(1.,0.)),f.x),mix(hash(i+vec2(0.,1.)),hash(i+vec2(1.,1.)),f.x),f.y);}
        void main(){float n=noise(vWorld.xz*2.8)*.12+noise(vWorld.xz*13.0)*.045;float leafgrain=noise(vWorld.xz*47.0)*.14+noise(vWorld.xz*91.0)*.08;float micro=noise(vWorld.xz*83.0);float fleck=noise(vWorld.xz*151.0);vec3 base=vColor*(.78+n+leafgrain)*mix(.84,1.18,micro)*mix(.94,1.07,fleck);vec3 N=normalize(vNormal);vec3 L=normalize(vec3(-.42,.86,.3));float diffuse=max(dot(N,L),0.0);float ambient=.44;float shade=ambient+diffuse*.72;float wet=step(.5,uWeather)*step(uWeather,1.5);base=mix(base,base*.72+vec3(.035,.045,.05),wet*.55);float puddleMask=wet*step(.5,uGround)*smoothstep(.62,.88,noise(vWorld.xz*3.7+vec2(uTime*.025,0.0)));base=mix(base,vec3(.17,.22,.21),puddleMask*.38);float snow=step(1.5,uWeather)*step(uWeather,2.5);float snowCover=clamp(snow*(.10+max(N.y,0.0)*.52+clamp(vWorld.y*.09,0.0,.38)),0.0,.78);;base=mix(base,vec3(.78,.82,.85),snowCover);float autumn=step(3.5,uWeather)*step(uWeather,4.5);float autumnLeaf=autumn*step(.5,uFoliage);base=mix(base,base*vec3(1.32,.76,.39)+vec3(.055,.018,.005),autumnLeaf*.88);float groundAutumn=autumn*step(.5,uGround);vec3 leafLitter=mix(vec3(.39,.35,.20),vec3(.51,.28,.14),noise(vWorld.xz*1.4));base=mix(base,leafLitter,groundAutumn*.66);float fog=smoothstep(18.0,42.0,distance(vWorld.xz,uPlayer.xz));float fogStrength=mix(.32,.72,step(2.5,uWeather)*step(uWeather,3.5));base=mix(base,vec3(.48,.54,.57),fog*fogStrength);vec3 viewDir=normalize(vec3(0.0,1.0,0.0));float spec=pow(max(dot(reflect(-L,N),viewDir),0.0),22.0)*wet*.22;float fade=1.0;if(uFoliage>0.5&&vWorld.y>2.3){float d=distance(vWorld.xz,uPlayer.xz);fade=mix(1.0,.18,1.0-smoothstep(.55,3.4,d));}gl_FragColor=vec4(base*shade+spec,fade);}"""
    override fun onSurfaceCreated(gl:GL10?,cfg:EGLConfig?){
        android.opengl.GLES20.glClearColor(.48f,.62f,.72f,1f)
        android.opengl.GLES20.glEnable(android.opengl.GLES20.GL_DEPTH_TEST)
        android.opengl.GLES20.glDisable(android.opengl.GLES20.GL_CULL_FACE)
        program=link(vShader,fShader)
        aPosition=android.opengl.GLES20.glGetAttribLocation(program,"aPos");aNormal=android.opengl.GLES20.glGetAttribLocation(program,"aNormal");aColor=android.opengl.GLES20.glGetAttribLocation(program,"aColor")
        uMvp=android.opengl.GLES20.glGetUniformLocation(program,"uMVP");uModel=android.opengl.GLES20.glGetUniformLocation(program,"uModel");uPlayer=android.opengl.GLES20.glGetUniformLocation(program,"uPlayer");uTime=android.opengl.GLES20.glGetUniformLocation(program,"uTime");uWeather=android.opengl.GLES20.glGetUniformLocation(program,"uWeather");uFoliage=android.opengl.GLES20.glGetUniformLocation(program,"uFoliage");uWalk=android.opengl.GLES20.glGetUniformLocation(program,"uWalk");uGround=android.opengl.GLES20.glGetUniformLocation(program,"uGround")
        groundMesh=makeGround();val rig=ForestModels.characterRig(123);playerBody=upload(rig.body);playerArm=upload(rig.arm);playerTool=upload(rig.tool);playerUpperLeg=upload(rig.upperLeg);playerLowerLeg=upload(rig.lowerLeg);shrubMesh=makeShrub();weatherFx=ForestWeatherParticles();weatherFx.init()
        val speciesMeshes=ArrayList<ForestMesh>()
        for(i in 0 until 14)speciesMeshes.add(ForestModels.tree(300+i,5.6f+(i%5)*.65f).mesh)
        // Static trees are CPU-merged into bounded chunks to reduce hundreds of draw calls.
        val rnd=java.util.Random(87129)
        val chunkSize=34f
        for(cz in -2..2)for(cx in -2..2){
            val batch=ForestMeshBuilder()
            val count=9+rnd.nextInt(3)
            repeat(count){
                val sx=cx*chunkSize+(rnd.nextFloat()-.5f)*chunkSize*.82f
                val sz=cz*chunkSize+(rnd.nextFloat()-.5f)*chunkSize*.82f
                val sp=rnd.nextInt(speciesMeshes.size)
                val sc=.86f+rnd.nextFloat()*.52f
                val rot=rnd.nextFloat()*6.28318f
                batch.append(speciesMeshes[sp],sx-cx*chunkSize,0f,sz-cz*chunkSize,sc,rot)
            }
            treeChunks.add(TreeChunk(cx*chunkSize,cz*chunkSize,upload(batch.snapshot())))
            // Dense, independently batched understory and ground detail around every forest tile.
            val shrubs=ForestMeshBuilder()
            val groundBits=ForestMeshBuilder()
            val rocks=ForestMeshBuilder()
            repeat(19+rnd.nextInt(9){
                val sx=(rnd.nextFloat()-.5f)*chunkSize*.88f
                val sz=(rnd.nextFloat()-.5f)*chunkSize*.88f
                val scale=.62f+rnd.nextFloat()*.72f
                shrubs.append(shrubMesh, sx, 0f, sz, scale, rnd.nextFloat()*6.28318f)
            }
            repeat(520){
                val gx=(rnd.nextFloat()-.5f)*chunkSize*.94f
                val gz=(rnd.nextFloat()-.5f)*chunkSize*.94f
                val h=.16f+rnd.nextFloat()*.36f
                val w=.025f+rnd.nextFloat()*.045f
                val col=when(rnd.nextInt(5)){0->0xFF7B8D42.toInt();1->0xFF87994A.toInt();2->0xFF536D34.toInt();3->0xFFB0A35A.toInt();else->0xFF657C3B.toInt()}
                val sway=(rnd.nextFloat()-.5f)*.14f
                groundBits.triangleUp(floatArrayOf(gx-w,0f,gz),floatArrayOf(gx+w,0f,gz),floatArrayOf(gx+sway,h,gz+(rnd.nextFloat()-.5f)*.12f),col)
                groundBits.triangleUp(floatArrayOf(gx,0f,gz-w),floatArrayOf(gx,0f,gz+w),floatArrayOf(gx+(rnd.nextFloat()-.5f)*.12f,h,gz+sway),col)
            }
                        repeat(18){
                val fx=(rnd.nextFloat()-.5f)*chunkSize*.9f
                val fz=(rnd.nextFloat()-.5f)*chunkSize*.9f
                val petal=when(rnd.nextInt(4)){0->0xFFE7E0CF.toInt();1->0xFFB6C7D5.toInt();2->0xFFD9C1DF.toInt();else->0xFFF0D18B.toInt()}
                val rr=.035f+rnd.nextFloat()*.035f
                for(k in 0..3){val ang=k*PI/2.0;groundBits.ellipsoid(fx+(cos(ang)*rr).toFloat(),.06f,fz+(sin(ang)*rr).toFloat(),rr,.018f,rr*.65f,petal,7,5)}
                groundBits.ellipsoid(fx,.08f,fz,.025f,.025f,.025f,0xFFD2B45C.toInt(),7,5)
            }
            repeat(11+rnd.nextInt(7)){
                val rx=(rnd.nextFloat()-.5f)*chunkSize*.9f
                val rz=(rnd.nextFloat()-.5f)*chunkSize*.9f
                val size=.18f+rnd.nextFloat()*.5f
                val tint=when(rnd.nextInt(4)){0->0xFF77766E.toInt();1->0xFF6D7168.toInt();2->0xFF817B70.toInt();else->0xFF5D665D.toInt()}
                rocks.ellipsoid(rx, size*.38f, rz,size*1.15f,size*.55f,size*.8f,tint,9,6)
                rocks.ellipsoid(rx+size*.38f,size*.25f,rz-size*.32f,size*.6f,size*.42f,size*.58f,tint-0x00040404,8,5)
            }
            shrubChunks.add(DetailChunk(cx*chunkSize,cz*chunkSize,upload(shrubs.snapshot())))
            groundDetailChunks.add(DetailChunk(cx*chunkSize,cz*chunkSize,upload(groundBits.snapshot())))
            rockChunks.add(DetailChunk(cx*chunkSize,cz*chunkSize,upload(rocks.snapshot())))
        }
    }
    override fun onSurfaceChanged(gl:GL10?,w:Int,h:Int){width=w.coerceAtLeast(1);height=h.coerceAtLeast(1);android.opengl.GLES20.glViewport(0,0,width,height)}
    override fun onDrawFrame(gl:GL10?){
        val now=System.nanoTime();val dt=((now-last)/1e9).toFloat().coerceIn(0f,.05f);last=now
        playerX=(playerX+mx*3.5f*dt).coerceIn(-84f,84f);playerZ=(playerZ-my*3.5f*dt).coerceIn(-84f,84f)
        val playerY=terrainHeight(playerX,playerZ)
        if(abs(mx)+abs(my)>.06f)heading=atan2(mx,-my)
        android.opengl.GLES20.glClear(android.opengl.GLES20.GL_COLOR_BUFFER_BIT or android.opengl.GLES20.GL_DEPTH_BUFFER_BIT)
        android.opengl.GLES20.glUseProgram(program)
        val aspect=width.toFloat()/height.toFloat()
        val view=lookAt(playerX,15.8f+playerY,playerZ+4.1f,playerX,playerY,playerZ,0f,1f,0f)
        val projection=ortho(-5.4f*aspect,5.4f*aspect,-5.4f,5.4f,.1f,70f)
        val vp=mul(projection,view)
        android.opengl.GLES20.glUniform3f(uPlayer,playerX,playerY,playerZ)
        android.opengl.GLES20.glUniform1f(uTime,now/1e9f);android.opengl.GLES20.glUniform1f(uWeather,weatherMode.toFloat())
        android.opengl.GLES20.glClearColor(if(weatherMode==1).24f else if(weatherMode==2).66f else if(weatherMode==3).58f else .48f,if(weatherMode==1).30f else if(weatherMode==2).72f else if(weatherMode==3).65f else .62f,if(weatherMode==1).36f else if(weatherMode==2).79f else if(weatherMode==3).69f else .72f,1f)
        draw(groundMesh,vp,identity(),false,0f,true)
        for(chunk in treeChunks){val dx=chunk.x-playerX;val dz=chunk.z-playerZ;if(dx*dx+dz*dz>1400f)continue
            val model=identity();android.opengl.Matrix.translateM(model,0,chunk.x,0f,chunk.z)
            android.opengl.GLES20.glEnable(android.opengl.GLES20.GL_BLEND);android.opengl.GLES20.glBlendFunc(android.opengl.GLES20.GL_SRC_ALPHA,android.opengl.GLES20.GL_ONE_MINUS_SRC_ALPHA);android.opengl.GLES20.glDepthMask(false);draw(chunk.mesh,vp,model,true);android.opengl.GLES20.glDepthMask(true);android.opengl.GLES20.glDisable(android.opengl.GLES20.GL_BLEND)
        }
        for(chunk in shrubChunks){val dx=chunk.x-playerX;val dz=chunk.z-playerZ;if(dx*dx+dz*dz>1400f)continue
            val model=identity();android.opengl.Matrix.translateM(model,0,chunk.x,0f,chunk.z);draw(chunk.mesh,vp,model,true)
        }
        for(chunk in groundDetailChunks){val dx=chunk.x-playerX;val dz=chunk.z-playerZ;if(dx*dx+dz*dz>1400f)continue
            val model=identity();android.opengl.Matrix.translateM(model,0,chunk.x,0f,chunk.z);draw(chunk.mesh,vp,model,false)
        }
        for(chunk in rockChunks){val dx=chunk.x-playerX;val dz=chunk.z-playerZ;if(dx*dx+dz*dz>1400f)continue
            val model=identity();android.opengl.Matrix.translateM(model,0,chunk.x,0f,chunk.z);draw(chunk.mesh,vp,model,false)
        }
        // Articulated gait: hip swings, knee flexion and counter-swinging arms.
        val moving=abs(mx)+abs(my)>.06f
        val phase=now/1e9*8.5
        val swing=if(moving)sin(phase).toFloat()*.42f else 0f
        val bob=if(moving)abs(sin(phase)).toFloat()*.035f else 0f
        val pm=identity();android.opengl.Matrix.translateM(pm,0,playerX,playerY+bob,playerZ);android.opengl.Matrix.rotateM(pm,0,heading*180f/PI.toFloat(),0f,1f,0f)
        draw(playerBody,vp,pm)
        for(sideIndex in 0..1){
            val side=if(sideIndex==0)-1f else 1f
            val armPivot=identity();android.opengl.Matrix.translateM(armPivot,0,side*.23f,1.18f,0f);android.opengl.Matrix.rotateM(armPivot,0,-swing*55f,1f,0f,0f)
            val armModel=mul(pm,armPivot);draw(playerArm,vp,armModel)
            if(side>0f)draw(playerTool,vp,armModel)
            val hip=identity();android.opengl.Matrix.translateM(hip,0,side*.13f,.62f,0f);android.opengl.Matrix.rotateM(hip,0,(if(side<0f)swing else -swing)*57.3f,1f,0f,0f)
            val upperModel=mul(pm,hip);draw(playerUpperLeg,vp,upperModel)
            val kneeAngle=if(side<0f)max(0f,-sin(phase).toFloat())*.5f else max(0f,sin(phase).toFloat())*.5f
            val knee=identity();android.opengl.Matrix.translateM(knee,0,0f,-.32f,0f);android.opengl.Matrix.rotateM(knee,0,kneeAngle*45f,1f,0f,0f)
            draw(playerLowerLeg,vp,mul(upperModel,knee))
        }
        weatherFx.render(vp,playerX,playerZ,dt,weatherMode)
    }
    private fun draw(mesh:GpuMesh,vp:FloatArray,model:FloatArray,foliage:Boolean=false,walking:Float=0f,ground:Boolean=false){
        android.opengl.GLES20.glUniform1f(uFoliage,if(foliage)1f else 0f);android.opengl.GLES20.glUniform1f(uWalk,walking);android.opengl.GLES20.glUniform1f(uGround,if(ground)1f else 0f)
        val m=mul(vp,model);android.opengl.GLES20.glUniformMatrix4fv(uMvp,1,false,m,0);android.opengl.GLES20.glUniformMatrix4fv(uModel,1,false,model,0)
        val stride=9*4
        mesh.vertices.position(0);android.opengl.GLES20.glEnableVertexAttribArray(aPosition);android.opengl.GLES20.glVertexAttribPointer(aPosition,3,android.opengl.GLES20.GL_FLOAT,false,stride,mesh.vertices)
        mesh.vertices.position(3);android.opengl.GLES20.glEnableVertexAttribArray(aNormal);android.opengl.GLES20.glVertexAttribPointer(aNormal,3,android.opengl.GLES20.GL_FLOAT,false,stride,mesh.vertices)
        mesh.vertices.position(6);android.opengl.GLES20.glEnableVertexAttribArray(aColor);android.opengl.GLES20.glVertexAttribPointer(aColor,3,android.opengl.GLES20.GL_FLOAT,false,stride,mesh.vertices)
        android.opengl.GLES20.glDrawElements(android.opengl.GLES20.GL_TRIANGLES,mesh.count,android.opengl.GLES20.GL_UNSIGNED_SHORT,mesh.indices)
    }
    private fun terrainHeight(x:Float,z:Float):Float=(sin(x*.105f)*.12f+cos(z*.13f)*.10f+sin((x+z)*.075f)*.085f+cos((x-z)*.048f)*.055f)
    private fun makeGround():GpuMesh{
        val b=ForestMeshBuilder()
        val rng=java.util.Random(94721)
        val colors=intArrayOf(0xFF536B3E.toInt(),0xFF5A7044.toInt(),0xFF647847.toInt(),0xFF4B633A.toInt(),0xFF6C7747.toInt(),0xFF746B42.toInt(),0xFF5D6840.toInt(),0xFF7A784C.toInt(),0xFF4D6540.toInt())
        val cells=96
        val step=180f/cells
        fun y(x:Float,z:Float):Float=(sin(x*.105f)*.12f+cos(z*.13f)*.10f+sin((x+z)*.075f)*.085f+cos((x-z)*.048f)*.055f)
        for(ix in 0 until cells)for(iz in 0 until cells){
            val x0=-90f+ix*step;val x1=x0+step
            val z0=-90f+iz*step;val z1=z0+step
            val c=colors[rng.nextInt(colors.size)]
            val a=floatArrayOf(x0,y(x0,z0),z0);val bb=floatArrayOf(x1,y(x1,z0),z0)
            val cc=floatArrayOf(x1,y(x1,z1),z1);val d=floatArrayOf(x0,y(x0,z1),z1)
            if((ix+iz)%2==0){b.triangle(a,cc,bb,c);b.triangle(a,d,cc,c)}
            else{b.triangle(a,d,bb,c);b.triangle(bb,d,cc,c)}
        }
        return upload(b.snapshot())
    }
    private fun makeShrub():ForestMesh=ForestModels.shrub(418)
    private fun upload(m:ForestMesh):GpuMesh=GpuMesh(m.vertexBuffer,m.indexBuffer,m.indexCount)
    private fun shader(type:Int,src:String):Int{val s=android.opengl.GLES20.glCreateShader(type);android.opengl.GLES20.glShaderSource(s,src);android.opengl.GLES20.glCompileShader(s);val ok=IntArray(1);android.opengl.GLES20.glGetShaderiv(s,android.opengl.GLES20.GL_COMPILE_STATUS,ok,0);if(ok[0]==0)throw RuntimeException(android.opengl.GLES20.glGetShaderInfoLog(s));return s}
    private fun link(v:String,f:String):Int{val p=android.opengl.GLES20.glCreateProgram();android.opengl.GLES20.glAttachShader(p,shader(android.opengl.GLES20.GL_VERTEX_SHADER,v));android.opengl.GLES20.glAttachShader(p,shader(android.opengl.GLES20.GL_FRAGMENT_SHADER,f));android.opengl.GLES20.glLinkProgram(p);val ok=IntArray(1);android.opengl.GLES20.glGetProgramiv(p,android.opengl.GLES20.GL_LINK_STATUS,ok,0);if(ok[0]==0)throw RuntimeException(android.opengl.GLES20.glGetProgramInfoLog(p));return p}
    private fun identity()=FloatArray(16).also{android.opengl.Matrix.setIdentityM(it,0)}
    private fun ortho(l:Float,r:Float,b:Float,t:Float,n:Float,f:Float):FloatArray{val m=FloatArray(16);android.opengl.Matrix.orthoM(m,0,l,r,b,t,n,f);return m}
    private fun lookAt(ex:Float,ey:Float,ez:Float,cx:Float,cy:Float,cz:Float,ux:Float,uy:Float,uz:Float):FloatArray{val m=FloatArray(16);android.opengl.Matrix.setLookAtM(m,0,ex,ey,ez,cx,cy,cz,ux,uy,uz);return m}
    private fun mul(a:FloatArray,b:FloatArray):FloatArray{val o=FloatArray(16);android.opengl.Matrix.multiplyMM(o,0,a,0,b,0);return o}
}