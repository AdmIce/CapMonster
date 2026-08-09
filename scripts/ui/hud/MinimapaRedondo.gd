class_name MinimapaRedondo
extends Control
## O minimapa do canto, redondo, com aro dourado e rosa dos ventos.
##
## Reaproveita o `MapView` inteiro — o desenho do mapa continua saindo do
## `maps.json`, nada é pintado à mão aqui. Esta classe só resolve a moldura:
## recorta o mapa num círculo e desenha o aro por cima.
##
## **Como o recorte circular funciona.** `clip_children` recorta os filhos pela
## forma que o próprio nó desenhou — então a máscara é um Control que desenha um
## círculo cheio e tem o MapView como filho. É o único jeito de recortar em
## círculo sem shader nem SubViewport; `clip_contents` só sabe recortar em
## retângulo.
##
## O norte é fixo em cima porque o mapa vem do JSON com a linha 0 no norte. Em
## terceira pessoa a câmera gira, mas o mapa não: mapa que gira junto com a
## câmera é mais difícil de ler e esconde para que lado fica o objetivo.

const DIAMETRO := 190.0
## Grosso o bastante para as letras dos pontos cardeais caberem **dentro** dele.
## Desenhadas do lado de fora, elas saíam da área do controle e a do leste era
## cortada pela borda da tela.
const ESPESSURA_ARO := 13.0
const ALTURA_TITULO := 26.0

const COR_ARO_EXTERNO := Color("#6B4A1E")
const COR_ARO := Color("#C9922F")
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


func configurar(dados: Dictionary, jogador: Node3D) -> void:
	if mapa != null:
		mapa.configurar(dados, jogador, false)
	if _titulo != null:
		_titulo.text = String(dados.get("name", "")).to_upper()
	queue_redraw()


## Círculo cheio: é ele que define o recorte dos filhos. A cor não aparece
## (CLIP_CHILDREN_ONLY desenha só os filhos), mas o alfa precisa ser 1.
func _desenhar_mascara() -> void:
	var raio := DIAMETRO * 0.5
	_mascara.draw_circle(Vector2(raio, raio), raio - ESPESSURA_ARO * 0.5, COR_FUNDO)


func _draw() -> void:
	var centro := Vector2(DIAMETRO * 0.5, ALTURA_TITULO + DIAMETRO * 0.5)
	var raio := DIAMETRO * 0.5 - ESPESSURA_ARO * 0.5

	# Três arcos concêntricos dão volume ao aro sem precisar de textura: sombra
	# por fora, ouro no meio, brilho por dentro.
	draw_arc(centro, raio + 1.5, 0.0, TAU, 64, COR_ARO_EXTERNO, ESPESSURA_ARO + 3.0, true)
	draw_arc(centro, raio, 0.0, TAU, 64, COR_ARO, ESPESSURA_ARO, true)
	draw_arc(centro, raio - ESPESSURA_ARO * 0.45, 0.0, TAU, 64, COR_ARO_BRILHO, 1.5, true)

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
			draw_string_outline(fonte, pos, letra, HORIZONTAL_ALIGNMENT_LEFT, -1, tamanho, 4, COR_ARO_BRILHO)
		draw_string(fonte, pos, letra, HORIZONTAL_ALIGNMENT_LEFT, -1, tamanho, COR_LETRA)
