class_name Montaria
extends Node3D
## O cavalo que o jogador monta.
##
## Entra como **filho do jogador**, e não como um corpo próprio andando ao lado.
## Assim ele segue posição e giro de graça, e não existe a possibilidade de o
## cavalo ficar para trás numa curva ou atravessar parede por conta própria —
## quem colide continua sendo o jogador, com a mesma cápsula de sempre.
##
## O modelo veio do Sketchfab, convertido de FBX: a raiz do esqueleto fica no
## topo e a malha pendura abaixo dela, então instanciar em y = 0 enterra o
## bicho. A altura certa é medida em cena, do mesmo jeito que a sola do
## personagem — chutar deslocamento foi o que já deixou coisa flutuando aqui.

const MODELO := "res://assets/models/montarias/cavalo.glb"

const ANIM_PARADO := "Horse|Horse_Idle"
const ANIM_ANDANDO := "Horse|Horse_Walk"

## Osso onde a sela fica, em ordem de preferência.
##
## A primeira tentativa foi centralizar pela caixa da malha, e ela erra: o
## pescoço e a cabeça do cavalo puxam a caixa para a frente, então centralizar
## deixa o cavaleiro atrás da garupa. O osso da espinha não tem esse problema --
## ele está onde a sela está.
const OSSOS_DA_SELA: Array[String] = ["spine_03", "spine_02", "spine_01", "pelvis"]

## Altura da sela, como fracao da altura do cavalo.
##
## O osso serve para o horizontal, e nao para o vertical: medido, ele coloca a
## sela em 2,98 m num cavalo de 2,70 m -- o eixo Y deste rig veio virado na
## conversao do FBX (a coluna tem y negativo e a cabeca e o ponto "mais baixo"
## dos ossos). O horizontal saiu exato, entao cada medida e usada onde ela se
## provou certa.
##
## 0,62 de 2,70 da 1,67 m, que e a altura de lombo de um cavalo desse porte.
const FRACAO_DA_SELA := 0.62

## Quanto o cavaleiro avanca a partir do osso da espinha, em metros.
##
## O osso escolhido cai um pouco atras da sela, e na foto o cavaleiro sentava na
## garupa. Empurrar o cavalo para tras e o mesmo que avancar o cavaleiro: o
## cavalo e filho dele, entao mexer no cavaleiro mexeria no cavalo junto.
const AVANCO_DA_SELA := 0.35

## Quanto o passo do cavalo acelera ou desacelera conforme a velocidade real.
## Sem isto o cavalo anda no mesmo ritmo parado ou a galope, e o pé patina.
const RITMO_MINIMO := 0.7
const RITMO_MAXIMO := 1.6

var altura: float = 0.0

var _altura_da_sela: float = 0.0

var _animador: AnimationPlayer = null
var _modelo: Node3D = null
var _andando: bool = false


static func criar() -> Montaria:
	var no := Montaria.new()
	no.name = "Montaria"
	return no


func _ready() -> void:
	if not ResourceLoader.exists(MODELO):
		GameLog.warn(GameLog.Channel.WORLD, "Modelo da montaria ausente: %s" % MODELO)
		return

	_modelo = (load(MODELO) as PackedScene).instantiate() as Node3D
	if _modelo == null:
		return
	# Igual aos personagens: o modelo olha para +Z e o projeto inteiro assume
	# -Z. Sem girar, o cavalo anda de re embaixo do cavaleiro.
	_modelo.rotation_degrees.y = 180.0
	add_child(_modelo)

	_animador = _achar_animador(_modelo)
	if _animador != null and _animador.has_animation(ANIM_PARADO):
		_animador.play(ANIM_PARADO)

	# Depois de entrar na árvore: as contas de altura precisam de transformação
	# global, e antes disto ela não existe.
	call_deferred("_assentar")


