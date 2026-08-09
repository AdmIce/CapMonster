class_name CreatureFactory
extends RefCounted
## Creation rules for creatures: rolling wild spawns from a zone table and the
## capture-chance formula. Stateless on purpose - every function is static so
## the world, the battle system and the debug menu share exactly one behaviour.


static func create(species_id: StringName, level: int) -> CreatureData:
	if not DataManager.has_species(species_id):
		GameLog.error(GameLog.Channel.CREATURE, "create(): espécie desconhecida '%s'" % species_id)
		return null
	return CreatureData.new(species_id, level)


## Picks a species from a zone table. Weights from the table are multiplied by
## the rarity's spawn_weight_modifier, so rare entries stay rare even when a
## designer types a generous weight.
static func roll_species(table: Array, rng: RandomNumberGenerator = null) -> StringName:
	if table.is_empty():
		return &""
	var weights: Array[float] = []
	var total := 0.0
	for row in table:
		var species: CreatureSpecies = DataManager.get_species(StringName(row.get("species", "")))
		if species == null:
			weights.append(0.0)
			continue
		var modifier := float(DataManager.get_rarity(species.rarity).get("spawn_weight_modifier", 1.0))
		var weight := maxf(0.0, float(row.get("weight", 0)) * modifier)
		weights.append(weight)
		total += weight
	if total <= 0.0:
		return &""

	var pick := (rng.randf() if rng != null else randf()) * total
	for i in table.size():
		pick -= weights[i]
		if pick <= 0.0:
			return StringName(table[i].get("species", ""))
	return StringName(table[table.size() - 1].get("species", ""))


## Rolls a full wild creature for a zone: species from the table, level inside
## the zone's range.
static func roll_wild(zone: Dictionary, rng: RandomNumberGenerator = null) -> CreatureData:
	var species_id := roll_species(zone.get("table", []), rng)
	if species_id == &"":
		return null
	var level_range: Array = zone.get("level_range", [1, 1])
	var low := int(level_range[0])
	var high := int(level_range[1]) if level_range.size() > 1 else low
	var level := rng.randi_range(low, high) if rng != null else randi_range(low, high)
	return create(species_id, level)


## Capture chance in 0..1.
## Weakening the target is the main lever; rarity and the core's power scale it.
static func capture_chance(target: CreatureData, item_power: float = 1.0) -> float:
	if target == null:
		return 0.0
	var species := target.species()
	if species == null or not species.is_capturable:
		return 0.0

	var curve := DataManager.progression
	# hp_factor goes from max (target nearly dead) down to min (untouched).
	var hp_factor: float = lerpf(curve.capture_hp_factor_max, curve.capture_hp_factor_min, target.hp_ratio())
	var rarity_modifier := DataManager.get_rarity_capture_modifier(species.rarity)
	var chance := species.capture_rate * hp_factor * rarity_modifier * maxf(0.1, item_power)
	return clampf(chance, curve.capture_min_chance, curve.capture_max_chance)


## XP a defeated creature awards, before any team-size split.
static func xp_reward(defeated: CreatureData) -> int:
	if defeated == null:
		return 0
	var species := defeated.species()
	if species == null:
		return 0
	var rarity_multiplier := DataManager.get_rarity_xp_multiplier(species.rarity)
	return maxi(1, int(round(float(species.xp_yield) * rarity_multiplier * (1.0 + 0.12 * float(defeated.level - 1)))))
