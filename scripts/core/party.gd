class_name Party
extends RefCounted

## A group of persistent adventurers on one wave. Power is a scalar for the room
## roll; member levels matter at enigma doors and in the boss fight.
##
## Damage is decimal, in member-equivalents: it accumulates as `wounds`; every
## full point kills the weakest member, the fraction left over is walking wounded
## (lower power, less appetite for the boss). Healing specials reduce wounds.
##
## Treasures are a counter of tiers actually picked up; only what a group brings
## home recruits new adventurers (see Town).

const CLASSES: Array[String] = ["warrior", "mage", "priest", "rogue"]
const POWER_PER_MEMBER := 1.0
## Levels above 1 add this much power each (a level-3 member = 1 + 2 x 0.5).
const POWER_PER_LEVEL := 0.5
## Power lost per point of wounds (a fully wounded member fights at half strength).
const WOUND_POWER := 0.5

var members: Array[Adventurer] = []   # sorted by level ascending; the weakest die first
var start_node: String = ""           # "" = the entrance
var camped_before: bool = false
var wounds: float = 0.0               # 0 <= wounds < 1 between kills
var loot: float = 0.0                 # reward value carried (boss-door satisfaction)
var treasures: Array[int] = []        # tiers of treasure pieces carried
var alive: bool = true
var members_lost: int = 0
var went_home: Array[Adventurer] = [] # turned away at an enigma door, safe


func _init(p_members: Array[Adventurer] = [], p_start: String = "") -> void:
	members = p_members.duplicate()
	members.sort_custom(func(a: Adventurer, b: Adventurer) -> bool: return a.level < b.level)
	start_node = p_start
	alive = members.size() > 0


func size() -> int:
	return members.size()


## Scalar power the opposed roll uses. Shrinks as members die or get hurt.
func power() -> float:
	var p := 0.0
	for a in members:
		p += POWER_PER_MEMBER + POWER_PER_LEVEL * (a.level - 1)
	return p - WOUND_POWER * wounds


## Highest-level adventurer still standing (0 when nobody is).
func max_level_alive() -> int:
	return members[members.size() - 1].level if members.size() > 0 else 0


func avg_level() -> float:
	if members.is_empty():
		return 0.0
	return float(levels_alive()) / members.size()


func levels_alive() -> int:
	var total := 0
	for a in members:
		total += a.level
	return total


## Decimal damage in member-equivalents. Returns how many members it killed.
func apply_damage(amount: float) -> int:
	wounds += maxf(amount, 0.0)
	var kills := floori(wounds)
	wounds -= kills
	lose_members(kills)
	if not alive:
		wounds = 0.0
	return kills


func heal(amount: float) -> void:
	wounds = maxf(wounds - amount, 0.0)


func lose_members(n: int) -> void:
	n = mini(n, members.size())
	for i in n:
		var a: Adventurer = members.pop_front()
		a.alive = false
	members_lost += n
	if members.is_empty():
		alive = false


## Enigma door: members below `min_level` cannot pass and go home. Returns them.
func split_below(min_level: int) -> Array[Adventurer]:
	var stopped: Array[Adventurer] = []
	var keep: Array[Adventurer] = []
	for a in members:
		if a.level < min_level:
			stopped.append(a)
		else:
			keep.append(a)
	members = keep
	went_home.append_array(stopped)
	if members.is_empty():
		alive = false   # nobody went further; they are safe though (see WaveSim)
	return stopped


func take_treasures(tiers: Array[int], value: float) -> void:
	treasures.append_array(tiers)
	loot += value


func total_treasure_tiers() -> int:
	var t := 0
	for x in treasures:
		t += x
	return t


func describe() -> String:
	var names: Array[String] = []
	for a in members:
		names.append(a.describe())
	return "%d adventurers (power %.1f%s%s): %s" % [members.size(), power(),
		", wounds %.1f" % wounds if wounds > 0.05 else "",
		", %d treasure(s)" % treasures.size() if treasures.size() > 0 else "",
		", ".join(names)]
