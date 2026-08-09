class_name CameraRig
extends Node3D
## The 2.5D camera.
##
## Fixed yaw and a fixed downward pitch, orthographic by default, following the
## player with a soft lag and clamped to the map's bounds so the world never
## shows its edges. No player-controlled rotation - the framing is part of the
## art direction, not a control.
##
## Bounds maths assumes yaw = 0 (screen-up is -Z). If a map ever needs a rotated
## camera, `_visible_half_extents` is the only function that has to change.

## Dois enquadramentos. O isométrico é o do documento de design; o de terceira
## pessoa existe porque dá para ver o personagem e o mascote de perto, o que o
## de cima esconde. Trocar não muda regra nenhuma de jogo: só a câmera e o
## referencial do movimento.
enum Modo { ISOMETRICA, TERCEIRA_PESSOA }

# Terceira pessoa
const TP_DISTANCIA := 7.2
const TP_ALTURA := 3.0
const TP_PITCH := -15.0
const TP_FOV := 58.0
const TP_ALVO_ALTURA := 1.3
const TP_VELOCIDADE_GIRO := 4.5

@export var pitch_degrees: float = 48.0
@export var yaw_degrees: float = 0.0
@export var distance: float = 26.0
@export var orthographic_size: float = 17.0
@export var follow_speed: float = 6.5
## Pushes the framing slightly ahead of the direction of travel.
@export var look_ahead: float = 1.1
@export var use_orthographic: bool = true

var camera: Camera3D = null
var modo: Modo = Modo.ISOMETRICA

var _yaw_terceira: float = 0.0
var _tremor: float = 0.0
var _tremor_decaimento: float = 1.0
var _rng := RandomNumberGenerator.new()
var _target: Node3D = null
var _bounds: Rect2 = Rect2()
var _bounds_enabled: bool = false
var _zoom: float = 1.0
var _desired := Vector3.ZERO


func _ready() -> void:
	_rng.randomize()
	camera = Camera3D.new()
	camera.name = "Camera3D"
	camera.near = 0.5
	camera.far = 220.0
	add_child(camera)
	_apply_projection()
	_apply_orientation()


## Respeitar o modo aqui não é detalhe: sem isso, mexer no zoom em terceira
## pessoa trocava a câmera para ortográfica **sem sair da posição de trás do
## personagem** — o mundo virava uma placa achatada com vazio em volta.
func _apply_projection() -> void:
	if modo == Modo.TERCEIRA_PESSOA:
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		camera.fov = TP_FOV
		return
	if use_orthographic:
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		# size é a altura enquadrada: zoom maior = size menor = mais perto.
		camera.size = orthographic_size / maxf(0.35, _zoom)
	else:
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		camera.fov = 38.0


func _apply_orientation() -> void:
	camera.rotation_degrees = Vector3(-pitch_degrees, yaw_degrees, 0.0)
	camera.position = camera.transform.basis.z * distance


## Sacode a câmera. Usado em golpe forte, crítico e entrada de chefe.
## O deslocamento é aplicado na câmera filha, não no rig, para não brigar com o
## seguimento nem com o clamp de limites.
func tremer(intensidade: float = 0.18, duracao: float = 0.25) -> void:
	_tremor = maxf(_tremor, intensidade)
	_tremor_decaimento = maxf(0.05, duracao)


func _aplicar_tremor(delta: float) -> void:
	if _tremor <= 0.0001:
		if camera.h_offset != 0.0 or camera.v_offset != 0.0:
			camera.h_offset = 0.0
			camera.v_offset = 0.0
		return
	_tremor = maxf(0.0, _tremor - delta / _tremor_decaimento * _tremor)
	camera.h_offset = _rng.randf_range(-_tremor, _tremor)
	camera.v_offset = _rng.randf_range(-_tremor, _tremor)


func set_zoom(zoom: float) -> void:
	_zoom = clampf(zoom, 0.6, 1.8)
	_apply_projection()


func follow(target: Node3D, snap: bool = true) -> void:
	_target = target
	if snap and target != null:
		_desired = target.global_position
		global_position = _clamped(_desired)


## Restricts the camera centre so the viewport never leaves the map rectangle.
func set_bounds(min_x: float, max_x: float, min_z: float, max_z: float) -> void:
	_bounds = Rect2(min_x, min_z, max_x - min_x, max_z - min_z)
	_bounds_enabled = _bounds.size.x > 0.0 and _bounds.size.y > 0.0


func clear_bounds() -> void:
	_bounds_enabled = false


## Troca de enquadramento. Devolve o modo novo, para quem chamou poder salvar.
func definir_modo(novo: Modo) -> Modo:
	modo = novo
	if modo == Modo.TERCEIRA_PESSOA:
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		camera.fov = TP_FOV
		if _target != null and is_instance_valid(_target):
			_yaw_terceira = _target.rotation.y
			global_position = _target.global_position
	else:
		_apply_projection()
		_apply_orientation()
		if _target != null and is_instance_valid(_target):
			global_position = _clamped(_target.global_position)
	return modo


