extends Node
## Autoload: DataManager
##
## Loads and indexes every JSON table in /data. Nothing else in the game is
## allowed to read those files directly; systems ask DataManager instead.
##
## Adding content = editing JSON. Run `python tools/validate_data.py` first.

signal data_loaded()

const DATA_DIR := "res://data/"

const FILES := {
	"elements": "elements.json",
	"rarities": "rarities.json",
	"progression": "progression.json",
	"skills": "skills.json",
	"creatures": "creatures.json",
	"items": "items.json",
	"maps": "maps.json",
	"roupas": "roupas.json",
	"classes": "classes.json",
	"quests": "quests.json",
	"intro": "intro.json",
}

## Rótulos em português para os identificadores internos, que continuam em inglês
## porque são chaves de código (e mexer neles quebraria saves e validadores).
const ROLE_NAMES := {
	"offense": "Ataque",
	"defense": "Defesa",
	"speed": "Velocidade",
	"support": "Suporte",
}

const SKILL_KIND_NAMES := {
	"damage": "Dano",
	"heal": "Cura",
	"buff": "Reforço",
	"debuff": "Enfraquecer",
}

const ITEM_CATEGORY_NAMES := {
	"capture": "Captura",
	"consumable": "Consumível",
	"material": "Material",
	"pet": "Companheiro",
	"quest": "Missão",
}

var progression: Progression = null

var _raw: Dictionary = {}
var _elements: Dictionary = {}          ## id -> element dict
var _element_chart: Dictionary = {}     ## attacker -> { defender: multiplier }
var _rarities: Dictionary = {}          ## id -> rarity dict
var _skills: Dictionary = {}            ## id -> skill dict
var _species: Dictionary = {}           ## id -> CreatureSpecies
var _items: Dictionary = {}             ## id -> item dict
var _maps: Dictionary = {}              ## id -> map dict
var _map_order: Array[String] = []
var _quests: Dictionary = {}            ## id -> quest dict

var _default_multiplier: float = 1.0
var is_loaded: bool = false


func _ready() -> void:
	load_all()


func load_all() -> bool:
	_raw.clear()
	for key in FILES.keys():
		var doc: Variant = _read_json(DATA_DIR + FILES[key])
		if doc == null:
			GameLog.error(GameLog.Channel.DATA, "Falha ao carregar %s - o jogo não pode iniciar." % FILES[key])
			return false
		_raw[key] = doc

	_index_elements()
	_index_rarities()
	progression = Progression.new(_raw["progression"])
	_index_skills()
	_index_species()
	_index_items()
	_index_maps()
	_index_quests()

	is_loaded = true
	GameLog.info(
		GameLog.Channel.DATA,
		"Carregado: %d espécies, %d habilidades, %d itens, %d mapas, %d missões." % [
			_species.size(), _skills.size(), _items.size(), _maps.size(), _quests.size()
		]
	)
	data_loaded.emit()
	return true


func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		GameLog.error(GameLog.Channel.DATA, "Arquivo de dados ausente: %s" % path)
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		GameLog.error(GameLog.Channel.DATA, "Não foi possível abrir %s (erro %d)" % [path, FileAccess.get_open_error()])
		return null
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		GameLog.error(GameLog.Channel.DATA, "JSON inválido em %s" % path)
		return null
	return parsed


# --- indexing -----------------------------------------------------------------

func _index_elements() -> void:
	_elements.clear()
	_element_chart.clear()
	var doc: Dictionary = _raw["elements"]
	_default_multiplier = float(doc.get("default_multiplier", 1.0))
	for element in doc.get("elements", []):
		_elements[element["id"]] = element
	for attacker in doc.get("chart", {}).keys():
		_element_chart[attacker] = doc["chart"][attacker]


func _index_rarities() -> void:
	_rarities.clear()
	for rarity in _raw["rarities"].get("rarities", []):
		_rarities[rarity["id"]] = rarity


func _index_skills() -> void:
	_skills.clear()
	for skill in _raw["skills"].get("skills", []):
		_skills[skill["id"]] = skill


func _index_species() -> void:
	_species.clear()
	for entry in _raw["creatures"].get("creatures", []):
		var species := CreatureSpecies.new(entry)
		# Keyed by String, never StringName: callers pass both and Dictionary
		# lookups do not treat the two as the same key.
		_species[String(species.id)] = species


func _index_items() -> void:
	_items.clear()
	for item in _raw["items"].get("items", []):
		_items[item["id"]] = item


func _index_maps() -> void:
	_maps.clear()
	_map_order.clear()
	var entries: Array = _raw["maps"].get("maps", [])
	entries.sort_custom(func(a, b): return int(a.get("order", 0)) < int(b.get("order", 0)))
	for map_data in entries:
		_maps[map_data["id"]] = map_data
		_map_order.append(map_data["id"])


func _index_quests() -> void:
	_quests.clear()
	for quest in _raw["quests"].get("quests", []):
		_quests[quest["id"]] = quest


