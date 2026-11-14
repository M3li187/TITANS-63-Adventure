extends RefCounted
## MeshBatcher
## Collects procedurally generated geometry grouped by material key and commits
## it into ONE ArrayMesh with one surface per material. Thousands of individual
## parts (rivets, buttons, ribs, panels...) therefore cost only one draw call per
## material instead of one per part.
##
## Winding: Godot treats CLOCKWISE triangles as front faces. Every primitive here
## passes the intended outward normal and the triangle order is fixed
## automatically, so callers never have to think about winding.

var materials: Dictionary = {}
var _verts: Dictionary = {}
var _norms: Dictionary = {}
var _uvs: Dictionary = {}
var tri_count: int = 0


func _init(mats: Dictionary = {}) -> void:
	materials = mats


func _ensure(key: String) -> void:
	if not _verts.has(key):
		_verts[key] = []
		_norms[key] = []
		_uvs[key] = []


## World-space planar UVs (1 UV unit = 1 metre) picked from the dominant normal
## axis. Lets tiling panel textures line up across separate parts.
static func _uv(p: Vector3, n: Vector3) -> Vector2:
	var a := n.abs()
	if a.x >= a.y and a.x >= a.z:
		return Vector2(p.z, -p.y)
	if a.y >= a.z:
		return Vector2(p.x, p.z)
	return Vector2(p.x, -p.y)


static func _sp(v: float, e: float) -> float:
	return signf(v) * pow(absf(v), e)


# ---------------------------------------------------------------------------
# Low level
# ---------------------------------------------------------------------------
func add_tri_smooth(key: String, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3) -> void:
	var cr := (b - a).cross(c - a)
	if cr.length_squared() < 1e-14:
		return
	var face := na + nb + nc
	if cr.dot(face) > 0.0:
		var tp := b
		b = c
		c = tp
		var tn := nb
		nb = nc
		nc = tn
	_ensure(key)
	var v: Array = _verts[key]
	var nn: Array = _norms[key]
	var uu: Array = _uvs[key]
	var fn := face.normalized()
	v.append(a)
	v.append(b)
	v.append(c)
	nn.append(na.normalized())
	nn.append(nb.normalized())
	nn.append(nc.normalized())
	uu.append(_uv(a, fn))
	uu.append(_uv(b, fn))
	uu.append(_uv(c, fn))
	tri_count += 1


func add_tri(key: String, a: Vector3, b: Vector3, c: Vector3, n: Vector3) -> void:
	add_tri_smooth(key, a, b, c, n, n, n)


