class_name StructuralElement
extends RefCounted

## Door / stair / chest / sarcophagus. A separate system from room content slots:
## free to place, but each carries its own independent, upgradeable modifier-slot track.
## Slot upgrades are meta-progression (tied to boss/dungeon growth), not a per-room buy.

enum Kind { DOOR, STAIR, CHEST, SARCOPHAGUS }

const KIND_NAMES := { Kind.DOOR: "Door", Kind.STAIR: "Stair", Kind.CHEST: "Chest", Kind.SARCOPHAGUS: "Sarcophagus" }

## Chest base treasure per tier (the fixed base slot, scaled to a target group level).
const CHEST_TIER_REWARD := 4.0
## Sarcophagus gamble outcomes.
const SARCO_REWARD := 5.0
const SARCO_MONSTER_DANGER := 5.0   # a mummy crawls out
const SARCO_MONSTER_CHANCE := 0.5
const SARCO_TIER := 2

var kind: Kind
var modifier_slots: int = 0          # upgradeable track (door starts 0, chest starts 0 extra)
var modifiers: Array[ContentDef] = []
var tier: int = 1                    # chest only: base treasure tier


static func door() -> StructuralElement:
	var s := StructuralElement.new()
	s.kind = Kind.DOOR
	return s


static func stair() -> StructuralElement:
	# Slot-upgrade path for stairs is still an open question in the spec; 0 slots for now.
	var s := StructuralElement.new()
	s.kind = Kind.STAIR
	return s


static func chest(p_tier: int = 1) -> StructuralElement:
	var s := StructuralElement.new()
	s.kind = Kind.CHEST
	s.tier = p_tier
	return s


static func sarcophagus() -> StructuralElement:
	var s := StructuralElement.new()
	s.kind = Kind.SARCOPHAGUS
	return s


func kind_name() -> String:
	return KIND_NAMES[kind]


func upgrade_slots() -> void:
	modifier_slots += 1


func free_slots() -> int:
	return modifier_slots - modifiers.size()


func accepts(def: ContentDef) -> bool:
	return def.is_modifier() and kind in def.modifier_for and free_slots() > 0


func add_modifier(def: ContentDef) -> bool:
	if not accepts(def):
		return false
	modifiers.append(def)
	return true


func remove_modifier(idx: int) -> ContentDef:
	if idx < 0 or idx >= modifiers.size():
		return null
	return modifiers.pop_at(idx)


func has_modifier(id: String) -> bool:
	for m in modifiers:
		if m.id == id:
			return true
	return false


## Deterministic part of danger (the sarcophagus gamble is rolled at wave time).
func danger() -> float:
	var d := 0.0
	for m in modifiers:
		d += m.danger
	return d


## Deterministic part of reward.
func reward() -> float:
	var r := 0.0
	if kind == Kind.CHEST:
		r += CHEST_TIER_REWARD * tier
	for m in modifiers:
		r += m.reward
	return r


## Sarcophagus gamble: ~50% a reward, ~50% a monster instead. Returns {danger, reward, text}.
func roll_gamble(rng: RandomNumberGenerator) -> Dictionary:
	if kind != Kind.SARCOPHAGUS:
		return {"danger": 0.0, "reward": 0.0, "text": ""}
	if rng.randf() < SARCO_MONSTER_CHANCE:
		return {"danger": SARCO_MONSTER_DANGER, "reward": 0.0, "tier": 0, "text": "the sarcophagus opens: a mummy!"}
	return {"danger": 0.0, "reward": SARCO_REWARD, "tier": SARCO_TIER, "text": "the sarcophagus held treasure"}


## Treasure tiers a party picks up here (chest base slot + gold modifiers).
func treasure_tiers() -> Array[int]:
	var out: Array[int] = []
	if kind == Kind.CHEST:
		out.append(tier)
	for m in modifiers:
		if m.tier > 0:
			out.append(m.tier)
	return out


## Enigma gate level of a door (0 = none).
func gate_level() -> int:
	var g := 0
	for m in modifiers:
		g = maxi(g, m.min_level)
	return g


## Part of the room's combo key so adventurers learn "chest+needle" as a thing.
func key_part() -> String:
	var ids: Array[String] = []
	for m in modifiers:
		ids.append(m.id)
	ids.sort()
	var base := kind_name().to_lower()
	if kind == Kind.CHEST:
		base += str(tier)
	return base + ("[" + ",".join(ids) + "]" if ids.size() > 0 else "")


func describe() -> String:
	var s := kind_name()
	if kind == Kind.CHEST:
		s += " T%d" % tier
	s += " %d/%d" % [modifiers.size(), modifier_slots]
	if modifiers.size() > 0:
		var names: Array[String] = []
		for m in modifiers:
			names.append(m.display_name)
		s += " (" + ", ".join(names) + ")"
	return s
