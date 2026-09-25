# Tiles

Drop PNGs here to replace the placeholder colours and shapes. They are picked up
automatically by `scripts/ui/map_view.gd` — no code change, no scene edit. Any
size works; each is scaled to `MapView.TILE_PX` (18 px by default).

| File | Drawn for |
| --- | --- |
| `empty.png` | solid rock (outside rooms and corridors) |
| `floor.png` | room floor |
| `corridor.png` | corridor between rooms |
| `door.png` | a door tile — one per connection leaving or entering a room |
| `entry.png` | the dungeon entrance |
| `boss.png` | the boss room centre (the room itself is 8x8) |
| `stair.png` | a plain stairwell down |
| `rest.png` | stairwell with a rest area (groups camp there) |
| `teleport.png` | stairwell with a teleport bind (shortcut to a deeper floor) |
| `chest.png` | a chest |
| `sarcophagus.png` | a sarcophagus |
| `monster.png` | any monster placed in a slot |
| `trap.png` | any trap placed in a slot |
| `reward.png` | any reward placed in a slot |

Room footprints come from the room size: Small 2x2, Medium 4x4, Large 8x8; the
entrance is 2x2 and the boss room 8x8. Doors without art are tinted by kind:
plain gold, secret blue, enigma purple, lethal red.
