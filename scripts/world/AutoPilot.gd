class_name AutoPilot
extends Node
## Modo automático: o personagem explora sozinho.
##
## O que ele decide hoje:
##   · se alguém da equipe está machucado, volta ao ponto de cura e descansa;
##   · senão, caça a criatura selvagem alcançável mais próxima e encosta nela;
##   · se não houver nada por perto, vagueia dentro dos limites do mapa.
##
## Quando o combate está rolando ele não faz nada: a batalha se resolve sozinha e
## o controle volta no fim.
##
## Ele nunca digita pelo jogador: escreve em PlayerController.auto_input um vetor
## em ESPAÇO DE MUNDO (não em espaço de câmera - isso importa, porque em terceira
## pessoa a câmera gira junto com o personagem e converter duas vezes faz ele
## andar em círculo). Encostar num direcional devolve o controle na hora.

signal state_changed(descricao: String)
signal enabled_changed(ativo: bool)

enum Estado { PARADO, CACAR, DESCANSAR, VAGAR }

const HP_PARA_DESCANSAR := 0.35
const HP_PARA_VOLTAR := 0.95
const DISTANCIA_CHEGADA := 1.2
const DISTANCIA_INTERAGIR := 2.4
const REPLANEJAR_SEGUNDOS := 1.0
const ALCANCE_DE_CACA := 46.0

## Antitravamento
const TEMPO_TRAVADO := 0.8
const DESVIO_SEGUNDOS := 0.9
const DESVIOS_ATE_DESISTIR := 3
const DESISTENCIA_SEGUNDOS := 12.0
## Tempo máximo perseguindo o mesmo alvo antes de escolher outro.
const PACIENCIA_POR_ALVO := 14.0

var player: PlayerController = null
var map_data: Dictionary = {}

var _ativo: bool = false
var _estado: Estado = Estado.PARADO
var _alvo := Vector2.ZERO
var _tem_alvo: bool = false
var _no_alvo: Node3D = null

var _tempo_replanejar: float = 0.0
var _tempo_no_alvo: float = 0.0
var _tempo_parado: float = 0.0
var _desvio := Vector2.ZERO
var _tempo_desvio: float = 0.0
var _desvios_seguidos: int = 0
## Alvos que se mostraram inalcançáveis: id -> segundos restantes de desistência.
var _desistidos: Dictionary = {}
var _rng := RandomNumberGenerator.new()


func setup(controller: PlayerController, data: Dictionary) -> void:
	player = controller
	map_data = data
	_rng.randomize()


func is_enabled() -> bool:
	return _ativo


func set_enabled(ativo: bool) -> void:
	if _ativo == ativo:
		return
	_ativo = ativo
	if player != null:
		player.auto_enabled = ativo
		player.auto_input = Vector2.ZERO
	_limpar_alvo()
	_desistidos.clear()
	_estado = Estado.PARADO
	enabled_changed.emit(ativo)
	GameLog.info(GameLog.Channel.WORLD, "Modo automático %s." % ("ligado" if ativo else "desligado"))
	if ativo:
		_replanejar()
	else:
		state_changed.emit("")


func toggle() -> void:
	set_enabled(not _ativo)


# --- ciclo --------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not _ativo or player == null or not is_instance_valid(player):
		return

	for chave in _desistidos.keys():
		_desistidos[chave] = float(_desistidos[chave]) - delta
		if _desistidos[chave] <= 0.0:
			_desistidos.erase(chave)

	if not player.input_enabled:
		# Batalha, diálogo ou menu aberto: espera sem empurrar o personagem.
		player.auto_input = Vector2.ZERO
		_tempo_parado = 0.0
		return

	_tempo_replanejar -= delta
	if _tem_alvo:
		_tempo_no_alvo += delta
		if _tempo_no_alvo > PACIENCIA_POR_ALVO:
			_desistir_do_alvo("demorou demais")
	if _tempo_replanejar <= 0.0 or not _alvo_ainda_vale():
		_replanejar()

	if not _tem_alvo:
		player.auto_input = Vector2.ZERO
		return

	var posicao := player.plane_position()
	if posicao.distance_to(_alvo) <= DISTANCIA_CHEGADA:
		_ao_chegar()
		player.auto_input = Vector2.ZERO
		return

	_atualizar_desvio(delta)
	var direcao := (_alvo - posicao).normalized()
	if _tempo_desvio > 0.0:
		direcao = (direcao + _desvio).normalized()
	player.auto_input = direcao


## O alvo deixa de valer quando a criatura sumiu, morreu ou entrou em recarga.
func _alvo_ainda_vale() -> bool:
	if not _tem_alvo:
		return false
	if _estado != Estado.CACAR:
		return true
	if _no_alvo == null or not is_instance_valid(_no_alvo):
		return false
	var selvagem := _no_alvo as WildCreature
	if selvagem == null or not selvagem.pode_iniciar_encontro():
		return false
	# Criatura anda: acompanha a posição dela.
	_alvo = Vector2(selvagem.global_position.x, selvagem.global_position.z)
	return true


