class_name ContentLibrary
extends RefCounted

## The lich content palette (first boss). Static lookup, built once.
## Undead theme keeps the asset needs minimal; the roster spans weak-but-numerous
## (skeleton) to dangerous single unit (banshee) for testing the dangerosity curve.


static var _defs: Dictionary = {}          # id -> ContentDef
static var _order: Array[String] = []      # stable display order


static func _ensure() -> void:
	if not _defs.is_empty():
		return
	var list: Array[ContentDef] = [
		# --- Monsters ---------------------------------------------------- danger reward cost attraction
		ContentDef.make("skeleton", "Skeleton", ContentDef.Category.MONSTER,  2.0, 0.0, 2, {"priest": 1.5}),
		ContentDef.make("undead",   "Undead",   ContentDef.Category.MONSTER,  3.0, 0.0, 3, {"priest": 1.2, "warrior": 1.2}),
		ContentDef.make("ghost",    "Ghost",    ContentDef.Category.MONSTER,  4.0, 0.0, 4, {"mage": 1.3, "priest": 1.2}),
		ContentDef.make("ghoul",    "Ghoul",    ContentDef.Category.MONSTER,  4.0, 0.0, 4, {"warrior": 1.3}),
		ContentDef.make("mummy",    "Mummy",    ContentDef.Category.MONSTER,  5.0, 0.0, 5, {"mage": 1.5}),
		ContentDef.make("banshee",  "Banshee",  ContentDef.Category.MONSTER,  7.0, 0.0, 8, {"priest": 1.3, "mage": 1.2}),
		# --- Traps ---------------------------------------------------------
		ContentDef.make("curse",        "Curse trap",    ContentDef.Category.TRAP, 2.0, 0.0, 2, {"priest": 1.2}),
		ContentDef.make("pit",          "Pit",           ContentDef.Category.TRAP, 3.0, 0.0, 2, {"rogue": 1.3}),
		ContentDef.make("poison_gas",   "Poisonous gas", ContentDef.Category.TRAP, 4.0, 0.0, 4),
		ContentDef.make("movable_wall", "Movable wall",  ContentDef.Category.TRAP, 2.0, 0.0, 3, {"rogue": 1.2}),
		# --- Rewards -------------------------------------------------------
		ContentDef.make("coins",    "Coin pile",      ContentDef.Category.REWARD, 0.0, 3.0,  2),
		ContentDef.make("treasure", "Treasure",       ContentDef.Category.REWARD, 0.0, 6.0,  4),
		ContentDef.make("relic",    "Cursed relic",   ContentDef.Category.REWARD, 1.0, 10.0, 7),
		# --- Decoration (no stats; flavour for later aesthetics) -----------
		ContentDef.make("bones",   "Bone pile", ContentDef.Category.DECORATION, 0.0, 0.0, 1),
		ContentDef.make("candles", "Candles",   ContentDef.Category.DECORATION, 0.0, 0.0, 1),
		# --- Specials (bait: make the dungeon feel survivable) -------------
		ContentDef.make("healing", "Source of healing", ContentDef.Category.SPECIAL, -2.0, 2.0, 3),
		ContentDef.make("rest",    "Rest zone / tents", ContentDef.Category.SPECIAL, -1.0, 1.0, 3),
		# --- Structural modifiers (door trap track, chest extra slots) -----
		ContentDef.make("mod_secret",  "Secret door",    ContentDef.Category.MODIFIER, 0.0, 0.0, 3),
		ContentDef.make("mod_enigma2", "Enigma door L2", ContentDef.Category.MODIFIER, 0.0, 0.0, 3),
		ContentDef.make("mod_enigma3", "Enigma door L3", ContentDef.Category.MODIFIER, 0.0, 0.0, 5),
		ContentDef.make("mod_lethal",  "Lethal door",    ContentDef.Category.MODIFIER, 3.0, 0.0, 5),
		ContentDef.make("mod_gold",    "Extra gold",     ContentDef.Category.MODIFIER, 0.0, 4.0, 3),
		ContentDef.make("mod_needle",  "Needle trap",    ContentDef.Category.MODIFIER, 2.0, 0.0, 2),
		# --- Stair modifiers (the stair slot track) ------------------------
		ContentDef.make("mod_rest",     "Rest area",     ContentDef.Category.MODIFIER, 0.0, 0.0, 4),
		ContentDef.make("mod_teleport", "Teleport bind", ContentDef.Category.MODIFIER, 0.0, 0.0, 6),
	]
	# Which structural kinds accept which modifier (StructuralElement.Kind values).
	var door := StructuralElement.Kind.DOOR
	var chest := StructuralElement.Kind.CHEST
	var stair := StructuralElement.Kind.STAIR
	var mod_targets := {
		"mod_secret": [door], "mod_enigma2": [door], "mod_enigma3": [door], "mod_lethal": [door],
		"mod_gold": [chest], "mod_needle": [chest, door],
		"mod_rest": [stair], "mod_teleport": [stair],
	}
	var heals := {"healing": 0.6, "rest": 0.4}
	var tiers := {"coins": 1, "treasure": 2, "relic": 3, "mod_gold": 1}
	var gates := {"mod_enigma2": 2, "mod_enigma3": 3}
	for d in list:
		if heals.has(d.id):
			d.heal = float(heals[d.id])
		if tiers.has(d.id):
			d.tier = int(tiers[d.id])
		if gates.has(d.id):
			d.min_level = int(gates[d.id])
		if mod_targets.has(d.id):
			var arr: Array[int] = []
			arr.assign(mod_targets[d.id])
			d.modifier_for = arr
		_defs[d.id] = d
		_order.append(d.id)


static func get_def(id: String) -> ContentDef:
	_ensure()
	return _defs.get(id)


static func all() -> Array[ContentDef]:
	_ensure()
	var out: Array[ContentDef] = []
	for id in _order:
		out.append(_defs[id])
	return out


## Room-slot contents only (everything that is not a structural modifier).
static func room_contents() -> Array[ContentDef]:
	var out: Array[ContentDef] = []
	for d in all():
		if not d.is_modifier():
			out.append(d)
	return out


## Modifiers that can be slotted into the given structural kind.
static func modifiers_for(kind: int) -> Array[ContentDef]:
	var out: Array[ContentDef] = []
	for d in all():
		if d.is_modifier() and kind in d.modifier_for:
			out.append(d)
	return out
