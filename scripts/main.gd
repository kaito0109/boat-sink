extends Node3D
## メイン: 海・空・カメラ・射撃・HUD。
## 操作: クリック/タップ=撃つ / 右ドラッグ or ドラッグ(移動量大)=回転 / ホイール=ズーム / R=リロード
## v3: 拳銃ビューモデル (反動・発砲炎・薬莢・合成銃声) + 12発マガジン + 水面着弾エフェクト

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
var hud_ammo: Label
var hud_bar: ProgressBar
var hud_cross: TextureRect

# --- v3 gun system ---
const MAG_SIZE := 12
const FIRE_INTERVAL := 0.16
const RELOAD_TIME := 1.15
var ammo := MAG_SIZE
var last_hit_boat := false
var _gun_pivot: Node3D
var _muzzle: Marker3D
var _flash: MeshInstance3D
var _flash_light: OmniLight3D
var _flash_timer := 0.0
var _kick := 0.0
var _shake := 0.0
var _gun_time := 0.0
var _cooldown := 0.0
var _reload_t := 0.0
var _gun_base_pos := Vector3(0.25, -0.225, -0.55)
var _audio_shot: AudioStreamPlayer
var _audio_splash: AudioStreamPlayer
var _audio_ui: AudioStreamPlayer
var _dry_stream: AudioStreamWAV
var _reload_stream: AudioStreamWAV
var _shells: Array = []
var _puff: MeshInstance3D
var _puff_timer := 0.0
var _ripples: Array = []
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
	_build_gun()
	_build_audio()
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

# ---------------------------------------------------------------- v3 銃まわり
func _pistol_mat(c: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m

func _flash_texture() -> ImageTexture:
	# 4-point muzzle flash star with a bright core.
	var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	for y in 128:
		for x in 128:
			var uv := Vector2((float(x) / 127.0 - 0.5) * 2.0, (float(y) / 127.0 - 0.5) * 2.0)
			var d := uv.length()
			var ang := atan2(uv.y, uv.x)
			var spikes := pow(absf(cos(ang * 2.0)), 6.0)
			var a := clampf((1.0 - d) * (0.30 + 0.85 * spikes) * 1.7, 0.0, 1.0)
			if d < 0.16:
				a = 1.0
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)

func _reticle_texture() -> ImageTexture:
	# Ring + centre dot + 4 ticks.
	var img := Image.create(96, 96, false, Image.FORMAT_RGBA8)
	for y in 96:
		for x in 96:
			var uv := Vector2((float(x) / 95.0 - 0.5) * 2.0, (float(y) / 95.0 - 0.5) * 2.0)
			var d := uv.length()
			var a := 0.0
			if d > 0.34 and d < 0.44:
				a = 0.95
			if d < 0.07:
				a = 0.95
			if absf(uv.x) < 0.045 and d >= 0.56 and d <= 0.82:
				a = 0.95
			if absf(uv.y) < 0.045 and d >= 0.56 and d <= 0.82:
				a = 0.95
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)