## Detecta parede: se está tentando andar e não sai do lugar, desvia de lado. Se
## nem assim destravar, marca o alvo como inalcançável e procura outro - é isso
## que evita ficar batendo numa árvore para sempre.
func _atualizar_desvio(delta: float) -> void:
	if _tempo_desvio > 0.0:
		_tempo_desvio -= delta
		return
	var velocidade := Vector2(player.velocity.x, player.velocity.z).length()
	if velocidade >= 0.8:
		_tempo_parado = 0.0
		_desvios_seguidos = 0
		return

	_tempo_parado += delta
	if _tempo_parado < TEMPO_TRAVADO:
		return

	_tempo_parado = 0.0
	_desvios_seguidos += 1
	if _desvios_seguidos > DESVIOS_ATE_DESISTIR:
		_desistir_do_alvo("não consegui chegar")
		return

	_tempo_desvio = DESVIO_SEGUNDOS
	var lado := 1.0 if _rng.randf() < 0.5 else -1.0
	var para_alvo := (_alvo - player.plane_position()).normalized()
	_desvio = Vector2(-para_alvo.y, para_alvo.x) * lado * 1.6


func _desistir_do_alvo(motivo: String) -> void:
	if _no_alvo != null and is_instance_valid(_no_alvo):
		_desistidos[_no_alvo.get_instance_id()] = DESISTENCIA_SEGUNDOS
		GameLog.verbose(GameLog.Channel.WORLD, "Auto: desistindo de %s (%s)." % [_no_alvo.name, motivo])
	_limpar_alvo()
	_tempo_replanejar = 0.0


func _limpar_alvo() -> void:
	_tem_alvo = false
	_no_alvo = null
	_tempo_no_alvo = 0.0
	_desvios_seguidos = 0
	_tempo_desvio = 0.0
	_tempo_parado = 0.0


func _ao_chegar() -> void:
	if _estado == Estado.DESCANSAR:
		_interagir_com_alvo()
	_limpar_alvo()
	_tempo_replanejar = 0.0


## Usa o mesmo caminho de interação do jogador, incluindo os bloqueios.
func _interagir_com_alvo() -> void:
	var alvo := player.current_interactable()
	if alvo != null and player.global_position.distance_to(alvo.global_position) <= DISTANCIA_INTERAGIR:
		alvo.interact(player)


# --- decisão ------------------------------------------------------------------

func _replanejar() -> void:
	_tempo_replanejar = REPLANEJAR_SEGUNDOS
	var dados := GameManager.player
	if dados == null:
		return

	if _precisa_descansar(dados):
		if _mirar_ponto_de_cura():
			return
	if _mirar_criatura():
		return
	_mirar_passeio()


func _precisa_descansar(dados: PlayerData) -> bool:
	var equipe := dados.team()
	if equipe.is_empty():
		return false
	# Uma vez decidido descansar, só larga o rumo com a equipe quase cheia -
	# senão fica indo e voltando do acampamento.
	var limite := HP_PARA_VOLTAR if _estado == Estado.DESCANSAR else HP_PARA_DESCANSAR
	for criatura in equipe:
		if criatura.hp_ratio() < limite:
			return true
	return false


func _mirar_ponto_de_cura() -> bool:
	var pontos: Array = map_data.get("heal_points", [])
	if pontos.is_empty():
		return false
	var posicao := player.plane_position()
	var melhor := Vector2.ZERO
	var melhor_distancia := INF
	for ponto in pontos:
		var pos: Array = ponto.get("pos", [])
		if pos.size() != 2:
			continue
		var candidato := Vector2(pos[0], pos[1])
		var distancia := posicao.distance_squared_to(candidato)
		if distancia < melhor_distancia:
			melhor_distancia = distancia
			melhor = candidato
	if melhor_distancia == INF:
		return false
	_definir_alvo(melhor, null, Estado.DESCANSAR, "voltando para descansar")
	return true


func _mirar_criatura() -> bool:
	var posicao := player.plane_position()
	var melhor: WildCreature = null
	var melhor_distancia := ALCANCE_DE_CACA * ALCANCE_DE_CACA

	for no in get_tree().get_nodes_in_group("wild_creature"):
		if not is_instance_valid(no):
			continue
		var criatura := no as WildCreature
		if criatura == null or not criatura.pode_iniciar_encontro():
			continue
		if _desistidos.has(criatura.get_instance_id()):
			continue
		var plano := Vector2(criatura.global_position.x, criatura.global_position.z)
		var distancia := posicao.distance_squared_to(plano)
		if distancia < melhor_distancia:
			melhor_distancia = distancia
			melhor = criatura

	if melhor == null:
		return false
	_definir_alvo(
		Vector2(melhor.global_position.x, melhor.global_position.z),
		melhor,
		Estado.CACAR,
		"caçando %s" % melhor.data.display_name()
	)
	return true


## Passeio: um ponto aleatório dentro dos limites, longe o bastante para o
## personagem realmente sair do lugar.
func _mirar_passeio() -> void:
	var limites: Dictionary = map_data.get("bounds", {})
	var posicao := player.plane_position()
	var angulo := _rng.randf_range(0.0, TAU)
	var raio := _rng.randf_range(8.0, 18.0)
	var destino := posicao + Vector2(cos(angulo), sin(angulo)) * raio
	destino.x = clampf(destino.x, float(limites.get("min_x", -20)) + 4.0, float(limites.get("max_x", 20)) - 4.0)
	destino.y = clampf(destino.y, float(limites.get("min_z", -20)) + 4.0, float(limites.get("max_z", 20)) - 4.0)
	_definir_alvo(destino, null, Estado.VAGAR, "explorando")


func _definir_alvo(destino: Vector2, no: Node3D, estado: Estado, descricao: String) -> void:
	var trocou_alvo := no != _no_alvo or estado != _estado
	_alvo = destino
	_no_alvo = no
	_tem_alvo = true
	if trocou_alvo:
		_tempo_no_alvo = 0.0
		_desvios_seguidos = 0
		_estado = estado
		state_changed.emit(descricao)
