extends RefCounted
## Cloak cloth simulation: PBD particles pinned to the animated body by springs (follow-through / lag),
## aerodynamic drag (quadratic, billows when running), pseudo-gravity relative to the body, capsule collision against the body.
## Particle displacements are applied to the mesh in a vertex shader (see shaders/cloak_skin.gdshader).

const G := 9.81
const MAX_PARTICLES := 192

var n := 0
var vertex_count := 0
var rest := PackedVector3Array()
var nrm := PackedVector3Array()
var bone_idx := PackedInt32Array()
var bone_w := PackedFloat32Array()
var ea := PackedInt32Array()
var eb := PackedInt32Array()
var omega := PackedFloat32Array()
var zeta := PackedFloat32Array()
var maxd := PackedFloat32Array()
var invm := PackedFloat32Array()
var wp := PackedFloat32Array()
var cap_a := PackedInt32Array()
var cap_b := PackedInt32Array()
var rel_caps: Array = []              # per particle: PackedInt32Array of capsule ids
var rel_clear: Array = []             # per particle: PackedFloat32Array clearances
var p := PackedVector3Array()
var v := PackedVector3Array()
var T := PackedVector3Array()
var Tprev := PackedVector3Array()
var N := PackedVector3Array()
var elen := PackedFloat32Array()
var disp := PackedVector3Array()
var vtx_idx := PackedFloat32Array()    # 4 per vertex
var vtx_w := PackedFloat32Array()      # 4 per vertex
var wind := Vector3.ZERO
var k_q := 0.30
var k_t := 0.25
var time := 0.0
var started := false
var enabled := true
var stat_max_disp := 0.0

func setup(solver) -> bool:
	var f := FileAccess.open("res://assets/cloak.json", FileAccess.READ)
	if f == null:
		push_error("cloak.json missing")
		return false
	var d: Dictionary = JSON.parse_string(f.get_as_text())
	n = int(d["n"])
	vertex_count = int(d["vertex_count"])
	if n > MAX_PARTICLES:
		push_error("too many particles")
		return false
	var pos: Array = d["pos"]
	var nr: Array = d["nrm"]
	var bones: Array = d["bones"]
	var weights: Array = d["weights"]
	var kp: Array = d["wsim"]
	var md: Array = d["maxd"]
	rest.resize(n)
	nrm.resize(n)
	bone_idx.resize(n * 4)
	bone_w.resize(n * 4)
	omega.resize(n)
	zeta.resize(n)
	maxd.resize(n)
	invm.resize(n)
	wp.resize(n)
	for i in n:
		var a: Array = pos[i]
		rest[i] = Vector3(a[0], a[1], a[2])
		var b: Array = nr[i]
		nrm[i] = Vector3(b[0], b[1], b[2])
		for k in 4:
			bone_idx[i * 4 + k] = int(solver.idx[bones[i][k]])
			bone_w[i * 4 + k] = float(weights[i][k])
		var w: float = float(kp[i])
		wp[i] = w
		omega[i] = 26.0 * (1.0 - w) * (1.0 - w) + 5.0 * w
		zeta[i] = 0.35 - 0.12 * w
		maxd[i] = float(md[i])
		invm[i] = 0.03 + w
	var edges: Array = d["edges"]
	ea.resize(edges.size())
	eb.resize(edges.size())
	for e in edges.size():
		ea[e] = int(edges[e][0])
		eb[e] = int(edges[e][1])
	elen.resize(edges.size())
	var caps: Array = d["caps"]
	cap_a.resize(caps.size())
	cap_b.resize(caps.size())
	for c in caps.size():
		cap_a[c] = int(solver.idx[caps[c]["a"]])
		cap_b[c] = int(solver.idx[caps[c]["b"]])
	var clear: Array = d["clear"]
	for i in n:
		var ids := PackedInt32Array()
		var cl := PackedFloat32Array()
		for c in caps.size():
			var cv: float = float(clear[i][c])
			if cv > 0.0:
				ids.append(c)
				cl.append(cv)
		rel_caps.append(ids)
		rel_clear.append(cl)
	p.resize(n)
	v.resize(n)
	T.resize(n)
	Tprev.resize(n)
	N.resize(n)
	disp.resize(MAX_PARTICLES)
	# per-vertex binding
	var fb := FileAccess.open("res://assets/cloak_vtx.bin", FileAccess.READ)
	if fb == null:
		push_error("cloak_vtx.bin missing")
		return false
	var raw := fb.get_buffer(fb.get_length()).to_float32_array()
	vtx_idx = raw.slice(0, vertex_count * 4)
	vtx_w = raw.slice(vertex_count * 4, vertex_count * 8)
	return true

