extends Node
## Probe: why do taps miss? Direct ray vs simulated tap events, several aim points.

var main: Node
var boat: BoatBody
var camera: Camera3D

func _wait(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _aim(local: Vector3) -> Vector2:
	return camera.unproject_position(boat.to_global(local))

func _tap(pos: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = pos
	press.global_position = pos
	Input.parse_input_event(press)
	await get_tree().process_frame
	await get_tree().process_frame
	print("   after press: _dragging=", main.get("_dragging"))
	var rel := InputEventMouseButton.new()
	rel.button_index = MOUSE_BUTTON_LEFT
	rel.pressed = false
	rel.position = pos
	rel.global_position = pos
	Input.parse_input_event(rel)
	await get_tree().process_frame
	await get_tree().process_frame

func _ready() -> void:
	var ps: PackedScene = load("res://main.tscn")
	main = ps.instantiate()
	add_child(main)
	await get_tree().physics_frame
	boat = main.get("boat")
	camera = main.get("camera")
	await _wait(90)
	# A) direct ray at the transom (surface facing the camera)
	var before: int = boat.holes.size()
	var sp := _aim(Vector3(-0.55, 0.7, -3.1))
	var ok: bool = main.call("shoot_at_screen", sp)
	print("A direct side-hull: ok=", ok, " holes ", before, "->", boat.holes.size(), " screen=", sp)
	if boat.holes.size() > before:
		print("   hole local=", boat.holes[boat.holes.size() - 1]["local"])
	# B) direct ray at console top (above the old box top y=1.195)
	before = boat.holes.size()
	sp = _aim(Vector3(0, 1.55, 0.35))
	ok = main.call("shoot_at_screen", sp)
	print("B direct console: ok=", ok, " holes ", before, "->", boat.holes.size(), " screen=", sp)
	if boat.holes.size() > before:
		print("   hole local=", boat.holes[boat.holes.size() - 1]["local"])
	# C) direct ray at bow tip area
	before = boat.holes.size()
	sp = _aim(Vector3(0.3, 0.9, 3.1))
	ok = main.call("shoot_at_screen", sp)
	print("C direct bow: ok=", ok, " holes ", before, "->", boat.holes.size(), " screen=", sp)
	if boat.holes.size() > before:
		print("   hole local=", boat.holes[boat.holes.size() - 1]["local"])
	# D) simulated tap (press+release via input system) at the transom
	boat.reset_boat()
	await _wait(30)
	before = boat.holes.size()
	sp = _aim(Vector3(-0.55, 0.7, -3.1))
	await _tap(sp)
	print("D simulated tap side-hull: holes ", before, "->", boat.holes.size(), " screen=", sp)
	# E) simulated tap at console
	before = boat.holes.size()
	sp = _aim(Vector3(0, 1.55, 0.35))
	await _tap(sp)
	print("E simulated tap console: holes ", before, "->", boat.holes.size(), " screen=", sp)
	get_tree().quit(0)
