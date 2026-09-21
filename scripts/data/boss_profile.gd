class_name BossProfile
extends Resource

## How a boss takes a fight. One shared round loop (WaveSim._boss_fight) reads
## these numbers, so bosses differ by data: the lich is fragile but grows fast,
## a dragon can buy its way out with treasure, a fighter shrugs off damage.
## All numbers are POC placeholders.

@export var id: String = ""
@export var display_name: String = ""
## Hit points at level 0, and gained per boss level.
@export var base_hp: int = 1
@export var hp_per_level: int = 1
## HP regained between waves (damage persists otherwise).
@export var hp_regen_per_wave: int = 1
## Combat skill: HP lost per round is reduced by this (never below 0).
@export var combat_skill: int = 0
## Adventurers killed per round (the boss strikes first each round).
@export var kills_per_round: int = 1
## Buy-out: when a round would kill the boss, pay `buyout_per_level` magic per
## adventurer level still alive and the party leaves with the bribe. 0 = never.
@export var buyout_per_level: int = 0
## Meat shield: every adventurer the boss kills in its room raises this many
## points of shield (zombies) that absorb damage before the boss's own HP.
## The army persists between waves.
@export var shield_per_kill: int = 0
## Late-game power-up: from this boss level on, adventurers killed anywhere in the
## dungeon also join the shield. -1 = never.
@export var dungeon_army_level: int = -1


static func make(p_id: String, p_name: String, p_base_hp: int, p_hp_per_level: int,
		p_skill: int = 0, p_kills: int = 1, p_buyout: int = 0, p_shield: int = 0) -> BossProfile:
	var b := BossProfile.new()
	b.id = p_id
	b.display_name = p_name
	b.base_hp = p_base_hp
	b.hp_per_level = p_hp_per_level
	b.combat_skill = p_skill
	b.kills_per_round = p_kills
	b.buyout_per_level = p_buyout
	b.shield_per_kill = p_shield
	return b


## The POC boss: low health, but each adventurer it kills becomes a zombie
## (1 shield point) standing between the next blow and its phylactery.
static func lich() -> BossProfile:
	var b := make("lich", "Lich", 3, 1, 0, 1, 0, 1)
	b.dungeon_army_level = 4
	return b


## Future bosses, here only to show the rule set covers them (not selectable yet).
static func dragon() -> BossProfile:
	return make("dragon", "Dragon", 2, 1, 0, 1, 2)


static func fallen_knight() -> BossProfile:
	return make("knight", "Fallen knight", 1, 1, 1, 1)
