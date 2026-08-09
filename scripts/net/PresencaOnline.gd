class_name PresencaOnline
extends Node3D
## Mantém no mundo um boneco para cada outro jogador conectado.
##
## Fica entre o `Rede` (que só conhece números) e a cena (que só conhece nós):
## escuta os sinais da rede, cria e remove `RemotePlayer`, e todo quadro manda a
## nossa própria posição. O WorldRoot só precisa criar este nó e esquecer.
##
## Só desenha quem está no **mesmo mapa**. Quem está em outro continua na lista
## de online — some do mundo, não da partida.

var _mapa: String = ""
var _jogador: PlayerController = null
var _bonecos: Dictionary = {}   ## id do peer -> RemotePlayer


static func criar(mapa: String, jogador: PlayerController) -> PresencaOnline:
	var node := PresencaOnline.new()
	node.name = "PresencaOnline"
	node._mapa = mapa
	node._jogador = jogador
	return node


func _ready() -> void:
	Rede.jogador_entrou.connect(_ao_entrar)
	Rede.jogador_saiu.connect(_ao_sair)
	Rede.jogador_moveu.connect(_ao_mover)
	Rede.estado_mudou.connect(_ressincronizar)
	_ressincronizar()


func _exit_tree() -> void:
	# Trocar de mapa destrói o mundo inteiro; a lista da rede sobrevive. Sem
	# limpar aqui, os nós ficariam apontando para bonecos já liberados.
	_bonecos.clear()


func _process(delta: float) -> void:
	if _jogador == null or not is_instance_valid(_jogador):
		return
	var plano := _jogador.plane_position()
	Rede.informar_posicao(
		delta, plano, _jogador.rotation.y,
		Vector2(_jogador.velocity.x, _jogador.velocity.z).length() > PlayerController.WALK_SPEED + 0.5,
		_mapa, _jogador.global_position.y
	)


## Refaz a lista inteira a partir do que a rede sabe agora. É o caminho usado na
## entrada e sempre que a conexão muda de estado — mais simples e mais difícil de
## dessincronizar do que tentar aplicar diferenças à mão.
func _ressincronizar() -> void:
	var esperados := Rede.companheiros_no_mapa(_mapa)

	for id in _bonecos.keys():
		if not esperados.has(id):
			_remover(id)

	for id in esperados:
		if _bonecos.has(id):
			_bonecos[id].aplicar(esperados[id])
		else:
			_criar(id, esperados[id])


func _ao_entrar(id: int, info: Dictionary) -> void:
	if String(info.get("mapa", "")) == _mapa:
		_criar(id, info)
		Notify.good("%s entrou no seu mundo." % info.get("nome", "Alguém"))


func _ao_sair(id: int) -> void:
	_remover(id)


## Também é aqui que a troca de mapa aparece: o pacote de posição carrega o mapa,
## então alguém que saiu do nosso simplesmente deixa de ser desenhado.
func _ao_mover(id: int, info: Dictionary) -> void:
	var aqui := String(info.get("mapa", "")) == _mapa
	if aqui and not _bonecos.has(id):
		_criar(id, info)
	elif not aqui and _bonecos.has(id):
		_remover(id)
	elif aqui:
		_bonecos[id].aplicar(info)


func _criar(id: int, info: Dictionary) -> void:
	var boneco := RemotePlayer.criar(id, info)
	add_child(boneco)
	boneco.aplicar(info)
	_bonecos[id] = boneco
	GameLog.info(GameLog.Channel.WORLD, "Presença: %s apareceu em %s (%d no mapa)." % [
		info.get("nome", "?"), _mapa, _bonecos.size()
	])


func _remover(id: int) -> void:
	var boneco: RemotePlayer = _bonecos.get(id, null)
	if boneco != null and is_instance_valid(boneco):
		boneco.queue_free()
	if _bonecos.erase(id):
		GameLog.info(GameLog.Channel.WORLD, "Presença: peer %d saiu do mapa (%d restam)." % [
			id, _bonecos.size()
		])


func quantidade() -> int:
	return _bonecos.size()
