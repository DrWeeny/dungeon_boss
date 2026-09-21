class_name WaveSim
extends RefCounted

## Runs one adventurer wave through the dungeon graph.
## - At every node the party picks the next branch by weighted random choice.
## - Every room is resolved by ONE opposed roll, not simulated combat:
##       GroupPower + Roll_g   vs   RoomDangerosity + Roll_r
##   and the margin picks an outcome tier: clean win / win with losses / flee / wipe.
##   Losses are decimal (member-equivalents): see Party.apply_damage.
## - At the boss door the party decides whether to go in, from what it believes
##   the boss is; inside, it discovers the real threat and may still turn back.
## - The boss fight is a round loop driven by BossProfile numbers.
## - Afterwards, survivors (or the wipe) update AdventurerKnowledge.
## All thresholds are POC placeholders; tune them here.

enum Outcome { CLEAN_WIN, WIN_WITH_LOSSES, FLEE, WIPE }
const OUTCOME_NAMES := {
	Outcome.CLEAN_WIN: "clean win", Outcome.WIN_WITH_LOSSES: "win with losses",
	Outcome.FLEE: "flee", Outcome.WIPE: "WIPE",
}

## Each side rolls uniformly in [0, ROLL_MAX].
const ROLL_MAX := 6.0
## Margin thresholds (group side minus room side).
const CLEAN_MARGIN := 4.0     # margin >= this            -> clean win
                              # 0 <= margin < CLEAN       -> win with losses
const FLEE_MARGIN := -4.0     # FLEE <= margin < 0        -> flee (they saw it coming)
                              # margin < FLEE             -> wipe
## Damage on a win-with-losses scales from ~0 (just under clean) to this at margin 0,
## in member-equivalents; a flee costs a flat amount on the way out.
const DAMAGE_AT_ZERO_MARGIN := 1.0
const DAMAGE_ON_FLEE := 1.0

## Junction weighting.
const BASE_WEIGHT := 1.0
const EXPLORE_BONUS := 0.4        # unknown (fogged) rooms pull a little
const SECRET_DOOR_BONUS := 0.6    # secret passages pull exploration further
const DANGER_WEIGHT := 0.12       # per point of believed danger, weight down
const REWARD_WEIGHT := 0.10       # per point of believed reward, weight up
const MIN_WEIGHT := 0.05

## Boss door: chance to go in by group level vs believed boss threat level ...
const APPROACH_HIGHER := 0.85
const APPROACH_EQUAL := 0.50
const APPROACH_LOWER := 0.25
## ... lowered by how satisfied they already are with their loot (0..1 of a target
## of LOOT_TARGET_PER_LEVEL x total party levels) and by wounds.
const LOOT_DETERRENT := 0.40
const LOOT_TARGET_PER_LEVEL := 1.5
const WOUND_DETERRENT := 0.15
const MIN_APPROACH := 0.05
## Before anyone has seen the boss, they judge it by the rooms they crossed:
## believed boss threat = average room danger x this (a boss is worse than a room).
const UNSEEN_BOSS_FACTOR := 1.5

## Souls and magic harvested per adventurer that dies in the dungeon.
const MAGIC_PER_SOUL := 3


class Encounter:
	var node_id: String
	var room_name: String
	var key: String
	var danger: float
	var reward: float
	var group_power: float
	var roll_g: float
	var roll_r: float
	var margin: float
	var outcome: WaveSim.Outcome
	var damage: float = 0.0
	var kills: int = 0
	var note: String = ""

	func describe() -> String:
		var s := "%s: power %.1f+%.1f vs danger %.1f+%.1f -> margin %+.1f = %s" % [
			room_name, group_power, roll_g, danger, roll_r, margin, WaveSim.OUTCOME_NAMES[outcome]]
		if damage > 0.0:
			s += " [%.1f dmg, %d dead]" % [damage, kills]
		if note != "":
			s += " (" + note + ")"
		return s


