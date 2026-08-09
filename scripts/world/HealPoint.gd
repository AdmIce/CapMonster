class_name HealPoint
extends Interactable
## Acampamento / abrigo. Recupera a coleção inteira e vira a âncora de retorno do
## mapa atual. Interagir também salva, já que é um ponto de checagem natural.

const PULSE_SPEED := 2.2

var point_id: String = ""

var _luz: OmniLight3D = null
var _phase: float = 0.0


static func create(data: Dictionary) -> HealPoint:
	var point := HealPoint.new()
	point.point_id = data.get("id", "")
	point.title = data.get("name", "Acampamento")
	point.verb = "Descansar em"
	point.radius = 3.0
	point.name = "Heal_%s" % point.point_id
	var pos: Array = data.get("pos", [0, 0])
	point.position = Vector3(pos[0], 0.0, pos[1])
	return point


func _ready() -> void:
	super._ready()
	_build_visual()


## A fogueira respira. Antes quem pulsava era o cone de chama desenhado à mão;
## com o modelo no lugar dele, quem pulsa é a luz -- que é o que se enxerga de
## longe e o que diz "aqui dá para descansar".
func _process(delta: float) -> void:
	if _luz == null:
		return
	_phase += delta * PULSE_SPEED
	_luz.light_energy = 1.5 + sin(_phase) * 0.35
	_luz.omni_range = 9.0 + sin(_phase) * 0.6


## O acampamento e a fogueira decorativa do mapa sao a mesma coisa vista de
## angulos diferentes, entao os dois pedem o modelo ao MapBuilder. Antes eram
## duas montagens a mao iguais, lado a lado, e nada garantia que continuassem
## iguais.
func _build_visual() -> void:
	var fogueira := MapBuilder.criar_fogueira()
	add_child(fogueira)
	for no in fogueira.get_children():
		if no is OmniLight3D:
			_luz = no as OmniLight3D
			break


## Quanto tempo o personagem fica sentado antes da cura sair. Curto de
## proposito: descansar e um gesto, nao uma espera. Medido no modelo, descer e
## levantar somam quase um segundo e meio -- com 1,2 sentado, a coisa toda dura
## menos de tres segundos.
const SEGUNDOS_SENTADO := 1.2


func _perform(by: Node3D) -> void:
	if GameManager.player == null:
		return
	_descansar(by)


## Senta junto da fogueira, cura, levanta.
##
## A cura sai no fim, e nao no comeco: sentar depois de ja estar curado seria
## enfeite. Se o personagem nao souber sentar (os Kenney nao sabem), a cura sai
## na hora, como sempre saiu -- o descanso nunca depende da animacao existir.
func _descansar(quem: Node3D) -> void:
	var jogador := quem as PlayerController
	if jogador == null or jogador.avatar == null or not jogador.avatar.sentar():
		_curar()
		return

	# Sem isto da para sair andando sentado: o controlador continua lendo o
	# teclado e o corpo desliza pelo chao na pose de sentado.
	jogador.input_enabled = false
	GameLog.info(GameLog.Channel.WORLD, "Sentou na fogueira de %s." % title)

	await get_tree().create_timer(SEGUNDOS_SENTADO).timeout
	# O jogador pode ter trocado de mapa ou fechado o jogo durante a espera, e
	# ai tanto ele quanto este ponto de cura ja nao existem mais.
	if not is_instance_valid(jogador) or not is_inside_tree():
		return

	_curar()
	jogador.avatar.levantar()
	GameLog.info(GameLog.Channel.WORLD, "Levantou.")

	await get_tree().create_timer(0.9).timeout
	if is_instance_valid(jogador):
		jogador.input_enabled = true


func _curar() -> void:
	var player := GameManager.player
	if player == null:
		return
	player.heal_all()
	player.set_flag("last_heal_point", point_id)
	player.set_flag("last_heal_map", player.current_map)
	GameManager.save_now("descanso")
	Notify.good("Sua equipe está descansada.")
	GameLog.info(GameLog.Channel.WORLD, "Descansou em %s." % title)


# --- utilidades ---------------------------------------------------------------

static func _mesh(mesh: Mesh, color: Color, position: Vector3, scale: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = position
	node.scale = scale
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	node.material_override = material
	return node


static func _cone(radius: float, height: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 10
	return mesh
