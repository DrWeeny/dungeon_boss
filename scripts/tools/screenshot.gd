extends SceneTree

## Loads the main scene, waits a few frames and writes a screenshot.
##   godot --path . -s scripts/tools/_shot.gd

var _frames := 0


func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	var scene: Node = packed.instantiate()
	root.add_child(scene)


func _process(_d: float) -> bool:
	_frames += 1
	if _frames < 5:
		return false
	var img := root.get_texture().get_image()
	var path := "user://shot.png"
	img.save_png(path)
	print("saved to ", ProjectSettings.globalize_path(path))
	return true
