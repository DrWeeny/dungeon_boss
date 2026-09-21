class_name Boss
extends RefCounted

## The bound soul's fighting state: profile + level + current hit points.
## Level comes from souls (GameSession); HP persists across waves with regen.

var profile: BossProfile
var level: int = 0
var hp: int = 0
var shield: int = 0     # meat shield (zombies); absorbs damage before hp



func _init(p_profile: BossProfile) -> void:
	profile = p_profile
	hp = max_hp()


func max_hp() -> int:
	return profile.base_hp + profile.hp_per_level * level


func level_up() -> void:
	level += 1
	hp += profile.hp_per_level   # a new level is fresh HP, not a heal


func regen() -> void:
	hp = mini(hp + profile.hp_regen_per_wave, max_hp())


func is_dead() -> bool:
	return hp <= 0


## Shield soaks first. Returns {shield: int, hp: int} actually lost.
func take_damage(dmg: int) -> Dictionary:
	var to_shield := mini(dmg, shield)
	shield -= to_shield
	var to_hp := mini(dmg - to_shield, hp)
	hp -= to_hp
	return {"shield": to_shield, "hp": to_hp}


func add_shield(n: int) -> void:
	shield += n


## What a group of `party_size` sizes up when it sees the boss: the adventurer
## level needed to kill it before it kills them. The boss strikes first each
## round, so n members get n-1 damage rounds of (level - skill) each.
func threat_level(party_size: int) -> int:
	var rounds := maxi(party_size - 1, 1)
	return ceili(float(hp + shield) / rounds) + profile.combat_skill


func describe() -> String:
	return "%s lvl %d, %d/%d HP%s" % [profile.display_name, level, hp, max_hp(),
		" + %d shield" % shield if shield > 0 else ""]
