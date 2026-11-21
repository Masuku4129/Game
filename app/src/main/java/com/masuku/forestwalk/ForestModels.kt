package com.masuku.forestwalk

import kotlin.math.*

/** Procedural organic model generators. Each model is assembled into a single indexed mesh. */
internal object ForestModels {
    data class TreeModel(val mesh:ForestMesh,val components:Int,val height:Float)

    private fun leafBlade(b:ForestMeshBuilder,x:Float,y:Float,z:Float,length:Float,width:Float,yaw:Double,color:Int){
        val dx=cos(yaw).toFloat();val dz=sin(yaw).toFloat()
        val sx=-dz;val sz=dx
        val tipX=x+dx*length*.72f;val tipY=y+length*.34f;val tipZ=z+dz*length*.72f
        val midX=x+dx*length*.40f;val midY=y+length*.18f;val midZ=z+dz*length*.40f
        val left=floatArrayOf(midX+sx*width,midY,midZ+sz*width)
        val right=floatArrayOf(midX-sx*width,midY,midZ-sz*width)
        val base=floatArrayOf(x,y,z);val tip=floatArrayOf(tipX,tipY,tipZ)
        b.triangle(base,left,tip,color);b.triangle(base,tip,right,color)
    }
    private fun leafCluster(b:ForestMeshBuilder,x:Float,y:Float,z:Float,size:Float,yaw:Double,baseColor:Int,seed:Int){
        val r=java.util.Random(seed.toLong())
        repeat(7){
            val a=yaw+r.nextDouble()*PI*2.0
            val offset=size*(.05f+r.nextFloat()*.45f)
            val bx=x+(cos(a)*offset).toFloat();val bz=z+(sin(a)*offset).toFloat()
            val by=y+(r.nextFloat()-.5f)*size*.28f
            val leafLength=size*(.48f+r.nextFloat()*.52f)
            val leafWidth=leafLength*(.13f+r.nextFloat()*.08f)
            val color=baseColor-(r.nextInt(28)*0x00010101)
            leafBlade(b,bx,by,bz,leafLength,leafWidth,a,color)
        }
    }
    fun shrub(seed:Int=1):ForestMesh{
        val b=ForestMeshBuilder();val r=java.util.Random(seed.toLong())
        val greens=intArrayOf(0xFF37663A.toInt(),0xFF4B7843.toInt(),0xFF5D8449.toInt(),0xFF2E5733.toInt())
        repeat(9){i->
            val a=i*PI*2.0/9.0+r.nextDouble()*.3
            val reach=.28f+r.nextFloat()*.40f
            val x=(cos(a)*reach).toFloat();val z=(sin(a)*reach).toFloat()
            val y=.18f+r.nextFloat()*.32f
            b.taperedCylinder(0f,.05f,0f,x,y,z,.045f,.018f,0xFF6A5234.toInt(),6)
            leafCluster(b,x,y,z,.50f+r.nextFloat()*.55f,a,greens[r.nextInt(greens.size)],seed+i*19)
        }
        repeat(5){i->
            val a=r.nextDouble()*PI*2.0
            leafCluster(b,(cos(a)*.18f).toFloat(),.40f+r.nextFloat()*.32f,(sin(a)*.18f).toFloat(),.45f,a,greens[r.nextInt(greens.size)],seed+300+i)
        }
        return b.snapshot()
    }
    /** A tree has 30+ separate smooth geometry components, with deterministic seed variation. */
    fun tree(seed:Int,height:Float=6.2f):TreeModel {
        val b=ForestMeshBuilder()
        val rnd=java.util.Random(seed.toLong())
        val species=((seed%3)+3)%3
        val trunk=when(species){1->0xFF493A2C.toInt();2->0xFFB7A88C.toInt();else->0xFF58412C.toInt()}
        val palette=when(species){
            1->intArrayOf(0xFF1D4430.toInt(),0xFF27543A.toInt(),0xFF2E6141.toInt(),0xFF376D47.toInt(),0xFF234A35.toInt(),0xFF3B7146.toInt())
            2->intArrayOf(0xFF487A3B.toInt(),0xFF5E8D45.toInt(),0xFF78A64E.toInt(),0xFF63994A.toInt(),0xFF3E6C39.toInt(),0xFF8AAE5A.toInt())
            else->intArrayOf(0xFF294F32.toInt(),0xFF32633A.toInt(),0xFF3B7042.toInt(),0xFF477B48.toInt(),0xFF22472E.toInt(),0xFF507E45.toInt())
        }
        val taper=0.15f+height*.025f
        val leanX=(rnd.nextFloat()-.5f)*height*.045f
        val leanZ=(rnd.nextFloat()-.5f)*height*.045f
        b.taperedCylinder(0f,0f,0f,leanX,height,leanZ,taper,taper*.20f,trunk,14)
        var components=1
        // Root flares spread irregularly around the base, partially exposed above forest floor.
        for(i in 0 until 7){
            val a=i*PI*2.0/7.0+rnd.nextDouble()*.25
            val reach=height*(.17f+rnd.nextFloat()*.12f)
            b.taperedCylinder(0f,.06f,0f,(cos(a)*reach).toFloat(),.13f,(sin(a)*reach).toFloat(),taper*.65f,.035f,trunk,7)
            components++
        }
        // Branches spiral irregularly up the trunk; foliage clumps are elongated and leaf-like rather than round balls.
        val branchCount=when(species){1->8+rnd.nextInt(4);2->12+rnd.nextInt(3);else->11+rnd.nextInt(4)}
        for(i in 0 until branchCount){
            val a=i*2.399963+rnd.nextDouble()*.28
            val startY=height*(.24f+(i.toFloat()/(branchCount))* .56f)
            val speciesReach=if(species==1) 1.22f else if(species==2) .86f else 1f
            val reach=height*(.20f+rnd.nextFloat()*.18f)*speciesReach*(1f-(startY/height)*(if(species==1) .62f else .22f))
            val ex=(cos(a)*reach).toFloat()+leanX*(startY/height)
            val ez=(sin(a)*reach).toFloat()+leanZ*(startY/height)
            val ey=startY+height*(.08f+rnd.nextFloat()*.10f)
            b.taperedCylinder(leanX*(startY/height),startY,leanZ*(startY/height),ex,ey,ez,taper*.38f,taper*.12f,trunk,8)
            components++
            for(k in 0..3){
                val f=.55f+rnd.nextFloat()*.6f
                val cx=ex*f+(rnd.nextFloat()-.5f)*height*.09f
                val cz=ez*f+(rnd.nextFloat()-.5f)*height*.09f
                val cy=ey+(rnd.nextFloat()-.5f)*height*.12f
                val leafSize=height*(.19f+rnd.nextFloat()*.09f)
                leafCluster(b,cx,cy,cz,leafSize,a,palette[rnd.nextInt(palette.size)],seed+i*17+k)
                components++
            }
        }
        // Loose asymmetric crown with overlapping canopy lobes and gaps for a natural silhouette.
        val crownCount=if(species==1)7 else if(species==2)15 else 12
        for(i in 0 until crownCount){
            val a=i*PI*2.0/crownCount+rnd.nextDouble()*.4
            val r=height*(if(species==1) .08f else if(species==2) .18f else .12f+rnd.nextFloat()*.23f)
            val cx=(cos(a)*r).toFloat()+leanX*.65f
            val cz=(sin(a)*r).toFloat()+leanZ*.65f
            val cy=height*(.68f+rnd.nextFloat()*.25f)
            val leafSize=height*(if(species==1) .19f+rnd.nextFloat()*.08f else if(species==2) .27f+rnd.nextFloat()*.13f else .24f+rnd.nextFloat()*.12f)
            leafCluster(b,cx,cy,cz,leafSize,a,palette[rnd.nextInt(palette.size)],seed+i*31)
            components++
        }
        return TreeModel(b.snapshot(),components,height)
    }

