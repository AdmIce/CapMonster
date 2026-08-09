extends Control
## Criação do personagem: nome mais cinco escolhas de aparência, com preview 3D
## ao vivo.
##
## De propósito pequeno (o documento pede um editor de protótipo, não um editor
## completo). O preview usa a mesma classe PlayerAvatar do mundo, então o que
## aparece aqui é exatamente o que sai andando da vila.

const PREVIEW_SIZE := Vector2i(290, 330)
## Quantas opções cabem numa linha antes de quebrar. Com 4 personagens numa
## linha só, a coluna da direita passava da largura da janela.
const OPCOES_POR_LINHA := 3

var _appearance := {
	"body": 0,
	"hair": 0,
	"hair_color": 0,
	"skin": 0,
	"outfit": 0,
}

var _avatar: PlayerAvatar = null
var _pivot: Node3D = null
var _name_field: LineEdit = null
var _outfit_label: Label = null
var _option_rows: Dictionary = {}   ## chave -> Array[Button]
var _linhas: Dictionary = {}        ## chave -> Control da linha inteira
var _aviso_kit: Label = null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	Design.screen_root(self)
	_build()


func _process(delta: float) -> void:
	if _pivot != null:
		_pivot.rotation.y += delta * 0.45


func _build() -> void:
	var margin := Design.margin(Design.S_XL)
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(margin)

	var column := Design.vbox(Design.S_LG)
	margin.add_child(column)

	var header := Design.vbox(Design.S_XS)
	header.add_child(Design.label("ETAPA 1 DE 2", Design.FS_LABEL, Design.ACCENT))
	header.add_child(Design.heading("Quem é você?", Design.FS_TITLE, Design.TEXT_CLARO))
	column.add_child(header)

	var columns := Design.hbox(Design.S_XL)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(columns)

	columns.add_child(_build_preview())

	# As opções vão dentro de um ScrollContainer que ocupa a altura que sobrar.
	# Assim o rodapé com "Continuar" fica sempre visível, mesmo que a lista de
	# opções cresça (foi o que aconteceu quando PERSONAGEM virou 4 itens e
	# passou a ocupar duas linhas: o botão saiu para fora da janela).
	var rolagem := ScrollContainer.new()
	rolagem.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rolagem.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rolagem.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	columns.add_child(rolagem)

	var opcoes := _build_options()
	opcoes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rolagem.add_child(opcoes)

	var footer := Design.hbox(Design.S_MD)
	footer.size_flags_vertical = Control.SIZE_SHRINK_END
	column.add_child(footer)

	var back := Design.button("Voltar", "ghost")
	back.pressed.connect(func(): SceneFlow.goto_main_menu())
	footer.add_child(back)

	footer.add_child(Design.expander())

	var confirm := Design.button("Continuar", "primary")
	confirm.custom_minimum_size = Vector2(200, 44)
	confirm.pressed.connect(_on_confirm)
	footer.add_child(confirm)


func _build_preview() -> Control:
	var frame := Design.panel(Design.SURFACE_SUNKEN)
	# A prévia encolhe junto com a janela para não roubar a coluna de opções.
	Responsivo.caixa(frame, Vector2(PREVIEW_SIZE), Vector2(0.3, 0.55))

	var container := SubViewportContainer.new()
	container.stretch = true
	container.custom_minimum_size = Vector2(PREVIEW_SIZE)
	frame.add_child(container)

	var viewport := SubViewport.new()
	viewport.size = PREVIEW_SIZE
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_2X
	container.add_child(viewport)

	var scene_root := Node3D.new()
	viewport.add_child(scene_root)

	_pivot = Node3D.new()
	scene_root.add_child(_pivot)

	_avatar = PlayerAvatar.new()
	_avatar.apply_appearance(_appearance)
	_pivot.add_child(_avatar)

	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 4.6
	camera.position = Vector3(0, 0.9, 3.4)
	camera.rotation_degrees = Vector3(0, 0, 0)
	scene_root.add_child(camera)

	var key := DirectionalLight3D.new()
	key.light_energy = 1.5
	key.rotation_degrees = Vector3(-38, 34, 0)
	scene_root.add_child(key)

	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.5
	fill.light_color = Color("#8FA8C4")
	fill.rotation_degrees = Vector3(-14, -140, 0)
	scene_root.add_child(fill)

	return frame


