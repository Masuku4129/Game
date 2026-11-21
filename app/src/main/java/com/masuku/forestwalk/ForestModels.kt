package com.masuku.forestwalk

import kotlin.math.*

/** Procedural organic model generators. Each model is assembled into a single indexed mesh. */
internal object ForestModels {
    data class TreeModel(val mesh:ForestMesh,val components:Int,val height:Float)

    /** A tree has 30+ separate smooth geometry components, with deterministic seed variation. */
    fun tree(seed:Int,height:Float=5.0f):TreeModel {
        val b=ForestMeshBuilder()
        val rnd=java.util.Random(seed.toLong())
        val trunk=0xFF58412C.toInt()
        val leafPalette=intArrayOf(0xFF28563A.toInt(),0xFF346644.toInt(),0xFF3E7449.toInt(),0xFF477C4A.toInt(),0xFF244C34.toInt())
        val taper=0.12f+height*.035f
        b.taperedCylinder(0f,0f,0f,0f,height,0f,taper,taper*.28f,trunk,12)
        var count=1
        // Eight major limbs, each with several foliage lobes.
        for(i in 0 until 8) {
            val a=i*PI/4.0+rnd.nextDouble()*.18
            val startY=height*(.30f+(i%3)*.10f)
            val reach=height*(.24f+rnd.nextFloat()*.13f)
            val endX=(cos(a)*reach).toFloat()
            val endZ=(sin(a)*reach).toFloat()
            b.taperedCylinder(0f,startY,0f,endX,startY+height*.12f,endZ,taper*.48f,taper*.16f,trunk,7)
            count++
            // 3 clusters per branch = 24; additional crown lobes ensure >=25 components total.
            for(k in 0..2) {
                val spread=.55f+(rnd.nextFloat()*.45f)
                val cx=endX*spread+(rnd.nextFloat()-.5f)*height*.10f
                val cz=endZ*spread+(rnd.nextFloat()-.5f)*height*.10f
                val cy=startY+height*.13f+k*height*.055f+(rnd.nextFloat()-.5f)*height*.08f
                val radius=height*(.14f+rnd.nextFloat()*.045f)
                b.ellipsoid(cx,cy,cz,radius*1.05f,radius*.88f,radius,rnd.nextInt(leafPalette.size).let{leafPalette[it]},10,7)
                count++
            }
        }
        // Crown center and four peripheral crown masses.
        for(i in 0..4) {
            val a=i*PI*2.0/5.0
            val radius=height*(.17f+rnd.nextFloat()*.03f)
            b.ellipsoid((cos(a)*height*.12f).toFloat(),height*(.72f+i*.025f),(sin(a)*height*.12f).toFloat(),radius,radius*.95f,radius,leafPalette[rnd.nextInt(leafPalette.size)],10,7)
            count++
        }
        return TreeModel(b.snapshot(),count,height)
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
        return b.snapshot()
    }
}
