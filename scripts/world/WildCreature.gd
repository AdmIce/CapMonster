class_name WildCreature
extends CharacterBody3D
## A creature roaming the map.
##
## Encounters are visible, not random: each creature patrols a small area around
## its spawn point, notices the player inside its awareness radius, chases, and
## triggers an encounter on contact. Rarer species get a restrained visual tell
## (a soft ground glow and a slower, heavier idle) rather than a banner.
##
## State machine mirrors the battle-side one so the vocabulary stays consistent:
## IDLE -> PATROL -> CHASE -> CONTACT -> RETREAT.

signal encounter_triggered(source: WildCreature)
## Morreu de pancada. Quem escuta paga a recompensa -- o monstro nao sabe
## quanto ele vale, e nem deveria.
signal derrubado(source: WildCreature)
signal despawned(source: WildCreature)

enum State { IDLE, PATROL, CHASE, CONTACT, RETREAT }

const PATROL_SPEED := 1.9
const CHASE_SPEED := 3.6
const RETREAT_SPEED := 4.2
const CONTACT_DISTANCE := 1.25
const IDLE_TIME_RANGE := Vector2(1.2, 3.4)
const CHASE_GIVE_UP_DISTANCE := 14.0
const ENCOUNTER_COOLDOWN := 4.0

var data: CreatureData = null
## Id da criatura no mundo autoritativo. O mesmo número em todas as máquinas —
## é por ele que o dono manda remover e que o cliente pede o encontro.
var id_de_rede: int = 0
var zone_id: String = ""
var home: Vector3 = Vector3.ZERO
var patrol_radius: float = 5.0
var awareness_radius: float = 6.5

var _state: State = State.IDLE
var _state_timer: float = 0.0
var _goal: Vector3 = Vector3.ZERO
var _player: Node3D = null
var _model: Node3D = null
var _animador: CreatureAnimator = null
var _bob_phase: float = 0.0
var _cooldown: float = 0.0
var _rng := RandomNumberGenerator.new()
var _barra: HealthBar3D = null


static func create(creature: CreatureData, spawn_position: Vector3, zone: Dictionary) -> WildCreature:
	var node := WildCreature.new()
	node.data = creature
	node.zone_id = zone.get("id", "")
	node.home = spawn_position
	node.position = spawn_position
	node.name = "Wild_%s" % creature.uid
	return node


func _ready() -> void:
	_rng.randomize()
	collision_layer = GameLayers.CREATURE
	collision_mask = GameLayers.WORLD
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	add_to_group("wild_creature")
	_montar_barra()

	_build_collider()
	_build_model()
	_build_awareness()
	_enter_state(State.IDLE)


## Barra de vida sobre a cabeca.
##
## Combate em tempo real sem barra e chute: o jogador nao tem como saber se
## esta perto de derrubar o bicho ou se esta batendo em pedra.
func _montar_barra() -> void:
	_barra = HealthBar3D.new(false)
	_barra.position = Vector3(0, _altura_do_texto() + 0.35, 0)
	add_child(_barra)
	if data != null:
		_barra.configurar(data.display_name(), data.level)
		_barra.definir_proporcao(data.hp_ratio(), true)


func _build_collider() -> void:
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	var scale := data.species().visual_size() if data != null and data.species() != null else 1.0
	capsule.radius = 0.34 * scale
	capsule.height = 1.2 * scale
	shape.shape = capsule
	shape.position = Vector3(0, 0.6 * scale, 0)
	add_child(shape)


func _build_model() -> void:
	var species: CreatureSpecies = data.species() if data != null else null
	_model = CreatureModelBuilder.build(species)
	add_child(_model)
	# Criatura grande precisa de menos amplitude para o passo ler igual.
	var tamanho := species.visual_size() if species != null else 1.0
	_animador = CreatureAnimator.new(_model, clampf(1.2 / maxf(0.5, tamanho), 0.5, 1.3))

	if species != null and DataManager.get_rarity_order(species.rarity) >= 2:
		_add_rarity_tell(DataManager.get_rarity_color(species.rarity))


