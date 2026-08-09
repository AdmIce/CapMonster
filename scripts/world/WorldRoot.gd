extends Node3D
## Root of the playable world. One generic scene serves every map: it reads the
## current map from the save, asks MapBuilder for geometry, places the
## interactables, spawns the player and the camera, and wires the HUD.
##
## Adding a third map means adding an entry to maps.json - not a new scene.

var map_id: String = ""
var map_data: Dictionary = {}

var player: PlayerController = null
var camera_rig: CameraRig = null
## O aviso do Alt sai uma vez por mapa, na primeira vez que uma câmera de mouse
## entra. Repetir a cada troca vira ruído.
var _avisou_do_cursor: bool = false
var spawner: SpawnManager = null
var autopilot: AutoPilot = null
var companion: CompanionCreature = null
var battle: BattleController = null
var presenca: PresencaOnline = null
var bosses: Array[BossEncounter] = []

var hud: HUD = null
var battle_hud: BattleHUD = null
var inventory: InventoryPanel = null
var shop: ShopPanel = null
var map_panel: MapPanel = null
var dialogue: DialoguePanel = null
var pause_menu: PauseMenu = null
var debug_menu: DebugMenu = null


func _ready() -> void:
	if not _validate_session():
		return

	map_id = GameManager.player.current_map
	map_data = DataManager.get_map(map_id)

	if GameManager.modo_servidor:
		# Servidor dedicado: só o que decide o mundo. Geometria entra porque as
		# criaturas colidem com ela; câmera, HUD, avatar e batalha ficam de fora,
		# porque não existe ninguém olhando nem lutando deste lado.
		_build_world()
		_build_interactables()
		_build_spawner()
		_build_presenca()
		GameManager.player.unlock_map(map_id)
		GameLog.info(GameLog.Channel.WORLD, "Servidor: mundo '%s' no ar." % map_id)
		return

	_build_world()
	_build_player()
	_build_camera()
	_build_interactables()
	_build_spawner()
	_build_companion()
	_build_autopilot()
	_build_battle()
	_build_presenca()
	_build_ui()

	GameManager.player.unlock_map(map_id)
	hud.show_map_banner(map_data.get("name", map_id), map_data.get("subtitle", ""))
	AudioManager.tocar_ambiente()
	QuestManager.registrar_mapa(map_id)
	GameLog.info(GameLog.Channel.WORLD, "Entrou em %s." % map_data.get("name", map_id))
	# O chat abre vazio na primeira partida e ninguém descobre que ele existe.
	Chat.sistema("Você chegou em %s. Enter abre o chat — /ajuda lista os comandos." % map_data.get("name", map_id))
	_mostrar_recompensa_offline()
	_abrir_painel_de_teste()


## `-- --abrir=loja|mochila|missoes` abre o painel já na entrada, para a
## ferramenta de captura conseguir fotografar telas que normalmente exigem
## andar até um NPC e apertar E. Só em build de debug.
func _abrir_painel_de_teste() -> void:
	if not OS.is_debug_build():
		return
	for argumento in OS.get_cmdline_user_args():
		if not argumento.begins_with("--abrir="):
			continue
		match argumento.split("=")[1]:
			"loja":
				for npc_data in map_data.get("npcs", []):
					var config: Dictionary = npc_data.get("shop", {})
					if not config.is_empty():
						shop.abrir(config)
						return
				GameLog.warn(GameLog.Channel.WORLD, "Teste: nenhum NPC com loja neste mapa.")
			"mochila":
				inventory.abrir()
			"missoes":
				inventory.abrir()
				inventory.mostrar_aba(InventoryPanel.Aba.MISSOES)
			"mapa":
				map_panel.abrir(map_data, player)
			"config":
				pause_menu.abrir_configuracoes()
			"sentar":
				player.sentar()
			"montaria":
				player.montar()
			"descanso":
				# Descansar exige andar ate a fogueira e apertar E, e um teste
				# automatico nao faz nenhum dos dois.
				var fogueira := _achar_descanso(self)
				if fogueira != null:
					fogueira.interact(player)
				else:
					GameLog.warn(GameLog.Channel.WORLD, "Teste: nenhum ponto de descanso neste mapa.")
		return


