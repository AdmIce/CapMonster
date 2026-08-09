class_name HUD
extends CanvasLayer
## HUD do mundo.
##
## De propósito enxuto: o que importa olhar é o cenário. Fica na tela só o que
## muda durante a exploração - o painel do treinador, o ouro, o estado da equipe
## ativa e o aviso de interação.
##
## A barra de atalhos de baixo (Equipe / Criaturas / Mochila / Mapa / Missões)
## ainda não existe porque essas telas não existem. Botão aparece quando a tela
## por trás dele aparecer.

const TEAM_CARD_WIDTH := 170
const MINIMAPA_TAMANHO := 190

var _player: PlayerData = null
var _controller: PlayerController = null

var _frame: PlayerFrame = null
var _gold_label: Label = null
var _map_label: Label = null

var _prompt: PanelContainer = null
var _prompt_label: Label = null
var _team_row: HBoxContainer = null
var _fps_label: Label = null
var _minimapa: MapView = null
var _banner: Control = null
var _banner_title: Label = null
var _banner_subtitle: Label = null

var _auto_button: Button = null
var _auto_status: Label = null
var _autopilot: AutoPilot = null
var _inventory_button: Button = null
var _inventory: InventoryPanel = null

var _chat: ChatPanel = null
var _team_widgets: Array = []
var _health_style: StyleBoxFlat = null
var _health_low_style: StyleBoxFlat = null


func _ready() -> void:
	layer = 10
	_health_style = Design.accent_bar_style(Design.HEALTH, Design.R_SM)
	_health_low_style = Design.accent_bar_style(Design.HEALTH_LOW, Design.R_SM)
	_build()


func bind(player: PlayerData, controller: PlayerController) -> void:
	_player = player
	_controller = controller
	_chat.ligar(controller)

	_frame.bind(player)
	player.gold_changed.connect(func(_g): _refresh_wallet())
	player.team_changed.connect(_rebuild_team)
	player.collection_changed.connect(_rebuild_team)

	if controller != null:
		controller.interaction_target_changed.connect(_on_interaction_target)

	_map_label.text = DataManager.get_map_name(player.current_map)
	if _minimapa != null:
		_minimapa.configurar(DataManager.get_map(player.current_map), controller, false)
	_refresh_wallet()
	_rebuild_team()
	set_prompt("")


# --- construção ---------------------------------------------------------------

func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var margin := Design.margin(Design.S_MD)
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(margin)

	var stack := Design.vbox(Design.S_MD)
	margin.add_child(stack)

	var top := Design.hbox(Design.S_MD)
	stack.add_child(top)

	_frame = PlayerFrame.new()
	_frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top.add_child(_frame)

	top.add_child(Design.expander())
	top.add_child(_build_wallet())

	stack.add_child(Design.expander())

	var bottom := Design.hbox(Design.S_MD)
	stack.add_child(bottom)

	# Canto de baixo à esquerda, empilhado: conversa em cima, equipe embaixo.
	var canto_esquerdo := Design.vbox(Design.S_SM)
	canto_esquerdo.size_flags_vertical = Control.SIZE_SHRINK_END
	bottom.add_child(canto_esquerdo)

	_chat = ChatPanel.new()
	_chat.name = "Chat"
	canto_esquerdo.add_child(_chat)

	_team_row = Design.hbox(Design.S_SM)
	canto_esquerdo.add_child(_team_row)
	bottom.add_child(Design.expander())

	var canto := Design.vbox(Design.S_XS)
	canto.size_flags_vertical = Control.SIZE_SHRINK_END
	bottom.add_child(canto)

	# O minimapa ganha a mesma moldura de pergaminho dos painéis, senão ele fica
	# como um retângulo preto colado na tela.
	var moldura_mapa := Design.card(Design.GOLD)
	canto.add_child(moldura_mapa)

	_minimapa = MapView.new()
	_minimapa.custom_minimum_size = Vector2(MINIMAPA_TAMANHO, MINIMAPA_TAMANHO)
	moldura_mapa.add_child(_minimapa)

	var dica_mapa := Design.sobre_o_mundo(Design.caption("M — mapa", Design.TEXT_CLARO_MUTED), 3)
	dica_mapa.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	canto.add_child(dica_mapa)

	_fps_label = Design.sobre_o_mundo(Design.caption("", Design.TEXT_CLARO_DIM), 3)
	_fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	canto.add_child(_fps_label)

	root.add_child(_build_prompt())
	root.add_child(_build_banner())

	# O HUD inteiro é decorativo e não deve engolir clique...
	Design.ignore_mouse(root)
	# ...menos o chat, que é o único painel do HUD com texto para ler e digitar.
	_chat.aplicar_estado()
	# ...menos os dois botões, que são os únicos controles da tela.
	for botao in [_auto_button, _inventory_button]:
		botao.mouse_filter = Control.MOUSE_FILTER_STOP
		# Sem foco de teclado: um botão focado é acionado por `ui_accept`, que o
		# Godot deixa em Espaço/Enter - as mesmas teclas de interagir. Com foco,
		# andar pelo mundo apertando Espaço ficava clicando no botão sozinho.
		botao.focus_mode = Control.FOCUS_NONE


