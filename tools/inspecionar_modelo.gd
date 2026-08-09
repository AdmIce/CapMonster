extends SceneTree
## Ferramenta de linha de comando: descreve um modelo importado sem abrir o editor.
##
##   godot --headless --path . --script tools/inspecionar_modelo.gd -- <res://caminho>
##
## Existe porque "o Godot importou?" e "dá para usar?" são perguntas diferentes:
## um .fbx pode virar cena e ainda assim vir sem esqueleto, sem malha ou com a
## escala errada. Isto responde as três de uma vez.

func _init() -> void:
	var alvos := OS.get_cmdline_user_args()
	if alvos.is_empty():
		alvos = ["res://3d/personagens/Model/characterMedium.fbx"]

	for caminho in alvos:
		print("=== ", caminho)
		if not ResourceLoader.exists(caminho):
			print("  NAO IMPORTADO")
			continue
		var recurso := load(caminho)
		if recurso is PackedScene:
			var no := (recurso as PackedScene).instantiate()
			_descrever(no, 1)
			no.free()
		else:
			print("  tipo: ", recurso.get_class())
	quit()


func _descrever(no: Node, nivel: int) -> void:
	var recuo := "  ".repeat(nivel)
	var extra := ""
	if no is Node3D:
		var escala := (no as Node3D).transform.basis.get_scale()
		if not escala.is_equal_approx(Vector3.ONE):
			extra += "  escala=%.4f" % escala.y
	if no is MeshInstance3D:
		var instancia := no as MeshInstance3D
		var malha := instancia.mesh
		if malha != null:
			# `mesh.get_aabb()` é a caixa do recurso; `instancia.get_aabb()` já leva
			# em conta a caixa customizada que a importação grava para malha com
			# pele. As duas divergem, e é a segunda que vale.
			var recurso := malha.get_aabb()
			var no_aabb := instancia.get_aabb()
			extra += "  malha=%d sup  recurso_h=%.4f  no_h=%.4f" % [
				malha.get_surface_count(), recurso.size.y, no_aabb.size.y
			]
	elif no is Skeleton3D:
		var esqueleto := no as Skeleton3D
		# Altura pela pose de descanso dos ossos, e não pela AABB: numa malha com
		# pele a AABB é a caixa do bind pose e costuma vir degenerada.
		var topo := -INF
		var base := INF
		var mais_alto := ""
		for i in esqueleto.get_bone_count():
			var y := esqueleto.get_bone_global_rest(i).origin.y
			base = minf(base, y)
			if y > topo:
				topo = y
				mais_alto = esqueleto.get_bone_name(i)
		extra = "  %d osso(s)  rest y=[%.3f..%.3f] (topo: %s)" % [
			esqueleto.get_bone_count(), base, topo, mais_alto
		]
	elif no is AnimationPlayer:
		extra = "  animacoes: %s" % ", ".join((no as AnimationPlayer).get_animation_list())

	print(recuo, no.name, " (", no.get_class(), ")", extra)
	for filho in no.get_children():
		_descrever(filho, nivel + 1)
