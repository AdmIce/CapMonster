class_name HealthBar3D
extends Node3D
## Barra de vida flutuante em cima de uma criatura no mundo.
##
## São dois quads com material billboard (sempre virados para a câmera) mais um
## Label3D com nome e nível. Nada de SubViewport: seria caro para uma coisa que
## pode existir seis vezes ao mesmo tempo.

const LARGURA := 1.5
const ALTURA := 0.2
const VELOCIDADE_ANIM := 6.0

const COR_FUNDO := Color("#12151A")
const COR_VIDA := Color("#C21F2B")
const COR_VIDA_BAIXA := Color("#8E1420")
const COR_ALIADO := Color("#3FA05A")

var _fundo: MeshInstance3D = null
var _preenchimento: MeshInstance3D = null
var _rotulo: Label3D = null
var _material_preenchimento: StandardMaterial3D = null

var _proporcao_alvo: float = 1.0
var _proporcao_atual: float = 1.0
var _aliado: bool = false


func _init(aliado: bool = false) -> void:
	_aliado = aliado


func _ready() -> void:
	_fundo = _quad(LARGURA, ALTURA, COR_FUNDO)
	add_child(_fundo)

	_material_preenchimento = _material(COR_ALIADO if _aliado else COR_VIDA)
	# render_priority maior que o do fundo: com no_depth_test ligado quem manda
	# na ordem de desenho é a prioridade, não a profundidade.
	_material_preenchimento.render_priority = 11
	_preenchimento = MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2(LARGURA - 0.06, ALTURA - 0.06)
	_preenchimento.mesh = mesh
	_preenchimento.material_override = _material_preenchimento
	_preenchimento.position.z = 0.004
	add_child(_preenchimento)

	_rotulo = Label3D.new()
	_rotulo.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_rotulo.no_depth_test = true
	_rotulo.render_priority = 12
	# Sem fixed_size: o nome tem que encolher com a distância como o resto do
	# mundo, senão vira um letreiro maior que a criatura.
	_rotulo.pixel_size = 0.006
	_rotulo.font_size = 32
	_rotulo.outline_size = 8
	_rotulo.outline_modulate = Color(0, 0, 0, 0.85)
	_rotulo.modulate = Color("#E6E3DB")
	_rotulo.position = Vector3(0, ALTURA + 0.16, 0)
	add_child(_rotulo)


func configurar(nome: String, nivel: int) -> void:
	if _rotulo != null:
		_rotulo.text = "%s  Nv.%d" % [nome, nivel]


func definir_proporcao(proporcao: float, imediato: bool = false) -> void:
	_proporcao_alvo = clampf(proporcao, 0.0, 1.0)
	if imediato:
		_proporcao_atual = _proporcao_alvo
		_aplicar()


func _process(delta: float) -> void:
	if is_equal_approx(_proporcao_atual, _proporcao_alvo):
		return
	_proporcao_atual = lerpf(_proporcao_atual, _proporcao_alvo, clampf(VELOCIDADE_ANIM * delta, 0.0, 1.0))
	_aplicar()


func _aplicar() -> void:
	if _preenchimento == null:
		return
	var largura_util := LARGURA - 0.05
	_preenchimento.scale.x = maxf(0.001, _proporcao_atual)
	# Encolhe a partir da esquerda, não do centro.
	_preenchimento.position.x = -largura_util * 0.5 * (1.0 - _proporcao_atual)
	if not _aliado:
		_material_preenchimento.albedo_color = COR_VIDA if _proporcao_atual > 0.3 else COR_VIDA_BAIXA
		_material_preenchimento.emission = _material_preenchimento.albedo_color


static func _quad(largura: float, altura: float, cor: Color) -> MeshInstance3D:
	var no := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2(largura, altura)
	no.mesh = mesh
	no.material_override = _material(cor)
	return no


static func _material(cor: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = cor
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.billboard_keep_scale = true
	material.no_depth_test = true
	material.render_priority = 10
	material.emission_enabled = true
	material.emission = cor
	material.emission_energy_multiplier = 0.6
	return material