class WaveResult:
	var wave: int
	var party: Party
	var path: Array[String] = []
	var encounters: Array = []   # of Encounter
	var reached_boss_door: bool = false
	var reached_boss: bool = false
	var turned_back: bool = false   # at the door or after seeing the boss
	var boss_defeated: bool = false
	var bought_out: bool = false
	var boss_rounds: int = 0
	var boss_hp_lost: int = 0
	var boss_kills: int = 0         # adventurers killed in the boss room
	var souls: int = 0
	var magic_gained: int = 0
	var magic_spent: int = 0        # boss buy-out
	var loot_taken: float = 0.0
	var surprises: int = 0
	var lines: Array[String] = []

	func ended_in_wipe() -> bool:
		return not party.alive

	func summary() -> String:
		if boss_defeated:
			return "The boss has fallen after %d round(s). Game over." % boss_rounds
		if bought_out:
			return "The boss bought them off for %d magic; %d walk away (%d souls)." % [magic_spent, party.size, souls]
		if reached_boss and ended_in_wipe():
			return "They reached the boss and were destroyed in %d round(s), costing %d HP: %d souls. Next group will over-prepare." % [boss_rounds, boss_hp_lost, souls]
		if turned_back:
			return "%d turned back from the boss with %.0f loot (%d souls)%s." % [party.size, loot_taken, souls,
				" and will report what they saw" if reached_boss else ""]
		if ended_in_wipe():
			return "Full wipe: %d souls harvested. Next group will over-prepare." % souls
		return "%d of %d escaped with %.0f loot (%d souls)." % [party.size, party.size + party.members_lost, loot_taken, souls]


var rng: RandomNumberGenerator


func _init(p_rng: RandomNumberGenerator = null) -> void:
	rng = p_rng if p_rng != null else RandomNumberGenerator.new()


# --- junctions --------------------------------------------------------------

## Weight of stepping into `node` for a party that believes `knowledge`.
func branch_weight(node: DungeonGraph.DNode, knowledge: AdventurerKnowledge) -> float:
	var w := BASE_WEIGHT
	if node.room != null:
		var x := knowledge.expectation(node.id, node.room.combo_key())
		if not x.explored:
			w += EXPLORE_BONUS
		else:
			w -= DANGER_WEIGHT * x.danger
			w += REWARD_WEIGHT * x.reward
			if x.source == "reputation":
				w += EXPLORE_BONUS * 0.5   # never been *here*, only heard of it
		if node.room.has_secret_door():
			w += SECRET_DOOR_BONUS
	return maxf(w, MIN_WEIGHT)


func choose_branch(options: Array[String], graph: DungeonGraph, knowledge: AdventurerKnowledge) -> String:
	if options.size() == 1:
		return options[0]
	var weights: Array[float] = []
	var total := 0.0
	for id in options:
		var w := branch_weight(graph.node_at(id), knowledge)
		weights.append(w)
		total += w
	var r := rng.randf() * total
	for i in options.size():
		r -= weights[i]
		if r <= 0.0:
			return options[i]
	return options[options.size() - 1]


# --- boss door --------------------------------------------------------------

## How satisfied the group is with its loot, 0..1.
func loot_satisfaction(party: Party) -> float:
	var target := LOOT_TARGET_PER_LEVEL * maxf(float(party.levels_alive()), 1.0)
	return clampf(party.loot / target, 0.0, 1.0)


## Chance the group pushes on toward a boss it believes has `threat` level.
func approach_probability(party: Party, threat: float) -> float:
	var lvl := party.avg_level()
	var base: float
	if lvl > threat + 0.5:
		base = APPROACH_HIGHER
	elif lvl < threat - 0.5:
		base = APPROACH_LOWER
	else:
		base = APPROACH_EQUAL
	var p := base - LOOT_DETERRENT * loot_satisfaction(party) - WOUND_DETERRENT * party.wounds
	return clampf(p, MIN_APPROACH, 1.0)


