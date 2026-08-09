class_name MinimapaRedondo
extends Control
## O minimapa do canto, redondo, com aro de metal e rosa dos ventos.
##
## Reaproveita o `MapView` inteiro — o desenho do mapa continua saindo do
## `maps.json`, nada é pintado à mão aqui. Esta classe só resolve a moldura:
## recorta o mapa num círculo e põe o aro por cima.
##
## **Como o recorte circular funciona.** `clip_children` recorta os filhos pela
## forma que o próprio nó desenhou — então a máscara é um Control que desenha um
## círculo cheio e tem o MapView como filho. É o único jeito de recortar em
## círculo sem shader nem SubViewport; `clip_contents` só sabe recortar em
## retângulo.
##
## **O aro é uma imagem, não `draw_arc`.** Arco desenhado é faixa de cor chapada,
## sem volume e serrilhada. O PNG é gerado por `tools/gerar_aro_minimapa.py`, com
## bisel calculado por pixel e luz vindo de cima à esquerda. Nenhum pacote CC0
## que eu achei traz moldura redonda — os do Kenney são todos retangulares, e
## 9-slice não faz círculo.
##
## O norte é fixo em cima porque o mapa vem do JSON com a linha 0 no norte. Em
## terceira pessoa a câmera gira, mas o mapa não: mapa que gira junto com a
## câmera é mais difícil de ler e esconde para que lado fica o objetivo.

const DIAMETRO := 190.0
const ALTURA_TITULO := 26.0
const ARO := "res://assets/ui/aro_minimapa.png"

## Geometria do PNG, em fração do lado dele (512). Mudar o gerador exige mudar
## estes dois números junto, senão o mapa vaza por baixo do aro.
const FRACAO_RAIO_INTERNO := 212.0 / 512.0
const FRACAO_RAIO_DA_FAIXA := 231.0 / 512.0

const COR_ARO_BRILHO := Color("#F2C75C")
## Tinta das letras dos pontos cardeais: escura, porque elas ficam sobre o ouro.
const COR_LETRA := Color("#3B2410")
const COR_FUNDO := Color("#0E1319")

const PONTOS_CARDEAIS := [
	{"letra": "N", "angulo": -PI * 0.5},
	{"letra": "L", "angulo": 0.0},
	{"letra": "S", "angulo": PI * 0.5},
	{"letra": "O", "angulo": PI},
]

var mapa: MapView = null

var _titulo: Label = null
var _mascara: Control = null


func _init() -> void:
	custom_minimum_size = Vector2(DIAMETRO, DIAMETRO + ALTURA_TITULO)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	_titulo = Design.sobre_o_mundo(
		Design.label("", Design.FS_CAPTION, Design.GOLD_CLARO), 4
	)
	_titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_titulo.size = Vector2(DIAMETRO, ALTURA_TITULO)
	_titulo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_titulo)

	# A máscara desenha o círculo; o MapView vive dentro dela e é recortado.
	_mascara = Control.new()
	_mascara.name = "Mascara"
	_mascara.position = Vector2(0, ALTURA_TITULO)
	_mascara.size = Vector2(DIAMETRO, DIAMETRO)
	_mascara.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	_mascara.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mascara.draw.connect(_desenhar_mascara)
	add_child(_mascara)

	mapa = MapView.new()
	mapa.name = "MapView"
	mapa.position = Vector2.ZERO
	mapa.size = Vector2(DIAMETRO, DIAMETRO)
	mapa.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mapa.preencher = true
	_mascara.add_child(mapa)

	# O aro entra depois da máscara, então fica por cima do mapa e esconde a
	# borda serrilhada do recorte.
	if ResourceLoader.exists(ARO):
		var aro := TextureRect.new()
		aro.name = "Aro"
		aro.texture = load(ARO)
		aro.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		aro.stretch_mode = TextureRect.STRETCH_SCALE
		aro.position = Vector2(0, ALTURA_TITULO)
		aro.size = Vector2(DIAMETRO, DIAMETRO)
		aro.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(aro)
	else:
		GameLog.warn(GameLog.Channel.UI, "Aro do minimapa ausente; rode tools/gerar_aro_minimapa.py.")

	# As letras vão num nó **depois** do aro. O `_draw` de um Control roda antes
	# dos filhos dele, então desenhá-las aqui na raiz punha N, L, S e O por baixo
	# do PNG do aro — elas existiam e ninguém via.
	var letras := Control.new()
	letras.name = "Cardeais"
	letras.set_anchors_preset(Control.PRESET_FULL_RECT)
	letras.mouse_filter = Control.MOUSE_FILTER_IGNORE
	letras.draw.connect(_desenhar_cardeais.bind(letras))
	add_child(letras)


func configurar(dados: Dictionary, jogador: Node3D) -> void:
	if mapa != null:
		mapa.configurar(dados, jogador, false)
	if _titulo != null:
		_titulo.text = String(dados.get("name", "")).to_upper()
	queue_redraw()


## Círculo cheio: é ele que define o recorte dos filhos. A cor não aparece
## (CLIP_CHILDREN_ONLY desenha só os filhos), mas o alfa precisa ser 1.
##
## O raio acompanha a borda interna do aro com uma folga de 1 px, para o mapa
## passar por baixo do metal em vez de deixar uma fresta.
func _desenhar_mascara() -> void:
	var meio := DIAMETRO * 0.5
	_mascara.draw_circle(Vector2(meio, meio), DIAMETRO * FRACAO_RAIO_INTERNO + 1.0, COR_FUNDO)


## Só as letras: o metal vem do PNG.
func _desenhar_cardeais(onde: Control) -> void:
	var centro := Vector2(DIAMETRO * 0.5, ALTURA_TITULO + DIAMETRO * 0.5)
	var raio := DIAMETRO * FRACAO_RAIO_DA_FAIXA

	var fonte := Design.ui_font()
	if fonte == null:
		fonte = ThemeDB.fallback_font

	for ponto in PONTOS_CARDEAIS:
		var angulo: float = ponto["angulo"]
		var direcao := Vector2(cos(angulo), sin(angulo))
		var letra: String = ponto["letra"]
		var tamanho := 13 if letra == "N" else 11
		var medida := fonte.get_string_size(letra, HORIZONTAL_ALIGNMENT_LEFT, -1, tamanho)
		# Centralizada na linha do aro. `draw_string` ancora na base da letra, daí
		# a metade da altura entrar no deslocamento vertical.
		var pos := centro + direcao * raio - Vector2(medida.x * 0.5, -medida.y * 0.32)
		# Tinta escura sobre o ouro: letra clara com contorno some no próprio aro,
		# que já é claro. O norte ganha um halo para se distinguir dos outros três.
		if letra == "N":
			onde.draw_string_outline(
				fonte, pos, letra, HORIZONTAL_ALIGNMENT_LEFT, -1, tamanho, 4, COR_ARO_BRILHO
			)
		onde.draw_string(fonte, pos, letra, HORIZONTAL_ALIGNMENT_LEFT, -1, tamanho, COR_LETRA)
