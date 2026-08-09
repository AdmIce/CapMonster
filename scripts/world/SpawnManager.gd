class_name SpawnManager
extends Node3D
## Mantém cada zona de encontro povoada.
##
## Regras: nunca mais que `max_alive` por zona, nunca nascer à vista do jogador,
## renascer depois do descanso da zona. Espécie e nível saem do CreatureFactory
## pela tabela da própria zona, então o equilíbrio do spawn é decisão de dado.
##
## **Autoridade.** Só o dono do mundo sorteia (jogando sozinho, é esta máquina;
## numa partida, é o host). No cliente este nó vira uma vitrine: ele não sorteia
## nada, só materializa o que o `MundoRede` mandou e apaga o que o dono mandou
## apagar. Sem isso cada máquina sorteava a sua própria fauna e dois jogadores
## lado a lado viam bichos diferentes no mesmo lugar.
##
## O encontro também passa pelo dono: encostar numa criatura **pede** a batalha,
## não a começa. É o que impede dois jogadores de capturarem o mesmo bicho.

signal creature_spawned(creature: WildCreature)
signal encounter_triggered(creature: WildCreature)

const TICK_SECONDS := 1.0
const MIN_DISTANCE_FROM_PLAYER := 12.0
const SPAWN_PLACEMENT_ATTEMPTS := 10

var zones: Array = []

var _player: Node3D = null
var _alive: Dictionary = {}          ## zone_id -> Array[WildCreature]
var _cooldown: Dictionary = {}       ## zone_id -> seconds until next spawn
var _blocked_rects: Array = []
var _rng := RandomNumberGenerator.new()
var _tick_accumulator: float = 0.0
var _mapa: String = ""
var _por_id: Dictionary = {}          ## id de rede -> WildCreature
var _esperando_resposta: int = 0      ## id cujo encontro foi pedido ao dono


func setup(map_data: Dictionary, player: Node3D) -> void:
	_rng.randomize()
	_player = player
	_mapa = String(map_data.get("id", ""))
	zones = map_data.get("zones", [])

	MundoRede.criatura_liberada.connect(_ao_liberar_do_dono)
	MundoRede.criatura_removida.connect(_ao_remover_do_dono)
	MundoRede.encontro_respondido.connect(_ao_responder_encontro)
	_blocked_rects.clear()
	for patch in map_data.get("terrain", []):
		if patch.get("kind", "") in ["water", "lava"]:
			_blocked_rects.append(patch.get("rect", []))

	for zone in zones:
		var zone_id: String = zone.get("id", "")
		_alive[zone_id] = []
		_cooldown[zone_id] = 0.0

	if not MundoRede.sou_o_dono():
		# Cliente: o mundo já existe do outro lado. Materializa o que o dono já
		# tinha mandado antes deste mapa ser construído.
		for registro in MundoRede.criaturas.values():
			_ao_liberar_do_dono(int(registro.get("id", 0)), registro)
		GameLog.info(
			GameLog.Channel.WORLD,
			"Spawner em modo cliente: %d criatura(s) vieram do dono." % total_alive()
		)
		return

	# Povoa na hora para o mapa não estar vazio na chegada.
	for zone in zones:
		var initial: int = maxi(1, int(zone.get("max_alive", 3)) - 1)
		for _i in initial:
			_spawn_in_zone(zone, true)

	GameLog.info(
		GameLog.Channel.WORLD,
		"Spawner pronto: %d zona(s), %d criatura(s) circulando." % [zones.size(), total_alive()]
	)


func total_alive() -> int:
	var count := 0
	for zone_id in _alive.keys():
		count += (_alive[zone_id] as Array).size()
	return count


func _process(delta: float) -> void:
	if not MundoRede.sou_o_dono():
		return
	_tick_accumulator += delta
	if _tick_accumulator < TICK_SECONDS:
		return
	var elapsed := _tick_accumulator
	_tick_accumulator = 0.0

	for zone in zones:
		var zone_id: String = zone.get("id", "")
		var living: Array = _alive.get(zone_id, [])
		living = living.filter(func(c): return is_instance_valid(c))
		_alive[zone_id] = living

		if living.size() >= int(zone.get("max_alive", 3)):
			continue
		_cooldown[zone_id] = float(_cooldown.get(zone_id, 0.0)) - elapsed
		if _cooldown[zone_id] > 0.0:
			continue
		if _spawn_in_zone(zone, false):
			_cooldown[zone_id] = float(zone.get("respawn_seconds", 25))
		else:
			# Player is standing in the zone; try again shortly.
			_cooldown[zone_id] = 2.0