## a,b,c,d in cyclic order (either direction).
func add_quad(key: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
	add_tri(key, a, b, c, n)
	add_tri(key, a, c, d, n)


# ---------------------------------------------------------------------------
# Primitives
# ---------------------------------------------------------------------------
## Oriented box. The basis of xf must be orthonormal; size is the full extent.
func add_box_xf(key: String, xf: Transform3D, size: Vector3) -> void:
	var bs := xf.basis
	var o := xf.origin
	var hx := bs.x.normalized() * size.x * 0.5
	var hy := bs.y.normalized() * size.y * 0.5
	var hz := bs.z.normalized() * size.z * 0.5
	var nx := bs.x.normalized()
	var ny := bs.y.normalized()
	var nz := bs.z.normalized()
	add_quad(key, o + hx - hy - hz, o + hx + hy - hz, o + hx + hy + hz, o + hx - hy + hz, nx)
	add_quad(key, o - hx - hy - hz, o - hx - hy + hz, o - hx + hy + hz, o - hx + hy - hz, -nx)
	add_quad(key, o + hy - hx - hz, o + hy - hx + hz, o + hy + hx + hz, o + hy + hx - hz, ny)
	add_quad(key, o - hy - hx - hz, o - hy + hx - hz, o - hy + hx + hz, o - hy - hx + hz, -ny)
	add_quad(key, o + hz - hx - hy, o + hz + hx - hy, o + hz + hx + hy, o + hz - hx + hy, nz)
	add_quad(key, o - hz - hx - hy, o - hz - hx + hy, o - hz + hx + hy, o - hz + hx - hy, -nz)


func add_box(key: String, center: Vector3, size: Vector3) -> void:
	add_box_xf(key, Transform3D(Basis(), center), size)


## Rectangular beam from p0 to p1. `h` is measured along up_hint, `w` across.
func add_beam(key: String, p0: Vector3, p1: Vector3, w: float, h: float, up_hint: Vector3 = Vector3.UP) -> void:
	var d := p1 - p0
	var length := d.length()
	if length < 1e-5:
		return
	var f := d / length
	var up := up_hint.normalized()
	if absf(up.dot(f)) > 0.98:
		up = Vector3.RIGHT if absf(f.x) < 0.9 else Vector3.FORWARD
	var r := up.cross(f).normalized()
	var u := f.cross(r).normalized()
	add_box_xf(key, Transform3D(Basis(r, u, f), (p0 + p1) * 0.5), Vector3(w, h, length))


## Cylinder / truncated cone along the LOCAL Y axis, centred on xf.origin.
func add_cyl_xf(key: String, xf: Transform3D, r: float, h: float, seg: int = 12, caps: bool = true, r_top: float = -1.0) -> void:
	if r_top < 0.0:
		r_top = r
	var bs := xf.basis
	var slope := (r - r_top) / maxf(h, 1e-5)
	var top_c := xf * Vector3(0, h * 0.5, 0)
	var bot_c := xf * Vector3(0, -h * 0.5, 0)
	var up := bs.y.normalized()
	for i in seg:
		var a0 := TAU * float(i) / float(seg)
		var a1 := TAU * float(i + 1) / float(seg)
		var c0 := cos(a0)
		var s0 := sin(a0)
		var c1 := cos(a1)
		var s1 := sin(a1)
		var b0 := xf * Vector3(c0 * r, -h * 0.5, s0 * r)
		var b1 := xf * Vector3(c1 * r, -h * 0.5, s1 * r)
		var t0 := xf * Vector3(c0 * r_top, h * 0.5, s0 * r_top)
		var t1 := xf * Vector3(c1 * r_top, h * 0.5, s1 * r_top)
		var n0 := (bs * Vector3(c0, slope, s0)).normalized()
		var n1 := (bs * Vector3(c1, slope, s1)).normalized()
		add_tri_smooth(key, b0, b1, t1, n0, n1, n1)
		add_tri_smooth(key, b0, t1, t0, n0, n1, n0)
		if caps:
			if r_top > 0.0:
				add_tri(key, top_c, t0, t1, up)
			if r > 0.0:
				add_tri(key, bot_c, b1, b0, -up)


func add_cyl_between(key: String, p0: Vector3, p1: Vector3, r: float, seg: int = 10, caps: bool = true) -> void:
	var d := p1 - p0
	var length := d.length()
	if length < 1e-5:
		return
	var y := d / length
	var ref := Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT
	var x := y.cross(ref).normalized()
	var z := x.cross(y).normalized()
	add_cyl_xf(key, Transform3D(Basis(x, y, z), (p0 + p1) * 0.5), r, length, seg, caps)


## Superellipsoid ("rounded box"). e = 1 -> ellipsoid, e -> 0 -> box.
## Used for cushions, pads, domes and rounded housings.
func add_superquad(key: String, xf: Transform3D, half: Vector3, e: float = 0.3, su: int = 16, sv: int = 10) -> void:
	var pts := []
	var nrm := []
	var bs := xf.basis
	for j in sv + 1:
		var phi := -PI * 0.5 + PI * float(j) / float(sv)
		var cp := cos(phi)
		var spv := sin(phi)
		for i in su + 1:
			var th := -PI + TAU * float(i) / float(su)
			var ct := cos(th)
			var st := sin(th)
			var p := Vector3(_sp(cp, e) * _sp(ct, e) * half.x, _sp(spv, e) * half.y, _sp(cp, e) * _sp(st, e) * half.z)
			var n := Vector3(_sp(cp, 2.0 - e) * _sp(ct, 2.0 - e) / half.x, _sp(spv, 2.0 - e) / half.y, _sp(cp, 2.0 - e) * _sp(st, 2.0 - e) / half.z)
			if n.length_squared() < 1e-12:
				n = Vector3(0, signf(spv), 0)
			pts.append(xf * p)
			nrm.append((bs * n).normalized())
	var row := su + 1
	for j in sv:
		for i in su:
			var i00 := j * row + i
			var i10 := i00 + 1
			var i01 := i00 + row
			var i11 := i01 + 1
			add_tri_smooth(key, pts[i00], pts[i10], pts[i11], nrm[i00], nrm[i10], nrm[i11])
			add_tri_smooth(key, pts[i00], pts[i11], pts[i01], nrm[i00], nrm[i11], nrm[i01])


func add_sphere(key: String, center: Vector3, r: float, su: int = 14, sv: int = 8) -> void:
	add_superquad(key, Transform3D(Basis(), center), Vector3(r, r, r), 1.0, su, sv)


## Thick plate from a (roughly planar, star-shaped) polygon. `n` is the front
## normal; the plate extends `t` behind the polygon (along -n).
func add_slab(key: String, pts: Array, n: Vector3, t: float) -> void:
	n = n.normalized()
	var cnt := pts.size()
	if cnt < 3:
		return
	var c := Vector3.ZERO
	for p in pts:
		c += p
	c /= float(cnt)
	var back := []
	for p in pts:
		back.append(p - n * t)
	var cb := c - n * t
	for i in cnt:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[(i + 1) % cnt]
		var ba: Vector3 = back[i]
		var bb: Vector3 = back[(i + 1) % cnt]
		add_tri(key, c, a, b, n)
		add_tri(key, cb, ba, bb, -n)
		if t > 0.0:
			var sn := (b - a).cross(n).normalized()
			if sn.dot((a + b) * 0.5 - c) < 0.0:
				sn = -sn
			add_quad(key, a, b, bb, ba, sn)


## Shrinks a polygon toward its centroid by an absolute distance (for panel gaps).
static func shrink(pts: Array, amount: float) -> Array:
	var c := Vector3.ZERO
	for p in pts:
		c += p
	c /= float(pts.size())
	var out := []
	for p in pts:
		var d: Vector3 = p - c
		var l := d.length()
		out.append(c + d * maxf(l - amount, 0.0) / maxf(l, 1e-6))
	return out


# ---------------------------------------------------------------------------
# Commit
# ---------------------------------------------------------------------------
func build(node_name: String) -> MeshInstance3D:
	var mesh := ArrayMesh.new()
	var keys := _verts.keys()
	keys.sort()
	for key in keys:
		var v: Array = _verts[key]
		if v.is_empty():
			continue
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = PackedVector3Array(v)
		arr[Mesh.ARRAY_NORMAL] = PackedVector3Array(_norms[key])
		arr[Mesh.ARRAY_TEX_UV] = PackedVector2Array(_uvs[key])
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var idx := mesh.get_surface_count() - 1
		mesh.surface_set_name(idx, str(key))
		if materials.has(key):
			mesh.surface_set_material(idx, materials[key])
		else:
			push_warning("MeshBatcher: no material for key '%s'" % key)
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	return mi
