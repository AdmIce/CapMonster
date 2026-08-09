class_name PlayerFrame
extends Control
## Painel de status do canto superior esquerdo: retrato, nome do treinador,
## emblema de nível e três barras.
##
##   vermelha  -> vida da criatura líder (slot 1 da equipe)
##   azul      -> experiência do treinador
##   verde     -> experiência da criatura líder
##
## Todos os três números são reais: saem de CreatureData e PlayerData, nenhum é
## decorativo. Se a equipe estiver vazia, as barras de criatura ficam vazias e o
## painel diz "sem equipe", em vez de mostrar um valor inventado.
##
## A arte vem do mesmo UI Pack RPG (Kenney, CC0) do resto da interface — moldura
## `panel_brown`, retrato `buttonSquare_brown`, emblema `buttonRound_brown` e as
## barras de três peças. Era a única tela ainda desenhada à mão em _draw(), e por
## isso a única que destoava. Sem o pacote, `_desenhar_chapado()` reproduz o
## painel antigo com retângulos, então o jogo nunca fica sem HUD.

## A altura é a última barra (112) mais a borda de baixo da moldura (18).
const FRAME_SIZE := Vector2(368, 132)

const RETRATO := Rect2(10, 30, 84, 84)
const EMBLEMA := Rect2(66, 90, 34, 34)
const NOME_POS := Vector2(104, 8)

## x, y, largura, altura de cada barra.
const HP_RECT := Rect2(104, 40, 250, 24)
const XP_RECT := Rect2(104, 70, 250, 20)
const SUB_RECT := Rect2(104, 96, 250, 16)

const ANIM_SPEED := 7.0

## Paleta de emergência, usada só quando o pacote não está no projeto.
const EDGE_DARK := Color("#0B1119")
const PANEL_FILL := Color("#101A26")
const NAME_GOLD := Color("#F2C75C")
const VALUE_GOLD := Color("#FFD98A")

var _player: PlayerData = null

var _trainer_name: String = "Treinador"
var _trainer_level: int = 1
var _leader_name: String = ""
var _leader_element: String = "nature"

var _hp_text: String = "sem equipe"
var _xp_text: String = ""
var _sub_text: String = ""

var _hp_target: float = 0.0
var _xp_target: float = 0.0
var _sub_target: float = 0.0
var _hp_shown: float = 0.0
var _xp_shown: float = 0.0
var _sub_shown: float = 0.0

# Nós da versão com arte. Ficam nulos quando o pacote não existe.
var _preenchimento: Dictionary = {}   ## "hp" | "xp" | "sub" -> NinePatchRect
var _valor: Dictionary = {}           ## "hp" | "xp" | "sub" -> Label
var _rotulo_nome: Label = null
var _rotulo_nivel: Label = null
var _rotulo_inicial: Label = null
var _fundo_retrato: ColorRect = null
var _com_arte: bool = false


func _init() -> void:
	custom_minimum_size = FRAME_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	_com_arte = UISkin.disponivel() and UISkin.textura_de_barra("Red") != null
	if _com_arte:
		_montar()
	queue_redraw()


func bind(player: PlayerData) -> void:
	_player = player
	player.level_changed.connect(func(_l): refresh())
	player.xp_changed.connect(func(_c, _n): refresh())
	player.team_changed.connect(refresh)
	player.collection_changed.connect(refresh)
	refresh()
	_hp_shown = _hp_target
	_xp_shown = _xp_target
	_sub_shown = _sub_target
	_aplicar()


## Relê tudo do PlayerData. Barato: são no máximo três criaturas.
func refresh() -> void:
	if _player == null:
		return
	_trainer_name = _player.display_name
	_trainer_level = _player.level

	var needed := _player.xp_to_next_level()
	if needed <= 0:
		_xp_target = 1.0
		_xp_text = "nível máximo"
	else:
		_xp_target = clampf(float(_player.xp) / float(needed), 0.0, 1.0)
		_xp_text = "%d / %d" % [_player.xp, needed]

	var team := _player.team()
	if team.is_empty():
		_leader_name = ""
		_leader_element = "nature"
		_hp_target = 0.0
		_sub_target = 0.0
		_hp_text = "sem equipe"
		_sub_text = ""
		_aplicar()
		return

	var leader: CreatureData = team[0]
	_leader_name = leader.display_name()
	_leader_element = leader.element()
	_hp_target = leader.hp_ratio()
	_hp_text = "%d / %d" % [leader.current_hp, leader.max_hp()]

	var creature_needed := leader.xp_to_next_level()
	if creature_needed <= 0:
		_sub_target = 1.0
		_sub_text = "%s  Nv.máx" % leader.display_name()
	else:
		_sub_target = clampf(float(leader.xp) / float(creature_needed), 0.0, 1.0)
		_sub_text = "%s  Nv.%d" % [leader.display_name(), leader.level]
	_aplicar()


