class_name CreatureModelBuilder
extends RefCounted
## Builds a creature's 3D representation.
##
## If the species declares a `model_path`, that scene is instantiated and this
## file gets out of the way. Otherwise it assembles a procedural placeholder
## from the `visual` block in creatures.json - readable silhouettes with the
## species' own palette, so the game is playable and visually distinct before
## any modelling work exists.
##
## The returned node exposes two meta keys used by the simple animator:
##   "anchor_head" : Node3D or null
##   "anchor_body" : Node3D

const ROUGHNESS := 0.82


static func build(species: CreatureSpecies) -> Node3D:
	if species == null:
		return _fallback()
	if species.model_path != "" and ResourceLoader.exists(species.model_path):
		var importado := _carregar_modelo(species)
		if importado != null:
			return importado

	var root := Node3D.new()
	root.name = "Model_%s" % species.id

	var primary := species.visual_color("primary", Color(0.5, 0.6, 0.4))
	var secondary := species.visual_color("secondary", primary.darkened(0.35))
	var accent := species.visual_color("accent", primary.lightened(0.4))
	var size := species.visual_size()

	match species.visual_body():
		"biped":
			_build_biped(root, primary, secondary, accent)
		"floating":
			_build_floating(root, primary, secondary, accent)
		"avian":
			_build_avian(root, primary, secondary, accent)
		"hulk":
			_build_hulk(root, primary, secondary, accent)
		"serpent":
			_build_serpent(root, primary, secondary, accent)
		_:
			_build_quadruped(root, primary, secondary, accent)

	_apply_features(root, species, primary, secondary, accent)
	root.scale = Vector3.ONE * size
	return root


## Carrega o `model_path` de uma espécie.
##
## Aceita as duas formas que o Godot produz: `.glb`/`.tscn` importam como
## PackedScene, `.obj` importa como Mesh solto. O resultado sai sempre embrulhado
## num Node3D com escala/altura/giro aplicados, para o resto do jogo tratar
## modelo importado e placeholder exatamente igual.
static func _carregar_modelo(species: CreatureSpecies) -> Node3D:
	var recurso: Resource = load(species.model_path)
	var conteudo: Node3D = null

	if recurso is PackedScene:
		var instancia := (recurso as PackedScene).instantiate()
		if instancia is Node3D:
			conteudo = instancia
		else:
			instancia.queue_free()
			GameLog.warn(GameLog.Channel.CREATURE, "model_path de '%s' não é um Node3D." % species.id)
			return null
	elif recurso is Mesh:
		var malha := MeshInstance3D.new()
		malha.mesh = recurso
		conteudo = malha
	else:
		GameLog.warn(
			GameLog.Channel.CREATURE,
			"model_path de '%s' não é uma cena nem uma malha." % species.id
		)
		return null

	var raiz := Node3D.new()
	raiz.name = "Modelo_%s" % species.id
	conteudo.name = "Malha"
	conteudo.scale = Vector3.ONE * maxf(0.01, species.model_scale)
	conteudo.position.y = species.model_offset_y
	conteudo.rotation_degrees = Vector3(species.model_pitch, species.model_yaw, 0.0)
	raiz.add_child(conteudo)
	return raiz


static func _fallback() -> Node3D:
	var root := Node3D.new()
	root.add_child(_mesh(SphereMesh.new(), Color(0.7, 0.2, 0.6), Vector3(0, 0.5, 0), Vector3.ONE))
	return root


# --- body plans ---------------------------------------------------------------

static func _build_quadruped(root: Node3D, primary: Color, secondary: Color, accent: Color) -> void:
	var body := _mesh(_capsule(0.34, 1.05), primary, Vector3(0, 0.58, 0), Vector3.ONE, Vector3(90, 0, 0))
	body.name = "Body"
	root.add_child(body)

	var head := _mesh(SphereMesh.new(), primary.lightened(0.06), Vector3(0, 0.78, -0.62), Vector3.ONE * 0.46)
	head.name = "Head"
	root.add_child(head)

	root.add_child(_mesh(SphereMesh.new(), secondary, Vector3(0, 0.66, -0.82), Vector3(0.24, 0.2, 0.3)))
	_eyes(root, Vector3(0, 0.86, -0.8), 0.13, accent)

	var leg := _cylinder(0.09, 0.46)
	for offset in [Vector3(0.22, 0.23, -0.3), Vector3(-0.22, 0.23, -0.3), Vector3(0.22, 0.23, 0.32), Vector3(-0.22, 0.23, 0.32)]:
		root.add_child(_mesh(leg, secondary, offset, Vector3.ONE))


