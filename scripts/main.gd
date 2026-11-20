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
var _water_mat: ShaderMaterial
var _foam_collar: MeshInstance3D
var _foam_patches: Array[MeshInstance3D] = []
var _foam_patch_bases: Array[Vector3] = []
var _distant_boat: MeshInstance3D

func _ready() -> void:
	_build_environment()
	_build_water()
	_build_world_dressing()
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
	# v2: ACES tonemap + modest glow + light fog (GL Compatibility ceiling:
	# glow/fog are best-effort in this renderer, tonemap + shadows do apply)
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	env.glow_intensity = 0.20
	env.glow_strength = 0.5
	env.glow_bloom = 0.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.65, 0.85, 0.92)
	env.fog_light_energy = 0.6
	env.fog_density = 0.008
	env.fog_sky_affect = 0.35
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.03
	env.adjustment_saturation = 1.06
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -35, 0)
	sun.light_energy = 1.05
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 80.0
	sun.shadow_opacity = 0.55
	add_child(sun)

func _ring_texture() -> ImageTexture:
	# Soft foam ring: alpha band with angular irregularity.
	var img := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	for y in 256:
		for x in 256:
			var uv := Vector2((float(x) / 255.0 - 0.5) * 2.0, (float(y) / 255.0 - 0.5) * 2.0)
			var d := uv.length()
			var ang := atan2(uv.y, uv.x)
			var wob := 0.05 * sin(ang * 7.0) + 0.03 * sin(ang * 13.0 + 1.7)
			var band := smoothstep(0.50 + wob, 0.64 + wob, d) * (1.0 - smoothstep(0.78 + wob, 0.96, d))
			img.set_pixel(x, y, Color(1, 1, 1, band * 0.85))
	return ImageTexture.create_from_image(img)

func _blob_texture() -> ImageTexture:
	# Soft round foam blob: radial falloff.
	var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	for y in 128:
		for x in 128:
			var uv := Vector2((float(x) / 127.0 - 0.5) * 2.0, (float(y) / 127.0 - 0.5) * 2.0)
			var d := uv.length()
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a * 0.55))
	return ImageTexture.create_from_image(img)

func _cloud_texture() -> ImageTexture:
	# Elongated multi-blob cloud sprite.
	var img := Image.create(256, 128, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var blobs: Array[Vector3] = []
	for i in 16:
		blobs.append(Vector3(rng.randf_range(-0.55, 0.55), rng.randf_range(-0.16, 0.16), rng.randf_range(0.22, 0.45)))
	for y in 128:
		for x in 256:
			var p := Vector2((float(x) / 255.0 - 0.5) * 2.0, (float(y) / 127.0 - 0.5) * 2.0)
			var best := 0.0
			for b in blobs:
				var q := Vector2((p.x - b.x) / b.z, (p.y - b.y) / (b.z * 0.45))
				best = maxf(best, clampf(1.0 - q.length(), 0.0, 1.0))
			var a := best * best * 0.5
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)

