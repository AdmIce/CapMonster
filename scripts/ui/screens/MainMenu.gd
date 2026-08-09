extends Control
## Tela de título. "Continuar" só fica ativo quando existe save de verdade, e
## mostra o que tem dentro dele para o jogador não ficar adivinhando.

var _continue_button: Button = null
var _settings_overlay: Control = null
## Node, não Control: o painel de online é um CanvasLayer, para ficar por cima
## do vídeo de fundo sem entrar no layout da coluna.
var _online_overlay: Node = null
var _update_overlay: Node = null
var _estado_rede: Label = null
var _botoes_de_jogo: Array[Button] = []


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

	# Com servidor oficial nao ha o que escolher: o jogo entra sozinho. O botao
	# vira "quem esta online", e a linha abaixo dele diz o estado da conexao.
	var online := Design.button(
		"Quem está online" if Rede.tem_servidor_oficial() else "Jogar junto", "default", true
	)
	online.pressed.connect(_on_online)
	right.add_child(online)

	_estado_rede = Design.sobre_o_mundo(Design.caption("", Design.TEXT_CLARO_MUTED), 3)
	_estado_rede.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	right.add_child(_estado_rede)

	var settings := Design.button("Configurações", "default", true)
	settings.pressed.connect(_on_settings)
	right.add_child(settings)

	var quit := Design.button("Sair", "default", true)
	quit.pressed.connect(_on_quit)
	right.add_child(quit)

	_botoes_de_jogo = [_continue_button, new_game]
	_refresh_save_state(save_info)
	_procurar_atualizacao()
	_ligar_no_servidor()

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


## Entra no servidor do jogo assim que o menu abre.
##
## Sem modo offline de proposito: o mundo e compartilhado, e deixar jogar solto
## faria cada um progredir num mundo diferente, sem nada do que fizeram junto se
## acumular. Enquanto nao conecta, os botoes de jogar ficam desligados e a linha
## de estado diz o porque - travar sem explicar seria pior que travar.
func _ligar_no_servidor() -> void:
	if not Rede.tem_servidor_oficial():
		if _estado_rede != null:
			_estado_rede.visible = false
		return
	Rede.estado_mudou.connect(_atualizar_estado_da_rede)
	_atualizar_estado_da_rede()
	Rede.entrar_no_oficial()


func _atualizar_estado_da_rede() -> void:
	if _estado_rede == null or not is_inside_tree():
		return

	var pronto := Rede.online()
	for botao in _botoes_de_jogo:
		if botao != null and is_instance_valid(botao):
			# "Continuar" tem a propria regra (so com save); a rede so pode piorar.
			botao.disabled = not pronto or botao.get_meta("sem_save", false)

	match Rede.estado:
		Rede.Estado.CONECTADO, Rede.Estado.HOSPEDANDO:
			_estado_rede.text = "Conectado  ·  %d no mundo" % maxi(1, Rede.jogadores.size())
			_estado_rede.add_theme_color_override("font_color", Design.HEALTH)
		Rede.Estado.CONECTANDO:
			_estado_rede.text = "Conectando ao servidor..."
			_estado_rede.add_theme_color_override("font_color", Design.TEXT_CLARO_MUTED)
		_:
			_estado_rede.text = "Servidor fora do ar. Tentando de novo..."
			_estado_rede.add_theme_color_override("font_color", Design.DANGER)
			_tentar_de_novo()


## Nova tentativa depois de uma pausa. Sem isto, quem abriu o jogo antes do
## servidor voltar ficaria travado no menu ate fechar e abrir.
func _tentar_de_novo() -> void:
	await get_tree().create_timer(5.0).timeout
	if is_inside_tree() and not Rede.online():
		Rede.entrar_no_oficial()


func _refresh_save_state(info: Label) -> void:
	var metadata := SaveManager.save_metadata()
	if metadata.is_empty():
		_continue_button.disabled = true
		_continue_button.set_meta("sem_save", true)
		info.text = "Nenhum save encontrado. Comece um jogo novo."
		return
	_continue_button.set_meta("sem_save", false)
	_continue_button.disabled = not Rede.online() and Rede.tem_servidor_oficial()
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


## O menu principal e o unico lugar onde parar tudo para atualizar nao custa
## nada: nao ha partida em andamento nem progresso por salvar.
func _procurar_atualizacao() -> void:
	Atualizador.verificacao_terminou.connect(_ao_verificar, CONNECT_ONE_SHOT)
	Atualizador.verificar()


func _ao_verificar(disponivel: bool, info: Dictionary) -> void:
	if not disponivel or not is_inside_tree():
		return
	if _update_overlay != null and is_instance_valid(_update_overlay):
		return
	_update_overlay = UpdatePanel.mostrar(self, info)


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
