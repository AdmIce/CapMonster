# CapMonster — comece por aqui

Bem-vindo. Este documento é para você rodar o jogo na sua máquina hoje e mandar
o primeiro Pull Request sem tropeçar em nada.

**O que é:** um monster idle RPG original em Godot 4.3 / GDScript. Você anda por
um mundo 3D, encontra criaturas, luta, captura e monta uma equipe de três. Já é
**online**: existe um servidor sempre ligado, e o jogo entra nele sozinho ao
abrir — não há modo offline.

**Onde está:** github.com/AdmIce/CapMonster, branch `main`.

**Nada é copiado de Pokémon** — nem arte, nem nome, nem mapa, nem texto. Isso não
é preciosismo, é o que permite publicar o jogo. Vale para tudo que você criar.

---

## 1. Preparar a máquina

| O quê | Versão | Por quê |
|---|---|---|
| [Godot](https://godotengine.org/download) | **4.3 estável**, .NET **não** | O projeto usa 4.3; 4.4 muda coisas de API |
| [Python](https://www.python.org/downloads/) | 3.9+ | Só para os validadores, não entra no jogo |
| Git | qualquer | — |

Não precisa de mais nada: sem engine paga, sem plugin, sem SDK.

```bash
git clone https://github.com/AdmIce/CapMonster.git
cd CapMonster
```

**A primeira abertura no editor demora alguns minutos** — a Godot importa os
modelos, texturas e o vídeo do menu. É uma vez só; o resultado fica em `.godot/`,
que não vai para o repositório.

---

## 2. Rodar

Abra o projeto no Godot e aperte F5. Ou pela linha de comando:

```bash
godot --path .
```

Teclas: **WASD** anda, **Shift** corre, **E** interage, **I** mochila, **M** mapa,
**C** troca a câmera, **Enter** abre o chat, **Esc** pausa.

### Sem clicar em nada

O jogo tem atalhos de teste que entram direto no mundo. Use sempre que for
conferir alguma coisa — é muito mais rápido que jogar até o ponto:

```bash
godot --headless --path . --quit-after 900 -- --smoke   # entra no mundo, sem janela
godot --path . -- --smoke --snapshot=6                  # abre, espera 6s, tira foto, fecha
godot --path . -- --smoke --abrir=loja --snapshot=9     # abre a loja na foto
godot --path . -- --smoke --auto                        # liga o modo automático
```

A foto sai em `snapshot.png` dentro do user data
(`%APPDATA%\Godot\app_userdata\CapMonster\` no Windows). **Copie para um nome
único antes de olhar** — reler a foto da execução anterior já enganou gente aqui
duas vezes.

O headless não desenha nada (renderizador falso), então para ver a tela use a
versão com janela. E ignore `ERROR: Parameter "m" is null`: é o renderizador
falso reclamando, não um bug.

---

## 3. Antes de abrir um PR

Três validadores. Todos precisam ficar em zero:

```bash
python tools/validate_data.py            # referências quebradas no /data
python tools/check_scripts.py            # indentação, membros renomeados, autoloads
powershell -File tools/godot_check.ps1   # o parser de verdade da Godot (só Windows)
```

Fora do Windows o terceiro não roda; nesse caso o teste de fumaça headless faz o
papel dele, porque um erro de parse impede o mundo de carregar.

O CI roda tudo isso em cada PR. **PR vermelho não entra** — e é melhor descobrir
em dois minutos no robô do que num merge já feito.

---

## 4. Testar o online sem duas pessoas

Suba duas instâncias na sua própria máquina:

```bash
# terminal 1 — hospeda
godot --headless --path . --quit-after 2000 -- --smoke --host --auto

# terminal 2 — entra
godot --headless --path . --quit-after 1500 -- --smoke --entrar=127.0.0.1 --auto
```

Os dois logs devem mostrar `Presença: ... apareceu em <mapa>`. É assim que a
rede foi construída e é assim que se prova que ela ainda funciona.

Se quiser testar contra o servidor de verdade, troque por `--entrar=<ip>` — mas
combine antes, porque **cliente e servidor precisam ser da mesma versão**.

---

## 5. Como trabalhamos

```bash
git switch -c o-que-voce-vai-fazer
# trabalha, comita
git push -u origin o-que-voce-vai-fazer
```

E abre um Pull Request.

**Ninguém empurra direto na `main`.** Nem eu, nem você. Tudo passa por PR e pelo
olho do outro. Não é burocracia: é a única forma de dois trabalharem sem um
desfazer o do outro sem perceber.

### Divisão por área, não por arquivo

Se cada um ficar na sua área, quase nunca dá conflito:

| Área | Onde mexe |
|---|---|
| conteúdo e balanceamento | `data/*.json` |
| mundo e combate | `scripts/world/`, `scripts/battle/` |
| interface | `scripts/ui/` |
| rede e servidor | `scripts/net/` |

Duas coisas deste projeto ajudam muito e talvez você não espere:

**A interface é construída em código, não em cenas.** Em Godot, dois devs
mexendo no mesmo `.tscn` é conflito impossível de resolver — arquivo de cena não
faz merge. Aqui é GDScript, então merge normal, linha por linha.

**Conteúdo é dado.** Criatura, item, mapa, missão e balanceamento vivem em
`data/*.json`. Dá para criar conteúdo por semanas sem tocar em código.

---

## 6. O que não fazer

- **Não empurre na `main`.**
- **Não comite `.godot/` nem `build/`.** São gerados. Se aparecerem no seu diff,
  algo está errado — avise em vez de commitar.
- **Não publique versão.** `tools/lancar.ps1` cria tag e dispara a release, que
  vai automaticamente para todos os jogadores. Isso fica comigo por enquanto,
  porque a release precisa combinar com o servidor.
- **Não mexa no servidor de produção** sem combinar. Ele está sempre no ar e tem
  as fichas dos jogadores.
- **Não invente interface que não faz nada.** Botão desligado que não explica o
  motivo, tela de mentira, número que não vem de lugar nenhum — nada disso entra.
  Se a opção não se aplica, ela some.

---

## 7. Se você usar IA para programar

Ótimo, eu uso também. Só faça uma coisa: **aponte ela para o
[`AGENTS.md`](AGENTS.md) na raiz do repositório antes de começar.**

Ali estão as convenções e, principalmente, as armadilhas que já custaram tempo
neste projeto — coisas que nenhuma IA adivinha e que geram bugs silenciosos. Um
exemplo real: **nada altera ouro, item ou XP direto**, tudo passa por
`Ficha.pedir()`. Se a sua IA escrever `dados.add_gold(...)` num lugar novo, o
ganho vai ser apagado no próximo estado que vier do servidor — sem erro, sem
aviso, e o bug aparece dias depois.

Ferramentas diferentes procuram nomes diferentes: o Claude Code lê `CLAUDE.md`,
o Cursor e o Codex leem `AGENTS.md`. Os dois já estão no repositório apontando
para o mesmo conteúdo.

E vale o óbvio: rode os validadores no que a IA escreveu. Ela vai dizer que
funciona; o CI é quem sabe.

---

## 8. Onde está o quê

```
data/           criaturas, habilidades, itens, mapas, missões — o jogo em JSON
scripts/
  core/         autoloads básicos: log, input, renderizador, atualizador
  managers/     dados, save, sessão, áudio, missões, idle
  world/        mundo 3D, mapa, spawn, criaturas selvagens, câmera
  battle/       combate
  player/       personagem, avatar, dados do jogador
  net/          rede: conexão, mundo autoritativo, ficha, chat
  ui/           tudo que aparece na tela
tools/          validadores e utilitários (não entram no jogo)
assets/         modelos, texturas, som, interface
```

Vale ler também o `ARCHITECTURE.md` (visão geral) e o `SERVIDOR.md` (como o
servidor funciona e do que ele precisa).

---

Qualquer dúvida, pergunte antes de assumir. É mais barato que refazer.
