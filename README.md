# CapMonster

Um monster-collector idle RPG. Universo próprio, criaturas próprias — nada de
asset, nome, mecânica-por-nome ou identidade visual tirada de outro jogo.

**Engine:** Godot 4.3+ (GDScript) · **Ferramentas:** Python 3.9+ e PowerShell ·
**Alvo:** Windows primeiro, depois Android / iOS / Linux.

Este repositório contém a **fundação (etapa 1)** mais a abertura com o professor,
o painel de status e o modo automático. Combate, captura, tela de equipe,
inventário, missões, chefes e o loop idle offline estão nas etapas 5 a 13 e
**não** estão implementados. Nada na build finge o contrário: não existe botão
sem função nem tela falsa.

---

## Rodando

**Atalho na área de trabalho:** `CapMonster` abre o jogo direto, sem passar
pelo editor. Ele aponta para o Godot em
`%LOCALAPPDATA%\Programs\Godot\Godot_v4.3-stable_win64.exe` com
`--path <esta pasta>`.

> Ainda **não** é um `.exe` autônomo: o atalho depende do Godot instalado nesse
> caminho e da pasta do projeto onde ela está. Para gerar um executável que roda
> em qualquer máquina é preciso instalar os *export templates* do Godot
> (Editor → Gerenciar Modelos de Exportação, ~800 MB) e então
> Projeto → Exportar → Windows Desktop.

**Pelo editor:** Godot → Importar → `project.godot` → Importar e editar → **F5**.

Não há nada para compilar nem dependência para baixar.

### Controles

| Tecla | Ação |
| --- | --- |
| `W A S D` / setas | Andar |
| `Shift` | Correr |
| `E` / `Enter` | Interagir (NPCs, acampamentos, portões) e avançar diálogo |
| `Espaço` | Pular |
| `Espaço` ×2 | Levantar voo; voando, segurar sobe |
| `Ctrl` | Voando, descer (chegou ao chão, pousa) |
| `C` | Trocar de câmera: de cima → terceira pessoa → sobre o ombro → primeira pessoa |
| Mouse | Olhar, nas câmeras de ombro e de primeira pessoa |
| `Alt` (segurando) | Soltar o cursor para clicar na interface, nessas duas câmeras |
| `Esc` | Menu de pausa / fechar diálogo (também solta o mouse) |
| `F5` | Salvamento rápido |
| `F1` | Menu de debug (**só em build de debug**) |

Analógico esquerdo e A/B/X já estão mapeados para controle.

---

## O primeiro minuto

Título → criação do personagem → **posto de pesquisa do Professor Elir** → mundo.

Na abertura o professor explica o mundo em falas curtas (o que são as criaturas
de éter, como funciona o Núcleo de Vínculo, a regra dos três na equipe, o que há
no norte de Valverde). Quando ele termina, as três iniciais se materializam nos
pedestais, o painel de escolha sobe e você fica com uma. Ele se despede, entrega
os itens iniciais e você entra no mapa.

Todo o roteiro está em `data/intro.json` — trocar as falas, o nome do professor
ou a ordem é edição de JSON. Tem botão **Pular abertura** para quem já viu.

---

## Sistemas em funcionamento

| Sistema | Estado |
| --- | --- |
| **Vila Juncal** (mapa inicial) | Vila de verdade com 143 peças modulares do kit do Kenney, descrita como desenho em texto em `maps.json`. Zona segura: sem criaturas selvagens. |
| **Combate** | Automático com intervalo por velocidade, elemento, crítico, dano flutuante, barra de vida 3D, habilidades manuais do líder, poção, captura e fuga. |
| **Chefes** | Mini-chefe e chefe visíveis no mapa com aura. Você escolhe encarar (não puxam briga por encostão). Segunda mecânica: fúria abaixo de 50% de vida. Chefe só libera depois do mini-chefe. |
| **Missões** | 7 missões lendo `quests.json`, abrindo e fechando sozinhas, com recompensa e cadeia de pré-requisitos. |
| **Mochila / Equipe / Coleção** | Três abas com detalhe: modelo 3D girável, atributos, habilidades com descrição, barra de XP, evoluir, trocar slot, invocar. |
| **Mascote** | A criatura do slot 1 anda com você e reage a troca de líder. |
| **Modo automático** | Caça, descansa quando a equipe cai abaixo de 35%, desiste de alvo inalcançável e devolve o controle ao primeiro toque no direcional. |
| **Idle offline** | Tela de "bem-vindo de volta" com ouro, XP e material, cortando no teto de 8 h. |
| **Áudio** | Três barramentos e biblioteca por nome lógico. Sons são placeholders CC0 do kit do Kenney. |
| **Câmera** | Terceira pessoa por padrão, isométrica na tecla C, e enquadramento próprio durante a batalha. |