func _targets(solver) -> void:
	for i in n:
		var t := Vector3.ZERO
		var nn := Vector3.ZERO
		for k in 4:
			var b := bone_idx[i * 4 + k]
			var w := bone_w[i * 4 + k]
			if w <= 0.0:
				continue
			var q: Quaternion = solver.D[b]
			t += (q * (rest[i] - solver.rest_pos[b]) + solver.P[b]) * w
			nn += (q * nrm[i]) * w
		T[i] = t
		N[i] = nn.normalized() if nn.length() > 1e-6 else Vector3.UP

func step(dt: float, solver) -> void:
	if n == 0:
		return
	_targets(solver)
	if not started:
		for i in n:
			p[i] = T[i]
			v[i] = Vector3.ZERO
			Tprev[i] = T[i]
		started = true
	var inv_dt := 1.0 / dt
	var vT := PackedVector3Array()
	vT.resize(n)
	for i in n:
		vT[i] = (T[i] - Tprev[i]) * inv_dt
		Tprev[i] = T[i]
	for e in ea.size():
		elen[e] = (T[eb[e]] - T[ea[e]]).length()
	var substeps := 2
	var iters := 2
	var h := dt / float(substeps)
	var hips_d: Quaternion = solver.D[solver.idx["Hips"]]
	var g_rel := Vector3(0, -G, 0) - hips_d * Vector3(0, -G, 0)
	time += dt
	var gust := 0.35 * Vector3(sin(time * 1.7), 0, sin(time * 1.3 + 1.0))
	var wnd := wind + gust
	var segA := PackedVector3Array()
	var segB := PackedVector3Array()
	segA.resize(cap_a.size())
	segB.resize(cap_a.size())
	for c in cap_a.size():
		segA[c] = solver.P[cap_a[c]]
		segB[c] = solver.P[cap_b[c]]
	var p0 := PackedVector3Array()
	p0.resize(n)
	for _s in substeps:
		for i in n:
			p0[i] = p[i]
			var pv := v[i]
			var nrm_i := N[i]
			var vrel := pv - wnd
			var vn := vrel.dot(nrm_i)
			var w := wp[i]
			var a := g_rel * (0.4 + 0.6 * w)
			a -= nrm_i * (k_q * absf(vn) * vn)
			a -= (vrel - nrm_i * vn) * (k_t * 0.5)
			var om := omega[i]
			a += (T[i] - p[i]) * (om * om) + (vT[i] - pv) * (2.0 * zeta[i] * om)
			pv += a * h
			v[i] = pv
			p[i] = p[i] + pv * h
		for _it in iters:
			for e in ea.size():
				var i := ea[e]
				var j := eb[e]
				var dv := p[j] - p[i]
				var L := dv.length() + 1e-9
				var wi := invm[i]
				var wj := invm[j]
				var c := (L - elen[e]) / L / (wi + wj) * 0.8
				p[i] = p[i] + dv * (c * wi)
				p[j] = p[j] - dv * (c * wj)
			for i in n:
				var off := p[i] - T[i]
				var ol := off.length()
				if ol > maxd[i]:
					p[i] = T[i] + off / ol * maxd[i]
				var ids: PackedInt32Array = rel_caps[i]
				var cls: PackedFloat32Array = rel_clear[i]
				var pi := p[i]
				for q in ids.size():
					var c2 := ids[q]
					var A := segA[c2]
					var ab := segB[c2] - A
					var t := clampf((pi - A).dot(ab) / maxf(ab.dot(ab), 1e-9), 0.0, 1.0)
					var cp := A + ab * t
					var dd := pi - cp
					var dl := dd.length() + 1e-9
					if dl < cls[q]:
						pi = cp + dd / dl * cls[q]
				if pi.y < 0.02:
					pi.y = 0.02
				p[i] = pi
		for i in n:
			v[i] = (p[i] - p0[i]) / h * 0.998
	var mx := 0.0
	for i in n:
		var d := p[i] - T[i]
		disp[i] = d
		mx = maxf(mx, d.length())
	stat_max_disp = mx
