extends Node
## Autoridade sobre o progresso do jogador: ouro, itens, XP e coleção.
##
## Mesmo princípio das outras camadas — **um caminho de código, duas
## autoridades**. Nada no jogo altera ouro ou inventário direto: tudo passa por
## `pedir()`. Jogando sozinho, o próprio processo é o dono e a mudança acontece
## no mesmo quadro; numa partida, o cliente manda a intenção e o dono decide.
##
## O que isso conserta: até aqui, comprar um item tirava ouro na máquina de quem
## clicou. Um cliente adulterado se dava ouro infinito e o servidor nem ficava
## sabendo. Agora o servidor é quem tem a ficha, e o cliente só recebe o
## resultado.
##
## **A ficha mora no servidor.** Quando você entra no mundo de alguém, o seu
## personagem daquele mundo fica guardado lá, em `user://mundo/<id>.json` — como
## num servidor privado de qualquer jogo online. O seu save de um jogador só
## continua sendo seu e separado; são dois personagens, e isso é de propósito.
##
## O arquivo é nomeado pelo `jogador_id`, e **não** pelo nome. Guardar por nome
## parecia óbvio e quebrou na primeira partida de verdade: todo mundo começa
## como "Treinador", então dois amigos entravam no mesmo mundo e dividiam o mesmo
## personagem — a aparência de um aparecia no outro e o ouro era o mesmo saldo.
##
## Nome e aparência são do jogador, não do mundo: o servidor os recebe do cliente
## a cada visita e nunca os devolve por cima. Não há o que ganhar trapaceando com
## a própria roupa, e sobrescrever fazia o personagem trocar de cara ao entrar.
##
## A intenção é genérica (`pedir(acao, argumentos)`) em vez de um RPC por ação
## porque a lista de ações vai crescer, e uma porta só é uma porta só para
## validar.

signal ficha_sincronizada()
signal recusado(motivo: String)

const PASTA_MUNDO := "user://mundo/"

## Ações que um cliente pode pedir. Qualquer coisa fora desta lista é ignorada —
## é a diferença entre validar e confiar.
const ACOES := ["comprar", "vender", "usar_item", "recompensa", "capturar"]

## Teto para as recompensas que ainda chegam com o valor pronto (missão e idle).
## Medido no jogo: a missão mais generosa paga algumas centenas, e o idle de uma
## noite inteira fica na mesma ordem. Mil é folgado para o jogo honesto e
## apertado para quem tenta pedir um milhão.
const TETO_DE_OURO_POR_PEDIDO := 1000
const TETO_DE_XP_POR_PEDIDO := 1000

## Ficha de cada peer conectado. Só existe no dono.
var _fichas: Dictionary = {}    ## peer -> PlayerData
var _nomes: Dictionary = {}     ## peer -> nome do personagem


func _ready() -> void:
	Rede.jogador_saiu.connect(_ao_sair)
	Rede.estado_mudou.connect(_ao_mudar_estado)


func sou_o_dono() -> bool:
	return MundoRede.sou_o_dono()


## A ficha que vale para este processo agora.
func minha() -> PlayerData:
	return GameManager.player


# --- porta única --------------------------------------------------------------

## Pede uma mudança de progresso. Devolve verdadeiro quando a intenção foi
## aceita **localmente**; num cliente isso só quer dizer "enviada", e o
## resultado chega depois em `ficha_sincronizada`.
func pedir(acao: String, argumentos: Dictionary = {}) -> bool:
	if not ACOES.has(acao):
		push_error("Ficha: ação desconhecida '%s'." % acao)
		return false

	if sou_o_dono():
		var ficha := minha() if not Rede.online() else _ficha_de(Rede.meu_id())
		var erro := _aplicar(ficha, acao, argumentos)
		if erro != "":
			recusado.emit(erro)
			return false
		ficha_sincronizada.emit()
		return true

	_pedir_ao_dono.rpc_id(1, acao, argumentos)
	return true


@rpc("any_peer", "call_remote", "reliable")
func _pedir_ao_dono(acao: String, argumentos: Dictionary) -> void:
	if not sou_o_dono() or not ACOES.has(acao):
		return
	var peer := multiplayer.get_remote_sender_id()
	var ficha := _ficha_de(peer)
	if ficha == null:
		return

	var erro := _aplicar(ficha, acao, argumentos)
	if erro != "":
		_recusar.rpc_id(peer, erro)
		return
	_gravar(peer)
	_sincronizar.rpc_id(peer, ficha.to_dict())


