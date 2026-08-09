extends Node
## Camada de rede: hospedar uma partida, entrar na de um amigo e manter a lista
## de quem está online com a posição de cada um.
##
## **Etapa 1 — presença compartilhada.** Quem entra vê os outros andando no mesmo
## mapa, com nome em cima. Batalha, captura e save continuam locais: o mundo
## ainda é autoritativo no cliente. Isso é de propósito — trocar a autoridade de
## spawn e combate para o servidor é a etapa seguinte, e ela precisa desta camada
## funcionando primeiro.
##
## Por que todos os RPCs moram neste autoload e não nos nós do mundo: o Godot
## roteia RPC por **caminho de nó**, que precisa ser idêntico nos dois lados. O
## mundo é construído por código e muda de forma conforme o mapa; o autoload é
## sempre `/root/Rede`. Assim a rede não quebra quando alguém está num mapa
## diferente ou com o painel aberto.
##
## Topologia: estrela com servidor-ouvinte (quem hospeda também joga). O Godot
## repassa RPC de cliente para cliente através do servidor por padrão
## (`server_relay`), então cada um só precisa falar uma vez.

signal jogador_entrou(id: int, info: Dictionary)
signal jogador_saiu(id: int)
signal jogador_moveu(id: int, info: Dictionary)
signal estado_mudou()   ## conectou, desconectou ou falhou — para a interface

const PORTA_PADRAO := 24565
const MAX_JOGADORES := 8

## 15 envios por segundo. Mais que isso é banda jogada fora para um jogo em que
## ninguém corre mais que 8 m/s; menos que isso e a interpolação começa a nadar.
const ENVIOS_POR_SEGUNDO := 15.0

enum Estado { OFFLINE, HOSPEDANDO, CONECTANDO, CONECTADO }

var estado: Estado = Estado.OFFLINE
var erro: String = ""

## id do peer -> { nome, aparencia, mapa, pos: Vector2, giro: float, correndo }
var jogadores: Dictionary = {}

var _relogio: float = 0.0
var _ultimo_enviado := Vector2(INF, INF)


func _ready() -> void:
	multiplayer.peer_connected.connect(_ao_conectar_peer)
	multiplayer.peer_disconnected.connect(_ao_desconectar_peer)
	multiplayer.connected_to_server.connect(_ao_entrar)
	multiplayer.connection_failed.connect(_ao_falhar)
	multiplayer.server_disconnected.connect(_ao_cair_o_servidor)


func online() -> bool:
	return estado == Estado.HOSPEDANDO or estado == Estado.CONECTADO


func meu_id() -> int:
	return multiplayer.get_unique_id() if multiplayer.multiplayer_peer != null else 0


# --- abrir e fechar -----------------------------------------------------------

func hospedar(porta: int = PORTA_PADRAO) -> bool:
	desligar()
	var peer := ENetMultiplayerPeer.new()
	var resultado := peer.create_server(porta, MAX_JOGADORES)
	if resultado != OK:
		erro = "Não consegui abrir a porta %d (erro %d). Ela pode já estar em uso." % [porta, resultado]
		GameLog.error(GameLog.Channel.SYSTEM, "Rede: " + erro)
		estado_mudou.emit()
		return false

	multiplayer.multiplayer_peer = peer
	estado = Estado.HOSPEDANDO
	erro = ""
	jogadores[meu_id()] = _meu_cartao()
	GameLog.info(GameLog.Channel.SYSTEM, "Rede: hospedando na porta %d." % porta)
	estado_mudou.emit()
	return true


func entrar(endereco: String, porta: int = PORTA_PADRAO) -> bool:
	desligar()
	var peer := ENetMultiplayerPeer.new()
	var resultado := peer.create_client(endereco, porta)
	if resultado != OK:
		erro = "Endereço inválido ou inalcançável: %s:%d." % [endereco, porta]
		GameLog.error(GameLog.Channel.SYSTEM, "Rede: " + erro)
		estado_mudou.emit()
		return false

	multiplayer.multiplayer_peer = peer
	estado = Estado.CONECTANDO
	erro = ""
	GameLog.info(GameLog.Channel.SYSTEM, "Rede: conectando em %s:%d..." % [endereco, porta])
	estado_mudou.emit()
	return true


func desligar() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	var tinha := not jogadores.is_empty()
	jogadores.clear()
	estado = Estado.OFFLINE
	_ultimo_enviado = Vector2(INF, INF)
	if tinha:
		estado_mudou.emit()


# --- eventos do transporte ----------------------------------------------------

func _ao_conectar_peer(id: int) -> void:
	# Quem chegou ainda não sabe quem somos, e nós ainda não sabemos quem é ele.
	# Os dois lados se apresentam; a resposta chega no _receber_cartao.
	_apresentar.rpc_id(id, _meu_cartao())


func _ao_desconectar_peer(id: int) -> void:
	if jogadores.erase(id):
		GameLog.info(GameLog.Channel.SYSTEM, "Rede: peer %d saiu." % id)
		jogador_saiu.emit(id)
		estado_mudou.emit()


