# -*- coding: utf-8 -*-
"""Converte um sprite no formato .spr para uma folha PNG.

    python tools/converter_spr.py npc/1_M_JOBTESTER.spr assets/npc/ash

O `.spr` guarda vários quadros de tamanhos diferentes, com paleta indexada e
compressão RLE. A Godot não lê nada disso, então a conversão gera:

  * `<saida>.png`  — todos os quadros lado a lado, mesma altura
  * `<saida>.json` — a caixa de cada quadro, para o jogo recortar

Formato (versão 2.1, que é a deste arquivo):
  "SP" + versão menor + versão maior
  uint16 quantidade de quadros indexados
  uint16 quantidade de quadros RGBA        (só na versão >= 2.0)
  para cada indexado: uint16 largura, uint16 altura, uint16 bytes comprimidos,
                      dados RLE onde 0x00 é seguido de quantos zeros vêm
  para cada RGBA:     uint16 largura, uint16 altura, pixels crus
  paleta de 1024 bytes no fim, se houver quadro indexado

O índice 0 da paleta é o fundo transparente — é convenção do formato, não
opção: sem isso todo sprite sai com um retângulo colorido em volta.
"""

import io
import json
import os
import struct
import sys

from PIL import Image


def _ler(dados, pos, formato):
    tamanho = struct.calcsize(formato)
    valores = struct.unpack_from(formato, dados, pos)
    return valores, pos + tamanho


def _descomprimir_rle(bruto, esperado):
    saida = bytearray()
    i = 0
    while i < len(bruto) and len(saida) < esperado:
        b = bruto[i]
        i += 1
        if b != 0:
            saida.append(b)
            continue
        if i >= len(bruto):
            break
        repeticoes = bruto[i]
        i += 1
        saida.extend(b"\x00" * repeticoes)
    return bytes(saida)


def ler_spr(caminho):
    dados = open(caminho, "rb").read()
    if dados[:2] != b"SP":
        raise ValueError("nao e um arquivo .spr")

    (menor, maior), pos = _ler(dados, 2, "<BB")
    versao = maior + menor / 10.0

    (n_indexados,), pos = _ler(dados, pos, "<H")
    n_rgba = 0
    if versao >= 2.0:
        (n_rgba,), pos = _ler(dados, pos, "<H")

    quadros = []
    indexados = []
    for _ in range(n_indexados):
        (largura, altura), pos = _ler(dados, pos, "<HH")
        if versao >= 2.1:
            (comprimido,), pos = _ler(dados, pos, "<H")
            cru = _descomprimir_rle(dados[pos:pos + comprimido], largura * altura)
            pos += comprimido
        else:
            cru = dados[pos:pos + largura * altura]
            pos += largura * altura
        indexados.append((largura, altura, cru))

    rgbas = []
    for _ in range(n_rgba):
        (largura, altura), pos = _ler(dados, pos, "<HH")
        cru = dados[pos:pos + largura * altura * 4]
        pos += largura * altura * 4
        rgbas.append((largura, altura, cru))

    paleta = None
    if n_indexados > 0 and len(dados) - pos >= 1024:
        paleta = dados[len(dados) - 1024:]

    for largura, altura, cru in indexados:
        if largura == 0 or altura == 0 or paleta is None:
            continue
        img = Image.new("RGBA", (largura, altura))
        pixels = []
        for indice in cru[:largura * altura]:
            if indice == 0:
                pixels.append((0, 0, 0, 0))       # índice 0 = transparente
            else:
                r, g, b = paleta[indice * 4:indice * 4 + 3]
                pixels.append((r, g, b, 255))
        img.putdata(pixels)
        quadros.append(img)

    for largura, altura, cru in rgbas:
        if largura == 0 or altura == 0:
            continue
        # O .spr guarda RGBA invertido na vertical e com os canais em ABGR.
        img = Image.frombytes("RGBA", (largura, altura), cru)
        r, g, b, a = img.split()
        img = Image.merge("RGBA", (a, b, g, r)).transpose(Image.FLIP_TOP_BOTTOM)
        quadros.append(img)

    return quadros, versao


def montar_folha(quadros, destino):
    if not quadros:
        raise ValueError("nenhum quadro legivel")
    altura = max(q.height for q in quadros)
    largura = sum(q.width for q in quadros)
    folha = Image.new("RGBA", (largura, altura), (0, 0, 0, 0))

    caixas = []
    x = 0
    for q in quadros:
        # Alinhado pelo pé: é assim que o sprite fica plantado no chão quando o
        # quadro muda de altura entre poses.
        y = altura - q.height
        folha.paste(q, (x, y))
        caixas.append({"x": x, "y": y, "w": q.width, "h": q.height})
        x += q.width

    os.makedirs(os.path.dirname(destino) or ".", exist_ok=True)
    folha.save(destino + ".png")
    with io.open(destino + ".json", "w", encoding="utf-8") as fh:
        json.dump({"altura": altura, "quadros": caixas}, fh, ensure_ascii=False, indent=1)
    return folha


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 1
    quadros, versao = ler_spr(sys.argv[1])
    folha = montar_folha(quadros, sys.argv[2])
    print("versao %.1f  |  %d quadro(s)  |  folha %dx%d" % (
        versao, len(quadros), folha.width, folha.height
    ))
    return 0


if __name__ == "__main__":
    sys.exit(main())
