class_name DamageCalculator
extends RefCounted
## Todas as contas de combate num lugar só.
##
## Os números saem de data/progression.json, então balancear é edição de JSON.
## Nenhum ator de batalha inventa fórmula própria: todos passam por aqui.
##
## Fórmula do dano:
##   base       = ataque * potência da habilidade
##   mitigação  = amortecimento / (amortecimento + defesa)
##   dano       = base * mitigação * elemento * variação  (× crítico)
##   final      = máximo(dano_mínimo, arredondado)

## Potência do ataque básico, que não é uma habilidade e por isso não vem do JSON
## de skills. Deixa o básico como dano de manutenção e a habilidade como pico.
const BASIC_ATTACK_POWER := 0.8

## Intervalo entre ataques básicos: velocidade de referência dividido pela
## velocidade da criatura, preso numa faixa para ninguém ficar parado nem virar
## metralhadora.
const BASE_ATTACK_INTERVAL := 2.6
const REFERENCE_SPEED := 18.0
const MIN_ATTACK_INTERVAL := 0.75
const MAX_ATTACK_INTERVAL := 3.2


class Resultado extends RefCounted:
	var amount: int = 0
	var critical: bool = false
	var element_multiplier: float = 1.0

	func is_effective() -> bool:
		return element_multiplier > 1.01

	func is_resisted() -> bool:
		return element_multiplier < 0.99


static func attack_interval(speed: int) -> float:
	if speed <= 0:
		return MAX_ATTACK_INTERVAL
	return clampf(
		BASE_ATTACK_INTERVAL * (REFERENCE_SPEED / float(speed)),
		MIN_ATTACK_INTERVAL,
		MAX_ATTACK_INTERVAL
	)


## `power` é a potência da habilidade; use BASIC_ATTACK_POWER para o golpe básico.
static func compute(
	attack: int,
	defense: int,
	power: float,
	attacker_element: String,
	defender_element: String,
	rng: RandomNumberGenerator = null
) -> Resultado:
	var curve := DataManager.progression
	var resultado := Resultado.new()

	var base := float(attack) * maxf(0.05, power)
	var softening := maxf(1.0, curve.defense_softening)
	var mitigation := softening / (softening + maxf(0.0, float(defense)))
	resultado.element_multiplier = DataManager.element_multiplier(attacker_element, defender_element)

	var variation := curve.random_variation
	var roll := rng.randf() if rng != null else randf()
	var jitter := 1.0 + lerpf(-variation, variation, roll)

	var damage := base * mitigation * resultado.element_multiplier * jitter

	var crit_roll := rng.randf() if rng != null else randf()
	if crit_roll < curve.critical_chance:
		resultado.critical = true
		damage *= curve.critical_multiplier

	resultado.amount = maxi(curve.minimum_damage, int(round(damage)))
	return resultado


## Cura de uma habilidade: `power` é a fração da vida máxima do alvo.
static func compute_heal(target_max_hp: int, power: float) -> int:
	return maxi(1, int(round(float(target_max_hp) * maxf(0.0, power))))


## XP que um grupo derrotado entrega, já dividido entre os sobreviventes.
static func split_xp(total: int, receivers: int) -> int:
	if receivers <= 0:
		return 0
	# Divisão com piso generoso: equipe cheia não é punida por ter equipe cheia.
	return maxi(1, int(round(float(total) * (0.6 + 0.4 / float(receivers)) / float(receivers))))
