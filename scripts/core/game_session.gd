class_name GameSession
extends RefCounted

## One playthrough: magic, waves, boss XP, the floor stack, the town of
## adventurers and what they believe. Pure data + rules, no scene nodes, so it can
## be driven by the UI (GameState autoload) or by the headless batch simulator.

enum Difficulty { EASY, NORMAL, HARD }
const DIFFICULTY_NAMES := { Difficulty.EASY: "Easy", Difficulty.NORMAL: "Normal", Difficulty.HARD: "Hard" }
## Survivor XP multiplier per difficulty.
const XP_MULT := { Difficulty.EASY: 0.5, Difficulty.NORMAL: 1.0, Difficulty.HARD: 1.5 }

## Starting economy (placeholders).
const START_MAGIC := 18
const MAGIC_PER_WAVE := 4          # passive income: the bound soul feeds on time too
## Boss progression: souls are XP. Every level: +HP (see BossProfile), +1
## modifier slot on every structural element and +1 chest tier. Every
## FLOOR_EVERY_LEVELS levels: a new floor.
const XP_PER_LEVEL := 8
const FLOOR_EVERY_LEVELS := 2
## Scrying (seeing the next groups at the entrance) unlocks at this boss level on Normal.
const SCRYING_LEVEL := 1

var difficulty: Difficulty = Difficulty.NORMAL
var magic: int = START_MAGIC
var wave: int = 1
var souls: int = 0
var boss: Boss
var town: Town
var game_over: bool = false

var graph: DungeonGraph
var knowledge: AdventurerKnowledge
var rng: RandomNumberGenerator
var history: Array = []   # of WaveSim.WaveResult (one per party)
var events: Array[String] = []   # progression messages from the last run_wave()


func _init(p_seed: int = -1, p_difficulty: Difficulty = Difficulty.NORMAL) -> void:
	difficulty = p_difficulty
	rng = RandomNumberGenerator.new()
	if p_seed >= 0:
		rng.seed = p_seed
	else:
		rng.randomize()
	graph = DungeonGraph.build_poc_level()
	knowledge = AdventurerKnowledge.new()
	boss = Boss.new(BossProfile.lich())
	town = Town.new(rng, class_bias())


# --- Building ---------------------------------------------------------------

func can_afford(cost: int) -> bool:
	return magic >= cost


func place_content(room: Room, def: ContentDef) -> bool:
	if game_over or not can_afford(def.cost) or not room.can_place(def):
		return false
	room.place(def)
	magic -= def.cost
	return true


## Free rearrangement between waves: removing refunds the full cost.
## (Adventurers still remember what was here; see AdventurerKnowledge.)
func remove_content(room: Room, idx: int) -> bool:
	if game_over:
		return false
	var def := room.remove_at(idx)
	if def == null:
		return false
	magic += def.cost
	return true


func place_modifier(elem: StructuralElement, def: ContentDef) -> bool:
	if game_over or not can_afford(def.cost) or not elem.accepts(def):
		return false
	elem.add_modifier(def)
	magic -= def.cost
	return true


func remove_modifier(elem: StructuralElement, idx: int) -> bool:
	if game_over:
		return false
	var def := elem.remove_modifier(idx)
	if def == null:
		return false
	magic += def.cost
	return true


func build_cost(size: Room.Size) -> int:
	return DungeonGraph.BUILD_COST[size]


## Grow a new branch off an existing node: a fresh spot nobody has expectations about.
func build_room(from_id: String, size: Room.Size, to_id: String = "") -> DungeonGraph.DNode:
	var cost := build_cost(size)
	if game_over or not can_afford(cost):
		return null
	var n := graph.build_room(from_id, size, to_id)
	magic -= cost
	return n


## A teleport stair down to a deeper floor; groups using it are bound to it.
func build_teleport(from_id: String, target_floor: int) -> DungeonGraph.DNode:
	if game_over or not can_afford(DungeonGraph.TELEPORT_COST):
		return null
	var n := graph.build_teleport(from_id, target_floor)
	magic -= DungeonGraph.TELEPORT_COST
	return n


## Floors a teleport from `from_id` may drop to (deeper, not the boss floor).
func teleport_targets(from_id: String) -> Array[int]:
	var out: Array[int] = []
	var from := graph.node_at(from_id)
	for i in range(from.floor + 1, graph.floors.size() - 1):
		out.append(i)
	return out


# --- Intel ------------------------------------------------------------------

## Easy: always. Normal: once the boss reaches SCRYING_LEVEL. Hard: never.
func scrying_unlocked() -> bool:
	match difficulty:
		Difficulty.EASY:
			return true
		Difficulty.NORMAL:
			return boss.level >= SCRYING_LEVEL
	return false


