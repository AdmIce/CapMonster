# assets/

Nothing in the prototype loads a binary asset yet — every model, prop and NPC is
built from Godot primitives at runtime. These folders exist so real art can be
dropped in without moving code around.

| Folder | Expected content | Who reads it |
| --- | --- | --- |
| `models/` | `.glb` / `.gltf` creature and character scenes | set `model_path` in `data/creatures.json`; `CreatureModelBuilder` instantiates it and skips the procedural build |
| `textures/` | albedo / normal maps for the above | referenced by the imported model materials |
| `icons/` | UI icons, element glyphs, item icons | `icon_path` in `creatures.json`, `glyph` in `elements.json` |
| `audio/` | BGM and SFX (`.ogg`) | AudioManager (stage 15) |
| `animations/` | shared `.res` animation libraries | rigged character/creature scenes |
| `fonts/` | `display.ttf` and `ui.ttf` | `Design.display_font()` / `Design.ui_font()` pick them up automatically if present, otherwise the engine default is used |

## Swapping the placeholder art

1. Drop `emberfang.glb` into `assets/models/creatures/`.
2. Set `"model_path": "res://assets/models/creatures/emberfang.glb"` on that
   species in `data/creatures.json`.
3. Run `python tools/validate_data.py`.

No code change. The `visual` block stays in the file and is simply ignored for
that species.

## Assets de terceiros já no projeto

| Pasta | Origem | Licença |
| --- | --- | --- |
| `models/city/` (15 `.glb` + `colormap.png`) | [Kenney — Starter Kit City Builder](https://github.com/KenneyNL/Starter-Kit-City-Builder) | modelos CC0, código MIT (cópia em `models/city/LICENSE-Kenney.md`) |
| `audio/` (11 `.ogg`) | mesmo kit | CC0 |
| `models/characters/` (4 `.glb` + texturas) | [KayKit — Adventurers Character Pack](https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0), por Kay Lousberg | CC0 (cópia em `LICENSE-KayKit.txt`) |
| `/3d/source/Dino-Might…obj` | fornecido pelo David (autor: IronGut) | **verificar antes de publicar** |

Os personagens do KayKit vêm com esqueleto de 41 ossos e **76 animações**. O jogo
usa `Idle`, `Walking_A`, `Running_A` e `Interact`; o resto (ataque, dano, morte,
pegar item, sentar) fica disponível para o combate e as cutscenes.

As peças vêm nomeadas (`Knight_Head`, `Rogue_Body`, `Mage_Cape`…), o que permite
tingir pele e roupa separadamente e esconder as armas que vêm no pacote — o jogo
é de treinador, não de guerreiro.

O `.mtl` do Dino-Might foi escrito à mão: não veio no download, e sem ele o
modelo importava todo branco.

O kit da cidade pinta tudo com uma textura de paleta só. O `MapBuilder` aplica
esse material na mão (`_material_do_kit`) em vez de confiar no que vem embutido
no `.glb` — resolve textura que não cola e ainda deixa um material só para as
143 peças.

## Licenciamento

Só adicione asset que você tem direito de distribuir. Nada aqui pode sair de
jogo comercial.
