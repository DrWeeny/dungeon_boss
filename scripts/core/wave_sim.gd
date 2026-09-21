class_name WaveSim
extends RefCounted

## Runs one adventurer wave through the dungeon graph.
## - At every node the party picks the next branch by weighted random choice.
## - Every room is resolved by ONE opposed roll, not simulated combat:
##       GroupPower + Roll_g   vs   RoomDangerosity + Roll_r
##   and the margin picks an outcome tier: clean win / win with losses / flee / wipe.
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
## Members lost on a win-with-losses / flee outcome.
const LOSSES_ON_WIN := 1
const LOSSES_ON_FLEE := 1

## Junction weighting.
const BASE_WEIGHT := 1.0
const EXPLORE_BONUS := 0.4        # unknown (fogged) rooms pull a little
const SECRET_DOOR_BONUS := 0.6    # secret passages pull exploration further
const DANGER_WEIGHT := 0.12       # per point of believed danger, weight down
const REWARD_WEIGHT := 0.10       # per point of believed reward, weight up
const MIN_WEIGHT := 0.05

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
	var note: String = ""

	func describe() -> String:
		var s := "%s: power %.1f+%.1f vs danger %.1f+%.1f -> margin %+.1f = %s" % [
			room_name, group_power, roll_g, danger, roll_r, margin, WaveSim.OUTCOME_NAMES[outcome]]
		if note != "":
			s += " (" + note + ")"
		return s


class WaveResult:
	var wave: int
	var party: Party
	var path: Array[String] = []
	var encounters: Array = []   # of Encounter
	var reached_boss: bool = false
	var boss_defeated: bool = false
	var bought_out: bool = false
	var boss_rounds: int = 0
	var boss_hp_lost: int = 0
	var souls: int = 0
	var magic_gained: int = 0
	var magic_spent: int = 0       # boss buy-out
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
		if reached_boss:
			return "They reached the boss and were destroyed in %d round(s), costing %d HP: %d souls. Next group will over-prepare." % [boss_rounds, boss_hp_lost, souls]
		if ended_in_wipe():
			return "Full wipe: %d souls harvested. Next group will over-prepare." % souls
		return "%d of %d escaped with %.0f loot (%d souls)." % [party.size, party.size + party.members_lost, loot_taken, souls]


var rng: RandomNumberGenerator


func _init(p_rng: RandomNumberGenerator = null) -> void:
	rng = p_rng if p_rng != null else RandomNumberGenerator.new()


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
	elif e.margin >= FLEE_MARGIN:
		e.outcome = Outcome.FLEE
	else:
		e.outcome = Outcome.WIPE
	return e


func run(graph: DungeonGraph, knowledge: AdventurerKnowledge, party: Party,
		boss: Boss, magic_available: int, wave: int) -> WaveResult:
	var res := WaveResult.new()
	res.wave = wave
	res.party = party
	res.lines.append("Wave %d: %s" % [wave, party.describe()])

	var visited: Array = []   # {key, danger, reward} in order, for the knowledge update
	var cur := graph.entry_id
	while true:
		var options := graph.next_of(cur)
		if options.is_empty():
			break
		cur = choose_branch(options, graph, knowledge)
		res.path.append(cur)
		var node := graph.node_at(cur)

		if node.kind == DungeonGraph.NodeKind.BOSS:
			res.reached_boss = true
			_boss_fight(res, party, boss, magic_available)
			visited.append({"node_id": node.id, "key": "boss", "danger": float(boss.max_hp() * 3), "reward": float(res.magic_spent)})
			break

		if node.room == null:
			continue

		var e := resolve_room(node, party, knowledge)
		res.encounters.append(e)
		visited.append({"node_id": node.id, "key": e.key, "danger": e.danger, "reward": e.reward})
		res.lines.append("  " + e.describe())

		var retreating := false
		match e.outcome:
			Outcome.CLEAN_WIN:
				party.loot += e.reward
			Outcome.WIN_WITH_LOSSES:
				party.lose_members(LOSSES_ON_WIN)
				party.loot += e.reward
			Outcome.FLEE:
				party.lose_members(LOSSES_ON_FLEE)
				res.lines.append("  The group retreats toward the surface.")
				retreating = true
			Outcome.WIPE:
				party.lose_members(party.size)
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
	else:
		knowledge.report_wipe(visited)
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
	res.lines.append("  BOSS ROOM: %s vs %s" % [boss.describe(), party.describe()])
	while party.alive and not boss.is_dead():
		res.boss_rounds += 1
		var killed := mini(prof.kills_per_round, party.size)
		party.lose_members(killed)
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
			party.lose_members(party.size)
			res.lines.append("    They cannot hurt it. The boss finishes them.")
	if boss.is_dead():
		res.boss_defeated = true