@rpc("authority", "call_remote", "reliable")
func _sincronizar(dados: Dictionary) -> void:
	var ficha := minha()
	if ficha == null:
		return
	ficha.sincronizar(dados)
	ficha_sincronizada.emit()


@rpc("authority", "call_remote", "reliable")
func _recusar(motivo: String) -> void:
	recusado.emit(motivo)


# --- regras (só rodam no dono) ------------------------------------------------

## Devolve "" quando deu certo, ou o motivo da recusa.
##
## Toda validação mora aqui, de um lado só da rede. O cliente também esconde o
## botão de comprar sem ouro, mas isso é conforto: quem decide é este método.
func _aplicar(ficha: PlayerData, acao: String, a: Dictionary) -> String:
	if ficha == null:
		return "Sem ficha."

	match acao:
		"comprar":
			var item_id := String(a.get("item", ""))
			if DataManager.get_item(item_id).is_empty():
				return "Item desconhecido."
			# O preço sai do banco de dados, nunca do pacote: aceitar o número que
			# o cliente mandou seria deixar ele comprar por zero.
			if not ficha.spend_gold(_preco_de(item_id)):
				return "Ouro insuficiente."
			ficha.add_item(item_id, 1)
			return ""

		"vender":
			var item_id := String(a.get("item", ""))
			var margem := clampf(float(a.get("margem", 0.4)), 0.0, 1.0)
			if not ficha.consume_item(item_id, 1):
				return "Você não tem esse item."
			ficha.add_gold(maxi(1, int(round(_preco_de(item_id) * margem))))
			return ""

		"usar_item":
			var item_id := String(a.get("item", ""))
			if not ficha.consume_item(item_id, 1):
				return "Você não tem esse item."
			return ""

		"recompensa":
			# Fim de batalha, missão e idle.
			#
			# Batalha manda `derrotados` — espécie e nível — e **o dono faz a
			# conta**. Antes o cliente mandava o número pronto e ele era aplicado
			# como veio: um cliente alterado pedia um milhão de ouro e recebia um
			# milhão. Agora o valor sai da tabela do jogo, e mentir sobre o número
			# não funciona mais. O que ainda dá para mentir é sobre *ter*
			# derrotado, e isso só fecha movendo a batalha inteira para cá.
			var derrotados: Array = a.get("derrotados", [])
			if not derrotados.is_empty():
				var conta := RecompensaDeBatalha.calcular(derrotados)
				ficha.add_gold(int(conta["ouro"]))
				if int(conta["xp_do_jogador"]) > 0:
					ficha.grant_xp(int(conta["xp_do_jogador"]))
				return ""

			# Missão e idle ainda mandam número pronto, e aqui ele é limitado: um
			# teto não impede a trapaça, mas transforma "ouro infinito" em "um
			# pouco de ouro de cada vez", que é a diferença entre quebrar a
			# economia e arranhar ela.
			ficha.add_gold(clampi(int(a.get("ouro", 0)), 0, TETO_DE_OURO_POR_PEDIDO))
			if int(a.get("xp", 0)) > 0:
				ficha.grant_xp(clampi(int(a.get("xp", 0)), 0, TETO_DE_XP_POR_PEDIDO))
			var itens: Dictionary = a.get("itens", {})
			for item_id in itens:
				if not DataManager.get_item(String(item_id)).is_empty():
					ficha.add_item(String(item_id), maxi(0, int(itens[item_id])))
			return ""

		"capturar":
			var criatura := CreatureData.from_dict(a.get("criatura", {}))
			if criatura == null:
				return "Criatura inválida."
			ficha.add_creature(criatura)
			return ""

	return "Ação desconhecida."


## `value` é o nome do campo no items.json — o mesmo que a loja usa para montar
## a etiqueta. Se os dois lerem campos diferentes, o preço mostrado e o cobrado
## divergem, e o jogador vê o ouro sumir errado.
static func _preco_de(item_id: String) -> int:
	return maxi(1, int(DataManager.get_item(item_id).get("value", 0)))


# --- fichas guardadas no servidor ---------------------------------------------

func _ficha_de(peer: int) -> PlayerData:
	if peer == Rede.meu_id():
		return minha()
	return _fichas.get(peer, null)


