class_name PlayerData
extends RefCounted
## The whole persistent player state: identity, appearance, wallet, collection,
## active team, inventory, world position and progression flags.
##
## This object is the single source of truth that SaveManager serialises.

signal level_changed(new_level: int)
signal xp_changed(current: int, needed: int)
signal gold_changed(amount: int)
signal team_changed()
signal collection_changed()
signal inventory_changed(item_id: String, new_count: int)

const SAVE_VERSION := 1
const TEAM_SIZE := 3

var display_name: String = "Treinador"

## Classe escolhida na criacao (espadachim, gatuno, mago, sacerdote).
##
## Guardada por **id de texto**, e nao pelo indice da lista: reordenar as
## classes um dia nao pode transformar o Mago de alguem em Sacerdote. Foi o erro
## que ja aconteceu aqui com cabelo e roupa, que sao guardados por indice.
var classe_id: String = "espadachim"

## Identidade do jogador, sorteada uma vez e guardada no save.
##
## O servidor guarda a ficha de cada um por **isto**, e nao pelo nome. Guardar
## por nome parece obvio e quebra na primeira partida de verdade: todo mundo
## comeca como "Treinador", entao dois amigos entravam no mesmo mundo e
## dividiam o mesmo personagem - aparencia de um aparecia no outro, e o ouro era
## o mesmo saldo para os dois.
##
## Trocar o nome no jogo nao muda a identidade: o nome e enfeite, isto e cadastro.
var jogador_id: String = ""
## Keys: body, hair, hair_color, skin, outfit. Values are indices into the
## presets in CharacterCreation / PlayerAvatar.
var appearance: Dictionary = {
	"body": 0,
	"hair": 0,
	"hair_color": 0,
	"skin": 0,
	"outfit": 0,
}

var level: int = 1
var xp: int = 0

## --- o jogador como combatente ---------------------------------------------
##
## Ate agora a vida na tela era a da criatura lider: o jogador nao lutava, ele
## mandava lutar. Com o combate de acao quem apanha e ele, entao ele precisa dos
## proprios numeros.
##
## Sao **derivados** de nivel e classe, e nao guardados um a um. Guardar
## atributo no save engessa o balanceamento: mexer numa formula deixaria de
## valer para quem ja jogava, e a primeira coisa que este jogo vai precisar e
## mexer nas formulas.
const VIDA_BASE := 60
const VIDA_POR_NIVEL := 12
const ATAQUE_BASE := 10
const ATAQUE_POR_NIVEL := 2
const DEFESA_BASE := 6
const DEFESA_POR_NIVEL := 1

## A unica coisa de combate que **e** guardada: quanto de vida sobrou.
var vida_atual: int = -1


func classe() -> Dictionary:
	return DataManager.classe(classe_id)


func vida_maxima() -> int:
	var mult := float(classe().get("vida", 1.0))
	return maxi(1, int(round((VIDA_BASE + VIDA_POR_NIVEL * (level - 1)) * mult)))


func ataque() -> int:
	var mult := float(classe().get("ataque", 1.0))
	return maxi(1, int(round((ATAQUE_BASE + ATAQUE_POR_NIVEL * (level - 1)) * mult)))


func defesa() -> int:
	var mult := float(classe().get("defesa", 1.0))
	return maxi(0, int(round((DEFESA_BASE + DEFESA_POR_NIVEL * (level - 1)) * mult)))


## Fracao de vida, para a barra. Cheio quando ainda nao ha valor guardado --
## personagem novo nasce inteiro, nao pela metade.
func vida_fracao() -> float:
	var maxima := vida_maxima()
	if vida_atual < 0:
		return 1.0
	return clampf(float(vida_atual) / float(maxi(1, maxima)), 0.0, 1.0)


## Devolve quanto tirou de fato. Nunca passa de zero: vida negativa vira numero
## estranho na tela e conta errada na proxima cura.
func sofrer_dano(quantia: int) -> int:
	if vida_atual < 0:
		vida_atual = vida_maxima()
	var antes := vida_atual
	vida_atual = maxi(0, vida_atual - maxi(0, quantia))
	return antes - vida_atual


func curar(quantia: int) -> int:
	var maxima := vida_maxima()
	if vida_atual < 0:
		vida_atual = maxima
	var antes := vida_atual
	vida_atual = mini(maxima, vida_atual + maxi(0, quantia))
	return vida_atual - antes


