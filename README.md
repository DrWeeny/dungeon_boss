# Dungeon Boss — POC (Godot 4)

Proof of concept for the *Dungeon Boss* loop: you play a bound soul (a lich, for
now) building a dungeon that feeds on adventurers. Wiping every group makes the
next one over-prepare; letting some flee with loot teaches them the place is
beatable and keeps them away from the boss room. The fun is in manipulating
probability, not executing a fixed plan.

Design spec: [Dungeon Boss — Design Spec (POC)](https://claude.ai/code/artifact/d99b5c11-15f9-4a49-88b4-eb01bbd81d88)

## Run it

Godot 4.7.2 lives in `D:\godot_4_7_2` on the dev machine (`Godot_v4.7.2-stable_win64_console.exe`
for terminal use).

1. Open `project.godot` in the editor and press **F5**, or from a terminal:

   ```
   godot --path .
   ```

2. Headless tuning harness (no window, prints stats for canned strategies). On a fresh
   clone run `godot --headless --path . --import` once so the `class_name` cache exists:

   ```
   godot --headless --path . -s scripts/tools/sim_batch.gd -- runs=300 waves=20 seed=3
   ```

   Strategies: `empty`, `greedy_kill`, `bait`, `balanced`, `swapper` (keeps swapping
   known rooms = surprises adventurers) and `builder` (grows dead-end reward annexes).

## Layout

| Path | What |
| --- | --- |
| `scripts/data/content_def.gd` | `ContentDef` resource: id, category, danger, reward, cost, per-class attraction |
| `scripts/data/content_library.gd` | The lich palette (monsters, traps, rewards, specials, door/chest modifiers) |
| `scripts/data/boss_profile.gd` | Per-boss fight numbers: HP, regen, combat skill, kills/round, buy-out, meat shield; `lich()`, `dragon()`, `fallen_knight()` |
| `scripts/core/boss.gd` | Boss fighting state: level, HP (persists, regen/wave), zombie shield |
| `scripts/core/room.gd` | Free-size room; type emerges from contents; additive danger/reward; `combo_key()` |
| `scripts/core/structural_element.gd` | Door / stair / chest / sarcophagus with independent modifier-slot tracks |
| `scripts/core/dungeon_graph.gd` | Floor stack of directed graphs; hand-authored floor 0; `insert_floor()`, `build_room()` |
| `scripts/core/party.gd` | Adventurer group: scalar power, class mix, per-member levels (weakest die first) |
| `scripts/core/adventurer_knowledge.gd` | Beliefs per *location* and per *combo*; surprise -> unpredictability (50% report, wipe ×2, worth-it discount, decay) |
| `scripts/core/wave_sim.gd` | Weighted junction choice, single opposed roll per room with outcome tiers, boss-room round loop |
| `scripts/core/game_session.gd` | One playthrough: magic, souls = boss XP, levels, floors, difficulty/scrying, building (pure data, no scene) |
| `scripts/core/game_state.gd` | Autoload wrapping the session with signals for the UI |
| `scripts/ui/main.gd` + `scenes/main.tscn` | Placeholder screen: floors, rooms, slots, build-path row, entrance scrying, branch odds, wave log |
| `scripts/tools/sim_batch.gd` | Headless batch simulator for tuning |

## The POC dungeon

```
Floor 0:   entry -> hall --+-> crypt ------------> vault --+-> stairs ==>
                           +-> ossuary --+-> vault --------+
                                         +-> shrine -> stairs
Floor -1:  boss
```

Two junctions (hall, ossuary), two routes to the stairs. The crypt has a
sarcophagus (50 % treasure / 50 % mummy), the vault a chest, hall and ossuary
each a door that can take secret / enigma / lethal modifiers once slots unlock.

Rules layered on top of the spec (from the 2026-09-21 review):

- **Location memory.** Adventurers remember what was at each spot as well as a
  combo's reputation (which travels with the combo when moved). Swapping a known
  room's contents *surprises* them: `unpredictability` rises and the next groups
  over-prepare. Building a new path (`build_room`) creates a spot with no
  expectations. A room with no exit is a dead end: the party leaves with its loot.
- **Boss XP.** Souls are XP; each level adds a modifier slot to every structural
  element and +1 chest tier; every 2 levels a new 4-room floor is inserted between
  the deepest floor and the boss floor (floor numbering: 0, -1, -2 ... boss last).
- **Entrance scrying** (next group's class repartition and power): Easy = always,
  Normal = from boss level 1, Hard = never.
- **Boss fight** (`BossProfile` + `WaveSim._boss_fight`). Not an opposed roll: the boss
  has hit points (`base_hp + hp_per_level x level`; lich 3 + 1/level), damage persists
  between waves with +1 regen. Each round the boss strikes first (kills the weakest
  member), then the survivors deal `highest level alive - combat_skill` HP. Bosses
  differ by data: the **lich** raises a zombie (1 shield point, soaked before HP,
  persists) for every adventurer it kills in its room; a **dragon** can buy a party
  off with magic when a round would kill it; a **fallen knight** has combat skill.
  Only the lich is selectable for now. Lich late-game power-up (boss level 4): the
  dungeon's own dead also join the zombie shield.
- **Boss door decision.** At the door the group compares its average level with
  what it believes the boss is: reported threat if a survivor has seen it,
  otherwise the average danger of the rooms it crossed x1.5. Higher -> 85 %,
  equal -> 50 %, lower -> 25 % chance to go in, minus loot satisfaction (loot vs
  1.5 x total party levels) and wounds. Inside, it sees the real threat (the level
  needed to kill the boss in the n-1 rounds it survives) and decides again; turning
  back is a flee and the boss gets reported (50 %; 25 % as rumour after a wipe).
- **Wounds.** Room losses are decimal member-equivalents: a barely-won fight
  wounds, margin 0 costs a full member, a flee costs one. Wounds accumulate, every
  full point kills the weakest, the fraction cuts power (0.5 per point) and appetite
  for the boss. Healing / rest specials heal on a won room.

## Where the placeholder numbers live

Everything is a `const` at the top of the file that uses it:

- Outcome tiers, roll size, junction weights: `wave_sim.gd`
- Survivor report rate, wipe multiplier, worth-it discount, rumour decay: `adventurer_knowledge.gd`
- Economy and wave scaling: `game_session.gd`
- Boss HP / shield / buy-out / dungeon-army level: `boss_profile.gd`
- Boss-door probabilities, loot/wound deterrents, decimal room damage: `wave_sim.gd`
- Per-content danger / reward / cost / attraction: `content_library.gd`

## Not in the POC (deferred per spec)

Procedural generation, multiple bosses/levels, quests/events, real combat,
per-class sub-stats, combo synergy formulas, endings, art pass.