## Deliberately quiet: a low ground disc and a dim light, no text, no burst.
func _add_rarity_tell(color: Color) -> void:
	var disc := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.95
	mesh.bottom_radius = 0.95
	mesh.height = 0.02
	mesh.radial_segments = 20
	disc.mesh = mesh
	disc.position = Vector3(0, 0.02, 0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color.r, color.g, color.b, 0.22)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.6
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	disc.material_override = material
	add_child(disc)

	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 0.7
	light.omni_range = 4.5
	light.position = Vector3(0, 0.7, 0)
	add_child(light)


func _build_awareness() -> void:
	var area := Area3D.new()
	area.name = "Awareness"
	area.collision_layer = GameLayers.AGGRO
	area.collision_mask = GameLayers.PLAYER
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = awareness_radius
	shape.shape = sphere
	shape.position = Vector3(0, 0.8, 0)
	area.add_child(shape)
	area.body_entered.connect(_on_player_near)
	area.body_exited.connect(_on_player_far)
	add_child(area)


func _on_player_near(body: Node3D) -> void:
	if body is PlayerController:
		_player = body


func _on_player_far(body: Node3D) -> void:
	if body == _player:
		_player = null


# --- state machine ------------------------------------------------------------

func _enter_state(next: State) -> void:
	_state = next
	match next:
		State.IDLE:
			_state_timer = _rng.randf_range(IDLE_TIME_RANGE.x, IDLE_TIME_RANGE.y)
		State.PATROL:
			var angle := _rng.randf_range(0.0, TAU)
			var distance := _rng.randf_range(patrol_radius * 0.3, patrol_radius)
			_goal = home + Vector3(cos(angle) * distance, 0.0, sin(angle) * distance)
			_state_timer = 6.0
		State.CONTACT:
			_state_timer = 0.4
		State.RETREAT:
			_goal = home
			_state_timer = 5.0


func _physics_process(delta: float) -> void:
	if _cooldown > 0.0:
		_cooldown -= delta
	_state_timer -= delta
	_bob_phase += delta * (2.0 if _state == State.CHASE else 1.3)

	match _state:
		State.IDLE:
			_move_towards(global_position, 0.0, delta)
			if _sees_player():
				_enter_state(State.CHASE)
			elif _state_timer <= 0.0:
				_enter_state(State.PATROL)
		State.PATROL:
			_move_towards(_goal, PATROL_SPEED, delta)
			if _sees_player():
				_enter_state(State.CHASE)
			elif _state_timer <= 0.0 or _planar_distance(_goal) < 0.6:
				_enter_state(State.IDLE)
		State.CHASE:
			if _player == null or _planar_distance(home) > CHASE_GIVE_UP_DISTANCE:
				_enter_state(State.RETREAT)
			else:
				_move_towards(_player.global_position, CHASE_SPEED, delta)
				if _planar_distance(_player.global_position) <= CONTACT_DISTANCE and _cooldown <= 0.0:
					_trigger_encounter()
		State.CONTACT:
			_move_towards(global_position, 0.0, delta)
			if _state_timer <= 0.0:
				_enter_state(State.RETREAT)
		State.RETREAT:
			_move_towards(home, RETREAT_SPEED, delta)
			if _planar_distance(home) < 0.8 or _state_timer <= 0.0:
				_enter_state(State.IDLE)

	_animate(delta)


func _sees_player() -> bool:
	return _player != null and _cooldown <= 0.0


func _planar_distance(target: Vector3) -> float:
	return Vector2(global_position.x, global_position.z).distance_to(Vector2(target.x, target.z))


func _move_towards(target: Vector3, speed: float, delta: float) -> void:
	var direction := Vector3(target.x - global_position.x, 0.0, target.z - global_position.z)
	if speed <= 0.0 or direction.length() < 0.15:
		velocity = velocity.move_toward(Vector3.ZERO, 14.0 * delta)
	else:
		velocity = velocity.move_toward(direction.normalized() * speed, 12.0 * delta)
	velocity.y = 0.0
	move_and_slide()
	global_position.y = 0.0

	var planar := Vector2(velocity.x, velocity.z)
	if planar.length_squared() > 0.05:
		rotation.y = lerp_angle(rotation.y, atan2(planar.x, planar.y) + PI, 9.0 * delta)


