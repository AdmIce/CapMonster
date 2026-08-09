class_name CameraRig
extends Node3D
## A câmera do mundo, em quatro enquadramentos.
##
## Trocar de enquadramento não muda regra nenhuma de jogo: só de onde se olha e
## qual é a frente do movimento. O "W" continua sendo "para longe da câmera" em
## todos eles, porque o PlayerController converte o input pela base que este nó
## devolve em `direcao_frente()`.
##
## Os quatro:
##
##   De cima          o do documento de design: ortográfica, presa aos limites
##                    do mapa, sem giro. É a visão de quem joga para caçar.
##   Terceira pessoa  atrás do ombro, girando sozinha para onde você anda.
##                    Mostra o personagem e o mascote de perto.
##   Sobre o ombro    mais perto e deslocada para o lado, com o mouse mandando
##                    na direção do olhar. É a de mirar.
##   Primeira pessoa  dentro da cabeça, mouse no comando, corpo escondido.
##
## Os dois últimos capturam o mouse. Quem decide a hora de capturar e de soltar
## é o WorldRoot, que é quem sabe se tem painel aberto — este nó só informa, em
## `usa_mouse()`, que precisa dele.
##
## As contas de limites assumem yaw = 0 (a tela aponta para -Z) e só valem no
## enquadramento de cima, o único que os usa.

## Trocou de enquadramento. Quem escuta cuida do resto: esconder o personagem,
## reenquadrar o mascote, prender ou soltar o mouse.
##
## Salvar a escolha **não** é tarefa de quem escuta: a batalha também troca o
## enquadramento, e gravar isso apagaria a preferência do jogador toda vez que
## ele entrasse numa luta. Quem salva é quem foi pedido pelo jogador — a tecla C
## e o painel de configurações.
signal modo_mudou(novo: Modo)

enum Modo { ISOMETRICA, TERCEIRA_PESSOA, OMBRO, PRIMEIRA_PESSOA }

## Tudo o que distingue um enquadramento do outro mora aqui, e não espalhado em
## `if`s pelo arquivo. Acrescentar um quinto é acrescentar uma entrada.
##
##   id            nome salvo no disco. **Texto, não o número do enum**: assim
##                 reordenar a lista um dia não embaralha a escolha de quem já
##                 estava jogando.
##   distancia     metros atrás do personagem (0 = dentro dele)
##   altura        altura do ponto para onde a câmera olha, em metros
##   lateral       deslocamento para a direita, em metros
##   pitch         inclinação inicial, em graus (negativo olha para baixo)
##   mouse         o mouse manda no olhar?
##   pitch_min/max limites da inclinação, quando o mouse manda
##   esconde       esconde o personagem (senão a câmera fica dentro da cabeça)
##   limites       prende a câmera ao retângulo do mapa
const MODOS := {
	Modo.ISOMETRICA: {
		"id": "isometrica",
		"rotulo": "De cima",
		"ajuda": "A visão do jogo. Enquadra o mapa inteiro e nunca mostra a borda dele.",
		"ortografica": true, "limites": true, "mouse": false, "esconde": false,
		"distancia": 26.0, "altura": 0.0, "lateral": 0.0, "pitch": 48.0, "fov": 38.0,
		"pitch_min": 48.0, "pitch_max": 48.0,
	},
	Modo.TERCEIRA_PESSOA: {
		"id": "terceira_pessoa",
		"rotulo": "Terceira pessoa",
		"ajuda": "Atrás do ombro, girando sozinha para onde você anda.",
		"ortografica": false, "limites": false, "mouse": false, "esconde": false,
		"distancia": 7.2, "altura": 3.0, "lateral": 0.0, "pitch": -15.0, "fov": 58.0,
		"pitch_min": -15.0, "pitch_max": -15.0,
	},
	Modo.OMBRO: {
		"id": "ombro",
		"rotulo": "Sobre o ombro",
		"ajuda": "Perto e de lado, com o mouse no comando do olhar.",
		"ortografica": false, "limites": false, "mouse": true, "esconde": false,
		# Medido na captura: a 3.1 m o personagem ocupava 45% da altura da tela e
		# tapava o que vinha pela esquerda. A 3.9 ele ocupa uns 35% e ainda é uma
		# câmera de ombro, não de terceira pessoa.
		#
		# O deslocamento lateral é o que faz a câmera ser de ombro: a 0.7 o
		# personagem ainda ficava no meio da tela, a 1.15 ele encostava na borda.
		# 1.0 tira o corpo do centro sem jogá-lo para fora do quadro. Se quiser
		# mexer, é este número e mais nenhum.
		"distancia": 3.9, "altura": 1.68, "lateral": 1.0, "pitch": -6.0, "fov": 66.0,
		"pitch_min": -55.0, "pitch_max": 40.0,
	},
	Modo.PRIMEIRA_PESSOA: {
		"id": "primeira_pessoa",
		"rotulo": "Primeira pessoa",
		"ajuda": "Pelos olhos do personagem. O mouse olha, o corpo some.",
		"ortografica": false, "limites": false, "mouse": true, "esconde": true,
		"distancia": 0.0, "altura": 1.58, "lateral": 0.0, "pitch": 0.0, "fov": 75.0,
		"pitch_min": -80.0, "pitch_max": 80.0,
	},
}

