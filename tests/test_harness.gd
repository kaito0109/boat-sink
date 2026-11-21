extends Node
## Headless logic test:
##  1) 無被弾では5秒浮き続け、浸水0・傾き小
##  2) 水面より上の穴では浸水しない
##  3) 船底(右舷寄り)3発で浸水が進み、沈下+右舷側へ傾く
##  4) さらに進むと沈没判定

var main: Node
var boat: BoatBody
var failed := false

func _ok(cond: bool, label: String) -> void:
	print(("PASS " if cond else "FAIL ") + label)
	if not cond:
		failed = true

func _wait_physics(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _fire_screen(sp: Vector2) -> bool:
	# Gameplay gating (cooldown / magazine) is bypassed for the physics
	# sections; section 8 tests the gating itself without this helper.
	main.set("_cooldown", 0.0)
	main.set("_reload_t", 0.0)
	if int(main.get("ammo")) <= 0:
		main.set("ammo", 12)
	return main.call("shoot_at_screen", sp)

func _fire_local(p: Vector3, n: Vector3) -> void:
	main.set("_cooldown", 0.0)
	main.set("_reload_t", 0.0)
	if int(main.get("ammo")) <= 0:
		main.set("ammo", 12)
	main.call("shoot_local", p, n)

func _tap(pos: Vector2) -> void:
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = pos
		ev.global_position = pos
		Input.parse_input_event(ev)
		await get_tree().process_frame
		await get_tree().process_frame

func _tilt_deg() -> float:
	var up: Vector3 = boat.global_transform.basis.y.normalized()
	return rad_to_deg(acos(clampf(up.dot(Vector3.UP), -1.0, 1.0)))

func _ready() -> void:
	var ps: PackedScene = load("res://main.tscn")
	main = ps.instantiate()
	add_child(main)
	await get_tree().physics_frame
	boat = main.get("boat")
	# --- 1) idle float ---
	var y0: float = boat.global_position.y
	await _wait_physics(300) # 5s
	print("idle: y0=%.3f y=%.3f tilt=%.2f flood=%.3f" % [y0, boat.global_position.y, _tilt_deg(), boat.flood_ratio])
	_ok(absf(boat.global_position.y) < 0.65, "idle floats near waterline")
	_ok(boat.flood_ratio == 0.0, "idle no flooding")
	_ok(_tilt_deg() < 10.0, "idle stays upright")
	_ok(not boat.sunk, "idle not sunk")
	# --- 2) hole above waterline does not flood ---
	_fire_local(Vector3(1.10, 1.15, 0.2), Vector3.RIGHT)
	await _wait_physics(180) # 3s
	print("above-water hole: flood=%.3f holes=%d" % [boat.flood_ratio, boat.holes.size()])
	_ok(boat.holes.size() == 1, "hole registered")
	_ok(boat.flood_ratio < 0.01, "hole above waterline does not flood")
	# --- 3) bottom holes (starboard) flood + sink + list ---
	boat.reset_boat()
	await _wait_physics(30)
	var y_start: float = boat.global_position.y
	_fire_local(Vector3(0.55, 0.16, -0.9), Vector3.DOWN)
	_fire_local(Vector3(0.60, 0.16, 0.3), Vector3.DOWN)
	_fire_local(Vector3(0.50, 0.16, 1.4), Vector3.DOWN)
	await _wait_physics(720) # 12s
	print("flooding: y_start=%.3f y=%.3f tilt=%.2f flood=%.3f status=%s" % [y_start, boat.global_position.y, _tilt_deg(), boat.flood_ratio, boat.status_text()])
	_ok(boat.flood_ratio > 0.45, "bottom holes flood the boat (>45% in 12s)")
	_ok(boat.global_position.y < y_start - 0.55, "boat sinks down")
	_ok(_tilt_deg() > 6.0, "boat lists while sinking")
	# --- 4) keeps sinking to sunk ---
	await _wait_physics(1500) # 25s more
	print("final: y=%.3f tilt=%.2f flood=%.3f sunk=%s" % [boat.global_position.y, _tilt_deg(), boat.flood_ratio, str(boat.sunk)])
	_ok(boat.flood_ratio > 0.9, "flooding reaches >90%")
	_ok(boat.global_position.y < -1.2 or boat.sunk, "boat goes under")
	# --- 5) reset restores ---
	boat.reset_boat()
	await _wait_physics(240)
	print("reset: y=%.3f flood=%.3f holes=%d" % [boat.global_position.y, boat.flood_ratio, boat.holes.size()])
	_ok(boat.holes.size() == 0 and boat.flood_ratio == 0.0, "reset clears holes/flood")
	_ok(absf(boat.global_position.y) < 0.65, "reset floats again")
	# --- 6) raycast hits the VISIBLE mesh where aimed (v2.1 regression) ---
	boat.reset_boat()
	await _wait_physics(30)
	var cam: Camera3D = main.get("camera")
	var aim_side := Vector3(-0.55, 0.7, -3.1) # transom, the surface facing the camera
	var sp := cam.unproject_position(boat.to_global(aim_side))
	var before: int = boat.holes.size()
	var ok_hit: bool = _fire_screen(sp)
	_ok(ok_hit and boat.holes.size() == before + 1, "ray hits boat at aimed screen point")
	if boat.holes.size() > before:
		var hl: Vector3 = boat.holes[boat.holes.size() - 1]["local"]
		print("ray hole local=", hl, " aimed near ", aim_side)
		_ok(hl.distance_to(aim_side) < 0.35, "hole lands near the aimed point on the hull")
		_ok(hl.y < 1.05, "transom aim does not land on the top face")
	before = boat.holes.size()
	sp = cam.unproject_position(boat.to_global(Vector3(0, 1.5, 0.35)))
	ok_hit = _fire_screen(sp)
	_ok(ok_hit and boat.holes.size() == before + 1, "ray hits console (visual mesh above old box)")
	# --- 7) simulated tap: NOTE — the headless DisplayServer drops mouse
	# button events, so the tap path is verified separately under Xvfb
	# (tests/probe_scene.tscn). Here we only check the tap handler state
	# machine via a direct release-position decision: distance from press.
	before = boat.holes.size()
	sp = cam.unproject_position(boat.to_global(Vector3(-0.55, 0.7, -3.1)))
	await _tap(sp)
	print("tap (headless, informational): holes ", before, "->", boat.holes.size())
	# --- 8) v3 gun system: ammo, water miss, auto reload, audio ---
	boat.reset_boat()
	await _wait_physics(30)
	main.set("ammo", 12)
	main.set("_cooldown", 0.0)
	main.set("_reload_t", 0.0)
	var cam2: Camera3D = main.get("camera")
	var sp2 := cam2.unproject_position(boat.to_global(Vector3(-0.55, 0.7, -3.1)))
	var fired: bool = main.call("shoot_at_screen", sp2)
	_ok(fired and int(main.get("ammo")) == 11, "shot consumes one round")
	_ok(bool(main.get("last_hit_boat")), "transom shot registers as boat hit")
	var wsp := cam2.unproject_position(Vector3(3.5, 0.0, 6.0))
	main.set("_cooldown", 0.0)
	fired = main.call("shoot_at_screen", wsp)
	_ok(fired and not bool(main.get("last_hit_boat")), "open-water shot is a miss (splash only)")
	main.set("ammo", 1)
	main.set("_cooldown", 0.0)
	fired = main.call("shoot_at_screen", sp2)
	_ok(fired and int(main.get("ammo")) == 0, "last round fires")
	_ok(float(main.get("_reload_t")) > 0.0, "auto reload starts when empty")
	await get_tree().create_timer(1.5).timeout
	_ok(int(main.get("ammo")) == 12, "reload refills the magazine")
	var shot_player: AudioStreamPlayer = main.get("_audio_shot")
	_ok(shot_player != null and shot_player.stream != null and shot_player.stream.get_length() > 0.2, "synthesized gunshot stream exists")
	_ok(main.get("_gun_pivot") != null, "gun viewmodel is built")
	print("RESULT: " + ("ALL PASS" if not failed else "SOME FAILED"))
	get_tree().quit(1 if failed else 0)