## O que funciona hoje

- **Fluxo completo** título → personagem → abertura → mundo, com save no fim.
- **Criação do personagem** — nome, corpo, 3 cabelos, 3 cores, 3 tons de pele,
  3 roupas, com preview 3D ao vivo da mesma classe de avatar que anda no mundo.
- **Escolha da inicial** lida de `creatures.json` (`"starter": true`). Os números
  mostrados saem da fórmula real de atributos, no nível em que a criatura é dada.
- **Arredores de Valverde inteiro caminhável** — vila, trilhas, riacho, bosque
  velho, ruínas, clareira do chefe, ~150 objetos, tudo gerado de `maps.json`.
- **Painel de status** no canto superior esquerdo: retrato em losango, nome em
  dourado, emblema de nível e três barras — **vermelha** = vida da criatura
  líder, **azul** = experiência do treinador, **fina** = experiência da criatura
  líder. Os três números são reais; nenhum é decorativo.
- **Modo automático (botão AUTO)** — o personagem explora sozinho: caça a
  criatura selvagem mais próxima, volta ao acampamento para descansar quando a
  equipe está machucada e vagueia quando não há nada por perto. Encostar num
  direcional retoma o controle na hora.
- **Câmera 2.5D** — inclinação fixa de 48°, ortográfica, seguindo com folga e
  travada nos limites do mapa. Zoom é uma configuração.
- **Movimentação** com aceleração, corrida, animação procedural e colisão contra
  objetos, água, penhascos e paredes do mapa.
- **4 NPCs com diálogo**, acampamento que cura de verdade e salva, e um portão
  para a Serra Cinérea que continua visível, selado, e explica o porquê.
- **Criaturas visíveis no mapa** — 6 zonas, tabelas de spawn ponderadas, faixas
  de nível, IA de patrulha/perseguição/recuo, respawn e um sinal discreto para
  espécies raras ou acima.
- **Salvar / carregar / autosave** — escrita atômica, payload versionado,
  autosave a cada 3 minutos mais descanso, troca de mapa, saída e F5.
- **Serra Cinérea** inteira autorada e carregando (acessível agora pelo menu de
  debug; normalmente quando o chefe existir, na etapa 10).
- **Menu de debug** com ouro, XP, nível, criaturas, cura, evolução, viagem entre
  mapas e reset de save — some da build de release por `OS.is_debug_build()`.

## O que é placeholder, e assumidamente

| Coisa | Situação |
| --- | --- |
| Toda a arte 3D | Primitivas montadas a partir do bloco `visual` do JSON. As silhuetas são distintas e a paleta é por espécie, mas é placeholder. Solte um `.glb` e preencha `model_path` para trocar. |
| Painel de status | Desenhado em `_draw()` com polígonos. Quando existir o PNG da moldura, troca-se o corpo de `_draw` por NinePatchRect e a interface pública não muda. |
| Fontes | Padrão da engine até existirem `assets/fonts/display.ttf` e `ui.ttf`. O `Design` pega sozinho. |
| Áudio | Nenhum. Por isso não existe slider de volume fingindo funcionar. |
| Mercador Hobb | Conversa, mas não tem loja — e a fala dele diz isso. Loja na etapa 8. |
| Chefes | Autorados em `maps.json` (posição, nível, escoltas, recompensas) mas não spawnados: não há combate para enfrentá-los. Etapa 10. |
| `quests.json` | Completo e validado, mas nenhum QuestManager lê ainda. Etapa 9. |
| Modo automático | Já anda, caça e descansa. Quando o combate entrar (etapa 5), ganha o passo "lutar" — a máquina de estados já está preparada. |
| Encontro → batalha | O contato é detectado e resolve o `CreatureData` real da criatura. `WorldRoot._on_encounter` é o único ponto de integração do BattleManager. |

