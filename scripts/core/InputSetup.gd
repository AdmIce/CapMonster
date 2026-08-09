extends Node
## Autoload: InputActions
##
## Registers every input action in code instead of in project.godot. Two reasons:
## the bindings stay readable in one place, and rebinding (settings menu, gamepad
## profiles) becomes a data operation later instead of an editor operation.

const DEFAULT_BINDINGS := {
	"move_up": [KEY_W, KEY_UP],
	"move_down": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"run": [KEY_SHIFT],
	# Enter saiu de "interact" quando o chat entrou: é a tecla de abrir a caixa de
	# conversa em todo jogo online, e deixar as duas coisas na mesma tecla fazia
	# mandar mensagem interagir com o NPC atrás de você.
	#
	# O mesmo raciocínio tirou o Espaço de "interact": agora ele pula, e
	# interagir ficou só no E. Dividir evitava pular enquanto tentava abrir uma
	# porta.
	"interact": [KEY_E],
	# Um toque pula, dois seguidos levantam voo. **Uma ação só** para as duas
	# coisas, de propósito: com `jump` e `voar` no mesmo Espaço, cada toque
	# disparava as duas e o personagem pulava toda vez que tentava decolar.
	# Quem separa é o tempo entre os toques, no PlayerController.
	"jump": [KEY_SPACE],
	"cancel": [KEY_ESCAPE],
	"descer": [KEY_CTRL],
	# Solta o cursor enquanto está segurado, nas câmeras que prendem o mouse.
	# Sem isto a HUD inteira (mochila, automático, chat) ficava inalcançável em
	# primeira pessoa: o cursor sumia e não havia como clicar em nada.
	"cursor": [KEY_ALT],
	# Sentar onde estiver. E gesto, nao acao de jogo: nao cura, nao pausa, nao
	# muda regra nenhuma -- so muda a pose.
	"sentar": [KEY_INSERT],
	"chat": [KEY_ENTER, KEY_KP_ENTER],
	"chat_comando": [KEY_SLASH],
	"inventory": [KEY_I, KEY_TAB],
	"toggle_camera": [KEY_C],
	"map": [KEY_M],
	"toggle_debug": [KEY_F1],
	"quick_save": [KEY_F5],
}

const JOY_BINDINGS := {
	"interact": [JOY_BUTTON_A],
	"cancel": [JOY_BUTTON_B],
	"run": [JOY_BUTTON_X],
	"inventory": [JOY_BUTTON_Y],
}


func _ready() -> void:
	_register_actions()
	GameLog.verbose(GameLog.Channel.SYSTEM, "Ações de entrada registradas (%d)" % DEFAULT_BINDINGS.size())


func _register_actions() -> void:
	for action_name in DEFAULT_BINDINGS.keys():
		if not InputMap.has_action(action_name):
			InputMap.add_action(action_name)
		for keycode in DEFAULT_BINDINGS[action_name]:
			var event := InputEventKey.new()
			event.physical_keycode = keycode
			InputMap.action_add_event(action_name, event)

	for action_name in JOY_BINDINGS.keys():
		for button in JOY_BINDINGS[action_name]:
			var event := InputEventJoypadButton.new()
			event.button_index = button
			InputMap.action_add_event(action_name, event)

	# Left stick drives movement on gamepads.
	_add_joy_axis("move_left", JOY_AXIS_LEFT_X, -1.0)
	_add_joy_axis("move_right", JOY_AXIS_LEFT_X, 1.0)
	_add_joy_axis("move_up", JOY_AXIS_LEFT_Y, -1.0)
	_add_joy_axis("move_down", JOY_AXIS_LEFT_Y, 1.0)


func _add_joy_axis(action_name: String, axis: int, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	InputMap.action_add_event(action_name, event)


## Returns the normalised movement vector in screen space (x = right, y = down).
func get_move_vector() -> Vector2:
	return Input.get_vector("move_left", "move_right", "move_up", "move_down")