func restaurar_vida() -> void:
	vida_atual = vida_maxima()


func esta_vivo() -> bool:
	return vida_atual != 0

var gold: int = 250

var current_map: String = ""
var spawn_point: String = "start"
## Exact position inside the map, so reloading puts the player back where they
## stood rather than at the map entrance.
var last_position: Vector2 = Vector2.ZERO
var has_exact_position: bool = false

var collection: Array[CreatureData] = []
var team_uids: Array[String] = []
var inventory: Dictionary = {}          ## item_id -> count

var quest_state: Dictionary = {}        ## quest_id -> { status, progress }
var flags: Dictionary = {}              ## generic progression flags
var unlocked_maps: Array[String] = []
var defeated_bosses: Array[String] = []
var defeated_mini_bosses: Array[String] = []
var cleared_zones: Array[String] = []

var created_at_unix: int = 0
var last_seen_unix: int = 0
var playtime_seconds: float = 0.0
var starter_species: String = ""


func _init() -> void:
	jogador_id = _sortear_id()
	created_at_unix = int(Time.get_unix_time_from_system())
	last_seen_unix = created_at_unix


# --- wallet & progression -----------------------------------------------------

func add_gold(amount: int) -> void:
	if amount == 0:
		return
	gold = maxi(0, gold + amount)
	gold_changed.emit(gold)


func spend_gold(amount: int) -> bool:
	if amount <= 0 or gold < amount:
		return false
	gold -= amount
	gold_changed.emit(gold)
	return true


func xp_to_next_level() -> int:
	return DataManager.progression.player_xp_to_next(level)


func is_max_level() -> bool:
	return level >= DataManager.progression.player_max_level


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
		level_changed.emit(level)
	if is_max_level():
		xp = 0
	xp_changed.emit(xp, xp_to_next_level())
	return gained


# --- collection ---------------------------------------------------------------

func add_creature(creature: CreatureData) -> void:
	if creature == null:
		return
	collection.append(creature)
	collection_changed.emit()
	# First creature always goes straight into the team.
	if team_uids.size() < TEAM_SIZE:
		equip_creature(creature.uid)


func remove_creature(uid: String) -> bool:
	for i in collection.size():
		if collection[i].uid == uid:
			collection.remove_at(i)
			unequip_creature(uid)
			collection_changed.emit()
			return true
	return false


func get_creature(uid: String) -> CreatureData:
	for creature in collection:
		if creature.uid == uid:
			return creature
	return null


func collection_size() -> int:
	return collection.size()


# --- team ---------------------------------------------------------------------

func team() -> Array[CreatureData]:
	var result: Array[CreatureData] = []
	for uid in team_uids:
		var creature := get_creature(uid)
		if creature != null:
			result.append(creature)
	return result


func is_equipped(uid: String) -> bool:
	return team_uids.has(uid)


func team_is_full() -> bool:
	return team_uids.size() >= TEAM_SIZE


## Adds a creature to the first free slot. Never exceeds TEAM_SIZE.
func equip_creature(uid: String) -> bool:
	if is_equipped(uid) or team_is_full():
		return false
	if get_creature(uid) == null:
		return false
	team_uids.append(uid)
	team_changed.emit()
	return true


func unequip_creature(uid: String) -> bool:
	var index := team_uids.find(uid)
	if index == -1:
		return false
	team_uids.remove_at(index)
	team_changed.emit()
	return true


## Puts `uid` in `slot`, swapping with whatever was there.
func set_team_slot(slot: int, uid: String) -> bool:
	if slot < 0 or slot >= TEAM_SIZE or get_creature(uid) == null:
		return false
	while team_uids.size() <= slot:
		team_uids.append("")
	var existing := team_uids.find(uid)
	if existing != -1:
		team_uids[existing] = team_uids[slot]
	team_uids[slot] = uid
	_compact_team()
	team_changed.emit()
	return true


func swap_team_slots(a: int, b: int) -> bool:
	if a < 0 or b < 0 or a >= team_uids.size() or b >= team_uids.size():
		return false
	var tmp := team_uids[a]
	team_uids[a] = team_uids[b]
	team_uids[b] = tmp
	team_changed.emit()
	return true


