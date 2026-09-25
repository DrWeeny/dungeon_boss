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
| `scripts/core/adventurer.gd` | One persistent adventurer: class, level, XP, camp / teleport bind |
| `scripts/core/town.gd` | The population: recruitment from treasures, fear -> recruit level, party formation, camps |
| `scripts/core/party.gd` | One group on one wave: power, wounds, treasure tiers, enigma split (weakest die first) |
| `scripts/core/adventurer_knowledge.gd` | Beliefs per *location* and per *combo*; surprise -> unpredictability (50% report, wipe ×2, worth-it discount, decay) |
| `scripts/core/wave_sim.gd` | Weighted junction choice, single opposed roll per room with outcome tiers, boss-room round loop |
| `scripts/core/game_session.gd` | One playthrough: magic, souls = boss XP, levels, floors, difficulty/scrying, building (pure data, no scene) |
| `scripts/core/game_state.gd` | Autoload wrapping the session with signals for the UI |
| `scripts/core/dungeon_map.gd` | Tile-grid layout of one floor: room footprints, corridors, door tiles, markers |
| `scripts/ui/map_view.gd` | Draws a floor and handles clicks; swaps in real tiles from `assets/tiles/` |
| `scripts/ui/main.gd` + `scenes/main.tscn` | Placeholder screen: floor tabs, clickable map, selected room's slots and build row, scrying, branch odds, wave log |
| `scripts/tools/sim_batch.gd` | Headless batch simulator for tuning |
| `scripts/tools/screenshot.gd` | Renders the main scene and saves a PNG (`godot --path . -s scripts/tools/screenshot.gd`) |

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
- **The town** (`town.gd`). Adventurers are persistent: survivors keep XP and
  levels (XP per room danger beaten and per wave home, x0.5 / x1 / x1.5 by
  difficulty) and come back. Two flows feed the population: **treasures brought
  home** recruit (1 basic recruit per 3 treasure tiers, a specialised +2-level
  recruit when a tier-3 piece came back) and **fear** (souls, wipes, surprises)
  raises the level new recruits arrive at. "Escaped" by itself recruits nobody.
  The town never drops below 4. One group per non-boss floor sets out each wave,
  population permitting; groups run one after another inside the wave.
- **Corridor tricks.** Enigma door L2 / L3: members below that level go home,
  the rest push on as a smaller group (or everyone goes home empty-handed).
  Secret door: extra pull at the junction. Rest area (stair modifier): a hurt or
  thinned group camps there and continues next wave from that floor. Teleport
  stair (built off any room, 10 magic): drops straight to a chosen deeper floor
  and binds the groups that use it, so they start there next time. Empty rooms
  are walked through without a roll.

## The map

Each floor is laid out on a tile grid, rebuilt from the graph after every change
(`dungeon_map.gd`), so the rules never have to know about tiles. Room footprints
follow the room size - **Small 2x2, Medium 4x4, Large 8x8** - with a 2x2 entrance
and an **8x8 boss room**. Every connection is carved as a door tile plus an
L-shaped corridor, so a room with two branches really shows two doors leading to
two rooms, and building a new path adds another door to that room.

Click a room on the map to edit it; the floor tabs switch levels. Door tiles are
tinted by kind (plain gold, secret blue, enigma purple, lethal red) and the last
group's route is highlighted after a wave.

Art is placeholder colours and shapes. Drop PNGs into `assets/tiles/` (names
listed in `assets/tiles/README.md`) and they are used automatically.

## Where the placeholder numbers live

Everything is a `const` at the top of the file that uses it:

- Outcome tiers, roll size, junction weights: `wave_sim.gd`
- Survivor report rate, wipe multiplier, worth-it discount, rumour decay: `adventurer_knowledge.gd`
- Economy and wave scaling: `game_session.gd`
- Boss HP / shield / buy-out / dungeon-army level: `boss_profile.gd`
- Boss-door probabilities, loot/wound deterrents, decimal room damage, survivor XP, camp thresholds: `wave_sim.gd`
- Recruitment ratios, fear per soul/wipe/surprise, population floor: `town.gd`
- Tile size, room footprints, corridor gaps: `map_view.gd` / `dungeon_map.gd`
- Per-content danger / reward / cost / attraction: `content_library.gd`

## Not in the POC (deferred per spec)

Procedural generation, multiple bosses/levels, quests/events, real combat,
per-class sub-stats, combo synergy formulas, endings, art pass.
