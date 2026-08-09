extends SceneTree
## Mostra a pose de descanso de um osso, com escala.
##
##   godot --headless --path . --script tools/inspecionar_osso.gd -- <cena> <osso>
##
## Existe porque pendurar coisa em osso dá errado em silêncio: se o rig tem
## escala embutida, o `BoneAttachment3D` herda ela e o acessório sai gigante ou
## microscópico sem nenhum erro no console.

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var caminho := args[0] if args.size() > 0 else "res://assets/models/characters/Knight.glb"
	var alvo := args[1] if args.size() > 1 else "chest"

	if not ResourceLoader.exists(caminho):
		print("nao existe: ", caminho)
		quit()
		return

	var no := (load(caminho) as PackedScene).instantiate()
	var esqueleto := _achar(no)
	if esqueleto == null:
		print("sem Skeleton3D")
		no.free()
		quit()
		return

	var indice := esqueleto.find_bone(alvo)
	if indice == -1:
		print("osso '%s' nao existe. Primeiros: " % alvo)
		for i in mini(esqueleto.get_bone_count(), 12):
			print("  ", esqueleto.get_bone_name(i))
		no.free()
		quit()
		return

	var descanso := esqueleto.get_bone_global_rest(indice)
	print("osso '%s'" % alvo)
	print("  posicao: ", descanso.origin)
	print("  escala:  ", descanso.basis.get_scale())
	print("  escala do proprio Skeleton3D: ", esqueleto.transform.basis.get_scale())
	no.free()
	quit()


func _achar(no: Node) -> Skeleton3D:
	if no is Skeleton3D:
		return no as Skeleton3D
	for filho in no.get_children():
		var achado := _achar(filho)
		if achado != null:
			return achado
	return null
