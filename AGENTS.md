# Como trabalhar neste projeto

Leia isto antes de mexer em qualquer coisa. Vale para pessoas e para IAs — este
arquivo existe para que dois desenvolvedores (ou dois assistentes diferentes)
produzam código que combina em vez de brigar.

CapMonster é um monster idle RPG **original** em Godot 4.3 / GDScript. Nada de
Pokémon: nem arte, nem nome, nem mapa, nem texto.

---

## As regras que não se negociam

**Nada de interface falsa.** Todo botão faz alguma coisa ou explica por que não
pode. Se um controle não se aplica ao estado atual, ele some — não fica cinza
mentindo. Um exemplo real: escolher um personagem do kit Kenney esconde cabelo,
pele e roupa, porque naquele kit a aparência é uma textura e as opções não
fariam nada.

**Tudo em português** — nomes de criaturas, mapas, habilidades, itens, e também
os comentários do código. A exceção: os `id` dentro dos JSON ficam em inglês,
porque são chave de código, não texto de jogador.

**Conteúdo é dado, não código.** Criatura, habilidade, item, mapa e missão nova
entram editando `data/*.json`. Se for preciso escrever GDScript para adicionar
uma criatura, o desenho está errado.

**Comentário explica o porquê, não o quê.** `# soma 1 ao contador` não serve.
`# começa em 1 porque o slot 0 é o líder` serve. Quando um valor foi medido,
diga o número medido e o que aconteceu com o valor anterior.

---

## Antes de dizer que algo funciona

Três validadores, todos precisam ficar em zero:

```bash
python tools/validate_data.py    # referências quebradas no /data
python tools/check_scripts.py    # indentação, membros renomeados, autoloads
powershell -File tools/godot_check.ps1   # o parser de verdade da Godot
```

E o teste de fumaça, que entra no mundo sem ninguém clicar em nada:

```bash
godot --headless --path . --quit-after 900 -- --smoke
```

Ignore `ERROR: Parameter "m" is null` — é o renderizador falso do headless, não
um bug. Um teste limpo mostra só linhas `[Data]`, `[Save]` e `[World]`.

**Para ver a tela**, o headless não serve (ele não desenha). Use a janela:

```bash
godot --path . -- --smoke --snapshot=6           # foto depois de 6 s
godot --path . -- --smoke --abrir=loja --snapshot=9
godot --path . -- --smoke --modelo=res://caminho.glb:1.5   # planta um modelo ao lado do jogador
```

A foto sai sempre em `snapshot.png` no user data. **Copie para um nome único
antes de olhar** — reler a foto da execução anterior já fez concluir duas vezes
que uma tela estava quebrada quando ela estava certa.

---

## Armadilhas que já custaram tempo

**Godot 4.3 trata inferência de Variant como erro de parse**, não aviso:
`var x := dicionario.get("a")` não compila. Declare o tipo.

**Não use o AABB de uma malha com esqueleto para medir altura.** Ele é a caixa da
pose de vínculo e costuma vir degenerada. Meça pela pose de descanso dos ossos —
ou, quando nem isso servir (FBX), plante o modelo em cena com `--modelo=` e
compare com o personagem.

**Botão de HUD precisa de `focus_mode = FOCUS_NONE`.** O `ui_accept` da Godot é
Espaço/Enter, as mesmas teclas do jogo: com foco, andar pelo mundo clica no botão
sozinho. O `Design.button` já faz isso; só o menu principal liga o foco.

**`export_presets.cfg` usa `;` para comentário, não `#`.** Um `#` faz o resto da
seção ser ignorado em silêncio.

**Não exclua `3d/*` da exportação.** É onde moram os personagens Kenney e o
Bravossauro; excluídos, eles caem no boneco de primitivas **só no build**, e no
editor tudo parece certo.

**Edição em massa em vários arquivos: use Python, nunca array de pares no
PowerShell.** `@(@('a','b'))` achata e passa a trocar caractere por caractere.

**Asset novo só existe para o jogo depois de** `godot --headless --path . --editor --quit`.

---

## Rede: um caminho de código, duas autoridades

O jogo é online. Três autoloads sustentam isso, e todos seguem o mesmo princípio:
o código **não** pergunta "estou online?", ele pergunta "eu sou o dono?".
Jogando sozinho, o próprio processo é o dono — então não existe caminho especial
para o modo de um jogador.

| Autoload | Manda em |
|---|---|
| `Rede` | conexão, quem está online, posição de cada um |
| `MundoRede` | criaturas selvagens e quem pode lutar com cada uma |
| `Ficha` | ouro, itens, XP e coleção |
| `Chat` | canais, comandos e o ritmo de mensagens |

**Nada altera ouro, item, XP ou coleção direto.** Tudo passa por
`Ficha.pedir(acao, argumentos)`. Se você escrever `dados.add_gold(...)` num lugar
novo, o ganho vai ser apagado no próximo estado que vier do servidor.

**Todo RPC mora num autoload.** A Godot roteia RPC por caminho de nó, e o mundo é
construído por código: `/root/Rede` é igual em todas as máquinas, um nó do mundo
não é.

**Cliente e servidor precisam ser da mesma versão.** Ver `SERVIDOR.md`.

Para testar de verdade sem duas pessoas, suba duas instâncias:

```bash
godot --headless --path . -- --smoke --host --auto
godot --headless --path . -- --smoke --entrar=127.0.0.1 --auto
```

---

## Interface

Ela é construída em **código**, não em cenas — por isso duas pessoas conseguem
mexer na interface ao mesmo tempo sem conflito de merge, o que não seria verdade
com arquivos `.tscn`.

- `Design` é o sistema de design: cores, espaçamentos, botões, painéis. Não
  invente cor nem tamanho solto; use as constantes.
- `UISkin` põe a arte do UI Pack RPG (Kenney, CC0) por cima. Sem o pacote, tudo
  cai num visual chapado e o jogo continua abrindo.
- `Responsivo` cuida de a interface caber em qualquer janela. Tamanho mínimo em
  pixel escrito à mão vira conteúdo cortado numa tela menor.
- Texto **dentro** de painel usa `Design.TEXT*` (escuro sobre pergaminho). Texto
  solto sobre o mundo 3D usa `TEXT_CLARO*` **e** `Design.sobre_o_mundo()`, que
  põe contorno — sem ele o texto some sobre grama clara.

---

## Combinando o trabalho

O repositório é o github.com/AdmIce/CapMonster, branch `main`.

1. Cada um trabalha numa branch própria: `git switch -c minha-mudanca`
2. Abre Pull Request. **Ninguém empurra direto na `main`.**
3. O CI (`.github/workflows/verificar.yml`) roda os validadores e o teste de
   fumaça em cada PR. PR vermelho não entra.
4. Publicar versão é `powershell -File tools/lancar.ps1 -Versao 0.4.1 -Notas "..."`,
   e só depois de a `main` estar verde.

**Para dois trabalharem sem se atropelar**, divida por área, não por arquivo:

- conteúdo e balanceamento → `data/*.json` (quase não toca em código)
- mundo e combate → `scripts/world/`, `scripts/battle/`
- interface → `scripts/ui/`
- rede e servidor → `scripts/net/`

`.godot/` e `build/` não vão para o repositório — são gerados. Se aparecerem num
diff, algo está errado no `.gitignore`.