static func _build_biped(root: Node3D, primary: Color, secondary: Color, accent: Color) -> void:
	var body := _mesh(_capsule(0.36, 0.9), primary, Vector3(0, 0.92, 0), Vector3.ONE)
	body.name = "Body"
	root.add_child(body)

	var head := _mesh(SphereMesh.new(), primary.lightened(0.08), Vector3(0, 1.52, 0), Vector3.ONE * 0.5)
	head.name = "Head"
	root.add_child(head)
	_eyes(root, Vector3(0, 1.56, -0.22), 0.14, accent)

	var arm := _capsule(0.1, 0.58)
	root.add_child(_mesh(arm, secondary, Vector3(0.42, 0.98, 0), Vector3.ONE, Vector3(0, 0, 12)))
	root.add_child(_mesh(arm, secondary, Vector3(-0.42, 0.98, 0), Vector3.ONE, Vector3(0, 0, -12)))

	var leg := _capsule(0.13, 0.5)
	root.add_child(_mesh(leg, secondary, Vector3(0.17, 0.3, 0), Vector3.ONE))
	root.add_child(_mesh(leg, secondary, Vector3(-0.17, 0.3, 0), Vector3.ONE))


static func _build_floating(root: Node3D, primary: Color, secondary: Color, accent: Color) -> void:
	var body := _mesh(SphereMesh.new(), primary, Vector3(0, 1.05, 0), Vector3(0.78, 0.9, 0.78))
	body.name = "Body"
	root.add_child(body)

	var core := _mesh(SphereMesh.new(), accent, Vector3(0, 1.05, -0.24), Vector3.ONE * 0.3)
	core.name = "Head"
	_glow(core, accent)
	root.add_child(core)

	# Trailing wisps instead of legs.
	for i in 3:
		var t := float(i)
		root.add_child(_mesh(
			SphereMesh.new(),
			secondary,
			Vector3(0.0, 0.66 - t * 0.16, 0.24 + t * 0.16),
			Vector3.ONE * (0.26 - t * 0.06)
		))


static func _build_avian(root: Node3D, primary: Color, secondary: Color, accent: Color) -> void:
	var body := _mesh(_capsule(0.28, 0.72), primary, Vector3(0, 0.82, 0), Vector3.ONE, Vector3(72, 0, 0))
	body.name = "Body"
	root.add_child(body)

	var head := _mesh(SphereMesh.new(), primary.lightened(0.08), Vector3(0, 1.16, -0.3), Vector3.ONE * 0.38)
	head.name = "Head"
	root.add_child(head)
	root.add_child(_mesh(_cone(0.09, 0.26), accent, Vector3(0, 1.12, -0.52), Vector3.ONE, Vector3(-90, 0, 0)))
	_eyes(root, Vector3(0, 1.2, -0.44), 0.11, accent)

	var leg := _cylinder(0.06, 0.34)
	root.add_child(_mesh(leg, secondary, Vector3(0.13, 0.17, 0.06), Vector3.ONE))
	root.add_child(_mesh(leg, secondary, Vector3(-0.13, 0.17, 0.06), Vector3.ONE))


static func _build_hulk(root: Node3D, primary: Color, secondary: Color, accent: Color) -> void:
	var body := _mesh(SphereMesh.new(), primary, Vector3(0, 0.78, 0), Vector3(1.22, 0.98, 1.1))
	body.name = "Body"
	root.add_child(body)

	var head := _mesh(SphereMesh.new(), primary.darkened(0.08), Vector3(0, 0.92, -0.68), Vector3.ONE * 0.5)
	head.name = "Head"
	root.add_child(head)
	_eyes(root, Vector3(0, 0.98, -0.86), 0.14, accent)

	var leg := _cylinder(0.16, 0.38)
	for offset in [Vector3(0.42, 0.19, -0.24), Vector3(-0.42, 0.19, -0.24), Vector3(0.42, 0.19, 0.3), Vector3(-0.42, 0.19, 0.3)]:
		root.add_child(_mesh(leg, secondary, offset, Vector3.ONE))


static func _build_serpent(root: Node3D, primary: Color, secondary: Color, accent: Color) -> void:
	var head := _mesh(SphereMesh.new(), primary.lightened(0.08), Vector3(0, 0.9, -0.5), Vector3.ONE * 0.46)
	head.name = "Head"
	root.add_child(head)
	_eyes(root, Vector3(0, 0.94, -0.68), 0.12, accent)

	var body := Node3D.new()
	body.name = "Body"
	root.add_child(body)
	for i in 5:
		var t := float(i)
		body.add_child(_mesh(
			SphereMesh.new(),
			primary if i % 2 == 0 else secondary,
			Vector3(0, 0.72 - t * 0.05, -0.1 + t * 0.3),
			Vector3.ONE * (0.44 - t * 0.05)
		))


# --- feature layer ------------------------------------------------------------