func _achar_descanso(no: Node) -> HealPoint:
	if no is HealPoint:
		return no as HealPoint
	for filho in no.get_children():
		var achado := _achar_descanso(filho)
		if achado != null:
			return achado
	return null


## Só na primeira entrada da sessão: trocar de mapa não paga idle de novo.
func _mostrar_recompensa_offline() -> void:
	if GameManager.idle_processado:
		return
	GameManager.idle_processado = true

	var resumo := IdleManager.processar_retorno(GameManager.player)
	if resumo.is_empty():
		return
	var painel := WelcomeBackPanel.new()
	painel.name = "BemVindoDeVolta"
	add_child(painel)
	painel.mostrar(resumo)


func _validate_session() -> bool:
	if not DataManager.is_loaded:
		GameLog.error(GameLog.Channel.WORLD, "Mundo carregado antes do banco de dados ficar pronto.")
		SceneFlow.goto_main_menu()
		return false
	if GameManager.player == null:
		GameLog.error(GameLog.Channel.WORLD, "Mundo carregado sem sessão ativa.")
		SceneFlow.goto_main_menu()
		return false
	if not DataManager.has_map(GameManager.player.current_map):
		GameLog.error(GameLog.Channel.WORLD, "Mapa desconhecido: '%s'." % GameManager.player.current_map)
		SceneFlow.goto_main_menu()
		return false
	return true


# --- construction -------------------------------------------------------------

func _build_world() -> void:
	MapBuilder.build_environment(self, map_data)

	# Cenário pronto num `.glb`: o chão, o terreno e os espalhados seriam
	# desenhados por cima dele. Os bloqueadores continuam, porque são as paredes
	# invisíveis declaradas no JSON e servem para fechar o que o modelo deixou
	# aberto.
	if MapBuilder.tem_modelo(map_data):
		MapBuilder.build_modelo(self, map_data)
		MapBuilder.build_blockers(self, map_data)
		return

	MapBuilder.build_ground(self, map_data)
	MapBuilder.build_terrain(self, map_data)
	MapBuilder.build_blockers(self, map_data)
	MapBuilder.build_landmarks(self, map_data)
	MapBuilder.build_tilemap(self, map_data)
	MapBuilder.build_scatter(self, map_data, _protected_points())


## Positions that scatter must keep clear so props never bury an interactable.
func _protected_points() -> Array:
	var points: Array = []
	for group in ["npcs", "heal_points", "gates"]:
		for entry in map_data.get(group, []):
			var pos: Array = entry.get("pos", [])
			if pos.size() == 2:
				points.append(Vector2(pos[0], pos[1]))
	for spawn_name in map_data.get("spawn_points", {}).keys():
		var pos: Array = map_data["spawn_points"][spawn_name]
		if pos.size() == 2:
			points.append(Vector2(pos[0], pos[1]))
	for key in ["mini_boss", "boss"]:
		var encounter: Dictionary = map_data.get(key, {})
		var pos: Array = encounter.get("pos", [])
		if pos.size() == 2:
			points.append(Vector2(pos[0], pos[1]))
	return points


func _build_player() -> void:
	player = PlayerController.new()
	player.name = "Player"
	add_child(player)
	player.apply_appearance(GameManager.player.appearance)
	player.teleport_to(_resolve_spawn_position())
	player.moved.connect(func(position: Vector2): GameManager.record_position(position))


func _resolve_spawn_position() -> Vector2:
	var data := GameManager.player
	if data.has_exact_position:
		return data.last_position
	var spawn_points: Dictionary = map_data.get("spawn_points", {})
	var key: String = data.spawn_point if spawn_points.has(data.spawn_point) else "start"
	var pos: Array = spawn_points.get(key, [0, 0])
	return Vector2(pos[0], pos[1])


## Os outros jogadores conectados. O nó existe mesmo offline: assim entrar numa
## partida no meio do jogo não precisa reconstruir o mundo.
func _build_presenca() -> void:
	presenca = PresencaOnline.criar(map_id, player)
	add_child(presenca)

	# Agora sim existe personagem. Quem conectou pelo menu se anunciou sem nome
	# nem aparência (não havia sessão ainda) e apareceu como o boneco padrão para
	# os outros; estas duas linhas corrigem o cartão e entregam a ficha.
	Rede.atualizar_cartao()
	Ficha.entrar_no_mundo()

	_rede_de_teste()
	_modelo_de_teste()


