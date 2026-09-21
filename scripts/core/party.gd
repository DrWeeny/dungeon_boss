class_name Party
extends RefCounted

## An adventurer group. For the POC it is a single scalar power stat plus a class
## mix and per-member levels. The class mix is only used by the monster-attraction
## system; member levels matter in the boss fight (highest level alive = damage).
##
## Damage is decimal, in member-equivalents: it accumulates as `wounds`; every
## full point kills the weakest member, the fraction left over is walking wounded
## (lower power, less appetite for the boss). Healing specials reduce wounds.

const CLASSES: Array[String] = ["warrior", "mage", "priest", "rogue"]
const POWER_PER_MEMBER := 1.0
## Power lost per point of wounds (a fully wounded member fights at half strength).
const WOUND_POWER := 0.5
## Member level = wave +/- this much (never below 1).
const LEVEL_SPREAD := 1

var size: int = 4
var level: int = 1                    # the wave's nominal level
var base_power: float = 4.0
var classes: Array[String] = []
var member_levels: Array[int] = []    # sorted ascending; the weakest die first
var wounds: float = 0.0               # 0 <= wounds < 1 between kills
var loot: float = 0.0
var alive: bool = true
var members_lost: int = 0


## Scalar power the opposed roll uses. Shrinks as members die or get hurt.
func power() -> float:
	return base_power + POWER_PER_MEMBER * size - WOUND_POWER * wounds


## Highest-level adventurer still standing (0 when nobody is).
func max_level_alive() -> int:
	return member_levels[member_levels.size() - 1] if member_levels.size() > 0 else 0


func avg_level() -> float:
	if member_levels.is_empty():
		return 0.0
	return float(levels_alive()) / member_levels.size()


func levels_alive() -> int:
	var total := 0
	for l in member_levels:
		total += l
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
	n = mini(n, size)
	for i in n:
		member_levels.pop_front()
		classes.pop_front()
	size -= n
	members_lost += n
	if size <= 0:
		alive = false


func describe() -> String:
	var members: Array[String] = []
	for i in size:
		members.append("%s L%d" % [classes[i], member_levels[i]])
	return "%d adventurers (power %.1f%s): %s" % [size, power(),
		", wounds %.1f" % wounds if wounds > 0.05 else "", ", ".join(members)]


## Spawn a party for a wave. `class_bias` maps class -> weight derived from the
## dungeon's monster attraction table (see GameSession.class_bias()).
static func spawn(wave: int, p_base_power: float, p_size: int,
		rng: RandomNumberGenerator, class_bias: Dictionary = {}) -> Party:
	var p := Party.new()
	p.level = wave
	p.size = p_size
	p.base_power = p_base_power
	var weights: Array[float] = []
	for c in CLASSES:
		weights.append(float(class_bias.get(c, 1.0)))
	var members: Array = []
	for i in p_size:
		members.append({
			"cls": CLASSES[_weighted_index(weights, rng)],
			"lvl": maxi(1, wave + rng.randi_range(-LEVEL_SPREAD, LEVEL_SPREAD)),
		})
	members.sort_custom(func(a, b) -> bool: return a.lvl < b.lvl)
	for m in members:
		p.classes.append(m.cls)
		p.member_levels.append(m.lvl)
	return p


static func _weighted_index(weights: Array[float], rng: RandomNumberGenerator) -> int:
	var total := 0.0
	for w in weights:
		total += w
	var r := rng.randf() * total
	for i in weights.size():
		r -= weights[i]
		if r <= 0.0:
			return i
	return weights.size() - 1