func _process(delta: float) -> void:
	# A vida muda fora dos sinais (dano em combate), então é relida todo frame.
	if _player != null:
		var team := _player.team()
		if not team.is_empty():
			var leader: CreatureData = team[0]
			_hp_target = leader.hp_ratio()
			_hp_text = "%d / %d" % [leader.current_hp, leader.max_hp()]

	var weight := clampf(ANIM_SPEED * delta, 0.0, 1.0)
	var before := Vector3(_hp_shown, _xp_shown, _sub_shown)
	_hp_shown = lerpf(_hp_shown, _hp_target, weight)
	_xp_shown = lerpf(_xp_shown, _xp_target, weight)
	_sub_shown = lerpf(_sub_shown, _sub_target, weight)
	if before.distance_to(Vector3(_hp_shown, _xp_shown, _sub_shown)) > 0.0005:
		_aplicar()


# --- versão com arte ----------------------------------------------------------

func _montar() -> void:
	_nove_fatias("panel_brown", Rect2(Vector2.ZERO, FRAME_SIZE), UISkin.MARGEM_PAINEL)

	_fundo_retrato = ColorRect.new()
	_fundo_retrato.position = RETRATO.position + Vector2(9, 9)
	_fundo_retrato.size = RETRATO.size - Vector2(18, 18)
	_fundo_retrato.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fundo_retrato)

	_nove_fatias("buttonSquare_brown", RETRATO, 12)

	_rotulo_inicial = _texto("", 38, Design.TEXT_CLARO, RETRATO, HORIZONTAL_ALIGNMENT_CENTER, true)
	_rotulo_inicial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	_barra("hp", HP_RECT, "Red", "HP")
	_barra("xp", XP_RECT, "Blue", "EXP")
	_barra("sub", SUB_RECT, "Green", "")

	# Emblema por último para ficar por cima do retrato e da ponta das barras.
	_nove_fatias("buttonRound_brown", EMBLEMA, 14)
	_rotulo_nivel = _texto("1", 15, Design.TEXT_CLARO, EMBLEMA, HORIZONTAL_ALIGNMENT_CENTER, true)
	_rotulo_nivel.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	_rotulo_nome = _texto(
		_trainer_name, 22, Design.GOLD_CLARO,
		Rect2(NOME_POS, Vector2(FRAME_SIZE.x - NOME_POS.x - 12, 28)),
		HORIZONTAL_ALIGNMENT_LEFT, true
	)
	Design.sobre_o_mundo(_rotulo_nome, 5)


## Trilho + preenchimento + rótulo + valor de uma barra.
##
## O preenchimento é um NinePatchRect cuja largura é a razão: as pontas do
## desenho não deformam porque só o miolo estica. Abaixo de uma ponta e meia de
## largura ele some, senão as duas pontas se sobrepõem e viram um borrão.
func _barra(chave: String, rect: Rect2, cor: String, rotulo: String) -> void:
	_nove_fatias_tex(UISkin.textura_de_barra("Back"), rect, UISkin.MARGEM_BARRA)

	var frente := _nove_fatias_tex(UISkin.textura_de_barra(cor), rect, UISkin.MARGEM_BARRA)
	if frente != null:
		_preenchimento[chave] = frente

	if rotulo != "":
		_texto(
			rotulo, 11, Color(1, 1, 1, 0.72),
			Rect2(rect.position + Vector2(8, 0), Vector2(40, rect.size.y)),
			HORIZONTAL_ALIGNMENT_LEFT, false
		).vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	var valor := _texto(
		"", 13 if chave != "sub" else 11, VALUE_GOLD if chave == "hp" else Color(0.96, 0.97, 1.0),
		Rect2(rect.position + Vector2(0, 0), Vector2(rect.size.x - 10, rect.size.y)),
		HORIZONTAL_ALIGNMENT_RIGHT if chave != "hp" else HORIZONTAL_ALIGNMENT_CENTER, false
	)
	valor.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	Design.sobre_o_mundo(valor, 3)
	_valor[chave] = valor


func _nove_fatias(nome: String, rect: Rect2, margem: int) -> NinePatchRect:
	return _nove_fatias_tex(UISkin.textura(nome), rect, margem)


