extends Control

## Placeholder POC screen, built in code:
##   left  = resources, entrance scrying (next group), live branch odds, then every
##           floor with its rooms / slots / structural modifier tracks / build-path row
##   right = the wave log
## No art: this exists to tune the loop until it feels right.

var _status: Label
var _scry: Label
var _odds: Label
var _rooms_box: VBoxContainer
var _log: RichTextLabel
var _run_btn: Button
var _difficulty: OptionButton
var _selection: Dictionary = {}   # picker key -> OptionButton selected index


func _ready() -> void:
	_build_layout()
	GameState.changed.connect(_refresh)
	GameState.wave_finished.connect(_on_wave_finished)
	_refresh()
	_log_line("[b]Dungeon Boss POC[/b] - place contents, then run a wave. "
		+ "Killing everyone makes the next group over-prepare; letting some flee with loot keeps them coming back. "
		+ "Adventurers remember each spot: swapping a known room surprises them (more over-prep); "
		+ "building a new path does not. Treasures brought home recruit new adventurers; "
		+ "survivors level up and come back.")


# --- layout -----------------------------------------------------------------

func _build_layout() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)

	var split := HSplitContainer.new()
	split.split_offset = 760
	margin.add_child(split)

	# Left column.
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 8)
	split.add_child(left)

	_status = _label(left)
	_scry = _label(left, Color(0.95, 0.85, 0.6))
	_odds = _label(left, Color(0.75, 0.9, 0.8))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)

	_rooms_box = VBoxContainer.new()
	_rooms_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rooms_box.add_theme_constant_override("separation", 6)
	scroll.add_child(_rooms_box)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	left.add_child(buttons)

	_run_btn = Button.new()
	_run_btn.text = "Run wave"
	_run_btn.pressed.connect(_on_run_wave)
	buttons.add_child(_run_btn)

	_difficulty = OptionButton.new()
	for d in GameSession.Difficulty.values():
		_difficulty.add_item(GameSession.DIFFICULTY_NAMES[d], d)
	_difficulty.selected = GameSession.Difficulty.NORMAL
	buttons.add_child(_difficulty)

	var new_btn := Button.new()
	new_btn.text = "New game"
	new_btn.pressed.connect(_on_new_game)
	buttons.add_child(new_btn)

	# Right column: log.
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(right)

	var log_title := Label.new()
	log_title.text = "Wave log"
	right.add_child(log_title)

	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(_log)


func _label(parent: Control, color: Color = Color.WHITE) -> Label:
	var l := Label.new()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if color != Color.WHITE:
		l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l


# --- refresh ----------------------------------------------------------------

func _refresh() -> void:
	var s := GameState.session
	_status.text = s.status_line()
	_scry.text = _scry_text(s)
	_odds.text = _odds_text(s)
	_run_btn.disabled = s.game_over
	for child in _rooms_box.get_children():
		child.queue_free()
	for f in s.graph.floors:
		var header := Label.new()
		header.text = "== %s ==" % f.depth_label() + ("  (boss)" if f == s.graph.boss_floor() else "")
		header.add_theme_font_size_override("font_size", 18)
		_rooms_box.add_child(header)
		for node in s.graph.room_nodes_on(f.index):
			_rooms_box.add_child(_build_room_panel(node, s))


## Next group, as seen from the entrance (when scrying is allowed).
func _scry_text(s: GameSession) -> String:
	var fc := s.next_wave_forecast()
	var head := "Town: %d adventurers, up to %d group(s) of %d next wave" % [
		int(fc.population), int(fc.parties), Town.PARTY_SIZE]
	if not s.scrying_unlocked():
		match s.difficulty:
			GameSession.Difficulty.HARD:
				return head + ". Scrying: never on Hard."
			_:
				return head + ". Scrying: locked until boss level %d." % GameSession.SCRYING_LEVEL
	var parts: Array[String] = []
	for cls in Party.CLASSES:
		parts.append("%s %d%%" % [cls, roundi(100.0 * float(fc.classes[cls]))])
	var unp: float = s.knowledge.unpredictability
	return head + "\nScrying: " + s.town.describe() + "; new blood: " + ", ".join(parts) \
		+ ("  (unpredictability %.1f)" % unp if unp > 0.05 else "")


