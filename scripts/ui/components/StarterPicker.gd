class_name StarterPicker
extends Control
## Painel de escolha da criatura inicial.
##
## Os três cartões são gerados a partir das espécies marcadas com
## `"starter": true` em creatures.json - trocar o trio é edição de dados.
## Não desenha modelo 3D: na cena de abertura as criaturas já estão nos pedestais,
## e repetir o mesmo modelo dentro do cartão só polui.
##
## Os números mostrados saem do mesmo cálculo que o combate vai usar, no nível em
## que a criatura é entregue.

signal selection_changed(index: int, species: CreatureSpecies)
signal chosen(species: CreatureSpecies)

const STARTER_LEVEL := 5

var species_list: Array = []

var _cards: Array[Control] = []
var _selected: int = -1
var _confirm: Button = null
var _detail: Label = null


func _ready() -> void:
	species_list = DataManager.get_starters()
	_build()
	if not species_list.is_empty():
		select(0)


func _build() -> void:
	var card := Design.panel(Color(0.043, 0.055, 0.067, 0.94))
	card.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(card)

	var column := Design.vbox(Design.S_SM)
	card.add_child(column)

	var row := Design.hbox(Design.S_MD)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(row)

	for i in species_list.size():
		var index := i
		var entry := _build_card(species_list[i], index)
		row.add_child(entry)
		_cards.append(entry)

	var footer := Design.hbox(Design.S_MD)
	column.add_child(footer)

	_detail = Design.body("")
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(_detail)

	_confirm = Design.button("Ficar com esta", "primary")
	_confirm.custom_minimum_size = Vector2(220, 44)
	_confirm.pressed.connect(_on_confirm)
	footer.add_child(_confirm)


func _build_card(species: CreatureSpecies, index: int) -> Control:
	var button := Button.new()
	button.flat = true
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.size_flags_vertical = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_ALL
	button.pressed.connect(func(): select(index))

	var frame := Design.panel(Design.SURFACE)
	frame.name = "Moldura"
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	button.add_child(frame)

	var column := Design.vbox(Design.S_XS)
	frame.add_child(column)

	var header := Design.hbox(Design.S_SM)
	var name_label := Design.label(species.name, Design.FS_HEADING, Design.TEXT, true)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(name_label)
	header.add_child(Design.chip(DataManager.get_role_name(species.role), Design.TEXT_MUTED))
	column.add_child(header)

	var chips := Design.hbox(Design.S_SM)
	chips.add_child(Design.chip(
		DataManager.get_element_name(species.element), DataManager.get_element_color(species.element)
	))
	chips.add_child(Design.chip(
		DataManager.get_rarity_name(species.rarity), DataManager.get_rarity_color(species.rarity)
	))
	column.add_child(chips)

	column.add_child(Design.divider())

	var sample := CreatureData.new(species.id, STARTER_LEVEL)
	var stats := Design.hbox(Design.S_MD)
	stats.add_child(_stat_block("VIDA", sample.max_hp()))
	stats.add_child(_stat_block("ATQ", sample.attack()))
	stats.add_child(_stat_block("DEF", sample.defense()))
	stats.add_child(_stat_block("VEL", sample.speed()))
	column.add_child(stats)

	column.add_child(Design.divider())

	for skill_id in species.skills:
		var skill := DataManager.get_skill(skill_id)
		if skill.is_empty():
			continue
		var skill_row := Design.hbox(Design.S_SM)
		var skill_name := Design.label(skill.get("name", skill_id), Design.FS_LABEL, Design.TEXT)
		skill_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		skill_row.add_child(skill_name)
		skill_row.add_child(Design.caption("%s · %.0fs" % [
			DataManager.get_skill_kind_name(skill.get("kind", "")), float(skill.get("cooldown", 0))
		]))
		column.add_child(skill_row)

	Design.ignore_mouse(frame)
	return button


func _stat_block(label_text: String, value: int) -> Control:
	var block := Design.vbox(0)
	block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var caption := Design.label(label_text, Design.FS_CAPTION, Design.TEXT_DIM)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	block.add_child(caption)
	var number := Design.label(str(value), Design.FS_BODY, Design.TEXT)
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	block.add_child(number)
	return block


func select(index: int) -> void:
	if index < 0 or index >= species_list.size():
		return
	_selected = index
	for i in _cards.size():
		var frame: PanelContainer = _cards[i].get_node("Moldura")
		var is_selected := i == index
		frame.add_theme_stylebox_override(
			"panel",
			Design.card_style(Design.ACCENT if is_selected else Design.TEXT_MUTED, is_selected)
		)
	var species: CreatureSpecies = species_list[index]
	_detail.text = species.description
	_confirm.text = "Ficar com %s" % species.name
	selection_changed.emit(index, species)


func selected_species() -> CreatureSpecies:
	if _selected < 0 or _selected >= species_list.size():
		return null
	return species_list[_selected]


func _on_confirm() -> void:
	var species := selected_species()
	if species == null:
		return
	_confirm.disabled = true
	chosen.emit(species)