---

## Idioma

Tudo que o jogador lê está em português: interface, diálogos, descrições, nomes
de criaturas, mapas, habilidades, itens, elementos e raridades.

Os campos `id` dos JSON continuam em inglês de propósito — são chaves de código
usadas em saves, tabelas de spawn e nos validadores. Renomear um `id` quebraria
saves existentes; renomear um `name` não quebra nada.

---

## Ferramentas de verificação

```bash
python tools/validate_data.py
```

```bash
python tools/check_scripts.py
```

```powershell
powershell -File tools/godot_check.ps1 -Godot "C:\Godot\Godot_v4.3-stable_win64.exe"
```

Rode os três depois de qualquer edição. Também existem testes headless que
percorrem o jogo sozinhos:

```powershell
& $godot --headless --path . --quit-after 900 -- --smoke
```

| Argumento | O que exercita |
| --- | --- |
| `--smoke` | Entra direto no mundo: dados, geração de mapa, spawner, HUD. Rodar duas vezes cobre salvar/carregar. |
| `--smoke-intro` | Percorre a abertura inteira: professor, pedestais, escolha e entrada no mundo. |
| `--smoke --auto` | Liga o modo automático na entrada e deixa o personagem caçar sozinho. |

Detalhes e como ler a saída: `tools/README.md`.

### Verificado

Godot **4.3.stable**. Os 40 scripts passam no parser; os dois mapas, a abertura,
o painel de status, o modo automático e o ciclo salvar/carregar rodam limpos em
headless. Falta um humano para conferir o que headless não alcança: sensação da
movimentação, enquadramento da câmera e navegação com mouse nos menus.

---

## Estrutura

```
project.godot            autoloads; input registrado em código (scripts/core/InputSetup.gd)
data/                    o banco de dados inteiro - editar aqui é trabalho de conteúdo
  elements.json          7 elementos + tabela de vantagens
  rarities.json          5 faixas e seus multiplicadores
  progression.json       todas as curvas: XP, atributos, combate, captura, idle
  skills.json            26 habilidades
  creatures.json         20 espécies (12 colecionáveis, 4 evoluções, 4 chefes)
  items.json             8 itens + inventário inicial
  maps.json              2 mapas: terreno, objetos, NPCs, zonas, portões, chefes
  quests.json            7 missões (só dados até a etapa 9)
  intro.json             roteiro da abertura com o professor
scenes/
  main/                  Boot, MainMenu, CharacterCreation, Intro
  maps/World.tscn        uma cena genérica, dirigida por maps.json
scripts/
  core/                  GameLog, InputSetup, Progression
  managers/              DataManager, SaveManager, GameManager, SceneFlow, Notify
  creatures/             CreatureSpecies, CreatureData, CreatureFactory, CreatureModelBuilder
  player/                PlayerData, PlayerController, PlayerAvatar
  world/                 WorldRoot, MapBuilder, CameraRig, SpawnManager, WildCreature,
                         AutoPilot, HumanoidBuilder, Interactable, NpcActor,
                         HealPoint, MapGate, GameLayers
  ui/                    DesignSystem, CreaturePreview, components/, screens/, hud/
assets/                  vazio de propósito - veja assets/README.md
tools/                   validate_data.py, check_scripts.py, godot_check.ps1
```

`ARCHITECTURE.md` explica por que as peças estão divididas assim e o que cada uma
possui. *(ainda em inglês — tradução pendente.)*

## Adicionar conteúdo sem tocar em código

- **Uma criatura** → uma entrada em `creatures.json`.
- **Habilidade / item / elemento / raridade** → uma entrada no arquivo certo.
- **Um mapa** → uma entrada em `maps.json`. O `World.tscn` monta o que achar.
- **Rebalancear** → `progression.json`. As curvas valem para criaturas que já
  estão em saves antigos, porque o save guarda nível e XP, nunca atributo pronto.
- **Mudar a abertura** → `intro.json`.

Sempre termine com `python tools/validate_data.py`.

## Próximos passos

**5** combate · **6** captura · **7** tela de equipe · **8** inventário ·
**9** missões · **10** chefes · **11** progressão do mapa 2 · **12** idle offline ·
**13** migração de save · **14** passada de UI · **15** áudio e polimento.
