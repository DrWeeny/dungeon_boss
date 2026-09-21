extends SceneTree

## Headless tuning harness. Runs many games with a few fixed "player strategies"
## and prints how long the boss survives, how many souls it harvests and how often
## wipes happen. Use it to see whether the core tension actually exists with the
## current placeholder numbers before touching the UI.
##
##   godot --headless -s scripts/tools/sim_batch.gd
##   godot --headless -s scripts/tools/sim_batch.gd -- runs=500 waves=20 seed=7

const DEFAULT_RUNS := 200
const DEFAULT_MAX_WAVES := 15


func _init() -> void:
	var args := _parse_args()
	var runs: int = int(args.get("runs", DEFAULT_RUNS))
	var max_waves: int = int(args.get("waves", DEFAULT_MAX_WAVES))
	var base_seed: int = int(args.get("seed", 1))

	print("Dungeon Boss batch sim: %d runs x up to %d waves" % [runs, max_waves])
	print("")
	for strat in ["empty", "greedy_kill", "bait", "balanced", "swapper", "builder"]:
		_report(strat, runs, max_waves, base_seed)
	quit()


func _parse_args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			out[kv[0]] = kv[1]
	return out


## A strategy places contents once at the start (and again whenever it can afford
## to) according to a simple policy. Returns nothing; mutates the session.
func _apply_strategy(s: GameSession, strat: String) -> void:
	var rooms := s.graph.rooms()
	match strat:
		"swapper":
			# Balanced start, then every 3rd wave swap the hall and ossuary contents
			# to surprise the adventurers (the thing the design says NOT to do).
			if s.wave == 1:
				_apply_strategy(s, "balanced")
			elif s.wave % 3 == 0:
				var hall := s.graph.node_at("hall").room
				var ossuary := s.graph.node_at("ossuary").room
				var a: Array[ContentDef] = hall.contents.duplicate()
				var b: Array[ContentDef] = ossuary.contents.duplicate()
				while hall.contents.size() > 0:
					s.remove_content(hall, 0)
				while ossuary.contents.size() > 0:
					s.remove_content(ossuary, 0)
				for d in b:
					s.place_content(hall, d)
				for d in a:
					s.place_content(ossuary, d)
		"builder":
			# Balanced start, then spend spare magic on dead-end reward annexes off
			# the hall (fresh spots, no expectations, bait that lets groups leave).
			if s.wave == 1:
				_apply_strategy(s, "balanced")
			elif s.magic >= s.build_cost(Room.Size.SMALL) + 2:
				var n := s.build_room("hall", Room.Size.SMALL, "")
				if n != null:
					s.place_content(n.room, ContentLibrary.get_def("coins"))
		"empty":
			pass
		"greedy_kill":
			# Fill every slot with the deadliest monster affordable, front to back.
			for room in rooms:
				while room.free_slots() > 0:
					var placed := false
					for id in ["banshee", "mummy", "ghoul", "ghost", "undead", "skeleton"]:
						if s.place_content(room, ContentLibrary.get_def(id)):
							placed = true
							break
					if not placed:
						return
		"bait":
			# Rewards everywhere, one cheap monster at the deepest room.
			for room in rooms:
				if room.free_slots() > 0:
					s.place_content(room, ContentLibrary.get_def("coins"))
			var vault := s.graph.node_at("vault").room
			s.place_content(vault, ContentLibrary.get_def("skeleton"))
		"balanced":
			# Moderate danger up front, reward mid-path, healing bait, heavy near stairs.
			var hall := s.graph.node_at("hall").room
			var ossuary := s.graph.node_at("ossuary").room
			var vault := s.graph.node_at("vault").room
			var shrine := s.graph.node_at("shrine").room
			var stairs := s.graph.node_at("stairs").room
			s.place_content(hall, ContentLibrary.get_def("skeleton"))
			s.place_content(hall, ContentLibrary.get_def("coins"))
			s.place_content(ossuary, ContentLibrary.get_def("pit"))
			s.place_content(ossuary, ContentLibrary.get_def("skeleton"))
			s.place_content(shrine, ContentLibrary.get_def("healing"))
			s.place_content(vault, ContentLibrary.get_def("ghoul"))
			s.place_content(stairs, ContentLibrary.get_def("mummy"))


func _report(strat: String, runs: int, max_waves: int, base_seed: int) -> void:
	var waves_survived := 0
	var boss_deaths := 0
	var total_souls := 0
	var total_wipes := 0
	var total_flees := 0
	var total_waves := 0
	var total_levels := 0
	var total_floors := 0
	var total_pop := 0
	var total_maxlvl := 0
	for r in runs:
		var s := GameSession.new(base_seed * 100000 + r)
		_apply_strategy(s, strat)
		while not s.game_over and s.wave <= max_waves:
			# Re-invest each wave with the same policy (cheap approximation of a player).
			_apply_strategy(s, strat)
			for res in s.run_wave():
				total_waves += 1
				if res.ended_in_wipe() and not res.stopped_at_gate:
					total_wipes += 1
				elif not res.reached_boss:
					total_flees += 1
		waves_survived += s.wave - 1
		total_souls += s.souls
		total_levels += s.boss.level
		total_floors += s.graph.floors.size()
		total_pop += s.town.alive().size()
		for a in s.town.alive():
			total_maxlvl = maxi(total_maxlvl, a.level)
		if s.game_over:
			boss_deaths += 1
	print("strategy=%-12s boss killed %3d%% | avg waves %5.1f | souls %5.1f | boss lvl %3.1f | floors %3.1f | town %4.1f (max L%d) | wipes %3d%% | escapes %3d%% of groups" % [
		strat, roundi(100.0 * boss_deaths / runs), float(waves_survived) / runs,
		float(total_souls) / runs, float(total_levels) / runs, float(total_floors) / runs,
		float(total_pop) / runs, total_maxlvl,
		roundi(100.0 * total_wipes / maxi(total_waves, 1)),
		roundi(100.0 * total_flees / maxi(total_waves, 1))])