func alternar_modo() -> Modo:
	return definir_modo(Modo.ISOMETRICA if modo == Modo.TERCEIRA_PESSOA else Modo.TERCEIRA_PESSOA)


## Frente da câmera projetada no chão. O movimento do jogador é convertido por
## esta base, então "W" sempre é "para longe da câmera" nos dois modos.
func direcao_frente() -> Vector3:
	if modo == Modo.TERCEIRA_PESSOA:
		return Vector3(-sin(_yaw_terceira), 0.0, -cos(_yaw_terceira)).normalized()
	return Vector3.FORWARD


func direcao_direita() -> Vector3:
	var frente := direcao_frente()
	return Vector3(-frente.z, 0.0, frente.x)


func _process(delta: float) -> void:
	_aplicar_tremor(delta)
	if _target == null or not is_instance_valid(_target):
		return
	if modo == Modo.TERCEIRA_PESSOA:
		_seguir_terceira_pessoa(delta)
		return
	var lead := Vector3.ZERO
	if _target is CharacterBody3D:
		var velocity: Vector3 = (_target as CharacterBody3D).velocity
		lead = Vector3(velocity.x, 0.0, velocity.z).normalized() * look_ahead * minf(1.0, velocity.length() / 6.0)
	_desired = _target.global_position + lead
	var goal := _clamped(_desired)
	global_position = global_position.lerp(goal, clampf(follow_speed * delta, 0.0, 1.0))


## Fica atrás do personagem, girando junto com atraso. Sem clamp de limites: em
## terceira pessoa mostrar um pedaço de fora do mapa incomoda menos do que a
## câmera travar enquanto o jogador anda.
func _seguir_terceira_pessoa(delta: float) -> void:
	global_position = global_position.lerp(_target.global_position, clampf(12.0 * delta, 0.0, 1.0))

	# Só reorienta quando o jogador está de fato se movendo, senão a câmera fica
	# girando sozinha por causa de qualquer tremida do controlador.
	if _target is CharacterBody3D:
		var velocidade: Vector3 = (_target as CharacterBody3D).velocity
		if Vector2(velocidade.x, velocidade.z).length() > 0.6:
			_yaw_terceira = lerp_angle(_yaw_terceira, _target.rotation.y, TP_VELOCIDADE_GIRO * delta)

	# A câmera fica em +(sin, cos) * distância e olha para a origem do rig, que é
	# o personagem: com esse arranjo o yaw da câmera é o próprio _yaw_terceira e
	# o pitch é constante, sem precisar de look_at todo quadro.
	#
	# Em terceira pessoa o zoom mexe na distância, não no `size` (que só existe
	# na ortográfica). Assim o slider continua fazendo sentido nos dois modos.
	var perto := clampf(_zoom, 0.6, 1.8)
	camera.position = Vector3(sin(_yaw_terceira), 0.0, cos(_yaw_terceira)) * (TP_DISTANCIA / perto) \
		+ Vector3(0, TP_ALTURA / perto, 0)
	camera.rotation_degrees = Vector3(TP_PITCH, rad_to_deg(_yaw_terceira), 0.0)


func _clamped(position: Vector3) -> Vector3:
	var result := Vector3(position.x, 0.0, position.z)
	if not _bounds_enabled:
		return result
	var half := _visible_half_extents()
	var min_x := _bounds.position.x + half.x
	var max_x := _bounds.position.x + _bounds.size.x - half.x
	var min_z := _bounds.position.y + half.y
	var max_z := _bounds.position.y + _bounds.size.y - half.y
	# When the map is narrower than the view, centre instead of clamping.
	result.x = clampf(result.x, min_x, max_x) if min_x <= max_x else _bounds.position.x + _bounds.size.x * 0.5
	result.z = clampf(result.z, min_z, max_z) if min_z <= max_z else _bounds.position.y + _bounds.size.y * 0.5
	return result


## Half of the world-space rectangle the camera can see on the ground plane.
func _visible_half_extents() -> Vector2:
	var viewport := get_viewport()
	var aspect := 16.0 / 9.0
	if viewport != null:
		var rect := viewport.get_visible_rect().size
		if rect.y > 0.0:
			aspect = rect.x / rect.y

	var size := camera.size if use_orthographic else 2.0 * distance * tan(deg_to_rad(camera.fov) * 0.5)
	var half_width := size * aspect * 0.5
	# A tilted camera sees further along Z than its vertical extent suggests.
	var sin_pitch := maxf(0.2, sin(deg_to_rad(pitch_degrees)))
	var half_depth := size * 0.5 / sin_pitch
	return Vector2(half_width, half_depth)