# --- elements -----------------------------------------------------------------

func get_element(element_id: String) -> Dictionary:
	return _elements.get(element_id, {})


func get_element_name(element_id: String) -> String:
	return _elements.get(element_id, {}).get("name", element_id.capitalize())


func get_element_color(element_id: String) -> Color:
	return _color_of(_elements.get(element_id, {}).get("color", "#9AA3AD"))


## Damage multiplier when `attacker` hits `defender`.
func element_multiplier(attacker: String, defender: String) -> float:
	var row: Dictionary = _element_chart.get(attacker, {})
	return float(row.get(defender, _default_multiplier))


# --- rarities -----------------------------------------------------------------

func get_rarity(rarity_id: String) -> Dictionary:
	return _rarities.get(rarity_id, {})


func get_rarity_name(rarity_id: String) -> String:
	return _rarities.get(rarity_id, {}).get("name", rarity_id.capitalize())


func get_rarity_color(rarity_id: String) -> Color:
	return _color_of(_rarities.get(rarity_id, {}).get("color", "#9AA3AD"))


func get_rarity_order(rarity_id: String) -> int:
	return int(_rarities.get(rarity_id, {}).get("order", 0))


func get_rarity_stat_multiplier(rarity_id: String) -> float:
	return float(_rarities.get(rarity_id, {}).get("stat_multiplier", 1.0))


func get_rarity_capture_modifier(rarity_id: String) -> float:
	return float(_rarities.get(rarity_id, {}).get("capture_modifier", 1.0))


func get_rarity_xp_multiplier(rarity_id: String) -> float:
	return float(_rarities.get(rarity_id, {}).get("xp_yield_multiplier", 1.0))


# --- skills / species / items -------------------------------------------------

func get_skill(skill_id: String) -> Dictionary:
	return _skills.get(skill_id, {})


func get_species(species_id: Variant) -> CreatureSpecies:
	return _species.get(String(species_id), null)


func has_species(species_id: Variant) -> bool:
	return _species.has(String(species_id))


func all_species() -> Array:
	return _species.values()


func get_starters() -> Array:
	var result: Array = []
	for species in _species.values():
		if species.is_starter:
			result.append(species)
	result.sort_custom(func(a, b): return a.id < b.id)
	return result


func get_item(item_id: String) -> Dictionary:
	return _items.get(item_id, {})


func get_item_name(item_id: String) -> String:
	return _items.get(item_id, {}).get("name", item_id)


func get_item_color(item_id: String) -> Color:
	return _color_of(_items.get(item_id, {}).get("color", "#9AA3AD"))


func all_items() -> Array:
	return _items.values()


func get_starting_inventory() -> Dictionary:
	return (_raw["items"].get("starting_inventory", {}) as Dictionary).duplicate(true)


# --- maps / quests ------------------------------------------------------------

## As classes do jogador, na ordem em que a criacao mostra.
func classes() -> Array:
	return _raw.get("classes", {}).get("classes", [])


## A classe por id, ou a primeira quando o id nao existe -- personagem salvo
## antes das classes existirem cai na primeira em vez de ficar sem nenhuma.
func classe(id: String) -> Dictionary:
	var lista := classes()
	for c in lista:
		if String(c.get("id", "")) == id:
			return c
	return lista[0] if not lista.is_empty() else {}


## Conjuntos de roupa do kit modular, por sexo do corpo.
func conjuntos_de_roupa(sexo: String) -> Array:
	return _raw.get("roupas", {}).get("conjuntos", {}).get(sexo, [])


## Todas as pecas que existem para um sexo. E a lista que o guarda-roupa mostra.
func pecas_de_roupa(sexo: String) -> Array:
	return _raw.get("roupas", {}).get("pecas_disponiveis", {}).get(sexo, [])


func get_map(map_id: String) -> Dictionary:
	return _maps.get(map_id, {})


func has_map(map_id: String) -> bool:
	return _maps.has(map_id)


func get_map_name(map_id: String) -> String:
	return _maps.get(map_id, {}).get("name", map_id)


func map_ids() -> Array[String]:
	return _map_order.duplicate()


func first_map_id() -> String:
	return _map_order[0] if not _map_order.is_empty() else ""


func get_quest(quest_id: String) -> Dictionary:
	return _quests.get(quest_id, {})


## Roteiro da abertura (data/intro.json).
func get_intro() -> Dictionary:
	return _raw.get("intro", {})


func get_role_name(role_id: String) -> String:
	return ROLE_NAMES.get(role_id, role_id)


func get_skill_kind_name(kind_id: String) -> String:
	return SKILL_KIND_NAMES.get(kind_id, kind_id)


func get_item_category_name(category_id: String) -> String:
	return ITEM_CATEGORY_NAMES.get(category_id, category_id)


func all_quests() -> Array:
	return _quests.values()


# --- helpers ------------------------------------------------------------------

static func _color_of(hex: String) -> Color:
	return Color.html(hex) if hex.begins_with("#") else Color.WHITE
