class_name FloatingText3D
extends Label3D
## Número de dano / cura que sobe e some.
##
## É o feedback mais importante do combate: sem ele o auto-battle vira uma
## barra que encolhe sozinha. Crítico sai maior e dourado, resistido sai menor e
## acinzentado, cura sai verde com "+".

const SUBIDA := 1.5
const DURACAO := 0.95

const COR_DANO := Color("#FFD98A")
const COR_CRITICO := Color("#FF8A3C")
const COR_EFETIVO := Color("#FF6B4A")
const COR_RESISTIDO := Color("#9FB3C8")
const COR_CURA := Color("#7FD98A")
const COR_AVISO := Color("#CFE3EC")


static func dano(resultado: DamageCalculator.Resultado) -> FloatingText3D:
	var texto := FloatingText3D.new()
	texto.text = str(resultado.amount)
	texto.font_size = 52
	if resultado.critical:
		texto.text = "%d!" % resultado.amount
		texto.modulate = COR_CRITICO
		texto.font_size = 72
	elif resultado.is_effective():
		texto.modulate = COR_EFETIVO
		texto.font_size = 62
	elif resultado.is_resisted():
		texto.modulate = COR_RESISTIDO
		texto.font_size = 42
	else:
		texto.modulate = COR_DANO
	return texto


static func cura(quantidade: int) -> FloatingText3D:
	var texto := FloatingText3D.new()
	texto.text = "+%d" % quantidade
	texto.font_size = 52
	texto.modulate = COR_CURA
	return texto


static func aviso(mensagem: String) -> FloatingText3D:
	var texto := FloatingText3D.new()
	texto.text = mensagem
	texto.font_size = 40
	texto.modulate = COR_AVISO
	return texto


func _ready() -> void:
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	no_depth_test = true
	# Mesma razão da barra de vida: sem fixed_size o número acompanha a escala do
	# mundo em vez de virar um letreiro.
	pixel_size = 0.006
	outline_size = 10
	outline_modulate = Color(0, 0, 0, 0.9)
	render_priority = 20

	# Espalha um pouco no eixo X para dois acertos seguidos não se sobreporem.
	position.x += randf_range(-0.28, 0.28)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "position:y", position.y + SUBIDA, DURACAO).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 0.0, DURACAO).set_delay(DURACAO * 0.35)
	tween.set_parallel(false)
	tween.tween_callback(queue_free)


## Coloca o texto na cena, acima de `origem`.
static func mostrar(pai: Node3D, origem: Vector3, texto: FloatingText3D) -> void:
	texto.position = origem
	pai.add_child(texto)
