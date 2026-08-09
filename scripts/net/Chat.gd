extends Node
## Chat do jogo: canais, comandos, sussurro e histórico.
##
## Como as outras camadas de rede, mora num autoload porque o Godot roteia RPC
## por caminho de nó — `/root/Chat` é igual em todas as máquinas.
##
## **Quem manda é o dono.** O cliente não fala com os outros clientes: ele manda
## a linha para o dono, que decide se ela vale (tamanho, ritmo, canal, alvo) e
## quem recebe. Isso não é burocracia — é o que impede alguém de mandar mensagem
## se passando por outro jogador, de inundar a tela dos outros, ou de escutar um
## sussurro que não era dele. O nome do autor **nunca** vem do pacote: o dono usa
## o nome que ele já tem registrado para aquele peer.
##
## Jogando sozinho, o próprio processo é o dono e tudo continua funcionando —
## suas mensagens aparecem só para você, e o chat avisa isso uma vez em vez de
## fingir que alguém está ouvindo.

signal mensagem(linha: Dictionary)
signal historico_limpo()

enum Canal { GERAL, LOCAL, SUSSURRO, SISTEMA }

const LIMITE_CARACTERES := 200
const HISTORICO_MAXIMO := 200

## Alcance do canal local, em metros de mundo. O mapa inicial tem uns 60 de
## lado, então 30 cobre "quem está por perto" sem virar um segundo canal geral.
const RAIO_LOCAL := 30.0

## Anti-inundação, verificado no dono: no mínimo este intervalo entre mensagens,
## e no máximo esta rajada antes de precisar esperar.
const INTERVALO_MINIMO := 0.35
const RAJADA_MAXIMA := 6
const RAJADA_RECARGA := 3.0

const COR_CANAL := {
	Canal.GERAL: "#E8DCC4",
	Canal.LOCAL: "#9BD17A",
	Canal.SUSSURRO: "#D7A8E8",
	Canal.SISTEMA: "#E0B252",
}

const NOME_CANAL := {
	Canal.GERAL: "Geral",
	Canal.LOCAL: "Local",
	Canal.SUSSURRO: "Sussurro",
	Canal.SISTEMA: "Sistema",
}

var historico: Array[Dictionary] = []
var canal_atual: Canal = Canal.GERAL

## Estado do controle de ritmo, por peer. Só existe no dono.
var _ritmo: Dictionary = {}   ## peer -> { sobra: float, ultimo: float }

var _avisou_sozinho: bool = false

## Ultimo nome que sussurrou para voce. Sustenta o /r — responder sem ter que
## digitar o nome de novo e, num jogo online, a diferenca entre conversar e
## desistir de conversar.
var ultimo_sussurro: String = ""


func _ready() -> void:
	Rede.jogador_entrou.connect(func(_id, info):
		sistema("%s entrou na partida." % info.get("nome", "Alguém"))
	)
	Rede.jogador_saiu.connect(func(id):
		var nome := String(Rede.jogadores.get(id, {}).get("nome", "Alguém"))
		sistema("%s saiu da partida." % nome)
	)


# --- entrada do jogador -------------------------------------------------------

## Recebe a linha crua digitada. Devolve falso quando não havia nada para mandar.
func enviar(bruto: String) -> bool:
	var texto := bruto.strip_edges()
	if texto == "":
		return false

	if texto.begins_with("/"):
		return _comando(texto)
	return _falar(canal_atual, texto, "")


func _comando(linha: String) -> bool:
	var partes := linha.substr(1).split(" ", true, 1)
	var verbo := String(partes[0]).to_lower()
	var resto := String(partes[1]) if partes.size() > 1 else ""

	match verbo:
		"g", "geral":
			if resto == "":
				canal_atual = Canal.GERAL
				sistema("Canal padrão: Geral.")
				return true
			return _falar(Canal.GERAL, resto, "")
		"l", "local", "p", "perto":
			if resto == "":
				canal_atual = Canal.LOCAL
				sistema("Canal padrão: Local (%d metros)." % int(RAIO_LOCAL))
				return true
			return _falar(Canal.LOCAL, resto, "")
		"r", "responder":
			if ultimo_sussurro == "":
				sistema("Ninguem sussurrou para voce ainda.")
				return true
			if resto.strip_edges() == "":
				sistema("Use: /r <mensagem>  (responde %s)" % ultimo_sussurro)
				return true
			return _falar(Canal.SUSSURRO, resto, ultimo_sussurro)
		"s", "w", "sussurro":
			var alvo := resto.split(" ", true, 1)
			if alvo.size() < 2 or String(alvo[1]).strip_edges() == "":
				sistema("Use: /s <nome> <mensagem>")
				return true
			return _falar(Canal.SUSSURRO, String(alvo[1]), String(alvo[0]))
		"quem", "online":
			_listar_online()
			return true
		"limpar":
			historico.clear()
			historico_limpo.emit()
			return true
		"ajuda", "?":
			_ajuda()
			return true
		_:
			sistema("Comando desconhecido: /%s. Digite /ajuda." % verbo)
			return true


