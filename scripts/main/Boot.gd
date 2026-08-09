extends Control
## Primeira cena. Confere se o banco de dados JSON carregou, mostra a logo por um
## instante e passa para o menu principal. Se os dados falharem, ela diz isso em
## vez de jogar o jogador num mundo quebrado.

const MINIMUM_SPLASH_SECONDS := 0.9

## Quadros por segundo do servidor dedicado.
const SERVIDOR_QUADROS := 30

## Carregado por caminho, não por class_name: assim funciona mesmo com o editor
## ainda sem ter reindexado as classes.
const SNAPSHOT_SCRIPT := preload("res://scripts/core/Snapshot.gd")

var _status: Label = null


func _ready() -> void:
	# `set_anchors_and_offsets_preset`, e nao `set_anchors_preset`: o segundo
	# **preserva o retangulo atual** ajustando os offsets. Chamado aqui, com o no
	# ja na arvore e ainda com tamanho zero, ele grava o zero para sempre -- foi
	# o que deixou o painel de configuracoes encolhido no canto da tela.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
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

	# Servidor dedicado. Fora do bloco de depuração de propósito: isto precisa
	# funcionar no build final, que é o que roda na VPS.
	if OS.get_cmdline_user_args().has("--servidor"):
		_subir_servidor()
		return

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
		if args.has("--smoke-selecao"):
			SceneFlow.goto_character_select()
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


## Sobe o mundo sem cliente:
##
##   CapMonster --headless -- --servidor [--mapa=greenvale] [--porta=24565]
##
## O `PlayerData` criado aqui não é personagem de ninguém — ele existe porque o
## mundo lê o mapa atual dele para saber o que construir. As fichas de verdade
## são as dos jogadores que conectarem, guardadas pelo `Ficha` em `user://mundo/`.
func _subir_servidor() -> void:
	var mapa := "greenvale"
	var porta := Rede.PORTA_PADRAO
	for argumento in OS.get_cmdline_user_args():
		if argumento.begins_with("--mapa="):
			mapa = argumento.substr("--mapa=".length())
		elif argumento.begins_with("--porta="):
			porta = int(argumento.substr("--porta=".length()))

	if not DataManager.has_map(mapa):
		GameLog.error(GameLog.Channel.SYSTEM, "Servidor: mapa '%s' não existe." % mapa)
		get_tree().quit(1)
		return

	# O servidor não desenha nada, então rodar o mundo a 60 Hz é queimar CPU à
	# toa: as posições viajam a 15 Hz e as criaturas andam devagar. A 30 Hz o
	# consumo cai pela metade, o que num VPS de um núcleo é a diferença entre
	# ocupá-lo e não sentir.
	Engine.max_fps = SERVIDOR_QUADROS
	Engine.physics_ticks_per_second = SERVIDOR_QUADROS

	GameManager.modo_servidor = true
	if GameManager.new_game("Servidor", {}) == null:
		# Servidor numa máquina com slots cheios: sem jogador local não há mundo
		# a construir, então valhtar a porta não adianta.
		GameLog.error(GameLog.Channel.SYSTEM, "Servidor: nenhum slot de personagem livre.")
		get_tree().quit(1)
		return
	GameManager.player.current_map = mapa
	GameManager.player.has_exact_position = false

	if not Rede.hospedar(porta):
		GameLog.error(GameLog.Channel.SYSTEM, "Servidor: %s" % Rede.erro)
		get_tree().quit(1)
		return

	GameLog.info(GameLog.Channel.SYSTEM, "Servidor dedicado: mapa '%s', porta %d." % [mapa, porta])
	SceneFlow.goto_world()


func _run_intro_test() -> void:
	GameLog.info(GameLog.Channel.SYSTEM, "Teste automático: abrindo a cena de introdução.")
	GameManager.new_game("Teste", {})
	SceneFlow.goto_intro()


## `-- --mapa=<id>` no teste automatico entra pelo mapa pedido em vez do que
## estava salvo. Sem isto, fotografar um mapa novo dependia de andar ate ele.
func _mapa_de_teste() -> void:
	for argumento in OS.get_cmdline_user_args():
		if not argumento.begins_with("--mapa="):
			continue
		var id := argumento.substr("--mapa=".length())
		if not DataManager.has_map(id):
			GameLog.warn(GameLog.Channel.SYSTEM, "Teste: mapa '%s' nao existe." % id)
			return
		GameManager.player.current_map = id
		GameManager.player.spawn_point = "start"
		# Sem isto o jogador nasceria na coordenada que tinha no mapa anterior,
		# que no mapa novo pode ser dentro de uma parede.
		GameManager.player.has_exact_position = false
		GameManager.player.unlock_map(id)
		return


## `-- --personagem=<indice>` troca o corpo antes de entrar no mundo. Serve para
## conferir animacao que so existe em parte dos modelos -- os KayKit sabem
## sentar, os Kenney nao -- sem depender de qual personagem estava salvo.
func _personagem_de_teste() -> void:
	for argumento in OS.get_cmdline_user_args():
		if not argumento.begins_with("--personagem="):
			continue
		var indice := int(argumento.substr("--personagem=".length()))
		var aparencia := GameManager.player.appearance.duplicate()
		aparencia["body"] = indice
		GameManager.player.appearance = aparencia
		GameLog.info(GameLog.Channel.SYSTEM, "Teste: corpo %d." % indice)
		return


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
	_mapa_de_teste()
	_personagem_de_teste()
	GameManager.begin_session()
	# Salvar aqui faz a segunda execução com --smoke cair no continue_game(),
	# o que testa o ciclo salvar/carregar de graça.
	GameManager.save_now("teste automático")
	SceneFlow.goto_world()
