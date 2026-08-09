class_name CompanionCreature
extends CharacterBody3D
## A criatura líder andando junto com o treinador.
##
## Fica atrás e um pouco de lado, corre quando fica para trás, para quando você
## para e olha para onde está indo. Se ficar longe demais (parede, troca de mapa,
## teleporte), ela reaparece do seu lado em vez de tentar atravessar o cenário.
##
## Trocar a líder no inventário troca o modelo aqui na hora.

signal invocada(criatura: CreatureData)

const DISTANCIA_ALVO := 2.1
const DESLOCAMENTO_LATERAL := 1.15
const DESLOCAMENTO_LATERAL_TP := 1.9
const VELOCIDADE_MAX := 9.5
const ACELERACAO := 26.0
const DISTANCIA_PARA_ANDAR := 0.55
const DISTANCIA_TELEPORTE := 22.0
const VELOCIDADE_GIRO := 9.0

var criatura: CreatureData = null

var _player: PlayerController = null
var _modelo: Node3D = null
var _animador: CreatureAnimator = null
var _fase: float = 0.0
var _lado: float = 1.0
var _terceira_pessoa: bool = false


func _ready() -> void:
	collision_layer = 0
	# Só colide com o cenário: não empurra o jogador nem as criaturas selvagens.
	collision_mask = GameLayers.WORLD
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	add_to_group("companion")


func seguir(player: PlayerController) -> void:
	_player = player
	if player != null:
		global_position = _posicao_desejada()


## Troca (ou define) a criatura acompanhante. Passar null esconde o mascote.
func definir_criatura(nova: CreatureData) -> void:
	criatura = nova
	if _modelo != null:
		_modelo.queue_free()
		_modelo = null

	if criatura == null:
		visible = false
		return

	visible = true
	_modelo = CreatureModelBuilder.build(criatura.species())
	add_child(_modelo)
	var especie := criatura.species()
	var tamanho := especie.visual_size() if especie != null else 1.0
	_animador = CreatureAnimator.new(_modelo, clampf(1.2 / maxf(0.5, tamanho), 0.5, 1.3))
	_tocar_invocacao()
	invocada.emit(criatura)
	GameLog.verbose(GameLog.Channel.CREATURE, "%s está te acompanhando." % criatura.display_name())


## Efeito de surgimento: cresce do chão com um clarão na cor do elemento.
func _tocar_invocacao() -> void:
	if _modelo == null:
		return
	_modelo.scale = Vector3(0.1, 0.1, 0.1)
	var tween := create_tween()
	tween.tween_property(_modelo, "scale", Vector3.ONE, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	var cor := DataManager.get_element_color(criatura.element())
	var luz := OmniLight3D.new()
	luz.light_color = cor
	luz.light_energy = 4.0
	luz.omni_range = 6.0
	luz.position = Vector3(0, 0.8, 0)
	add_child(luz)
	var apagar := create_tween()
	apagar.tween_property(luz, "light_energy", 0.0, 0.7)
	apagar.tween_callback(luz.queue_free)


## Em terceira pessoa a câmera fica atrás do jogador, que é justamente onde o
## mascote andaria: nesse modo ele passa a caminhar ao lado e um pouco à frente,
## senão tapa a tela inteira.
func definir_enquadramento(terceira_pessoa: bool) -> void:
	_terceira_pessoa = terceira_pessoa


func _posicao_desejada() -> Vector3:
	if _player == null:
		return global_position
	var frente := -_player.global_transform.basis.z
	frente.y = 0.0
	if frente.length() < 0.01:
		frente = Vector3.FORWARD
	frente = frente.normalized()
	var lateral := Vector3(-frente.z, 0.0, frente.x) * _lado

	if _terceira_pessoa:
		return _player.global_position + frente * 0.7 + lateral * DESLOCAMENTO_LATERAL_TP
	return _player.global_position - frente * DISTANCIA_ALVO + lateral * DESLOCAMENTO_LATERAL


func _physics_process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player) or criatura == null:
		return

	var alvo := _posicao_desejada()
	var para_alvo := alvo - global_position
	para_alvo.y = 0.0
	var distancia := para_alvo.length()

	if distancia > DISTANCIA_TELEPORTE:
		global_position = alvo
		velocity = Vector3.ZERO
		return

	if distancia > DISTANCIA_PARA_ANDAR:
		# Anda mais rápido quanto mais atrás está, para não ficar sobrando.
		var desejada := para_alvo.normalized() * minf(VELOCIDADE_MAX, distancia * 3.4)
		velocity = velocity.move_toward(desejada, ACELERACAO * delta)
	else:
		velocity = velocity.move_toward(Vector3.ZERO, ACELERACAO * delta)

	velocity.y = 0.0
	move_and_slide()
	global_position.y = 0.0

	_orientar(delta)
	_animar(delta)


func _orientar(delta: float) -> void:
	var plano := Vector2(velocity.x, velocity.z)
	if plano.length_squared() > 0.09:
		rotation.y = lerp_angle(rotation.y, atan2(plano.x, plano.y) + PI, VELOCIDADE_GIRO * delta)
	elif _player != null:
		# Parado: olha para a mesma direção do treinador.
		rotation.y = lerp_angle(rotation.y, _player.rotation.y, VELOCIDADE_GIRO * 0.4 * delta)


func _animar(delta: float) -> void:
	if _animador == null or not _animador.valido():
		return
	_animador.atualizar(delta, Vector2(velocity.x, velocity.z).length() / VELOCIDADE_MAX)

	var orbes := _modelo.get_node_or_null("Orbs")
	if orbes != null:
		orbes.rotation.y += delta * 1.4
