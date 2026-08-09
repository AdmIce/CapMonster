class_name PlayerController
extends CharacterBody3D
## Movement, facing and interaction for the player character.
##
## The world is flat (y = 0) and the camera yaw is fixed, so input maps straight
## onto XZ: screen-right is +X, screen-up is -Z. Gravity is off; this is a
## top-down-ish 2.5D game, not a platformer.

signal interaction_target_changed(target: Interactable)
signal moved(position: Vector2)

const WALK_SPEED := 5.4
const RUN_SPEED := 8.2

## --- voo ---------------------------------------------------------------------
##
## Dois toques no espaco levantam voo. A janela e curta de proposito: mais que
## isso e um toque solto vira decolagem sem querer no meio de uma corrida.
const JANELA_DUPLO_TOQUE := 0.30
const ALTURA_DE_DECOLAGEM := 5.5
const ALTURA_MAXIMA := 34.0
const VELOCIDADE_VERTICAL := 7.5
const VELOCIDADE_VOO := 11.5
## Abaixo disto o personagem encosta e o voo termina sozinho.
const ALTURA_DE_POUSO := 0.12
const ACCELERATION := 42.0
const FRICTION := 38.0
const TURN_SPEED := 14.0
## Pulo: velocidade inicial e a "gravidade" só dele. O mundo não tem gravidade
## (levitar escala da física), então a parábola é calculada aqui. Medido a
## 6.5 de subida / 22 de queda dá ~0,9 m de altura e ~0,6 s de ar.
const JUMP_SPEED := 6.5
const JUMP_GRAVITY := 22.0
## Metros percorridos entre um passo e outro, por ritmo. Com o jaleco andando em
## 5.4 m/s, 1.6 m dá ~3,4 passos/s; correndo a 8.6 m/s, 2.0 m dá ~4,3 passos/s.
const STEP_WALK := 1.6
const STEP_RUN := 2.0
## How far the player can drift before the position is worth re-recording.
const POSITION_REPORT_DISTANCE := 1.5

@export var input_enabled: bool = true

## Modo automático: quando ligado, o AutoPilot escreve em `auto_input` o mesmo
## vetor que o teclado escreveria. O resto do controlador não muda.
var auto_enabled: bool = false
var auto_input: Vector2 = Vector2.ZERO

var voando: bool = false

var _altura_alvo: float = 0.0
var _ultimo_toque_de_voo: float = -10.0

var avatar: PlayerAvatar = null
## Definido pelo WorldRoot. Serve só para converter o input para o referencial da
## câmera; o controlador nunca mexe na câmera.
var camera_rig: CameraRig = null

var _interactables: Array[Interactable] = []
var _current_target: Interactable = null
var _last_reported := Vector2(INF, INF)
var _last_plane := Vector2.ZERO
var _facing_angle: float = 0.0
var _jumping := false
var _step_distance := 0.0


func _ready() -> void:
	collision_layer = GameLayers.PLAYER
	collision_mask = GameLayers.WORLD
	# Floating mode: the world is flat and gravity is off, so every contact is a
	# wall to slide along. Grounded mode would try to resolve floors that do not
	# exist.
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	add_to_group("player_controller")

	_build_collider()
	_build_avatar()
	_build_interaction_sensor()


func _build_collider() -> void:
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.34
	capsule.height = 1.5
	shape.shape = capsule
	shape.position = Vector3(0, 0.75, 0)
	add_child(shape)


func _build_avatar() -> void:
	avatar = PlayerAvatar.new()
	avatar.name = "Avatar"
	# Aparência antes de entrar na árvore: assim o corpo é montado uma vez só,
	# com o visual certo, em vez de nascer padrão e ser reconstruído em seguida.
	if GameManager.player != null:
		avatar.apply_appearance(GameManager.player.appearance)
	add_child(avatar)


func _build_interaction_sensor() -> void:
	var sensor := Area3D.new()
	sensor.name = "InteractionSensor"
	sensor.collision_layer = 0
	sensor.collision_mask = GameLayers.INTERACT
	sensor.monitoring = true
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 1.6
	shape.shape = sphere
	shape.position = Vector3(0, 0.8, 0)
	sensor.add_child(shape)
	sensor.area_entered.connect(_on_interactable_entered)
	sensor.area_exited.connect(_on_interactable_exited)
	add_child(sensor)


func apply_appearance(appearance: Dictionary) -> void:
	if avatar != null:
		avatar.apply_appearance(appearance)


## Cached every physics frame so it stays readable during teardown, when the
## node has already left the tree and global_position would error.
func plane_position() -> Vector2:
	if not is_inside_tree():
		return _last_plane
	_last_plane = Vector2(global_position.x, global_position.z)
	return _last_plane


