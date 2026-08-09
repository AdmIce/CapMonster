# -*- coding: utf-8 -*-
"""Reexporta um .glb com as texturas reduzidas.

    blender --background --python tools/encolher_glb.py -- <entrada.glb> <saida.glb> [limite] [alvo_de_faces]

Por que existe: modelo de banco de assets vem com textura de 4K ou 8K embutida,
e um so deles pesa mais que o jogo inteiro. Num jogo low-poly rodando em OpenGL
essa resolucao nao aparece na tela -- so aparece no tamanho do .exe que os
jogadores baixam.

Reduzir a textura de um .glb pela metade nao da para fazer copiando arquivo: as
imagens estao dentro do binario. Por isso o caminho e abrir no Blender, trocar
as imagens e exportar de novo.
"""

import os
import sys

import bpy


def limpar_cena():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def main():
    if "--" not in sys.argv:
        print("ERRO: uso: -- <entrada.glb> <saida.glb> [limite]")
        sys.exit(1)
    args = sys.argv[sys.argv.index("--") + 1:]
    if len(args) < 2:
        print("ERRO: faltam entrada e saida")
        sys.exit(1)

    entrada, saida = args[0], args[1]
    limite = int(args[2]) if len(args) > 2 else 1024
    alvo_faces = int(args[3]) if len(args) > 3 else 0

    limpar_cena()
    bpy.ops.import_scene.gltf(filepath=entrada)

    mexidas = 0
    for imagem in bpy.data.images:
        if imagem.size[0] == 0:
            continue
        maior = max(imagem.size)
        if maior <= limite:
            continue
        fator = float(limite) / float(maior)
        largura = max(1, int(imagem.size[0] * fator))
        altura = max(1, int(imagem.size[1] * fator))
        print("  %s: %dx%d -> %dx%d" % (imagem.name, imagem.size[0], imagem.size[1], largura, altura))
        imagem.scale(largura, altura)
        mexidas += 1

    pasta = os.path.dirname(os.path.abspath(saida))
    if pasta and not os.path.isdir(pasta):
        os.makedirs(pasta)

    # Reducao de malha, quando pedida. Modelo de banco de assets costuma vir com
    # contagem de triangulo de renderizacao offline: bonito no visualizador,
    # absurdo para um bicho que anda ao lado do jogador e aparece com 80 px de
    # altura na tela.
    if alvo_faces > 0:
        antes = sum(len(o.data.polygons) for o in bpy.data.objects if o.type == "MESH")
        if antes > alvo_faces:
            razao = float(alvo_faces) / float(antes)
            for objeto in bpy.data.objects:
                if objeto.type != "MESH":
                    continue
                mod = objeto.modifiers.new(name="Reduzir", type="DECIMATE")
                mod.ratio = razao
            bpy.ops.object.select_all(action="DESELECT")
            for objeto in bpy.data.objects:
                if objeto.type == "MESH":
                    bpy.context.view_layer.objects.active = objeto
                    bpy.ops.object.modifier_apply(modifier="Reduzir")
            depois = sum(len(o.data.polygons) for o in bpy.data.objects if o.type == "MESH")
            print("  faces: %d -> %d" % (antes, depois))
        else:
            print("  faces: %d (abaixo do alvo, sem reduzir)" % antes)

    bpy.ops.export_scene.gltf(filepath=saida, export_format="GLB", export_apply=True)
    print("SAIU: %s (%.1f MB, %d textura(s) reduzida(s))" % (
        saida, os.path.getsize(saida) / 1048576.0, mexidas
    ))


main()
