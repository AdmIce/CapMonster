extends Control
## Tela de título. "Continuar" só fica ativo quando existe save de verdade, e
## mostra o que tem dentro dele para o jogador não ficar adivinhando.

var _continue_button: Button = null
var _settings_overlay: Control = null
## Node, não Control: o painel de online é um CanvasLayer, para ficar por cima
## do vídeo de fundo sem entrar no layout da coluna.
var _online_overlay: Node = null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	Design.screen_root(self)
	_build()


func _build() -> void:
	# Antes de tudo, para ficar atrás da interface inteira.
	add_child(VideoBackdrop.criar("mountain-cabin"))

	var margin := Design.margin(Design.S_HUGE)
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(margin)

	var columns := Design.hbox(Design.S_HUGE)
	margin.add_child(columns)

	# Coluna da esquerda: identidade.
	var left := Design.vbox(Design.S_SM)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.alignment = BoxContainer.ALIGNMENT_CENTER
	columns.add_child(left)

	# A logo já traz o nome e o subtítulo desenhados, então ela substitui as duas
	# linhas de texto. Sem o arquivo, o título volta a ser escrito — com contorno,
	# porque o fundo é vídeo e vai de céu claro a mata escura no mesmo laço.
	var logo := Logo.criar(520.0)
	if logo != null:
		logo.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		left.add_child(logo)
	else:
		left.add_child(Design.sobre_o_mundo(
			Design.label("MONSTER IDLE RPG", Design.FS_LABEL, Design.GOLD_CLARO), 3
		))
		left.add_child(Design.sobre_o_mundo(
			Design.label("CAPMONSTER", Design.FS_DISPLAY, Design.TEXT_CLARO, true), 8
		))

	left.add_child(Design.spacer(Design.S_SM))
	var blurb := Design.body(
		"Vincule criaturas de éter, monte uma equipe de três e siga para o norte, "
		+ "passando de Valverde até a serra que engoliu a última expedição.",
		Design.TEXT_CLARO_MUTED
	)
	Design.sobre_o_mundo(blurb, 4)
	Responsivo.largura(blurb, 400, 0.42)
	left.add_child(blurb)

	# Coluna da direita: ações.
	var right := Design.vbox(Design.S_MD)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	Responsivo.largura(right, 320, 0.32)
	columns.add_child(right)

	_continue_button = Design.button("Continuar", "primary", true)
	_continue_button.pressed.connect(_on_continue)
	right.add_child(_continue_button)

	var save_info := Design.sobre_o_mundo(Design.caption("", Design.TEXT_CLARO_MUTED), 3)
	right.add_child(save_info)

	right.add_child(Design.spacer(Design.S_SM))

	var new_game := Design.button("Novo jogo", "default", true)
	new_game.pressed.connect(_on_new_game)
	right.add_child(new_game)

	var online := Design.button("Jogar junto", "default", true)
	online.pressed.connect(_on_online)
	right.add_child(online)

	var settings := Design.button("Configurações", "default", true)
	settings.pressed.connect(_on_settings)
	right.add_child(settings)

	var quit := Design.button("Sair", "default", true)
	quit.pressed.connect(_on_quit)
	right.add_child(quit)

	_refresh_save_state(save_info)

	var version := Design.caption(
		"v%s  ·  protótipo" % ProjectSettings.get_setting("application/config/version", "0.0.0"),
		Design.TEXT_CLARO_DIM
	)
	Design.sobre_o_mundo(version, 3)
	version.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	version.offset_left = -260
	version.offset_top = -32
	version.offset_right = -Design.S_XL
	version.offset_bottom = -Design.S_MD
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(version)


func _refresh_save_state(info: Label) -> void:
	var metadata := SaveManager.save_metadata()
	if metadata.is_empty():
		_continue_button.disabled = true
		info.text = "Nenhum save encontrado. Comece um jogo novo."
		return
	_continue_button.disabled = false
	var minutes := int(float(metadata.get("playtime", 0.0)) / 60.0)
	info.text = "%s  ·  Nv.%d  ·  %s  ·  %d criatura(s)  ·  %d min jogados" % [
		metadata.get("name", "Treinador"),
		int(metadata.get("level", 1)),
		DataManager.get_map_name(String(metadata.get("map", ""))),
		int(metadata.get("creatures", 0)),
		minutes,
	]


# --- ações --------------------------------------------------------------------

func _on_continue() -> void:
	if not GameManager.continue_game():
		Notify.bad("Não foi possível ler esse save.")
		return
	GameManager.begin_session()
	SceneFlow.goto_world()


func _on_new_game() -> void:
	if SaveManager.has_save():
		_confirm_overwrite()
		return
	SceneFlow.goto_character_creation()


func _confirm_overwrite() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Começar um jogo novo?"
	dialog.dialog_text = "Isso vai sobrescrever o save atual quando você chegar ao mundo."
	dialog.ok_button_text = "Começar novo"
	dialog.cancel_button_text = "Continuar o antigo"
	add_child(dialog)
	dialog.confirmed.connect(func():
		SaveManager.delete_save()
		SceneFlow.goto_character_creation()
	)
	dialog.popup_centered()


func _on_online() -> void:
	if _online_overlay != null and is_instance_valid(_online_overlay):
		return
	_online_overlay = OnlinePanel.new()
	add_child(_online_overlay)


func _on_settings() -> void:
	if _settings_overlay != null and is_instance_valid(_settings_overlay):
		return
	_settings_overlay = SettingsPanel.new()
	add_child(_settings_overlay)


func _on_quit() -> void:
	GameManager.quit_game()