func teleport_to(plane: Vector2) -> void:
	global_position = Vector3(plane.x, 0.0, plane.y)
	velocity = Vector3.ZERO
	_last_reported = plane
	_last_plane = plane
	# Teleporte cancela pulo e passo em andamento: chega no chão, e não toca
	# passo logo depois por causa da distância do salto.
	_jumping = false
	_step_distance = 0.0


# --- loop ---------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	var direcao := Vector3.ZERO
	var running := false

	if input_enabled:
		var input := InputActions.get_move_vector()
		if input.length_squared() > 0.01:
			# Teclado: relativo à câmera, para "W" ser sempre "para longe da
			# câmera" nos dois enquadramentos. No isométrico a base é a
			# identidade, então o resultado é o mesmo de antes.
			var frente := Vector3.FORWARD
			var direita := Vector3.RIGHT
			if camera_rig != null and is_instance_valid(camera_rig):
				frente = camera_rig.direcao_frente()
				direita = camera_rig.direcao_direita()
			direcao = direita * input.x + frente * -input.y
			running = Input.is_action_pressed("run")
		elif auto_enabled:
			# Modo automático: o AutoPilot já calcula em espaço de mundo. Passar
			# isto pela base da câmera faria o personagem girar em círculo em
			# terceira pessoa, porque a câmera gira junto com ele.
			direcao = Vector3(auto_input.x, 0.0, auto_input.y).limit_length(1.0)
			running = true

	var target_speed := VELOCIDADE_VOO if voando else (RUN_SPEED if running else WALK_SPEED)
	var desired := direcao * target_speed

	if input_enabled and not auto_enabled and Input.is_action_just_pressed("jump"):
		_tocou_no_espaco()

	if desired.length_squared() > 0.001:
		velocity.x = move_toward(velocity.x, desired.x, ACCELERATION * delta)
		velocity.z = move_toward(velocity.z, desired.z, ACCELERATION * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)
		velocity.z = move_toward(velocity.z, 0.0, FRICTION * delta)

	# Três estados verticais e só um vale por quadro. Ficarem separados é o que
	# impede o pulo de brigar com o voo: quem está voando não tem gravidade, e
	# quem está no chão tem o y cravado em zero como sempre teve.
	if voando:
		velocity.y = 0.0
		move_and_slide()
		_atualizar_altura(delta)
	elif _jumping:
		velocity.y -= JUMP_GRAVITY * delta
		move_and_slide()
		# O chão é a colisão no y=0; encostou, aterrissa e entrega o controle do
		# eixo vertical de volta (importante: o voo não prende o piso).
		if global_position.y <= 0.001:
			global_position.y = 0.0
			velocity.y = 0.0
			_jumping = false
			AudioManager.tocar(&"pouso")
	else:
		velocity.y = 0.0
		move_and_slide()
		global_position.y = 0.0

	_update_facing(delta)
	_update_avatar(running)
	if avatar != null:
		avatar.definir_voo(voando, delta)
	_update_steps(running, delta)
	_report_position()


## Espaço é uma tecla só para duas coisas, e quem separa é o tempo entre os
## toques: o primeiro pula, e um segundo logo em seguida decola.
##
## O pulo sai na hora, sem esperar para ver se vem o segundo toque. Esperar
## deixaria o salto com um atraso de 0,3 s, e salto com atraso parece jogo
## travando. Em troca, a decolagem corta a parábola no meio — que é justamente
## como um pulo que vira voo deveria parecer.
func _tocou_no_espaco() -> void:
	var agora := Time.get_ticks_msec() / 1000.0
	var duplo := agora - _ultimo_toque_de_voo < JANELA_DUPLO_TOQUE
	_ultimo_toque_de_voo = agora

	if duplo:
		# Consome o par: sem isto, um terceiro toque logo em seguida faria par
		# com o segundo e desfaria a decolagem que acabou de acontecer.
		_ultimo_toque_de_voo = -10.0
		alternar_voo()
		return
	if voando:
		# Voando, segurar o espaço sobe (ver `_atualizar_altura`). Só o toque
		# duplo muda de estado.
		return
	if not _jumping and _on_ground():
		_jumping = true
		velocity.y = JUMP_SPEED
		AudioManager.tocar(&"salto")


func _on_ground() -> bool:
	return global_position.y <= 0.001