func _ajuda() -> void:
	sistema("Enter abre o chat, Esc fecha. Comandos:")
	sistema("  /g <msg>  — fala no Geral        /g sozinho troca o canal padrão")
	sistema("  /l <msg>  — fala com quem está a %d metros" % int(RAIO_LOCAL))
	sistema("  /s <nome> <msg>  — sussurra para um jogador   /r <msg> responde")
	sistema("  /quem — lista quem está online    /limpar — apaga o histórico")


func _listar_online() -> void:
	if not Rede.online():
		sistema("Você está jogando sozinho.")
		return
	var nomes: Array[String] = []
	for id in Rede.jogadores:
		var info: Dictionary = Rede.jogadores[id]
		nomes.append("%s (%s)" % [
			info.get("nome", "?"), DataManager.get_map_name(String(info.get("mapa", "")))
		])
	sistema("Online (%d): %s" % [nomes.size(), ", ".join(nomes)])


# --- envio --------------------------------------------------------------------

func _falar(canal: Canal, texto: String, alvo: String) -> bool:
	var limpo := higienizar(texto)
	if limpo == "":
		return false

	if not Rede.online():
		# Sozinho o dono é este processo: a mensagem aparece para você e mais
		# ninguém. Dizer isso uma vez é mais honesto que deixar o jogador achar
		# que mandou para alguém.
		_registrar({
			"canal": canal, "autor": _meu_nome(), "autor_id": 0,
			"texto": limpo, "alvo": alvo, "proprio": true,
		})
		if not _avisou_sozinho:
			_avisou_sozinho = true
			sistema("Você não está numa partida — ninguém mais recebe. Use \"Jogar junto\" no menu.")
		return true

	if MundoRede.sou_o_dono():
		_distribuir(Rede.meu_id(), canal, limpo, alvo)
	else:
		_pedir.rpc_id(1, int(canal), limpo, alvo)
	return true


## Tira BBCode e quebras de linha do texto do jogador.
##
## O painel desenha com BBCode para colorir nome e canal; sem escapar o colchete,
## qualquer um poderia mandar `[color=red]` — ou pior, `[img]` — e pintar a tela
## dos outros. Escapar na origem é mais seguro que confiar em quem desenha.
static func higienizar(texto: String) -> String:
	var limpo := texto.replace("[", "[lb]").replace("\n", " ").replace("\r", " ")
	limpo = limpo.strip_edges()
	if limpo.length() > LIMITE_CARACTERES:
		limpo = limpo.substr(0, LIMITE_CARACTERES)
	return limpo


@rpc("any_peer", "call_remote", "reliable")
func _pedir(canal: int, texto: String, alvo: String) -> void:
	if not MundoRede.sou_o_dono():
		return
	var autor := multiplayer.get_remote_sender_id()
	if not _tem_folego(autor):
		_recusar.rpc_id(autor, "Devagar com as mensagens.")
		return
	# Higieniza de novo: o cliente pode ter sido adulterado e mandado o cru.
	_distribuir(autor, _canal_valido(canal), higienizar(texto), String(alvo).substr(0, 24))


## Controle de ritmo em balde: cada mensagem gasta uma ficha, e as fichas voltam
## com o tempo. Deixa passar uma rajada curta (conversa normal) e barra o
## despejo contínuo.
func _tem_folego(peer: int) -> bool:
	var agora := Time.get_ticks_msec() / 1000.0
	var estado: Dictionary = _ritmo.get(peer, {"fichas": float(RAJADA_MAXIMA), "ultimo": agora})
	var passou: float = agora - float(estado["ultimo"])
	estado["fichas"] = minf(float(RAJADA_MAXIMA), float(estado["fichas"]) + passou / RAJADA_RECARGA * RAJADA_MAXIMA)
	estado["ultimo"] = agora

	if passou < INTERVALO_MINIMO or float(estado["fichas"]) < 1.0:
		_ritmo[peer] = estado
		return false

	estado["fichas"] = float(estado["fichas"]) - 1.0
	_ritmo[peer] = estado
	return true


