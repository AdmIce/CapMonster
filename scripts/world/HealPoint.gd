class_name HealPoint
extends Interactable
## Acampamento / abrigo. Recupera a coleção inteira e vira a âncora de retorno do
## mapa atual. Interagir também salva, já que é um ponto de checagem natural.

const PULSE_SPEED := 2.2

var point_id: String = ""

var _glow: MeshInstance3D = null
var _phase: float = 0.0


static func create(data: Dictionary) -> HealPoint:
	var point := HealPoint.new()
	point.point_id = data.get("id", "")
	point.title = data.get("name", "Acampamento")
	point.verb = "Descansar em"
	point.radius = 3.0
	point.name = "Heal_%s" % point.point_id
	var pos: Array = data.get("pos", [0, 0])
	point.position = Vector3(pos[0], 0.0, pos[1])
	return point


func _ready() -> void:
	super._ready()
	_build_visual()


func _process(delta: float) -> void:
	if _glow == null:
		return
	_phase += delta * PULSE_SPEED
	var material: StandardMaterial3D = _glow.material_override
	material.emission_energy_multiplier = 1.4 + sin(_phase) * 0.5
	_glow.scale = Vector3.ONE * (1.0 + sin(_phase) * 0.04)


func _build_visual() -> void:
	var stone := Color("#6E6558")
	for i in 6:
		var angle := TAU * float(i) / 6.0
		add_child(_mesh(
			SphereMesh.new(), stone,
			Vector3(cos(angle) * 0.85, 0.14, sin(angle) * 0.85), Vector3.ONE * 0.36
		))

	_glow = _mesh(_cone(0.36, 0.9), Color("#E08A3C"), Vector3(0, 0.5, 0))
	var material: StandardMaterial3D = _glow.material_override
	material.emission_enabled = true
	material.emission = Color("#F0A64E")
	material.emission_energy_multiplier = 1.6
	add_child(_glow)

	var light := OmniLight3D.new()
	light.light_color = Color("#F0A64E")
	light.light_energy = 1.5
	light.omni_range = 9.0
	light.position = Vector3(0, 1.1, 0)
	add_child(light)


func _perform(_by: Node3D) -> void:
	var player := GameManager.player
	if player == null:
		return
	player.heal_all()
	player.set_flag("last_heal_point", point_id)
	player.set_flag("last_heal_map", player.current_map)
	GameManager.save_now("descanso")
	Notify.good("Sua equipe está descansada.")
	GameLog.info(GameLog.Channel.WORLD, "Descansou em %s." % title)


# --- utilidades ---------------------------------------------------------------

static func _mesh(mesh: Mesh, color: Color, position: Vector3, scale: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = position
	node.scale = scale
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	node.material_override = material
	return node


static func _cone(radius: float, height: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 10
	return mesh