func _build_gun() -> void:
	_gun_pivot = Node3D.new()
	_gun_pivot.position = _gun_base_pos
	camera.add_child(_gun_pivot)
	var mi := MeshInstance3D.new()
	var mesh: Mesh = load("res://assets/pistol.obj")
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_gun_pivot.add_child(mi)
	var mats := {
		"SteelDark": _pistol_mat(Color(0.23, 0.25, 0.28), 0.38, 0.85),
		"SteelLight": _pistol_mat(Color(0.42, 0.44, 0.47), 0.30, 0.90),
		"Polymer": _pistol_mat(Color(0.075, 0.075, 0.082), 0.62, 0.10),
		"GripPanel": _pistol_mat(Color(0.08, 0.08, 0.085), 0.88, 0.0),
		"BlackHole": _pistol_mat(Color(0.008, 0.008, 0.01), 0.90, 0.0),
		"Brass": _pistol_mat(Color(0.42, 0.30, 0.12), 0.38, 0.90),
	}
	var dot := _pistol_mat(Color(0.95, 0.35, 0.05), 0.5, 0.0)
	dot.emission_enabled = true
	dot.emission = Color(0.95, 0.35, 0.05)
	dot.emission_energy_multiplier = 1.6
	mats["OrangeDot"] = dot
	if mesh is ArrayMesh:
		var am := mesh as ArrayMesh
		for i in am.get_surface_count():
			var sname := am.surface_get_name(i)
			for k in mats.keys():
				if sname.contains(k):
					mi.set_surface_override_material(i, mats[k])
					break
	_muzzle = Marker3D.new()
	_muzzle.position = Vector3(0, 0.047, -0.13)
	_gun_pivot.add_child(_muzzle)
	_flash = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.17, 0.17)
	_flash.mesh = q
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.albedo_texture = _flash_texture()
	fm.albedo_color = Color(1.0, 0.85, 0.55)
	_flash.material_override = fm
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flash.position = Vector3(0, 0.047, -0.175)
	_flash.visible = false
	_gun_pivot.add_child(_flash)
	_flash_light = OmniLight3D.new()
	_flash_light.light_color = Color(1.0, 0.75, 0.4)
	_flash_light.light_energy = 0.0
	_flash_light.omni_range = 5.0
	_flash_light.position = Vector3(0, 0.05, -0.2)
	_gun_pivot.add_child(_flash_light)
	# --- shell casings (pool, world space) ---
	var brass := _pistol_mat(Color(0.55, 0.40, 0.16), 0.32, 0.90)
	for i in 8:
		var s := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.009, 0.009, 0.022)
		s.mesh = bm
		s.material_override = brass
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		s.visible = false
		add_child(s)
		_shells.append({"mi": s, "vel": Vector3.ZERO, "rot": Vector3.ZERO, "t": 0.0})
	# --- impact puff on the boat ---
	_puff = MeshInstance3D.new()
	var pq := QuadMesh.new()
	pq.size = Vector2(0.3, 0.3)
	_puff.mesh = pq
	var pm := StandardMaterial3D.new()
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.albedo_texture = _blob_texture()
	pm.albedo_color = Color(0.20, 0.20, 0.20, 0.0)
	pm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_puff.material_override = pm
	_puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_puff.visible = false
	add_child(_puff)
	# --- water ripples (pool) ---
	for i in 4:
		var r := MeshInstance3D.new()
		var pl := PlaneMesh.new()
		pl.size = Vector2(1, 1)
		r.mesh = pl
		var rm := StandardMaterial3D.new()
		rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		rm.albedo_texture = _ring_texture()
		rm.albedo_color = Color(1, 1, 1, 0)
		r.material_override = rm
		r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		r.visible = false
		add_child(r)
		_ripples.append({"mi": r, "mat": rm, "t": -1.0})

# ---------------------------------------------------------------- v3 合成サウンド
func _wav(samples: PackedByteArray, rate: int) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = samples
	return w

