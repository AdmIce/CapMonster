# Architecture

The shape of the project and, more usefully, *why* it is shaped this way.

---

## 1. The three layers

```
        data/*.json                 content, edited by design
             |
        DataManager                 loads + indexes it once, at boot
             |
   +---------+-----------+
   |                     |
 model layer          systems layer
 (RefCounted)         (Nodes / autoloads)
 CreatureSpecies      GameManager     SceneFlow
 CreatureData         SaveManager     Notify
 PlayerData           SpawnManager    (BattleManager, QuestManager, IdleManager...)
 Progression
   |
 presentation layer
 WorldRoot, MapBuilder, CameraRig, PlayerController, HUD, screens
```

The rule that keeps this from rotting: **the model layer never touches nodes,
and the presentation layer never owns state.** `CreatureData` has no idea a
`WildCreature` exists. `HUD` holds no numbers of its own — it reads `PlayerData`
and reacts to its signals.

## 2. Autoloads

Seven, in load order. Each has one job.

| Autoload | Owns | Explicitly does *not* own |
| --- | --- | --- |
| `GameLog` | Channel-tagged logging (`[Save]`, `[Battle]`, …) | anything gameplay |
| `InputActions` | Registering the input map in code, so rebinding becomes data later | reading input for anyone else |
| `DataManager` | Parsing and indexing `data/*.json`; element chart; `Progression` | mutable game state |
| `SaveManager` | Disk I/O, atomic writes, save versioning, settings, autosave timer | deciding *when* the game is worth saving |
| `GameManager` | Session lifecycle: who is playing, new game, continue, quit, travel | battle, quest, inventory rules |
| `SceneFlow` | The only place that changes scenes; owns the fade overlay | what any scene contains |
| `Notify` | Transient toasts | anything blocking or interactive |

`GameManager` is deliberately ~150 lines. Every temptation to grow it — battle
resolution, quest checks, idle rewards — belongs in its own manager that reads
`GameManager.player`.

## 3. Data-driven by default

Adding a creature, skill, item, element, rarity, map, zone or quest is a JSON
edit. There is no per-content code anywhere.

Two consequences worth stating:

- **Saves store inputs, not outputs.** A `CreatureData` persists species id,
  level, XP and current HP. Attack, defense, speed and max HP are recomputed from
  `creatures.json` + `progression.json` on every read. Rebalancing therefore
  applies retroactively to existing saves instead of leaving them stale.
- **`World.tscn` is generic.** It contains one `Node3D` and a script. It reads
  the current map id off the save, asks `MapBuilder` for geometry, and places
  interactables from the same data. A third map costs zero scenes.

`tools/validate_data.py` is the guard rail: it cross-checks every reference in
the database and fails the build-your-content loop early.

## 4. Why the UI is built in code

Screens are thin `.tscn` shells (a root node plus a script); the widget tree is
assembled by `Design` (`scripts/ui/DesignSystem.gd`).

This is a deliberate trade. The design brief asks for one grid, one spacing
scale, one type scale and one button system across the whole game. With 20+
scene files, those rules drift the first time someone nudges a margin in the
inspector. With a design system module, changing `Design.S_MD` or the button
padding updates every screen at once, and a code review can actually see the
layout rules.

The spacing scale is `4 / 8 / 12 / 16 / 24 / 32 / 48`, radii are `4 / 8 / 12`,
and the palette is graphite + mineral green with gold reserved strictly for
rarity and reward. Nothing else is allowed to invent a colour.

`Design.ignore_mouse(node)` exists because Godot's `Control` defaults to
`MOUSE_FILTER_STOP`; decorative HUD elements and the contents of card-shaped
buttons must be made click-through explicitly.

## 5. The 2.5D camera

`CameraRig` is a `Node3D` whose child `Camera3D` sits at a fixed pitch (48°) and
fixed yaw (0°), orthographic by default. The rig follows the player with a soft
lerp and a small velocity lead.

