extends RigidBody3D
class_name BoatBody
## 被弾 -> 穴 -> 浸水 -> 浮力低下 + 穴側に荷重 -> 傾いて沈む船。
## 水は全流体シミュレーションせず「溜まった水の量」を数値で持つ。
## 浮力は船体4点(+中央)でサンプルし、点ごとに force + torque を加える。

const WATER_Y := 0.0
const BUOY_K := 4300.0          # 1点あたり浮力係数 (深さ1mあたり)
const FLOOD_CAPACITY := 1.0      # flood_ratio 0..1 で正規化
const BUOY_POINTS: Array[Vector3] = [
	Vector3(-0.95, 0.30, -2.30),
	Vector3(0.95, 0.30, -2.30),
	Vector3(-0.95, 0.30, 2.30),
	Vector3(0.95, 0.30, 2.30),
	Vector3(0.0, 0.30, 0.0),
]

var flood_ratio: float = 0.0
var holes: Array[Dictionary] = []   # {local: Vector3, normal: Vector3}
var time_s: float = 0.0
var sunk: bool = false

var _interior_water: MeshInstance3D
var _hole_container: Node3D
var _foam_nodes: Array[MeshInstance3D] = []

static func water_height_at(x: float, z: float, t: float) -> float:
	# EXACTLY the same 3 directional sine waves as shaders/water.gdshader
	# (dirs / frequencies / speeds / amplitudes). Do not change one without
	# the other, or buoyancy will drift away from the visual surface.
	var h := 0.0
	h += 0.140 * sin((x * 0.92 + z * 0.39) * 1.05 + t * 1.15)
	h += 0.090 * sin((x * -0.52 + z * 0.86) * 1.65 + t * 1.55)
	h += 0.045 * sin((x * 0.98 + z * -0.20) * 3.10 + t * 2.30)
	return WATER_Y + h

func _ready() -> void:
	mass = 600.0
	collision_layer = 2
	collision_mask = 0
	linear_damp = 0.6
	angular_damp = 1.2
	can_sleep = false
	contact_monitor = false
	_build_collision()
	_build_boat_model()
	_build_interior_water()
	_build_character()
	_hole_container = Node3D.new()
	_hole_container.name = "Holes"
	add_child(_hole_container)

