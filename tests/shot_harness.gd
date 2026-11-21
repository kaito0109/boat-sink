extends Node
## Xvfb screenshots: 01 floating (photo composition) / 02 flooding, deck awash, listing (photo state) / 03 sunk

var main: Node
var boat: BoatBody

func _wait_physics(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _snap(path: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("saved ", path, " size=", img.get_size())

func _ready() -> void:
	get_window().size = Vector2i(1152, 768)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://shots"))
	var ps: PackedScene = load("res://main.tscn")
	main = ps.instantiate()
	add_child(main)
	await get_tree().physics_frame
	boat = main.get("boat")
	await _wait_physics(150)
	await _snap("res://shots/01_floating.png")
	# 発砲の瞬間: 船尾を狙って撃ち、トレーサー/フラッシュを撮る
	var cam: Camera3D = main.get("camera")
	var sp := cam.unproject_position(boat.to_global(Vector3(-0.55, 0.7, -3.1)))
	main.call("shoot_at_screen", sp)
	await get_tree().process_frame
	var fimg := get_viewport().get_texture().get_image()
	fimg.save_png("res://shots/00_firing.png")
	print("saved res://shots/00_firing.png")
	boat.reset_boat()
	await _wait_physics(90)
	# 写真の状態へ: 右舷の船底2発 + 右舷側面(水面付近)1発
	main.set("_cooldown", 0.0)
	main.call("shoot_local", Vector3(0.55, 0.16, -0.9), Vector3.DOWN)
	main.set("_cooldown", 0.0)
	main.call("shoot_local", Vector3(0.60, 0.16, 1.2), Vector3.DOWN)
	main.set("_cooldown", 0.0)
	main.call("shoot_local", Vector3(1.10, 0.55, 0.2), Vector3.RIGHT)
	await _wait_physics(690) # ~11.5s: 船内が水で満たされ傾く (写真の状態)
	print("shot02 state: y=%.2f flood=%.2f" % [boat.global_position.y, boat.flood_ratio])
	await _snap("res://shots/02_flooding.png")
	await _wait_physics(720) # さらに12s
	print("shot03 state: y=%.2f flood=%.2f sunk=%s" % [boat.global_position.y, boat.flood_ratio, str(boat.sunk)])
	await _snap("res://shots/03_sunk.png")
	get_tree().quit(0)
