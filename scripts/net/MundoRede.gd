extends Node
## Autoridade do mundo: quem manda nas criaturas selvagens.
##
## O princípio que sustenta o resto do online: **um caminho de código, duas
## autoridades**. Jogando sozinho, o próprio processo é o dono do mundo; numa
## partida, o dono é o host (ou, depois, o servidor dedicado). O `SpawnManager`
## não pergunta "estou online?" — ele pergunta "eu sou o dono?". Offline a
## resposta é sim, e nada muda em relação ao jogo de um jogador só.
##
## Sem isso, cada máquina sorteava as próprias criaturas: dois jogadores lado a
## lado viam bichos diferentes no mesmo lugar.
##
## Divisão de responsabilidade:
##   dono    - sorteia, decide onde nasce, guarda a lista e libera o encontro;
##   cliente - só materializa o que o dono mandou e pede permissão para lutar.
##
## Mora num autoload porque o Godot roteia RPC por caminho de nó e o mundo é
## construído por código: `/root/MundoRede` é igual em todas as máquinas.

signal criatura_liberada(id: int, dados: Dictionary)
signal criatura_removida(id: int)
signal encontro_respondido(id: int, permitido: bool)

## id da criatura -> { id, mapa, zona, pos: Vector2, criatura: Dictionary }
var criaturas: Dictionary = {}

## id da criatura -> peer que está lutando com ela. Existe só no dono.
var _reservas: Dictionary = {}

var _proximo_id: int = 1


func _ready() -> void:
	Rede.jogador_entrou.connect(_ao_entrar_jogador)
	Rede.estado_mudou.connect(_ao_mudar_estado)


## Verdadeiro quando este processo decide o que acontece no mundo.
##
## CONECTANDO conta como **não-dono** de propósito: entre pedir a conexão e ela
## fechar existe uma janela de um a dois segundos, e continuar sorteando bicho
## nela só cria fauna que vai ser jogada fora daqui a pouco.
func sou_o_dono() -> bool:
	return Rede.estado == Rede.Estado.OFFLINE or Rede.estado == Rede.Estado.HOSPEDANDO


## Esvaziar a lista não basta: os nós continuam na cena. Quem escuta
## `criatura_removida` é que sabe apagá-los — sem este aviso, entrar numa
## partida deixava a fauna local invisível para os outros circulando por cima da
## do dono.
func limpar() -> void:
	if not criaturas.is_empty():
		GameLog.info(GameLog.Channel.WORLD, "MundoRede: apagando %d criatura(s) da autoridade anterior." % criaturas.size())
	for id in criaturas.keys():
		criatura_removida.emit(id)
	criaturas.clear()
	_reservas.clear()


# --- lado do dono -------------------------------------------------------------

## Chamado pelo SpawnManager do dono logo depois de sortear a criatura. Devolve o
## id que passa a identificá-la em todas as máquinas.
func registrar(mapa: String, zona: String, pos: Vector2, criatura: Dictionary) -> int:
	var id := _proximo_id
	_proximo_id += 1
	var registro := {"id": id, "mapa": mapa, "zona": zona, "pos": pos, "criatura": criatura}
	criaturas[id] = registro
	if Rede.estado == Rede.Estado.HOSPEDANDO:
		_nasceu.rpc(registro)
	return id


func remover(id: int) -> void:
	if not criaturas.erase(id):
		return
	_reservas.erase(id)
	if Rede.estado == Rede.Estado.HOSPEDANDO:
		_morreu.rpc(id)


## Quem acabou de chegar recebe o mundo inteiro de uma vez. Mandar criatura por
## criatura funcionaria, mas na entrada são dezenas de pacotes ao mesmo tempo.
func _ao_entrar_jogador(id_do_peer: int, _info: Dictionary) -> void:
	if Rede.estado != Rede.Estado.HOSPEDANDO:
		return
	_mundo_inteiro.rpc_id(id_do_peer, criaturas.values())


## Sair de uma partida devolve a autoridade para a própria máquina; a lista do
## host não vale mais nada aqui. O spawner local repovoa as zonas no próximo
## tique, então o mapa não fica vazio.
func _ao_mudar_estado() -> void:
	if Rede.estado == Rede.Estado.OFFLINE or Rede.estado == Rede.Estado.CONECTANDO:
		limpar()


# --- replicação ---------------------------------------------------------------

@rpc("authority", "call_remote", "reliable")
func _nasceu(registro: Dictionary) -> void:
	var id := int(registro.get("id", 0))
	if id == 0 or criaturas.has(id):
		return
	criaturas[id] = registro
	criatura_liberada.emit(id, registro)


@rpc("authority", "call_remote", "reliable")
func _morreu(id: int) -> void:
	if criaturas.erase(id):
		criatura_removida.emit(id)


## O mundo que valia até agora era o local: quem entra numa partida construiu a
## própria cena antes de conectar e já tinha sorteado a sua fauna. Apagar essa
## fauna é parte de receber a do dono — sem isso o mapa fica com o dobro de
## bichos, metade deles invisível para todo mundo menos para quem entrou.
@rpc("authority", "call_remote", "reliable")
func _mundo_inteiro(lista: Array) -> void:
	var descartadas := criaturas.size()
	for id_antigo in criaturas.keys():
		criatura_removida.emit(id_antigo)
	criaturas.clear()
	_reservas.clear()

	for registro in lista:
		if not registro is Dictionary:
			continue
		var id := int(registro.get("id", 0))
		if id == 0:
			continue
		criaturas[id] = registro
		criatura_liberada.emit(id, registro)

	GameLog.info(GameLog.Channel.WORLD, "MundoRede: %d criatura(s) vieram do dono (%d local(is) descartada(s))." % [
		criaturas.size(), descartadas
	])


# --- reserva de encontro ------------------------------------------------------

## O cliente nunca começa a batalha sozinho: ele pede. Sem isso, dois jogadores
## que encostam na mesma criatura ao mesmo tempo lutariam cada um com a sua cópia
## e os dois capturariam o mesmo bicho.
func pedir_encontro(id: int) -> void:
	if sou_o_dono():
		encontro_respondido.emit(id, _reservar(id, Rede.meu_id()))
		return
	_pedir.rpc_id(1, id)


@rpc("any_peer", "call_remote", "reliable")
func _pedir(id: int) -> void:
	if Rede.estado != Rede.Estado.HOSPEDANDO:
		return
	var solicitante := multiplayer.get_remote_sender_id()
	_responder.rpc_id(solicitante, id, _reservar(id, solicitante))


@rpc("authority", "call_remote", "reliable")
func _responder(id: int, permitido: bool) -> void:
	encontro_respondido.emit(id, permitido)


## Só existe no dono. Uma criatura reservada continua no mundo (os outros a veem)
## mas ninguém mais consegue iniciar batalha com ela.
func _reservar(id: int, peer: int) -> bool:
	if not criaturas.has(id):
		return false
	var dono_atual := int(_reservas.get(id, 0))
	if dono_atual != 0 and dono_atual != peer:
		return false
	_reservas[id] = peer
	return true


func liberar_reserva(id: int) -> void:
	if sou_o_dono():
		_reservas.erase(id)
