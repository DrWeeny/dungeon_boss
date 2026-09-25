class_name MapView
extends Control

## Draws one floor of the dungeon on a tile grid and lets you click a room.
##
## Placeholder art by default: every tile is a flat colour and markers are drawn
## as simple shapes. To use real tiles, drop PNGs into `assets/tiles/` named after
## the tile or marker and they are picked up automatically, no code change:
##   floor.png  corridor.png  door.png  empty.png
##   entry.png  stair.png  teleport.png  rest.png  boss.png
##   chest.png  sarcophagus.png  monster.png  trap.png  reward.png
## Any size works; they are scaled to TILE_PX.

signal room_clicked(node_id: String)

const TILE_PX := 18
const TILE_DIR := "res://assets/tiles/"

const COLORS := {
	DungeonMap.Tile.EMPTY: Color(0.09, 0.08, 0.12),
	DungeonMap.Tile.FLOOR: Color(0.30, 0.28, 0.34),
	DungeonMap.Tile.CORRIDOR: Color(0.20, 0.19, 0.24),
	DungeonMap.Tile.DOOR: Color(0.62, 0.52, 0.28),
}
const DOOR_COLORS := {
	DungeonMap.DoorKind.PLAIN: Color(0.62, 0.52, 0.28),
	DungeonMap.DoorKind.SECRET: Color(0.35, 0.55, 0.65),
	DungeonMap.DoorKind.ENIGMA: Color(0.55, 0.40, 0.70),
	DungeonMap.DoorKind.LETHAL: Color(0.70, 0.25, 0.25),
}
const MARKER_COLORS := {
	DungeonMap.MARK_CHEST: Color(0.90, 0.75, 0.30),
	DungeonMap.MARK_REWARD: Color(0.90, 0.75, 0.30),
	DungeonMap.MARK_STAIR: Color(0.75, 0.80, 0.85),
	DungeonMap.MARK_TELEPORT: Color(0.45, 0.85, 0.85),
	DungeonMap.MARK_REST: Color(0.50, 0.85, 0.55),
	DungeonMap.MARK_SARCO: Color(0.70, 0.60, 0.85),
	DungeonMap.MARK_MONSTER: Color(0.85, 0.35, 0.35),
	DungeonMap.MARK_TRAP: Color(0.85, 0.55, 0.25),
	DungeonMap.MARK_BOSS: Color(0.95, 0.30, 0.45),
	DungeonMap.MARK_ENTRY: Color(0.55, 0.85, 0.95),
}

var map: DungeonMap
var selected: String = ""
## Node ids the last wave walked through, drawn as a trail.
var path: Array = []

static var _tex_cache: Dictionary = {}


func set_map(p_map: DungeonMap) -> void:
	map = p_map
	custom_minimum_size = Vector2(map.width * TILE_PX, map.height * TILE_PX) if map != null else Vector2.ZERO
	queue_redraw()


func set_selected(node_id: String) -> void:
	selected = node_id
	queue_redraw()


func set_path(p_path: Array) -> void:
	path = p_path
	queue_redraw()


static func _tex(name: String) -> Texture2D:
	if _tex_cache.has(name):
		return _tex_cache[name]
	var p := TILE_DIR + name + ".png"
	var t: Texture2D = load(p) if ResourceLoader.exists(p) else null
	_tex_cache[name] = t
	return t


func _gui_input(event: InputEvent) -> void:
	if map == null:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var t := Vector2i(event.position / TILE_PX)
		var id := map.node_at_tile(t)
		if id != "":
			room_clicked.emit(id)


func _draw() -> void:
	if map == null:
		return
	for y in map.height:
		for x in map.width:
			var p := Vector2i(x, y)
			var tile: DungeonMap.Tile = map.tile_at(p)
			var rect := Rect2(x * TILE_PX, y * TILE_PX, TILE_PX, TILE_PX)
			var name := ""
			var col: Color = COLORS[tile]
			match tile:
				DungeonMap.Tile.FLOOR:
					name = "floor"
				DungeonMap.Tile.CORRIDOR:
					name = "corridor"
				DungeonMap.Tile.DOOR:
					name = "door"
					var d: Dictionary = map.doors.get(p, {})
					if d.has("kind"):
						col = DOOR_COLORS[d.kind]
				_:
					name = "empty"
			var tex := _tex(name)
			if tex != null:
				draw_texture_rect(tex, rect, false)
			else:
				draw_rect(rect, col)
				if tile == DungeonMap.Tile.FLOOR:
					draw_rect(rect, Color(0, 0, 0, 0.25), false, 1.0)

	# Trail of the last wave.
	for id in path:
		var r: Rect2i = map.rect_of(id)
		if r.size.x == 0:
			continue
		draw_rect(_px(r), Color(0.95, 0.85, 0.40, 0.14))

	# Markers on top.
	for p in map.markers:
		var name: String = map.markers[p]
		var rect := Rect2(p.x * TILE_PX, p.y * TILE_PX, TILE_PX, TILE_PX)
		var tex := _tex(name)
		if tex != null:
			draw_texture_rect(tex, rect, false)
		else:
			_draw_marker(name, rect)

	# Room outlines, names and the selection.
	var font := ThemeDB.fallback_font
	for id in map.rects:
		var r: Rect2i = map.rects[id]
		var px := _px(r)
		var is_sel: bool = id == selected
		draw_rect(px, Color(0.95, 0.85, 0.45) if is_sel else Color(0.55, 0.52, 0.60), false, 2.0 if is_sel else 1.0)
		draw_string(font, px.position + Vector2(3, 11), id, HORIZONTAL_ALIGNMENT_LEFT, px.size.x - 4, 9,
			Color(1, 1, 1, 0.75) if is_sel else Color(1, 1, 1, 0.45))


func _px(r: Rect2i) -> Rect2:
	return Rect2(r.position.x * TILE_PX, r.position.y * TILE_PX, r.size.x * TILE_PX, r.size.y * TILE_PX)


## Placeholder glyphs: a shape per marker so the map reads without art.
func _draw_marker(name: String, rect: Rect2) -> void:
	var col: Color = MARKER_COLORS.get(name, Color.WHITE)
	var c := rect.get_center()
	var r := TILE_PX * 0.30
	match name:
		DungeonMap.MARK_CHEST, DungeonMap.MARK_REWARD:
			draw_rect(Rect2(c - Vector2(r, r * 0.8), Vector2(r * 2, r * 1.6)), col)
		DungeonMap.MARK_MONSTER:
			draw_circle(c, r, col)
		DungeonMap.MARK_TRAP:
			draw_line(c - Vector2(r, r), c + Vector2(r, r), col, 2.0)
			draw_line(c - Vector2(r, -r), c + Vector2(r, -r), col, 2.0)
		DungeonMap.MARK_STAIR, DungeonMap.MARK_TELEPORT, DungeonMap.MARK_REST:
			var steps := 3
			for i in steps:
				var h := rect.size.y / steps
				draw_rect(Rect2(rect.position.x + i * (rect.size.x / steps), rect.position.y + rect.size.y - (i + 1) * h,
					rect.size.x / steps, h), col)
		DungeonMap.MARK_SARCO:
			draw_rect(Rect2(c - Vector2(r * 0.7, r), Vector2(r * 1.4, r * 2)), col)
		DungeonMap.MARK_BOSS:
			draw_circle(c, r * 1.8, col)
		DungeonMap.MARK_ENTRY:
			draw_rect(Rect2(c - Vector2(r, r), Vector2(r * 2, r * 2)), col, false, 2.0)
		_:
			draw_circle(c, r * 0.6, col)
