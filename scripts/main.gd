extends Node3D
## メイン: 海・空・カメラ・射撃・HUD。
## 操作: クリック/タップ=撃つ / 右ドラッグ or ドラッグ(移動量大)=回転 / ホイール=ズーム / R=リセット

var boat: BoatBody
var camera: Camera3D
var cam_yaw: float = -3.02       # 船尾の真後ろ・やや左舷寄り・上方から (写真の構図: 船尾と人が手前, 船首が右奥)
var cam_pitch: float = 0.92
var cam_dist: float = 9.6
var _dragging := false
var _drag_moved := 0.0
var _press_pos := Vector2.ZERO
var _orbiting := false

var hud_holes: Label
var hud_flood: Label
var hud_status: Label
var hud_bar: ProgressBar
var _tracer: MeshInstance3D
var _tracer_timer := 0.0
var _splash: MeshInstance3D
var _splash_timer := 0.0

func _ready() -> void:
	_build_environment()
	_build_water()
	boat = BoatBody.new()
	boat.name = "Boat"
	add_child(boat)
	boat.reset_boat()
	camera = Camera3D.new()
	camera.fov = 55.0
	add_child(camera)
	_build_fx()
	_build_hud()
	_update_camera(0.0)

func _build_environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = Color(0.25, 0.55, 0.85)
	psm.sky_horizon_color = Color(0.65, 0.88, 0.95)
	psm.ground_bottom_color = Color(0.05, 0.35, 0.45)
	psm.ground_horizon_color = Color(0.65, 0.88, 0.95)
	psm.sun_angle_max = 30.0
	sky.sky_material = psm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.68, 0.72)
	env.ambient_light_energy = 0.55
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -35, 0)
	sun.light_energy = 1.05
	sun.shadow_enabled = true
	add_child(sun)

func _build_water() -> void:
	var water := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(400, 400)
	plane.subdivide_width = 48
	plane.subdivide_depth = 48
	water.mesh = plane
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.03, 0.50, 0.60)
	m.roughness = 0.5
	m.metallic = 0.0
	water.material_override = m
	add_child(water)
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	# きらめき: 白い小片を水面に散らす (写真の光の反射っぽく)
	for i in 130:
		var s := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(rng.randf_range(0.2, 0.45), 0.05)
		s.mesh = q
		var mm := StandardMaterial3D.new()
		mm.albedo_color = Color(1, 1, 1, rng.randf_range(0.15, 0.35))
		mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		s.material_override = mm
		s.position = Vector3(rng.randf_range(-45, 45), 0.035, rng.randf_range(-45, 45))
		s.rotation_degrees = Vector3(-90, 0, rng.randf_range(0, 180))
		add_child(s)

func _build_fx() -> void:
	_tracer = MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(0.02, 0.02, 1.0)
	_tracer.mesh = tm
	var mm := StandardMaterial3D.new()
	mm.albedo_color = Color(1.0, 0.95, 0.6)
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tracer.material_override = mm
	_tracer.visible = false
	add_child(_tracer)
	_splash = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.22
	sm.height = 0.44
	_splash.mesh = sm
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.95, 1.0, 1.0, 0.8)
	wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_splash.material_override = wm
	_splash.visible = false
	add_child(_splash)

func _build_hud() -> void:
	var font := load("res://jpfont.ttf") as FontFile
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(14, 12)
	layer.add_child(panel)
	var vb := VBoxContainer.new()
	panel.add_child(vb)
	var title := Label.new()
	title.text = "撃つと浸水して沈む船 — Godot再現"
	title.add_theme_font_size_override("font_size", 20)
	if font: title.add_theme_font_override("font", font)
	vb.add_child(title)
	hud_holes = _hud_label(vb, font, "穴: 0")
	hud_flood = _hud_label(vb, font, "浸水: 0%")
	hud_bar = ProgressBar.new()
	hud_bar.min_value = 0
	hud_bar.max_value = 100
	hud_bar.value = 0
	hud_bar.custom_minimum_size = Vector2(280, 16)
	vb.add_child(hud_bar)
	hud_status = _hud_label(vb, font, "状態: 浮いている")
	var help := _hud_label(vb, font, "クリック/タップ: 撃つ (船底・水面下が効く)\nドラッグ: 回転 / ホイール: ズーム / R: リセット")
	help.add_theme_font_size_override("font_size", 13)
	# ボタン (下部)
	var hb := HBoxContainer.new()
	hb.position = Vector2(14, 640)
	layer.add_child(hb)
	var b1 := Button.new()
	b1.text = "船底を撃つ"
	if font: b1.add_theme_font_override("font", font)
	b1.pressed.connect(_on_auto_shoot_bottom)
	hb.add_child(b1)
	var b2 := Button.new()
	b2.text = "右舷を撃つ"
	if font: b2.add_theme_font_override("font", font)
	b2.pressed.connect(_on_auto_shoot_side)
	hb.add_child(b2)
	var b3 := Button.new()
	b3.text = "リセット (R)"
	if font: b3.add_theme_font_override("font", font)
	b3.pressed.connect(func() -> void: boat.reset_boat())
	hb.add_child(b3)
	# 照準 (マウス位置の + )
	var cross := Label.new()
	cross.name = "Crosshair"
	cross.text = "+"
	cross.add_theme_font_size_override("font_size", 22)
	layer.add_child(cross)

