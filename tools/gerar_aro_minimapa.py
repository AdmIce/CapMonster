# -*- coding: utf-8 -*-
"""Gera o aro do minimapa como PNG.

    python tools/gerar_aro_minimapa.py

Por que gerar em vez de baixar: nenhum pacote CC0 que eu encontrei traz uma
moldura **redonda** — Kenney UI Pack RPG e Fantasy UI Borders são todos
retangulares, e 9-slice não faz círculo (estica os cantos e vira uma pílula).

E por que PNG em vez de `draw_arc` no jogo: arco desenhado é uma faixa de cor
chata, sem volume e com serrilhado. Aqui dá para calcular o bisel por pixel, com
a luz vindo de cima à esquerda, e ainda renderizar em 4x para o contorno sair
liso. O resultado é um anel de metal, não três círculos coloridos.

Saída: assets/ui/aro_minimapa.png (512x512, centro transparente).
"""

import os
import numpy as np
from PIL import Image, ImageFilter

TAMANHO = 512
SUPER = 2                      # supersampling; 1024x1024 na conta, 512 no arquivo
LADO = TAMANHO * SUPER

# Raios em pixels do arquivo final.
R_EXTERNO = 250.0
R_INTERNO = 212.0
R_BISEL_ESCURO = 6.0           # espessura da borda escura externa
R_BEZEL = 9.0                  # aro escuro interno, entre o ouro e o mapa

# Paleta: a mesma família do resto da interface (ouro #C9922F).
OURO_CLARO = np.array([246, 218, 140], dtype=float)
OURO = np.array([201, 146, 47], dtype=float)
OURO_ESCURO = np.array([124, 84, 24], dtype=float)
BORDA = np.array([54, 34, 12], dtype=float)
BEZEL = np.array([32, 24, 16], dtype=float)

# Luz vindo de cima à esquerda, como no resto da arte do jogo.
LUZ = np.array([-0.62, -0.78])

REBITES = 8
RAIO_REBITE = 7.0
RAIO_ORBITA_REBITE = (R_EXTERNO + R_INTERNO) * 0.5


def _grade():
    eixo = (np.arange(LADO) + 0.5) / SUPER - TAMANHO / 2.0
    x, y = np.meshgrid(eixo, eixo)
    return x, y, np.sqrt(x * x + y * y)