## What they think the boss is before anyone has come back from it.
func believed_boss_threat(knowledge: AdventurerKnowledge, encounters: Array) -> float:
	if knowledge.boss_known:
		return knowledge.boss_threat
	if encounters.is_empty():
		return 0.0
	var total := 0.0
	for e in encounters:
		total += e.danger
	return total / encounters.size() * UNSEEN_BOSS_FACTOR


# --- rooms ------------------------------------------------------------------

func resolve_room(node: DungeonGraph.DNode, party: Party, knowledge: AdventurerKnowledge) -> Encounter:
	var room := node.room
	var e := Encounter.new()
	e.node_id = node.id
	e.room_name = room.name
	e.key = room.combo_key()
	e.danger = room.danger()
	e.reward = room.reward()
	if knowledge.check_surprise(node.id, e.key):
		e.note = "SURPRISE: not the room they expected"
	# Sarcophagus gamble is rolled fresh every visit.
	for s in room.structurals:
		if s.kind == StructuralElement.Kind.SARCOPHAGUS:
			var g := s.roll_gamble(rng)
			e.danger += float(g.danger)
			e.reward += float(g.reward)
			e.note = (e.note + "; " if e.note != "" else "") + str(g.text)
	e.group_power = party.power()
	e.roll_g = rng.randf_range(0.0, ROLL_MAX)
	e.roll_r = rng.randf_range(0.0, ROLL_MAX)
	e.margin = (e.group_power + e.roll_g) - (e.danger + e.roll_r)
	if e.margin >= CLEAN_MARGIN:
		e.outcome = Outcome.CLEAN_WIN
	elif e.margin >= 0.0:
		e.outcome = Outcome.WIN_WITH_LOSSES
		e.damage = DAMAGE_AT_ZERO_MARGIN * (CLEAN_MARGIN - e.margin) / CLEAN_MARGIN
	elif e.margin >= FLEE_MARGIN:
		e.outcome = Outcome.FLEE
		e.damage = DAMAGE_ON_FLEE
	else:
		e.outcome = Outcome.WIPE
	return e


# --- the wave ---------------------------------------------------------------

