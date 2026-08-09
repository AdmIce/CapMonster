extends CanvasLayer
## Autoload: SceneFlow
##
## The only place allowed to swap scenes. Owns the fade overlay so every
## transition looks the same, and exposes named destinations instead of raw
## paths so screens never hardcode res:// strings.

signal transition_started(target: String)
signal transition_finished(target: String)

const SCENES := {
	"main_menu": "res://scenes/main/MainMenu.tscn",
	"character_select": "res://scenes/main/CharacterSelect.tscn",
	"character_creation": "res://scenes/main/CharacterCreation.tscn",
	"intro": "res://scenes/main/Intro.tscn",
	"world": "res://scenes/maps/World.tscn",
}

const FADE_OUT_SECONDS := 0.28
const FADE_IN_SECONDS := 0.34

var _fade: ColorRect = null
var _is_transitioning: bool = false


func _ready() -> void:
	layer = 200
	process_mode = Node.PROCESS_MODE_ALWAYS

	_fade = ColorRect.new()
	_fade.color = Color(0.043, 0.051, 0.063, 1.0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.modulate.a = 0.0
	_fade.visible = false
	add_child(_fade)


func is_transitioning() -> bool:
	return _is_transitioning


func goto_main_menu() -> void:
	_goto("main_menu")


func goto_character_creation() -> void:
	_goto("character_creation")


func goto_character_select() -> void:
	_goto("character_select")


## Abertura com o professor, que termina na escolha da criatura inicial.
func goto_intro() -> void:
	_goto("intro")


func goto_world() -> void:
	_goto("world")


func _goto(key: String) -> void:
	if not SCENES.has(key):
		GameLog.error(GameLog.Channel.SYSTEM, "Chave de cena desconhecida: '%s'." % key)
		return
	change_scene(SCENES[key], key)


func change_scene(path: String, label: String = "") -> void:
	if _is_transitioning:
		return
	_is_transitioning = true
	var target := label if label != "" else path
	transition_started.emit(target)

	await fade_out()
	var err := get_tree().change_scene_to_file(path)
	if err != OK:
		GameLog.error(GameLog.Channel.SYSTEM, "Falha ao carregar %s (erro %d)." % [path, err])
	# One frame so the new scene builds itself before we reveal it.
	await get_tree().process_frame
	await fade_in()

	_is_transitioning = false
	transition_finished.emit(target)


func fade_out(duration: float = FADE_OUT_SECONDS) -> void:
	_fade.visible = true
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	var tween := create_tween()
	tween.tween_property(_fade, "modulate:a", 1.0, duration)
	await tween.finished


func fade_in(duration: float = FADE_IN_SECONDS) -> void:
	var tween := create_tween()
	tween.tween_property(_fade, "modulate:a", 0.0, duration)
	await tween.finished
	_fade.visible = false
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
