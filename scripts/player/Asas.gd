class_name Asas
extends Node3D
## Um par de asas nas costas do personagem, que bate e sustenta o voo.
##
## Modeladas em código, não baixadas. Procurei modelo pronto e não achei asa em
## CC0 que combinasse com o traço do jogo — o que existe é CC-BY com licença por
## arquivo. Além disso, asa precisa **bater**: um `.glb` fechado seria uma peça
## rígida, e aqui cada pena é um nó separado que eu giro. É o mesmo caminho do
## resto da arte de protótipo (`CreatureModelBuilder`, `MapBuilder._make_*`).
##
## Duas poses e a transição entre elas:
##   dobrada  — em pé no chão, encostadas nas costas, quase paradas
##   aberta   — voando, batida ampla com as penas em onda
##
## A onda vem de atrasar cada pena um pouco em relação à anterior. Sem isso as
## penas sobem em bloco e a asa parece uma placa, não uma asa.

const PENAS := 4
const COMPRIMENTO_BASE := 0.86
const LARGURA_BASE := 0.26

## Quanto cada pena atrasa em relação à de dentro, em radianos de fase.
const ATRASO_ENTRE_PENAS := 0.42

## Amplitude da batida, em graus.
const ABERTURA_DOBRADA := 8.0
const ABERTURA_VOANDO := 42.0

## Batidas por segundo em cada estado.
const RITMO_DOBRADA := 0.9
const RITMO_VOANDO := 4.6

const COR_INTERNA := Color("#E8DCC4")
const COR_EXTERNA := Color("#C9922F")

var _lados: Array[Node3D] = []
var _penas: Array[Array] = []
var _fase: float = 0.0
## 0 = dobrada, 1 = voando. Interpolado para a troca não ser um estalo.
var _abertura: float = 0.0


static func criar(cor_interna: Color = COR_INTERNA, cor_externa: Color = COR_EXTERNA) -> Asas:
	var node := Asas.new()
	node.name = "Asas"
	node._montar(cor_interna, cor_externa)
	return node


func _montar(cor_interna: Color, cor_externa: Color) -> void:
	for lado in [-1.0, 1.0]:
		var raiz := Node3D.new()
		raiz.name = "AsaEsquerda" if lado < 0.0 else "AsaDireita"
		# Bem atrás da espinha, onde ficaria a escápula. A distância importa: a
		# 0,06 as asas nasciam **dentro** da capa do cavaleiro e só as pontas
		# apareciam, o que parecia asa quebrada em vez de asa escondida.
		raiz.position = Vector3(lado * 0.13, 0.06, 0.24)
		add_child(raiz)
		_lados.append(raiz)

		var penas: Array[Node3D] = []
		for i in PENAS:
			var t := float(i) / float(maxi(1, PENAS - 1))
			# As penas de fora são mais longas e mais estreitas.
			var comprimento := COMPRIMENTO_BASE * (1.0 + t * 0.55)
			var largura := LARGURA_BASE * (1.0 - t * 0.45)

			var pivo := Node3D.new()
			pivo.name = "Pena%d" % i
			# Leque: cada pena abre um pouco mais para trás que a anterior.
			pivo.rotation_degrees = Vector3(t * 26.0, lado * (14.0 + t * 30.0), lado * (t * 18.0))
			raiz.add_child(pivo)

			var malha := BoxMesh.new()
			malha.size = Vector3(comprimento, 0.035, largura)

			var material := StandardMaterial3D.new()
			material.albedo_color = cor_interna.lerp(cor_externa, t)
			material.roughness = 0.85
			material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED

			var visual := MeshInstance3D.new()
			visual.mesh = malha
			visual.material_override = material
			# Deslocada meia peça: assim o pivô fica na base da pena e ela gira
			# a partir do corpo, e não pelo meio.
			visual.position = Vector3(lado * comprimento * 0.5, 0.0, 0.0)
			pivo.add_child(visual)

			penas.append(pivo)
		_penas.append(penas)


## `voando` troca a pose; a mudança é suave, não instantânea.
func definir_voo(voando: bool, delta: float) -> void:
	var alvo := 1.0 if voando else 0.0
	_abertura = move_toward(_abertura, alvo, delta * 3.2)


func _process(delta: float) -> void:
	var ritmo: float = lerpf(RITMO_DOBRADA, RITMO_VOANDO, _abertura)
	var amplitude: float = lerpf(ABERTURA_DOBRADA, ABERTURA_VOANDO, _abertura)
	_fase += delta * ritmo * TAU

	for lado_indice in _lados.size():
		var sinal := -1.0 if lado_indice == 0 else 1.0
		var penas: Array = _penas[lado_indice]
		for i in penas.size():
			var pena: Node3D = penas[i]
			var onda := sin(_fase - i * ATRASO_ENTRE_PENAS)
			# Só o giro de bater é sobrescrito; o leque montado continua valendo.
			pena.rotation_degrees.z = sinal * (float(i) / float(maxi(1, PENAS - 1)) * 18.0) + onda * amplitude * sinal
