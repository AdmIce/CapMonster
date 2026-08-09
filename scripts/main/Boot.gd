extends Control
## Primeira cena. Confere se o banco de dados JSON carregou, mostra a logo por um
## instante e passa para o menu principal. Se os dados falharem, ela diz isso em
## vez de jogar o jogador num mundo quebrado.

const MINIMUM_SPLASH_SECONDS := 0.9

## Carregado por caminho, não por class_name: assim funciona mesmo com o editor
## ainda sem ter reindexado as classes.
const SNAPSHOT_SCRIPT := preload("res://scripts/core/Snapshot.gd")

var _status: Label = null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_travar_tamanho_minimo()
	Design.screen_root(self)
	_build()
	_boot()


## Abaixo de MIN_JANELA as telas não têm mais como se reorganizar e passam a
## cortar conteúdo. Barrar aqui é mais honesto do que deixar o jogador chegar num
## estado onde o botão de confirmar está fora da tela.
func _travar_tamanho_minimo() -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_min_size(Responsivo.MIN_JANELA)
	# A escala escolhida vale para a janela inteira e sobrevive à troca de cena,
	# então basta aplicar uma vez aqui.
	Responsivo.aplicar_escala(self, Responsivo.escala_salva())


func _build() -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var column := Design.vbox(Design.S_SM)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(column)

	# A logo é a identidade; o título em texto fica como reserva para o caso de
	# o PNG não estar no projeto (build de teste, asset ainda não importado).
	var logo := Logo.criar(420.0)
	if logo != null:
		column.add_child(logo)
	else:
		var title := Design.label("CAPMONSTER", Design.FS_TITLE, Design.TEXT_CLARO, true)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(title)

	_status = Design.label("carregando banco de dados...", Design.FS_CAPTION, Design.TEXT_CLARO_DIM)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_status)


func _boot() -> void:
	var started := Time.get_ticks_msec()

	if not DataManager.is_loaded:
		# O DataManager carrega no próprio _ready; damos um quadro de folga caso a
		# ordem dos autoloads mude, e tentamos de novo antes de falhar em voz alta.
		await get_tree().process_frame
		if not DataManager.is_loaded and not DataManager.load_all():
			_status.text = "Falha ao carregar /data. Veja o console para detalhes."
			_status.add_theme_color_override("font_color", Design.DANGER)
			return

	_status.text = "%d espécies  ·  %d mapas" % [
		DataManager.all_species().size(), DataManager.map_ids().size()
	]

	# Testes automáticos headless, para exercitar as cenas sem ninguém apertar
	# botão:
	#   godot --headless --quit-after 900 -- --smoke        (vai direto ao mundo)
	#   godot --headless --quit-after 400 -- --smoke-intro  (vai direto à abertura)
	if OS.is_debug_build():
		var fotografo := SNAPSHOT_SCRIPT.new()
		if fotografo.configurar_a_partir_da_linha_de_comando():
			# Filho da raiz, não da cena: precisa sobreviver às trocas de cena.
			get_tree().root.add_child.call_deferred(fotografo)
		else:
			fotografo.free()

		var args := OS.get_cmdline_user_args()
		if args.has("--smoke-criacao"):
			SceneFlow.goto_character_creation()
			return
		if args.has("--smoke-intro"):
			_run_intro_test()
			return
		if args.has("--smoke"):
			_run_smoke_test()
			return

	var elapsed := float(Time.get_ticks_msec() - started) / 1000.0
	if elapsed < MINIMUM_SPLASH_SECONDS:
		await get_tree().create_timer(MINIMUM_SPLASH_SECONDS - elapsed).timeout

	SceneFlow.goto_main_menu()


## `-- --criatura=<id>[:nivel]` entrega a espécie pedida e coloca ela na frente
## da equipe. Serve para conferir um modelo novo em cena sem depender de spawn.
func _conceder_criatura_de_teste() -> void:
	for argumento in OS.get_cmdline_user_args():
		if not argumento.begins_with("--criatura="):
			continue
		var valor := argumento.split("=")[1]
		var partes := valor.split(":")
		var especie := StringName(partes[0])
		if not DataManager.has_species(especie):
			GameLog.error(GameLog.Channel.SYSTEM, "Teste: espécie '%s' não existe." % especie)
			return
		var nivel := int(partes[1]) if partes.size() > 1 else 20
		var criatura := CreatureFactory.create(especie, nivel)
		GameManager.player.add_creature(criatura)
		GameManager.player.set_team_slot(0, criatura.uid)
		GameLog.info(GameLog.Channel.SYSTEM, "Teste: entregue %s Nv.%d." % [criatura.display_name(), nivel])
		return


func _run_intro_test() -> void:
	GameLog.info(GameLog.Channel.SYSTEM, "Teste automático: abrindo a cena de introdução.")
	GameManager.new_game("Teste", {})
	SceneFlow.goto_intro()


func _run_smoke_test() -> void:
	GameLog.info(GameLog.Channel.SYSTEM, "Teste automático: entrando direto no mundo.")
	if not GameManager.continue_game():
		GameManager.new_game("Teste", {})
		var starters := DataManager.get_starters()
		if starters.is_empty():
			GameLog.error(GameLog.Channel.SYSTEM, "Teste automático: nenhuma criatura inicial definida.")
			return
		GameManager.choose_starter((starters[0] as CreatureSpecies).id)
	_conceder_criatura_de_teste()
	GameManager.begin_session()
	# Salvar aqui faz a segunda execução com --smoke cair no continue_game(),
	# o que testa o ciclo salvar/carregar de graça.
	GameManager.save_now("teste automático")
	SceneFlow.goto_world()