## Which adventurer classes the dungeon's monsters lure in: mean attraction over
## all placed monsters/traps, per class. Drives the class of new recruits.
func class_bias() -> Dictionary:
	var bias := {}
	for cls in Party.CLASSES:
		var total := 0.0
		var n := 0
		for room in graph.rooms():
			for c in room.contents:
				if c.category == ContentDef.Category.MONSTER or c.category == ContentDef.Category.TRAP:
					total += float(c.attraction.get(cls, 1.0))
					n += 1
		bias[cls] = total / n if n > 0 else 1.0
	return bias


## How many groups set out next wave: one per non-boss floor, population permitting.
func party_count() -> int:
	return graph.floors.size() - 1


## The "next adventurers" view at the entrance: {parties: int, classes: {cls: share},
## population: int, min_level, max_level}.
func next_wave_forecast() -> Dictionary:
	var bias := class_bias()
	var total := 0.0
	for cls in bias:
		total += float(bias[cls])
	var shares := {}
	for cls in bias:
		shares[cls] = float(bias[cls]) / total
	var lo := 99
	var hi := 0
	for a in town.alive():
		lo = mini(lo, a.level)
		hi = maxi(hi, a.level)
	return {"parties": party_count(), "classes": shares, "population": town.alive().size(),
		"min_level": lo, "max_level": hi}


# --- Waves ------------------------------------------------------------------

## Runs every party of the wave in turn. Returns their results.
func run_wave() -> Array:
	assert(not game_over, "run_wave after game over")
	events.clear()
	var bias := class_bias()
	town.replenish(bias)
	var parties := town.form_parties(party_count())
	var results: Array = []
	var xp_mult: float = XP_MULT[difficulty]
	for party in parties:
		if game_over:
			break
		var sim := WaveSim.new(rng)
		var res := sim.run(graph, knowledge, party, boss, magic, wave, xp_mult)
		history.append(res)
		results.append(res)
		_settle(res, bias)
	_apply_boss_levels()
	boss.regen()
	knowledge.decay()
	wave += 1
	return results


## Harvest, recruit and frighten after one party's run.
func _settle(res: WaveSim.WaveResult, bias: Dictionary) -> void:
	var party := res.party
	magic += res.magic_gained + MAGIC_PER_WAVE - res.magic_spent
	souls += res.souls
	town.fear(res.souls, res.ended_in_wipe() and not res.stopped_at_gate, res.surprises)

	var dungeon_kills := res.souls - res.boss_kills
	if dungeon_army_active() and dungeon_kills > 0:
		boss.add_shield(dungeon_kills * boss.profile.shield_per_kill)
		events.append("%d dungeon dead rise to join the army (shield %d)." % [dungeon_kills, boss.shield])

	if res.camped_at != "":
		town.camp(res.camped_at, party)
	elif party.alive and party.treasures.size() > 0:
		var recruits := town.reward_treasures(party.treasures, bias)
		if recruits.size() > 0:
			var names: Array[String] = []
			for a in recruits:
				names.append(a.describe())
			events.append("Word of the loot spreads: %s join the town." % ", ".join(names))

	if res.boss_defeated:
		game_over = true


## Late-game lich power-up: the dungeon's own dead join the shield.
func dungeon_army_active() -> bool:
	var lvl := boss.profile.dungeon_army_level
	return lvl >= 0 and boss.level >= lvl


func _apply_boss_levels() -> void:
	var target := floori(float(souls) / XP_PER_LEVEL)
	while boss.level < target:
		boss.level_up()
		for room in graph.rooms():
			for s in room.structurals:
				s.upgrade_slots()
				if s.kind == StructuralElement.Kind.CHEST:
					s.tier += 1
		events.append("Boss level %d: +%d HP, +1 modifier slot everywhere, chests +1 tier." % [boss.level, boss.profile.hp_per_level])
		if boss.level == SCRYING_LEVEL and difficulty == Difficulty.NORMAL:
			events.append("Scrying unlocked: the entrance now shows the next groups.")
		if boss.level == boss.profile.dungeon_army_level:
			events.append("Power-up: from now on everyone who dies in the dungeon rises to guard the boss.")
		if boss.level % FLOOR_EVERY_LEVELS == 0:
			var f := graph.insert_floor(boss.level)
			events.append("The dungeon grows: %s inserted above the boss. One more group per wave." % f.depth_label())


func status_line() -> String:
	return "Wave %d | Magic %d | Souls %d (%d/%d xp) | %s | %s | up to %d group(s) next wave" % [
		wave, magic, souls, souls - boss.level * XP_PER_LEVEL, XP_PER_LEVEL, boss.describe(),
		DIFFICULTY_NAMES[difficulty], party_count()]