## Ordem em que a tecla C percorre os enquadramentos.
const ORDEM: Array[Modo] = [Modo.ISOMETRICA, Modo.TERCEIRA_PESSOA, Modo.OMBRO, Modo.PRIMEIRA_PESSOA]

const CHAVE_MODO := "camera_mode"
const CHAVE_SENSIBILIDADE := "camera_sensibilidade"

## Graus de giro por pixel de mouse, no ajuste do meio.
const SENSIBILIDADE_PADRAO := 0.16
const SENSIBILIDADE_MIN := 0.04
const SENSIBILIDADE_MAX := 0.45

## Velocidade com que a câmera de terceira pessoa alcança a direção da corrida.
const VELOCIDADE_GIRO := 4.5
## Abaixo desta velocidade o personagem conta como parado, e a câmera de
## terceira pessoa para de girar. Sem isto ela ficava rodando sozinha por causa
## de qualquer tremida do controlador.
const VELOCIDADE_MINIMA_PARA_GIRAR := 0.6
## A câmera nunca desce disto, para não entrar no chão ao olhar para cima.
const ALTURA_MINIMA := 0.35

@export var pitch_degrees: float = 48.0
@export var yaw_degrees: float = 0.0
@export var distance: float = 26.0
@export var orthographic_size: float = 17.0
@export var follow_speed: float = 6.5
## Empurra o enquadramento um pouco à frente da direção do movimento.
@export var look_ahead: float = 1.1
@export var use_orthographic: bool = true

var camera: Camera3D = null
var modo: Modo = Modo.ISOMETRICA

var _yaw: float = 0.0
var _pitch: float = 0.0
var _sensibilidade: float = SENSIBILIDADE_PADRAO
var _tremor: float = 0.0
var _tremor_decaimento: float = 1.0
var _rng := RandomNumberGenerator.new()
var _target: Node3D = null
var _bounds: Rect2 = Rect2()
var _bounds_enabled: bool = false
var _zoom: float = 1.0
var _desired := Vector3.ZERO


func _ready() -> void:
	_rng.randomize()
	camera = Camera3D.new()
	camera.name = "Camera3D"
	# Perto o bastante para a primeira pessoa não recortar o que está colado no
	# rosto; em 0.5 uma parede próxima virava um buraco na tela.
	camera.near = 0.08
	camera.far = 220.0
	add_child(camera)
	_sensibilidade = clampf(
		float(SaveManager.get_setting(CHAVE_SENSIBILIDADE, SENSIBILIDADE_PADRAO)),
		SENSIBILIDADE_MIN, SENSIBILIDADE_MAX
	)
	_apply_projection()
	_apply_orientation()


# --- consultas ----------------------------------------------------------------

func config() -> Dictionary:
	return MODOS[modo]


## O enquadramento atual precisa do mouse preso? Quem responde à pergunta com
## uma ação é o WorldRoot: só ele sabe se tem painel aberto na frente.
func usa_mouse() -> bool:
	return bool(config().get("mouse", false))


## O personagem deve sumir? Verdadeiro na primeira pessoa, onde a câmera está
## dentro da cabeça e o que apareceria é o miolo do modelo.
func esconde_personagem() -> bool:
	return bool(config().get("esconde", false))


## Nestes enquadramentos o corpo aponta para onde a câmera olha, mesmo parado.
## No de cima e no de terceira pessoa quem manda na direção é o movimento.
func orienta_personagem() -> bool:
	return usa_mouse()


static func modo_do_id(id: String, padrao: Modo = Modo.TERCEIRA_PESSOA) -> Modo:
	for chave in MODOS:
		if MODOS[chave]["id"] == id:
			return chave
	return padrao


func id_do_modo() -> String:
	return String(config()["id"])


# --- troca de enquadramento ---------------------------------------------------

