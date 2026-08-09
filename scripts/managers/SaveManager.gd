extends Node
## Autoload: SaveManager
##
## Owns everything that touches disk: the save slot and the settings file.
## Writes go through a temp file + rename so a crash mid-write cannot leave a
## truncated save behind.
##
## The payload is plain JSON with a top-level "version" so a future migration
## step has something to switch on. Swapping this for a server call later only
## means replacing _write_file / _read_file.

signal game_saved(reason: String)
signal game_loaded()
signal save_deleted()

const SAVE_DIR := "user://saves/"
const SETTINGS_FILE := "user://settings.json"
const CURRENT_VERSION := 1
## Quantos personagens cabem ao mesmo tempo. A tela de seleção mostra um card
## por slot ocupado; no limite, criar exige apagar algum primeiro.
const MAX_SLOTS := 6

const AUTOSAVE_INTERVAL_SECONDS := 180.0

var settings: Dictionary = {
	"fullscreen": false,
	"vsync": true,
	"show_fps": false,
	"camera_zoom": 1.0,
	# Câmera padrão do jogo: atrás do personagem. A isométrica continua na tecla C.
	"camera_mode": "terceira_pessoa",
	"master_volume": 0.8,
}

var _autosave_timer: Timer = null
var _autosave_enabled: bool = false


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	_load_settings()
	_apply_settings()

	_autosave_timer = Timer.new()
	_autosave_timer.wait_time = AUTOSAVE_INTERVAL_SECONDS
	_autosave_timer.one_shot = false
	_autosave_timer.timeout.connect(_on_autosave_tick)
	add_child(_autosave_timer)


# --- save slot ----------------------------------------------------------------

func has_save(slot: int = 0) -> bool:
	return FileAccess.file_exists(_slot_path(slot))


## Primeiro slot livre, ou -1 se todos estiverem ocupados. A criação de
## personagem usa isto para decidir onde gravar sem perguntar nada.
func free_slot() -> int:
	for slot in MAX_SLOTS:
		if not has_save(slot):
			return slot
	return -1


static func _slot_path(slot: int) -> String:
	return "%sslot_%d.json" % [SAVE_DIR, slot]


static func _slot_tmp_path(slot: int) -> String:
	return "%sslot_%d.json.tmp" % [SAVE_DIR, slot]


## `slot` -1 significa "o personagem em andamento": quem manda é o
## `GameManager.slot_ativo`, que a criação e a continuação configuram.
func save_game(player: PlayerData, reason: String = "manual", slot: int = -1) -> bool:
	if player == null:
		GameLog.warn(GameLog.Channel.SAVE, "save_game() chamado sem dados de jogador.")
		return false
	var alvo := slot if slot >= 0 else GameManager.slot_ativo
	if alvo < 0 or alvo >= MAX_SLOTS:
		GameLog.warn(GameLog.Channel.SAVE, "save_game(): nenhum slot de personagem em turno.")
		return false

	player.last_seen_unix = int(Time.get_unix_time_from_system())
	var payload := {
		"version": CURRENT_VERSION,
		"saved_at": player.last_seen_unix,
		"app_version": ProjectSettings.get_setting("application/config/version", "0.0.0"),
		"player": player.to_dict(),
	}

	if not _write_file(_slot_tmp_path(alvo), JSON.stringify(payload, "\t")):
		return false
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		GameLog.error(GameLog.Channel.SAVE, "Não foi possível abrir %s" % SAVE_DIR)
		return false
	var nome := "slot_%d.json" % alvo
	if dir.file_exists(nome):
		dir.remove(nome)
	var err := dir.rename("slot_%d.json.tmp" % alvo, nome)
	if err != OK:
		GameLog.error(GameLog.Channel.SAVE, "Falha ao gravar o save (erro %d)" % err)
		return false

	GameLog.info(GameLog.Channel.SAVE, "Salvo no slot %d (%s)." % [alvo, reason])
	game_saved.emit(reason)
	return true


func load_game(slot: int = 0) -> PlayerData:
	if not has_save(slot):
		GameLog.info(GameLog.Channel.SAVE, "Nenhum save no slot %d." % slot)
		return null
	var text := _read_file(_slot_path(slot))
	if text == "":
		return null
	var payload: Variant = JSON.parse_string(text)
	if not (payload is Dictionary) or not payload.has("player"):
		GameLog.error(GameLog.Channel.SAVE, "Save corrompido; carregamento cancelado.")
		return null

	var version := int(payload.get("version", 0))
	if version > CURRENT_VERSION:
		GameLog.warn(
			GameLog.Channel.SAVE,
			"Save gravado por uma versão mais nova (v%d > v%d). Carregando mesmo assim." % [version, CURRENT_VERSION]
		)
	payload = _migrate(payload, version)

	var player := PlayerData.from_dict(payload["player"])
	GameLog.info(
		GameLog.Channel.SAVE,
		"Carregado '%s' - nível %d, %d criatura(s), mapa '%s'." % [
			player.display_name, player.level, player.collection_size(), player.current_map
		]
	)
	game_loaded.emit()
	return player


