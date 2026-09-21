class_name DungeonGraph
extends RefCounted

## The dungeon as a stack of floors, each a fixed directed graph:
##   entry -> rooms/junctions -> stairs  ==>  next floor's landing  ...  ==> boss floor
## You start with floor 0 and floor -1 (the boss). Boss levels insert new floors
## in between (see insert_floor). Parties do not path-find; at each node they pick
## one outgoing edge by weighted random choice (WaveSim.branch_weight).
##
## A node with no outgoing edge is a dead end: the party leaves the dungeon from
## there with whatever it looted. That is the "let them flee with a reward" bait.

enum NodeKind { ENTRY, ROOM, STAIR, BOSS }

## Magic cost to build a new room by size.
const BUILD_COST := { Room.Size.SMALL: 4, Room.Size.MEDIUM: 7, Room.Size.LARGE: 12 }
## Magic cost of a teleport stair (a small stairwell fitted with a teleport bind).
const TELEPORT_COST := 10


class DNode:
	var id: String
	var kind: DungeonGraph.NodeKind
	var room: Room          # null for ENTRY / BOSS
	var floor: int = 0      # index into DungeonGraph.floors
	var next: Array[String] = []

	func label() -> String:
		return room.name if room != null else id.capitalize()


class Floor:
	var index: int          # 0 = top; the boss floor is always last
	var entry_id: String    # where a party arrives on this floor
	var exit_id: String     # the stairs down (== entry for the boss floor)
	var node_ids: Array[String] = []

	## Display number: floor 0, -1, -2 ... (the boss floor is the deepest).
	func depth_label() -> String:
		return "Floor %d" % (-index)


var nodes: Dictionary = {}      # id -> DNode
var floors: Array[Floor] = []
var entry_id: String = ""
var boss_id: String = ""
var _built_rooms: int = 0


# --- queries ----------------------------------------------------------------

func node_at(id: String) -> DNode:
	return nodes.get(id)


func next_of(id: String) -> Array[String]:
	var n := node_at(id)
	if n == null:
		var empty: Array[String] = []
		return empty
	return n.next


func floor_of(id: String) -> Floor:
	var n := node_at(id)
	return floors[n.floor] if n != null else null


func boss_floor() -> Floor:
	return floors[floors.size() - 1]


## All room-bearing nodes, floor by floor, in insertion order.
func room_nodes() -> Array[DNode]:
	var out: Array[DNode] = []
	for f in floors:
		for id in f.node_ids:
			var n: DNode = nodes[id]
			if n.room != null:
				out.append(n)
	return out


func rooms() -> Array[Room]:
	var out: Array[Room] = []
	for n in room_nodes():
		out.append(n.room)
	return out


func room_nodes_on(floor_index: int) -> Array[DNode]:
	var out: Array[DNode] = []
	for id in floors[floor_index].node_ids:
		var n: DNode = nodes[id]
		if n.room != null:
			out.append(n)
	return out


# --- construction -----------------------------------------------------------

func _add_node(id: String, kind: NodeKind, floor_index: int, room: Room = null) -> DNode:
	assert(not nodes.has(id), "duplicate node id " + id)
	var n := DNode.new()
	n.id = id
	n.kind = kind
	n.room = room
	n.floor = floor_index
	nodes[id] = n
	floors[floor_index].node_ids.append(id)
	if kind == NodeKind.BOSS:
		boss_id = id
	return n


func _add_floor_at(index: int) -> Floor:
	var f := Floor.new()
	floors.insert(index, f)
	for i in floors.size():
		floors[i].index = i
	for id in nodes:
		var n: DNode = nodes[id]
		if n.floor >= index and not floors[index].node_ids.has(id):
			n.floor += 1
	return f


func link(from: String, to: String) -> void:
	assert(nodes.has(from) and nodes.has(to), "link: unknown node")
	var n: DNode = nodes[from]
	if not n.next.has(to):
		n.next.append(to)


## Each floor's stairs lead to exactly the next floor's entry.
func _relink_floors() -> void:
	for i in floors.size() - 1:
		var stairs: DNode = nodes[floors[i].exit_id]
		var down := floors[i + 1].entry_id
		stairs.next.clear()
		stairs.next.append(down)


## Player action: grow a new branch off `from_id` on the same floor.
## `to_id` = "" makes a dead end (the party leaves from there); otherwise the new
## room links onward to that node (typically the floor's stairs).
func build_room(from_id: String, size: Room.Size, to_id: String = "", name: String = "") -> DNode:
	var from := node_at(from_id)
	assert(from != null and from.kind != NodeKind.BOSS, "build_room: bad origin")
	if to_id != "":
		var to := node_at(to_id)
		assert(to != null and to.floor == from.floor, "build_room: target must be on the same floor")
	_built_rooms += 1
	if name == "":
		name = "%s annex %d" % [Room.SIZE_NAMES[size], _built_rooms]
	var room := Room.new(name, size)
	var n := _add_node("built_%d" % _built_rooms, NodeKind.ROOM, from.floor, room)
	link(from_id, n.id)
	if to_id != "":
		link(n.id, to_id)
	return n


