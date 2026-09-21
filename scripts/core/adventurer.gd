class_name Adventurer
extends RefCounted

## One persistent adventurer in the town's roster. Survives between waves,
## gains XP and levels, can camp at a rest area or be bound to a teleport stair.

## XP needed to go from level L to L+1 = L * XP_PER_LEVEL.
const XP_PER_LEVEL := 5.0

var id: int
var cls: String
var level: int = 1
var xp: float = 0.0
var alive: bool = true
var camp_node: String = ""    # stairwell they are camping at (continue from there next wave)
var bind_node: String = ""    # teleport stair they are bound to (start there next wave)
var waves_survived: int = 0


func _init(p_id: int, p_cls: String, p_level: int = 1) -> void:
	id = p_id
	cls = p_cls
	level = p_level


func name() -> String:
	return "%s#%d" % [cls.capitalize(), id]


func xp_to_next() -> float:
	return level * XP_PER_LEVEL


## Returns how many levels were gained.
func gain_xp(amount: float) -> int:
	xp += amount
	var gained := 0
	while xp >= xp_to_next():
		xp -= xp_to_next()
		level += 1
		gained += 1
	return gained


func describe() -> String:
	return "%s L%d" % [name(), level]
