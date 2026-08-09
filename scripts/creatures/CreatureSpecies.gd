class_name CreatureSpecies
extends RefCounted
## Immutable description of a species, parsed once from data/creatures.json.
##
## A species is the template. A CreatureData is one owned instance of it.

var id: StringName = &""
var name: String = ""
var element: String = ""
var rarity: String = "common"
var role: String = "offense"
var description: String = ""

var base_hp: float = 1.0
var base_attack: float = 1.0
var base_defense: float = 1.0
var base_speed: float = 1.0

var skills: Array[String] = []
var capture_rate: float = 0.0
var xp_yield: int = 10

var is_capturable: bool = false
var is_obtainable: bool = false
var is_starter: bool = false
var boss_tier: String = ""          ## "" | "mini" | "boss"

var model_path: String = ""
var icon_path: String = ""
## Ajustes de encaixe para modelos importados, que quase nunca vêm na escala e
## na orientação que o jogo usa (personagens olhando para -Z, ~1,2 unidade).
var model_scale: float = 1.0
var model_offset_y: float = 0.0
var model_yaw: float = 0.0
## Muitos exports vêm com Z para cima (padrão do Blender); -90 aqui põe o bicho
## de pé sem precisar reexportar nada.
var model_pitch: float = 0.0

var evolves_to: StringName = &""
var evolution_level: int = 0

var spawn_maps: Array[String] = []

## Placeholder-model description. Consumed by CreatureModelBuilder while real
## art is missing; ignored once `model_path` points at a real scene.
var visual: Dictionary = {}


func _init(source: Dictionary = {}) -> void:
	if source.is_empty():
		return
	id = StringName(source.get("id", ""))
	name = source.get("name", str(id))
	element = source.get("element", "nature")
	rarity = source.get("rarity", "common")
	role = source.get("role", "offense")
	description = source.get("description", "")

	var stats: Dictionary = source.get("base_stats", {})
	base_hp = float(stats.get("hp", 1))
	base_attack = float(stats.get("attack", 1))
	base_defense = float(stats.get("defense", 1))
	base_speed = float(stats.get("speed", 1))

	for skill_id in source.get("skills", []):
		skills.append(String(skill_id))

	capture_rate = float(source.get("capture_rate", 0.0))
	xp_yield = int(source.get("xp_yield", 10))

	is_capturable = bool(source.get("capturable", false))
	is_obtainable = bool(source.get("obtainable", false))
	is_starter = bool(source.get("starter", false))
	boss_tier = source.get("boss_tier", "")

	model_path = source.get("model_path", "")
	icon_path = source.get("icon_path", "")
	model_scale = float(source.get("model_scale", 1.0))
	model_offset_y = float(source.get("model_offset_y", 0.0))
	model_yaw = float(source.get("model_yaw", 0.0))
	model_pitch = float(source.get("model_pitch", 0.0))

	var evolution: Variant = source.get("evolution", null)
	if evolution is Dictionary:
		evolves_to = StringName(evolution.get("to", ""))
		evolution_level = int(evolution.get("level", 0))

	for map_id in source.get("spawn_maps", []):
		spawn_maps.append(String(map_id))

	visual = (source.get("visual", {}) as Dictionary).duplicate(true)


func has_evolution() -> bool:
	return evolves_to != &"" and evolution_level > 0


func is_boss() -> bool:
	return boss_tier != ""


func primary_skill_id() -> String:
	return skills[0] if skills.size() > 0 else ""


func secondary_skill_id() -> String:
	return skills[1] if skills.size() > 1 else ""


func visual_color(key: String, fallback: Color = Color(0.6, 0.6, 0.6)) -> Color:
	var hex: String = visual.get(key, "")
	return Color.html(hex) if hex.begins_with("#") else fallback


func visual_features() -> Array:
	return visual.get("features", [])


func has_feature(feature: String) -> bool:
	return visual_features().has(feature)


func visual_body() -> String:
	return visual.get("body", "quadruped")


func visual_size() -> float:
	return float(visual.get("size", 1.0))