func run(graph: DungeonGraph, knowledge: AdventurerKnowledge, party: Party,
		boss: Boss, magic_available: int, wave: int) -> WaveResult:
	var res := WaveResult.new()
	res.wave = wave
	res.party = party
	res.lines.append("Wave %d: %s" % [wave, party.describe()])

	var visited: Array = []   # {node_id, key, danger, reward} in order, for the knowledge update
	var cur := graph.entry_id
	while true:
		var options := graph.next_of(cur)
		if options.is_empty():
			break
		cur = choose_branch(options, graph, knowledge)
		var node := graph.node_at(cur)

		if node.kind == DungeonGraph.NodeKind.BOSS:
			res.reached_boss_door = true
			var believed := believed_boss_threat(knowledge, res.encounters)
			var p := approach_probability(party, believed)
			res.lines.append("  Boss door: they believe threat ~%.1f vs their lvl %.1f, loot %.0f -> %d%% to go in" % [
				believed, party.avg_level(), party.loot, roundi(p * 100.0)])
			if rng.randf() >= p:
				res.turned_back = true
				res.lines.append("  They turn back at the door.")
				break
			res.path.append(cur)
			res.reached_boss = true
			# Inside: the real thing.
			var real := float(boss.threat_level(party.size))
			var p2 := approach_probability(party, real)
			res.lines.append("  They see the boss: real threat %.1f (%s) -> %d%% to fight" % [real, boss.describe(), roundi(p2 * 100.0)])
			if rng.randf() >= p2:
				res.turned_back = true
				res.lines.append("  They run for it.")
				break
			_boss_fight(res, party, boss, magic_available)
			visited.append({"node_id": node.id, "key": "boss", "danger": real * 3.0, "reward": float(res.magic_spent)})
			break

		res.path.append(cur)
		if node.room == null:
			continue

		var e := resolve_room(node, party, knowledge)
		res.encounters.append(e)
		visited.append({"node_id": node.id, "key": e.key, "danger": e.danger, "reward": e.reward})

		var retreating := false
		match e.outcome:
			Outcome.CLEAN_WIN:
				party.loot += e.reward
				party.heal(node.room.heal())
			Outcome.WIN_WITH_LOSSES:
				e.kills = party.apply_damage(e.damage)
				party.loot += e.reward
				party.heal(node.room.heal())
			Outcome.FLEE:
				e.kills = party.apply_damage(e.damage)
				retreating = true
			Outcome.WIPE:
				e.kills = party.size
				party.lose_members(party.size)
		res.lines.append("  " + e.describe())
		if retreating:
			res.lines.append("  The group retreats toward the surface.")
		if retreating or not party.alive:
			break

	# Harvest.
	res.surprises = knowledge.surprises_this_wave
	res.souls = party.members_lost
	res.magic_gained = res.souls * MAGIC_PER_SOUL
	res.loot_taken = party.loot + res.magic_spent if party.alive else 0.0

	# Update what the next groups will believe.
	if party.alive:
		knowledge.report_survivors(visited, party.power())
		if res.reached_boss:
			knowledge.report_boss(float(boss.threat_level(party.size + party.members_lost)), AdventurerKnowledge.REPORT_RATE)
	else:
		knowledge.report_wipe(visited)
		if res.reached_boss:
			knowledge.report_boss(float(boss.threat_level(party.size + party.members_lost)), AdventurerKnowledge.RUMOUR_RATE)
	res.lines.append("  " + res.summary())
	if res.surprises > 0:
		res.lines.append("  %d surprise(s): word spreads that this dungeon is unpredictable (+over-prep)." % res.surprises)
	return res


## Round loop shared by every boss; BossProfile supplies the numbers.
## Each round: the boss strikes first (kills the weakest), then the survivors
## deal (highest level alive - combat skill) HP. A boss that can buy out does so
## the moment a round would kill it, if it can pay.
func _boss_fight(res: WaveResult, party: Party, boss: Boss, magic_available: int) -> void:
	var prof := boss.profile
	res.lines.append("  BOSS FIGHT: %s vs %s" % [boss.describe(), party.describe()])
	while party.alive and not boss.is_dead():
		res.boss_rounds += 1
		var killed := mini(prof.kills_per_round, party.size)
		party.lose_members(killed)
		res.boss_kills += killed
		boss.add_shield(killed * prof.shield_per_kill)
		if not party.alive:
			res.lines.append("    round %d: the boss strikes, nobody is left standing." % res.boss_rounds)
			break
		var dmg := maxi(0, party.max_level_alive() - prof.combat_skill)
		if dmg >= boss.hp + boss.shield and prof.buyout_per_level > 0:
			var price := party.levels_alive() * prof.buyout_per_level
			if magic_available - res.magic_spent >= price:
				res.magic_spent += price
				res.bought_out = true
				res.lines.append("    round %d: the boss buys them off for %d magic." % [res.boss_rounds, price])
				return
		var lost := boss.take_damage(dmg)
		res.boss_hp_lost += int(lost.hp)
		res.lines.append("    round %d: boss kills %d (%d left)%s; %d damage -> %s." % [
			res.boss_rounds, killed, party.size,
			", raises %d zombie(s)" % (killed * prof.shield_per_kill) if prof.shield_per_kill > 0 else "",
			dmg, boss.describe()])
		if dmg == 0:
			# Nobody left can scratch it; the boss finishes the rest.
			res.boss_kills += party.size
			party.lose_members(party.size)
			res.lines.append("    They cannot hurt it. The boss finishes them.")
	if boss.is_dead():
		res.boss_defeated = true