func _build_wallet() -> Control:
	var column := Design.vbox(Design.S_XS)
	column.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	column.alignment = BoxContainer.ALIGNMENT_BEGIN

	var card := Design.panel(Color(0.055, 0.067, 0.082, 0.88))
	column.add_child(card)

	var row := Design.hbox(Design.S_SM)
	card.add_child(row)

	var coin := Panel.new()
	coin.custom_minimum_size = Vector2(12, 12)
	coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	coin.add_theme_stylebox_override("panel", Design.panel_style(Design.GOLD, 6, 0, Design.GOLD))
	row.add_child(coin)

	_gold_label = Design.label("0", Design.FS_BODY, Design.TEXT)
	row.add_child(_gold_label)

	_map_label = Design.sobre_o_mundo(Design.caption("", Design.TEXT_CLARO_MUTED), 3)
	_map_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	column.add_child(_map_label)

	_auto_button = Design.button("AUTO: desligado")
	_auto_button.custom_minimum_size = Vector2(170, 36)
	_auto_button.pressed.connect(_on_auto_pressed)
	column.add_child(_auto_button)

	_inventory_button = Design.button("Mochila  (I)")
	_inventory_button.custom_minimum_size = Vector2(170, 36)
	_inventory_button.pressed.connect(_on_inventory_pressed)
	column.add_child(_inventory_button)

	_auto_status = Design.sobre_o_mundo(Design.caption("", Design.TEXT_CLARO_MUTED), 3)
	_auto_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	column.add_child(_auto_status)

	return column


func _build_prompt() -> Control:
	var anchor := Control.new()
	anchor.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	anchor.offset_top = -152
	anchor.offset_bottom = -108

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	anchor.add_child(center)

	_prompt = Design.card(Design.GOLD)
	center.add_child(_prompt)

	var row := Design.hbox(Design.S_SM)
	_prompt.add_child(row)

	var key_panel := PanelContainer.new()
	var key_style := Design.panel_style(Design.ACCENT, Design.R_SM, 0)
	key_style.content_margin_left = Design.S_SM
	key_style.content_margin_right = Design.S_SM
	key_style.content_margin_top = 1
	key_style.content_margin_bottom = 1
	key_panel.add_theme_stylebox_override("panel", key_style)
	key_panel.add_child(Design.label("E", Design.FS_CAPTION, Design.BACKGROUND))
	row.add_child(key_panel)

	_prompt_label = Design.label("", Design.FS_LABEL, Design.TEXT)
	row.add_child(_prompt_label)

	return anchor


func _build_banner() -> Control:
	_banner = Control.new()
	_banner.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_banner.offset_top = 170
	_banner.offset_bottom = 250
	_banner.modulate.a = 0.0

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_banner.add_child(center)

	var column := Design.vbox(2)
	center.add_child(column)

	_banner_title = Design.sobre_o_mundo(
		Design.label("", Design.FS_TITLE, Design.TEXT_CLARO, true), 6
	)
	_banner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_banner_title)

	_banner_subtitle = Design.sobre_o_mundo(
		Design.label("", Design.FS_LABEL, Design.TEXT_CLARO_MUTED), 4
	)
	_banner_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_banner_subtitle)

	return _banner


# --- atualização --------------------------------------------------------------

func _refresh_wallet() -> void:
	if _player != null:
		_gold_label.text = str(_player.gold)
		_map_label.text = DataManager.get_map_name(_player.current_map)


## Verdadeiro quando o jogador está digitando: quem escuta tecla no mundo
## precisa se calar, senão "mapa" abre o mapa no meio da frase.
func chat_aberto() -> bool:
	return _chat != null and _chat.aberto()