## `-- --modelo=<res://caminho>:<escala>` planta um modelo ao lado do jogador.
##
## Serve para calibrar arte nova sem abrir o editor: malha com pele tem AABB da
## pose de vínculo, que costuma vir degenerada, então "qual é a escala certa" só
## se responde comparando com o personagem em cena.
func _modelo_de_teste() -> void:
	if not OS.is_debug_build():
		return
	for argumento in OS.get_cmdline_user_args():
		if not argumento.begins_with("--modelo="):
			continue
		var valor := argumento.substr("--modelo=".length())
		var corte := valor.rfind(":")
		var caminho := valor.substr(0, corte) if corte > 6 else valor
		var escala := float(valor.substr(corte + 1)) if corte > 6 else 1.0
		if not ResourceLoader.exists(caminho):
			GameLog.error(GameLog.Channel.WORLD, "Teste: modelo '%s' não existe." % caminho)
			return

		var cena := load(caminho)
		if not (cena is PackedScene):
			GameLog.error(GameLog.Channel.WORLD, "Teste: '%s' não é uma cena." % caminho)
			return
		var no := (cena as PackedScene).instantiate() as Node3D
		if no == null:
			return
		no.name = "ModeloDeTeste"
		no.scale = Vector3.ONE * maxf(0.0001, escala)
		no.position = player.global_position + Vector3(2.5, 0, 0)
		add_child(no)
		GameLog.info(GameLog.Channel.WORLD, "Teste: '%s' plantado com escala %.3f." % [caminho, escala])
		return


## `-- --host` e `-- --entrar=<ip>` sobem a rede sozinhos na entrada do mundo.
## É o que permite testar dois clientes de verdade sem ninguém clicar em nada:
##   instância A: -- --smoke --host
##   instância B: -- --smoke --entrar=127.0.0.1
func _rede_de_teste() -> void:
	if not OS.is_debug_build():
		return
	for argumento in OS.get_cmdline_user_args():
		if argumento == "--host":
			Rede.hospedar()
			return
		if argumento.begins_with("--entrar="):
			Rede.entrar(argumento.split("=")[1])
			return


func _build_camera() -> void:
	camera_rig = CameraRig.new()
	camera_rig.name = "CameraRig"
	camera_rig.add_to_group("camera_rig")
	add_child(camera_rig)
	camera_rig.set_zoom(float(SaveManager.get_setting("camera_zoom", 1.0)))

	var bounds: Dictionary = map_data.get("bounds", {})
	camera_rig.set_bounds(
		float(bounds.get("min_x", -50)), float(bounds.get("max_x", 50)),
		float(bounds.get("min_z", -50)), float(bounds.get("max_z", 50))
	)
	# Quanto o enquadramento de cima abrange, em metros de altura de tela. Mapa
	# aberto quer os 17 padrão; um quarto de 12 m de lado, com esse valor, fica
	# uma miniatura no meio da tela cercada de vazio. Aumentar o modelo em vez
	# disso resolveria o vazio e criaria outro problema: o personagem viraria
	# formiga dentro de um quarto de gigante. Quem muda é a câmera.
	var enquadramento := float(map_data.get("camera", {}).get("tamanho", 0.0))
	if enquadramento > 0.0:
		camera_rig.orthographic_size = enquadramento

	camera_rig.follow(player, true)
	player.camera_rig = camera_rig
	camera_rig.modo_mudou.connect(_ao_mudar_camera)
	camera_rig.definir_modo(CameraRig.modo_do_id(_modo_de_camera_pedido()))


## Qual enquadramento entra. Normalmente o que ficou salvo; em build de debug,
## `-- --camera=primeira_pessoa` manda mais, para a ferramenta de captura poder
## fotografar cada um sem depender do que estava gravado na máquina.
func _modo_de_camera_pedido() -> String:
	if OS.is_debug_build():
		for argumento in OS.get_cmdline_user_args():
			if argumento.begins_with("--camera="):
				return argumento.split("=")[1]
	return String(SaveManager.get_setting(CameraRig.CHAVE_MODO, "terceira_pessoa"))