Because yaw is 0, screen-up is `-Z` and the input vector maps directly onto XZ —
`Vector3(input.x, 0, input.y)`. No camera-relative basis maths, no drift.

Bounds clamping is the part worth reading (`_visible_half_extents`): a tilted
camera sees further along Z than its vertical screen extent suggests, so the
depth half-extent is `size / (2 · sin(pitch))`, not `size / 2`. When a map is
narrower than the view, the camera centres instead of clamping. This function is
the single place that would need changing if a map ever wanted a rotated camera.

## 6. World construction

`WorldRoot._ready` runs a fixed sequence: validate session → environment →
ground → terrain patches → blockers → landmarks → scatter → player → camera →
interactables → spawner → UI.

`MapBuilder` is stateless statics. Scatter placement is seeded per group, so a
map looks identical on every machine and every run, and candidate points are
rejected if they land in a declared clearing, on a path, in water, or within 3 m
of an NPC / gate / heal point / spawn point. That is what keeps walkways open
without hand-placing 150 props.

Physics layers live in one file (`GameLayers`): `WORLD`, `PLAYER`, `CREATURE`,
`INTERACT`, `AGGRO`. Bodies use `MOTION_MODE_FLOATING` — the world is flat and
gravity is off, so every contact is a wall to slide along.

## 7. Interaction

`Interactable` (an `Area3D`) is the base for NPCs, heal points and gates.
Subclasses override `_perform`, and — if the action can be blocked — `is_available`
and `unavailable_reason`. The player carries a sensor area, tracks everything
overlapping it, and picks the nearest. The HUD only ever calls `prompt_label()`.

A locked gate stays visible and says why it is locked rather than disappearing.

## 8. Encounters

Encounters are visible, not random. `SpawnManager` keeps each zone at its
`max_alive`, never spawns within 12 m of the player, and respawns on the zone's
cooldown. `CreatureFactory.roll_wild` picks the species by table weight *times*
the rarity's `spawn_weight_modifier`, so a generous weight on a rare entry still
behaves.

`WildCreature` runs `IDLE → PATROL → CHASE → CONTACT → RETREAT`, using the same
state vocabulary the battle actors will use. On contact it emits
`encounter_triggered`, `SpawnManager` forwards it, and `WorldRoot._on_encounter`
handles it. **That function is the entire battle integration surface** — stage 5
replaces its body with a `BattleManager` hand-off and nothing else moves.

## 9. Saving

One slot, `user://saves/slot_0.json`, written to a temp file and renamed so a
crash mid-write cannot truncate it. The payload carries a `version` and
`SaveManager._migrate` is the switch future versions extend.

Save triggers: rest at a camp, map change, quick save, pause-menu save, quit, and
a 3-minute autosave timer. Leaving the world records the exact player position —
except when the player is mid-travel, in which case the destination map's own
spawn point wins.

Settings live separately in `user://settings.json` so wiping a save does not
reset the player's display preferences.

## 10. Conventions

- Tabs for indentation. `check_scripts.py` fails the file otherwise.
- Types on declarations and signatures wherever the type is knowable.
- Signals over polling for state changes; `_process` only for animation and
  smoothing.
- No magic numbers in gameplay code — they belong in `progression.json` or a
  named `const`.
- Comments explain *why*. The code already says what.
- Any file drifting past ~400 lines is a sign a responsibility needs extracting.

## 11. Prepared for, not built for

Multiplayer, accounts, cloud saves, PvP and guilds are not implemented and add no
complexity today. What makes them possible later:

- All persistent state funnels through `PlayerData.to_dict()` / `from_dict()`, so
  a server payload is the same shape as the local file.
- `SaveManager._write_file` / `_read_file` are the only I/O calls; swapping them
  for HTTP is a two-function change.
- Combat maths lives in `Progression`, not scattered across actors, so it can be
  moved server-side and stay authoritative.
- `GameManager` holds session identity separately from world state, which is the
  seam a login flow slots into.
