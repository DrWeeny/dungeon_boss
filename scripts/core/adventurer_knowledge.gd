class_name AdventurerKnowledge
extends RefCounted

## What future adventurer groups *believe* about the dungeon. Two memories:
##   - per LOCATION (node id): what they expect to find at that spot, including
##     which combo was there last time. Swapping a room's contents does not erase
##     this: the next group walks in expecting the old room and gets surprised.
##   - per COMBO (combo key): a combination's reputation, which travels with it
##     when the player moves it somewhere else.
## Surprises pile up as `unpredictability`: pissed-off adventurers over-prepare.
## Building a fresh path (new node, no expectation) avoids that.

## Survivors report roughly this fraction of what they actually experienced.
const REPORT_RATE := 0.5
## A full party wipe multiplies that spot's believed dangerosity for the next wave.
const WIPE_MULT := 2.0
## A "worth it" reward found later on the path scales down the believed danger
## of the rooms that came before it.
const WORTH_IT_DISCOUNT := 0.8
## A reward counts as "worth it" when it is at least this fraction of the party's
## power at the time (placeholder for "reward matches the level's difficulty").
const WORTH_IT_RATIO := 0.75
## Beliefs drift back toward the unknown a little each wave (rumours fade).
const DECAY := 0.9
## Each surprise adds this much unpredictability; it decays per wave.
const SURPRISE_WEIGHT := 1.0
const UNPREDICTABILITY_DECAY := 0.6


class Belief:
	var danger: float = 0.0
	var reward: float = 0.0
	var explored: bool = false
	var wipes: int = 0
	var expected_key: String = ""   # location beliefs only: the combo seen there last

	func describe() -> String:
		if not explored:
			return "unknown"
		return "believed D=%.1f R=%.1f%s" % [danger, reward, " (wiped x%d)" % wipes if wipes > 0 else ""]


## What a party expects when weighing a branch: {danger, reward, explored, source}.
class Expectation:
	var danger: float = 0.0
	var reward: float = 0.0
	var explored: bool = false
	var source: String = "unknown"   # "here" | "reputation" | "unknown"

	func describe() -> String:
		match source:
			"here":
				return "expect D=%.1f R=%.1f" % [danger, reward]
			"reputation":
				return "heard of it: D=%.1f R=%.1f" % [danger, reward]
		return "unknown"


var locations: Dictionary = {}   # node_id -> Belief
var combos: Dictionary = {}      # combo_key -> Belief
var unpredictability: float = 0.0
var surprises_this_wave: int = 0


func location(node_id: String) -> Belief:
	if not locations.has(node_id):
		locations[node_id] = Belief.new()
	return locations[node_id]


func combo(key: String) -> Belief:
	if not combos.has(key):
		combos[key] = Belief.new()
	return combos[key]


## Location memory first; otherwise the combo's reputation from elsewhere.
func expectation(node_id: String, key: String) -> Expectation:
	var e := Expectation.new()
	var loc := location(node_id)
	if loc.explored:
		e.danger = loc.danger
		e.reward = loc.reward
		e.explored = true
		e.source = "here"
		return e
	var rep := combo(key)
	if rep.explored:
		e.danger = rep.danger
		e.reward = rep.reward
		e.explored = true
		e.source = "reputation"
	return e


## True when the party expected a different room at this spot. Call on arrival.
func check_surprise(node_id: String, key: String) -> bool:
	var loc := location(node_id)
	if loc.explored and loc.expected_key != "" and loc.expected_key != key:
		unpredictability += SURPRISE_WEIGHT
		surprises_this_wave += 1
		return true
	return false


## Survivors made it out. `visited` is an ordered list of
## {node_id, key, danger, reward} for each room the party actually resolved.
func report_survivors(visited: Array, party_power: float) -> void:
	for v in visited:
		_blend(location(v.node_id), v, REPORT_RATE)
		_blend(combo(v.key), v, REPORT_RATE)
	# A worth-it reward makes the rooms before it feel less dangerous.
	for i in visited.size():
		if float(visited[i].reward) >= party_power * WORTH_IT_RATIO:
			for j in i:
				location(visited[j].node_id).danger *= WORTH_IT_DISCOUNT
				combo(visited[j].key).danger *= WORTH_IT_DISCOUNT


## Nobody came back. The last spot is where they vanished; over-preparation follows.
## Earlier rooms are still reported (the group was seen entering) at lower confidence.
func report_wipe(visited: Array) -> void:
	if visited.is_empty():
		return
	var last: Dictionary = visited[visited.size() - 1]
	for b in [location(last.node_id), combo(last.key)]:
		b.danger = maxf(b.danger, float(last.danger)) * WIPE_MULT
		b.explored = true
		b.wipes += 1
	location(last.node_id).expected_key = last.key
	for i in visited.size() - 1:
		var v: Dictionary = visited[i]
		_blend(location(v.node_id), v, REPORT_RATE * 0.5)
		_blend(combo(v.key), v, REPORT_RATE * 0.5)


func _blend(b: Belief, v: Dictionary, rate: float) -> void:
	b.danger = lerpf(b.danger, float(v.danger), rate)
	b.reward = lerpf(b.reward, float(v.reward), rate)
	b.explored = true
	b.expected_key = v.key


## Called once per wave so old scares (and old grudges) do not dominate forever.
func decay() -> void:
	for dict in [locations, combos]:
		for key in dict:
			var b: Belief = dict[key]
			b.danger *= DECAY
			b.reward *= DECAY
	unpredictability *= UNPREDICTABILITY_DECAY
	surprises_this_wave = 0


func describe(node_id: String, key: String) -> String:
	return expectation(node_id, key).describe()
