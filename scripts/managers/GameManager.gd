extends Node
## Autoload: GameManager
##
## Session lifecycle only: who is playing, starting a new run, continuing an old
## one, and the handful of save triggers. It deliberately does NOT know how
## battles, quests or inventories work - those managers own their own rules and
## read the player through GameManager.player.

signal session_started(player: PlayerData)
signal session_ended()
signal starter_chosen(creature: CreatureData)
signal map_changed(map_id: String, spawn_point: String)

## Verdadeiro quando este processo é um servidor dedicado: sem jogador local,
## sem câmera e sem interface. O mundo roda só pela regra.
var modo_servidor: bool = false

var player: PlayerData = null
var is_in_session: bool = false
## Slot do save onde mora o personagem em sessão. Sem personagem (-1) não há
## onde gravar: criar um jogo novo escolhe o primeiro slot livre.
var slot_ativo: int = -1
## Recompensa offline é paga uma vez por sessão, não a cada troca de mapa.
## Runtime puro: não vai para o save, senão nunca mais pagaria.
var idle_processado: bool = false
## Set while a save is being loaded so systems can skip transient reactions.
var is_restoring: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().auto_accept_quit = false


func _process(delta: float) -> void:
	if is_in_session and player != null:
		player.playtime_seconds += delta


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		quit_game()


func has_player() -> bool:
	return player != null


# --- lifecycle ----------------------------------------------------------------

## Creates a fresh player. The starter is chosen right after, in StarterChoice.
## `slot` -1 deixa o SaveManager escolher o primeiro slot livre; -1 continua
## quando todos estão ocupados, porque criar sobre outro personagem nunca é a
## intenção.
func new_game(display_name: String, appearance: Dictionary, slot: int = -1) -> PlayerData:
	if slot < 0:
		slot = SaveManager.free_slot()
	if slot < 0:
		GameLog.warn(
			GameLog.Channel.SYSTEM,
			"Todos os %d slots de personagem estão ocupados." % SaveManager.MAX_SLOTS
		)
		return null
	slot_ativo = slot
	player = PlayerData.new()
	player.display_name = display_name.strip_edges()
	if player.display_name == "":
		player.display_name = "Treinador"
	player.appearance = appearance.duplicate()

	var first_map := DataManager.first_map_id()
	player.current_map = first_map
	player.spawn_point = "start"
	player.unlock_map(first_map)

	var starting_items := DataManager.get_starting_inventory()
	for item_id in starting_items.keys():
		player.add_item(String(item_id), int(starting_items[item_id]))

	GameLog.info(GameLog.Channel.SYSTEM, "Jogo novo iniciado para '%s'." % player.display_name)
	return player


func choose_starter(species_id: StringName) -> CreatureData:
	if player == null:
		GameLog.error(GameLog.Channel.SYSTEM, "choose_starter() chamado antes de new_game().")
		return null
	var creature := CreatureFactory.create(species_id, 5)
	if creature == null:
		return null
	player.starter_species = String(species_id)
	player.add_creature(creature)
	GameLog.info(GameLog.Channel.CREATURE, "Criatura inicial escolhida: %s." % creature.display_name())
	starter_chosen.emit(creature)
	return creature


## Marks the session as live. Called once the world scene is about to load.
func begin_session() -> void:
	if player == null:
		return
	is_in_session = true
	idle_processado = false
	SaveManager.set_autosave_enabled(true)
	session_started.emit(player)


func continue_game(slot: int = 0) -> bool:
	var loaded := SaveManager.load_game(slot)
	if loaded == null:
		return false
	slot_ativo = slot
	is_restoring = true
	player = loaded
	if not DataManager.has_map(player.current_map):
		GameLog.warn(
			GameLog.Channel.SAVE,
			"O mapa salvo '%s' não existe mais; voltando para o primeiro mapa." % player.current_map
		)
		player.current_map = DataManager.first_map_id()
		player.spawn_point = "start"
		player.has_exact_position = false
	is_restoring = false
	return true


func end_session(save_first: bool = true) -> void:
	if save_first and player != null:
		SaveManager.save_game(player, "fim de sessão")
	SaveManager.set_autosave_enabled(false)
	is_in_session = false
	player = null
	session_ended.emit()


func quit_game() -> void:
	if is_in_session and player != null:
		SaveManager.save_game(player, "saída")
	SaveManager.save_settings()
	GameLog.info(GameLog.Channel.SYSTEM, "Encerrando.")
	get_tree().quit()


# --- save triggers ------------------------------------------------------------

## Autosave points defined in the design doc: map change, capture, battle end,
## plus the periodic timer inside SaveManager.
func save_now(reason: String) -> void:
	if player != null:
		SaveManager.save_game(player, reason)


# --- world helpers ------------------------------------------------------------

func record_position(position: Vector2) -> void:
	if player == null:
		return
	player.last_position = position
	player.has_exact_position = true


func can_enter_map(map_id: String) -> bool:
	if player == null or not DataManager.has_map(map_id):
		return false
	return player.is_map_unlocked(map_id)


## Moves the player to another map and reloads the world scene.
func travel_to_map(map_id: String, spawn_point: String = "start") -> bool:
	if player == null or not DataManager.has_map(map_id):
		GameLog.warn(GameLog.Channel.WORLD, "travel_to_map(): mapa desconhecido '%s'." % map_id)
		return false
	player.unlock_map(map_id)
	player.current_map = map_id
	player.spawn_point = spawn_point
	player.has_exact_position = false
	save_now("troca de mapa")
	map_changed.emit(map_id, spawn_point)
	SceneFlow.goto_world()
	return true
