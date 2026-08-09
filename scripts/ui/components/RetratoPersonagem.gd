class_name RetratoPersonagem
extends Control
## O boneco do jogador em 3D dentro de um painel de interface.
##
## Uma cena 3D minúscula por retrato: mundo próprio, câmera ortográfica e duas
## luzes. O `own_world_3d` é o que permite vários retratos na mesma tela sem um
## enxergar a iluminação do outro — sem ele, a lista de personagens vira uma
## sopa de luzes somadas.
##
## Usa o mesmo `PlayerAvatar` do mundo, então o que aparece aqui é exatamente o
## que sai andando da vila. É de propósito: retrato desenhado à parte envelhece
## e passa a mentir sobre o personagem.

const GIRO_POR_SEGUNDO := 0.45

var _pivot: Node3D = null
var _avatar: PlayerAvatar = null


## `tamanho` em pixels de projeto. `girar` desliga a rotação para listas grandes,
## onde vários bonecos girando ao mesmo tempo cansam a vista.
static func criar(aparencia: Dictionary, tamanho: Vector2i, girar: bool = true) -> RetratoPersonagem:
	var node := RetratoPersonagem.new()
	node.custom_minimum_size = Vector2(tamanho)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node._montar(aparencia, tamanho, girar)
	return node


func _montar(aparencia: Dictionary, tamanho: Vector2i, girar: bool) -> void:
	set_process(girar)

	var container := SubViewportContainer.new()
	container.stretch = true
	container.custom_minimum_size = Vector2(tamanho)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)

	var viewport := SubViewport.new()
	viewport.size = tamanho
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_2X
	container.add_child(viewport)

	var raiz := Node3D.new()
	viewport.add_child(raiz)

	_pivot = Node3D.new()
	raiz.add_child(_pivot)

	_avatar = PlayerAvatar.new()
	_avatar.apply_appearance(aparencia)
	_pivot.add_child(_avatar)

	# Ortográfica: sem perspectiva o boneco não distorce quando o retrato é
	# pequeno, e a altura na tela não muda com o tamanho do painel.
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.6
	camera.position = Vector3(0, 1.0, 3.4)
	raiz.add_child(camera)

	var principal := DirectionalLight3D.new()
	principal.light_energy = 1.5
	principal.rotation_degrees = Vector3(-38, 34, 0)
	raiz.add_child(principal)

	var preenchimento := DirectionalLight3D.new()
	preenchimento.light_energy = 0.5
	preenchimento.light_color = Color("#8FA8C4")
	preenchimento.rotation_degrees = Vector3(-14, -140, 0)
	raiz.add_child(preenchimento)


func aplicar(aparencia: Dictionary) -> void:
	if _avatar != null:
		_avatar.apply_appearance(aparencia)


func _process(delta: float) -> void:
	if _pivot != null:
		_pivot.rotation.y += delta * GIRO_POR_SEGUNDO