func _build_interactables() -> void:
	var container := Node3D.new()
	container.name = "Interactables"
	add_child(container)

	for npc_data in map_data.get("npcs", []):
		var npc := NpcActor.create(npc_data)
		container.add_child(npc)
		npc.dialogue_requested.connect(_on_dialogue_requested)
		npc.shop_requested.connect(_ao_pedir_loja)
		if npc.heals_team:
			npc.interacted.connect(func(_by):
				GameManager.player.heal_all()
				Notify.good("%s cuidou da sua equipe." % npc.speaker_name)
			)

	for heal_data in map_data.get("heal_points", []):
		container.add_child(HealPoint.create(heal_data))

	for gate_data in map_data.get("gates", []):
		container.add_child(MapGate.create(gate_data))

	for chave in ["mini_boss", "boss"]:
		var dados_chefe: Dictionary = map_data.get(chave, {})
		if dados_chefe.is_empty():
			continue
		var chefe := BossEncounter.create(dados_chefe, map_id, "mini" if chave == "mini_boss" else "boss")
		container.add_child(chefe)
		chefe.batalha_pedida.connect(_ao_pedir_chefe)
		bosses.append(chefe)


func _build_spawner() -> void:
	spawner = SpawnManager.new()
	spawner.name = "Spawner"
	add_child(spawner)
	spawner.setup(map_data, player)
	spawner.encounter_triggered.connect(_on_encounter)


func _build_autopilot() -> void:
	autopilot = AutoPilot.new()
	autopilot.name = "AutoPilot"
	add_child(autopilot)
	autopilot.setup(player, map_data)
	# `-- --auto` liga o modo automático já na entrada, para o smoke test headless
	# conseguir exercitar a navegação sem ninguém clicar no botão.
	if OS.is_debug_build() and OS.get_cmdline_user_args().has("--auto"):
		autopilot.set_enabled(true)


func _build_companion() -> void:
	companion = CompanionCreature.new()
	companion.name = "Mascote"
	add_child(companion)
	companion.definir_enquadramento(camera_rig.modo == CameraRig.Modo.TERCEIRA_PESSOA)
	companion.seguir(player)
	_atualizar_mascote()
	# A líder pode mudar pelo inventário, por captura ou por derrota.
	GameManager.player.team_changed.connect(_atualizar_mascote)


## Mantém o mascote sincronizado com o slot 1 da equipe.
func _atualizar_mascote() -> void:
	if companion == null or not is_instance_valid(companion):
		return
	var equipe := GameManager.player.team()
	var lider: CreatureData = equipe[0] if not equipe.is_empty() else null
	if companion.criatura == lider:
		return
	companion.definir_criatura(lider)


func _build_battle() -> void:
	battle = BattleController.new()
	battle.name = "Batalha"
	add_child(battle)
	battle.setup(player, camera_rig)
	battle.batalha_iniciada.connect(_ao_iniciar_batalha)
	battle.batalha_encerrada.connect(_ao_encerrar_batalha)


func _build_ui() -> void:
	hud = HUD.new()
	hud.name = "HUD"
	add_child(hud)
	hud.bind(GameManager.player, player)
	hud.bind_autopilot(autopilot)

	battle_hud = BattleHUD.new()
	battle_hud.name = "BattleHUD"
	add_child(battle_hud)
	battle_hud.bind(battle)

	inventory = InventoryPanel.new()
	inventory.name = "Inventario"
	add_child(inventory)
	inventory.criatura_invocada.connect(func(_c): _atualizar_mascote())
	hud.bind_inventory(inventory)

	shop = ShopPanel.new()
	shop.name = "Loja"
	add_child(shop)
	shop.fechado.connect(func(): player.revalidate_target())

	map_panel = MapPanel.new()
	map_panel.name = "Mapa"
	add_child(map_panel)
	# O HUD sai de cena enquanto o mapa grande está aberto: com ele por baixo, o
	# painel de status e o minimapa apareciam através do escurecimento.
	map_panel.aberto.connect(func(): hud.visible = false)
	map_panel.fechado.connect(func():
		hud.visible = true
		player.revalidate_target()
	)

	dialogue = DialoguePanel.new()
	dialogue.name = "Dialogue"
	add_child(dialogue)
	dialogue.finished.connect(_on_dialogue_finished)

	pause_menu = PauseMenu.new()
	pause_menu.name = "PauseMenu"
	add_child(pause_menu)

	if OS.is_debug_build():
		debug_menu = DebugMenu.new()
		debug_menu.name = "DebugMenu"
		add_child(debug_menu)


