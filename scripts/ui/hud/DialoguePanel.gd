class_name DialoguePanel
extends CanvasLayer
## Short NPC dialogue. One line at a time, advanced with Interact or a click,
## with a typewriter reveal that can be skipped by pressing again.
##
## No branching and no portraits yet - the design brief asks for short, natural
## exchanges, not a conversation system.

signal finished()

const CHARACTERS_PER_SECOND := 55.0

var _lines: Array = []
var _index: int = 0
var _revealed: float = 0.0
var _speaker_label: Label = null
var _text_label: Label = null
var _hint_label: Label = null
var _is_open: bool = false


func _ready() -> void:
	layer = 40
	_build()
	visible = false


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var anchor := Control.new()
	anchor.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	anchor.offset_left = Design.S_HUGE
	anchor.offset_right = -Design.S_HUGE
	anchor.offset_top = -210
	anchor.offset_bottom = -Design.S_XXL
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(anchor)

	var card := Design.panel(Design.SURFACE)
	card.set_anchors_preset(Control.PRESET_FULL_RECT)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor.add_child(card)

	var column := Design.vbox(Design.S_SM)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(column)

	_speaker_label = Design.label("", Design.FS_LABEL, Design.ACCENT)
	column.add_child(_speaker_label)

	_text_label = Design.label("", Design.FS_HEADING, Design.TEXT)
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_label.custom_minimum_size = Vector2(0, 68)
	column.add_child(_text_label)

	column.add_child(Design.expander())

	_hint_label = Design.caption("E / Clique para continuar")
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	column.add_child(_hint_label)


func open(speaker: String, lines: Array) -> void:
	if lines.is_empty():
		return
	_lines = lines.duplicate()
	_index = 0
	_revealed = 0.0
	_is_open = true
	_speaker_label.text = speaker.to_upper()
	visible = true
	_show_current()


func is_open() -> bool:
	return _is_open


func _show_current() -> void:
	_revealed = 0.0
	_text_label.text = String(_lines[_index])
	_text_label.visible_ratio = 0.0
	_hint_label.text = "E / Clique para continuar" if _index < _lines.size() - 1 else "E / Clique para fechar"


func _process(delta: float) -> void:
	if not _is_open:
		return
	var length := maxi(1, _text_label.text.length())
	if _text_label.visible_ratio < 1.0:
		_revealed += delta * CHARACTERS_PER_SECOND
		_text_label.visible_ratio = clampf(_revealed / float(length), 0.0, 1.0)


func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return
	var advance := event.is_action_pressed("interact")
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		advance = true
	if not advance:
		return
	get_viewport().set_input_as_handled()
	_advance()


func _advance() -> void:
	# First press finishes the reveal, second press moves on.
	if _text_label.visible_ratio < 1.0:
		_text_label.visible_ratio = 1.0
		_revealed = float(_text_label.text.length())
		return
	_index += 1
	if _index >= _lines.size():
		close()
		return
	_show_current()


func close() -> void:
	_is_open = false
	visible = false
	finished.emit()
