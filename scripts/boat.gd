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
	return WATER_Y + sin(x * 0.18 + t * 0.9) * 0.07 + cos(z * 0.14 + t * 0.7) * 0.07

func _ready() -> void:
	mass = 600.0
	collision_layer = 2
	collision_mask = 0
	linear_damp = 0.6
	angular_damp = 1.2
	can_sleep = false
	contact_monitor = false
	_build_collision()
	_build_hull()
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

func _sphere(parent: Node, radius: float, pos: Vector3, color: Color, scale_v: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	mi.mesh = sm
	mi.material_override = _mat(color, 0.65)
	mi.position = pos
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

func _build_hull() -> void:
	var white := Color(0.88, 0.89, 0.90)
	var white2 := Color(0.78, 0.80, 0.81)
	var deck_c := Color(0.66, 0.68, 0.68)
	# 船底
	_box(self, Vector3(1.95, 0.22, 5.55), Vector3(0, 0.22, -0.15), white2)
	# 左右の舷側 (少し外開き)
	_box(self, Vector3(0.16, 0.95, 5.9), Vector3(-1.06, 0.78, -0.05), white, Vector3(0, 0, -6))
	_box(self, Vector3(0.16, 0.95, 5.9), Vector3(1.06, 0.78, -0.05), white, Vector3(0, 0, 6))
	# 船尾トランサム
	_box(self, Vector3(2.25, 0.95, 0.16), Vector3(0, 0.78, -3.0), white)
	# 船首: 左右を寄せた2枚 + 前面パネル
	_box(self, Vector3(0.16, 0.95, 1.7), Vector3(-0.72, 0.78, 3.25), white, Vector3(0, 38, -6))
	_box(self, Vector3(0.16, 0.95, 1.7), Vector3(0.72, 0.78, 3.25), white, Vector3(0, -38, 6))
	_box(self, Vector3(1.05, 0.9, 0.16), Vector3(0, 0.76, 3.95), white)
	# ガンネル (上縁レール)
	_box(self, Vector3(0.24, 0.09, 6.0), Vector3(-1.08, 1.28, -0.05), white, Vector3(0, 0, -6))
	_box(self, Vector3(0.24, 0.09, 6.0), Vector3(1.08, 1.28, -0.05), white, Vector3(0, 0, 6))
	_box(self, Vector3(2.3, 0.09, 0.24), Vector3(0, 1.28, -3.0), white)
	# 内側デッキ床
	_box(self, Vector3(1.95, 0.07, 5.7), Vector3(0, 0.42, 0.1), deck_c)
	# 船首デッキ (写真の白い前甲板 + オレンジのハッチ)
	_box(self, Vector3(1.85, 0.09, 1.55), Vector3(0, 1.16, 3.05), white)
	_box(self, Vector3(0.62, 0.10, 0.85), Vector3(0, 1.24, 3.0), Color(0.78, 0.36, 0.07))
	# 後部ベンチ + 木箱 (写真中央の茶色い箱)
	_box(self, Vector3(1.85, 0.42, 0.55), Vector3(0, 0.66, 1.55), white2)
	_box(self, Vector3(0.85, 0.30, 0.45), Vector3(0.15, 0.82, 1.55), Color(0.58, 0.35, 0.13))
	# センターコンソール + 風防 + ハンドル
	_box(self, Vector3(0.85, 0.85, 0.55), Vector3(0, 0.85, 0.35), white)
	var shield := _box(self, Vector3(0.85, 0.55, 0.05), Vector3(0, 1.55, 0.52), Color(0.55, 0.8, 0.85, 0.45), Vector3(-18, 0, 0))
	var sm := shield.material_override as StandardMaterial3D
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_cyl(self, 0.20, 0.06, Vector3(-0.25, 1.22, 0.02), Color(0.12, 0.12, 0.13), Vector3(70, 0, 0))
	_box(self, Vector3(0.34, 0.24, 0.06), Vector3(0.18, 1.28, 0.10), Color(0.10, 0.13, 0.16))
	# 船尾ベンチ
	_box(self, Vector3(1.85, 0.35, 0.5), Vector3(0, 0.62, -2.55), white2)
	# 釣り竿 2本 (船尾から斜め上)
	_cyl(self, 0.016, 1.7, Vector3(-0.55, 1.75, -2.80), Color(0.08, 0.08, 0.09), Vector3(16, 0, 6))
	_cyl(self, 0.016, 1.9, Vector3(-0.33, 1.85, -2.80), Color(0.08, 0.08, 0.09), Vector3(19, 0, 3))
	# 手すり (船首)
	_cyl(self, 0.03, 1.5, Vector3(0, 1.62, 3.55), Color(0.75, 0.78, 0.8), Vector3(0, 0, 90))
	_cyl(self, 0.025, 0.35, Vector3(-0.72, 1.45, 3.55), Color(0.75, 0.78, 0.8))
	_cyl(self, 0.025, 0.35, Vector3(0.72, 1.45, 3.55), Color(0.75, 0.78, 0.8))
	# 船内の溜まり水 (浸水で上昇する透明な水面) — 子供なので船と一緒に傾く
	_interior_water = _box(self, Vector3(1.88, 0.06, 5.55), Vector3(0, 0.47, 0.05), Color(0.15, 0.75, 0.82, 0.78))
	var wm := _interior_water.material_override as StandardMaterial3D
	wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wm.roughness = 0.15
	_interior_water.visible = false

func _build_character() -> void:
	# 写真の男性: 船尾に立ち船首を向く。上半身裸・赤い水着・金髪寄りの短髪。
	var man := Node3D.new()
	man.name = "Man"
	man.position = Vector3(-0.42, 0.46, -1.88)
	man.rotation_degrees = Vector3(0, 4, 0)
	man.scale = Vector3.ONE * 1.12
	add_child(man)
	var skin := Color(0.76, 0.50, 0.35)
	var skin2 := Color(0.70, 0.45, 0.31)
	# 脚 (膝下は浸水で水の中に入る)
	_cyl(man, 0.075, 0.62, Vector3(-0.13, 0.31, 0), skin2)
	_cyl(man, 0.075, 0.62, Vector3(0.14, 0.31, 0.02), skin2)
	# 赤い水着 (横縞つき)
	_box(man, Vector3(0.44, 0.36, 0.30), Vector3(0, 0.78, 0), Color(0.78, 0.16, 0.20))
	_box(man, Vector3(0.45, 0.05, 0.31), Vector3(0, 0.86, 0), Color(0.92, 0.88, 0.85))
	_box(man, Vector3(0.45, 0.04, 0.31), Vector3(0, 0.70, 0), Color(0.92, 0.88, 0.85))
	# 上半身 (裸の背中がカメラ側 = -Z)
	var torso := _cyl(man, 0.20, 0.62, Vector3(0, 1.27, 0), skin)
	torso.scale = Vector3(1.18, 1.0, 0.75)
	_sphere(man, 0.19, Vector3(0, 1.585, 0), skin, Vector3(1.2, 0.38, 0.78)) # 肩
	# 腕 (体の横に下ろす・少し太く)
	_cyl(man, 0.068, 0.62, Vector3(-0.315, 1.20, 0.0), skin2, Vector3(0, 0, 6))
	_cyl(man, 0.068, 0.62, Vector3(0.325, 1.20, 0.03), skin2, Vector3(-5, 0, -8))
	_sphere(man, 0.07, Vector3(-0.345, 0.88, 0.02), skin2) # 手
	_sphere(man, 0.07, Vector3(0.365, 0.88, 0.06), skin2)
	# 首・頭 + 髪 (金髪寄り)
	_cyl(man, 0.06, 0.12, Vector3(0, 1.66, 0.01), skin2)
	_sphere(man, 0.145, Vector3(0, 1.83, 0.01), skin)
	_sphere(man, 0.15, Vector3(0, 1.885, -0.02), Color(0.62, 0.48, 0.26), Vector3(1.0, 0.60, 1.0))

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
