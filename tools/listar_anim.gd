extends SceneTree
## Lista as animações de um modelo.
##
##   godot --headless --path . --script tools/listar_anim.gd -- <res://caminho.glb>
##
## Existe porque "esse personagem sabe sentar?" não se responde abrindo o
## arquivo: o nome da animação varia por pacote (`Sit_Floor_Idle` num kit,
## `Root|Sit` em outro), e chutar o nome dá um `has_animation()` falso em
## silêncio, sem erro nenhum no console.

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var caminho := args[0] if args.size() > 0 else "res://assets/models/characters/Knight.glb"
	if not ResourceLoader.exists(caminho):
		print("nao existe: ", caminho)
		quit()
		return

	var no := (load(caminho) as PackedScene).instantiate()
	var tocador := _achar(no)
	if tocador == null:
		print("sem AnimationPlayer em ", caminho)
		no.free()
		quit()
		return

	var nomes := tocador.get_animation_list()
	print("%s — %d animacao(oes)" % [caminho, nomes.size()])
	for n in nomes:
		print("  ", n)
	no.free()
	quit()


func _achar(no: Node) -> AnimationPlayer:
	if no is AnimationPlayer:
		return no as AnimationPlayer
	for filho in no.get_children():
		var achado := _achar(filho)
		if achado != null:
			return achado
	return null
