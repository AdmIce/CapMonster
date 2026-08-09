class_name ImpactBurst
extends GPUParticles3D
## Faísca curta no ponto de impacto, na cor do elemento do golpe.
##
## É `one_shot` e se apaga sozinha: quem cria não precisa guardar referência nem
## lembrar de liberar. Poucas partículas de propósito - o documento de arte pede
## partícula discreta, não chuva de confete.

const DURACAO := 0.45


static func disparar(pai: Node3D, posicao: Vector3, cor: Color, forca: float = 1.0) -> void:
	var burst := ImpactBurst.new()
	burst.position = posicao
	burst._configurar(cor, forca)
	pai.add_child(burst)
	burst.emitting = true
	burst.get_tree().create_timer(DURACAO + burst.lifetime).timeout.connect(burst.queue_free)


func _configurar(cor: Color, forca: float) -> void:
	amount = int(clampf(10.0 * forca, 6.0, 26.0))
	lifetime = 0.5
	one_shot = true
	explosiveness = 1.0
	speed_scale = 1.4

	var forma := SphereMesh.new()
	forma.radius = 0.055
	forma.height = 0.11
	forma.radial_segments = 6
	forma.rings = 3
	draw_pass_1 = forma

	var material := StandardMaterial3D.new()
	material.albedo_color = cor
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.emission_enabled = true
	material.emission = cor
	material.emission_energy_multiplier = 2.2
	material_override = material

	var processo := ParticleProcessMaterial.new()
	processo.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	processo.emission_sphere_radius = 0.18
	processo.direction = Vector3(0, 1, 0)
	processo.spread = 75.0
	processo.initial_velocity_min = 1.6 * forca
	processo.initial_velocity_max = 3.4 * forca
	processo.gravity = Vector3(0, -5.5, 0)
	processo.damping_min = 1.0
	processo.damping_max = 2.5
	processo.scale_min = 0.5
	processo.scale_max = 1.2

	# Encolhe até sumir, em vez de piscar fora da tela.
	var curva := Curve.new()
	curva.add_point(Vector2(0.0, 1.0))
	curva.add_point(Vector2(1.0, 0.0))
	var textura := CurveTexture.new()
	textura.curve = curva
	processo.scale_curve = textura

	process_material = processo
