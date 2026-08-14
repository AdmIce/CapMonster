class_name Cena
extends Node
## Encena uma sequência sem o jogador no controle.
##
## A abertura do quarto é a primeira: o personagem acorda, vai até a televisão
## sozinho, tenta desligar, desiste e volta para a cama. Enquanto isso o teclado
## não faz nada — é cinema, não jogo.
##
## O roteiro mora no maps.json, não aqui. Mudar uma fala, um caminho ou a ordem
## dos passos é edição de JSON; este script só sabe executar os tipos de passo.
## Foi assim que o resto do projeto foi feito e é o que permite escrever a
## segunda cena sem tocar em código.
##
## Passos que existem:
##
##   andar   {"para": [x, z]}                caminha até o ponto e espera chegar
##   olhar   {"para": [x, z]}                vira a câmera e o corpo para o ponto
##   falar   {"quem": "...", "linhas": [..], "segundos_por_linha": 2.5}
##           abre o diálogo; com `segundos_por_linha` ele corre sozinho, sem
##           `segundos_por_linha` espera a tecla
##   esperar {"segundos": 1.2}               pausa
##   ir      {"cena": "character_select"}    troca de cena e encerra
##
## O passo `andar` desiste depois de `SEGUNDOS_MAXIMOS_ANDANDO`. Sem isso, um
## ponto inalcançável (mobília no caminho, coordenada errada no JSON) travaria o
## jogador para sempre numa cena sem controle e sem saída.

signal terminou()

## Quão perto do ponto conta como "chegou". Frouxo de propósito: o personagem
## desliza ao parar, e exigir precisão faria ele ficar tremendo em volta do alvo.
const DISTANCIA_DE_CHEGADA := 0.45
const SEGUNDOS_MAXIMOS_ANDANDO := 12.0

## Fracao do passo normal durante a cena. A 0,45 a travessia do quarto passa de
## meio segundo para pouco mais de um -- tempo de a camera contar alguma coisa.
const VELOCIDADE_DA_CENA := 0.45

var _jogador: PlayerController = null
var _camera: CameraRig = null
var _dialogo: DialoguePanel = null
var _passos: Array = []
var _rodando := false
var _mascara_guardada: int = 0


static func criar(passos: Array) -> Cena:
	var no := Cena.new()
	no.name = "Cena"
	no._passos = passos.duplicate(true)
	return no


func encenar(jogador: PlayerController, camera: CameraRig, dialogo: DialoguePanel) -> void:
	if _rodando or _passos.is_empty():
		return
	_rodando = true
	_jogador = jogador
	_camera = camera
	_dialogo = dialogo

	# O teclado sai de cena, mas o modo automático entra: é ele que move o
	# personagem, pelo mesmo caminho que o piloto automático usa.
	_jogador.input_enabled = false
	_jogador.auto_enabled = true
	_jogador.auto_correndo = false
	_jogador.auto_velocidade = VELOCIDADE_DA_CENA

	# A colisao sai durante a cena.
	#
	# O caminho aqui e roteirizado, entao parede e movel so tem como atrapalhar:
	# medido, o personagem acordava em cima da cama (que e solida, porque a
	# colisao do quarto vem das proprias malhas) e nao saia do lugar -- 12 s
	# empurrando contra o colchao. Fora da cena a colisao volta, e ai ela serve.
	_mascara_guardada = _jogador.collision_mask
	_jogador.collision_mask = 0

	for passo in _passos:
		if not is_instance_valid(_jogador):
			return
		await _executar(passo)

	_encerrar()


func _executar(passo: Dictionary) -> void:
	match String(passo.get("tipo", "")):
		"andar":
			await _andar(_ponto(passo.get("para", [0, 0])))
		"olhar":
			await _olhar(_ponto(passo.get("para", [0, 0])), float(passo.get("segundos", 0.8)))
		"falar":
			await _falar(
				String(passo.get("quem", "")),
				passo.get("linhas", []),
				float(passo.get("segundos_por_linha", 0.0))
			)
		"esperar":
			await get_tree().create_timer(float(passo.get("segundos", 1.0))).timeout
		"ir":
			_ir(String(passo.get("cena", "character_select")))
		_:
			GameLog.warn(GameLog.Channel.WORLD, "Cena: passo desconhecido '%s'." % passo.get("tipo", ""))


