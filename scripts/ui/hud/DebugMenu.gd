class_name DebugMenu
extends CanvasLayer
## Developer tools, F1. Only instantiated when OS.is_debug_build() is true, so
## it cannot ship in a release export.
##
## Every action here calls the same public API the game uses - no shortcuts into
## private state - which means the debug menu also serves as a smoke test of
## those APIs.

const PANEL_WIDTH := 340

var _panel: Control = null
var _species_picker: OptionButton = null
var _level_spin: SpinBox = null
var _map_picker: OptionButton = null
var _player_level_spin: SpinBox = null
var _status: Label = null
var _obtainable: Array = []


func _ready() -> void:
	layer = 80
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	visible = false


func toggle() -> void:
	visible = not visible
	if visible:
		_refresh_status()


func _build() -> void:
	_panel = Control.new()
	# RIGHT_WIDE anchors to the full height of the right edge; TOP_RIGHT would
	# collapse the panel to zero height.
	_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	_panel.offset_left = -PANEL_WIDTH - Design.S_LG
	_panel.offset_right = -Design.S_LG
	_panel.offset_top = Design.S_LG
	_panel.offset_bottom = -Design.S_LG
	add_child(_panel)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(scroll)

	var card := Design.panel(Color(0.043, 0.055, 0.067, 0.96))
	Responsivo.largura(card, PANEL_WIDTH, 0.34)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(card)

	var column := Design.vbox(Design.S_SM)
	card.add_child(column)

	column.add_child(Design.heading("Debug  ·  F1"))
	_status = Design.caption("")
	column.add_child(_status)
	column.add_child(Design.divider())

	# --- economy
	column.add_child(Design.label("ECONOMIA", Design.FS_CAPTION, Design.TEXT_DIM))
	column.add_child(_action("+1000 de ouro", func():
		GameManager.player.add_gold(1000)
		_toast("+1000 de ouro")
	))
	column.add_child(_action("+500 de XP de treinador", func():
		var gained := GameManager.player.grant_xp(500)
		_toast("+500 XP (%d nível(is) ganho(s))" % gained)
	))

	var level_row := Design.hbox(Design.S_SM)
	_player_level_spin = _spin(1, 99, 1)
	_player_level_spin.value = 1
	level_row.add_child(_player_level_spin)
	var apply_level := Design.button("Definir nível")
	apply_level.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	apply_level.pressed.connect(func():
		var player := GameManager.player
		player.level = clampi(int(_player_level_spin.value), 1, DataManager.progression.player_max_level)
		player.xp = 0
		player.level_changed.emit(player.level)
		player.xp_changed.emit(0, player.xp_to_next_level())
		_toast("Nível do treinador definido para %d" % player.level)
	)
	level_row.add_child(apply_level)
	column.add_child(level_row)

	column.add_child(Design.divider())

	# --- creatures
	column.add_child(Design.label("CRIATURAS", Design.FS_CAPTION, Design.TEXT_DIM))
	_species_picker = OptionButton.new()
	_species_picker.custom_minimum_size = Vector2(0, 34)
	for species in DataManager.all_species():
		if species.is_obtainable:
			_obtainable.append(species)
	_obtainable.sort_custom(func(a, b): return a.name < b.name)
	for species in _obtainable:
		_species_picker.add_item("%s (%s)" % [species.name, species.rarity])
	column.add_child(_species_picker)

	var give_row := Design.hbox(Design.S_SM)
	_level_spin = _spin(1, DataManager.progression.creature_max_level, 5)
	give_row.add_child(_level_spin)
	var give := Design.button("Dar criatura")
	give.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	give.pressed.connect(_on_give_creature)
	give_row.add_child(give)
	column.add_child(give_row)

	column.add_child(_action("Curar equipe", func():
		GameManager.player.heal_all()
		_toast("Equipe curada")
	))
	column.add_child(_action("Tirar 30% da vida", func():
		for creature in GameManager.player.team():
			creature.apply_damage(int(creature.max_hp() * 0.3))
		_toast("Equipe danificada")
	))
	column.add_child(_action("Evoluir quem já pode", func():
		var count := 0
		for creature in GameManager.player.collection:
			if creature.can_evolve() and creature.evolve():
				count += 1
		_toast("%d criatura(s) evoluíram" % count)
	))

	column.add_child(Design.divider())

	# --- world
	column.add_child(Design.label("MUNDO", Design.FS_CAPTION, Design.TEXT_DIM))
	_map_picker = OptionButton.new()
	_map_picker.custom_minimum_size = Vector2(0, 34)
	for map_id in DataManager.map_ids():
		_map_picker.add_item(DataManager.get_map_name(map_id))
	column.add_child(_map_picker)

	column.add_child(_action("Viajar para o mapa selecionado", func():
		var ids := DataManager.map_ids()
		var index := clampi(_map_picker.selected, 0, ids.size() - 1)
		GameManager.travel_to_map(ids[index], "start")
	))
	column.add_child(_action("Liberar todos os mapas", func():
		for map_id in DataManager.map_ids():
			GameManager.player.unlock_map(map_id)
		_toast("Todos os mapas liberados")
	))
	column.add_child(_action("Marcar chefes deste mapa como derrotados", func():
		var map_id := GameManager.player.current_map
		GameManager.player.mark_mini_boss_defeated(map_id)
		GameManager.player.mark_boss_defeated(map_id)
		for node in get_tree().get_nodes_in_group("player_controller"):
			if node is PlayerController:
				(node as PlayerController).revalidate_target()
		_toast("Chefes de %s marcados como derrotados" % DataManager.get_map_name(map_id))
	))
	column.add_child(_action("Puxar a criatura mais próxima", func():
		_force_encounter()
	))

	column.add_child(Design.divider())

	# --- save
	column.add_child(Design.label("SAVE", Design.FS_CAPTION, Design.TEXT_DIM))
	column.add_child(_action("Salvar agora", func():
		GameManager.save_now("debug")
		_toast("Salvo")
	))
	column.add_child(_action("Apagar save e voltar ao título", func():
		SaveManager.delete_save()
		GameManager.end_session(false)
		SceneFlow.goto_main_menu()
	))

	column.add_child(Design.divider())
	column.add_child(Design.caption(
		"Ferramentas de combate, captura, inventário e missões aparecem aqui conforme esses sistemas entram."
	))