## O mundo e plano e todo o resto anda em y = 0; o voo e a unica coisa que tira
## o personagem desse plano de forma duradoura, entao a altura vive aqui e em
## mais lugar nenhum. (O pulo tambem sai do plano, mas volta sozinho.)
func _atualizar_altura(delta: float) -> void:
	if not voando:
		global_position.y = 0.0
		return

	if input_enabled:
		if Input.is_action_pressed("jump"):
			_altura_alvo += VELOCIDADE_VERTICAL * delta
		if Input.is_action_pressed("descer"):
			_altura_alvo -= VELOCIDADE_VERTICAL * delta
	_altura_alvo = clampf(_altura_alvo, 0.0, ALTURA_MAXIMA)

	# Sobe e desce com atraso: sem isto a altura acompanha a tecla no mesmo
	# quadro e o voo parece um elevador.
	global_position.y = move_toward(global_position.y, _altura_alvo, VELOCIDADE_VERTICAL * 1.6 * delta)

	if _altura_alvo <= 0.0 and global_position.y <= ALTURA_DE_POUSO:
		pousar()


func alternar_voo() -> void:
	if voando:
		# Descer ate o chao em vez de cair: o pouso acontece no _atualizar_altura.
		_altura_alvo = 0.0
		return
	voando = true
	# Decolou no meio de um pulo: a parabola morre aqui, senao a gravidade do
	# salto continuaria puxando contra a altura de voo no quadro seguinte.
	_jumping = false
	velocity.y = 0.0
	_altura_alvo = ALTURA_DE_DECOLAGEM
	AudioManager.tocar(&"ui_alternar")


func pousar() -> void:
	if not voando:
		return
	voando = false
	_altura_alvo = 0.0
	global_position.y = 0.0
	# Chegando do voo, o contador de passos comeca do zero: senao o primeiro
	# passo depois de pousar sai imediatamente, por causa da distancia voada.
	_step_distance = 0.0


func _update_steps(running: bool, delta: float) -> void:
	# Sem passo no ar, seja pulando ou voando — nao ha chao para pisar.
	if _jumping or voando:
		return
	var planar := Vector2(velocity.x, velocity.z)
	var andou := planar.length() * delta
	if andou < 0.001:
		return
	_step_distance += andou
	if _step_distance < (STEP_RUN if running else STEP_WALK):
		return
	_step_distance = 0.0
	AudioManager.tocar(&"passo_cor" if running else &"passo")


func _update_facing(delta: float) -> void:
	# Com o mouse mandando na câmera, o corpo aponta para onde se olha, mesmo
	# parado. Deixar o corpo seguir o movimento nesses enquadramentos faria você
	# mirar num lado e andar de lado para o outro — e em primeira pessoa seria
	# impossível virar sem sair andando.
	if camera_rig != null and is_instance_valid(camera_rig) and camera_rig.orienta_personagem():
		var frente := camera_rig.direcao_frente()
		_facing_angle = atan2(frente.x, frente.z)
		rotation.y = lerp_angle(rotation.y, _facing_angle + PI, TURN_SPEED * delta)
		return

	var planar := Vector2(velocity.x, velocity.z)
	if planar.length_squared() < 0.04:
		return
	# atan2(x, z) gives the yaw that points -Z forward, which is how the meshes
	# are authored (they face -Z at rest).
	_facing_angle = atan2(planar.x, planar.y)
	rotation.y = lerp_angle(rotation.y, _facing_angle + PI, TURN_SPEED * delta)


func _update_avatar(running: bool) -> void:
	if avatar == null:
		return
	var ratio := Vector2(velocity.x, velocity.z).length() / RUN_SPEED
	avatar.set_locomotion(ratio, running)


func _report_position() -> void:
	_last_plane = Vector2(global_position.x, global_position.z)
	var plane := _last_plane
	if plane.distance_to(_last_reported) < POSITION_REPORT_DISTANCE:
		return
	_last_reported = plane
	moved.emit(plane)


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return

	if not event.is_action_pressed("interact"):
		return
	if _current_target == null:
		return
	get_viewport().set_input_as_handled()
	if avatar != null:
		avatar.play_interact()
	_current_target.interact(self)


# --- interaction target -------------------------------------------------------

func _on_interactable_entered(area: Area3D) -> void:
	if area is Interactable and not _interactables.has(area):
		_interactables.append(area)
		_refresh_target()


func _on_interactable_exited(area: Area3D) -> void:
	if area is Interactable:
		_interactables.erase(area)
		_refresh_target()


func _refresh_target() -> void:
	var best: Interactable = null
	var best_distance := INF
	for candidate in _interactables:
		if not is_instance_valid(candidate):
			continue
		var distance := global_position.distance_squared_to(candidate.global_position)
		if distance < best_distance:
			best_distance = distance
			best = candidate
	if best == _current_target:
		return
	_current_target = best
	interaction_target_changed.emit(_current_target)


func current_interactable() -> Interactable:
	return _current_target


## Refreshes the prompt after an interactable changed availability
## (for example a gate that just unlocked).
func revalidate_target() -> void:
	interaction_target_changed.emit(_current_target)