func _spawn_in_zone(zone: Dictionary, ignore_player_distance: bool) -> bool:
	var creature := CreatureFactory.roll_wild(zone, _rng)
	if creature == null:
		return false
	# Explicitly Variant: _find_spawn_point returns a Vector2 or null, and Godot
	# rejects inferring a type from a Variant expression.
	var point: Variant = _find_spawn_point(zone, ignore_player_distance)
	if point == null:
		return false
	var spawn: Vector2 = point

	var node := _materializar(creature, spawn, zone)
	node.id_de_rede = MundoRede.registrar(
		_mapa, String(zone.get("id", "")), spawn, creature.to_dict()
	)
	_por_id[node.id_de_rede] = node

	(_alive[zone.get("id", "")] as Array).append(node)
	creature_spawned.emit(node)
	GameLog.verbose(
		GameLog.Channel.WORLD,
		"Nasceu %s Nv.%d em %s." % [creature.display_name(), creature.level, zone.get("name", "zone")]
	)
	return true


## Returns a Vector2 or null if no acceptable point was found.
func _find_spawn_point(zone: Dictionary, ignore_player_distance: bool) -> Variant:
	var rect: Array = zone.get("rect", [0, 0, 1, 1])
	for _attempt in SPAWN_PLACEMENT_ATTEMPTS:
		var point := Vector2(
			_rng.randf_range(minf(rect[0], rect[2]), maxf(rect[0], rect[2])),
			_rng.randf_range(minf(rect[1], rect[3]), maxf(rect[1], rect[3]))
		)
		if _in_blocked_rect(point):
			continue
		if not ignore_player_distance and _player != null and is_instance_valid(_player):
			var player_point := Vector2(_player.global_position.x, _player.global_position.z)
			if point.distance_to(player_point) < MIN_DISTANCE_FROM_PLAYER:
				continue
		return point
	return null


func _in_blocked_rect(point: Vector2) -> bool:
	for rect in _blocked_rects:
		if rect.size() != 4:
			continue
		if (
			point.x >= minf(rect[0], rect[2]) and point.x <= maxf(rect[0], rect[2])
			and point.y >= minf(rect[1], rect[3]) and point.y <= maxf(rect[1], rect[3])
		):
			return true
	return false


## Constrói o nó em cena. Separado do sorteio porque o cliente chega aqui pelo
## outro caminho: ele recebe a criatura pronta e só precisa da parte visual.
func _materializar(creature: CreatureData, spawn: Vector2, zone: Dictionary) -> WildCreature:
	var node := WildCreature.create(creature, Vector3(spawn.x, 0.0, spawn.y), zone)
	node.patrol_radius = 5.0
	node.encounter_triggered.connect(_on_encounter)
	node.despawned.connect(_on_despawned.bind(zone.get("id", "")))
	add_child(node)
	return node


func _zona_por_id(zona_id: String) -> Dictionary:
	for zone in zones:
		if String(zone.get("id", "")) == zona_id:
			return zone
	return {}


func _ao_liberar_do_dono(id: int, registro: Dictionary) -> void:
	if MundoRede.sou_o_dono() or _por_id.has(id):
		return
	if String(registro.get("mapa", "")) != _mapa:
		return   # criatura de outro mapa: existe no mundo, mas não nesta cena
	var criatura := CreatureData.from_dict(registro.get("criatura", {}))
	if criatura == null:
		return
	var zona := _zona_por_id(String(registro.get("zona", "")))
	var pos: Vector2 = registro.get("pos", Vector2.ZERO)
	var node := _materializar(criatura, pos, zona)
	node.id_de_rede = id
	_por_id[id] = node


func _ao_remover_do_dono(id: int) -> void:
	var node: WildCreature = _por_id.get(id, null)
	_por_id.erase(id)
	if node != null and is_instance_valid(node):
		node.despawn()


## Encostar numa criatura pede a batalha ao dono. Offline a resposta volta no
## mesmo quadro; numa partida ela leva uma ida e volta, e pode vir negada porque
## outro jogador chegou primeiro.
func _on_encounter(creature: WildCreature) -> void:
	if creature.id_de_rede == 0:
		encounter_triggered.emit(creature)
		return
	_esperando_resposta = creature.id_de_rede
	MundoRede.pedir_encontro(creature.id_de_rede)


func _ao_responder_encontro(id: int, permitido: bool) -> void:
	if id != _esperando_resposta:
		return
	_esperando_resposta = 0
	if not permitido:
		GameLog.verbose(GameLog.Channel.WORLD, "Encontro negado: criatura %d já está em batalha." % id)
		return
	var node: WildCreature = _por_id.get(id, null)
	if node != null and is_instance_valid(node):
		encounter_triggered.emit(node)


func _on_despawned(creature: WildCreature, zone_id: String) -> void:
	var living: Array = _alive.get(zone_id, [])
	living.erase(creature)
	_alive[zone_id] = living


## Tira a criatura do mundo depois de capturada ou derrotada. Quem manda é o
## dono: no cliente isto só chega de volta quando o dono confirmar.
func remove(creature: WildCreature) -> void:
	if not is_instance_valid(creature):
		return
	var id := creature.id_de_rede
	if id != 0:
		_por_id.erase(id)
		if MundoRede.sou_o_dono():
			MundoRede.remover(id)
		else:
			MundoRede.liberar_reserva(id)
	creature.despawn()
