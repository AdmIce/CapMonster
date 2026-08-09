# tools/

Python-side developer tooling. None of it ships with the game — it exists to
keep the JSON database and the GDScript honest between engine runs.

Requires Python 3.9+. No third-party packages.

## `validate_data.py`

Cross-checks everything in `data/`:

- broken references (creature → skill, zone → species, gate → map, quest → item)
- malformed colours, level ranges, spawn weights, capture rates
- evolution chains that self-loop or point at nothing
- `spawn_maps` that disagrees with the zone tables that actually use the species
- bosses that are accidentally capturable, non-obtainable species in wild tables

```bash
python tools/validate_data.py
```

Exit code 0 = clean. Run it after every content edit.

## `check_scripts.py`

Static sanity pass over `scripts/`:

- mixed tab/space indentation (Godot refuses to parse the file)
- unbalanced brackets and unterminated strings
- duplicate `class_name` registrations
- `SomeClass.member` where the member is declared nowhere in that class or its
  project-local ancestors — this is what catches renamed methods and typos
- autoloads in `project.godot` pointing at missing scripts
- `.tscn` files referencing scripts that do not exist

```bash
python tools/check_scripts.py
```

It is not a GDScript parser and never will be — the engine is the real
authority. It exists to catch the cheap mistakes before you launch the editor.

## `godot_check.ps1`

Parses every script with the **real** Godot parser, headlessly.

```powershell
powershell -File tools/godot_check.ps1 -Godot "C:\Godot\Godot_v4.3-stable_win64.exe"
```

Or set `GODOT_BIN` once and drop the `-Godot` argument.

`godot --check-only --script <file>` loads one script with **no autoloads
registered**, so it reports `Compile Error: Identifier not found: DataManager`
for perfectly healthy files. The script filters those out, plus the bare
`Compile Error:` cascade from a dependency that failed for the same reason.
Everything it still prints is real — parse errors, type-inference errors,
genuine missing identifiers.

This is what catches Godot 4.3 treating *"the variable type is being inferred
from a Variant value"* as an **error**, not a warning: `var x := some_variant`
will not compile. Declare the type explicitly.

## Headless smoke test

`Boot.gd` accepts a `--smoke` user argument in debug builds. It skips the title
screen, loads the save (or creates a throwaway one and picks the first starter),
saves, and drops straight into the world.

```powershell
& $godot --headless --path . --quit-after 700 -- --smoke
```

That exercises data loading, map generation, prop scatter, the spawner, the
interactables and the HUD without anyone pressing a button. Running it twice in
a row also covers the save/load round-trip, because the second run finds the
save the first one wrote.

Ignore `ERROR: Parameter "m" is null` at `mesh_storage.h` — that is the headless
dummy renderer refusing to allocate meshes, not a bug in the game. A clean run
shows only `[Data]`, `[Save]` and `[World]` lines.

**Sempre copie o PNG para um nome único antes de olhar.** O arquivo sai sempre
em `snapshot.png`; reler esse mesmo caminho depois de outra execução já me fez
duas vezes concluir que uma tela estava quebrada quando eu estava olhando a foto
anterior. Faça `Copy-Item snapshot.png tela_<algo>.png` e leia a cópia.

### Abrir um painel direto na captura

Painéis que normalmente exigem andar até um NPC e apertar E podem ser abertos
na entrada do mapa:

```powershell
& $godot --path . -- --smoke --abrir=loja --snapshot=5
```

Valores aceitos: `loja`, `mochila`, `missoes`, `mapa`.

To smoke-test the second map, point the save at it before running:
`%APPDATA%\Godot\app_userdata\Aetherbound\saves\slot_0.json` → set
`player.current_map` to `ashen_ridge`.