func _encode(dur: float, rate: int, fn: Callable) -> AudioStreamWAV:
	var n := int(rate * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var v: float = clampf(fn.call(float(i) / float(rate)), -1.0, 1.0)
		data.encode_s16(i * 2, int(v * 32767.0))
	return _wav(data, rate)

func _build_audio() -> void:
	var rate := 22050
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var phase := [0.0]
	var shot := _encode(0.30, rate, func(t: float) -> float:
		var freq := lerpf(140.0, 42.0, clampf(t / 0.12, 0.0, 1.0))
		phase[0] += TAU * freq / 22050.0
		var v := rng.randf_range(-1.0, 1.0) * exp(-t * 30.0) * 0.85 + sin(phase[0]) * exp(-t * 11.0) * 0.55
		if t < 0.004:
			v += (1.0 - t / 0.004) * 0.30
		return v * 0.8)
	var sm := [0.0]
	var splash := _encode(0.38, rate, func(t: float) -> float:
		sm[0] = sm[0] * 0.70 + rng.randf_range(-1.0, 1.0) * 0.30
		var env := pow(sin(PI * clampf(t / 0.38, 0.0, 1.0)), 1.5)
		return sm[0] * env * 1.5)
	_dry_stream = _encode(0.07, rate, func(t: float) -> float:
		return rng.randf_range(-1.0, 1.0) * exp(-t * 80.0) * 0.6)
	_reload_stream = _encode(1.05, rate, func(t: float) -> float:
		var v := 0.0
		for t0 in [0.06, 0.52]:
			if t >= t0 and t < t0 + 0.05:
				v += rng.randf_range(-1.0, 1.0) * exp(-(t - t0) * 70.0) * 0.7
		if t >= 0.78 and t < 0.94:
			var lt := t - 0.78
			v += rng.randf_range(-1.0, 1.0) * 0.35 * sin(PI * lt / 0.16) + sin(TAU * 2400.0 * t) * exp(-lt * 18.0) * 0.12
		return v)
	_audio_shot = AudioStreamPlayer.new()
	_audio_shot.stream = shot
	_audio_shot.volume_db = -5.0
	add_child(_audio_shot)
	_audio_splash = AudioStreamPlayer.new()
	_audio_splash.stream = splash
	_audio_splash.volume_db = -9.0
	add_child(_audio_splash)
	_audio_ui = AudioStreamPlayer.new()
	_audio_ui.volume_db = -6.0
	add_child(_audio_ui)

func _build_hud() -> void:
	var font := load("res://jpfont.ttf") as FontFile
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(14, 12)
	# HUDは表示専用: タップを一切奪わない (v2.1 — 照準ラベル等が
	# 指の下に来て _unhandled_input に届かない事故の修正)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(panel)
	var vb := VBoxContainer.new()
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(vb)
	var title := Label.new()
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.text = "撃つと浸水して沈む船 — Godot再現"
	title.add_theme_font_size_override("font_size", 20)
	if font: title.add_theme_font_override("font", font)
	vb.add_child(title)
	hud_holes = _hud_label(vb, font, "穴: 0")
	hud_flood = _hud_label(vb, font, "浸水: 0%")
	hud_bar = ProgressBar.new()
	hud_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_bar.min_value = 0
	hud_bar.max_value = 100
	hud_bar.value = 0
	hud_bar.custom_minimum_size = Vector2(280, 16)
	vb.add_child(hud_bar)
	hud_status = _hud_label(vb, font, "状態: 浮いている")
	hud_ammo = _hud_label(vb, font, "弾: 12 / 12")
	var help := _hud_label(vb, font, "クリック/タップ: 撃つ (船底・水面下が効く)\nドラッグ: 回転 / ホイール: ズーム / R: リロード")
	help.add_theme_font_size_override("font_size", 13)
	# ボタン (下部)
	var hb := HBoxContainer.new()
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	b3.text = "リセット"
	if font: b3.add_theme_font_override("font", font)
	b3.pressed.connect(func() -> void: boat.reset_boat())
	hb.add_child(b3)
	# 照準 (リング型レティクル, マウス/タップ位置に追従)
	hud_cross = TextureRect.new()
	hud_cross.name = "Crosshair"
	hud_cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_cross.texture = _reticle_texture()
	hud_cross.custom_minimum_size = Vector2(44, 44)
	hud_cross.size = Vector2(44, 44)
	hud_cross.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	layer.add_child(hud_cross)

func _hud_label(parent: Node, font: Font, txt: String) -> Label:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
				# タップ判定は「押した場所からの距離」で決める (指の微振動で
				# 累積移動量が膨らみ、タップが回転扱いになる事故を防ぐ)
				if _dragging and mb.position.distance_to(_press_pos) < 20.0:
					shoot_at_screen(mb.position)
				_dragging = false
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			_orbiting = mb.pressed
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _dragging or _orbiting:
			_drag_moved += mm.relative.length()
			if _drag_moved >= 20.0 or _orbiting:
				cam_yaw -= mm.relative.x * 0.005
				cam_pitch = clampf(cam_pitch + mm.relative.y * 0.004, 0.12, 1.25)
	elif event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and k.keycode == KEY_R:
			_start_reload()

func _raycast_boat(from: Vector3, dir: Vector3) -> Dictionary:
	# 第1優先: 見た目メッシュの当たり判定 (layer 4 の Area3D)
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * 120.0, 4)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		# フォールバック: 従来の箱コリジョン (layer 2)
		var q2 := PhysicsRayQueryParameters3D.create(from, from + dir * 120.0, 2)
		result = get_world_3d().direct_space_state.intersect_ray(q2)
	return result