func _build_options() -> Control:
	var panel := Design.panel(Design.SURFACE)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	var column := Design.vbox(Design.S_MD)
	panel.add_child(column)

	column.add_child(Design.label("NOME", Design.FS_CAPTION, Design.TEXT_DIM))
	_name_field = Design.line_edit("Treinador", 16)
	column.add_child(_name_field)

	column.add_child(Design.divider())

	column.add_child(_option_row("PERSONAGEM", "body", PlayerAvatar.BODY_TYPES))

	_aviso_kit = Design.caption("")
	_aviso_kit.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_aviso_kit)

	column.add_child(_option_row("CABELO", "hair", PlayerAvatar.HAIR_LABELS))
	column.add_child(_color_row("COR DO CABELO", "hair_color", PlayerAvatar.HAIR_COLORS))
	column.add_child(_color_row("TOM DE PELE", "skin", PlayerAvatar.SKIN_TONES))

	var outfit_names: Array[String] = []
	for outfit in PlayerAvatar.OUTFITS:
		outfit_names.append(outfit["name"])
	column.add_child(_option_row("ROUPA", "outfit", outfit_names))

	_outfit_label = Design.caption(_outfit_description())
	_outfit_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_outfit_label)

	_ajustar_ao_kit()
	return panel


## Esconde cabelo, cor, pele e roupa quando o personagem selecionado nao aceita
## nenhum dos quatro. Deixar os botoes visiveis e inertes seria pior que nao ter.
func _ajustar_ao_kit() -> void:
	if _aviso_kit == null:
		return
	var indice := int(_appearance.get("body", 0))
	var personalizavel := PlayerAvatar.aceita_personalizacao(indice)

	for chave in ["hair", "hair_color", "skin", "outfit"]:
		var linha: Control = _linhas.get(chave, null)
		if linha != null:
			linha.visible = personalizavel
	if _outfit_label != null:
		_outfit_label.visible = personalizavel

	_aviso_kit.visible = not personalizavel
	if not personalizavel:
		_aviso_kit.text = "Este personagem vem com visual proprio — cabelo, pele e roupa nao se aplicam a ele." 


func _option_row(caption: String, key: String, labels: Array) -> Control:
	var row := Design.vbox(Design.S_SM)
	row.add_child(Design.label(caption, Design.FS_CAPTION, Design.TEXT_DIM))

	var buttons := GridContainer.new()
	buttons.columns = mini(OPCOES_POR_LINHA, maxi(1, labels.size()))
	buttons.add_theme_constant_override("h_separation", Design.S_SM)
	buttons.add_theme_constant_override("v_separation", Design.S_SM)

	var created: Array[Button] = []
	for i in labels.size():
		var index := i
		var button := Design.button(String(labels[i]))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.clip_text = true
		button.pressed.connect(func(): _select(key, index))
		buttons.add_child(button)
		created.append(button)
	_option_rows[key] = created
	row.add_child(buttons)
	_linhas[key] = row
	_refresh_row(key)
	return row


func _color_row(caption: String, key: String, colors: Array) -> Control:
	var row := Design.vbox(Design.S_SM)
	row.add_child(Design.label(caption, Design.FS_CAPTION, Design.TEXT_DIM))

	var buttons := GridContainer.new()
	buttons.columns = mini(OPCOES_POR_LINHA, maxi(1, colors.size()))
	buttons.add_theme_constant_override("h_separation", Design.S_SM)
	buttons.add_theme_constant_override("v_separation", Design.S_SM)

	var created: Array[Button] = []
	for i in colors.size():
		var index := i
		var button := Design.button("")
		button.custom_minimum_size = Vector2(0, 34)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var swatch := ColorRect.new()
		swatch.color = colors[i]
		swatch.set_anchors_preset(Control.PRESET_FULL_RECT)
		swatch.offset_left = 8
		swatch.offset_right = -8
		swatch.offset_top = 8
		swatch.offset_bottom = -8
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(swatch)
		button.pressed.connect(func(): _select(key, index))
		buttons.add_child(button)
		created.append(button)
	_option_rows[key] = created
	row.add_child(buttons)
	_linhas[key] = row
	_refresh_row(key)
	return row


func _select(key: String, index: int) -> void:
	_appearance[key] = index
	_refresh_row(key)
	if key == "body":
		# Trocar de personagem pode trocar de kit, e cada kit aceita um conjunto
		# diferente de opções.
		_ajustar_ao_kit()
	if _avatar != null:
		_avatar.apply_appearance(_appearance)
	if _outfit_label != null:
		_outfit_label.text = _outfit_description()


func _refresh_row(key: String) -> void:
	var buttons: Array = _option_rows.get(key, [])
	var selected := int(_appearance.get(key, 0))
	for i in buttons.size():
		var button: Button = buttons[i]
		button.modulate = Color.WHITE if i == selected else Color(1, 1, 1, 0.55)
		button.add_theme_color_override(
			"font_color", Design.TEXT if i == selected else Design.TEXT_DIM
		)


func _outfit_description() -> String:
	var outfit: Dictionary = PlayerAvatar.OUTFITS[int(_appearance.get("outfit", 0))]
	return "%s — o padrão de quem sai da Vila Juncal pela primeira vez." % outfit["name"]


func _on_confirm() -> void:
	var chosen_name := _name_field.text.strip_edges()
	if chosen_name == "":
		chosen_name = "Treinador"
	GameManager.new_game(chosen_name, _appearance)
	SceneFlow.goto_intro()
