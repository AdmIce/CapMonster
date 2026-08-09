class_name RemotePlayer
extends Node3D
## O boneco de outro jogador.
##
## Não é um PlayerController: não tem colisão, input, sensor de interação nem
## física. Ele só recebe uma posição pela rede e caminha até ela. Reaproveitar o
## controlador aqui traria colisão entre jogadores e um corpo que a física tenta
## resolver — coisas que a etapa 1 não precisa e que causariam empurrão a
## distância enquanto a autoridade ainda é local.
##
## A posição chega a 15 Hz; o quadro roda a 60. Por isso o nó anda **em direção**
## ao último ponto recebido em vez de saltar para ele, e a velocidade da caminhada
## sai do próprio deslocamento — assim a animação bate com o que se vê.

## Acima disto assume-se teleporte (troca de mapa, portal) e o boneco salta.
const DISTANCIA_DE_SALTO := 12.0
const SUAVIDADE := 12.0
const ALTURA_DO_NOME := 2.15

## Tamanho do nome flutuante.
##
## Com `fixed_size`, a etiqueta não encolhe com a distância: a altura dela na
## tela é mais ou menos `TAMANHO_FONTE * PIXEL * altura_da_viewport / (2·tan(fov/2))`.
## Com fov 58 e 720p isso dá ~649 de fator, então o 0,0032 de antes rendia uns
## **66 pixels** de altura — nome maior que a cabeça do boneco. 0,0008 põe em
## torno de 17, na mesma faixa do texto do HUD.
const TAMANHO_FONTE := 32
const PIXEL_DO_NOME := 0.0008
## O contorno é medido na escala da fonte, não na da tela: 12 sobre uma fonte 32
## engrossava a letra a ponto de fechar os buracos do "a" e do "o".
const CONTORNO_DO_NOME := 5

var id_do_peer: int = 0

var _avatar: PlayerAvatar = null
var _etiqueta: Label3D = null
var _companheiro: CompanionCreature = null
## Espécie do mascote já montado, para não reconstruir a cada pacote.
var _especie_do_mascote: String = ""
var _alvo := Vector2.ZERO
var _giro_alvo: float = 0.0
var _correndo: bool = false
var _altura_alvo: float = 0.0


static func criar(id: int, info: Dictionary) -> RemotePlayer:
	var node := RemotePlayer.new()
	node.name = "Remoto_%d" % id
	node.id_do_peer = id
	node._alvo = info.get("pos", Vector2.ZERO)
	node._giro_alvo = float(info.get("giro", 0.0))
	return node


func _ready() -> void:
	position = Vector3(_alvo.x, 0.0, _alvo.y)
	rotation.y = _giro_alvo

	_avatar = PlayerAvatar.new()
	_avatar.name = "Avatar"
	add_child(_avatar)

	_etiqueta = Label3D.new()
	_etiqueta.name = "Nome"
	_etiqueta.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_etiqueta.no_depth_test = true
	_etiqueta.fixed_size = true
	_etiqueta.font_size = TAMANHO_FONTE
	_etiqueta.pixel_size = PIXEL_DO_NOME
	_etiqueta.outline_size = CONTORNO_DO_NOME
	_etiqueta.modulate = Design.GOLD_CLARO
	_etiqueta.outline_modulate = Color(0.05, 0.05, 0.06, 0.9)
	_etiqueta.position = Vector3(0, ALTURA_DO_NOME, 0)
	add_child(_etiqueta)


func aplicar(info: Dictionary) -> void:
	_alvo = info.get("pos", _alvo)
	_giro_alvo = float(info.get("giro", _giro_alvo))
	_correndo = bool(info.get("correndo", false))
	_altura_alvo = float(info.get("altura", 0.0))
	if _etiqueta != null:
		_etiqueta.text = String(info.get("nome", "?"))
	if _avatar != null and info.has("aparencia"):
		_avatar.apply_appearance(info["aparencia"])
	_atualizar_mascote(info.get("lider", {}))


## O mascote do outro jogador.
##
## Reaproveita o `CompanionCreature` inteiro — é o mesmo comportamento de andar
## atrás, correr para alcançar e reaparecer quando fica longe. Fazer um segundo
## companheiro "só para o remoto" seria duas lógicas para dessincronizar.
##
## Ele entra como irmão deste nó, não como filho: o companheiro se move sozinho,
## e pendurado aqui ele seria arrastado junto e nunca ficaria para trás.
func _atualizar_mascote(lider: Variant) -> void:
	var dados: Dictionary = lider if lider is Dictionary else {}
	var especie := String(dados.get("especie", ""))
	if especie == _especie_do_mascote:
		return
	_especie_do_mascote = especie

	if especie == "" or not DataManager.has_species(StringName(especie)):
		if _companheiro != null and is_instance_valid(_companheiro):
			_companheiro.queue_free()
			_companheiro = null
		return

	if _companheiro == null or not is_instance_valid(_companheiro):
		_companheiro = CompanionCreature.new()
		_companheiro.name = "MascoteDe_%d" % id_do_peer
		get_parent().add_child(_companheiro)
		_companheiro.seguir(self)

	_companheiro.definir_criatura(
		CreatureFactory.create(StringName(especie), maxi(1, int(dados.get("nivel", 1))))
	)


func _exit_tree() -> void:
	# O mascote é irmão, então sair de cena não o leva junto.
	if _companheiro != null and is_instance_valid(_companheiro):
		_companheiro.queue_free()
		_companheiro = null


func _process(delta: float) -> void:
	var atual := Vector2(position.x, position.z)
	var distancia := atual.distance_to(_alvo)

	if distancia > DISTANCIA_DE_SALTO:
		position = Vector3(_alvo.x, _altura_alvo, _alvo.y)
		rotation.y = _giro_alvo
		if _avatar != null:
			_avatar.set_locomotion(0.0, false)
		return

	var peso := clampf(SUAVIDADE * delta, 0.0, 1.0)
	var novo := atual.lerp(_alvo, peso)
	position = Vector3(novo.x, lerpf(position.y, _altura_alvo, peso), novo.y)
	rotation.y = lerp_angle(rotation.y, _giro_alvo, peso)

	# A animação vem do deslocamento real deste quadro, não do que foi anunciado:
	# se o pacote atrasar, o boneco para de andar em vez de patinar no lugar.
	if _avatar != null:
		var velocidade := atual.distance_to(novo) / maxf(0.0001, delta)
		_avatar.set_locomotion(clampf(velocidade / PlayerController.RUN_SPEED, 0.0, 1.0), _correndo)
