class_name SettingsPanel
extends Control
## Settings overlay, reusable from the main menu and the in-game pause menu.
## Every control here changes something observable immediately and is persisted
## to user://settings.json. Options with nothing to act on yet are not shown.

signal closed()


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()


func _build() -> void:
	var scrim := ColorRect.new()
	scrim.color = Color(0, 0, 0, 0.55)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(scrim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var card := Design.panel(Design.SURFACE)
	Responsivo.largura(card, 420, 0.5)
	center.add_child(card)

	var column := Design.vbox(Design.S_LG)
	card.add_child(column)

	column.add_child(Design.heading("Configurações"))
	column.add_child(Design.divider())

	var fullscreen := Design.check("Tela cheia", bool(SaveManager.get_setting("fullscreen", false)))
	fullscreen.toggled.connect(func(on): SaveManager.set_setting("fullscreen", on))
	column.add_child(fullscreen)

	var vsync := Design.check("V-Sync", bool(SaveManager.get_setting("vsync", true)))
	vsync.toggled.connect(func(on): SaveManager.set_setting("vsync", on))
	column.add_child(vsync)

	var fps := Design.check("Mostrar FPS", bool(SaveManager.get_setting("show_fps", false)))
	fps.toggled.connect(func(on): SaveManager.set_setting("show_fps", on))
	column.add_child(fps)

	column.add_child(Design.divider())
	_montar_grafico(column)
	column.add_child(Design.divider())

	var escala_linha := Design.vbox(Design.S_XS)
	var escala_valor := Responsivo.escala_salva()
	var escala_rotulo := Design.label(
		"Tamanho da interface  %d%%" % int(round(escala_valor * 100.0)),
		Design.FS_LABEL, Design.TEXT_MUTED
	)
	escala_linha.add_child(escala_rotulo)

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
	escala_linha.add_child(escala)
	column.add_child(escala_linha)

	var zoom_row := Design.vbox(Design.S_XS)
	var zoom_value := float(SaveManager.get_setting("camera_zoom", 1.0))
	var zoom_label := Design.label("Zoom da câmera  %.2fx" % zoom_value, Design.FS_LABEL, Design.TEXT_MUTED)
	zoom_row.add_child(zoom_label)

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
	zoom_row.add_child(slider)
	column.add_child(zoom_row)

	column.add_child(Design.spacer(Design.S_SM))

	var close := Design.button("Fechar", "primary")
	close.pressed.connect(_close)
	column.add_child(close)


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
