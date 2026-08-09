class_name CreatureData
extends RefCounted
## One owned creature. Persistent state only (level, xp, current hp, nickname);
## every derived stat is recomputed from the species so a balance pass in JSON
## instantly applies to creatures already in a save file.

signal leveled_up(new_level: int)
signal evolved(from_species: StringName, to_species: StringName)
signal hp_changed(current: int, maximum: int)
signal died()

const SAVE_VERSION := 1

var uid: String = ""
var species_id: StringName = &""
var nickname: String = ""
var level: int = 1
var xp: int = 0
var current_hp: int = 1
var captured_at_unix: int = 0
var is_favourite: bool = false

var _species: CreatureSpecies = null


func _init(p_species_id: StringName = &"", p_level: int = 1, p_uid: String = "") -> void:
	if p_species_id == &"":
		return
	species_id = p_species_id
	level = maxi(1, p_level)
	uid = p_uid if p_uid != "" else _generate_uid()
	captured_at_unix = int(Time.get_unix_time_from_system())
	_resolve_species()
	current_hp = max_hp()


static func _generate_uid() -> String:
	return "c_%d_%d" % [Time.get_ticks_usec(), randi() % 100000]


func _resolve_species() -> void:
	_species = DataManager.get_species(species_id)
	if _species == null:
		GameLog.error(GameLog.Channel.CREATURE, "Espécie desconhecida: '%s'" % species_id)


func species() -> CreatureSpecies:
	if _species == null:
		_resolve_species()
	return _species


# --- identity -----------------------------------------------------------------

func display_name() -> String:
	if nickname != "":
		return nickname
	var s := species()
	return s.name if s != null else String(species_id)


func element() -> String:
	var s := species()
	return s.element if s != null else "nature"


func rarity() -> String:
	var s := species()
	return s.rarity if s != null else "common"


# --- derived stats ------------------------------------------------------------

func _rarity_multiplier() -> float:
	return DataManager.get_rarity_stat_multiplier(rarity())


func max_hp() -> int:
	var s := species()
	if s == null:
		return 1
	return DataManager.progression.scale_stat(s.base_hp, level, _rarity_multiplier(), true)


func attack() -> int:
	var s := species()
	if s == null:
		return 1
	return DataManager.progression.scale_stat(s.base_attack, level, _rarity_multiplier())


func defense() -> int:
	var s := species()
	if s == null:
		return 1
	return DataManager.progression.scale_stat(s.base_defense, level, _rarity_multiplier())


func speed() -> int:
	var s := species()
	if s == null:
		return 1
	return DataManager.progression.scale_stat(s.base_speed, level, _rarity_multiplier())


func stats() -> Dictionary:
	return {
		"hp": max_hp(),
		"attack": attack(),
		"defense": defense(),
		"speed": speed(),
	}


func skill_ids() -> Array[String]:
	var s := species()
	if s == null:
		return []
	return s.skills.duplicate()


# --- health -------------------------------------------------------------------

func is_alive() -> bool:
	return current_hp > 0


func hp_ratio() -> float:
	var maximum := max_hp()
	return 0.0 if maximum <= 0 else clampf(float(current_hp) / float(maximum), 0.0, 1.0)


func apply_damage(amount: int) -> int:
	if amount <= 0 or not is_alive():
		return 0
	var before := current_hp
	current_hp = maxi(0, current_hp - amount)
	hp_changed.emit(current_hp, max_hp())
	if current_hp == 0:
		died.emit()
		GameLog.verbose(GameLog.Channel.BATTLE, "%s foi derrubado." % display_name())
	return before - current_hp


func heal(amount: int) -> int:
	if amount <= 0:
		return 0
	var maximum := max_hp()
	var before := current_hp
	current_hp = mini(maximum, current_hp + amount)
	hp_changed.emit(current_hp, maximum)
	return current_hp - before


func full_heal() -> void:
	current_hp = max_hp()
	hp_changed.emit(current_hp, current_hp)


# --- progression --------------------------------------------------------------

func xp_to_next_level() -> int:
	return DataManager.progression.creature_xp_to_next(level)


func is_max_level() -> bool:
	return level >= DataManager.progression.creature_max_level


## Grants xp and resolves every level-up it triggers.
## Returns how many levels were gained.
func grant_xp(amount: int) -> int:
	if amount <= 0 or is_max_level():
		return 0
	xp += amount
	var gained := 0
	while not is_max_level():
		var needed := xp_to_next_level()
		if needed <= 0 or xp < needed:
			break
		xp -= needed
		level += 1
		gained += 1
		# Levelling restores the health the new maximum adds, not the whole bar.
		current_hp = mini(max_hp(), current_hp + int(round(max_hp() * 0.1)))
		leveled_up.emit(level)
	if gained > 0:
		GameLog.info(GameLog.Channel.CREATURE, "%s chegou ao nível %d." % [display_name(), level])
	if is_max_level():
		xp = 0
	return gained


func can_evolve() -> bool:
	var s := species()
	if s == null or not s.has_evolution():
		return false
	if not DataManager.has_species(s.evolves_to):
		return false
	return level >= s.evolution_level


## Applies the evolution in place, keeping level, xp and hp ratio.
func evolve() -> bool:
	if not can_evolve():
		return false
	var from_id := species_id
	var ratio := hp_ratio()
	species_id = species().evolves_to
	_species = null
	_resolve_species()
	current_hp = maxi(1, int(round(max_hp() * ratio)))
	GameLog.info(
		GameLog.Channel.CREATURE,
		"%s evoluiu para %s." % [String(from_id), display_name()]
	)
	evolved.emit(from_id, species_id)
	return true


# --- serialisation ------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"v": SAVE_VERSION,
		"uid": uid,
		"species": String(species_id),
		"nickname": nickname,
		"level": level,
		"xp": xp,
		"hp": current_hp,
		"captured_at": captured_at_unix,
		"favourite": is_favourite,
	}


static func from_dict(source: Dictionary) -> CreatureData:
	var species_id := StringName(source.get("species", ""))
	if not DataManager.has_species(species_id):
		GameLog.warn(GameLog.Channel.SAVE, "Criatura salva descartada: espécie desconhecida '%s'" % species_id)
		return null
	var creature := CreatureData.new(species_id, int(source.get("level", 1)), source.get("uid", ""))
	creature.nickname = source.get("nickname", "")
	creature.xp = int(source.get("xp", 0))
	creature.current_hp = clampi(int(source.get("hp", creature.max_hp())), 0, creature.max_hp())
	creature.captured_at_unix = int(source.get("captured_at", 0))
	creature.is_favourite = bool(source.get("favourite", false))
	return creature