# ---------------------------------------------------------------- 構築
func _mat(color: Color, rough: float = 0.75, metallic: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metallic
	return m

func _box(parent: Node, size: Vector3, pos: Vector3, color: Color, rot_deg: Vector3 = Vector3.ZERO, rough: float = 0.75) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(color, rough)
	mi.position = pos
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi

func _cyl(parent: Node, radius: float, height: float, pos: Vector3, color: Color, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	mi.mesh = cm
	mi.material_override = _mat(color, 0.7)
	mi.position = pos
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi

func _sphere(parent: Node, radius: float, pos: Vector3, color: Color, scale_v: Vector3 = Vector3.ONE, rough: float = 0.65) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	mi.mesh = sm
	mi.material_override = _mat(color, rough)
	mi.position = pos
	mi.scale = scale_v
	parent.add_child(mi)
	return mi

func _capsule(parent: Node, radius: float, height: float, pos: Vector3, color: Color, rot_deg: Vector3 = Vector3.ZERO, scale_v: Vector3 = Vector3.ONE, rough: float = 0.55) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = radius
	cm.height = height
	cm.radial_segments = 12
	cm.rings = 6
	mi.mesh = cm
	mi.material_override = _mat(color, rough)
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.scale = scale_v
	parent.add_child(mi)
	return mi

func _build_collision() -> void:
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.3, 1.15, 6.1)
	cs.shape = shape
	cs.position = Vector3(0, 0.62, 0)
	add_child(cs)

func _boat_pbr(name: String, color: Color, rough: float, metallic: float = 0.0, rough_tex: Texture2D = null) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.resource_name = name
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metallic
	if rough_tex:
		m.roughness_texture = rough_tex
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

var _boat_mats: Dictionary = {}

func _get_boat_mats() -> Dictionary:
	if not _boat_mats.is_empty():
		return _boat_mats
	var nt := NoiseTexture2D.new()
	nt.width = 256
	nt.height = 256
	nt.seamless = true
	var fn := FastNoiseLite.new()
	fn.noise_type = FastNoiseLite.TYPE_PERLIN
	fn.frequency = 0.06
	nt.noise = fn
	var gel := _boat_pbr("HullWhite", Color(0.93, 0.95, 0.96), 0.62, 0.0, nt)
	_boat_mats["HullWhite"] = gel
	_boat_mats["ConsoleWhite"] = _boat_pbr("ConsoleWhite", Color(0.91, 0.93, 0.94), 0.62, 0.0, nt)
	_boat_mats["HullBottom"] = _boat_pbr("HullBottom", Color(0.04, 0.11, 0.14), 0.50)
	_boat_mats["DeckGray"] = _boat_pbr("DeckGray", Color(0.58, 0.61, 0.61), 0.92, 0.0, nt)
	_boat_mats["VinylTeal"] = _boat_pbr("VinylTeal", Color(0.0, 0.45, 0.48), 0.55)
	_boat_mats["WoodBrown"] = _boat_pbr("WoodBrown", Color(0.48, 0.29, 0.14), 0.85, 0.0, nt)
	_boat_mats["CrateDark"] = _boat_pbr("CrateDark", Color(0.30, 0.18, 0.08), 0.88)
	_boat_mats["OrangeHatch"] = _boat_pbr("OrangeHatch", Color(0.80, 0.30, 0.02), 0.50)
	_boat_mats["MetalRail"] = _boat_pbr("MetalRail", Color(0.78, 0.80, 0.82), 0.30, 0.90)
	_boat_mats["BlackParts"] = _boat_pbr("BlackParts", Color(0.04, 0.045, 0.05), 0.55, 0.20)
	_boat_mats["MotorDark"] = _boat_pbr("MotorDark", Color(0.07, 0.08, 0.09), 0.42, 0.35)
	var glass := _boat_pbr("GlassWindshield", Color(0.25, 0.55, 0.65, 0.38), 0.08, 0.10)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_boat_mats["GlassWindshield"] = glass
	for nav in [["NavRed", Color(0.90, 0.05, 0.05)], ["NavGreen", Color(0.05, 0.85, 0.25)]]:
		var nm := _boat_pbr(nav[0], nav[1], 0.40)
		nm.emission_enabled = true
		nm.emission = nav[1]
		nm.emission_energy_multiplier = 2.0
		_boat_mats[nav[0]] = nm
	return _boat_mats

func _build_boat_model() -> void:
	# Blender-authored boat (tools/build_boat_model.py -> assets/boat.obj).
	# OBJ is text so it survives the GitHub snapshot push; surfaces are named
	# after the Blender materials and get rich PBR overrides here.
	var mesh := load("res://assets/boat.obj") as Mesh
	if mesh == null:
		push_warning("boat.obj failed to load; boat will be invisible")
		return
	var mi := MeshInstance3D.new()
	mi.name = "BoatModel"
	mi.mesh = mesh
	add_child(mi)
	var mats := _get_boat_mats()
	var keys: Array = mats.keys()
	for i in mesh.get_surface_count():
		var sname := ""
		if mesh is ArrayMesh:
			sname = (mesh as ArrayMesh).surface_get_name(i)
		var existing := mesh.surface_get_material(i)
		var hay := sname
		if existing:
			hay += "|" + existing.resource_name
		for k in keys:
			if hay.contains(k):
				mi.set_surface_override_material(i, mats[k])
				break
	# 射撃の当たり判定は見た目メッシュそのものに合わせる (v2.1)。
	# 旧仕様は大きな箱コリジョンに当たっていたため、上から撃つと
	# 「狙った舷側」ではなく箱の上面に穴が開いて見えた。
	var area := Area3D.new()
	area.name = "HitArea"
	area.collision_layer = 4
	area.collision_mask = 0
	area.monitoring = false
	area.monitorable = true
	var cs := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(mesh.get_faces())
	cs.shape = shape
	area.add_child(cs)
	mi.add_child(area)

func _build_interior_water() -> void:
	# 船内の溜まり水 (浸水で上昇する透明な水面) — 子供なので船と一緒に傾く
	_interior_water = _box(self, Vector3(1.88, 0.06, 5.55), Vector3(0, 0.47, 0.05), Color(0.15, 0.75, 0.82, 0.78))
	var wm := _interior_water.material_override as StandardMaterial3D
	wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wm.roughness = 0.15
	_interior_water.visible = false

func _build_character() -> void:
	# 写真の男性: 船尾に立ち船首を向く。上半身裸・赤い水着・金髪寄りの短髪。
	# v2: 手足と胴は CapsuleMesh で丸みを持たせた (旧版は円柱)。
	var man := Node3D.new()
	man.name = "Man"
	man.position = Vector3(-0.42, 0.46, -1.88)
	man.rotation_degrees = Vector3(0, 4, 0)
	man.scale = Vector3.ONE * 1.12
	add_child(man)
	var skin := Color(0.76, 0.50, 0.35)
	var skin2 := Color(0.70, 0.45, 0.31)
	# 脚 (カプセル)
	_capsule(man, 0.078, 0.66, Vector3(-0.13, 0.33, 0), skin2)
	_capsule(man, 0.078, 0.66, Vector3(0.14, 0.33, 0.02), skin2)
	# 赤い水着 (横縞つき)
	_box(man, Vector3(0.44, 0.36, 0.30), Vector3(0, 0.78, 0), Color(0.78, 0.16, 0.20))
	_box(man, Vector3(0.45, 0.05, 0.31), Vector3(0, 0.86, 0), Color(0.92, 0.88, 0.85))
	_box(man, Vector3(0.45, 0.04, 0.31), Vector3(0, 0.70, 0), Color(0.92, 0.88, 0.85))
	# 上半身 (裸の背中がカメラ側 = -Z): カプセルの胴 + 肩
	_capsule(man, 0.205, 0.74, Vector3(0, 1.28, 0), skin, Vector3.ZERO, Vector3(1.18, 1.0, 0.76))
	_sphere(man, 0.19, Vector3(0, 1.60, 0), skin, Vector3(1.2, 0.38, 0.78), 0.55) # 肩
	# 腕 (カプセル, 体の横に下ろす)
	_capsule(man, 0.066, 0.64, Vector3(-0.315, 1.20, 0.0), skin2, Vector3(0, 0, 6))
	_capsule(man, 0.066, 0.64, Vector3(0.325, 1.20, 0.03), skin2, Vector3(-5, 0, -8))
	_sphere(man, 0.07, Vector3(-0.345, 0.88, 0.02), skin2, Vector3.ONE, 0.55) # 手
	_sphere(man, 0.07, Vector3(0.365, 0.88, 0.06), skin2, Vector3.ONE, 0.55)
	# 首・頭 + 髪 (金髪寄り)
	_capsule(man, 0.06, 0.16, Vector3(0, 1.67, 0.01), skin2)
	_sphere(man, 0.145, Vector3(0, 1.84, 0.01), skin, Vector3.ONE, 0.55)
	_sphere(man, 0.15, Vector3(0, 1.895, -0.02), Color(0.62, 0.48, 0.26), Vector3(1.0, 0.60, 1.0), 0.7)

# ---------------------------------------------------------------- 被弾
func register_hit(world_pos: Vector3, world_normal: Vector3) -> void:
	var local_pos := to_local(world_pos)
	var local_n := (global_transform.basis.inverse() * world_normal).normalized()
	holes.append({"local": local_pos, "normal": local_n})
	# 穴の見た目: 黒い丸 + 焦げ縁
	var h := MeshInstance3D.new()
	var smesh := SphereMesh.new()
	smesh.radius = 0.10
	smesh.height = 0.20
	h.mesh = smesh
	h.material_override = _mat(Color(0.03, 0.03, 0.035), 0.95)
	h.position = local_pos + local_n * 0.02
	h.scale = Vector3(1, 1, 1)
	_hole_container.add_child(h)
	var rim := MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.085
	ring.outer_radius = 0.125
	rim.mesh = ring
	rim.material_override = _mat(Color(0.25, 0.22, 0.18), 0.9)
	rim.position = local_pos + local_n * 0.03
	rim.look_at_from_position(rim.position, rim.position + local_n, Vector3.UP if abs(local_n.y) < 0.9 else Vector3.RIGHT)
	_hole_container.add_child(rim)
	# 漏水の泡/しぶき (船内側に白い泡)
	if local_pos.y < 1.0:
		var foam := _sphere(self, 0.10, Vector3(local_pos.x * 0.82, 0.55, local_pos.z * 0.92), Color(0.95, 0.99, 1.0, 0.5))
		var fm := foam.material_override as StandardMaterial3D
		fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_foam_nodes.append(foam)

func clear_holes() -> void:
	holes.clear()
	for c in _hole_container.get_children():
		c.queue_free()
	for f in _foam_nodes:
		f.queue_free()
	_foam_nodes.clear()

func reset_boat() -> void:
	clear_holes()
	flood_ratio = 0.0
	sunk = false
	global_transform = Transform3D(Basis.from_euler(Vector3(0, -0.42, 0)), Vector3(0, 0.05, 0))
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	freeze = false

# ---------------------------------------------------------------- 物理
func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var dt: float = state.step
	time_s += dt
	var xform := state.transform
	var buoy_factor: float = 1.0 - flood_ratio * 0.78
	# --- 浮力 (点ごとに force + torque) ---
	for p_local in BUOY_POINTS:
		var p_world: Vector3 = xform * p_local
		var wh: float = water_height_at(p_world.x, p_world.z, time_s)
		var depth: float = wh - p_world.y + 0.28
		if depth > 0.0:
			var f := Vector3.UP * (depth * BUOY_K * buoy_factor)
			var offset: Vector3 = p_world - xform.origin
			state.apply_central_force(f)
			state.apply_torque(offset.cross(f))
		# 水の抵抗
		var point_vel: Vector3 = state.linear_velocity + state.angular_velocity.cross(p_world - xform.origin)
		var drag := -point_vel * 55.0 * (1.0 if depth > 0.0 else 0.15)
		var off2: Vector3 = p_world - xform.origin
		state.apply_central_force(drag)
		state.apply_torque(off2.cross(drag))
	# --- 浸水の重さ: 穴の平均位置に下向き荷重 -> 穴側へ傾く ---
	if flood_ratio > 0.001 and holes.size() > 0:
		var center := Vector3.ZERO
		for h in holes:
			center += (h["local"] as Vector3)
		center /= float(holes.size())
		var c_world: Vector3 = xform * center
		var weight := Vector3.DOWN * (flood_ratio * mass * 9.8 * 0.95)
		state.apply_central_force(weight)
		state.apply_torque((c_world - xform.origin).cross(weight))
	elif flood_ratio > 0.001:
		state.apply_central_force(Vector3.DOWN * (flood_ratio * mass * 9.8 * 0.95))
	# --- 浸水量の更新: 水面より下の穴だけが効く ---
	if holes.size() > 0 and flood_ratio < FLOOD_CAPACITY:
		var inflow := 0.0
		for h in holes:
			var lp: Vector3 = h["local"]
			var wp: Vector3 = xform * lp
			var wh2: float = water_height_at(wp.x, wp.z, time_s)
			var below: float = wh2 - wp.y
			if below > 0.0:
				inflow += 0.010 + below * 0.030
		flood_ratio = minf(FLOOD_CAPACITY, flood_ratio + inflow * dt)
	if global_position.y < -2.6:
		sunk = true

func _process(_delta: float) -> void:
	# 船内の水面: 浸水量に応じてデッキ内で上昇
	if _interior_water:
		_interior_water.visible = flood_ratio > 0.02
		_interior_water.position.y = lerpf(0.47, 1.10, flood_ratio)
		var s: float = 0.75 + 0.45 * sin(time_s * 2.2) * flood_ratio
		for i in _foam_nodes.size():
			var f := _foam_nodes[i]
			var grow: float = 0.55 + flood_ratio * 0.5 + 0.08 * sin(time_s * 3.0 + float(i) * 1.7)
			f.scale = Vector3.ONE * grow
			f.position.y = _interior_water.position.y + 0.05

func status_text() -> String:
	if sunk or flood_ratio >= 0.99:
		return "沈没…"
	if flood_ratio > 0.55:
		return "もう乗っていられない"
	if flood_ratio > 0.15:
		return "浸水中"
	if holes.size() > 0:
		return "被弾 (水面上の穴は浸水しない)"
	return "浮いている"