def _suave(borda0, borda1, valor):
    """Transição suave entre dois limites — é o que tira o serrilhado.

    O denominador guarda o **sinal**: `borda1 < borda0` é uma transição
    decrescente, e é assim que se descreve a borda externa do anel. Proteger o
    zero com `max(1e-6, ...)` trocaria esse sinal e inverteria a máscara — o
    anel saía como um disco cheio com o miolo furado.
    """
    denom = borda1 - borda0
    if abs(denom) < 1e-6:
        denom = 1e-6 if denom >= 0 else -1e-6
    t = np.clip((valor - borda0) / denom, 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def gerar():
    x, y, r = _grade()

    # Onde há metal.
    dentro = _suave(R_EXTERNO, R_EXTERNO - 1.5, r) * _suave(R_INTERNO, R_INTERNO + 1.5, r)

    # Posição dentro da faixa: 0 na borda interna, 1 na externa.
    t = np.clip((r - R_INTERNO) / (R_EXTERNO - R_INTERNO), 0.0, 1.0)

    # Bisel: o anel é redondo em seção, então o meio da faixa é o ponto alto.
    # `altura` vai de 0 nas bordas a 1 no meio.
    altura = 1.0 - np.abs(t * 2.0 - 1.0)
    cor = (
        OURO_ESCURO[None, None, :] * (1.0 - altura)[:, :, None]
        + OURO[None, None, :] * altura[:, :, None]
    )

    # Luz direcional: a normal da superfície aponta para fora do centro, então o
    # produto escalar com a luz dá o lado iluminado do anel.
    with np.errstate(invalid="ignore", divide="ignore"):
        nx = np.where(r > 0, x / np.maximum(r, 1e-6), 0.0)
        ny = np.where(r > 0, y / np.maximum(r, 1e-6), 0.0)
    incidencia = np.clip(nx * LUZ[0] + ny * LUZ[1], -1.0, 1.0)
    brilho = 0.30 * incidencia * altura
    cor = cor + (OURO_CLARO - OURO)[None, None, :] * np.clip(brilho, 0, 1)[:, :, None]
    cor = cor + (OURO_ESCURO - OURO)[None, None, :] * np.clip(-brilho, 0, 1)[:, :, None]

    # Fio de luz fino perto da borda externa, do lado iluminado.
    fio = _suave(0.86, 0.94, t) * _suave(0.98, 0.90, t) * np.clip(incidencia, 0, 1)
    cor = cor + (OURO_CLARO - OURO)[None, None, :] * fio[:, :, None] * 0.9

    # Contornos escuros: fora e dentro. Sem eles o anel encosta no mundo e some.
    fora = _suave(R_EXTERNO - R_BISEL_ESCURO, R_EXTERNO, r)
    cor = cor * (1.0 - fora[:, :, None]) + BORDA[None, None, :] * fora[:, :, None]
    dentro_escuro = _suave(R_INTERNO + R_BEZEL, R_INTERNO, r)
    cor = cor * (1.0 - dentro_escuro[:, :, None]) + BEZEL[None, None, :] * dentro_escuro[:, :, None]

    # Rebites só nas diagonais. As quatro posições cardeais ficam lisas de
    # propósito: é onde o jogo escreve N, L, S e O, e rebite ali vira um borrão
    # atrás da letra.
    for i in range(REBITES):
        if i % 2 == 0:
            continue
        ang = -np.pi / 2.0 + i * (2.0 * np.pi / REBITES)
        raio = RAIO_REBITE
        cx = np.cos(ang) * RAIO_ORBITA_REBITE
        cy = np.sin(ang) * RAIO_ORBITA_REBITE
        d = np.sqrt((x - cx) ** 2 + (y - cy) ** 2)

        corpo = _suave(raio, raio - 1.2, d)
        # Cúpula: mais claro em cima à esquerda do próprio rebite.
        domo = np.clip(1.0 - d / max(1e-6, raio), 0.0, 1.0)
        lx = np.where(d > 0, (x - cx) / np.maximum(d, 1e-6), 0.0)
        ly = np.where(d > 0, (y - cy) / np.maximum(d, 1e-6), 0.0)
        face = np.clip(lx * LUZ[0] + ly * LUZ[1], -1.0, 1.0)
        cor_rebite = (
            OURO[None, None, :]
            + (OURO_CLARO - OURO)[None, None, :] * (np.clip(face, 0, 1) * domo)[:, :, None]
            + (OURO_ESCURO - OURO)[None, None, :] * (np.clip(-face, 0, 1) * domo)[:, :, None]
        )
        anel_rebite = _suave(raio + 1.4, raio, d) * (1.0 - corpo)
        cor = cor * (1.0 - corpo[:, :, None]) + cor_rebite * corpo[:, :, None]
        cor = cor * (1.0 - anel_rebite[:, :, None]) + BORDA[None, None, :] * anel_rebite[:, :, None]
        dentro = np.maximum(dentro, _suave(raio + 1.4, raio - 1.2, d))

    rgba = np.zeros((LADO, LADO, 4), dtype=np.uint8)
    rgba[:, :, :3] = np.clip(cor, 0, 255).astype(np.uint8)
    rgba[:, :, 3] = np.clip(dentro * 255.0, 0, 255).astype(np.uint8)

    imagem = Image.fromarray(rgba, "RGBA").resize((TAMANHO, TAMANHO), Image.LANCZOS)

    # Sombra por baixo, para o aro descolar do mundo.
    sombra = Image.new("RGBA", (TAMANHO, TAMANHO), (0, 0, 0, 0))
    sombra.paste((0, 0, 0, 150), (0, 0), imagem.split()[3])
    sombra = sombra.filter(ImageFilter.GaussianBlur(5))
    final = Image.alpha_composite(sombra, imagem)

    destino = os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
        "assets", "ui", "aro_minimapa.png",
    )
    final.save(destino)
    print("gravado:", destino, final.size)


if __name__ == "__main__":
    gerar()
