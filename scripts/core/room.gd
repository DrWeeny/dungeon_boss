class_name Room
extends RefCounted

## A free-size container. Its "type" emerges from what is placed inside:
## content slots (monster / trap / reward / decoration / special) plus structural
## elements (door / stair / chest / sarcophagus) that carry their own modifier tracks.

enum Size { SMALL, MEDIUM, LARGE }
const SLOTS := { Size.SMALL: 1, Size.MEDIUM: 2, Size.LARGE: 4 }
const SIZE_NAMES := { Size.SMALL: "Small", Size.MEDIUM: "Medium", Size.LARGE: "Large" }

var name: String = ""
var size: Size = Size.SMALL
var contents: Array[ContentDef] = []
var structurals: Array[StructuralElement] = []
## Extra slots granted by boss-power unlocks ("Larger" rooms, scalable beyond 4).
var bonus_slots: int = 0


func _init(p_name: String = "", p_size: Size = Size.SMALL) -> void:
	name = p_name
	size = p_size


func size_name() -> String:
	return SIZE_NAMES[size]


func slot_count() -> int:
	return SLOTS[size] + bonus_slots


func free_slots() -> int:
	return slot_count() - contents.size()


func can_place(def: ContentDef) -> bool:
	return not def.is_modifier() and free_slots() > 0


func place(def: ContentDef) -> bool:
	if not can_place(def):
		return false
	contents.append(def)
	return true


func remove_at(idx: int) -> ContentDef:
	if idx < 0 or idx >= contents.size():
		return null
	return contents.pop_at(idx)


func add_structural(s: StructuralElement) -> void:
	structurals.append(s)


func has_secret_door() -> bool:
	for s in structurals:
		if s.kind == StructuralElement.Kind.DOOR and s.has_modifier("mod_secret"):
			return true
	return false


func has_sarcophagus() -> bool:
	for s in structurals:
		if s.kind == StructuralElement.Kind.SARCOPHAGUS:
			return true
	return false


## Additive dangerosity model (POC). Combo synergies are a planned extension.
func danger() -> float:
	var d := 0.0
	for c in contents:
		d += c.danger
	for s in structurals:
		d += s.danger()
	return maxf(d, 0.0)


func reward() -> float:
	var r := 0.0
	for c in contents:
		r += c.reward
	for s in structurals:
		r += s.reward()
	return r


## Wounds a party recovers here after winning the room (healing / rest specials).
func heal() -> float:
	var h := 0.0
	for c in contents:
		h += c.heal
	return h


## Identity of this room's content combination. Adventurer knowledge is keyed by
## this, so moving a combo to another node carries its reputation with it.
func combo_key() -> String:
	var ids: Array[String] = []
	for c in contents:
		ids.append(c.id)
	for s in structurals:
		ids.append(s.key_part())
	ids.sort()
	return ",".join(ids) if ids.size() > 0 else "empty"


## Mean attraction weight of this room's monsters/traps for an adventurer class.
func attraction_for(cls: String) -> float:
	var total := 0.0
	var n := 0
	for c in contents:
		if c.category == ContentDef.Category.MONSTER or c.category == ContentDef.Category.TRAP:
			total += float(c.attraction.get(cls, 1.0))
			n += 1
	return total / n if n > 0 else 1.0


func describe() -> String:
	var parts: Array[String] = []
	for c in contents:
		parts.append(c.display_name)
	for s in structurals:
		parts.append(s.describe())
	var body := ", ".join(parts) if parts.size() > 0 else "empty"
	return "%s [%s %d/%d] D=%.0f R=%.0f - %s" % [name, size_name(), contents.size(), slot_count(), danger(), reward(), body]