## Devolve o modo novo, para quem chamou poder salvar.
func definir_modo(novo: Modo) -> Modo:
	modo = novo
	var c := config()
	_pitch = float(c["pitch"])
	_apply_projection()

	if modo == Modo.ISOMETRICA:
		_apply_orientation()
		if _target != null and is_instance_valid(_target):
			global_position = _clamped(_target.global_position)
	elif _target != null and is_instance_valid(_target):
		# Entrando num enquadramento de trás: começa olhando para onde o
		# personagem já está virado, senão a troca dá um giro brusco de 180°.
		_yaw = _target.rotation.y
		global_position = _target.global_position

	modo_mudou.emit(modo)
	return modo


## Percorre os enquadramentos em ordem. É o que a tecla C faz.
func alternar_modo() -> Modo:
	var indice := ORDEM.find(modo)
	return definir_modo(ORDEM[(indice + 1) % ORDEM.size()])


func definir_sensibilidade(valor: float) -> void:
	_sensibilidade = clampf(valor, SENSIBILIDADE_MIN, SENSIBILIDADE_MAX)


## Movimento do mouse, em pixels. Ignorado nos enquadramentos que não usam mouse.
func girar_com_mouse(relativo: Vector2) -> void:
	if not usa_mouse():
		return
	var c := config()
	_yaw -= deg_to_rad(relativo.x * _sensibilidade)
	_pitch = clampf(_pitch - relativo.y * _sensibilidade, float(c["pitch_min"]), float(c["pitch_max"]))


# --- projeção e enquadramento -------------------------------------------------

## Respeitar o modo aqui não é detalhe: sem isso, mexer no zoom em terceira
## pessoa trocava a câmera para ortográfica **sem sair de trás do personagem** —
## o mundo virava uma placa achatada com vazio em volta.
func _apply_projection() -> void:
	var c := config()
	if not bool(c["ortografica"]):
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		camera.fov = float(c["fov"])
		return
	if use_orthographic:
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		# size é a altura enquadrada: zoom maior = size menor = mais perto.
		camera.size = orthographic_size / maxf(0.35, _zoom)
	else:
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		camera.fov = float(c["fov"])


func _apply_orientation() -> void:
	camera.rotation_degrees = Vector3(-pitch_degrees, yaw_degrees, 0.0)
	camera.position = camera.transform.basis.z * distance


## Sacode a câmera. Usado em golpe forte, crítico e entrada de chefe.
## O deslocamento é aplicado na câmera filha, não no rig, para não brigar com o
## seguimento nem com o clamp de limites.
func tremer(intensidade: float = 0.18, duracao: float = 0.25) -> void:
	_tremor = maxf(_tremor, intensidade)
	_tremor_decaimento = maxf(0.05, duracao)


func _aplicar_tremor(delta: float) -> void:
	if _tremor <= 0.0001:
		if camera.h_offset != 0.0 or camera.v_offset != 0.0:
			camera.h_offset = 0.0
			camera.v_offset = 0.0
		return
	_tremor = maxf(0.0, _tremor - delta / _tremor_decaimento * _tremor)
	camera.h_offset = _rng.randf_range(-_tremor, _tremor)
	camera.v_offset = _rng.randf_range(-_tremor, _tremor)


func set_zoom(zoom: float) -> void:
	_zoom = clampf(zoom, 0.6, 1.8)
	_apply_projection()


func follow(target: Node3D, snap: bool = true) -> void:
	_target = target
	if snap and target != null:
		_desired = target.global_position
		global_position = _clamped(_desired)


## Prende o centro da câmera para o quadro nunca sair do retângulo do mapa.
func set_bounds(min_x: float, max_x: float, min_z: float, max_z: float) -> void:
	_bounds = Rect2(min_x, min_z, max_x - min_x, max_z - min_z)
	_bounds_enabled = _bounds.size.x > 0.0 and _bounds.size.y > 0.0


func clear_bounds() -> void:
	_bounds_enabled = false


## Frente da câmera projetada no chão. O movimento do jogador é convertido por
## esta base, então "W" sempre é "para longe da câmera" em todos os modos.
func direcao_frente() -> Vector3:
	if modo == Modo.ISOMETRICA:
		return Vector3.FORWARD
	return Vector3(-sin(_yaw), 0.0, -cos(_yaw)).normalized()


func direcao_direita() -> Vector3:
	var frente := direcao_frente()
	return Vector3(-frente.z, 0.0, frente.x)


# --- loop ---------------------------------------------------------------------

func _process(delta: float) -> void:
	_aplicar_tremor(delta)
	if _target == null or not is_instance_valid(_target):
		return
	if modo == Modo.ISOMETRICA:
		_seguir_de_cima(delta)
		return
	_seguir_atras(delta)


