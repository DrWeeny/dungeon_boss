class_name DungeonMap
extends RefCounted

## Geometry for one floor: where each node sits on a tile grid, which tiles are
## room floor / corridor / door, and what marker (chest, stair, boss) to draw.
##
## The map is a LAYOUT of DungeonGraph, not a second source of truth: it is
## rebuilt from the graph after every change, so the simulation rules never have
## to know about tiles. Room footprints come from Room.Size:
##   Small 2x2, Medium 4x4, Large 8x8; the entry is 2x2 and the boss room 8x8.
##
## Doors are not decoration: a room gets one door tile per connection, so a room
## with two outgoing branches really shows two doors leading to two rooms.

enum Tile { EMPTY, FLOOR, CORRIDOR, DOOR }

const SIZE_TILES := { Room.Size.SMALL: 2, Room.Size.MEDIUM: 4, Room.Size.LARGE: 8 }
const ENTRY_TILES := 2
const BOSS_TILES := 8
## Blank tiles between one column of rooms and the next (corridors run here).
const COLUMN_GAP := 4
## Blank tiles between two rooms stacked in the same column.
const ROW_GAP := 2
const MARGIN := 1

## Marker names are also the texture file names looked up in assets/tiles/.
const MARK_CHEST := "chest"
const MARK_STAIR := "stair"
const MARK_TELEPORT := "teleport"
const MARK_REST := "rest"
const MARK_SARCO := "sarcophagus"
const MARK_BOSS := "boss"
const MARK_ENTRY := "entry"
const MARK_MONSTER := "monster"
const MARK_TRAP := "trap"
const MARK_REWARD := "reward"

## A door tile knows what it gates, so the view can colour it.
enum DoorKind { PLAIN, SECRET, ENIGMA, LETHAL }

var width: int = 0
var height: int = 0
var tiles: Array = []                  # [y][x] -> Tile
var rects: Dictionary = {}             # node id -> Rect2i (in tiles)
var markers: Dictionary = {}           # Vector2i -> marker name
var doors: Dictionary = {}             # Vector2i -> {kind: DoorKind, from: String, to: String}
var owner_of: Dictionary = {}          # Vector2i -> node id (room tiles only)
var floor_index: int = 0


static func build(graph: DungeonGraph, floor_index: int) -> DungeonMap:
	var m := DungeonMap.new()
	m.floor_index = floor_index
	m._layout(graph, floor_index)
	return m


# --- queries ----------------------------------------------------------------

func tile_at(p: Vector2i) -> Tile:
	if p.x < 0 or p.y < 0 or p.y >= tiles.size() or p.x >= width:
		return Tile.EMPTY
	return tiles[p.y][p.x]


func node_at_tile(p: Vector2i) -> String:
	return owner_of.get(p, "")


func rect_of(node_id: String) -> Rect2i:
	return rects.get(node_id, Rect2i())


# --- layout -----------------------------------------------------------------

## Column = distance from the floor's entry, so a path reads left to right and
## branches stack vertically.
func _depths(graph: DungeonGraph, ids: Array) -> Dictionary:
	var depth := {}
	var floor := graph.floors[floor_index]
	var root := floor.entry_id
	if root == "" or not ids.has(root):
		root = ids[0] if ids.size() > 0 else ""
	if root == "":
		return depth
	depth[root] = 0
	var queue: Array[String] = [root]
	while queue.size() > 0:
		var cur: String = queue.pop_front()
		for nid in graph.next_of(cur):
			if not ids.has(nid):
				continue   # leads to another floor
			var d: int = int(depth[cur]) + 1
			if not depth.has(nid) or int(depth[nid]) < d:
				depth[nid] = d
				queue.append(nid)
	# Anything unreachable (shouldn't happen) lands in column 0.
	for id in ids:
		if not depth.has(id):
			depth[id] = 0
	return depth


func _tiles_for(graph: DungeonGraph, node_id: String) -> int:
	var n := graph.node_at(node_id)
	if n.kind == DungeonGraph.NodeKind.ENTRY:
		return ENTRY_TILES
	if n.kind == DungeonGraph.NodeKind.BOSS:
		return BOSS_TILES
	return SIZE_TILES[n.room.size]


func _layout(graph: DungeonGraph, p_floor: int) -> void:
	var ids: Array = graph.floors[p_floor].node_ids.duplicate()
	if ids.is_empty():
		return
	var depth := _depths(graph, ids)

	# Group by column, keeping insertion order inside a column.
	var columns := {}
	for id in ids:
		var d: int = int(depth[id])
		if not columns.has(d):
			columns[d] = []
		columns[d].append(id)
	var col_keys: Array = columns.keys()
	col_keys.sort()

	# Column x offsets and total height.
	var col_x := {}
	var x := MARGIN
	var tallest := 0
	for c in col_keys:
		var w := 0
		var h := -ROW_GAP
		for id in columns[c]:
			var t := _tiles_for(graph, id)
			w = maxi(w, t)
			h += t + ROW_GAP
		col_x[c] = x
		x += w + COLUMN_GAP
		tallest = maxi(tallest, h)
	width = x - COLUMN_GAP + MARGIN
	height = tallest + MARGIN * 2

	# Place rooms, centred vertically in their column.
	for c in col_keys:
		var h := -ROW_GAP
		for id in columns[c]:
			h += _tiles_for(graph, id) + ROW_GAP
		var y := MARGIN + (tallest - h) / 2
		for id in columns[c]:
			var t := _tiles_for(graph, id)
			rects[id] = Rect2i(int(col_x[c]), y, t, t)
			y += t + ROW_GAP

	_init_tiles()
	for id in ids:
		_carve_room(graph, id)
	for id in ids:
		for nid in graph.next_of(id):
			if ids.has(nid):
				_carve_link(graph, id, nid)


