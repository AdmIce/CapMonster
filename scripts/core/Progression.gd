class_name Progression
extends RefCounted
## Owns every XP / stat curve in the game. Built by DataManager from
## data/progression.json and exposed as DataManager.progression.
##
## Keeping the maths in one small object means designers tune JSON, not code,
## and battle/idle systems never invent their own formulas.

var player_max_level: int = 20
var player_base_xp: float = 40.0
var player_exponent: float = 1.6

var creature_max_level: int = 30
var creature_base_xp: float = 28.0
var creature_exponent: float = 1.5

var stat_growth: float = 0.075
var hp_growth: float = 0.095

var critical_chance: float = 0.05
var critical_multiplier: float = 1.6
var random_variation: float = 0.12
var defense_softening: float = 55.0
var minimum_damage: int = 1

var capture_hp_factor_min: float = 0.35
var capture_hp_factor_max: float = 1.75
var capture_min_chance: float = 0.02
var capture_max_chance: float = 0.95

var idle_max_offline_hours: float = 8.0
var idle_gold_per_hour: float = 120.0
var idle_player_xp_per_hour: float = 55.0
var idle_creature_xp_per_hour: float = 70.0
var idle_material_chance_per_hour: float = 0.45


func _init(config: Dictionary = {}) -> void:
	if config.is_empty():
		return
	var player: Dictionary = config.get("player", {})
	player_max_level = int(player.get("max_level", player_max_level))
	player_base_xp = float(player.get("base_xp", player_base_xp))
	player_exponent = float(player.get("exponent", player_exponent))

	var creature: Dictionary = config.get("creature", {})
	creature_max_level = int(creature.get("max_level", creature_max_level))
	creature_base_xp = float(creature.get("base_xp", creature_base_xp))
	creature_exponent = float(creature.get("exponent", creature_exponent))

	var stats: Dictionary = config.get("creature_stats", {})
	stat_growth = float(stats.get("growth_per_level", stat_growth))
	hp_growth = float(stats.get("hp_growth_per_level", hp_growth))

	var combat: Dictionary = config.get("combat", {})
	critical_chance = float(combat.get("critical_chance", critical_chance))
	critical_multiplier = float(combat.get("critical_multiplier", critical_multiplier))
	random_variation = float(combat.get("random_variation", random_variation))
	defense_softening = float(combat.get("defense_softening", defense_softening))
	minimum_damage = int(combat.get("minimum_damage", minimum_damage))

	var capture: Dictionary = config.get("capture", {})
	capture_hp_factor_min = float(capture.get("hp_factor_min", capture_hp_factor_min))
	capture_hp_factor_max = float(capture.get("hp_factor_max", capture_hp_factor_max))
	capture_min_chance = float(capture.get("min_chance", capture_min_chance))
	capture_max_chance = float(capture.get("max_chance", capture_max_chance))

	var idle: Dictionary = config.get("idle", {})
	idle_max_offline_hours = float(idle.get("max_offline_hours", idle_max_offline_hours))
	idle_gold_per_hour = float(idle.get("gold_per_hour", idle_gold_per_hour))
	idle_player_xp_per_hour = float(idle.get("player_xp_per_hour", idle_player_xp_per_hour))
	idle_creature_xp_per_hour = float(idle.get("creature_xp_per_hour", idle_creature_xp_per_hour))
	idle_material_chance_per_hour = float(
		idle.get("material_chance_per_hour", idle_material_chance_per_hour)
	)


## XP required to advance from `level` to `level + 1`.
func player_xp_to_next(level: int) -> int:
	if level >= player_max_level:
		return 0
	return int(floor(player_base_xp * pow(float(level), player_exponent)))


func creature_xp_to_next(level: int) -> int:
	if level >= creature_max_level:
		return 0
	return int(floor(creature_base_xp * pow(float(level), creature_exponent)))


## Scales a base stat to a level, applying the rarity multiplier.
func scale_stat(base_value: float, level: int, rarity_multiplier: float, is_hp: bool = false) -> int:
	var growth := hp_growth if is_hp else stat_growth
	var value := base_value * (1.0 + growth * float(level - 1)) * rarity_multiplier
	return maxi(1, int(round(value)))
