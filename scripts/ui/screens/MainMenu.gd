extends Control
## Tela de título. "Jogar" abre a seleção de personagem, onde o jogador continua
## um save ou cria outro; a linha abaixo mostra quantos personagens existem.

var _jogar_button: Button = null
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

	_jogar_button = Design.button("Jogar", "primary", true)
	_jogar_button.pressed.connect(_on_jogar)
	right.add_child(_jogar_button)

	var save_info := Design.sobre_o_mundo(Design.caption("", Design.TEXT_CLARO_MUTED), 3)
	right.add_child(save_info)

	right.add_child(Design.spacer(Design.S_SM))

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

	_botoes_de_jogo = [_jogar_button]
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
			botao.disabled = not pronto

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
	var slots := SaveManager.save_slots()
	# "Jogar" só a rede pode atrasar; sem personagem a tela de seleção já explica
	# e leva para a criação. Nada aqui trava sozinho.
	_jogar_button.disabled = not Rede.online() and Rede.tem_servidor_oficial()
	if slots.is_empty():
		info.text = "Nenhum personagem neste dispositivo. Crie o primeiro."
	else:
		var nomes: Array[String] = []
		for meta in slots:
			nomes.append(String(meta.get("name", "Treinador")))
		info.text = "%d personagem(ns)  ·  %s" % [slots.size(), ", ".join(nomes)]


# --- ações --------------------------------------------------------------------

func _on_jogar() -> void:
	SceneFlow.goto_character_select()


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