func _seguir_de_cima(delta: float) -> void:
	var lead := Vector3.ZERO
	if _target is CharacterBody3D:
		var velocity: Vector3 = (_target as CharacterBody3D).velocity
		lead = Vector3(velocity.x, 0.0, velocity.z).normalized() * look_ahead * minf(1.0, velocity.length() / 6.0)
	_desired = _target.global_position + lead
	var goal := _clamped(_desired)
	global_position = global_position.lerp(goal, clampf(follow_speed * delta, 0.0, 1.0))


## Vale para os três enquadramentos de trás. Sem clamp de limites: aqui mostrar
## um pedaço de fora do mapa incomoda menos do que a câmera travar enquanto o
## jogador anda.
func _seguir_atras(delta: float) -> void:
	# A primeira pessoa não tem atraso: a câmera está **dentro** da cabeça, e
	# qualquer atraso faria o cenário deslizar a cada passo, que é o caminho
	# mais curto para embrulhar o estômago de quem joga.
	if modo == Modo.PRIMEIRA_PESSOA:
		global_position = _target.global_position
	else:
		global_position = global_position.lerp(_target.global_position, clampf(12.0 * delta, 0.0, 1.0))

	# Com o mouse no comando, o giro já veio de `girar_com_mouse`. Sem ele, a
	# câmera alcança sozinha a direção da corrida.
	if not usa_mouse() and _target is CharacterBody3D:
		var velocidade: Vector3 = (_target as CharacterBody3D).velocity
		if Vector2(velocidade.x, velocidade.z).length() > VELOCIDADE_MINIMA_PARA_GIRAR:
			_yaw = lerp_angle(_yaw, _target.rotation.y, VELOCIDADE_GIRO * delta)

	var c := config()
	# Em terceira pessoa o zoom mexe na distância, não no `size` (que só existe
	# na ortográfica). Assim o slider continua fazendo sentido em todos os modos.
	var perto := clampf(_zoom, 0.6, 1.8)
	var distancia := float(c["distancia"]) / perto
	var altura := float(c["altura"])
	var p := deg_to_rad(_pitch)

	# Órbita em volta de um ponto à altura dos olhos: olhar para baixo sobe a
	# câmera, olhar para cima abaixa. Aplicar o pitch só na rotação, sem mexer
	# na posição, faria a câmera apontar para o céu de trás do personagem.
	var atras := Vector3(sin(_yaw), 0.0, cos(_yaw))
	var direita := Vector3(cos(_yaw), 0.0, -sin(_yaw))
	var alvo := Vector3(0.0, altura, 0.0) \
		+ atras * distancia * cos(p) \
		+ Vector3(0.0, -distancia * sin(p), 0.0) \
		+ direita * float(c["lateral"])
	# Em mundo, e não em local: o rig está na altura do personagem, que voa.
	alvo.y = maxf(alvo.y, ALTURA_MINIMA - global_position.y)

	camera.position = alvo
	camera.rotation_degrees = Vector3(_pitch, rad_to_deg(_yaw), 0.0)


func _clamped(position: Vector3) -> Vector3:
	# A altura passa direto: o mundo é plano, mas o voo tira o personagem do
	# plano, e uma câmera presa em y = 0 o deixaria sair de quadro por cima.
	# Os limites são só de x e z, que é o retângulo do mapa.
	var result := Vector3(position.x, position.y, position.z)
	if not _bounds_enabled or modo != Modo.ISOMETRICA:
		return result
	var half := _visible_half_extents()
	var min_x := _bounds.position.x + half.x
	var max_x := _bounds.position.x + _bounds.size.x - half.x
	var min_z := _bounds.position.y + half.y
	var max_z := _bounds.position.y + _bounds.size.y - half.y
	# Mapa mais estreito que a vista: centraliza em vez de prender.
	result.x = clampf(result.x, min_x, max_x) if min_x <= max_x else _bounds.position.x + _bounds.size.x * 0.5
	result.z = clampf(result.z, min_z, max_z) if min_z <= max_z else _bounds.position.y + _bounds.size.y * 0.5
	return result


## Metade do retângulo de mundo que a câmera enxerga no chão.
func _visible_half_extents() -> Vector2:
	var viewport := get_viewport()
	var aspect := 16.0 / 9.0
	if viewport != null:
		var rect := viewport.get_visible_rect().size
		if rect.y > 0.0:
			aspect = rect.x / rect.y

	var size := camera.size if use_orthographic else 2.0 * distance * tan(deg_to_rad(camera.fov) * 0.5)
	var half_width := size * aspect * 0.5
	# Câmera inclinada enxerga mais longe em Z do que a altura do quadro sugere.
	var sin_pitch := maxf(0.2, sin(deg_to_rad(pitch_degrees)))
	var half_depth := size * 0.5 / sin_pitch
	return Vector2(half_width, half_depth)