    data class CharacterRig(val body:ForestMesh,val arm:ForestMesh,val upperLeg:ForestMesh,val lowerLeg:ForestMesh)
    fun characterRig(seed:Int=1):CharacterRig{
        val body=ForestMeshBuilder();val arm=ForestMeshBuilder();val upperLeg=ForestMeshBuilder();val lowerLeg=ForestMeshBuilder()
        val cloth=0xFF455762.toInt();val leather=0xFF66503B.toInt();val skin=0xFFD4A47C.toInt();val dark=0xFF26323A.toInt()
        // Main torso, coat layers, collar, belt, backpack and head are the stationary core.
        body.ellipsoid(0f,1.00f,0f,.24f,.34f,.15f,cloth,14,9)
        body.ellipsoid(0f,1.23f,0f,.20f,.21f,.14f,0xFF52636A.toInt(),13,8)
        body.ellipsoid(0f,1.45f,.005f,.13f,.14f,.13f,skin,13,8)
        body.ellipsoid(0f,1.58f,-.01f,.16f,.09f,.14f,leather,13,8)
        body.ellipsoid(0f,.88f,.16f,.19f,.045f,.035f,dark,12,7)
        body.ellipsoid(0f,1.02f,-.19f,.22f,.28f,.16f,leather,14,9)
        body.ellipsoid(0f,1.26f,-.20f,.18f,.07f,.14f,0xFF795D3F.toInt(),13,8)
        body.ellipsoid(-.16f,.92f,-.20f,.065f,.15f,.085f,0xFF76563B.toInt(),10,7)
        body.ellipsoid(.16f,.92f,-.20f,.065f,.15f,.085f,0xFF76563B.toInt(),10,7)
        body.ellipsoid(0f,1.11f,-.035f,.20f,.055f,.16f,0xFF51402E.toInt(),11,7)
        body.ellipsoid(-.12f,1.34f,.015f,.05f,.11f,.045f,leather,10,6)
        body.ellipsoid(.12f,1.34f,.015f,.05f,.11f,.045f,leather,10,6)
        body.ellipsoid(0f,1.62f,0f,.19f,.035f,.18f,0xFF3A3027.toInt(),13,8)
        body.ellipsoid(0f,1.68f,-.005f,.13f,.09f,.13f,0xFF514334.toInt(),13,8)
        body.ellipsoid(0f,1.55f,-.055f,.14f,.055f,.14f,0xFF352B24.toInt(),12,7)
        // Upper/lower arms are a compact sleeve-and-hand mesh, mirrored at shoulder pivots.
        arm.ellipsoid(0f,-.13f,0f,.095f,.14f,.095f,cloth,12,8)
        arm.ellipsoid(0f,-.28f,.015f,.075f,.12f,.075f,0xFF59656A.toInt(),11,7)
        arm.ellipsoid(0f,-.39f,.03f,.055f,.07f,.06f,skin,10,6)
        // Right hand carries a small field hatchet: haft and metal head.
        arm.taperedCylinder(.13f,-.30f,.09f,.18f,-.49f,.10f,.025f,.018f,0xFF765337.toInt(),8)
        arm.ellipsoid(.18f,-.50f,.10f,.09f,.04f,.045f,0xFF92999A.toInt(),10,6)
        arm.ellipsoid(.23f,-.50f,.10f,.04f,.055f,.045f,0xFFB6BEC0.toInt(),9,6)
        // Separate upper and lower legs are rotated around hip and knee during the gait.
        upperLeg.ellipsoid(0f,-.17f,0f,.12f,.20f,.11f,cloth,12,8)
        upperLeg.ellipsoid(0f,-.33f,.015f,.09f,.06f,.09f,0xFF4C5960.toInt(),10,6)
        lowerLeg.ellipsoid(0f,-.18f,.005f,.085f,.20f,.085f,0xFF4C5960.toInt(),12,8)
        lowerLeg.ellipsoid(0f,-.38f,.06f,.095f,.07f,.14f,dark,11,7)
        return CharacterRig(body.snapshot(),arm.snapshot(),upperLeg.snapshot(),lowerLeg.snapshot())
    }
    /** Multi-piece humanoid base model (50+ smooth geometry components). */
    fun character(seed:Int=1):ForestMesh {
        val b=ForestMeshBuilder()
        val rnd=java.util.Random(seed.toLong())
        val cloth=0xFF3E4F58.toInt(); val leather=0xFF66503B.toInt(); val skin=0xFFD4A47C.toInt(); val dark=0xFF26323A.toInt()
        // Core torso and layered clothing.
        b.ellipsoid(0f,.98f,0f,.24f,.34f,.15f,cloth,12,8)
        b.ellipsoid(0f,1.20f,0f,.20f,.22f,.14f,cloth,12,8)
        b.ellipsoid(0f,1.48f,0f,.14f,.14f,.13f,skin,12,8)
        b.ellipsoid(0f,1.59f,-.015f,.16f,.09f,.14f,leather,12,8)
        var pieces=4
        // Layered coat panels and belts.
        for(i in 0 until 6) {
            val side=if(i%2==0) -1f else 1f
            b.ellipsoid(side*.11f,.88f+(i/2)*.13f,.02f,.12f,.13f,.12f,if(i%3==0) leather else cloth,10,6); pieces++
        }
        b.ellipsoid(0f,.91f,.17f,.19f,.045f,.035f,dark,10,6); pieces++
        // Limbs: joint spheres + smooth segment capsules, articulated placeholders; total 50+.
        for(side in listOf(-1f,1f)) {
            // shoulders, upper arms, elbows, forearms, hands
            b.ellipsoid(side*.24f,1.20f,0f,.11f,.12f,.11f,cloth,10,6); pieces++
            b.ellipsoid(side*.30f,1.08f,0f,.085f,.12f,.085f,cloth,10,6); pieces++
            b.ellipsoid(side*.35f,.96f,0f,.075f,.08f,.075f,skin,10,6); pieces++
            b.ellipsoid(side*.38f,.84f,.01f,.065f,.11f,.065f,cloth,10,6); pieces++
            b.ellipsoid(side*.40f,.72f,.02f,.055f,.07f,.055f,skin,10,6); pieces++
            // Upper/lower leg, knee, ankle, boot layers.
            b.ellipsoid(side*.12f,.62f,0f,.13f,.16f,.13f,cloth,10,6); pieces++
            b.ellipsoid(side*.13f,.46f,0f,.105f,.14f,.105f,cloth,10,6); pieces++
            b.ellipsoid(side*.13f,.34f,0f,.085f,.09f,.085f,cloth,10,6); pieces++
            b.ellipsoid(side*.13f,.23f,.02f,.075f,.12f,.075f,leather,10,6); pieces++
            b.ellipsoid(side*.13f,.11f,.09f,.10f,.07f,.16f,dark,10,6); pieces++
        }
        // Small folds, seams and gear pouches add mesh detail without separate draw calls.
        for(i in 0 until 12) {
            val side=if(i%2==0) -1f else 1f
            b.ellipsoid(side*(.07f+(i%3)*.035f),.68f+(i/4)*.11f,.10f,.035f,.06f,.03f,if(i%3==0) leather else cloth,8,5); pieces++
        }
        // Add 12 belt/backpack/strap fittings to ensure geometry count comfortably exceeds 50.
        for(i in 0 until 12) {
            val side=if(i%2==0) -1f else 1f
            b.ellipsoid(side*.19f,.95f+(i%4)*.08f,-.12f,.045f,.05f,.045f,if(i%3==0) dark else leather,8,5); pieces++
        }
        // Slight deterministic surface variation accessories.
        repeat(6) { i ->
            val a=rnd.nextDouble()*PI*2.0
            b.ellipsoid((cos(a)*.13f).toFloat(),.76f+rnd.nextFloat()*.35f,(sin(a)*.13f).toFloat(),.035f,.04f,.035f,leather,8,5); pieces++
        }
        // Backpack, weathered straps, hood/hat layers, and carried field tool complete the silhouette.
        b.ellipsoid(0f,1.02f,-.19f,.22f,.29f,.16f,leather,12,8)
        b.ellipsoid(0f,1.26f,-.20f,.19f,.08f,.15f,0xFF795D3F.toInt(),12,7)
        b.ellipsoid(-.16f,.91f,-.20f,.07f,.16f,.09f,0xFF76563B.toInt(),10,6)
        b.ellipsoid(.16f,.91f,-.20f,.07f,.16f,.09f,0xFF76563B.toInt(),10,6)
        b.ellipsoid(0f,1.12f,-.035f,.21f,.06f,.17f,0xFF51402E.toInt(),10,6)
        b.ellipsoid(-.12f,1.35f,.015f,.05f,.12f,.045f,leather,9,6)
        b.ellipsoid(.12f,1.35f,.015f,.05f,.12f,.045f,leather,9,6)
        // Headwear: brim and crown, with a dark hair/hood rim.
        b.ellipsoid(0f,1.62f,0f,.19f,.035f,.18f,0xFF3A3027.toInt(),12,7)
        b.ellipsoid(0f,1.68f,-.005f,.13f,.09f,.13f,0xFF514334.toInt(),12,7)
        b.ellipsoid(0f,1.55f,-.055f,.14f,.055f,.14f,0xFF352B24.toInt(),12,7)
        // Tool haft and head carried at the side.
        b.taperedCylinder(.43f,.68f,.10f,.49f,1.00f,.10f,.035f,.022f,0xFF765337.toInt(),8)
        b.ellipsoid(.49f,1.02f,.10f,.11f,.055f,.05f,0xFF92999A.toInt(),10,6)
        b.ellipsoid(.55f,1.01f,.10f,.045f,.07f,.05f,0xFFB6BEC0.toInt(),10,6)
        repeat(8){i->
            val side=if(i%2==0)-1f else 1f
            b.ellipsoid(side*(.10f+(i/2)*.02f),.80f+(i%4)*.10f,-.23f,.025f,.035f,.025f,0xFF8C6B45.toInt(),8,5)
        }
        return b.snapshot()
    }
}
