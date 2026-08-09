extends Node
## Autoload: QuestManager
##
## Lê data/quests.json e acompanha o progresso. Guarda tudo em
## PlayerData.quest_state, então missão entra no save junto com o resto.
##
## Formato do estado: { quest_id: { "status": "ativa"|"concluida", "progresso": int } }
##
## Quem gera evento não conhece missão nenhuma: a batalha chama
## `registrar_derrota()`, a captura chama `registrar_captura()`, e é aqui que se
## decide se aquilo interessa a alguma missão. Adicionar missão é editar JSON.

signal missao_iniciada(quest_id: String, missao: Dictionary)
signal missao_progrediu(quest_id: String, atual: int, alvo: int)
signal missao_concluida(quest_id: String, missao: Dictionary)

const ATIVA := "ativa"
const CONCLUIDA := "concluida"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameManager.session_started.connect(_ao_iniciar_sessao)
	GameManager.map_changed.connect(func(map_id: String, _spawn: String): registrar_mapa(map_id))


func _ao_iniciar_sessao(dados: PlayerData) -> void:
	dados.level_changed.connect(func(_n): _avaliar_tipo("player_level"))
	dados.team_changed.connect(func(): _avaliar_tipo("team_size"))
	sincronizar()


# --- consulta -----------------------------------------------------------------

func estado(quest_id: String) -> Dictionary:
	var dados := GameManager.player
	if dados == null:
		return {}
	return dados.quest_state.get(quest_id, {})


func esta_ativa(quest_id: String) -> bool:
	return estado(quest_id).get("status", "") == ATIVA


func esta_concluida(quest_id: String) -> bool:
	return estado(quest_id).get("status", "") == CONCLUIDA


func progresso(quest_id: String) -> int:
	return int(estado(quest_id).get("progresso", 0))


func alvo(quest_id: String) -> int:
	return maxi(1, int(DataManager.get_quest(quest_id).get("objective", {}).get("count", 1)))


func missoes_ativas() -> Array:
	var resultado: Array = []
	for missao in DataManager.all_quests():
		if esta_ativa(String(missao.get("id", ""))):
			resultado.append(missao)
	return resultado


func missoes_concluidas() -> Array:
	var resultado: Array = []
	for missao in DataManager.all_quests():
		if esta_concluida(String(missao.get("id", ""))):
			resultado.append(missao)
	return resultado


# --- ciclo --------------------------------------------------------------------

## Abre as missões que já podem começar e reavalia objetivos que dependem de
## estado (nível, tamanho da equipe) em vez de evento.
func sincronizar() -> void:
	var dados := GameManager.player
	if dados == null:
		return

	for missao in DataManager.all_quests():
		var quest_id := String(missao.get("id", ""))
		if esta_ativa(quest_id) or esta_concluida(quest_id):
			continue
		if bool(missao.get("auto_start", false)) or _requisitos_ok(missao):
			_iniciar(quest_id, missao)

	_avaliar_tipo("player_level")
	_avaliar_tipo("team_size")


func _requisitos_ok(missao: Dictionary) -> bool:
	var requisitos: Array = missao.get("requires", [])
	if requisitos.is_empty():
		return false
	for req in requisitos:
		if not esta_concluida(String(req)):
			return false
	return true


func _iniciar(quest_id: String, missao: Dictionary) -> void:
	var dados := GameManager.player
	dados.quest_state[quest_id] = { "status": ATIVA, "progresso": 0 }
	GameLog.info(GameLog.Channel.QUEST, "Missão aberta: %s" % missao.get("name", quest_id))
	Notify.show_message("Nova missão: %s" % missao.get("name", quest_id))
	missao_iniciada.emit(quest_id, missao)


# --- eventos ------------------------------------------------------------------

func registrar_captura(_criatura: CreatureData) -> void:
	_avancar_tipo("capture", 1)


func registrar_derrota(_criatura: CreatureData) -> void:
	_avancar_tipo("defeat", 1)


## Chefes e mini-chefes: `alvo_id` é o id do encontro em maps.json (gv_boss...).
func registrar_encontro_nomeado(alvo_id: String) -> void:
	_avancar_tipo("defeat_named", 1, alvo_id)


func registrar_mapa(map_id: String) -> void:
	_avancar_tipo("reach_map", 1, map_id)


## Objetivos que são um estado, não uma contagem: recalcula direto da fonte.
func _avaliar_tipo(tipo: String) -> void:
	var dados := GameManager.player
	if dados == null:
		return
	for missao in DataManager.all_quests():
		var quest_id := String(missao.get("id", ""))
		if not esta_ativa(quest_id):
			continue
		var objetivo: Dictionary = missao.get("objective", {})
		if String(objetivo.get("type", "")) != tipo:
			continue

		var valor := 0
		match tipo:
			"player_level":
				valor = dados.level
			"team_size":
				valor = dados.team_uids.size()
		_definir_progresso(quest_id, missao, valor)


func _avancar_tipo(tipo: String, quantidade: int, alvo_id: String = "") -> void:
	var dados := GameManager.player
	if dados == null:
		return
	for missao in DataManager.all_quests():
		var quest_id := String(missao.get("id", ""))
		if not esta_ativa(quest_id):
			continue
		var objetivo: Dictionary = missao.get("objective", {})
		if String(objetivo.get("type", "")) != tipo:
			continue
		# Objetivo com alvo específico só conta para aquele alvo.
		var esperado := String(objetivo.get("target", ""))
		if esperado != "" and esperado != alvo_id:
			continue
		_definir_progresso(quest_id, missao, progresso(quest_id) + quantidade)


func _definir_progresso(quest_id: String, missao: Dictionary, valor: int) -> void:
	var dados := GameManager.player
	var necessario := alvo(quest_id)
	var novo := clampi(valor, 0, necessario)
	if novo == progresso(quest_id):
		return

	dados.quest_state[quest_id]["progresso"] = novo
	missao_progrediu.emit(quest_id, novo, necessario)

	if novo >= necessario:
		_concluir(quest_id, missao)
	else:
		Notify.show_message("%s  %d/%d" % [missao.get("name", quest_id), novo, necessario])


func _concluir(quest_id: String, missao: Dictionary) -> void:
	var dados := GameManager.player
	dados.quest_state[quest_id]["status"] = CONCLUIDA

	var recompensas: Dictionary = missao.get("rewards", {})
	var ouro := int(recompensas.get("gold", 0))
	var xp := int(recompensas.get("player_xp", 0))
	# Pela Ficha, e nao direto: num cliente, mexer no ouro local faz o proximo
	# estado que vier do servidor apagar o premio sem ninguem perceber.
	var itens_do_premio: Dictionary = {}
	for item_id in recompensas.get("items", {}).keys():
		itens_do_premio[String(item_id)] = int(recompensas["items"][item_id])
	Ficha.pedir("recompensa", {"ouro": ouro, "xp": xp, "itens": itens_do_premio})

	var partes: Array[String] = []
	if ouro > 0:
		partes.append("%d de ouro" % ouro)
	if xp > 0:
		partes.append("%d XP" % xp)
	var extra := ("  ·  " + ", ".join(partes)) if not partes.is_empty() else ""

	GameLog.info(GameLog.Channel.QUEST, "Missão concluída: %s" % missao.get("name", quest_id))
	Notify.good("Missão concluída: %s%s" % [missao.get("name", quest_id), extra])
	AudioManager.tocar(&"vitoria")
	missao_concluida.emit(quest_id, missao)

	GameManager.save_now("missão concluída")
	# Concluir uma pode destravar a seguinte.
	sincronizar()