func _andar(destino: Vector2) -> void:
	var partiu := _jogador.plane_position()
	var gasto := 0.0
	while gasto < SEGUNDOS_MAXIMOS_ANDANDO:
		if not is_instance_valid(_jogador):
			return
		var aqui := _jogador.plane_position()
		var resto := destino - aqui
		if resto.length() <= DISTANCIA_DE_CHEGADA:
			break
		_jogador.auto_input = resto.normalized()
		# A câmera acompanha o caminho: em primeira pessoa é ela que conta a
		# cena, e uma caminhada olhando para o lado errado não conta nada.
		_apontar_camera(resto)
		gasto += get_process_delta_time()
		await get_tree().process_frame

	_jogador.auto_input = Vector2.ZERO
	if gasto < SEGUNDOS_MAXIMOS_ANDANDO:
		GameLog.verbose(GameLog.Channel.WORLD,
			"Cena: cheguei em (%.1f, %.1f) em %.1f s." % [destino.x, destino.y, gasto])
	if gasto >= SEGUNDOS_MAXIMOS_ANDANDO:
		# Quanto ele andou separa "esbarrou em algo" de "nao saiu do lugar", e as
		# duas coisas pedem consertos diferentes.
		var andou := _jogador.plane_position().distance_to(partiu)
		GameLog.warn(GameLog.Channel.WORLD,
			"Cena: não cheguei em (%.1f, %.1f) em %.0f s (andei %.2f m); seguindo assim mesmo." % [
				destino.x, destino.y, SEGUNDOS_MAXIMOS_ANDANDO, andou
			])


func _olhar(alvo: Vector2, segundos: float) -> void:
	var gasto := 0.0
	while gasto < segundos:
		if not is_instance_valid(_jogador):
			return
		_apontar_camera(alvo - _jogador.plane_position())
		gasto += get_process_delta_time()
		await get_tree().process_frame


## Com `segundos_por_linha`, a fala corre sozinha -- e o que faz a abertura ser
## cinema em vez de um diálogo que espera clique. Sem o campo, espera a tecla,
## que ainda é o certo para conversa com NPC.
func _falar(quem: String, linhas: Array, segundos_por_linha: float) -> void:
	if _dialogo == null or linhas.is_empty():
		return
	_dialogo.open(quem, linhas)

	if segundos_por_linha <= 0.0:
		await _dialogo.finished
		return

	# Uma passada por linha, e uma a mais para fechar a última.
	for i in linhas.size():
		await get_tree().create_timer(segundos_por_linha).timeout
		if _dialogo == null or not is_instance_valid(_dialogo) or not _dialogo.is_open():
			return
		_dialogo.avancar_linha()


func _ir(cena: String) -> void:
	GameManager.save_now("fim da cena")
	match cena:
		"character_select":
			SceneFlow.goto_character_select()
		"character_creation":
			SceneFlow.goto_character_creation()
		"world":
			SceneFlow.goto_world()
		_:
			GameLog.warn(GameLog.Channel.WORLD, "Cena: destino desconhecido '%s'." % cena)


func _apontar_camera(direcao: Vector2) -> void:
	if _camera == null or not is_instance_valid(_camera) or direcao.length_squared() < 0.0001:
		return
	_camera.olhar_para_direcao(direcao)


func _ponto(bruto: Variant) -> Vector2:
	var lista: Array = bruto if bruto is Array else [0, 0]
	if lista.size() < 2:
		return Vector2.ZERO
	return Vector2(float(lista[0]), float(lista[1]))


func _encerrar() -> void:
	_rodando = false
	if is_instance_valid(_jogador):
		_jogador.auto_enabled = false
		_jogador.auto_input = Vector2.ZERO
		_jogador.input_enabled = true
		_jogador.auto_correndo = true
		_jogador.auto_velocidade = 1.0
		_jogador.collision_mask = _mascara_guardada
	terminou.emit()
