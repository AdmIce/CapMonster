extends CanvasLayer
## Autoload: Notify
##
## Short, non-blocking messages ("Ridge Pass is sealed", "Team restored").
## Stacked bottom-centre, auto-dismissed, capped so a burst cannot flood the
## screen. Deliberately dumb: no buttons, no queue the player has to clear.

const MAX_VISIBLE := 4
const LIFETIME_SECONDS := 2.6

enum Tone { NEUTRAL, GOOD, WARN, BAD }

var _stack: VBoxContainer = null


func _ready() -> void:
	layer = 150
	process_mode = Node.PROCESS_MODE_ALWAYS

	var anchor := Control.new()
	anchor.set_anchors_preset(Control.PRESET_FULL_RECT)
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(anchor)

	_stack = Design.vbox(Design.S_SM)
	_stack.alignment = BoxContainer.ALIGNMENT_END
	_stack.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_stack.offset_left = 0
	_stack.offset_right = 0
	_stack.offset_top = -220
	_stack.offset_bottom = -Design.S_XXL
	_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor.add_child(_stack)


func show_message(text: String, tone: Tone = Tone.NEUTRAL) -> void:
	if _stack == null:
		return
	while _stack.get_child_count() >= MAX_VISIBLE:
		var oldest := _stack.get_child(0)
		_stack.remove_child(oldest)
		oldest.queue_free()

	var toast := _build_toast(text, tone)
	_stack.add_child(toast)

	var tween := create_tween()
	tween.tween_property(toast, "modulate:a", 1.0, 0.14)
	tween.tween_interval(LIFETIME_SECONDS)
	tween.tween_property(toast, "modulate:a", 0.0, 0.3)
	tween.tween_callback(toast.queue_free)


func good(text: String) -> void:
	show_message(text, Tone.GOOD)


func warn(text: String) -> void:
	show_message(text, Tone.WARN)


func bad(text: String) -> void:
	show_message(text, Tone.BAD)


func _build_toast(text: String, tone: Tone) -> Control:
	var accent := Design.BORDER_STRONG
	var text_color := Design.TEXT
	match tone:
		Tone.GOOD:
			accent = Design.ACCENT
		Tone.WARN:
			accent = Design.GOLD
		Tone.BAD:
			accent = Design.DANGER
			text_color = Color("#E5B5AC")

	var row := Design.hbox(0)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER

	var card := PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := Design.panel_style(Color(0.055, 0.067, 0.082, 0.94), Design.R_SM, 1, accent)
	style.content_margin_left = Design.S_LG
	style.content_margin_right = Design.S_LG
	style.content_margin_top = Design.S_SM
	style.content_margin_bottom = Design.S_SM
	card.add_theme_stylebox_override("panel", style)

	var message := Design.label(text, Design.FS_LABEL, text_color)
	message.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(message)

	row.add_child(card)
	row.modulate.a = 0.0
	return row
