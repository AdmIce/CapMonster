# Servidor dedicado

O CapMonster roda sem cliente: o mundo existe, as criaturas nascem e circulam, e
as fichas dos jogadores ficam guardadas ali, mesmo com ninguém conectado. É o
que separa "jogar na casa de alguém" de "um mundo que está sempre no ar".

## Do que ele precisa

Medido com o mundo de pé, em regime (não no arranque, que consome mais):

| Recurso   | Consumo real         | O que contratar        |
|-----------|----------------------|------------------------|
| RAM       | 142 MB               | 1 GB sobra             |
| CPU       | 4,5% de um núcleo    | 1 vCPU                 |
| Disco     | 74 MB o binário      | qualquer coisa (10 GB) |
| Banda     | ~15 KB/s com 4 jogadores | qualquer franquia  |

Ou seja: **o VPS mais barato que existir serve**. 1 vCPU e 1 GB, Ubuntu 22.04 ou
24.04. Não precisa de placa de vídeo — o servidor roda `--headless` e nem abre
janela.

A conta da banda: cada jogador manda a posição 15 vezes por segundo, uns 80
bytes com o cabeçalho, e o servidor repassa para os outros. Com quatro pessoas
conectadas o dia inteiro isso dá algo como 40 GB por mês, dentro da franquia de
qualquer plano.

O servidor roda a 30 quadros por segundo de propósito (`SERVIDOR_QUADROS` no
`Boot.gd`): ele não desenha nada e as posições viajam a 15 Hz, então 60 seria
queimar CPU à toa. A 60 o consumo era quatro vezes maior.

## Subir

```bash
./capmonster-servidor.x86_64 --headless -- --servidor --mapa=greenvale --porta=24565
```

Os dois traços soltos são obrigatórios: o que vem depois deles é argumento do
jogo, não do motor.

| Argumento   | Padrão      | O que faz                          |
|-------------|-------------|------------------------------------|
| `--servidor`| —           | liga o modo sem cliente            |
| `--mapa=`   | `greenvale` | qual mapa o servidor hospeda       |
| `--porta=`  | `24565`     | porta UDP do ENet                  |

## Gerar o binário

```powershell
godot --headless --path . --export-release "Servidor Linux" build/servidor/capmonster-servidor.x86_64
```

O preset é `dedicated_server=true` e sai com o `.pck` embutido: um arquivo só
para copiar para a VPS. O vídeo do menu fica de fora — servidor não desenha nada.

## Na VPS

```bash
scp build/servidor/capmonster-servidor.x86_64 root@SEU_IP:/opt/capmonster/
ssh root@SEU_IP 'chmod +x /opt/capmonster/capmonster-servidor.x86_64'
```

Serviço do systemd, para subir sozinho no boot e reiniciar se cair:

```ini
# /etc/systemd/system/capmonster.service
[Unit]
Description=CapMonster - servidor dedicado
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/capmonster
ExecStart=/opt/capmonster/capmonster-servidor.x86_64 --headless -- --servidor --mapa=greenvale
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

```bash
systemctl enable --now capmonster
ufw allow 24565/udp        # ENet é UDP, não TCP
journalctl -u capmonster -f
```

## Onde ficam as fichas

Em `~/.local/share/godot/app_userdata/CapMonster/mundo/<nome>.json`, uma por
personagem. **É isso que precisa de backup** — o binário se regera, o progresso
dos jogadores não.

O personagem de um jogador neste mundo é separado do save de um jogador só dele,
como em qualquer servidor privado. Entrar aqui pela primeira vez traz o
personagem que ele tinha; a partir daí quem manda é o servidor, e editar o
arquivo na máquina dele não muda mais nada aqui.

## O que o servidor decide hoje

- quais criaturas existem, onde nascem e quando renascem;
- quem pode iniciar batalha com cada uma (dois jogadores não capturam o mesmo);
- ouro, itens, XP, nível e coleção de cada ficha;
- quem recebe cada mensagem de chat, e o ritmo de envio.

## O que ainda roda no cliente

A **batalha em si**. O servidor credita o resultado que o cliente relatou, então
um cliente adulterado ainda consegue dizer que venceu uma luta que não teve.
Fechar isso significa mover o combate inteiro para cá — é a próxima etapa, e é
grande.