func _ao_entrar() -> void:
	estado = Estado.CONECTADO
	erro = ""
	jogadores[meu_id()] = _meu_cartao()
	GameLog.info(GameLog.Channel.SYSTEM, "Rede: conectado como peer %d." % meu_id())
	estado_mudou.emit()


func _ao_falhar() -> void:
	erro = "Não consegui conectar. Confira o endereço, a porta e se o host está com o jogo aberto."
	GameLog.warn(GameLog.Channel.SYSTEM, "Rede: " + erro)
	desligar()


func _ao_cair_o_servidor() -> void:
	erro = "O host encerrou a partida."
	GameLog.warn(GameLog.Channel.SYSTEM, "Rede: " + erro)
	desligar()


# --- identidade ---------------------------------------------------------------

func _meu_cartao() -> Dictionary:
	var dados := GameManager.player
	if dados == null:
		return {"nome": "Treinador", "aparencia": {}, "mapa": "", "pos": Vector2.ZERO, "giro": 0.0, "correndo": false}
	return {
		"nome": dados.display_name,
		"aparencia": dados.appearance,
		"mapa": dados.current_map,
		"pos": dados.last_position,
		"giro": 0.0,
		"correndo": false,
	}


## Chega de quem acabou de nos conhecer. Respondemos com o nosso cartão para o
## aperto de mão fechar dos dois lados sem precisar de ordem garantida.
@rpc("any_peer", "call_remote", "reliable")
func _apresentar(cartao: Dictionary) -> void:
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		return
	# Os dois lados se apresentam ao mesmo tempo, então o segundo cartão do mesmo
	# peer é a resposta ao nosso — atualiza os dados e cala a boca, senão cada
	# entrada vira dois avisos e dois "entrou no seu mundo".
	var novo := not jogadores.has(id)
	jogadores[id] = _higienizar(cartao)
	if not novo:
		return
	GameLog.info(GameLog.Channel.SYSTEM, "Rede: %s (peer %d) está online." % [jogadores[id]["nome"], id])
	_apresentar.rpc_id(id, _meu_cartao())
	jogador_entrou.emit(id, jogadores[id])
	estado_mudou.emit()


## Nunca confiar no que veio da rede: um cliente adulterado pode mandar qualquer
## coisa, e um valor errado aqui vira crash no construtor do avatar.
func _higienizar(cartao: Dictionary) -> Dictionary:
	var pos: Vector2 = cartao.get("pos", Vector2.ZERO)
	return {
		"nome": String(cartao.get("nome", "Treinador")).substr(0, 24),
		"aparencia": cartao.get("aparencia", {}) if cartao.get("aparencia", {}) is Dictionary else {},
		"mapa": String(cartao.get("mapa", "")),
		"pos": pos if pos is Vector2 else Vector2.ZERO,
		"giro": clampf(float(cartao.get("giro", 0.0)), -TAU, TAU),
		"correndo": bool(cartao.get("correndo", false)),
	}


# --- posição ------------------------------------------------------------------

## Chamado pelo WorldRoot todo quadro. Ele decide a hora de enviar, não o
## chamador: assim a taxa fica num lugar só.
func informar_posicao(delta: float, pos: Vector2, giro: float, correndo: bool, mapa: String) -> void:
	if not online():
		return
	_relogio += delta
	if _relogio < 1.0 / ENVIOS_POR_SEGUNDO:
		return
	_relogio = 0.0

	# Parado não gasta pacote. A margem evita mandar por causa de tremida de
	# física quando o personagem está encostado numa parede.
	if pos.distance_to(_ultimo_enviado) < 0.02 and jogadores.get(meu_id(), {}).get("giro", 0.0) == giro:
		return
	_ultimo_enviado = pos

	var meu: Dictionary = jogadores.get(meu_id(), _meu_cartao())
	meu["pos"] = pos
	meu["giro"] = giro
	meu["correndo"] = correndo
	meu["mapa"] = mapa
	jogadores[meu_id()] = meu

	_mover.rpc(pos, giro, correndo, mapa)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _mover(pos: Vector2, giro: float, correndo: bool, mapa: String) -> void:
	var id := multiplayer.get_remote_sender_id()
	if id == 0 or not jogadores.has(id):
		return
	var info: Dictionary = jogadores[id]
	info["pos"] = pos
	info["giro"] = giro
	info["correndo"] = correndo
	info["mapa"] = mapa
	jogador_moveu.emit(id, info)


## Todos menos eu, filtrados pelo mapa em que estou. Quem está em outro mapa
## continua na lista (aparece no painel de online), mas não é desenhado.
func companheiros_no_mapa(mapa: String) -> Dictionary:
	var saida: Dictionary = {}
	for id in jogadores:
		if id == meu_id():
			continue
		if String(jogadores[id].get("mapa", "")) == mapa:
			saida[id] = jogadores[id]
	return saida