func _rebuild_team() -> void:
	if _player == null or _team_row == null:
		return
	for child in _team_row.get_children():
		_team_row.remove_child(child)
		child.queue_free()
	_team_widgets.clear()

	var members := _player.team()
	for i in PlayerData.TEAM_SIZE:
		_team_row.add_child(_build_team_card(members[i] if i < members.size() else null, i))
	Design.ignore_mouse(_team_row)


func _build_team_card(creature: CreatureData, slot: int) -> Control:
	var destaque := Design.TEXT_MUTED
	if creature != null:
		destaque = DataManager.get_rarity_color(creature.rarity())
	var card := Design.card(destaque, slot == 0)
	card.custom_minimum_size = Vector2(TEAM_CARD_WIDTH, 0)
	card.size_flags_vertical = Control.SIZE_SHRINK_END

	var column := Design.vbox(3)
	card.add_child(column)

	if creature == null:
		column.add_child(Design.label("Slot %d" % (slot + 1), Design.FS_LABEL, Design.TEXT_MUTED))
		column.add_child(Design.caption("vazio", Design.TEXT_MUTED))
		_team_widgets.append(null)
		return card

	var top := Design.hbox(Design.S_XS)
	var element_dot := Panel.new()
	element_dot.custom_minimum_size = Vector2(8, 8)
	element_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	element_dot.add_theme_stylebox_override(
		"panel", Design.panel_style(DataManager.get_element_color(creature.element()), 4, 0)
	)
	top.add_child(element_dot)

	var name_label := Design.label(creature.display_name(), Design.FS_LABEL, Design.TEXT)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	top.add_child(name_label)
	top.add_child(Design.label("Nv.%d" % creature.level, Design.FS_CAPTION, Design.TEXT_MUTED))
	column.add_child(top)

	var hp_bar := Design.meter(Design.HEALTH, 5)
	hp_bar.value = creature.hp_ratio()
	column.add_child(hp_bar)

	var hp_text := Design.caption("%d / %d" % [creature.current_hp, creature.max_hp()])
	column.add_child(hp_text)

	_team_widgets.append({ "creature": creature, "bar": hp_bar, "text": hp_text, "low": false })
	return card


func _process(_delta: float) -> void:
	if _fps_label != null:
		var show_fps := bool(SaveManager.get_setting("show_fps", false))
		_fps_label.visible = show_fps
		if show_fps:
			_fps_label.text = "%d FPS" % Engine.get_frames_per_second()

	for widget in _team_widgets:
		if widget == null:
			continue
		var creature: CreatureData = widget["creature"]
		if creature == null:
			continue
		var bar: ProgressBar = widget["bar"]
		var ratio := creature.hp_ratio()
		bar.value = lerpf(bar.value, ratio, 0.2)
		var is_low := ratio <= 0.3
		if is_low != bool(widget["low"]):
			widget["low"] = is_low
			bar.add_theme_stylebox_override("fill", _health_low_style if is_low else _health_style)
		(widget["text"] as Label).text = "%d / %d" % [creature.current_hp, creature.max_hp()]


# --- público ------------------------------------------------------------------

func set_prompt(text: String) -> void:
	if _prompt == null:
		return
	_prompt.visible = text != ""
	_prompt_label.text = text


func _on_interaction_target(target: Interactable) -> void:
	set_prompt(target.prompt_label() if target != null else "")


# --- modo automático ----------------------------------------------------------

func bind_autopilot(autopilot: AutoPilot) -> void:
	_autopilot = autopilot
	autopilot.enabled_changed.connect(_on_auto_changed)
	autopilot.state_changed.connect(func(descricao: String): _auto_status.text = descricao)
	_on_auto_changed(autopilot.is_enabled())


func _on_auto_pressed() -> void:
	if _autopilot != null:
		_autopilot.toggle()


func bind_inventory(panel: InventoryPanel) -> void:
	_inventory = panel


func _on_inventory_pressed() -> void:
	if _inventory != null:
		_inventory.alternar()


func _on_auto_changed(ativo: bool) -> void:
	_auto_button.text = "AUTO: ligado" if ativo else "AUTO: desligado"
	_auto_button.add_theme_color_override("font_color", Design.ACCENT_HOVER if ativo else Design.TEXT_MUTED)
	if not ativo:
		_auto_status.text = ""


func show_map_banner(title: String, subtitle: String) -> void:
	if _banner == null:
		return
	_banner_title.text = title.to_upper()
	_banner_subtitle.text = subtitle
	var tween := create_tween()
	tween.tween_property(_banner, "modulate:a", 1.0, 0.4)
	tween.tween_interval(2.2)
	tween.tween_property(_banner, "modulate:a", 0.0, 0.8)
