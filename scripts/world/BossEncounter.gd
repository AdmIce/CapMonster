class_name BossEncounter
extends Interactable
## O chefe (ou mini-chefe) parado no mapa, esperando.
##
## Diferente de criatura selvagem, chefe **não** puxa briga por encostão: fica
## visível com uma aura e o jogador escolhe encarar apertando Interagir. Perder
## para um chefe sem querer seria punição por caminhar.
##
## Depois de derrotado ele continua no lugar, mas apagado - vira marco de
## progresso em vez de sumir do mundo.

signal batalha_pedida(encontro: Dictionary, tier: String)

const AURA_VELOCIDADE := 1.1

var encontro: Dictionary = {}
var tier: String = "boss"
var map_id: String = ""

var _modelo: Node3D = null
var _aura: MeshInstance3D = null
var _luz: OmniLight3D = null
var _fase: float = 0.0


static func create(dados: Dictionary, mapa: String, faixa: String) -> BossEncounter:
	var no := BossEncounter.new()
	no.encontro = dados.duplicate(true)
	no.map_id = mapa
	no.tier = faixa
	no.title = String(dados.get("name", "Chefe"))
	no.verb = "Encarar"
	no.radius = 4.0
	no.name = "Chefe_%s" % dados.get("id", faixa)
	var pos: Array = dados.get("pos", [0, 0])
	no.position = Vector3(pos[0], 0.0, pos[1])
	return no


func _ready() -> void:
	super._ready()
	_montar_visual()
	_atualizar_aparencia()


func _process(delta: float) -> void:
	_fase += delta * AURA_VELOCIDADE
	if _aura != null:
		var escala := 1.0 + sin(_fase) * 0.06
		_aura.scale = Vector3(escala, 1.0, escala)
	if _luz != null and not derrotado():
		_luz.light_energy = 2.2 + sin(_fase * 1.6) * 0.6
	if _modelo != null and not derrotado():
		_modelo.position.y = absf(sin(_fase * 0.8)) * 0.07


func _montar_visual() -> void:
	var especie := DataManager.get_species(StringName(encontro.get("species", "")))
	_modelo = CreatureModelBuilder.build(especie)
	# Chefe é maior que a versão selvagem da mesma espécie: leitura à distância.
	_modelo.scale = Vector3.ONE * 1.25
	add_child(_modelo)

	var cor := DataManager.get_element_color(especie.element if especie != null else "nature")

	_aura = MeshInstance3D.new()
	var disco := CylinderMesh.new()
	disco.top_radius = 3.0
	disco.bottom_radius = 3.0
	disco.height = 0.04
	disco.radial_segments = 28
	_aura.mesh = disco
	_aura.position = Vector3(0, 0.03, 0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(cor.r, cor.g, cor.b, 0.3)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.emission_enabled = true
	material.emission = cor
	material.emission_energy_multiplier = 0.9
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_aura.material_override = material
	add_child(_aura)

	_luz = OmniLight3D.new()
	_luz.light_color = cor
	_luz.light_energy = 2.2
	_luz.omni_range = 9.0
	_luz.position = Vector3(0, 1.4, 0)
	add_child(_luz)

	var corpo := StaticBody3D.new()
	corpo.collision_layer = GameLayers.WORLD
	corpo.collision_mask = 0
	var forma := CollisionShape3D.new()
	var cilindro := CylinderShape3D.new()
	cilindro.radius = 1.1
	cilindro.height = 2.6
	forma.shape = cilindro
	forma.position = Vector3(0, 1.3, 0)
	corpo.add_child(forma)
	add_child(corpo)


func derrotado() -> bool:
	var dados := GameManager.player
	if dados == null:
		return false
	return dados.is_mini_boss_defeated(map_id) if tier == "mini" else dados.is_boss_defeated(map_id)


## Mini-chefe está sempre disponível; o chefe só depois do mini-chefe.
func is_available() -> bool:
	if derrotado():
		return false
	var dados := GameManager.player
	if dados == null:
		return false
	var requisitos: Dictionary = encontro.get("requires", {})
	var mini_exigido := String(requisitos.get("mini_boss_defeated", ""))
	if mini_exigido != "" and not dados.is_mini_boss_defeated(mini_exigido):
		return false
	return true


func unavailable_reason() -> String:
	if derrotado():
		return "%s já foi derrotado." % title
	return "%s não vai se mostrar enquanto o guardião das ruínas estiver de pé." % title


func prompt_label() -> String:
	if derrotado():
		return "%s  (derrotado)" % title
	if not is_available():
		return "%s  (ainda não)" % title
	var nivel := int(encontro.get("level", 1))
	return "%s  %s  ·  Nv.%d" % [verb, title, nivel]


func _perform(_by: Node3D) -> void:
	batalha_pedida.emit(encontro, tier)


## Chamado pelo mundo quando a batalha acaba, para o chefe apagar na hora.
func atualizar_estado() -> void:
	_atualizar_aparencia()


func _atualizar_aparencia() -> void:
	var caido := derrotado()
	if _aura != null:
		_aura.visible = not caido
	if _luz != null:
		_luz.visible = not caido
	if _modelo != null:
		_modelo.rotation_degrees.z = 78.0 if caido else 0.0
		_modelo.position.y = -0.2 if caido else 0.0
		_modelo.scale = Vector3.ONE * (1.0 if caido else 1.25)