func _compact_team() -> void:
	var cleaned: Array[String] = []
	for uid in team_uids:
		if uid != "" and get_creature(uid) != null and not cleaned.has(uid):
			cleaned.append(uid)
	team_uids = cleaned


func team_is_defeated() -> bool:
	var members := team()
	if members.is_empty():
		return true
	for creature in members:
		if creature.is_alive():
			return false
	return true


func heal_team() -> void:
	for creature in team():
		creature.full_heal()
	team_changed.emit()


func heal_all() -> void:
	for creature in collection:
		creature.full_heal()
	team_changed.emit()
	collection_changed.emit()


# --- inventory ----------------------------------------------------------------

func item_count(item_id: String) -> int:
	return int(inventory.get(item_id, 0))


func add_item(item_id: String, amount: int = 1) -> void:
	if amount <= 0:
		return
	var max_stack := int(DataManager.get_item(item_id).get("max_stack", 999))
	var new_count := mini(max_stack, item_count(item_id) + amount)
	inventory[item_id] = new_count
	inventory_changed.emit(item_id, new_count)


func consume_item(item_id: String, amount: int = 1) -> bool:
	if amount <= 0 or item_count(item_id) < amount:
		return false
	var new_count := item_count(item_id) - amount
	if new_count <= 0:
		inventory.erase(item_id)
	else:
		inventory[item_id] = new_count
	inventory_changed.emit(item_id, new_count)
	return true


# --- world progression --------------------------------------------------------

func unlock_map(map_id: String) -> void:
	if map_id != "" and not unlocked_maps.has(map_id):
		unlocked_maps.append(map_id)
		GameLog.info(GameLog.Channel.WORLD, "Mapa liberado: %s" % map_id)


func is_map_unlocked(map_id: String) -> bool:
	return unlocked_maps.has(map_id)


func mark_boss_defeated(map_id: String) -> void:
	if not defeated_bosses.has(map_id):
		defeated_bosses.append(map_id)


func is_boss_defeated(map_id: String) -> bool:
	return defeated_bosses.has(map_id)


func mark_mini_boss_defeated(map_id: String) -> void:
	if not defeated_mini_bosses.has(map_id):
		defeated_mini_bosses.append(map_id)


func is_mini_boss_defeated(map_id: String) -> bool:
	return defeated_mini_bosses.has(map_id)


func set_flag(key: String, value: Variant) -> void:
	flags[key] = value


func get_flag(key: String, default_value: Variant = false) -> Variant:
	return flags.get(key, default_value)


# --- serialisation ------------------------------------------------------------

func to_dict() -> Dictionary:
	var creatures: Array = []
	for creature in collection:
		creatures.append(creature.to_dict())
	return {
		"v": SAVE_VERSION,
		"name": display_name,
		"jogador_id": jogador_id,
		"classe": classe_id,
		"vida": vida_atual,
		"appearance": appearance.duplicate(),
		"level": level,
		"xp": xp,
		"gold": gold,
		"current_map": current_map,
		"spawn_point": spawn_point,
		"last_position": [last_position.x, last_position.y],
		"has_exact_position": has_exact_position,
		"collection": creatures,
		"team": team_uids.duplicate(),
		"inventory": inventory.duplicate(),
		"quest_state": quest_state.duplicate(true),
		"flags": flags.duplicate(true),
		"unlocked_maps": unlocked_maps.duplicate(),
		"defeated_bosses": defeated_bosses.duplicate(),
		"defeated_mini_bosses": defeated_mini_bosses.duplicate(),
		"cleared_zones": cleared_zones.duplicate(),
		"created_at": created_at_unix,
		"last_seen": last_seen_unix,
		"playtime": playtime_seconds,
		"starter": starter_species,
	}