## Placeholder migration chain. Each future version bump adds one branch here.
func _migrate(payload: Dictionary, from_version: int) -> Dictionary:
	if from_version < 1:
		payload["version"] = 1
	return payload


func delete_save(slot: int = 0) -> bool:
	if not has_save(slot):
		return false
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return false
	var err := dir.remove("slot_%d.json" % slot)
	if err != OK:
		GameLog.error(GameLog.Channel.SAVE, "Não foi possível apagar o slot %d (erro %d)" % [slot, err])
		return false
	# O .tmp é resto de uma gravação interrompida; apagar junto evita o slot 0
	# renascer da lixeira num próximo `free_slot()`.
	dir.remove("slot_%d.json.tmp" % slot)
	GameLog.info(GameLog.Channel.SAVE, "Slot %d apagado." % slot)
	save_deleted.emit()
	return true


func save_metadata(slot: int = 0) -> Dictionary:
	if not has_save(slot):
		return {}
	var text := _read_file(_slot_path(slot))
	var payload: Variant = JSON.parse_string(text)
	if not (payload is Dictionary):
		return {}
	var player: Dictionary = payload.get("player", {})
	return {
		"name": player.get("name", "Treinador"),
		"level": int(player.get("level", 1)),
		"map": String(player.get("current_map", "")),
		"creatures": (player.get("collection", []) as Array).size(),
		"saved_at": int(payload.get("saved_at", 0)),
		"playtime": float(player.get("playtime", 0.0)),
	}


## Metadados de todos os slots ocupados, em ordem. Cada item traz o índice no
## campo "slot" para a tela de seleção saber onde continuar, apagar ou falar.
func save_slots() -> Array[Dictionary]:
	var resultado: Array[Dictionary] = []
	for slot in MAX_SLOTS:
		var meta := save_metadata(slot)
		if meta.is_empty():
			continue
		meta["slot"] = slot
		resultado.append(meta)
	return resultado


# --- autosave -----------------------------------------------------------------

func set_autosave_enabled(enabled: bool) -> void:
	_autosave_enabled = enabled
	if enabled:
		_autosave_timer.start()
	else:
		_autosave_timer.stop()


func _on_autosave_tick() -> void:
	if _autosave_enabled and GameManager.has_player():
		save_game(GameManager.player, "salvamento automático")


# --- settings -----------------------------------------------------------------

func _load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_FILE):
		return
	var parsed: Variant = JSON.parse_string(_read_file(SETTINGS_FILE))
	if parsed is Dictionary:
		for key in parsed.keys():
			settings[key] = parsed[key]


func save_settings() -> void:
	_write_file(SETTINGS_FILE, JSON.stringify(settings, "\t"))
	_apply_settings()


func set_setting(key: String, value: Variant) -> void:
	settings[key] = value
	save_settings()


func get_setting(key: String, default_value: Variant = null) -> Variant:
	return settings.get(key, default_value)


func _apply_settings() -> void:
	var mode := (
		DisplayServer.WINDOW_MODE_FULLSCREEN
		if bool(settings.get("fullscreen", false))
		else DisplayServer.WINDOW_MODE_WINDOWED
	)
	if DisplayServer.window_get_mode() != mode:
		DisplayServer.window_set_mode(mode)
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if bool(settings.get("vsync", true)) else DisplayServer.VSYNC_DISABLED
	)
	AudioServer.set_bus_volume_db(0, linear_to_db(clampf(float(settings.get("master_volume", 0.8)), 0.0, 1.0)))


# --- io -----------------------------------------------------------------------

func _write_file(path: String, text: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		GameLog.error(GameLog.Channel.SAVE, "Não foi possível escrever %s (erro %d)" % [path, FileAccess.get_open_error()])
		return false
	file.store_string(text)
	file.close()
	return true


func _read_file(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		GameLog.error(GameLog.Channel.SAVE, "Não foi possível ler %s (erro %d)" % [path, FileAccess.get_open_error()])
		return ""
	var text := file.get_as_text()
	file.close()
	return text
