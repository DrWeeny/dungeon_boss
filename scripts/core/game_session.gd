class_name GameSession
extends RefCounted

## One playthrough: magic, waves, boss XP, the floor stack and adventurer knowledge.
## Pure data + rules, no scene nodes, so it can be driven by the UI (GameState
## autoload) or by the headless batch simulator (scripts/tools/sim_batch.gd).

enum Difficulty { EASY, NORMAL, HARD }
const DIFFICULTY_NAMES := { Difficulty.EASY: "Easy", Difficulty.NORMAL: "Normal", Difficulty.HARD: "Hard" }

## Starting economy (placeholders).
const START_MAGIC := 18
const MAGIC_PER_WAVE := 4          # passive income: the bound soul feeds on time too
## Wave scaling.
const START_PARTY_POWER := 0.0
const PARTY_POWER_PER_WAVE := 0.8
const PARTY_SIZE := 4
## The next group over-prepares after a full wipe (on top of normal scaling).
const WIPE_OVERPREP_BONUS := 2.0
## ... and when the dungeon keeps surprising them (per point of unpredictability).
const UNPREDICTABILITY_POWER := 1.0
## Boss progression: souls are XP. Every level: +HP (see BossProfile), +1
## modifier slot on every structural element and +1 chest tier. Every
## FLOOR_EVERY_LEVELS levels: a new floor.
const XP_PER_LEVEL := 8
const FLOOR_EVERY_LEVELS := 2
## Scrying (seeing the next group at the entrance) unlocks at this boss level on Normal.
const SCRYING_LEVEL := 1

var difficulty: Difficulty = Difficulty.NORMAL
var magic: int = START_MAGIC
var wave: int = 1
var souls: int = 0
var boss: Boss
var party_power: float = START_PARTY_POWER
var last_wave_wiped: bool = false
var game_over: bool = false

var graph: DungeonGraph
var knowledge: AdventurerKnowledge
var rng: RandomNumberGenerator
var history: Array = []   # of WaveSim.WaveResult
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
## all placed monsters/traps, per class.
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


func next_party_power() -> float:
	return party_power + Party.POWER_PER_MEMBER * PARTY_SIZE \
		+ UNPREDICTABILITY_POWER * knowledge.unpredictability


## The "next adventurers repartition" shown at the entrance when scrying is unlocked:
## {power: float, classes: {cls: share 0..1}}.
func next_party_forecast() -> Dictionary:
	var bias := class_bias()
	var total := 0.0
	for cls in bias:
		total += float(bias[cls])
	var shares := {}
	for cls in bias:
		shares[cls] = float(bias[cls]) / total
	return {"power": next_party_power(), "classes": shares}


# --- Waves ------------------------------------------------------------------

func run_wave() -> WaveSim.WaveResult:
	assert(not game_over, "run_wave after game over")
	events.clear()
	var party := Party.spawn(wave, party_power + UNPREDICTABILITY_POWER * knowledge.unpredictability,
		PARTY_SIZE, rng, class_bias())
	var sim := WaveSim.new(rng)
	var res := sim.run(graph, knowledge, party, boss, magic, wave)
	history.append(res)

	# Harvest and grow.
	magic += res.magic_gained + MAGIC_PER_WAVE - res.magic_spent
	souls += res.souls
	_apply_boss_levels()
	boss.regen()

	# Next wave spawns stronger; a full wipe makes them over-prepare.
	last_wave_wiped = res.ended_in_wipe()
	party_power += PARTY_POWER_PER_WAVE
	if last_wave_wiped:
		party_power += WIPE_OVERPREP_BONUS
	knowledge.decay()

	if res.boss_defeated:
		game_over = true
	wave += 1
	return res


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
			events.append("Scrying unlocked: the entrance now shows the next group.")
		if boss.level % FLOOR_EVERY_LEVELS == 0:
			var f := graph.insert_floor(boss.level)
			events.append("The dungeon grows: %s inserted above the boss." % f.depth_label())


func status_line() -> String:
	return "Wave %d | Magic %d | Souls %d (%d/%d xp) | %s | %s | Next party power ~%.1f%s" % [
		wave, magic, souls, souls - boss.level * XP_PER_LEVEL, XP_PER_LEVEL, boss.describe(),
		DIFFICULTY_NAMES[difficulty], next_party_power(),
		" (over-prepared)" if last_wave_wiped else ""]