## Live probability of each branch at every junction, given current expectations.
func _odds_text(s: GameSession) -> String:
	var sim := WaveSim.new(s.rng)
	var parts: Array[String] = []
	for f in s.graph.floors:
		for id in f.node_ids:
			var node := s.graph.node_at(id)
			if node.next.size() < 2:
				continue
			var total := 0.0
			var ws: Array[float] = []
			for nid in node.next:
				var w := sim.branch_weight(s.graph.node_at(nid), s.knowledge)
				ws.append(w)
				total += w
			var branch_strs: Array[String] = []
			for i in node.next.size():
				branch_strs.append("%s %d%%" % [s.graph.node_at(node.next[i]).label(), roundi(100.0 * ws[i] / total)])
			parts.append("%s -> %s" % [node.label(), " / ".join(branch_strs)])
	return "Branch odds:  " + "   |   ".join(parts) + "\nBoss door: " + s.knowledge.describe_boss() \
		+ " | real threat now %d (for a group of %d)" % [s.boss.threat_level(Town.PARTY_SIZE), Town.PARTY_SIZE]


func _build_room_panel(node: DungeonGraph.DNode, s: GameSession) -> Control:
	var room := node.room
	var panel := PanelContainer.new()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)

	var exits: Array[String] = []
	for nid in node.next:
		exits.append(s.graph.node_at(nid).label())
	var camped := ""
	if s.town.camps.has(node.id):
		camped = "   CAMPED HERE: %d adventurers" % (s.town.camps[node.id].members as Array).size()
	var title := Label.new()
	title.text = "%s  [%s, %d/%d slots]  danger %.0f  reward %.0f  ->  %s\n   adventurers: %s%s" % [
		room.name, room.size_name(), room.contents.size(), room.slot_count(),
		room.danger(), room.reward(),
		", ".join(exits) if exits.size() > 0 else "dead end (they leave)",
		s.knowledge.describe(node.id, room.combo_key()), camped]
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(title)

	# Content chips (click to remove, full refund).
	var chips := HBoxContainer.new()
	box.add_child(chips)
	for i in room.contents.size():
		var c := room.contents[i]
		var chip := Button.new()
		chip.text = c.display_name + "  x"
		chip.tooltip_text = "Remove (refund %d magic). Adventurers will still expect the old room here." % c.cost
		chip.pressed.connect(func() -> void: GameState.remove_content(room, i))
		chips.add_child(chip)
	if room.free_slots() > 0:
		var picker := _make_picker(ContentLibrary.room_contents(), s, node.id + "|room")
		chips.add_child(picker)
		var add := Button.new()
		add.text = "Place"
		add.pressed.connect(func() -> void:
			var def: ContentDef = picker.get_item_metadata(picker.selected)
			if not GameState.place_content(room, def):
				_log_line("[color=orange]Cannot place %s (need %d magic, room full?)[/color]" % [def.display_name, def.cost]))
		chips.add_child(add)

	# Structural elements with their own modifier tracks.
	for si in room.structurals.size():
		var elem := room.structurals[si]
		var row := HBoxContainer.new()
		box.add_child(row)
		var lbl := Label.new()
		lbl.text = "   " + elem.describe()
		row.add_child(lbl)
		for mi in elem.modifiers.size():
			var m := elem.modifiers[mi]
			var chip := Button.new()
			chip.text = m.display_name + "  x"
			chip.pressed.connect(func() -> void: GameState.remove_modifier(elem, mi))
			row.add_child(chip)
		var mods := ContentLibrary.modifiers_for(elem.kind)
		if elem.free_slots() > 0 and mods.size() > 0:
			var picker := _make_picker(mods, s, node.id + "|" + str(si))
			row.add_child(picker)
			var add := Button.new()
			add.text = "Add modifier"
			add.pressed.connect(func() -> void:
				var def: ContentDef = picker.get_item_metadata(picker.selected)
				if not GameState.place_modifier(elem, def):
					_log_line("[color=orange]Cannot add %s (need %d magic)[/color]" % [def.display_name, def.cost]))
			row.add_child(add)
		elif elem.modifier_slots == 0:
			var hint := Label.new()
			hint.text = "(no modifier slots yet - +1 per boss level)"
			hint.modulate = Color(1, 1, 1, 0.5)
			row.add_child(hint)

	# Build a new path off this room: a fresh spot with no expectations attached.
	var build := HBoxContainer.new()
	box.add_child(build)
	var blbl := Label.new()
	blbl.text = "   New path:"
	build.add_child(blbl)
	var size_pick := OptionButton.new()
	for sz in Room.Size.values():
		size_pick.add_item("%s (%d magic)" % [Room.SIZE_NAMES[sz], s.build_cost(sz)], sz)
	size_pick.selected = int(_selection.get(node.id + "|bsize", 0))
	size_pick.item_selected.connect(func(idx: int) -> void: _selection[node.id + "|bsize"] = idx)
	build.add_child(size_pick)
	var target_pick := OptionButton.new()
	target_pick.add_item("dead end (they leave with the loot)")
	target_pick.set_item_metadata(0, "")
	var floor := s.graph.floor_of(node.id)
	if floor.exit_id != node.id:
		target_pick.add_item("-> " + s.graph.node_at(floor.exit_id).label())
		target_pick.set_item_metadata(1, floor.exit_id)
	target_pick.selected = clampi(int(_selection.get(node.id + "|btarget", 0)), 0, target_pick.item_count - 1)
	target_pick.item_selected.connect(func(idx: int) -> void: _selection[node.id + "|btarget"] = idx)
	build.add_child(target_pick)
	var bbtn := Button.new()
	bbtn.text = "Build"
	bbtn.pressed.connect(func() -> void:
		var sz: Room.Size = size_pick.get_selected_id() as Room.Size
		var to: String = target_pick.get_item_metadata(target_pick.selected)
		if not GameState.build_room(node.id, sz, to):
			_log_line("[color=orange]Cannot build (need %d magic)[/color]" % s.build_cost(sz)))
	build.add_child(bbtn)
	var targets := s.teleport_targets(node.id)
	if targets.size() > 0:
		var tp := OptionButton.new()
		for fi in targets:
			tp.add_item("Teleport stair to %s (%d magic)" % [s.graph.floors[fi].depth_label(), DungeonGraph.TELEPORT_COST], fi)
		build.add_child(tp)
		var tbtn := Button.new()
		tbtn.text = "Build teleport"
		tbtn.pressed.connect(func() -> void:
			if not GameState.build_teleport(node.id, tp.get_selected_id()):
				_log_line("[color=orange]Cannot build a teleport (need %d magic)[/color]" % DungeonGraph.TELEPORT_COST))
		build.add_child(tbtn)
	return panel