## Player action: a stairwell off `from_id` that drops straight to a deeper floor
## (skipping the ones between) and binds the groups that use it, so they start
## there next time. The bait for a "secret corridor".
func build_teleport(from_id: String, target_floor: int) -> DNode:
	var from := node_at(from_id)
	assert(from != null and from.kind != NodeKind.BOSS, "build_teleport: bad origin")
	assert(target_floor > from.floor and target_floor < floors.size() - 1, "build_teleport: target must be a deeper non-boss floor")
	_built_rooms += 1
	var room := Room.new("Teleport stair %d" % _built_rooms, Room.Size.SMALL)
	var stair := StructuralElement.stair()
	stair.modifier_slots = maxi(stair.modifier_slots, 1)
	stair.add_modifier(ContentLibrary.get_def("mod_teleport"))
	room.add_structural(stair)
	var n := _add_node("built_%d" % _built_rooms, NodeKind.STAIR, from.floor, room)
	link(from_id, n.id)
	link(n.id, floors[target_floor].entry_id)
	return n


## Boss progression: a new floor slides in between the deepest floor and the boss.
## Layout of a generated floor (4 rooms, 1 junction):
##   landing --+-> gallery --+-> stairs
##             +-> tomb -----+
func insert_floor(chest_tier: int = 1) -> Floor:
	var index := floors.size() - 1          # just above the boss floor
	var f := _add_floor_at(index)
	var p := "f%d_" % index
	var depth := -index

	var landing := Room.new("Landing %d" % depth, Room.Size.MEDIUM)
	landing.add_structural(StructuralElement.door())
	var gallery := Room.new("Gallery %d" % depth, Room.Size.LARGE)
	var tomb := Room.new("Tomb %d" % depth, Room.Size.SMALL)
	tomb.add_structural(StructuralElement.chest(chest_tier))
	var stairs := Room.new("Stairwell %d" % depth, Room.Size.SMALL)
	stairs.add_structural(StructuralElement.stair())

	_add_node(p + "landing", NodeKind.ROOM, index, landing)
	_add_node(p + "gallery", NodeKind.ROOM, index, gallery)
	_add_node(p + "tomb", NodeKind.ROOM, index, tomb)
	_add_node(p + "stairs", NodeKind.STAIR, index, stairs)
	f.entry_id = p + "landing"
	f.exit_id = p + "stairs"
	link(p + "landing", p + "gallery")
	link(p + "landing", p + "tomb")
	link(p + "gallery", p + "stairs")
	link(p + "tomb", p + "stairs")
	_relink_floors()
	return f


## The POC's hand-authored start: floor 0 (7 nodes, 2 junctions) + the boss floor.
##
##   entry -> hall --+-> crypt ------------> vault --+-> stairs ==> boss
##                   +-> ossuary --+-> vault --------+
##                                 +-> shrine -> stairs
static func build_poc_level() -> DungeonGraph:
	var g := DungeonGraph.new()

	var f0 := g._add_floor_at(0)
	g._add_node("entry", NodeKind.ENTRY, 0)
	g.entry_id = "entry"

	var hall := Room.new("Entrance hall", Room.Size.MEDIUM)
	hall.add_structural(StructuralElement.door())
	g._add_node("hall", NodeKind.ROOM, 0, hall)

	var crypt := Room.new("Crypt", Room.Size.SMALL)
	crypt.add_structural(StructuralElement.sarcophagus())
	g._add_node("crypt", NodeKind.ROOM, 0, crypt)

	var ossuary := Room.new("Ossuary", Room.Size.LARGE)
	ossuary.add_structural(StructuralElement.door())
	g._add_node("ossuary", NodeKind.ROOM, 0, ossuary)

	var vault := Room.new("Vault", Room.Size.MEDIUM)
	vault.add_structural(StructuralElement.chest(1))
	g._add_node("vault", NodeKind.ROOM, 0, vault)

	var shrine := Room.new("Shrine", Room.Size.SMALL)
	g._add_node("shrine", NodeKind.ROOM, 0, shrine)

	var stairs := Room.new("Stairwell", Room.Size.SMALL)
	stairs.add_structural(StructuralElement.stair())
	g._add_node("stairs", NodeKind.STAIR, 0, stairs)
	f0.entry_id = "entry"
	f0.exit_id = "stairs"

	g.link("entry", "hall")
	g.link("hall", "crypt")
	g.link("hall", "ossuary")
	g.link("crypt", "vault")
	g.link("ossuary", "vault")
	g.link("ossuary", "shrine")
	g.link("vault", "stairs")
	g.link("shrine", "stairs")

	var fb := g._add_floor_at(1)
	g._add_node("boss", NodeKind.BOSS, 1)
	fb.entry_id = "boss"
	fb.exit_id = "boss"

	g._relink_floors()
	return g