func _ray_water_point(from: Vector3, dir: Vector3) -> Vector3:
	# レイが波の表面と交わる点を探す (浮力と同じ波関数で判定)
	var prev := from
	for i in range(1, 121):
		var p := from + dir * float(i)
		if p.y <= BoatBody.water_height_at(p.x, p.z, boat.time_s):
			var a := prev
			var b := p
			for j in 8:
				var m := (a + b) * 0.5
				if m.y <= BoatBody.water_height_at(m.x, m.z, boat.time_s):
					b = m
				else:
					a = m
			return (a + b) * 0.5
		prev = p
	return Vector3.INF

func _start_reload() -> void:
	if _reload_t > 0.0 or ammo == MAG_SIZE:
		return
	_reload_t = RELOAD_TIME
	_audio_ui.stream = _reload_stream
	_audio_ui.play()

func _fire_gun_fx() -> void:
	_kick = 1.0
	_shake = 1.0
	_flash.visible = true
	_flash.rotation.z = randf() * TAU
	var fs := randf_range(0.85, 1.25)
	_flash.scale = Vector3(fs, fs, 1.0)
	_flash_timer = 0.045
	_flash_light.light_energy = 2.4
	_audio_shot.pitch_scale = randf_range(0.94, 1.06)
	_audio_shot.play()
	# 薬莢を右上へ排出
	for sh in _shells:
		if float(sh["t"]) <= 0.0:
			var mi := sh["mi"] as MeshInstance3D
			mi.global_position = _gun_pivot.global_transform * Vector3(0.03, 0.055, 0.01)
			var cb := camera.global_transform.basis
			sh["vel"] = cb * Vector3(randf_range(0.5, 0.8), randf_range(0.9, 1.25), randf_range(0.10, 0.35))
			sh["rot"] = Vector3(randf_range(-9.0, 9.0), randf_range(-9.0, 9.0), randf_range(-9.0, 9.0))
			sh["t"] = 0.9
			mi.visible = true
			break

func _show_puff(p: Vector3) -> void:
	_puff.global_position = p
	_puff.scale = Vector3.ONE * 0.8
	_puff.visible = true
	_puff_timer = 0.30

func _show_water_hit(p: Vector3) -> void:
	_splash.global_position = p + Vector3(0, 0.12, 0)
	_splash.scale = Vector3.ONE
	_splash.visible = true
	_splash_timer = 0.28
	_audio_splash.pitch_scale = randf_range(0.92, 1.08)
	_audio_splash.play()
	for r in _ripples:
		if float(r["t"]) < 0.0:
			var mi := r["mi"] as MeshInstance3D
			mi.global_position = Vector3(p.x, BoatBody.water_height_at(p.x, p.z, boat.time_s) + 0.03, p.z)
			mi.visible = true
			r["t"] = 0.0
			break

func shoot_at_screen(screen_pos: Vector2) -> bool:
	# 戻り値: 実際に発砲したか (クールダウン/リロード中/空撃ちは false)
	if _cooldown > 0.0 or _reload_t > 0.0:
		return false
	if ammo <= 0:
		_audio_ui.stream = _dry_stream
		_audio_ui.play()
		_start_reload()
		return false
	ammo -= 1
	_cooldown = FIRE_INTERVAL
	var from := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	var muzzle := _muzzle.global_position
	var result := _raycast_boat(from, dir)
	if not result.is_empty():
		var pos: Vector3 = result["position"]
		var normal: Vector3 = result["normal"]
		boat.register_hit(pos, normal)
		_show_shot_fx(muzzle, pos)
		_show_puff(pos)
		last_hit_boat = true
	else:
		var wp := _ray_water_point(from, dir)
		if wp != Vector3.INF:
			_show_shot_fx(muzzle, wp)
			_show_water_hit(wp)
		last_hit_boat = false
	_fire_gun_fx()
	if ammo == 0:
		_start_reload()
	return true

