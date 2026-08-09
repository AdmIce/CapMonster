class_name BattleActor
extends Node3D
## Um combatente em campo: o modelo, a barra de vida, os temporizadores e a
## máquina de estados.
##
##   IDLE -> TARGETING -> ATTACKING / CASTING -> IDLE
##   qualquer estado -> HIT -> volta
##   vida 0 -> DEAD
##
## O ator cuida de quando quer agir e de como isso parece na tela. Quem escolhe
## alvo e aplica dano é o BattleController - assim a regra fica num lugar só.

signal quer_atacar(ator: BattleActor)
signal quer_usar_habilidade(ator: BattleActor, skill_id: String)
signal morreu(ator: BattleActor)
signal enfureceu(ator: BattleActor)

enum State { IDLE, TARGETING, ATTACKING, CASTING, HIT, DEAD }

const DURACAO_INVESTIDA := 0.26
const DISTANCIA_INVESTIDA := 0.9
const DURACAO_HIT := 0.18

var data: CreatureData = null
var is_ally: bool = false
var home: Vector3 = Vector3.ZERO
## Habilidades manuais não disparam sozinhas: são os botões do jogador.
var skills_automaticas: bool = true

var _state: State = State.IDLE
var _modelo: Node3D = null
var _animador: CreatureAnimator = null
var _barra: HealthBar3D = null
var _ativo: bool = false

var _intervalo_ataque: float = 2.0
var _tempo_ataque: float = 0.0
var _recargas: Dictionary = {}          ## skill_id -> segundos restantes
var _modificadores: Array = []          ## { stat, amount, restante }
var _tempo_estado: float = 0.0
var _enfurecido: bool = false
var _rng := RandomNumberGenerator.new()

## Segunda mecânica dos chefes (a primeira é a habilidade exclusiva): abaixo
## desta fração de vida ele se enfurece uma vez, ganhando ataque e velocidade.
const CHEFE_LIMIAR_FURIA := 0.5
const CHEFE_BONUS_ATAQUE := 0.4
const CHEFE_BONUS_VELOCIDADE := 0.3


static func create(criatura: CreatureData, aliado: bool, posicao: Vector3) -> BattleActor:
	var ator := BattleActor.new()
	ator.data = criatura
	ator.is_ally = aliado
	ator.home = posicao
	ator.position = posicao
	ator.name = "Ator_%s" % criatura.uid
	return ator


func _ready() -> void:
	_rng.randomize()
	var especie := data.species()

	_modelo = CreatureModelBuilder.build(especie)
	add_child(_modelo)
	# Quem vira o ator para o inimigo é o BattleController, no nó do ator - o
	# modelo é do animador, e girar os dois brigaria pelo mesmo transform.
	var tamanho := especie.visual_size() if especie != null else 1.0
	_animador = CreatureAnimator.new(_modelo, clampf(1.2 / maxf(0.5, tamanho), 0.5, 1.3))

	var altura := 1.5 * (especie.visual_size() if especie != null else 1.0)
	_barra = HealthBar3D.new(is_ally)
	_barra.position = Vector3(0, altura, 0)
	add_child(_barra)
	_barra.configurar(data.display_name(), data.level)
	_barra.definir_proporcao(data.hp_ratio(), true)

	_intervalo_ataque = DamageCalculator.attack_interval(data.speed())
	# Primeiro golpe sai com atraso aleatório, senão todo mundo bate no mesmo frame.
	_tempo_ataque = _rng.randf_range(0.25, _intervalo_ataque)

	for skill_id in data.skill_ids():
		_recargas[skill_id] = _rng.randf_range(1.0, 3.0)


func iniciar() -> void:
	_ativo = true
	_entrar(State.IDLE)


func encerrar() -> void:
	_ativo = false


func esta_vivo() -> bool:
	return data != null and data.is_alive() and _state != State.DEAD


func estado() -> State:
	return _state


func e_chefe() -> bool:
	var especie := data.species() if data != null else null
	return especie != null and especie.is_boss()


func esta_enfurecido() -> bool:
	return _enfurecido


## Duração longa de propósito: é uma virada de fase, não um buff temporário.
func _enfurecer() -> void:
	_enfurecido = true
	aplicar_modificador("attack", CHEFE_BONUS_ATAQUE, 9999.0)
	aplicar_modificador("speed", CHEFE_BONUS_VELOCIDADE, 9999.0)
	# Mexer na escala aqui brigaria com o animador; a fúria se lê pela passada
	# mais agitada e pelo efeito que o BattleController dispara.
	if _animador != null:
		_animador.escala_do_efeito *= 1.6
	GameLog.info(GameLog.Channel.BATTLE, "%s se enfureceu." % data.display_name())
	enfureceu.emit(self)


func altura_do_topo() -> float:
	var especie := data.species()
	return 1.7 * (especie.visual_size() if especie != null else 1.0)


# --- atributos com modificadores ----------------------------------------------

