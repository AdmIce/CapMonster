class_name WelcomeBackPanel
extends CanvasLayer
## "Bem-vindo de volta": o que rendeu enquanto o jogo estava fechado.
##
## Só aparece quando o IdleManager realmente creditou alguma coisa. Se o tempo
## foi cortado no teto, a tela diz isso em vez de esconder - o jogador precisa
## saber que passou do limite para voltar antes na próxima.

signal fechado()


func _ready() -> void:
	layer = 70
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


func mostrar(resumo: Dictionary) -> void:
	if resumo.is_empty():
		return
	_construir(resumo)
	visible = true
	get_tree().paused = true
	AudioManager.tocar(&"vitoria")


func _construir(resumo: Dictionary) -> void:
	for filho in get_children():
		filho.queue_free()

	var raiz := Control.new()
	raiz.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(raiz)

	var scrim := ColorRect.new()
	scrim.color = Color(0.02, 0.03, 0.04, 0.78)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	raiz.add_child(scrim)

	var centro := CenterContainer.new()
	centro.set_anchors_preset(Control.PRESET_FULL_RECT)
	raiz.add_child(centro)

	var cartao := Design.panel(Design.SURFACE)
	Responsivo.largura(cartao, 480, 0.55)
	centro.add_child(cartao)

	var coluna := Design.vbox(Design.S_MD)
	cartao.add_child(coluna)

	coluna.add_child(Design.label("ENQUANTO VOCÊ ESTEVE FORA", Design.FS_LABEL, Design.ACCENT))
	coluna.add_child(Design.heading("Bem-vindo de volta", Design.FS_TITLE))

	var duracao := IdleManager.formatar_duracao(float(resumo.get("segundos", 0.0)))
	coluna.add_child(Design.body("Você ficou fora por %s." % duracao))
	if bool(resumo.get("limitado", false)):
		var teto := DataManager.progression.idle_max_offline_hours
		var aviso := Design.body(
			"O acúmulo para em %d horas — o que passou disso não foi contado." % int(teto)
		)
		aviso.add_theme_color_override("font_color", Design.GOLD)
		coluna.add_child(aviso)

	coluna.add_child(Design.divider())

	_linha(coluna, "Ouro", "+%d" % int(resumo.get("ouro", 0)), Design.GOLD)
	_linha(coluna, "XP de treinador", "+%d" % int(resumo.get("xp_treinador", 0)), Design.XP)
	_linha(
		coluna, "XP por criatura da equipe",
		"+%d" % int(resumo.get("xp_criatura", 0)), Design.XP
	)
	var material_qtd := int(resumo.get("material_qtd", 0))
	if material_qtd > 0:
		_linha(
			coluna,
			DataManager.get_item_name(String(resumo.get("material_id", ""))),
			"+%d" % material_qtd,
			DataManager.get_item_color(String(resumo.get("material_id", "")))
		)

	var subiram: Array = resumo.get("subiram_de_nivel", [])
	if not subiram.is_empty():
		coluna.add_child(Design.divider())
		coluna.add_child(Design.label("SUBIU DE NÍVEL", Design.FS_CAPTION, Design.TEXT_DIM))
		for texto in subiram:
			coluna.add_child(Design.label(String(texto), Design.FS_BODY, Design.ACCENT))

	coluna.add_child(Design.spacer(Design.S_SM))
	var botao := Design.button("Continuar", "primary")
	botao.pressed.connect(_fechar)
	coluna.add_child(botao)


func _linha(pai: VBoxContainer, rotulo: String, valor: String, cor: Color) -> void:
	var linha := Design.hbox(Design.S_MD)
	var nome := Design.label(rotulo, Design.FS_BODY, Design.TEXT_MUTED)
	nome.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	linha.add_child(nome)
	linha.add_child(Design.label(valor, Design.FS_BODY, cor))
	pai.add_child(linha)


func _fechar() -> void:
	visible = false
	get_tree().paused = false
	fechado.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("cancel") or event.is_action_pressed("interact")):
		get_viewport().set_input_as_handled()
		_fechar()