func shoot_local(local_pos: Vector3, local_normal: Vector3) -> void:
	# テスト/自動ボタン用: ローカル座標で直接穴を開ける (弾数・演出は通常射撃と同じ)
	if _cooldown > 0.0 or _reload_t > 0.0:
		return
	if ammo <= 0:
		_audio_ui.stream = _dry_stream
		_audio_ui.play()
		_start_reload()
		return
	ammo -= 1
	_cooldown = FIRE_INTERVAL
	var wp := boat.to_global(local_pos)
	var wn := (boat.global_transform.basis * local_normal).normalized()
	boat.register_hit(wp, wn)
	_show_shot_fx(_muzzle.global_position, wp)
	_show_puff(wp)
	last_hit_boat = true
	_fire_gun_fx()
	if ammo == 0:
		_start_reload()

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
	# --- v3 gun timers / animation ---
	_gun_time += delta
	_cooldown = maxf(0.0, _cooldown - delta)
	if _reload_t > 0.0:
		_reload_t -= delta
		if _reload_t <= 0.0:
			ammo = MAG_SIZE
	_kick = maxf(0.0, _kick - delta * 5.5)
	_shake = maxf(0.0, _shake - delta * 4.0)
	if _gun_pivot:
		var sway := Vector3(sin(_gun_time * 1.4) * 0.0016, sin(_gun_time * 1.9 + 0.7) * 0.0014, 0)
		var dip := 0.0
		var dip_rot := 0.0
		if _reload_t > 0.0:
			var pr := 1.0 - _reload_t / RELOAD_TIME
			dip = sin(pr * PI) * 0.085
			dip_rot = sin(pr * PI) * 0.5
		_gun_pivot.position = _gun_base_pos + sway + Vector3(0, _kick * 0.014 - dip, _kick * 0.055)
		_gun_pivot.rotation = Vector3(_kick * 0.13 - dip_rot, sin(_gun_time * 0.9) * 0.004, 0)
	if _flash_timer > 0.0:
		_flash_timer -= delta
		if _flash_timer <= 0.0:
			_flash.visible = false
			_flash_light.light_energy = 0.0
	for sh in _shells:
		var t := float(sh["t"])
		if t > 0.0:
			t -= delta
			sh["t"] = t
			var mi := sh["mi"] as MeshInstance3D
			var vel: Vector3 = sh["vel"]
			vel.y -= 6.5 * delta
			sh["vel"] = vel
			mi.global_position += vel * delta
			var rot: Vector3 = sh["rot"]
			mi.rotation += rot * delta
			if t <= 0.0:
				mi.visible = false
	if _puff_timer > 0.0:
		_puff_timer -= delta
		var k := 1.0 - clampf(_puff_timer / 0.30, 0.0, 1.0)
		_puff.scale = Vector3.ONE * (0.8 + k * 1.8)
		var pm := _puff.material_override as StandardMaterial3D
		pm.albedo_color.a = (1.0 - k) * 0.5
		if _puff_timer <= 0.0:
			_puff.visible = false
	for r in _ripples:
		var rt := float(r["t"])
		if rt >= 0.0:
			rt += delta / 0.8
			r["t"] = rt
			var mi2 := r["mi"] as MeshInstance3D
			if rt >= 1.0:
				mi2.visible = false
				r["t"] = -1.0
			else:
				var s := 0.35 + rt * 1.7
				mi2.scale = Vector3(s, 1.0, s)
				(r["mat"] as StandardMaterial3D).albedo_color.a = (1.0 - rt) * 0.75
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
	hud_ammo.text = "弾: %d / %d" % [ammo, MAG_SIZE]
	if _reload_t > 0.0:
		hud_ammo.text += "  リロード中…"
	if hud_cross:
		hud_cross.position = get_viewport().get_mouse_position() - Vector2(22, 22)

func _update_camera(_delta: float) -> void:
	if not boat or not camera:
		return
	var target := Vector3(boat.global_position.x, clampf(boat.global_position.y + 0.9, 0.35, 3.0), boat.global_position.z)
	var off := Vector3(sin(cam_yaw) * cos(cam_pitch), sin(cam_pitch), cos(cam_yaw) * cos(cam_pitch)) * cam_dist
	camera.global_position = target + off
	camera.look_at(target, Vector3.UP)
	if _shake > 0.0:
		camera.rotation.x += sin(_gun_time * 95.0) * 0.0035 * _shake
		camera.rotation.z += cos(_gun_time * 83.0) * 0.0028 * _shake