static func _apply_features(
	root: Node3D, species: CreatureSpecies, primary: Color, secondary: Color, accent: Color
) -> void:
	var head: Node3D = root.get_node_or_null("Head")
	var head_pos: Vector3 = head.position if head != null else Vector3(0, 1.0, -0.4)

	if species.has_feature("horns"):
		var horn := _cone(0.09, 0.36)
		root.add_child(_mesh(horn, accent, head_pos + Vector3(0.19, 0.26, 0.04), Vector3.ONE, Vector3(-18, 0, 16)))
		root.add_child(_mesh(horn, accent, head_pos + Vector3(-0.19, 0.26, 0.04), Vector3.ONE, Vector3(-18, 0, -16)))

	if species.has_feature("crest"):
		root.add_child(_mesh(
			_cone(0.16, 0.34), accent, head_pos + Vector3(0, 0.3, 0.06), Vector3(1.0, 1.0, 0.35)
		))

	if species.has_feature("mane"):
		root.add_child(_mesh(
			TorusMesh.new(), secondary.lightened(0.1), head_pos + Vector3(0, -0.06, 0.22),
			Vector3(0.62, 0.62, 0.62), Vector3(84, 0, 0)
		))

	if species.has_feature("tail"):
		root.add_child(_mesh(_cone(0.12, 0.6), secondary, Vector3(0, 0.66, 0.62), Vector3.ONE, Vector3(52, 0, 0)))

	if species.has_feature("wings"):
		var wing := BoxMesh.new()
		wing.size = Vector3(0.9, 0.06, 0.55)
		root.add_child(_mesh(wing, secondary.lightened(0.14), Vector3(0.6, 1.02, 0.06), Vector3.ONE, Vector3(0, 0, 22)))
		root.add_child(_mesh(wing, secondary.lightened(0.14), Vector3(-0.6, 1.02, 0.06), Vector3.ONE, Vector3(0, 0, -22)))

	if species.has_feature("plates"):
		for i in 3:
			var t := float(i)
			root.add_child(_mesh(
				_prism(), secondary.darkened(0.12),
				Vector3(0, 1.02 - t * 0.04, -0.2 + t * 0.32),
				Vector3(0.42 - t * 0.05, 0.3, 0.14)
			))

	if species.has_feature("gem"):
		var gem := _mesh(SphereMesh.new(), accent, head_pos + Vector3(0, 0.02, -0.24), Vector3.ONE * 0.15)
		_glow(gem, accent)
		root.add_child(gem)

	if species.has_feature("orbs"):
		var orbs := Node3D.new()
		orbs.name = "Orbs"
		root.add_child(orbs)
		for i in 3:
			var angle := TAU * float(i) / 3.0
			var orb := _mesh(
				SphereMesh.new(), accent,
				Vector3(cos(angle) * 0.62, 1.0 + sin(angle) * 0.14, sin(angle) * 0.62),
				Vector3.ONE * 0.14
			)
			_glow(orb, accent)
			orbs.add_child(orb)


# --- primitives ---------------------------------------------------------------

static func _mesh(
	mesh: Mesh, color: Color, position: Vector3, scale: Vector3, rotation_deg: Vector3 = Vector3.ZERO
) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = position
	node.scale = scale
	node.rotation_degrees = rotation_deg
	node.material_override = _material(color)
	return node


static func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = ROUGHNESS
	material.metallic = 0.0
	material.rim_enabled = true
	material.rim = 0.35
	material.rim_tint = 0.5
	return material


static func _glow(node: MeshInstance3D, color: Color) -> void:
	var material: StandardMaterial3D = node.material_override
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.9


static func _capsule(radius: float, height: float) -> CapsuleMesh:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = maxf(height, radius * 2.0 + 0.01)
	mesh.radial_segments = 12
	mesh.rings = 6
	return mesh


static func _cylinder(radius: float, height: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 10
	return mesh


static func _cone(radius: float, height: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 10
	return mesh


static func _prism() -> PrismMesh:
	var mesh := PrismMesh.new()
	mesh.size = Vector3.ONE
	return mesh


static func _eyes(root: Node3D, position: Vector3, spread: float, color: Color) -> void:
	var eye_color := Color(0.06, 0.07, 0.09)
	var left := _mesh(SphereMesh.new(), eye_color, position + Vector3(spread, 0, 0), Vector3.ONE * 0.09)
	var right := _mesh(SphereMesh.new(), eye_color, position + Vector3(-spread, 0, 0), Vector3.ONE * 0.09)
	root.add_child(left)
	root.add_child(right)
	var spark := _mesh(SphereMesh.new(), color.lightened(0.4), position + Vector3(0, 0.16, 0.02), Vector3.ONE * 0.05)
	root.add_child(spark)
