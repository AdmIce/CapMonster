class_name HumanoidBuilder
extends RefCounted
## Monta a figura humanoide usada por NPCs e pela cena de abertura.
##
## As cores vêm dos dados (maps.json / intro.json), então cada personagem tem
## silhueta própria sem nenhum asset. Quando existir modelo rigado, esta classe
## é substituída por uma instância de cena e o resto do código não muda.

const ROLE_MARKERS := {
	"healer": "#6FA84A",
	"researcher": "#4A8FB8",
	"merchant": "#C9922F",
	"guide": "#C9B173",
}


const ALTURA_ALVO := 1.68

## Cada NPC ganha um dos personagens do pacote, escolhido de forma estável pelo
## papel: assim o curandeiro é sempre o mesmo, mas a vila não fica com quatro
## clones.
const POR_PAPEL := {
	"healer": "Mage",
	"researcher": "Mage",
	"merchant": "Barbarian",
	"guide": "Rogue",
	"villager": "Knight",
}


static func build(colors: Dictionary, role: String = "") -> Node3D:
	# Mesmo pacote do jogador: a vila inteira fica coerente e os NPCs ganham a
	# animação de parado de graça.
	var importado := _build_importado(colors, role)
	if importado != null:
		return importado
	return _build_primitivas(colors, role)


static func _build_importado(colors: Dictionary, role: String) -> Node3D:
	var nome := String(POR_PAPEL.get(role, "Knight"))
	var caminho := PlayerAvatar.PASTA + nome + ".glb"
	if not ResourceLoader.exists(caminho):
		return null
	var instancia := (load(caminho) as PackedScene).instantiate()
	if not (instancia is Node3D):
		instancia.queue_free()
		return null

	var modelo := instancia as Node3D
	PlayerAvatar._esconder_armas(modelo)

	var pele := _color(colors.get("skin", "#C99B72"))
	var roupa := _color(colors.get("outfit", "#4F6E8A"))
	var detalhe := _color(colors.get("trim", "#C9B173"))

	var tintas := {
		nome + "_Head": pele,
		nome + "_ArmLeft": pele,
		nome + "_ArmRight": pele,
		nome + "_Body": roupa,
		nome + "_LegLeft": roupa.darkened(0.25),
		nome + "_LegRight": roupa.darkened(0.25),
		nome + "_Cape": detalhe,
	}
	for no in PlayerAvatar._todos(modelo):
		if no is MeshInstance3D and tintas.has(no.name):
			(no as MeshInstance3D).material_override = PlayerAvatar._tingir(no, tintas[no.name])

	var animador := PlayerAvatar._achar_animador(modelo)
	if animador != null and animador.has_animation("Idle"):
		var animacao := animador.get_animation("Idle")
		if animacao != null:
			animacao.loop_mode = Animation.LOOP_LINEAR
		animador.play("Idle")

	# Mesmo rig do jogador: `root` nos pés, rosto virado para +Z (ver PlayerAvatar).
	modelo.scale = Vector3.ONE * (ALTURA_ALVO / PlayerAvatar.ALTURA_DO_RIG)
	modelo.position.y = 0.0
	modelo.rotation_degrees.y = PlayerAvatar.GIRO_PARA_FRENTE

	var raiz := Node3D.new()
	raiz.name = "Corpo"
	raiz.add_child(modelo)

	if ROLE_MARKERS.has(role):
		raiz.add_child(_role_marker(_color(ROLE_MARKERS[role])))
	return raiz


## Reserva: usado se o .glb do personagem sumir.
static func _build_primitivas(colors: Dictionary, role: String = "") -> Node3D:
	var skin := _color(colors.get("skin", "#C99B72"))
	var hair := _color(colors.get("hair", "#3B2E23"))
	var outfit := _color(colors.get("outfit", "#4F6E8A"))
	var trim := _color(colors.get("trim", "#C9B173"))

	var body := Node3D.new()
	body.name = "Corpo"

	body.add_child(_mesh(_capsule(0.22, 0.62), outfit, Vector3(0, 0.94, 0)))
	body.add_child(_mesh(_cylinder(0.24, 0.07), trim, Vector3(0, 0.72, 0)))
	body.add_child(_mesh(SphereMesh.new(), skin, Vector3(0, 1.38, 0), Vector3.ONE * 0.24))
	body.add_child(_mesh(SphereMesh.new(), hair, Vector3(0, 1.44, 0.01), Vector3(0.27, 0.19, 0.27)))
	body.add_child(_mesh(_capsule(0.055, 0.4), outfit.darkened(0.1), Vector3(0.28, 1.06, 0)))
	body.add_child(_mesh(_capsule(0.055, 0.4), outfit.darkened(0.1), Vector3(-0.28, 1.06, 0)))
	body.add_child(_mesh(_capsule(0.07, 0.56), outfit.darkened(0.3), Vector3(0.1, 0.4, 0)))
	body.add_child(_mesh(_capsule(0.07, 0.56), outfit.darkened(0.3), Vector3(-0.1, 0.4, 0)))

	# Olhos, para a figura ter frente definida em vez de virar um boneco cego.
	var eye := Color(0.08, 0.09, 0.11)
	body.add_child(_mesh(SphereMesh.new(), eye, Vector3(0.075, 1.39, -0.2), Vector3.ONE * 0.045))
	body.add_child(_mesh(SphereMesh.new(), eye, Vector3(-0.075, 1.39, -0.2), Vector3.ONE * 0.045))

	if ROLE_MARKERS.has(role):
		body.add_child(_role_marker(_color(ROLE_MARKERS[role])))
	return body


## Emblema flutuante que identifica a função do NPC de relance.
static func _role_marker(color: Color) -> MeshInstance3D:
	var prism := PrismMesh.new()
	prism.size = Vector3.ONE
	var marker := _mesh(prism, color, Vector3(0, 1.95, 0), Vector3(0.22, 0.3, 0.1))
	var material: StandardMaterial3D = marker.material_override
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.8
	return marker


static func _color(hex: String) -> Color:
	return Color.html(hex) if hex.begins_with("#") else Color.WHITE


static func _mesh(mesh: Mesh, color: Color, position: Vector3, scale: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = position
	node.scale = scale
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.88
	node.material_override = material
	return node


static func _capsule(radius: float, height: float) -> CapsuleMesh:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = maxf(height, radius * 2.0 + 0.01)
	mesh.radial_segments = 10
	mesh.rings = 4
	return mesh


static func _cylinder(radius: float, height: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 10
	return mesh
