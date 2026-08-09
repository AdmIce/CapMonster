class_name MapGate
extends Interactable
## The physical link between two maps. Locked gates stay visible and explain
## themselves rather than disappearing, so the player knows where to come back to.

var gate_id: String = ""
var to_map: String = ""
var to_spawn: String = "start"
var requirements: Dictionary = {}
var locked_message: String = "O caminho está fechado."

var _seal: MeshInstance3D = null
var _phase: float = 0.0


static func create(data: Dictionary) -> MapGate:
	var gate := MapGate.new()
	gate.gate_id = data.get("id", "")
	gate.to_map = data.get("to_map", "")
	gate.to_spawn = data.get("to_spawn", "start")
	gate.requirements = (data.get("requires", {}) as Dictionary).duplicate()
	gate.locked_message = data.get("locked_message", "O caminho está fechado.")
	gate.title = data.get("name", "Passagem")
	gate.verb = "Entrar"
	gate.radius = 2.8
	gate.name = "Gate_%s" % gate.gate_id
	gate.set_meta("color", data.get("color", "#7E7869"))
	var pos: Array = data.get("pos", [0, 0])
	gate.position = Vector3(pos[0], 0.0, pos[1])
	return gate


func _ready() -> void:
	super._ready()
	_build_visual()


func _process(delta: float) -> void:
	if _seal == null:
		return
	_phase += delta * 1.4
	var material: StandardMaterial3D = _seal.material_override
	var open := is_available()
	material.emission = Design.ACCENT if open else Design.DANGER
	material.emission_energy_multiplier = (1.0 if open else 0.5) + sin(_phase) * 0.25


func _build_visual() -> void:
	var stone := Color.html(str(get_meta("color", "#7E7869")))
	for side in [-1.0, 1.0]:
		add_child(_mesh(_cylinder(0.42, 3.6), stone, Vector3(side * 1.7, 1.8, 0)))
	var lintel := BoxMesh.new()
	lintel.size = Vector3(4.4, 0.7, 0.9)
	add_child(_mesh(lintel, stone.lightened(0.1), Vector3(0, 3.9, 0)))

	var seal_mesh := BoxMesh.new()
	seal_mesh.size = Vector3(2.6, 3.2, 0.12)
	_seal = _mesh(seal_mesh, Color(0.1, 0.12, 0.14, 0.55), Vector3(0, 1.7, 0))
	var material: StandardMaterial3D = _seal.material_override
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.emission_enabled = true
	material.emission = Design.DANGER
	material.emission_energy_multiplier = 0.6
	add_child(_seal)

	for side in [-1.0, 1.0]:
		var body := StaticBody3D.new()
		body.collision_layer = GameLayers.WORLD
		body.collision_mask = 0
		body.position = Vector3(side * 1.7, 1.8, 0)
		var shape := CollisionShape3D.new()
		var cylinder := CylinderShape3D.new()
		cylinder.radius = 0.5
		cylinder.height = 3.6
		shape.shape = cylinder
		body.add_child(shape)
		add_child(body)


func is_available() -> bool:
	var player := GameManager.player
	if player == null or not DataManager.has_map(to_map):
		return false
	var required_boss: String = requirements.get("boss_defeated", "")
	if required_boss != "" and not player.is_boss_defeated(required_boss):
		return false
	var required_level := int(requirements.get("player_level", 0))
	if required_level > 0 and player.level < required_level:
		return false
	return true


func unavailable_reason() -> String:
	var player := GameManager.player
	if player == null:
		return ""
	var required_level := int(requirements.get("player_level", 0))
	if required_level > 0 and player.level < required_level:
		return "Você precisa chegar ao nível %d de treinador antes." % required_level
	return locked_message


func prompt_label() -> String:
	if not is_available():
		return "%s  (selado)" % title
	return "%s  %s -> %s" % [verb, title, DataManager.get_map_name(to_map)]


func _perform(_by: Node3D) -> void:
	GameLog.info(GameLog.Channel.WORLD, "Viajando para %s." % to_map)
	GameManager.travel_to_map(to_map, to_spawn)


# --- helpers ------------------------------------------------------------------

static func _mesh(mesh: Mesh, color: Color, position: Vector3) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = position
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	node.material_override = material
	return node


static func _cylinder(radius: float, height: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 10
	return mesh