# --- events -------------------------------------------------------------------

func _on_dialogue_requested(speaker: String, lines: Array) -> void:
	if dialogue.is_open():
		return
	player.input_enabled = false
	hud.set_prompt("")
	dialogue.open(speaker, lines)


func _ao_pedir_loja(config: Dictionary) -> void:
	if battle.em_batalha or dialogue.is_open() or shop.esta_aberto():
		return
	hud.set_prompt("")
	shop.abrir(config)


func _on_dialogue_finished() -> void:
	player.input_enabled = true
	player.revalidate_target()


## Ponto de entrada do combate: encostar numa criatura selvagem abre a batalha
## ali mesmo, no lugar do encontro.
func _on_encounter(creature: WildCreature) -> void:
	if dialogue.is_open() or pause_menu.is_open() or battle.em_batalha:
		return
	if inventory != null and inventory.esta_aberto():
		return
	# O modo automático também aciona as habilidades do líder.
	battle.auto_habilidades = autopilot != null and autopilot.is_enabled()
	battle.iniciar([creature.data], creature.global_position, creature)


func _ao_iniciar_batalha(_aliados: Array, _inimigos: Array) -> void:
	hud.set_prompt("")
	# O resto do mapa para de correr atrás do jogador durante a luta.
	for outra in get_tree().get_nodes_in_group("wild_creature"):
		if outra is WildCreature:
			(outra as WildCreature).congelar(true)


func _ao_pedir_chefe(encontro: Dictionary, tier: String) -> void:
	if battle.em_batalha:
		return
	battle.auto_habilidades = autopilot != null and autopilot.is_enabled()
	battle.iniciar_chefe(encontro, map_id, tier)


func _ao_encerrar_batalha(vitoria: bool, resumo: Dictionary) -> void:
	for outra in get_tree().get_nodes_in_group("wild_creature"):
		if outra is WildCreature:
			(outra as WildCreature).congelar(false)
	_atualizar_mascote()
	for chefe in bosses:
		if is_instance_valid(chefe):
			chefe.atualizar_estado()
	player.revalidate_target()

	if not vitoria and not bool(resumo.get("fuga", false)):
		_voltar_ao_ponto_de_cura()


## Derrota: volta para o último acampamento usado neste mapa, ou para a entrada.
func _voltar_ao_ponto_de_cura() -> void:
	var pontos: Array = map_data.get("heal_points", [])
	var destino := _resolve_spawn_position()
	var preferido := String(GameManager.player.get_flag("last_heal_point", ""))
	for ponto in pontos:
		var pos: Array = ponto.get("pos", [])
		if pos.size() != 2:
			continue
		if preferido == "" or String(ponto.get("id", "")) == preferido:
			destino = Vector2(pos[0], pos[1])
			if preferido != "":
				break
	player.teleport_to(destino + Vector2(1.5, 1.5))
	camera_rig.follow(player, true)
	_atualizar_mascote()
	if companion != null:
		companion.seguir(player)


## Reage à troca de enquadramento, venha ela da tecla C, do painel de
## configurações ou da batalha. Só o lado visível: quem salva a escolha é quem
## atendeu o jogador.
func _ao_mudar_camera(_novo: CameraRig.Modo) -> void:
	if companion != null:
		companion.definir_enquadramento(camera_rig.modo != CameraRig.Modo.ISOMETRICA)
	# Em primeira pessoa a câmera está dentro da cabeça: o que apareceria é o
	# miolo do modelo, que é um borrão que tapa a tela inteira.
	if player != null and player.avatar != null:
		player.avatar.visible = not camera_rig.esconde_personagem()

	# Avisar não é enfeite: o cursor sumir sem explicação é indistinguível de o
	# jogo ter travado, e a HUD toda depende de clique. Só ao **entrar** num
	# enquadramento de mouse, para não repetir a cada batalha.
	if camera_rig.usa_mouse() and not _avisou_do_cursor:
		_avisou_do_cursor = true
		Notify.show_message("Segure Alt para soltar o cursor e usar a interface.")

	_atualizar_mouse()


