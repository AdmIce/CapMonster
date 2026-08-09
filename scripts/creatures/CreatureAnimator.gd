class_name CreatureAnimator
extends RefCounted
## Animação procedural das criaturas, num lugar só.
##
## Nenhum modelo do projeto tem esqueleto - nem os placeholders montados com
## primitivas, nem os `.obj`/`.glb` importados, que são malha estática. Sem osso
## não existe clipe de animação, então o movimento é feito no transform:
##
##   parado  - respira (escala) e balança de leve
##   andando - sobe-desde a cada passo, gingado lateral, inclina para a frente
##             e achata na aterrissagem
##   atacar  - investida na direção do alvo e volta
##   dano    - tranco curto para trás
##
## Lido junto, isso lê como andar. Quando existir modelo rigado, esta classe é
## trocada por um AnimationTree e quem chama continua chamando `andar()`.
##
## Usada por CompanionCreature, WildCreature e BattleActor - antes cada um tinha
## seu próprio meio-sobe-desce, e por isso as criaturas pareciam estátuas.

const BALANCO_PARADO := 1.4
const RITMO_BASE := 2.4
const RITMO_POR_VELOCIDADE := 1.6

var modelo: Node3D = null
## Multiplica a amplitude toda. Criatura grande precisa de menos para ler igual.
var escala_do_efeito: float = 1.0

var _fase: float = 0.0
var _escala_base := Vector3.ONE
var _ocupado_ate: float = 0.0


func _init(alvo: Node3D, forca: float = 1.0) -> void:
	modelo = alvo
	escala_do_efeito = forca
	if modelo != null:
		_escala_base = modelo.scale


func valido() -> bool:
	return modelo != null and is_instance_valid(modelo)


## `ritmo` é 0 parado e 1 na velocidade máxima daquele contexto.
func atualizar(delta: float, ritmo: float) -> void:
	if not valido():
		return
	# Enquanto uma animação de ação está tocando, a passada não mexe no modelo.
	if _ocupado_ate > 0.0:
		_ocupado_ate -= delta
		return

	var andando := ritmo > 0.06
	if andando:
		_andar(delta, clampf(ritmo, 0.0, 1.0))
	else:
		_parado(delta)


func _andar(delta: float, ritmo: float) -> void:
	_fase += delta * (RITMO_BASE + ritmo * RITMO_POR_VELOCIDADE) * TAU * 0.5
	var ciclo := sin(_fase)
	var meio := absf(ciclo)
	var f := escala_do_efeito

	modelo.position.y = meio * (0.04 + ritmo * 0.16) * f
	modelo.rotation_degrees.z = ciclo * (1.6 + ritmo * 5.0) * f
	modelo.rotation_degrees.y = sin(_fase * 0.5) * ritmo * 6.0 * f
	modelo.rotation_degrees.x = -ritmo * 7.0 * f

	# Achata quando o pé encosta: é o que dá peso ao passo sem osso nenhum.
	var achatamento := (1.0 - meio) * ritmo * 0.09 * f
	modelo.scale = Vector3(
		_escala_base.x * (1.0 + achatamento),
		_escala_base.y * (1.0 - achatamento),
		_escala_base.z * (1.0 + achatamento)
	)


func _parado(delta: float) -> void:
	_fase += delta * BALANCO_PARADO
	var f := escala_do_efeito
	modelo.position.y = absf(sin(_fase)) * 0.025 * f
	modelo.rotation_degrees.z = sin(_fase * 0.7) * 1.2 * f
	modelo.rotation_degrees.x = 0.0
	modelo.rotation_degrees.y = sin(_fase * 0.35) * 1.5 * f
	var respiro := 1.0 + sin(_fase * 0.9) * 0.014 * f
	modelo.scale = Vector3(_escala_base.x, _escala_base.y * respiro, _escala_base.z)


## Investida curta na direção do alvo. Devolve a duração para quem quiser esperar.
func tocar_ataque(direcao: Vector3, distancia: float = 0.9) -> float:
	if not valido():
		return 0.0
	var plana := Vector3(direcao.x, 0.0, direcao.z)
	if plana.length() < 0.01:
		plana = Vector3.FORWARD
	var deslocamento := plana.normalized() * distancia

	var ida := 0.16
	var volta := 0.22
	_ocupado_ate = ida + volta

	var tween := modelo.create_tween()
	tween.tween_property(modelo, "position", deslocamento, ida).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(modelo, "position", Vector3.ZERO, volta)
	return _ocupado_ate


func tocar_dano() -> void:
	if not valido():
		return
	_ocupado_ate = 0.18
	var tween := modelo.create_tween()
	tween.tween_property(modelo, "rotation_degrees:x", 14.0, 0.06)
	tween.tween_property(modelo, "rotation_degrees:x", 0.0, 0.12)


func tocar_conjuracao() -> float:
	if not valido():
		return 0.0
	_ocupado_ate = 0.46
	var tween := modelo.create_tween()
	tween.tween_property(modelo, "scale", _escala_base * 1.16, 0.16).set_trans(Tween.TRANS_SINE)
	tween.tween_property(modelo, "scale", _escala_base, 0.3)
	return _ocupado_ate


func tocar_morte() -> void:
	if not valido():
		return
	_ocupado_ate = 999.0
	var tween := modelo.create_tween()
	tween.set_parallel(true)
	tween.tween_property(modelo, "rotation_degrees:z", 82.0, 0.4).set_trans(Tween.TRANS_BACK)
	tween.tween_property(modelo, "position:y", -0.25, 0.4)
	tween.tween_property(modelo, "scale", _escala_base * 0.85, 0.4)
