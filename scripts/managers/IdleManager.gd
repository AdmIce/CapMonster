extends Node
## Autoload: IdleManager
##
## Recompensa por tempo offline. Ao carregar um save, mede quanto tempo passou
## desde o último `last_seen`, corta no teto (8 h por padrão) e converte em ouro,
## XP de treinador, XP das criaturas e material.
##
## Regra de design que o documento pede e que este arquivo respeita: o idle
## **não substitui o jogo**. Ele dá recurso, nunca criatura - captura só
## acontece com o jogador jogando.
##
## Todas as taxas estão em progression.json → "idle".

signal recompensa_calculada(resumo: Dictionary)

## Abaixo disso não vale a pena mostrar a tela de boas-vindas.
const MINIMO_SEGUNDOS := 120.0

## Materiais que o idle pode render, por mapa onde o jogador parou.
const MATERIAIS_POR_MAPA := {
	"greenvale": "verdant_fiber",
	"ashen_ridge": "ember_ash",
}
const MATERIAL_PADRAO := "aether_shard"

var ultimo_resumo: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## Calcula e aplica. Devolve um resumo vazio quando não houve tempo suficiente.
## Chamado uma vez, ao entrar no mundo com um save carregado.
func processar_retorno(dados: PlayerData) -> Dictionary:
	ultimo_resumo = {}
	if dados == null or dados.last_seen_unix <= 0:
		return {}

	var agora := int(Time.get_unix_time_from_system())
	var decorridos := float(agora - dados.last_seen_unix)
	if decorridos < MINIMO_SEGUNDOS:
		return {}

	var curva := DataManager.progression
	var teto := curva.idle_max_offline_hours * 3600.0
	var creditados := minf(decorridos, teto)
	var horas := creditados / 3600.0

	var ouro := int(round(curva.idle_gold_per_hour * horas))
	var xp_treinador := int(round(curva.idle_player_xp_per_hour * horas))
	var xp_criatura := int(round(curva.idle_creature_xp_per_hour * horas))

	# Material: uma rolagem por hora, do bioma onde o jogador parou.
	var material_id := String(MATERIAIS_POR_MAPA.get(dados.current_map, MATERIAL_PADRAO))
	var material_qtd := 0
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var rolagens := int(floor(horas))
	for _i in rolagens:
		if rng.randf() < curva.idle_material_chance_per_hour:
			material_qtd += rng.randi_range(1, 3)

	if ouro > 0:
		dados.add_gold(ouro)
	if xp_treinador > 0:
		dados.grant_xp(xp_treinador)

	var subiram: Array[String] = []
	for criatura in dados.team():
		if criatura.grant_xp(xp_criatura) > 0:
			subiram.append("%s Nv.%d" % [criatura.display_name(), criatura.level])
	if material_qtd > 0:
		dados.add_item(material_id, material_qtd)

	ultimo_resumo = {
		"segundos": decorridos,
		"segundos_creditados": creditados,
		"limitado": decorridos > teto,
		"ouro": ouro,
		"xp_treinador": xp_treinador,
		"xp_criatura": xp_criatura,
		"material_id": material_id,
		"material_qtd": material_qtd,
		"subiram_de_nivel": subiram,
	}

	GameLog.info(
		GameLog.Channel.IDLE,
		"Retorno após %s: +%d ouro, +%d XP, +%d %s." % [
			formatar_duracao(decorridos), ouro, xp_treinador, material_qtd, material_id
		]
	)
	recompensa_calculada.emit(ultimo_resumo)
	return ultimo_resumo


static func formatar_duracao(segundos: float) -> String:
	var total := int(segundos)
	var dias := total / 86400
	var horas := (total % 86400) / 3600
	var minutos := (total % 3600) / 60
	if dias > 0:
		return "%dd %dh" % [dias, horas]
	if horas > 0:
		return "%dh %dmin" % [horas, minutos]
	return "%dmin" % maxi(1, minutos)