func _action(text: String, callback: Callable) -> Button:
	var button := Design.button(text)
	button.pressed.connect(func():
		if GameManager.player == null:
			_toast("Sem sessão ativa")
			return
		callback.call()
		_refresh_status()
	)
	return button


func _spin(low: float, high: float, value: float) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = low
	spin.max_value = high
	spin.value = value
	spin.custom_minimum_size = Vector2(84, 34)
	return spin


func _on_give_creature() -> void:
	if GameManager.player == null or _obtainable.is_empty():
		return
	var index := clampi(_species_picker.selected, 0, _obtainable.size() - 1)
	var species: CreatureSpecies = _obtainable[index]
	var creature := CreatureFactory.create(species.id, int(_level_spin.value))
	if creature == null:
		return
	GameManager.player.add_creature(creature)
	_toast("Adicionado %s Nv.%d" % [creature.display_name(), creature.level])
	_refresh_status()


func _force_encounter() -> void:
	var creatures := get_tree().get_nodes_in_group("wild_creature")
	if creatures.is_empty():
		_toast("Nenhuma criatura selvagem por perto")
		return
	var players := get_tree().get_nodes_in_group("player_controller")
	if players.is_empty():
		return
	var origin: Vector3 = (players[0] as Node3D).global_position
	var best: Node3D = null
	var best_distance := INF
	for creature in creatures:
		var distance: float = origin.distance_squared_to((creature as Node3D).global_position)
		if distance < best_distance:
			best_distance = distance
			best = creature
	if best != null:
		(best as Node3D).global_position = origin + Vector3(1.0, 0, 1.0)
		_toast("%s foi puxado até você" % (best as WildCreature).data.display_name())


func _refresh_status() -> void:
	var player := GameManager.player
	if player == null:
		_status.text = "sem sessão ativa"
		return
	_status.text = "%s  Nv.%d  %d ouro  ·  %d criatura(s), %d na equipe" % [
		player.display_name, player.level, player.gold, player.collection_size(), player.team_uids.size()
	]


func _toast(message: String) -> void:
	Notify.show_message(message)
	GameLog.info(GameLog.Channel.SYSTEM, "[debug] %s" % message)