static func _canal_valido(bruto: int) -> Canal:
	# SISTEMA nunca vem da rede: só o próprio jogo escreve nesse canal.
	match bruto:
		Canal.LOCAL:
			return Canal.LOCAL
		Canal.SUSSURRO:
			return Canal.SUSSURRO
		_:
			return Canal.GERAL


## Só roda no dono. Escolhe quem recebe e manda para cada um.
func _distribuir(autor: int, canal: Canal, texto: String, alvo: String) -> void:
	if texto == "":
		return
	var nome := _nome_do_peer(autor)

	match canal:
		Canal.SUSSURRO:
			var destino := _peer_por_nome(alvo)
			if destino == 0:
				_entregar(autor, {
					"canal": Canal.SISTEMA, "autor": "", "autor_id": 0,
					"texto": "Ninguém online se chama \"%s\"." % alvo, "alvo": "",
				})
				return
			var linha := {
				"canal": Canal.SUSSURRO, "autor": nome, "autor_id": autor,
				"texto": texto, "alvo": _nome_do_peer(destino),
			}
			_entregar(destino, linha)
			if destino != autor:
				_entregar(autor, linha)   # eco para quem mandou ver o que disse
		Canal.LOCAL:
			var origem: Vector2 = Rede.jogadores.get(autor, {}).get("pos", Vector2.ZERO)
			var mapa := String(Rede.jogadores.get(autor, {}).get("mapa", ""))
			var linha_local := {
				"canal": Canal.LOCAL, "autor": nome, "autor_id": autor, "texto": texto, "alvo": "",
			}
			for id in Rede.jogadores:
				var info: Dictionary = Rede.jogadores[id]
				if String(info.get("mapa", "")) != mapa:
					continue
				var pos: Vector2 = info.get("pos", Vector2.ZERO)
				if pos.distance_to(origem) <= RAIO_LOCAL:
					_entregar(id, linha_local)
		_:
			var linha_geral := {
				"canal": Canal.GERAL, "autor": nome, "autor_id": autor, "texto": texto, "alvo": "",
			}
			for id in Rede.jogadores:
				_entregar(id, linha_geral)


func _entregar(peer: int, linha: Dictionary) -> void:
	if peer == Rede.meu_id() or peer == 0:
		_registrar(linha)
		return
	_receber.rpc_id(peer, linha)


@rpc("authority", "call_remote", "reliable")
func _receber(linha: Dictionary) -> void:
	_registrar(linha)


@rpc("authority", "call_remote", "reliable")
func _recusar(motivo: String) -> void:
	sistema(motivo)


# --- histórico ----------------------------------------------------------------

## Linha do próprio jogo (entrou, saiu, aviso). Nunca vai para a rede.
func sistema(texto: String) -> void:
	_registrar({
		"canal": Canal.SISTEMA, "autor": "", "autor_id": 0, "texto": texto, "alvo": "",
	})


func _registrar(linha: Dictionary) -> void:
	linha["hora"] = Time.get_time_string_from_system().substr(0, 5)
	linha["proprio"] = linha.get("proprio", int(linha.get("autor_id", 0)) == Rede.meu_id())
	if int(linha.get("canal", Canal.GERAL)) == Canal.SUSSURRO and not bool(linha["proprio"]):
		ultimo_sussurro = String(linha.get("autor", ""))
	historico.append(linha)
	if historico.size() > HISTORICO_MAXIMO:
		historico = historico.slice(historico.size() - HISTORICO_MAXIMO)
	mensagem.emit(linha)


func _meu_nome() -> String:
	return GameManager.player.display_name if GameManager.player != null else "Treinador"


func _nome_do_peer(peer: int) -> String:
	if peer == Rede.meu_id():
		return _meu_nome()
	return String(Rede.jogadores.get(peer, {}).get("nome", "Alguém"))


func _peer_por_nome(nome: String) -> int:
	var procurado := nome.strip_edges().to_lower()
	if procurado == "":
		return 0
	for id in Rede.jogadores:
		if String(Rede.jogadores[id].get("nome", "")).to_lower() == procurado:
			return id
	return 0
