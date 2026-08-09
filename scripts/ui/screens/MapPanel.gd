class_name MapPanel
extends CanvasLayer
## O mapa em tela cheia, na tecla M.
##
## É o mesmo `MapView` do minimapa, só que grande e com `detalhado` ligado, o que
## acrescenta os nomes das zonas, dos portões e dos chefes, mais a legenda.
##
## Pausa o jogo enquanto está aberto: ler o mapa com criatura correndo atrás de
## você não seria leitura, seria pressa.

signal aberto()
signal fechado()

var _mapa: MapView = null
var _titulo: Label = null


func _ready() -> void:
	layer = 48
	process_mode = Node.PROCESS_MODE_ALWAYS
	_construir()
	visible = false


func alternar(dados: Dictionary, jogador: Node3D) -> void:
	if visible:
		fechar()
	else:
		abrir(dados, jogador)


func abrir(dados: Dictionary, jogador: Node3D) -> void:
	_titulo.text = String(dados.get("name", "Mapa")).to_upper()
	_mapa.configurar(dados, jogador, true)
	visible = true
	aberto.emit()
	get_tree().paused = true
	AudioManager.tocar_ui(&"ui_alternar")


func fechar() -> void:
	visible = false
	get_tree().paused = false
	AudioManager.tocar_ui(&"ui_alternar")
	fechado.emit()


func esta_aberto() -> bool:
	return visible


func _construir() -> void:
	var raiz := Control.new()
	raiz.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(raiz)

	var scrim := ColorRect.new()
	scrim.color = Color(0.02, 0.03, 0.04, 0.8)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	raiz.add_child(scrim)

	var margem := Design.margin(Design.S_XL)
	margem.set_anchors_preset(Control.PRESET_FULL_RECT)
	raiz.add_child(margem)

	var coluna := Design.vbox(Design.S_SM)
	margem.add_child(coluna)

	var cabecalho := Design.hbox(Design.S_MD)
	coluna.add_child(cabecalho)
	_titulo = Design.label("", Design.FS_TITLE, Design.TEXT, true)
	cabecalho.add_child(_titulo)
	cabecalho.add_child(Design.expander())

	var fechar_botao := Design.button("Fechar  (M / Esc)", "ghost")
	fechar_botao.pressed.connect(fechar)
	cabecalho.add_child(fechar_botao)

	_mapa = MapView.new()
	_mapa.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mapa.size_flags_vertical = Control.SIZE_EXPAND_FILL
	coluna.add_child(_mapa)

	coluna.add_child(_montar_legenda())


func _montar_legenda() -> Control:
	var linha := Design.hbox(Design.S_LG)
	linha.alignment = BoxContainer.ALIGNMENT_CENTER

	var itens := [
		["Você", MapView.COR_JOGADOR],
		["Descanso", MapView.COR_CURA],
		["Passagem", MapView.COR_PORTAO],
		["Chefe", MapView.COR_CHEFE],
		["Morador", MapView.COR_NPC],
		["Zona de encontro", MapView.COR_ZONA],
	]
	for item in itens:
		var grupo := Design.hbox(Design.S_XS)
		var ponto := Panel.new()
		ponto.custom_minimum_size = Vector2(10, 10)
		ponto.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		ponto.add_theme_stylebox_override("panel", Design.panel_style(item[1], 5, 0))
		grupo.add_child(ponto)
		grupo.add_child(Design.label(String(item[0]), Design.FS_CAPTION, Design.TEXT_MUTED))
		linha.add_child(grupo)

	return linha


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("cancel") or event.is_action_pressed("map"):
		get_viewport().set_input_as_handled()
		fechar()
