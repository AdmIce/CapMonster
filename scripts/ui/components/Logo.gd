class_name Logo
extends TextureRect
## A logo do jogo, para a tela de abertura e o menu de título.
##
## Existe como componente e não como um TextureRect solto em cada tela porque a
## logo tem proporção fixa (3:2) e é fácil alguém esticá-la sem perceber: aqui o
## `expand_mode` e o `stretch_mode` já vêm certos e só a largura é escolhida.
##
## Se o arquivo sumir, o nó devolve `null` e quem chamou volta ao título em texto
## — a abertura não pode depender de um PNG para existir.

const CAMINHO := "res://assets/ui/logo.png"

## Proporção real do arquivo, usada para deduzir a altura a partir da largura.
const PROPORCAO := 1536.0 / 1024.0


## `largura` em pixels de projeto. Devolve `null` quando não há arquivo.
static func criar(largura: float) -> Logo:
	if not ResourceLoader.exists(CAMINHO):
		return null
	var node := Logo.new()
	node.texture = load(CAMINHO)
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	node.custom_minimum_size = Vector2(largura, largura / PROPORCAO)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node
