extends Control
## Seleção de personagem: um card por slot ocupado do save, com a opção de
## continuar um deles ou criar um novo. É o destino do botão "Jogar" do menu.
##
## O card mais recentemente jogado vem em destaque, para quem voltou ao jogo
## reconhecer o próprio personagem sem ter de ler os detalhes de todo mundo.

const LARGURA_CARD := 300.0
const MAX_COLUNAS := 3

var _grade: GridContainer = null
var _aviso: Label = null
var _criar: Button = null
var _botoes_jogar: Array[Button] = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	Design.screen_root(self)
	_build()
	# O menu já segura os botões de jogar até conectar, mas a tela também abre em
	# teste sem rede; repetir a trava aqui evita "entrar no mundo" no ar.
	Rede.estado_mudou.connect(_atualizar_rede)


func _build() -> void:
	var margin := Design.margin(Design.S_XL)
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(margin)

	var column := Design.vbox(Design.S_LG)
	margin.add_child(column)

	var header := Design.vbox(Design.S_XS)
	header.add_child(Design.label("QUEM VAI JOGAR?", Design.FS_LABEL, Design.ACCENT))
	header.add_child(Design.heading("Selecione um personagem", Design.FS_TITLE, Design.TEXT_CLARO))
	column.add_child(header)

	var rolagem := ScrollContainer.new()
	rolagem.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rolagem.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rolagem.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(rolagem)

	var conteudo := Design.vbox(Design.S_MD)
	conteudo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rolagem.add_child(conteudo)

	_grade = GridContainer.new()
	_grade.add_theme_constant_override("h_separation", Design.S_MD)
	_grade.add_theme_constant_override("v_separation", Design.S_MD)
	_grade.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	conteudo.add_child(_grade)

	_aviso = Design.body("", Design.TEXT_CLARO_DIM)
	conteudo.add_child(_aviso)

	var footer := Design.hbox(Design.S_MD)
	footer.size_flags_vertical = Control.SIZE_SHRINK_END
	column.add_child(footer)

	var back := Design.button("Voltar", "ghost")
	back.pressed.connect(func(): SceneFlow.goto_main_menu())
	footer.add_child(back)

	footer.add_child(Design.expander())

	_criar = Design.button("Criar personagem", "primary")
	_criar.custom_minimum_size = Vector2(200, 44)
	_criar.pressed.connect(_on_criar)
	footer.add_child(_criar)

	_redesenhar()


func _redesenhar() -> void:
	for filho in _grade.get_children():
		_grade.remove_child(filho)
		filho.queue_free()
	_botoes_jogar.clear()

	var slots := SaveManager.save_slots()
	var liberado := SaveManager.free_slot()

	if slots.is_empty():
		_aviso.text = "Nenhum personagem aqui ainda. Crie o primeiro."
		_aviso.visible = true
	elif liberado < 0:
		_aviso.text = "Máximo de %d personagens atingido. Apague um para criar outro." % SaveManager.MAX_SLOTS
		_aviso.visible = true
	else:
		_aviso.visible = false

	# O slot mais recente entra destacado para o jogador reconhecer onde estava.
	var mais_recente := 0
	for meta in slots:
		mais_recente = maxi(mais_recente, int(meta.get("saved_at", 0)))

	_grade.columns = Responsivo.colunas(
		Responsivo.tela(self).x - Design.S_XL * 2, LARGURA_CARD, Design.S_MD, MAX_COLUNAS
	)
	for meta in slots:
		_grade.add_child(_cartao(int(meta.get("slot", 0)), meta, int(meta.get("saved_at", 0)) >= mais_recente))

	# Slots cheios: o botão de criar não mente, ele some.
	_criar.visible = liberado >= 0
	_atualizar_rede()


func _cartao(slot: int, meta: Dictionary, recente: bool) -> Control:
	var cartao := Design.card(Design.ACCENT if recente else Design.TEXT_MUTED, recente)
	cartao.custom_minimum_size = Vector2(LARGURA_CARD, 0)
	cartao.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var coluna := Design.vbox(Design.S_SM)
	cartao.add_child(coluna)

	var nome := Design.heading(String(meta.get("name", "Treinador")), Design.FS_HEADING, Design.TEXT)
	nome.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nome.add_theme_constant_override("line_spacing", -2)
	coluna.add_child(nome)

	if recente:
		coluna.add_child(Design.chip("último", Design.ACCENT))

	var mapa := DataManager.get_map_name(String(meta.get("map", "")))
	if mapa == "":
		mapa = "primeiro mapa"
	var minutos := int(float(meta.get("playtime", 0.0)) / 60.0)
	coluna.add_child(Design.label(
		"Nv.%d  ·  %s  ·  %d min" % [int(meta.get("level", 1)), mapa, minutos],
		Design.FS_BODY, Design.TEXT_MUTED
	))
	coluna.add_child(Design.caption("%d criatura(s)" % int(meta.get("creatures", 0))))

	coluna.add_child(Design.spacer(Design.S_SM))

	var botoes := Design.hbox(Design.S_SM)
	coluna.add_child(botoes)

	var jogar := Design.button("Jogar", "primary")
	jogar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	jogar.focus_mode = Control.FOCUS_NONE
	jogar.pressed.connect(func(): _jogar(slot))
	botoes.add_child(jogar)
	_botoes_jogar.append(jogar)

	var apagar := Design.button("Apagar", "danger")
	apagar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	apagar.focus_mode = Control.FOCUS_NONE
	apagar.pressed.connect(func(): _confirmar_apagar(slot, String(meta.get("name", "Treinador"))))
	botoes.add_child(apagar)

	return cartao


func _pode_jogar() -> bool:
	return not Rede.tem_servidor_oficial() or Rede.online()


func _atualizar_rede() -> void:
	for botao in _botoes_jogar:
		if is_instance_valid(botao):
			botao.disabled = not _pode_jogar()


# --- ações --------------------------------------------------------------------

func _jogar(slot: int) -> void:
	if not _pode_jogar():
		return
	if not GameManager.continue_game(slot):
		Notify.bad("Não foi possível ler esse save.")
		_redesenhar()
		return
	GameManager.begin_session()
	SceneFlow.goto_world()


func _on_criar() -> void:
	if SaveManager.free_slot() < 0:
		return
	SceneFlow.goto_character_creation()


func _confirmar_apagar(slot: int, nome: String) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Apagar %s?" % nome
	dialog.dialog_text = "Todo o progresso deste personagem será perdido."
	dialog.ok_button_text = "Apagar"
	dialog.cancel_button_text = "Manter"
	add_child(dialog)
	dialog.confirmed.connect(func():
		if SaveManager.delete_save(slot):
			Notify.good("%s foi apagado." % nome)
			_redesenhar()
		else:
			Notify.bad("Não consegui apagar esse personagem.")
	)
	dialog.popup_centered()