func _flat_quad(tex: Texture2D, size: Vector2, alpha: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := PlaneMesh.new()
	q.size = size
	mi.mesh = q
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.albedo_color = Color(1, 1, 1, alpha)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.render_priority = 1
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

func _build_water() -> void:
	# v2: custom wave shader sea. Near field displaced mesh + far flat sheet
	# with the same shader (fragment normals still animate at distance).
	var shader := load("res://shaders/water.gdshader") as Shader
	_water_mat = ShaderMaterial.new()
	_water_mat.shader = shader
	var near_sea := MeshInstance3D.new()
	var np := PlaneMesh.new()
	np.size = Vector2(170, 170)
	np.subdivide_width = 128
	np.subdivide_depth = 128
	near_sea.mesh = np
	near_sea.material_override = _water_mat
	near_sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(near_sea)
	var far_sea := MeshInstance3D.new()
	var fp := PlaneMesh.new()
	fp.size = Vector2(800, 800)
	fp.subdivide_width = 4
	fp.subdivide_depth = 4
	far_sea.mesh = fp
	far_sea.material_override = _water_mat
	far_sea.position.y = -0.07
	far_sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(far_sea)
	# Foam collar hugging the hull at water level (follows the boat in _process)
	_foam_collar = _flat_quad(_ring_texture(), Vector2(4.6, 8.6), 0.85)
	(_foam_collar.material_override as StandardMaterial3D).render_priority = 2
	add_child(_foam_collar)
	# Drifting foam patches
	var blob := _blob_texture()
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for i in 7:
		var patch := _flat_quad(blob, Vector2(rng.randf_range(2.0, 5.0), rng.randf_range(1.2, 3.0)), 0.5)
		var base := Vector3(rng.randf_range(-32, 32), 0, rng.randf_range(-32, 32))
		if base.length() < 7.0:
			base += Vector3(9, 0, 9)
		patch.position = base
		patch.rotation.y = rng.randf_range(0, TAU)
		_foam_patches.append(patch)
		_foam_patch_bases.append(base)
		add_child(patch)

func _build_world_dressing() -> void:
	# Distant low island silhouettes (flattened spheres, fog does the rest)
	var isl_mat := StandardMaterial3D.new()
	isl_mat.albedo_color = Color(0.10, 0.23, 0.25)
	isl_mat.roughness = 1.0
	var islands := [
		[Vector3(-40, -0.6, 68), Vector3(21, 3.4, 8)],
		[Vector3(-27, -0.5, 74), Vector3(11, 2.3, 6)],
		[Vector3(38, -0.7, 88), Vector3(27, 4.2, 10)],
		[Vector3(60, -0.4, 42), Vector3(9, 1.7, 5)],
	]
	for isl in islands:
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 1.0
		sm.height = 2.0
		sm.radial_segments = 24
		sm.rings = 12
		mi.mesh = sm
		mi.material_override = isl_mat
		mi.position = isl[0]
		mi.scale = isl[1]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	# One distant boat (same OBJ, imported MTL materials are fine at range)
	var mesh := load("res://assets/boat.obj") as Mesh
	if mesh:
		_distant_boat = MeshInstance3D.new()
		_distant_boat.mesh = mesh
		_distant_boat.scale = Vector3.ONE * 0.5
		_distant_boat.position = Vector3(26, 0, 54)
		_distant_boat.rotation_degrees = Vector3(0, -35, 0)
		_distant_boat.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_distant_boat)
	# Soft billboard clouds
	var ctex := _cloud_texture()
	var cloud_pos := [
		Vector3(-32, 21, 85), Vector3(24, 25, 100), Vector3(2, 27, -75),
		Vector3(-62, 23, 30), Vector3(56, 20, -45), Vector3(12, 30, 130),
	]
	for cp in cloud_pos:
		var sp := Sprite3D.new()
		sp.texture = ctex
		sp.pixel_size = 0.16
		sp.modulate = Color(1, 1, 1, 0.55)
		sp.shaded = false
		sp.position = cp
		add_child(sp)

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
	# --- v2 water/world sync: shader clock = boat physics clock (exact match)
	if _water_mat and boat:
		_water_mat.set_shader_parameter("wave_time", boat.time_s)
	if _foam_collar and boat:
		var bp := boat.global_position
		_foam_collar.global_position = Vector3(bp.x, BoatBody.water_height_at(bp.x, bp.z, boat.time_s) + 0.05, bp.z)
		var fwd := boat.global_transform.basis.z
		_foam_collar.rotation.y = atan2(fwd.x, fwd.z)
		var pulse := 1.0 + 0.025 * sin(boat.time_s * 2.1)
		_foam_collar.scale = Vector3.ONE * pulse
		_foam_collar.visible = bp.y > -2.4
	if boat:
		for i in _foam_patches.size():
			var patch := _foam_patches[i]
			var base := _foam_patch_bases[i]
			var px := base.x + sin(boat.time_s * 0.05 + float(i) * 1.7) * 1.6
			var pz := base.z + cos(boat.time_s * 0.04 + float(i) * 1.3) * 1.6
			patch.position = Vector3(px, BoatBody.water_height_at(px, pz, boat.time_s) + 0.04, pz)
		if _distant_boat:
			var dp := _distant_boat.position
			_distant_boat.position.y = BoatBody.water_height_at(dp.x, dp.z, boat.time_s) - 0.04
			_distant_boat.rotation.z = 0.03 * sin(boat.time_s * 0.7)
			_distant_boat.rotation.x = 0.02 * sin(boat.time_s * 0.5 + 1.0)
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