func _bonus(stat: String) -> float:
	var total := 0.0
	for modificador in _modificadores:
		if modificador["stat"] == stat:
			total += float(modificador["amount"])
	return total


func ataque_efetivo() -> int:
	return maxi(1, int(round(float(data.attack()) * (1.0 + _bonus("attack")))))


func defesa_efetiva() -> int:
	return maxi(0, int(round(float(data.defense()) * (1.0 + _bonus("defense")))))


func velocidade_efetiva() -> int:
	return maxi(1, int(round(float(data.speed()) * (1.0 + _bonus("speed")))))


func aplicar_modificador(stat: String, amount: float, duracao: float) -> void:
	_modificadores.append({ "stat": stat, "amount": amount, "restante": duracao })
	_intervalo_ataque = DamageCalculator.attack_interval(velocidade_efetiva())


# --- recargas -----------------------------------------------------------------

func recarga_restante(skill_id: String) -> float:
	return float(_recargas.get(skill_id, 0.0))


func habilidade_pronta(skill_id: String) -> bool:
	return esta_vivo() and recarga_restante(skill_id) <= 0.0


func consumir_recarga(skill_id: String) -> void:
	var skill := DataManager.get_skill(skill_id)
	_recargas[skill_id] = float(skill.get("cooldown", 8.0))


# --- ciclo --------------------------------------------------------------------

func _process(delta: float) -> void:
	if not _ativo:
		return

	_tempo_estado -= delta
	for skill_id in _recargas.keys():
		_recargas[skill_id] = maxf(0.0, float(_recargas[skill_id]) - delta)

	var expirou := false
	for i in range(_modificadores.size() - 1, -1, -1):
		_modificadores[i]["restante"] = float(_modificadores[i]["restante"]) - delta
		if _modificadores[i]["restante"] <= 0.0:
			_modificadores.remove_at(i)
			expirou = true
	if expirou:
		_intervalo_ataque = DamageCalculator.attack_interval(velocidade_efetiva())

	if _barra != null:
		_barra.definir_proporcao(data.hp_ratio())

	if not esta_vivo():
		if _state != State.DEAD:
			_entrar(State.DEAD)
		return

	if e_chefe() and not _enfurecido and data.hp_ratio() <= CHEFE_LIMIAR_FURIA:
		_enfurecer()

	match _state:
		State.HIT:
			if _tempo_estado <= 0.0:
				_entrar(State.IDLE)
		State.ATTACKING, State.CASTING:
			if _tempo_estado <= 0.0:
				_entrar(State.IDLE)
		_:
			_tempo_ataque -= delta
			_pensar()

	_animar_ocioso(delta)


func _pensar() -> void:
	if skills_automaticas:
		for skill_id in data.skill_ids():
			if habilidade_pronta(skill_id):
				_entrar(State.TARGETING)
				quer_usar_habilidade.emit(self, skill_id)
				return
	if _tempo_ataque <= 0.0:
		_tempo_ataque = _intervalo_ataque
		_entrar(State.TARGETING)
		quer_atacar.emit(self)


func _entrar(novo: State) -> void:
	_state = novo
	match novo:
		State.ATTACKING:
			_tempo_estado = DURACAO_INVESTIDA * 2.0
		State.CASTING:
			_tempo_estado = DURACAO_INVESTIDA * 2.4
		State.HIT:
			_tempo_estado = DURACAO_HIT
		State.DEAD:
			_tocar_morte()


# --- animação -----------------------------------------------------------------

## Em campo a criatura fica em guarda: nunca parada de todo. Passa um ritmo
## pequeno e constante para o animador, em vez de zero, senão vira estátua.
func _animar_ocioso(delta: float) -> void:
	if _animador == null or _state == State.DEAD:
		return
	if _state in [State.ATTACKING, State.CASTING]:
		return
	_animador.atualizar(delta, 0.22)


func tocar_ataque(alvo: Vector3) -> void:
	if _animador == null:
		return
	_entrar(State.ATTACKING)
	_animador.tocar_ataque(alvo - global_position, DISTANCIA_INVESTIDA)


func tocar_conjuracao(cor: Color) -> void:
	if _animador == null:
		return
	_entrar(State.CASTING)
	_animador.tocar_conjuracao()

	var brilho := OmniLight3D.new()
	brilho.light_color = cor
	brilho.light_energy = 3.2
	brilho.omni_range = 5.0
	brilho.position = Vector3(0, 0.9, 0)
	add_child(brilho)
	var apagar := create_tween()
	apagar.tween_property(brilho, "light_energy", 0.0, 0.5)
	apagar.tween_callback(brilho.queue_free)


func tocar_dano() -> void:
	if _animador == null or _state == State.DEAD:
		return
	_entrar(State.HIT)
	_animador.tocar_dano()


func _tocar_morte() -> void:
	if _barra != null:
		_barra.visible = false
	if _animador != null:
		_animador.tocar_morte()
	AudioManager.tocar(&"abate")
	morreu.emit(self)
