class_name PetAcompanhante
extends Node3D
## Um bicho de estimação que voa ao lado do jogador.
##
## Não é filho do jogador, ao contrário da montaria. Filho seguiria posição e
## giro no mesmo quadro, e um acompanhante grudado que gira junto parece peça de
## roupa, não bicho. Aqui ele persegue um ponto ao lado do dono com atraso, e é
## esse atraso que faz ele parecer vivo.
##
## O modelo não tem animação nenhuma — é uma estátua alada. Então o movimento é
## todo daqui: sobe e desce no ar, e vira para onde está indo.

## O modelo vem com 1,5 m, quase a altura do jogador -- na tela lia como um
## segundo personagem, e nao como um acompanhante. A 0,75 ele fica com ~1,1 m.
const ESCALA := 0.75

const ALTURA_DE_VOO := 1.1
## Onde ele fica em relação ao dono: à direita e um pouco atrás, para não tapar
## a frente da câmera nem entrar no caminho.
const DESLOCAMENTO_LATERAL := 1.3
const DESLOCAMENTO_ATRAS := 0.7

## Quanto ele corre atrás do ponto. Alto o bastante para acompanhar corrida a
## 12 m/s (montado) sem ficar para trás.
const VELOCIDADE := 9.0

## Sobe e desce: amplitude em metros e batidas por segundo.
const BALANCO := 0.13
const RITMO := 1.6

## Abaixo desta velocidade ele para de virar. Sem isso ele fica rodopiando
## parado, porque qualquer tremida vira uma direção nova.
const VELOCIDADE_MINIMA_PARA_VIRAR := 0.4

var _dono: Node3D = null
var _modelo: Node3D = null
var _fase: float = 0.0


static func criar(caminho: String) -> PetAcompanhante:
	var no := PetAcompanhante.new()
	no.name = "Pet"
	no.set_meta("modelo", caminho)
	return no


func _ready() -> void:
	var caminho := String(get_meta("modelo", ""))
	if not ResourceLoader.exists(caminho):
		GameLog.warn(GameLog.Channel.WORLD, "Modelo do pet ausente: %s" % caminho)
		return
	_modelo = (load(caminho) as PackedScene).instantiate() as Node3D
	if _modelo == null:
		return
	# Igual a todo modelo importado aqui: olha para +Z, e o projeto assume -Z.
	_modelo.rotation_degrees.y = 180.0
	_modelo.scale = Vector3.ONE * ESCALA
	add_child(_modelo)


func seguir(dono: Node3D) -> void:
	_dono = dono
	if dono != null and is_inside_tree():
		# Nasce já no lugar, senão ele vem voando do centro do mapa na primeira
		# vez que é chamado.
		global_position = _ponto_de_voo()


func _process(delta: float) -> void:
	if _dono == null or not is_instance_valid(_dono):
		return

	_fase += delta * RITMO * TAU
	var alvo := _ponto_de_voo()
	alvo.y += sin(_fase) * BALANCO

	var antes := global_position
	global_position = global_position.lerp(alvo, clampf(VELOCIDADE * delta, 0.0, 1.0))

	# Vira para onde está indo, e não para onde o dono olha: assim ele curva
	# quando corta caminho, que é o que faz ele parecer que voa por conta.
	var movimento := global_position - antes
	var plano := Vector2(movimento.x, movimento.z)
	if plano.length() / maxf(delta, 0.0001) > VELOCIDADE_MINIMA_PARA_VIRAR:
		rotation.y = lerp_angle(rotation.y, atan2(plano.x, plano.y), 6.0 * delta)


## O ponto ao lado do dono, em mundo. Calculado a partir do giro dele, para o
## pet trocar de lado quando o dono se vira.
func _ponto_de_voo() -> Vector3:
	var giro := _dono.rotation.y
	var direita := Vector3(cos(giro), 0.0, -sin(giro))
	var atras := Vector3(sin(giro), 0.0, cos(giro))
	return _dono.global_position \
		+ direita * DESLOCAMENTO_LATERAL \
		+ atras * DESLOCAMENTO_ATRAS \
		+ Vector3(0.0, ALTURA_DE_VOO, 0.0)