func _init_tiles() -> void:
	tiles = []
	for y in height:
		var row: Array = []
		row.resize(width)
		row.fill(Tile.EMPTY)
		tiles.append(row)


func _put(p: Vector2i, t: Tile) -> void:
	if p.x < 0 or p.y < 0 or p.x >= width or p.y >= height:
		return
	# A door already carved stays a door; a room floor never becomes a corridor.
	var cur: Tile = tiles[p.y][p.x]
	if cur == Tile.DOOR and t != Tile.DOOR:
		return
	if cur == Tile.FLOOR and t == Tile.CORRIDOR:
		return
	tiles[p.y][p.x] = t


func _carve_room(graph: DungeonGraph, node_id: String) -> void:
	var r: Rect2i = rects[node_id]
	var n := graph.node_at(node_id)
	for yy in r.size.y:
		for xx in r.size.x:
			var p := Vector2i(r.position.x + xx, r.position.y + yy)
			_put(p, Tile.FLOOR)
			owner_of[p] = node_id
	_mark_room(n, r)


## Markers describe the room's contents at a glance (and are the tile names the
## view looks for in assets/tiles/).
func _mark_room(n: DungeonGraph.DNode, r: Rect2i) -> void:
	if n.kind == DungeonGraph.NodeKind.ENTRY:
		markers[r.position] = MARK_ENTRY
		return
	if n.kind == DungeonGraph.NodeKind.BOSS:
		markers[r.position + r.size / 2 - Vector2i.ONE] = MARK_BOSS
		return
	# Fill from the bottom row up, so the room name stays readable at the top.
	var spots: Array[Vector2i] = []
	for yy in range(r.size.y - 1, -1, -1):
		for xx in r.size.x:
			spots.append(Vector2i(r.position.x + xx, r.position.y + yy))
	var i := 0
	for s in n.room.structurals:
		if i >= spots.size():
			break
		var name := ""
		match s.kind:
			StructuralElement.Kind.CHEST:
				name = MARK_CHEST
			StructuralElement.Kind.SARCOPHAGUS:
				name = MARK_SARCO
			StructuralElement.Kind.STAIR:
				name = MARK_TELEPORT if s.has_modifier("mod_teleport") else (MARK_REST if s.has_modifier("mod_rest") else MARK_STAIR)
		if name != "":
			markers[spots[i]] = name
			i += 1
	for c in n.room.contents:
		if i >= spots.size():
			break
		match c.category:
			ContentDef.Category.MONSTER:
				markers[spots[i]] = MARK_MONSTER
			ContentDef.Category.TRAP:
				markers[spots[i]] = MARK_TRAP
			ContentDef.Category.REWARD:
				markers[spots[i]] = MARK_REWARD
			_:
				continue
		i += 1


func _door_kind(room: Room) -> DoorKind:
	if room == null:
		return DoorKind.PLAIN
	for s in room.structurals:
		if s.kind != StructuralElement.Kind.DOOR:
			continue
		if s.has_modifier("mod_lethal"):
			return DoorKind.LETHAL
		if s.gate_level() > 0:
			return DoorKind.ENIGMA
		if s.has_modifier("mod_secret"):
			return DoorKind.SECRET
	return DoorKind.PLAIN


## A corridor from `from` to `to`: out of a door on the source room, an L-shaped
## run through the gap, in through a door on the target room.
func _carve_link(graph: DungeonGraph, from: String, to: String) -> void:
	var a: Rect2i = rects[from]
	var b: Rect2i = rects[to]
	var a_door := Vector2i(a.position.x + a.size.x, a.position.y + a.size.y / 2)
	var b_door := Vector2i(b.position.x - 1, b.position.y + b.size.y / 2)
	if b.position.x <= a.position.x:
		# Target is not to the right (a link back or within a column): go around.
		a_door = Vector2i(a.position.x + a.size.x / 2, a.position.y + a.size.y)
		b_door = Vector2i(b.position.x + b.size.x / 2, b.position.y - 1)

	_put(a_door, Tile.DOOR)
	doors[a_door] = {"kind": _door_kind(graph.node_at(from).room), "from": from, "to": to}
	_put(b_door, Tile.DOOR)
	doors[b_door] = {"kind": _door_kind(graph.node_at(to).room), "from": from, "to": to}

	# L-shaped corridor between the two door tiles.
	var p := a_door
	var mid_x := a_door.x + 1 if b_door.x > a_door.x else a_door.x
	while p.x != mid_x:
		p.x += signi(mid_x - p.x)
		_put(p, Tile.CORRIDOR)
	while p.y != b_door.y:
		p.y += signi(b_door.y - p.y)
		_put(p, Tile.CORRIDOR)
	while p.x != b_door.x:
		p.x += signi(b_door.x - p.x)
		_put(p, Tile.CORRIDOR)
	_put(a_door, Tile.DOOR)
	_put(b_door, Tile.DOOR)
