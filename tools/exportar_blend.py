# -*- coding: utf-8 -*-
"""Exporta um .blend para .glb, sem abrir o Blender na tela.

    blender --background <arquivo.blend> --python tools/exportar_blend.py -- <saida.glb>

Por que existe: modelo comprado costuma vir em .blend, e .blend nao pode entrar
no projeto. O Godot so importa .blend se houver Blender instalado na maquina, e
o build no GitHub Actions nao tem -- a versao publicada sairia sem o modelo, ou
o build quebraria. Convertendo aqui, o repositorio guarda um .glb que qualquer
maquina abre.

As texturas vao embutidas no proprio .glb (`export_format='GLB'`), entao o
arquivo e autossuficiente: nao ha caminho relativo para quebrar quando alguem
clonar o repositorio em outra pasta.
"""

import os
import sys

import bpy


def main():
    if "--" not in sys.argv:
        print("ERRO: falta o caminho de saida depois de --")
        sys.exit(1)
    saida = sys.argv[sys.argv.index("--") + 1:][0]

    pasta = os.path.dirname(os.path.abspath(saida))
    if pasta and not os.path.isdir(pasta):
        os.makedirs(pasta)

    bpy.ops.export_scene.gltf(
        filepath=saida,
        export_format="GLB",
        # Aplica modificadores: o que o artista ve na tela e o que sai. Sem
        # isto, subdivisao e espelhamento ficam para tras e o modelo chega
        # facetado ou pela metade.
        export_apply=True,
        export_yup=True,
    )
    print("SAIU: %s (%d bytes)" % (saida, os.path.getsize(saida)))


main()