## Copia um estado inteiro **para dentro** desta instância e avisa quem escuta.
##
## Diferente de `from_dict`, que cria um objeto novo. A diferença importa: o HUD,
## a moldura do jogador e a mochila estão todos ligados aos sinais **deste**
## objeto. Trocar a instância deixaria a interface ligada num fantasma, mostrando
## o ouro de antes para sempre.
##
## É por aqui que o estado autoritativo do servidor chega ao cliente.
func sincronizar(source: Dictionary) -> void:
	var outro := PlayerData.from_dict(source)
	if outro == null:
		return

	var mudou_ouro := gold != outro.gold
	var mudou_nivel := level != outro.level
	var inventario_antigo := inventory.duplicate()

	# Nome e aparencia **nao** vem do servidor: eles sao do jogador, nao do mundo.
	# Sobrescrever aqui fazia o personagem trocar de cara ao entrar numa partida,
	# e nao ha nada a ganhar trapaceando com a propria roupa.
	level = outro.level
	xp = outro.xp
	gold = outro.gold
	collection = outro.collection
	team_uids = outro.team_uids
	inventory = outro.inventory
	quest_state = outro.quest_state
	flags = outro.flags
	unlocked_maps = outro.unlocked_maps
	defeated_bosses = outro.defeated_bosses
	defeated_mini_bosses = outro.defeated_mini_bosses
	cleared_zones = outro.cleared_zones
	starter_species = outro.starter_species

	# Posição e mapa **não** vêm juntos de propósito: quem manda em onde você
	# está é o seu próprio jogo, e sobrescrever isso com o que o servidor tinha
	# guardado teleportaria o jogador para trás a cada compra.

	if mudou_ouro:
		gold_changed.emit(gold)
	if mudou_nivel:
		level_changed.emit(level)
	xp_changed.emit(xp, xp_to_next_level())
	for item_id in inventory:
		if int(inventario_antigo.get(item_id, 0)) != int(inventory[item_id]):
			inventory_changed.emit(String(item_id), int(inventory[item_id]))
	for item_id in inventario_antigo:
		if not inventory.has(item_id):
			inventory_changed.emit(String(item_id), 0)
	collection_changed.emit()
	team_changed.emit()


static func from_dict(source: Dictionary) -> PlayerData:
	var data := PlayerData.new()
	data.display_name = source.get("name", "Treinador")
	# Save antigo nao tem identidade: sorteia uma agora, senao este jogador
	# continuaria dividindo ficha com todo mundo que se chama igual.
	data.jogador_id = String(source.get("jogador_id", ""))
	if data.jogador_id == "":
		data.jogador_id = _sortear_id()
	# Personagem criado antes das classes existirem cai na primeira, em vez de
	# ficar sem nenhuma e quebrar tudo que consultar a classe.
	data.classe_id = String(source.get("classe", "espadachim"))
	# -1 quer dizer "nunca lutou": nasce cheio na primeira vez que alguem
	# perguntar, em vez de nascer com zero de vida.
	data.vida_atual = int(source.get("vida", -1))
	data.appearance = (source.get("appearance", {}) as Dictionary).duplicate()
	data.level = maxi(1, int(source.get("level", 1)))
	data.xp = int(source.get("xp", 0))
	data.gold = int(source.get("gold", 0))
	data.current_map = source.get("current_map", "")
	data.spawn_point = source.get("spawn_point", "start")

	var position: Array = source.get("last_position", [0, 0])
	if position.size() == 2:
		data.last_position = Vector2(float(position[0]), float(position[1]))
	data.has_exact_position = bool(source.get("has_exact_position", false))

	for entry in source.get("collection", []):
		var creature := CreatureData.from_dict(entry)
		if creature != null:
			data.collection.append(creature)

	for uid in source.get("team", []):
		data.team_uids.append(String(uid))
	data._compact_team()

	data.inventory = (source.get("inventory", {}) as Dictionary).duplicate()
	data.quest_state = (source.get("quest_state", {}) as Dictionary).duplicate(true)
	data.flags = (source.get("flags", {}) as Dictionary).duplicate(true)

	for map_id in source.get("unlocked_maps", []):
		data.unlocked_maps.append(String(map_id))
	for map_id in source.get("defeated_bosses", []):
		data.defeated_bosses.append(String(map_id))
	for map_id in source.get("defeated_mini_bosses", []):
		data.defeated_mini_bosses.append(String(map_id))
	for zone_id in source.get("cleared_zones", []):
		data.cleared_zones.append(String(zone_id))

	data.created_at_unix = int(source.get("created_at", 0))
	data.last_seen_unix = int(source.get("last_seen", 0))
	data.playtime_seconds = float(source.get("playtime", 0.0))
	data.starter_species = source.get("starter", "")
	return data


## Identificador aleatorio de 16 digitos hexadecimais. Nao precisa ser seguro,
## so precisa nao colidir entre os amigos de alguem.
static func _sortear_id() -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return "%08x%08x" % [rng.randi(), rng.randi()]