## O mouse fica preso só quando a câmera precisa dele **e** não há nada na tela
## para clicar ou ler. Um painel aberto com o cursor preso é um painel que não
## dá para usar.
func _atualizar_mouse() -> void:
	var precisa := camera_rig != null and camera_rig.usa_mouse() \
		and not _interface_na_frente() \
		and not Input.is_action_pressed("cursor")
	var desejado := Input.MOUSE_MODE_CAPTURED if precisa else Input.MOUSE_MODE_VISIBLE
	if Input.mouse_mode != desejado:
		Input.mouse_mode = desejado


## Cada painel é testado contra `null` porque `_process` já está rodando
## enquanto o mundo se monta, e volta a rodar enquanto ele se desfaz: nas duas
## pontas há quadros em que metade da interface ainda não existe.
func _interface_na_frente() -> bool:
	if battle != null and battle.em_batalha:
		return true
	if dialogue != null and dialogue.is_open():
		return true
	if pause_menu != null and pause_menu.is_open():
		return true
	if shop != null and shop.esta_aberto():
		return true
	if inventory != null and inventory.esta_aberto():
		return true
	if map_panel != null and map_panel.visible:
		return true
	return hud != null and hud.chat_aberto()


func _process(_delta: float) -> void:
	# Todo quadro, e não só na troca de painel: painel é aberto e fechado de
	# muitos lugares (tecla, clique, fim de diálogo, fim de batalha), e um deles
	# esquecido deixaria o cursor preso sem jeito de soltar.
	_atualizar_mouse()


func _unhandled_input(event: InputEvent) -> void:
	# Olhar com o mouse, nos enquadramentos que usam mouse. Antes de tudo: é o
	# evento mais frequente do jogo e não combina com nenhuma ação de tecla.
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		camera_rig.girar_com_mouse((event as InputEventMouseMotion).relative)
		return

	if event.is_action_pressed("map"):
		# Mapa não abre no meio da batalha nem por cima de outro painel.
		if not battle.em_batalha and not dialogue.is_open() and not shop.esta_aberto() \
				and not inventory.esta_aberto():
			map_panel.alternar(map_data, player)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("inventory"):
		# Durante a batalha a mochila fica fechada: os itens de combate estão nos
		# botões do BattleHUD.
		if not battle.em_batalha and not dialogue.is_open() and not shop.esta_aberto():
			inventory.alternar()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("cancel"):
		if dialogue.is_open():
			dialogue.close()
		elif shop.esta_aberto():
			shop.fechar()
		elif inventory.esta_aberto():
			inventory.fechar()
		elif not battle.em_batalha:
			pause_menu.toggle()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_camera"):
		camera_rig.alternar_modo()
		# Salvar aqui, e não no sinal: a batalha também troca o enquadramento, e
		# gravar lá apagaria a escolha do jogador a cada luta.
		SaveManager.set_setting(CameraRig.CHAVE_MODO, camera_rig.id_do_modo())
		Notify.show_message("Câmera: %s" % camera_rig.config()["rotulo"])
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_debug") and debug_menu != null:
		debug_menu.toggle()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("quick_save"):
		GameManager.record_position(player.plane_position())
		GameManager.save_now("salvamento rápido")
		Notify.good("Progresso salvo.")
		get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	# Sair do mundo com o cursor preso deixaria o menu inutilizável: `_process`
	# não roda mais para soltá-lo.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	# Leaving the world keeps the exact position so returning puts the player
	# back on the same spot. Skipped when the player is mid-travel: the
	# destination map already chose its own spawn point.
	if GameManager.player == null or player == null or not is_instance_valid(player):
		return
	if GameManager.player.current_map != map_id:
		return
	GameManager.record_position(player.plane_position())