func _nove_fatias_tex(tex: Texture2D, rect: Rect2, margem: int) -> NinePatchRect:
	if tex == null:
		return null
	var node := NinePatchRect.new()
	node.texture = tex
	node.position = rect.position
	node.size = rect.size
	node.patch_margin_left = margem
	node.patch_margin_right = margem
	# As barras têm 18px de altura inteira: fatiar na vertical cortaria o brilho.
	node.patch_margin_top = margem if tex.get_height() > margem * 2 else 0
	node.patch_margin_bottom = node.patch_margin_top
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(node)
	return node


func _texto(valor: String, tamanho: int, cor: Color, rect: Rect2,
		alinhamento: int, destaque: bool) -> Label:
	var node := Design.label(valor, tamanho, cor, destaque)
	node.position = rect.position
	node.size = rect.size
	node.horizontal_alignment = alinhamento
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(node)
	return node


## Passa os valores atuais para os nós (ou pede um redesenho, no modo chapado).
func _aplicar() -> void:
	if not _com_arte:
		queue_redraw()
		return

	_atualizar_barra("hp", HP_RECT, _hp_shown, _hp_text)
	_atualizar_barra("xp", XP_RECT, _xp_shown, _xp_text)
	_atualizar_barra("sub", SUB_RECT, _sub_shown, "")

	if _rotulo_nome != null:
		_rotulo_nome.text = _trainer_name
	if _rotulo_nivel != null:
		_rotulo_nivel.text = str(_trainer_level)
	if _rotulo_inicial != null:
		_rotulo_inicial.text = _trainer_name.substr(0, 1).to_upper() if _trainer_name.length() > 0 else "?"
	if _fundo_retrato != null:
		var tint := DataManager.get_element_color(_leader_element)
		_fundo_retrato.color = Color(tint.r, tint.g, tint.b, 0.5)


func _atualizar_barra(chave: String, rect: Rect2, razao: float, texto: String) -> void:
	var frente: NinePatchRect = _preenchimento.get(chave, null)
	if frente != null:
		var minimo := float(UISkin.LARGURA_PONTA * 2)
		var largura := rect.size.x * clampf(razao, 0.0, 1.0)
		frente.visible = largura >= minimo * 0.75
		frente.size.x = maxf(minimo, largura)
	var rotulo: Label = _valor.get(chave, null)
	if rotulo != null:
		rotulo.text = texto if chave != "sub" else _sub_text


# --- versão chapada (sem o pacote de arte) ------------------------------------

func _draw() -> void:
	if _com_arte:
		return
	_desenhar_chapado()


func _desenhar_chapado() -> void:
	draw_rect(Rect2(Vector2.ZERO, FRAME_SIZE), Color(PANEL_FILL.r, PANEL_FILL.g, PANEL_FILL.b, 0.8))
	draw_rect(Rect2(Vector2.ZERO, FRAME_SIZE), EDGE_DARK, false, 2.0)
	_barra_chapada(HP_RECT, _hp_shown, Design.DANGER)
	_barra_chapada(XP_RECT, _xp_shown, Design.XP)
	_barra_chapada(SUB_RECT, _sub_shown, Design.HEALTH)

	var font := Design.ui_font()
	if font == null:
		font = ThemeDB.fallback_font
	draw_string(font, NOME_POS + Vector2(0, 20), _trainer_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, NAME_GOLD)
	draw_string(
		font, HP_RECT.position + Vector2(0, HP_RECT.size.y - 6), _hp_text,
		HORIZONTAL_ALIGNMENT_CENTER, HP_RECT.size.x, 14, VALUE_GOLD
	)
	draw_string(
		font, XP_RECT.position + Vector2(0, XP_RECT.size.y - 5), _xp_text,
		HORIZONTAL_ALIGNMENT_RIGHT, XP_RECT.size.x - 8, 12, Color(0.92, 0.96, 1.0)
	)
	draw_string(
		font, RETRATO.position + Vector2(0, RETRATO.size.y * 0.65),
		_trainer_name.substr(0, 1).to_upper(), HORIZONTAL_ALIGNMENT_CENTER, RETRATO.size.x, 36, NAME_GOLD
	)
	draw_string(
		font, EMBLEMA.position + Vector2(0, EMBLEMA.size.y * 0.7), str(_trainer_level),
		HORIZONTAL_ALIGNMENT_CENTER, EMBLEMA.size.x, 15, Color.WHITE
	)


func _barra_chapada(rect: Rect2, razao: float, cor: Color) -> void:
	draw_rect(rect, Color(0.05, 0.06, 0.08, 0.9))
	if razao > 0.002:
		draw_rect(Rect2(rect.position, Vector2(rect.size.x * razao, rect.size.y)), cor)
	draw_rect(rect, EDGE_DARK, false, 1.5)