func _hud_label(parent: Node, font: Font, txt: String) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", 16)
	if font: l.add_theme_font_override("font", font)
	parent.add_child(l)
	return l

# ---------------------------------------------------------------- 入力・射撃
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			cam_dist = clampf(cam_dist - 0.8, 5.0, 22.0)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			cam_dist = clampf(cam_dist + 0.8, 5.0, 22.0)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_dragging = true
				_drag_moved = 0.0
				_press_pos = mb.position
			else:
				if _dragging and _drag_moved < 8.0:
					shoot_at_screen(mb.position)
				_dragging = false
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			_orbiting = mb.pressed
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _dragging or _orbiting:
			_drag_moved += mm.relative.length()
			if _drag_moved >= 8.0 or _orbiting:
				cam_yaw -= mm.relative.x * 0.005
				cam_pitch = clampf(cam_pitch + mm.relative.y * 0.004, 0.12, 1.25)
	elif event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and k.keycode == KEY_R:
			boat.reset_boat()

func shoot_at_screen(screen_pos: Vector2) -> bool:
	var from := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * 120.0, 2)
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		return false
	var pos: Vector3 = result["position"]
	var normal: Vector3 = result["normal"]
	boat.register_hit(pos, normal)
	_show_shot_fx(from, pos)
	return true

func shoot_local(local_pos: Vector3, local_normal: Vector3) -> void:
	# テスト/自動ボタン用: ローカル座標で直接穴を開ける
	var wp := boat.to_global(local_pos)
	var wn := (boat.global_transform.basis * local_normal).normalized()
	boat.register_hit(wp, wn)
	_show_shot_fx(camera.global_position, wp)

func _on_auto_shoot_bottom() -> void:
	shoot_local(Vector3(0.45, 0.18, -0.6), Vector3.DOWN)

func _on_auto_shoot_side() -> void:
	shoot_local(Vector3(1.10, 0.55, 0.4), Vector3.RIGHT)

func _show_shot_fx(from: Vector3, to: Vector3) -> void:
	var mid := (from + to) * 0.5
	_tracer.global_position = mid
	_tracer.look_at_from_position(mid, to, Vector3.UP)
	_tracer.scale = Vector3(1, 1, from.distance_to(to))
	_tracer.visible = true
	_tracer_timer = 0.07
	_splash.global_position = to
	_splash.scale = Vector3.ONE
	_splash.visible = true
	_splash_timer = 0.28

# ---------------------------------------------------------------- 毎フレーム
func _process(delta: float) -> void:
	_update_camera(delta)
	if _tracer_timer > 0.0:
		_tracer_timer -= delta
		if _tracer_timer <= 0.0: _tracer.visible = false
	if _splash_timer > 0.0:
		_splash_timer -= delta
		_splash.scale = Vector3.ONE * (1.0 + (0.28 - _splash_timer) * 5.0)
		if _splash_timer <= 0.0: _splash.visible = false
	hud_holes.text = "穴: %d" % boat.holes.size()
	hud_flood.text = "浸水: %d%%" % int(boat.flood_ratio * 100.0)
	hud_bar.value = boat.flood_ratio * 100.0
	hud_status.text = "状態: " + boat.status_text()
	var cross := get_node_or_null("CanvasLayer/Crosshair") as Label
	# CanvasLayerは名前未指定で追加したので子を走査
	for c in get_children():
		if c is CanvasLayer:
			var cr := c.get_node_or_null("Crosshair") as Label
			if cr:
				var mp := get_viewport().get_mouse_position()
				cr.position = mp - Vector2(7, 13)

func _update_camera(_delta: float) -> void:
	if not boat or not camera:
		return
	var target := Vector3(boat.global_position.x, clampf(boat.global_position.y + 0.9, 0.35, 3.0), boat.global_position.z)
	var off := Vector3(sin(cam_yaw) * cos(cam_pitch), sin(cam_pitch), cos(cam_yaw) * cos(cam_pitch)) * cam_dist
	camera.global_position = target + off
	camera.look_at(target, Vector3.UP)
