class_name SettingsPanel
extends Control
## Settings overlay, reusable from the main menu and the in-game pause menu.
## Every control here changes something observable immediately and is persisted
## to user://settings.json. Options with nothing to act on yet are not shown.

signal closed()


func _ready() -> void:
	# `set_anchors_and_offsets_preset`, e nao `set_anchors_preset`: o segundo
	# **preserva o retangulo atual** ajustando os offsets. Chamado aqui, com o no
	# ja na arvore e ainda com tamanho zero, ele grava o zero para sempre -- foi
	# o que deixou o painel de configuracoes encolhido no canto da tela.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()


## Largura de uma coluna de opções. Duas cabem lado a lado a partir de uma
## janela de ~1100; abaixo disso elas empilham.
const LARGURA_COLUNA := 340.0
const LARGURA_DUAS_COLUNAS := 1100.0


func _build() -> void:
	var scrim := ColorRect.new()
	scrim.color = Color(0, 0, 0, 0.55)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(scrim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var duas := Responsivo.tela(self).x >= LARGURA_DUAS_COLUNAS

	var card := Design.panel(Design.SURFACE)
	# Altura limitada de propósito. Antes o painel só crescia, e bastou entrar a
	# seção de câmera para o botão "Fechar" sair pela borda de baixo da tela --
	# sem rolagem e sem jeito de alcançar. Agora o que passa disto rola.
	Responsivo.caixa(
		card,
		Vector2(LARGURA_COLUNA * 2.0 + 64.0 if duas else LARGURA_COLUNA + 48.0, 620.0),
		Vector2(0.94, 0.88)
	)
	center.add_child(card)

	var moldura := Design.vbox(Design.S_MD)
	card.add_child(moldura)

	moldura.add_child(Design.heading("Configurações"))
	moldura.add_child(Design.divider())

	var conteudo: Control
	if duas:
		var lado_a_lado := Design.hbox(Design.S_LG)
		lado_a_lado.add_child(_coluna_video())
		lado_a_lado.add_child(_coluna_camera())
		conteudo = lado_a_lado
	else:
		var empilhado := Design.vbox(Design.S_LG)
		empilhado.add_child(_coluna_video())
		empilhado.add_child(_coluna_camera())
		conteudo = empilhado

	moldura.add_child(Responsivo.rolagem(conteudo))

	moldura.add_child(Design.divider())
	# Fora da rolagem: o botão de sair não pode depender de o jogador descobrir
	# que precisa rolar até o fim para achá-lo.
	var close := Design.button("Fechar", "primary")
	close.pressed.connect(_close)
	moldura.add_child(close)


## Título de seção. Existe para o painel ser lido como três assuntos e não como
## uma lista de dezoito controles soltos.
func _secao(texto: String) -> Label:
	return Design.label(texto.to_upper(), Design.FS_LABEL, Design.GOLD)


func _coluna_video() -> VBoxContainer:
	var column := Design.vbox(Design.S_MD)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.custom_minimum_size = Vector2(LARGURA_COLUNA, 0)

	column.add_child(_secao("Vídeo"))

	var fullscreen := Design.check("Tela cheia", bool(SaveManager.get_setting("fullscreen", false)))
	fullscreen.toggled.connect(func(on): SaveManager.set_setting("fullscreen", on))
	column.add_child(fullscreen)

	var vsync := Design.check("V-Sync", bool(SaveManager.get_setting("vsync", true)))
	vsync.toggled.connect(func(on): SaveManager.set_setting("vsync", on))
	column.add_child(vsync)

	var fps := Design.check("Mostrar FPS", bool(SaveManager.get_setting("show_fps", false)))
	fps.toggled.connect(func(on): SaveManager.set_setting("show_fps", on))
	column.add_child(fps)

	_montar_grafico(column)

	column.add_child(Design.divider())
	column.add_child(_secao("Interface"))

	var escala_valor := Responsivo.escala_salva()
	var escala_rotulo := Design.label(
		"Tamanho da interface  %d%%" % int(round(escala_valor * 100.0)),
		Design.FS_LABEL, Design.TEXT_MUTED
	)
	column.add_child(escala_rotulo)

	var escala := HSlider.new()
	escala.min_value = Responsivo.ESCALA_MIN
	escala.max_value = Responsivo.ESCALA_MAX
	escala.step = 0.05
	escala.value = escala_valor
	escala.custom_minimum_size = Vector2(0, 22)
	# Aplica ao vivo: escolher o tamanho às cegas e só ver o resultado depois de
	# fechar seria adivinhação.
	escala.value_changed.connect(func(valor: float):
		escala_rotulo.text = "Tamanho da interface  %d%%" % int(round(valor * 100.0))
		SaveManager.set_setting(Responsivo.CHAVE_ESCALA, valor)
		Responsivo.aplicar_escala(self, valor)
	)
	column.add_child(escala)
	return column


func _coluna_camera() -> VBoxContainer:
	var column := Design.vbox(Design.S_MD)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.custom_minimum_size = Vector2(LARGURA_COLUNA, 0)

	column.add_child(_secao("Câmera"))
	_montar_camera(column)

	column.add_child(Design.divider())

	var zoom_value := float(SaveManager.get_setting("camera_zoom", 1.0))
	var zoom_label := Design.label("Zoom da câmera  %.2fx" % zoom_value, Design.FS_LABEL, Design.TEXT_MUTED)
	column.add_child(zoom_label)

	var slider := HSlider.new()
	slider.min_value = 0.7
	slider.max_value = 1.6
	slider.step = 0.05
	slider.value = zoom_value
	slider.custom_minimum_size = Vector2(0, 22)
	slider.value_changed.connect(func(value: float):
		zoom_label.text = "Zoom da câmera  %.2fx" % value
		SaveManager.set_setting("camera_zoom", value)
		_apply_camera_zoom(value)
	)
	column.add_child(slider)
	return column


## Qualidade alta = Forward+ (Vulkan). Fica desligada por padrao porque nem toda
## maquina consegue rodar, e um jogo que nao abre e pior que um jogo mais simples.
## Trocar reinicia: o renderizador e escolhido antes do primeiro quadro existir.
func _montar_grafico(column: VBoxContainer) -> void:
	# A caixinha mostra o que foi **escolhido**, não o que está rodando: no
	# editor os dois divergem, e ver a opção voltar sozinha parecia bug de save.
	var alta := Design.check("Qualidade alta", Renderizador.escolhido() == Renderizador.QUALIDADE)

	# Dizer em qual modo o jogo **está** agora, e não só qual foi escolhido.
	# Sem isto, "liguei e não mudou nada" não tem como ser respondido: o jogador
	# não vê diferença entre a troca não ter pegado e a placa não aguentar.
	var atual := Design.label(
		"Rodando agora em: %s" % ("Qualidade alta (Vulkan)" if Renderizador.em_qualidade() else "Compatível (OpenGL)"),
		Design.FS_LABEL, Design.GOLD
	)
	column.add_child(atual)

	var aviso := Design.caption(
		"Luz e sombra melhores. Exige placa de vídeo com Vulkan — se o jogo não abrir "
		+ "depois de ligar, ele volta sozinho para o modo compatível."
	)
	aviso.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	alta.toggled.connect(func(ligado: bool): _confirmar_grafico(alta, aviso, ligado))
	column.add_child(alta)
	column.add_child(aviso)


## Trocar o renderizador só vale reiniciando, então o jogo pergunta e reinicia
## na hora. Pedir para o jogador fechar e abrir na mão é pedir para ele descobrir
## depois que não pegou.
func _confirmar_grafico(caixa: CheckButton, aviso: Label, ligado: bool) -> void:
	var modo := Renderizador.QUALIDADE if ligado else Renderizador.COMPATIBILIDADE
	if Renderizador.escolhido() == modo and Renderizador.em_qualidade() == ligado:
		return

	var dialogo := ConfirmationDialog.new()
	dialogo.title = "Reiniciar o jogo?"
	dialogo.dialog_text = (
		"Ligar a qualidade alta precisa reiniciar o CapMonster agora.\nSeu progresso já está salvo."
		if ligado else
		"Voltar para o modo compatível precisa reiniciar o CapMonster agora."
	)
	dialogo.ok_button_text = "Reiniciar agora"
	dialogo.cancel_button_text = "Agora não"
	add_child(dialogo)

	dialogo.confirmed.connect(func():
		if not Renderizador.aplicar_agora(modo):
			aviso.text = "Gravado. Rodando pelo editor, isso só vale no jogo exportado."
			aviso.add_theme_color_override("font_color", Design.GOLD)
	)
	# Desmarcar de volta ao cancelar, senão a caixinha mente sobre o estado.
	dialogo.canceled.connect(func(): caixa.set_pressed_no_signal(not ligado))
	dialogo.popup_centered()


## Escolha do enquadramento. Quatro botões em vez de uma lista suspensa: são
## quatro opções fixas, e ver as quatro de uma vez explica mais que abrir um
## menu para descobrir o que existe.
func _montar_camera(column: VBoxContainer) -> void:
	var ajuda := Design.caption("")
	# Sem quebra de linha a explicação some para fora da coluna, e a coluna toda
	# estica atrás dela.
	ajuda.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var sensibilidade_linha := _montar_sensibilidade()
	var botoes := {}

	for modo in CameraRig.ORDEM:
		var config: Dictionary = CameraRig.MODOS[modo]
		var botao := Design.button(String(config["rotulo"]))
		botao.pressed.connect(func(): _escolher_camera(modo, botoes, ajuda, sensibilidade_linha))
		botoes[modo] = botao
		column.add_child(botao)

	column.add_child(ajuda)
	column.add_child(sensibilidade_linha)

	# Pintar sem aplicar: abrir as configurações não é trocar de câmera.
	_pintar_camera(
		CameraRig.modo_do_id(String(SaveManager.get_setting(CameraRig.CHAVE_MODO, "terceira_pessoa"))),
		botoes, ajuda, sensibilidade_linha
	)


func _montar_sensibilidade() -> VBoxContainer:
	var linha := Design.vbox(Design.S_XS)
	var valor := clampf(
		float(SaveManager.get_setting(CameraRig.CHAVE_SENSIBILIDADE, CameraRig.SENSIBILIDADE_PADRAO)),
		CameraRig.SENSIBILIDADE_MIN, CameraRig.SENSIBILIDADE_MAX
	)
	var rotulo := Design.label(
		"Sensibilidade do mouse  %d%%" % _sensibilidade_em_porcento(valor),
		Design.FS_LABEL, Design.TEXT_MUTED
	)
	linha.add_child(rotulo)

	var barra := HSlider.new()
	barra.min_value = CameraRig.SENSIBILIDADE_MIN
	barra.max_value = CameraRig.SENSIBILIDADE_MAX
	barra.step = 0.01
	barra.value = valor
	barra.custom_minimum_size = Vector2(0, 22)
	barra.value_changed.connect(func(v: float):
		rotulo.text = "Sensibilidade do mouse  %d%%" % _sensibilidade_em_porcento(v)
		SaveManager.set_setting(CameraRig.CHAVE_SENSIBILIDADE, v)
		for node in get_tree().get_nodes_in_group("camera_rig"):
			if node is CameraRig:
				(node as CameraRig).definir_sensibilidade(v)
	)
	linha.add_child(barra)
	return linha


## Em porcentagem do máximo, porque "0,16 graus por pixel" não diz nada a
## ninguém enquanto arrasta o controle.
func _sensibilidade_em_porcento(valor: float) -> int:
	return int(round(valor / CameraRig.SENSIBILIDADE_MAX * 100.0))


func _escolher_camera(modo: CameraRig.Modo, botoes: Dictionary, ajuda: Label, sensibilidade: Control) -> void:
	SaveManager.set_setting(CameraRig.CHAVE_MODO, String(CameraRig.MODOS[modo]["id"]))
	for node in get_tree().get_nodes_in_group("camera_rig"):
		if node is CameraRig:
			(node as CameraRig).definir_modo(modo)
	_pintar_camera(modo, botoes, ajuda, sensibilidade)


func _pintar_camera(modo: CameraRig.Modo, botoes: Dictionary, ajuda: Label, sensibilidade: Control) -> void:
	for chave in botoes:
		Design.repintar_botao(botoes[chave], "primary" if chave == modo else "default")
	ajuda.text = String(CameraRig.MODOS[modo]["ajuda"])
	# O controle de sensibilidade só existe quando a câmera usa o mouse. Deixar
	# ele à mostra e sem efeito nos outros enquadramentos seria mentira.
	sensibilidade.visible = bool(CameraRig.MODOS[modo]["mouse"])


func _apply_camera_zoom(value: float) -> void:
	for node in get_tree().get_nodes_in_group("camera_rig"):
		if node is CameraRig:
			(node as CameraRig).set_zoom(value)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cancel"):
		get_viewport().set_input_as_handled()
		_close()


func _close() -> void:
	closed.emit()
	queue_free()
