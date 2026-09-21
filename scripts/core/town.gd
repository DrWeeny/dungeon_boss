class_name Town
extends RefCounted

## The adventurer population above the dungeon. Two flows feed it:
##   - the PULL: treasures brought home recruit new people (basic, or specialised
##     when the haul had a high-tier piece);
##   - the PUSH: kills, wipes and surprises raise `reputation`, and new recruits
##     arrive at a level that grows with it (over-preparation).
## Survivors keep their level and XP. Camped groups and bound adventurers start
## their next wave inside the dungeon.

const START_POPULATION := 8
## There is always someone willing to try: the town never drops below this many alive.
const MIN_POPULATION := 4
const PARTY_SIZE := 4
## Recruitment: one basic recruit per this many treasure tiers brought home ...
const TIERS_PER_RECRUIT := 3
## ... and a specialised (higher-level) recruit when a piece of at least this tier came back.
const SPECIAL_TIER := 3
const SPECIAL_LEVEL_BONUS := 2
## Reputation: how badly the dungeon is feared. Recruits arrive at 1 + reputation / REP_PER_LEVEL.
const REP_PER_SOUL := 1.0
const REP_PER_WIPE := 3.0
const REP_PER_SURPRISE := 1.0
const REP_PER_LEVEL := 6.0

var roster: Array[Adventurer] = []
var reputation: float = 0.0
var camps: Dictionary = {}     # stair node id -> {members: Array[Adventurer], treasures: Array[int], loot: float}
var recruits_log: Array[String] = []
var _next_id: int = 1
var rng: RandomNumberGenerator


func _init(p_rng: RandomNumberGenerator, class_bias: Dictionary = {}) -> void:
	rng = p_rng
	for i in START_POPULATION:
		recruit(1, class_bias)


# --- population -------------------------------------------------------------

func alive() -> Array[Adventurer]:
	var out: Array[Adventurer] = []
	for a in roster:
		if a.alive:
			out.append(a)
	return out


func recruit_level() -> int:
	return 1 + floori(reputation / REP_PER_LEVEL)


func recruit(level: int, class_bias: Dictionary) -> Adventurer:
	var a := Adventurer.new(_next_id, _pick_class(class_bias), maxi(level, 1))
	_next_id += 1
	roster.append(a)
	return a


func _pick_class(class_bias: Dictionary) -> String:
	var total := 0.0
	for c in Party.CLASSES:
		total += float(class_bias.get(c, 1.0))
	var r := rng.randf() * total
	for c in Party.CLASSES:
		r -= float(class_bias.get(c, 1.0))
		if r <= 0.0:
			return c
	return Party.CLASSES[Party.CLASSES.size() - 1]


## Treasures brought home by a group that made it out. Returns the recruits.
func reward_treasures(treasures: Array[int], class_bias: Dictionary) -> Array[Adventurer]:
	var out: Array[Adventurer] = []
	var tiers := 0
	var best := 0
	for t in treasures:
		tiers += t
		best = maxi(best, t)
	var basic := floori(float(tiers) / TIERS_PER_RECRUIT)
	for i in basic:
		out.append(recruit(recruit_level(), class_bias))
	if best >= SPECIAL_TIER:
		out.append(recruit(recruit_level() + SPECIAL_LEVEL_BONUS, class_bias))
	return out


func fear(souls: int, wiped: bool, surprises: int) -> void:
	reputation += souls * REP_PER_SOUL + (REP_PER_WIPE if wiped else 0.0) + surprises * REP_PER_SURPRISE


## Keep the game alive: top the town up with basic recruits when it runs thin.
func replenish(class_bias: Dictionary) -> Array[Adventurer]:
	var out: Array[Adventurer] = []
	while alive().size() < MIN_POPULATION:
		out.append(recruit(recruit_level(), class_bias))
	return out


# --- parties ----------------------------------------------------------------

## One party per non-boss floor (as many as the population allows). Camped groups
## go first and continue from their stairwell; then free adventurers, grouped by
## the teleport stair they are bound to (if any), start from there or the entrance.
func form_parties(party_count: int) -> Array[Party]:
	var parties: Array[Party] = []
	for node in camps.keys():
		var c: Dictionary = camps[node]
		var members: Array[Adventurer] = []
		for a in c.members:
			if a.alive:
				members.append(a)
		if members.is_empty():
			continue
		var p := Party.new(members, node)
		p.treasures.assign(c.treasures)
		p.loot = float(c.loot)
		p.camped_before = true
		for a in members:
			a.camp_node = ""
		parties.append(p)
	camps.clear()

	var free: Array[Adventurer] = []
	for a in alive():
		if a.camp_node == "":
			free.append(a)
	free.shuffle()
	var by_bind := {}
	for a in free:
		if not by_bind.has(a.bind_node):
			by_bind[a.bind_node] = []
		by_bind[a.bind_node].append(a)
	for bind in by_bind.keys():
		var pool: Array = by_bind[bind]
		while pool.size() > 0 and parties.size() < party_count:
			var members: Array[Adventurer] = []
			while members.size() < PARTY_SIZE and pool.size() > 0:
				members.append(pool.pop_back())
			parties.append(Party.new(members, bind))
	return parties


func camp(node: String, party: Party) -> void:
	var members: Array[Adventurer] = []
	for a in party.members:
		a.camp_node = node
		members.append(a)
	camps[node] = {"members": members, "treasures": party.treasures.duplicate(), "loot": party.loot}


func describe() -> String:
	var counts := {}
	for a in alive():
		counts[a.level] = int(counts.get(a.level, 0)) + 1
	var levels := counts.keys()
	levels.sort()
	var parts: Array[String] = []
	for l in levels:
		parts.append("%dx L%d" % [counts[l], l])
	var camped := 0
	for node in camps:
		camped += (camps[node].members as Array).size()
	return "%d adventurers (%s)%s, fear %.0f -> recruits arrive at L%d" % [
		alive().size(), ", ".join(parts), ", %d camped inside" % camped if camped > 0 else "",
		reputation, recruit_level()]