## Assenta o cavalo no chão e mede a altura dele.
func _assentar() -> void:
	if _modelo == null or not _modelo.is_inside_tree():
		return

	var baixo := INF
	var alto := -INF
	var frente := Vector3(INF, 0.0, INF)
	var tras := Vector3(-INF, 0.0, -INF)
	for no in _todos(_modelo):
		if no is MeshInstance3D and (no as MeshInstance3D).mesh != null:
			var malha := no as MeshInstance3D
			var caixa := malha.global_transform * malha.mesh.get_aabb()
			baixo = minf(baixo, caixa.position.y)
			alto = maxf(alto, caixa.position.y + caixa.size.y)
			frente.x = minf(frente.x, caixa.position.x)
			frente.z = minf(frente.z, caixa.position.z)
			tras.x = maxf(tras.x, caixa.position.x + caixa.size.x)
			tras.z = maxf(tras.z, caixa.position.z + caixa.size.z)

	if baixo == INF:
		return

	# Assenta no chao.
	_modelo.position.y -= baixo - global_position.y
	altura = alto - baixo

	# E poe a sela debaixo do cavaleiro. Sem isto o cavalo nasce deslocado --
	# o pivo do modelo cai perto da garupa, e o cavaleiro fica flutuando atras
	# do bicho em vez de montado nele.
	var sela := _osso_da_sela()
	if sela != Vector3.INF:
		_modelo.position.x -= sela.x - global_position.x
		# -Z e a frente no projeto inteiro, entao +Z recua o cavalo.
		_modelo.position.z -= sela.z - global_position.z - AVANCO_DA_SELA
		_altura_da_sela = altura * FRACAO_DA_SELA
	else:
		# Sem o osso o cavalo fica deslocado, mas ainda da para montar.
		_altura_da_sela = altura * FRACAO_DA_SELA
		GameLog.warn(GameLog.Channel.WORLD, "Montaria sem osso de sela; usando a altura do meio.")
	# Confere o resultado em vez de confiar na conta: se o sinal estiver
	# invertido, o cavalo sai do lugar errado para outro lugar errado, e a unica
	# forma de saber e medindo de novo depois de mexer.
	# Confere o resultado em vez de confiar na conta: se o sinal estiver
	# invertido, o cavalo sai de um lugar errado para outro, e a unica forma de
	# saber e medindo de novo depois de mexer.
	await get_tree().process_frame
	var conferido := _osso_da_sela()
	GameLog.verbose(GameLog.Channel.WORLD,
		"Montaria: altura %.2f m, sela a %.2f m; osso da sela ficou em (%.2f, %.2f) do cavaleiro." % [
			altura, altura_da_sela(),
			conferido.x - global_position.x, conferido.z - global_position.z
		])


## Posicao do osso da sela, em mundo. `Vector3.INF` quando nenhum dos nomes
## conhecidos existe neste esqueleto.
func _osso_da_sela() -> Vector3:
	var esqueleto := _achar_esqueleto(_modelo)
	if esqueleto == null:
		return Vector3.INF
	for nome in OSSOS_DA_SELA:
		for i in esqueleto.get_bone_count():
			# `begins_with` porque o exportador numera os ossos ("spine_03_011").
			if String(esqueleto.get_bone_name(i)).begins_with(nome):
				return esqueleto.global_transform * esqueleto.get_bone_global_pose(i).origin
	return Vector3.INF


func _achar_esqueleto(no: Node) -> Skeleton3D:
	if no is Skeleton3D:
		return no as Skeleton3D
	for filho in no.get_children():
		var achado := _achar_esqueleto(filho)
		if achado != null:
			return achado
	return null


func _centro_atual() -> Vector3:
	var minimo := Vector3(INF, 0.0, INF)
	var maximo := Vector3(-INF, 0.0, -INF)
	for no in _todos(_modelo):
		if no is MeshInstance3D and (no as MeshInstance3D).mesh != null:
			var malha := no as MeshInstance3D
			var caixa := malha.global_transform * malha.mesh.get_aabb()
			minimo.x = minf(minimo.x, caixa.position.x)
			minimo.z = minf(minimo.z, caixa.position.z)
			maximo.x = maxf(maximo.x, caixa.position.x + caixa.size.x)
			maximo.z = maxf(maximo.z, caixa.position.z + caixa.size.z)
	return (minimo + maximo) * 0.5


## Altura em que o cavaleiro senta, em metros acima do chão. Medida no osso da
## espinha depois do cavalo assentado; zero enquanto isso não aconteceu.
func altura_da_sela() -> float:
	return _altura_da_sela


## `velocidade` em m/s. O cavalo anda quando o jogador anda, e no ritmo dele.
func definir_movimento(velocidade: float) -> void:
	if _animador == null:
		return

	var quer_andar := velocidade > 0.2
	if quer_andar != _andando:
		_andando = quer_andar
		var nome := ANIM_ANDANDO if quer_andar else ANIM_PARADO
		if _animador.has_animation(nome):
			_animador.play(nome, 0.25)

	if _andando:
		_animador.speed_scale = clampf(velocidade / 6.0, RITMO_MINIMO, RITMO_MAXIMO)
	else:
		_animador.speed_scale = 1.0


func _achar_animador(no: Node) -> AnimationPlayer:
	if no is AnimationPlayer:
		return no as AnimationPlayer
	for filho in no.get_children():
		var achado := _achar_animador(filho)
		if achado != null:
			return achado
	return null


func _todos(no: Node) -> Array[Node]:
	var lista: Array[Node] = []
	for filho in no.get_children():
		lista.append(filho)
		lista.append_array(_todos(filho))
	return lista
