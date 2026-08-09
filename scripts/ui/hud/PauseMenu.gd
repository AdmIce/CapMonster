class_name PauseMenu
extends CanvasLayer
## Esc menu. Pauses the tree, so the world genuinely stops instead of running
## behind the panel.

signal resumed()

var _panel: Control = null
var _is_open: bool = false


func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	visible = false


func _build() -> void:
	_panel = Control.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_panel)

	var scrim := ColorRect.new()
	scrim.color = Color(0.02, 0.03, 0.04, 0.7)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.add_child(scrim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.add_child(center)

	var card := Design.panel(Design.SURFACE)
	Responsivo.largura(card, 360, 0.45)
	center.add_child(card)

	var column := Design.vbox(Design.S_MD)
	card.add_child(column)

	column.add_child(Design.heading("Pausado"))
	column.add_child(Design.divider())

	var resume := Design.button("Retomar", "primary")
	resume.pressed.connect(close)
	column.add_child(resume)

	var save := Design.button("Salvar agora")
	save.pressed.connect(func():
		GameManager.save_now("manual")
		Notify.good("Progresso salvo.")
	)
	column.add_child(save)

	var settings := Design.button("Configurações")
	settings.pressed.connect(func():
		var overlay := SettingsPanel.new()
		_panel.add_child(overlay)
	)
	column.add_child(settings)

	column.add_child(Design.divider())

	var to_menu := Design.button("Salvar e voltar ao título")
	to_menu.pressed.connect(func():
		close()
		GameManager.end_session(true)
		SceneFlow.goto_main_menu()
	)
	column.add_child(to_menu)

	var quit := Design.button("Sair do jogo", "danger")
	quit.pressed.connect(func(): GameManager.quit_game())
	column.add_child(quit)


func toggle() -> void:
	if _is_open:
		close()
	else:
		open()


func open() -> void:
	_is_open = true
	visible = true
	get_tree().paused = true


func close() -> void:
	_is_open = false
	visible = false
	get_tree().paused = false
	resumed.emit()


func is_open() -> bool:
	return _is_open
