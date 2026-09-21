class_name ContentDef
extends Resource

## One placeable piece of content: monster, trap, reward, decoration or special.
## A room's type is not chosen directly; it emerges from the ContentDefs placed in it.
## All numbers are POC placeholders meant to be tuned in-engine.

enum Category { MONSTER, TRAP, REWARD, DECORATION, SPECIAL, MODIFIER }

@export var id: String = ""
@export var display_name: String = ""
@export var category: Category = Category.MONSTER
## Contribution to the room's dangerosity (additive model for the POC).
@export var danger: float = 0.0
## Contribution to the room's reward (additive model for the POC).
@export var reward: float = 0.0
## Magic spent to place it. Refunded on removal (free rearrangement between waves).
@export var cost: int = 0
## Wounds healed (member-equivalents) when a party wins the room. Specials only.
@export var heal: float = 0.0
## Treasure tier of a reward piece (0 = not a treasure). Tiers are what recruit
## new adventurers when brought home; `reward` is the value felt on the way.
@export var tier: int = 0
## Enigma door modifier: members below this level cannot pass. 0 = no gate.
@export var min_level: int = 0
## Per-adventurer-class attraction weight, e.g. {"priest": 1.5}. Missing class = 1.0.
## Skews which classes show up in the *next* party, not where the party walks.
@export var attraction: Dictionary = {}
## Structural kinds this can be slotted into as a modifier (see StructuralElement.Kind).
## Empty = a normal room-slot content.
@export var modifier_for: Array[int] = []


static func make(p_id: String, p_name: String, p_cat: Category,
		p_danger: float, p_reward: float, p_cost: int,
		p_attr: Dictionary = {}) -> ContentDef:
	var c := ContentDef.new()
	c.id = p_id
	c.display_name = p_name
	c.category = p_cat
	c.danger = p_danger
	c.reward = p_reward
	c.cost = p_cost
	c.attraction = p_attr
	return c


func is_modifier() -> bool:
	return category == Category.MODIFIER


func short() -> String:
	var parts: Array[String] = []
	if danger != 0.0:
		parts.append("D%+.0f" % danger)
	if reward != 0.0:
		parts.append("R%+.0f" % reward)
	return "%s (%s, %d✦)" % [display_name, " ".join(parts) if parts.size() > 0 else "-", cost]