func _make_picker(defs: Array[ContentDef], s: GameSession, key: String) -> OptionButton:
	var picker := OptionButton.new()
	for i in defs.size():
		var d := defs[i]
		picker.add_item(d.short(), i)
		picker.set_item_metadata(i, d)
		picker.set_item_disabled(i, not s.can_afford(d.cost))
	picker.selected = clampi(int(_selection.get(key, 0)), 0, maxi(defs.size() - 1, 0))
	picker.item_selected.connect(func(idx: int) -> void: _selection[key] = idx)
	return picker


# --- actions ----------------------------------------------------------------

func _on_run_wave() -> void:
	GameState.run_wave()


func _on_new_game() -> void:
	_log.clear()
	_selection.clear()
	GameState.new_game(-1, _difficulty.get_selected_id() as GameSession.Difficulty)
	_log_line("[b]New game (%s).[/b]" % GameSession.DIFFICULTY_NAMES[GameState.session.difficulty])


func _on_wave_finished(results: Array) -> void:
	for res in results:
		_log_line("")
		for i in res.lines.size():
			var line: String = res.lines[i]
			if i == 0:
				_log_line("[b]%s[/b]" % line)
			elif line.begins_with("  " + res.summary()):
				var col := "red" if res.ended_in_wipe() and not res.stopped_at_gate else ("yellow" if res.boss_defeated else "lime")
				_log_line("[color=%s]%s[/color]" % [col, line])
			else:
				_log_line(line)
		_log_line("  path: " + " > ".join(res.path))
	for ev in GameState.session.events:
		_log_line("[color=aqua]%s[/color]" % ev)


func _log_line(text: String) -> void:
	_log.append_text(text + "\n")