func _animate(delta: float) -> void:
	if _animador == null or not _animador.valido():
		return
	# Ritmo relativo à corrida da criatura, para o passo bater com o deslocamento.
	var ritmo := Vector2(velocity.x, velocity.z).length() / CHASE_SPEED
	_animador.atualizar(delta, ritmo)

	var orbs := _model.get_node_or_null("Orbs")
	if orbs != null:
		orbs.rotation.y += delta * 1.2


## Encostou no jogador: bate nele.
##
## Antes isto abria a tela de batalha por turnos. Agora o combate acontece no
## mundo, entao encostar e dar o golpe -- o `_cooldown` que existia para nao
## reabrir a tela virou o intervalo entre as pancadas, que e a mesma ideia.
func _trigger_encounter() -> void:
	_cooldown = ENCOUNTER_COOLDOWN
	_enter_state(State.CONTACT)

	if _player == null or not is_instance_valid(_player) or not (_player is PlayerController):
		return
	var jogador := _player as PlayerController
	var dados := GameManager.player
	if dados == null:
		return

	var resultado := CombateDeAcao.golpe(data.attack(), dados.defesa(), data.element(), "")
	jogador.receber_dano(resultado, self)
	encounter_triggered.emit(self)


## Falso enquanto a criatura está em recarga de encontro. O AutoPilot usa isso
## para não ficar perseguindo um bicho que não vai reagir.
func pode_iniciar_encontro() -> bool:
	return _cooldown <= 0.0 and esta_vivo()


func esta_vivo() -> bool:
	return data != null and data.is_alive()


## Leva um golpe. Devolve quanto entrou de fato.
##
## Quem calcula e o `CombateDeAcao`, e nao esta funcao: o jogador tambem apanha,
## e a regra de quanto doi tem de ser a mesma nos dois sentidos.
func receber_dano(resultado: DamageCalculator.Resultado, de: Node3D = null) -> int:
	if data == null or not data.is_alive():
		return 0

	var entrou := data.apply_damage(resultado.amount)
	if entrou <= 0:
		return 0

	FloatingText3D.mostrar(self, global_position + Vector3(0, _altura_do_texto(), 0), FloatingText3D.dano(resultado))
	if _barra != null and is_instance_valid(_barra):
		_barra.definir_proporcao(data.hp_ratio())

	if not data.is_alive():
		morrer(de)
		return entrou

	# Apanhou: passa a perseguir quem bateu, mesmo que estivesse de costas. Um
	# monstro que continua patrulhando depois de levar uma pancada nao le como
	# inimigo, le como cenario.
	if de != null and is_instance_valid(de):
		_player = de
		_enter_state(State.CHASE)
	return entrou


func morrer(_de: Node3D = null) -> void:
	GameLog.info(GameLog.Channel.BATTLE, "%s foi derrubado." % data.display_name())
	derrubado.emit(self)
	despawned.emit(self)
	queue_free()


func _altura_do_texto() -> float:
	# Acima da cabeca, e nao no centro: numero saindo do meio do bicho fica
	# escondido atras dele quando a camera esta baixa.
	return 1.4


## Impede novos encontros por um tempo (usado depois de fuga ou derrota, para o
## jogador conseguir sair de perto sem ser puxado de novo na hora).
func definir_recarga_de_encontro(segundos: float) -> void:
	_cooldown = maxf(_cooldown, segundos)
	_enter_state(State.RETREAT)


## Congela a criatura durante uma batalha, para o resto do mapa não continuar
## correndo atrás do jogador enquanto ele luta.
func congelar(congelado: bool) -> void:
	set_physics_process(not congelado)
	if congelado:
		velocity = Vector3.ZERO


func despawn() -> void:
	despawned.emit(self)
	queue_free()