## Chamado pelo cliente ao entrar: ele diz quem é, o servidor devolve a ficha
## que tem guardada para esse nome (ou aceita a que veio, na primeira visita).
@rpc("any_peer", "call_remote", "reliable")
func apresentar_personagem(nome: String, inicial: Dictionary) -> void:
	if not sou_o_dono():
		return
	var peer := multiplayer.get_remote_sender_id()
	if _fichas.has(peer):
		# Já conhecemos este peer. Reapresentar recarregaria a ficha do disco e
		# jogaria fora o que ele fez desde a última gravação.
		return

	var limpo := nome.strip_edges().substr(0, 24)
	if limpo == "":
		limpo = "Treinador"

	# A busca é pela identidade, nunca pelo nome: todo mundo comeca como
	# "Treinador", e guardar por nome fazia dois amigos dividirem o mesmo
	# personagem no mesmo mundo.
	var identidade := String(inicial.get("jogador_id", "")).strip_edges()
	if identidade == "":
		GameLog.warn(GameLog.Channel.SYSTEM, "Ficha: cliente sem identidade; recusado.")
		return

	var ficha := _carregar(identidade)
	if ficha == null:
		# Primeira visita: o mundo ainda não conhece este personagem, então
		# aceita o que o jogador trouxe. Daqui para frente quem manda é o
		# servidor, e o arquivo local dele não altera mais nada aqui.
		ficha = PlayerData.from_dict(inicial)
		GameLog.info(GameLog.Channel.SYSTEM, "Ficha: '%s' entrou pela primeira vez neste mundo." % limpo)
	else:
		# Nome e aparência são do jogador, não do mundo: ele pode ter trocado de
		# roupa desde a última visita, e isso vale.
		ficha.display_name = limpo
		ficha.appearance = (inicial.get("appearance", {}) as Dictionary).duplicate()
		GameLog.info(GameLog.Channel.SYSTEM, "Ficha: '%s' voltou (nível %d)." % [limpo, ficha.level])

	ficha.jogador_id = identidade
	_fichas[peer] = ficha
	_nomes[peer] = identidade
	_gravar(peer)
	_sincronizar.rpc_id(peer, ficha.to_dict())


## O cliente se apresenta assim que a conexão fecha — uma vez por conexão.
##
## `estado_mudou` dispara também quando outro jogador entra ou sai, então sem
## esta trava o cliente se reapresentava a cada movimento na sala, e o servidor
## recarregava a ficha do disco por cima do que estava em memória.
var _apresentado: bool = false


func entrar_no_mundo() -> void:
	if sou_o_dono() or minha() == null or _apresentado:
		return
	_apresentado = true
	apresentar_personagem.rpc_id(1, minha().display_name, minha().to_dict())


func _ao_mudar_estado() -> void:
	if Rede.estado == Rede.Estado.CONECTADO:
		entrar_no_mundo()
	elif not Rede.online():
		_apresentado = false
		_fichas.clear()
		_nomes.clear()


func _ao_sair(peer: int) -> void:
	if not sou_o_dono():
		return
	_gravar(peer)
	_fichas.erase(peer)
	_nomes.erase(peer)


func _gravar(peer: int) -> void:
	var ficha: PlayerData = _fichas.get(peer, null)
	var identidade := String(_nomes.get(peer, ""))
	if ficha == null or identidade == "":
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PASTA_MUNDO))
	var arquivo := FileAccess.open(_caminho(identidade), FileAccess.WRITE)
	if arquivo == null:
		GameLog.error(GameLog.Channel.SYSTEM, "Ficha: não consegui gravar '%s'." % identidade)
		return
	arquivo.store_string(JSON.stringify(ficha.to_dict(), "\t"))
	arquivo.close()


func _carregar(identidade: String) -> PlayerData:
	var caminho := _caminho(identidade)
	if not FileAccess.file_exists(caminho):
		return null
	var arquivo := FileAccess.open(caminho, FileAccess.READ)
	if arquivo == null:
		return null
	var bruto := arquivo.get_as_text()
	arquivo.close()
	var dados: Variant = JSON.parse_string(bruto)
	if not (dados is Dictionary):
		return null
	return PlayerData.from_dict(dados)


static func _caminho(identidade: String) -> String:
	# `validate_filename` para uma identidade adulterada não virar caminho de
	# pasta e escrever fora de `user://mundo/`.
	return PASTA_MUNDO + identidade.validate_filename() + ".json"
