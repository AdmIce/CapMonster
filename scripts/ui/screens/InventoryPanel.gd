class_name InventoryPanel
extends CanvasLayer
## Mochila, equipe e coleção, na tecla I.
##
## Três abas à esquerda e um painel de detalhe à direita:
##   EQUIPE    - os três slots, com trocar de posição, tirar e definir líder.
##   CRIATURAS - a coleção inteira; clicar seleciona, o detalhe mostra tudo.
##   ITENS     - clicar num consumível usa de verdade.
##
## O detalhe mostra modelo 3D, atributos calculados, as duas habilidades com
## descrição e o botão de evoluir quando a criatura já tem nível. Nada aqui é
## enfeite: todo botão faz alguma coisa ou explica por que não pode.

signal fechado()
signal criatura_invocada(criatura: CreatureData)

enum Aba { EQUIPE, CRIATURAS, ITENS, MISSOES }

## Largura de projeto de um cartao da grade. O numero de colunas sai de uma
## divisao pelo espaco que sobra, nao de uma constante: em janela estreita a
## grade vira duas ou uma coluna em vez de espremer tres.
const LARGURA_CARD := 182
const MAX_COLUNAS := 6
const LARGURA_DETALHE := 330

var _aba: Aba = Aba.EQUIPE
var _selecionada: CreatureData = null

var _botoes_aba: Dictionary = {}
var _conteudo: VBoxContainer = null
var _detalhe: VBoxContainer = null
var _painel_detalhe: PanelContainer = null
var _rodape: Label = null
var _resumo: Label = null


func _ready() -> void:
	layer = 45
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	visible = false
	get_viewport().size_changed.connect(_ao_redimensionar)


## A grade e montada com o numero de colunas que cabe agora; se a janela muda
## com o painel aberto, o desenho anterior fica com colunas demais e corta.
func _ao_redimensionar() -> void:
	if visible:
		_redesenhar()


func alternar() -> void:
	if visible:
		fechar()
	else:
		abrir()


func abrir() -> void:
	visible = true
	get_tree().paused = true
	AudioManager.tocar_ui(&"ui_alternar")
	_redesenhar()


func fechar() -> void:
	visible = false
	get_tree().paused = false
	AudioManager.tocar_ui(&"ui_alternar")
	fechado.emit()


func esta_aberto() -> bool:
	return visible


## Abre numa aba específica (usado pelo menu de pausa e pelas capturas de teste).
func mostrar_aba(aba: Aba) -> void:
	_aba = aba
	_redesenhar()


# --- construção ---------------------------------------------------------------

func _build() -> void:
	var raiz := Control.new()
	raiz.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(raiz)

	var scrim := ColorRect.new()
	scrim.color = Color(0.02, 0.03, 0.04, 0.76)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	raiz.add_child(scrim)

	var margem := Design.margin(Design.S_XL)
	margem.set_anchors_preset(Control.PRESET_FULL_RECT)
	raiz.add_child(margem)

	var cartao := Design.panel(Design.SURFACE)
	margem.add_child(cartao)

	var coluna := Design.vbox(Design.S_MD)
	cartao.add_child(coluna)

	var cabecalho := Design.hbox(Design.S_SM)
	coluna.add_child(cabecalho)
	# O título é quem cede espaço quando a janela aperta: ele expande e corta,
	# em vez de um expansor fixo empurrar as abas e o "Fechar" para fora.
	var titulo := Design.heading("Mochila")
	titulo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titulo.clip_text = true
	cabecalho.add_child(titulo)

	var linha_abas := Design.hbox(Design.S_XS)
	cabecalho.add_child(linha_abas)

	for par in [[Aba.EQUIPE, "Equipe"], [Aba.CRIATURAS, "Criaturas"],
			[Aba.ITENS, "Itens"], [Aba.MISSOES, "Missões"]]:
		var aba: Aba = par[0]
		var botao := Design.button(String(par[1]))
		botao.pressed.connect(func(): _trocar_aba(aba))
		linha_abas.add_child(botao)
		_botoes_aba[aba] = botao

	var fechar_botao := Design.button("Fechar  (Esc)", "ghost")
	fechar_botao.pressed.connect(fechar)
	cabecalho.add_child(fechar_botao)

	_resumo = Design.caption("")
	coluna.add_child(_resumo)
	coluna.add_child(Design.divider())

	var corpo := Design.hbox(Design.S_LG)
	corpo.size_flags_vertical = Control.SIZE_EXPAND_FILL
	coluna.add_child(corpo)

	var rolagem := ScrollContainer.new()
	rolagem.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rolagem.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rolagem.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	corpo.add_child(rolagem)

	_conteudo = Design.vbox(Design.S_MD)
	_conteudo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rolagem.add_child(_conteudo)

	_painel_detalhe = Design.panel(Design.SURFACE_SUNKEN)
	Responsivo.largura(_painel_detalhe, LARGURA_DETALHE, 0.3)
	corpo.add_child(_painel_detalhe)

	# Com rolagem porque a ficha cresce com o nivel: habilidades e o botao de
	# evoluir ficavam abaixo da borda e sumiam sem aviso nenhum.
	_detalhe = Design.vbox(Design.S_SM)
	_painel_detalhe.add_child(Responsivo.rolagem(_detalhe))

	coluna.add_child(Design.divider())
	_rodape = Design.body("Clique numa criatura para ver os detalhes.")
	coluna.add_child(_rodape)


func _trocar_aba(aba: Aba) -> void:
	_aba = aba
	AudioManager.tocar_ui(&"ui_clique")
	_redesenhar()


# --- desenho ------------------------------------------------------------------

func _redesenhar() -> void:
	var dados := GameManager.player
	if dados == null or _conteudo == null:
		return

	for aba in _botoes_aba.keys():
		var botao: Button = _botoes_aba[aba]
		botao.modulate = Color.WHITE if aba == _aba else Color(1, 1, 1, 0.5)

	for filho in _conteudo.get_children():
		_conteudo.remove_child(filho)
		filho.queue_free()

	match _aba:
		Aba.EQUIPE:
			_resumo.text = "Equipe com %d de %d  ·  o slot 1 é quem te acompanha e lidera a batalha" % [
				dados.team_uids.size(), PlayerData.TEAM_SIZE
			]
			_desenhar_equipe(dados)
		Aba.CRIATURAS:
			_resumo.text = "%d criatura(s) na coleção" % dados.collection_size()
			_desenhar_grade_criaturas(dados)
		Aba.ITENS:
			_resumo.text = "%d tipo(s) de item" % dados.inventory.size()
			_desenhar_itens(dados)
		Aba.MISSOES:
			var ativas := QuestManager.missoes_ativas().size()
			var feitas := QuestManager.missoes_concluidas().size()
			_resumo.text = "%d em andamento  ·  %d concluída(s)" % [ativas, feitas]
			_desenhar_missoes()

	_desenhar_detalhe()


func _desenhar_missoes() -> void:
	var ativas := QuestManager.missoes_ativas()
	var concluidas := QuestManager.missoes_concluidas()

	if ativas.is_empty() and concluidas.is_empty():
		_conteudo.add_child(Design.caption("Nenhuma missão ainda. Elas abrem sozinhas conforme você avança."))
		return

	if not ativas.is_empty():
		_conteudo.add_child(Design.label("EM ANDAMENTO", Design.FS_CAPTION, Design.ACCENT))
		for missao in ativas:
			_conteudo.add_child(_cartao_missao(missao, false))

	if not concluidas.is_empty():
		_conteudo.add_child(Design.spacer(Design.S_SM))
		_conteudo.add_child(Design.label("CONCLUÍDAS", Design.FS_CAPTION, Design.TEXT_DIM))
		for missao in concluidas:
			_conteudo.add_child(_cartao_missao(missao, true))


func _cartao_missao(missao: Dictionary, concluida: bool) -> Control:
	var quest_id := String(missao.get("id", ""))
	var cartao := Design.card(Design.ACCENT if concluida else Design.TEXT_MUTED, concluida)

	var coluna := Design.vbox(Design.S_XS)
	cartao.add_child(coluna)

	var topo := Design.hbox(Design.S_SM)
	var nome := Design.label(String(missao.get("name", quest_id)), Design.FS_BODY, Design.TEXT)
	nome.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	topo.add_child(nome)

	var alvo := QuestManager.alvo(quest_id)
	var atual := QuestManager.progresso(quest_id)
	topo.add_child(Design.label(
		"concluída" if concluida else "%d / %d" % [atual, alvo],
		Design.FS_LABEL,
		Design.ACCENT if concluida else Design.TEXT_MUTED
	))
	coluna.add_child(topo)

	var descricao := Design.caption(String(missao.get("description", "")))
	descricao.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	coluna.add_child(descricao)

	if not concluida:
		var barra := Design.meter(Design.ACCENT, 5)
		barra.value = clampf(float(atual) / float(maxi(1, alvo)), 0.0, 1.0)
		coluna.add_child(barra)

	# Recompensa à vista: é o que faz a missão valer o desvio.
	var premios: Array[String] = []
	var recompensas: Dictionary = missao.get("rewards", {})
	if int(recompensas.get("gold", 0)) > 0:
		premios.append("%d de ouro" % int(recompensas["gold"]))
	if int(recompensas.get("player_xp", 0)) > 0:
		premios.append("%d XP" % int(recompensas["player_xp"]))
	for item_id in recompensas.get("items", {}).keys():
		premios.append("%dx %s" % [
			int(recompensas["items"][item_id]), DataManager.get_item_name(String(item_id))
		])
	if not premios.is_empty():
		coluna.add_child(Design.label(
			"Recompensa: " + ", ".join(premios), Design.FS_CAPTION,
			Design.TEXT_DIM if concluida else Design.GOLD
		))

	return cartao


## Espaco horizontal que sobra para a lista, ja descontando margem da tela,
## recheio do painel e a coluna de detalhe ao lado.
func _largura_da_lista() -> float:
	var tela := Responsivo.tela(self)
	var detalhe := _painel_detalhe.custom_minimum_size.x if _painel_detalhe != null else float(LARGURA_DETALHE)
	var gasto := Design.S_XL * 2 + Design.S_LG * 2 + Design.S_LG + detalhe
	return maxf(float(LARGURA_CARD), tela.x - gasto)


func _grade() -> GridContainer:
	var grade := GridContainer.new()
	grade.columns = Responsivo.colunas(_largura_da_lista(), LARGURA_CARD, Design.S_SM, MAX_COLUNAS)
	grade.add_theme_constant_override("h_separation", Design.S_SM)
	grade.add_theme_constant_override("v_separation", Design.S_SM)
	return grade


func _desenhar_equipe(dados: PlayerData) -> void:
	var linha := GridContainer.new()
	linha.columns = Responsivo.colunas(_largura_da_lista(), 190.0, Design.S_SM, PlayerData.TEAM_SIZE)
	linha.add_theme_constant_override("h_separation", Design.S_SM)
	linha.add_theme_constant_override("v_separation", Design.S_SM)
	_conteudo.add_child(linha)

	var equipe := dados.team()
	for slot in PlayerData.TEAM_SIZE:
		var criatura: CreatureData = equipe[slot] if slot < equipe.size() else null
		linha.add_child(_cartao_slot(criatura, slot, dados))

	_conteudo.add_child(Design.divider())
	_conteudo.add_child(Design.label("ADICIONAR À EQUIPE", Design.FS_CAPTION, Design.TEXT_DIM))

	var fora: Array[CreatureData] = []
	for criatura in dados.collection:
		if not dados.is_equipped(criatura.uid):
			fora.append(criatura)
	if fora.is_empty():
		_conteudo.add_child(Design.caption("Toda a sua coleção já está na equipe."))
		return

	var grade := _grade()
	_conteudo.add_child(grade)
	for criatura in fora:
		grade.add_child(_cartao_criatura(criatura, dados))


## O cartao nao tem altura fixa: a area clicavel fica **atras** do conteudo,
## ocupando o cartao inteiro, e o bloco de informacao ignora o mouse para o
## clique atravessar ate ela. Os botoes de acao continuam por cima e recebem o
## clique primeiro.
##
## Antes disso o conteudo morava dentro de um Button de altura fixa, ancorado em
## FULL_RECT: como o texto e a barra somavam mais que essa altura, eles vazavam
## e ficavam desenhados em cima da linha de botoes.
func _cartao_slot(criatura: CreatureData, slot: int, dados: PlayerData) -> Control:
	var cartao := Design.card(Design.GOLD if slot == 0 else Design.TEXT_MUTED, slot == 0)
	cartao.custom_minimum_size = Vector2(LARGURA_CARD, 0)
	cartao.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	if criatura != null:
		var seletor := Button.new()
		seletor.flat = true
		seletor.focus_mode = Control.FOCUS_NONE
		seletor.pressed.connect(func(): _selecionar(criatura))
		cartao.add_child(seletor)

	var coluna := Design.vbox(Design.S_XS)
	cartao.add_child(coluna)

	coluna.add_child(Design.label(
		"SLOT %d%s" % [slot + 1, "  ·  LÍDER" if slot == 0 else ""],
		Design.FS_CAPTION,
		Design.ACCENT if slot == 0 else Design.TEXT_DIM
	))

	if criatura == null:
		coluna.add_child(Design.caption("vazio", Design.TEXT_MUTED))
		coluna.add_child(Design.expander())
		return cartao

	var info := Design.vbox(2)
	coluna.add_child(info)
	var nome := Design.label(criatura.display_name(), Design.FS_BODY, Design.TEXT)
	nome.clip_text = true
	info.add_child(nome)
	info.add_child(Design.caption("Nv.%d  ·  %s" % [
		criatura.level, DataManager.get_element_name(criatura.element())
	]))
	var barra := Design.meter(Design.HEALTH, 5)
	barra.value = criatura.hp_ratio()
	info.add_child(barra)
	info.add_child(Design.caption("%d / %d" % [criatura.current_hp, criatura.max_hp()]))
	Design.ignore_mouse(info)

	coluna.add_child(Design.expander())

	var acoes := Design.hbox(Design.S_XS)
	coluna.add_child(acoes)

	var esquerda := Design.button("◀")
	esquerda.disabled = slot == 0
	esquerda.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	esquerda.pressed.connect(func(): _trocar_slots(slot, slot - 1))
	acoes.add_child(esquerda)

	var direita := Design.button("▶")
	direita.disabled = slot >= dados.team_uids.size() - 1
	direita.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	direita.pressed.connect(func(): _trocar_slots(slot, slot + 1))
	acoes.add_child(direita)

	var tirar := Design.button("✕", "danger")
	tirar.pressed.connect(func(): _tirar_da_equipe(criatura))
	acoes.add_child(tirar)

	return cartao


func _desenhar_grade_criaturas(dados: PlayerData) -> void:
	if dados.collection.is_empty():
		_conteudo.add_child(Design.caption("Você ainda não capturou nada."))
		return
	var grade := _grade()
	_conteudo.add_child(grade)
	for criatura in dados.collection:
		grade.add_child(_cartao_criatura(criatura, dados))


## Mesmo arranjo do cartao de slot: botao atras, conteudo por cima ignorando o
## mouse. Sem altura fixa, entao um nome longo ou uma barra mais alta empurram o
## cartao para baixo em vez de vazar por fora dele.
func _cartao_criatura(criatura: CreatureData, dados: PlayerData) -> Control:
	var na_equipe := dados.is_equipped(criatura.uid)
	var lider := dados.team_uids.size() > 0 and dados.team_uids[0] == criatura.uid
	var cor := DataManager.get_rarity_color(criatura.rarity())
	var destaque := Design.ACCENT if lider else (cor if na_equipe else Design.TEXT_MUTED)

	var cartao := Design.card(destaque, criatura == _selecionada)
	cartao.custom_minimum_size = Vector2(LARGURA_CARD, 0)
	cartao.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var seletor := Button.new()
	seletor.flat = true
	seletor.focus_mode = Control.FOCUS_NONE
	seletor.pressed.connect(func(): _selecionar(criatura))
	cartao.add_child(seletor)

	var coluna := Design.vbox(2)
	cartao.add_child(coluna)

	var topo := Design.hbox(Design.S_XS)
	var ponto := Panel.new()
	ponto.custom_minimum_size = Vector2(9, 9)
	ponto.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ponto.add_theme_stylebox_override(
		"panel", Design.panel_style(DataManager.get_element_color(criatura.element()), 4, 0)
	)
	topo.add_child(ponto)
	var nome := Design.label(criatura.display_name(), Design.FS_LABEL, Design.TEXT)
	nome.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nome.clip_text = true
	topo.add_child(nome)
	topo.add_child(Design.label("Nv.%d" % criatura.level, Design.FS_CAPTION, Design.TEXT_MUTED))
	coluna.add_child(topo)

	coluna.add_child(Design.caption(DataManager.get_rarity_name(criatura.rarity())))

	var barra := Design.meter(Design.HEALTH, 5)
	barra.value = criatura.hp_ratio()
	coluna.add_child(barra)
	coluna.add_child(Design.caption("%d / %d" % [criatura.current_hp, criatura.max_hp()]))

	coluna.add_child(Design.expander())
	var marca := ""
	if lider:
		marca = "NA FRENTE"
	elif na_equipe:
		marca = "na equipe"
	elif criatura.can_evolve():
		marca = "pode evoluir"
	coluna.add_child(Design.label(
		marca, Design.FS_CAPTION,
		Design.ACCENT if lider else (Design.GOLD if criatura.can_evolve() and not na_equipe else Design.TEXT_DIM)
	))

	Design.ignore_mouse(coluna)
	return cartao


func _desenhar_itens(dados: PlayerData) -> void:
	if dados.inventory.is_empty():
		_conteudo.add_child(Design.caption("A mochila está vazia."))
		return
	var grade := _grade()
	_conteudo.add_child(grade)

	for item_id in dados.inventory.keys():
		grade.add_child(_cartao_item(String(item_id), int(dados.inventory[item_id])))


func _cartao_item(item_id: String, quantidade: int) -> Control:
	var item := DataManager.get_item(item_id)
	var cor := DataManager.get_item_color(item_id)

	var cartao := Design.card(cor, false)
	cartao.custom_minimum_size = Vector2(LARGURA_CARD, 0)
	cartao.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var seletor := Button.new()
	seletor.flat = true
	seletor.focus_mode = Control.FOCUS_NONE
	seletor.pressed.connect(func(): _usar_item(item_id))
	cartao.add_child(seletor)

	var coluna := Design.vbox(2)
	cartao.add_child(coluna)

	var topo := Design.hbox(Design.S_XS)
	var nome := Design.label(item.get("name", item_id), Design.FS_LABEL, Design.TEXT)
	nome.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nome.clip_text = true
	topo.add_child(nome)
	topo.add_child(Design.label("x%d" % quantidade, Design.FS_LABEL, Design.GOLD))
	coluna.add_child(topo)

	coluna.add_child(Design.chip(
		DataManager.get_item_category_name(String(item.get("category", ""))), cor
	))

	var descricao := Design.caption(String(item.get("description", "")))
	descricao.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	descricao.size_flags_vertical = Control.SIZE_EXPAND_FILL
	coluna.add_child(descricao)

	Design.ignore_mouse(coluna)
	return cartao


# --- painel de detalhe --------------------------------------------------------

func _desenhar_detalhe() -> void:
	for filho in _detalhe.get_children():
		_detalhe.remove_child(filho)
		filho.queue_free()

	var dados := GameManager.player
	if _selecionada == null or dados == null:
		_detalhe.add_child(Design.label("DETALHE", Design.FS_CAPTION, Design.TEXT_DIM))
		_detalhe.add_child(Design.body("Selecione uma criatura para ver atributos, habilidades e evolução."))
		return

	var criatura := _selecionada
	var especie := criatura.species()

	var largura_previa := int(_painel_detalhe.custom_minimum_size.x) - Design.S_XL * 2
	var preview := CreaturePreview.new(especie, Vector2i(maxi(140, largura_previa), 170), 0.5)
	preview.set_interactive(true)
	preview.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_detalhe.add_child(preview)

	var titulo := Design.label(criatura.display_name(), Design.FS_HEADING, Design.TEXT, true)
	titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detalhe.add_child(titulo)

	var chips := Design.hbox(Design.S_XS)
	chips.alignment = BoxContainer.ALIGNMENT_CENTER
	chips.add_child(Design.chip(
		DataManager.get_element_name(criatura.element()), DataManager.get_element_color(criatura.element())
	))
	chips.add_child(Design.chip(
		DataManager.get_rarity_name(criatura.rarity()), DataManager.get_rarity_color(criatura.rarity())
	))
	chips.add_child(Design.chip(DataManager.get_role_name(especie.role), Design.TEXT_MUTED))
	_detalhe.add_child(chips)

	_detalhe.add_child(Design.divider())

	var necessario := criatura.xp_to_next_level()
	_detalhe.add_child(Design.label(
		"NÍVEL %d" % criatura.level, Design.FS_CAPTION, Design.TEXT_DIM
	))
	var barra_xp := Design.meter(Design.XP, 6)
	barra_xp.value = 1.0 if necessario <= 0 else clampf(float(criatura.xp) / float(necessario), 0.0, 1.0)
	_detalhe.add_child(barra_xp)
	_detalhe.add_child(Design.caption(
		"nível máximo" if necessario <= 0 else "%d / %d XP" % [criatura.xp, necessario]
	))

	var barra_hp := Design.meter(Design.HEALTH, 6)
	barra_hp.value = criatura.hp_ratio()
	_detalhe.add_child(barra_hp)
	_detalhe.add_child(Design.caption("%d / %d de vida" % [criatura.current_hp, criatura.max_hp()]))

	_detalhe.add_child(Design.divider())
	_atributo("Ataque", criatura.attack())
	_atributo("Defesa", criatura.defense())
	_atributo("Velocidade", criatura.speed())

	_detalhe.add_child(Design.divider())
	_detalhe.add_child(Design.label("HABILIDADES", Design.FS_CAPTION, Design.TEXT_DIM))
	for skill_id in criatura.skill_ids():
		var skill := DataManager.get_skill(skill_id)
		if skill.is_empty():
			continue
		var bloco := Design.vbox(0)
		var linha := Design.hbox(Design.S_XS)
		var nome_skill := Design.label(skill.get("name", skill_id), Design.FS_LABEL, Design.TEXT)
		nome_skill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		linha.add_child(nome_skill)
		linha.add_child(Design.caption("%s · %.0fs" % [
			DataManager.get_skill_kind_name(String(skill.get("kind", ""))),
			float(skill.get("cooldown", 0))
		]))
		bloco.add_child(linha)
		var desc := Design.caption(String(skill.get("description", "")))
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		bloco.add_child(desc)
		_detalhe.add_child(bloco)

	_detalhe.add_child(Design.divider())
	_desenhar_acoes(criatura, dados, especie)


func _atributo(rotulo: String, valor: int) -> void:
	var linha := Design.hbox(Design.S_SM)
	var nome := Design.label(rotulo, Design.FS_LABEL, Design.TEXT_MUTED)
	nome.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	linha.add_child(nome)
	linha.add_child(Design.label(str(valor), Design.FS_BODY, Design.TEXT))
	_detalhe.add_child(linha)


func _desenhar_acoes(criatura: CreatureData, dados: PlayerData, especie: CreatureSpecies) -> void:
	var lider := dados.team_uids.size() > 0 and dados.team_uids[0] == criatura.uid

	if not lider:
		var invocar := Design.button("Invocar (virar líder)", "primary")
		invocar.pressed.connect(func(): _invocar(criatura))
		_detalhe.add_child(invocar)

	if dados.is_equipped(criatura.uid):
		var tirar := Design.button("Tirar da equipe")
		tirar.pressed.connect(func(): _tirar_da_equipe(criatura))
		_detalhe.add_child(tirar)
	elif not dados.team_is_full():
		var por := Design.button("Colocar na equipe")
		por.pressed.connect(func(): _por_na_equipe(criatura))
		_detalhe.add_child(por)

	if especie.has_evolution():
		var destino := DataManager.get_species(especie.evolves_to)
		var nome_destino := destino.name if destino != null else String(especie.evolves_to)
		if criatura.can_evolve():
			var evoluir := Design.button("Evoluir para %s" % nome_destino, "primary")
			evoluir.pressed.connect(func(): _evoluir(criatura))
			_detalhe.add_child(evoluir)
		else:
			_detalhe.add_child(Design.caption(
				"Evolui para %s no nível %d." % [nome_destino, especie.evolution_level]
			))


# --- ações --------------------------------------------------------------------

func _selecionar(criatura: CreatureData) -> void:
	_selecionada = criatura
	AudioManager.tocar_ui(&"ui_clique")
	_redesenhar()


func _trocar_slots(a: int, b: int) -> void:
	var dados := GameManager.player
	if dados == null:
		return
	if dados.swap_team_slots(a, b):
		AudioManager.tocar_ui(&"ui_clique")
		_rodape.text = "Ordem da equipe alterada."
		criatura_invocada.emit(dados.team()[0])
		_redesenhar()


func _por_na_equipe(criatura: CreatureData) -> void:
	var dados := GameManager.player
	if dados == null:
		return
	if not criatura.is_alive():
		_rodape.text = "%s está sem condições. Descanse antes." % criatura.display_name()
		return
	if dados.equip_creature(criatura.uid):
		AudioManager.tocar_ui(&"ui_clique")
		_rodape.text = "%s entrou na equipe." % criatura.display_name()
		_redesenhar()


func _tirar_da_equipe(criatura: CreatureData) -> void:
	var dados := GameManager.player
	if dados == null:
		return
	if dados.team_uids.size() <= 1:
		_rodape.text = "Você não pode ficar sem nenhuma criatura na equipe."
		return
	if dados.unequip_creature(criatura.uid):
		AudioManager.tocar_ui(&"ui_clique")
		_rodape.text = "%s saiu da equipe." % criatura.display_name()
		criatura_invocada.emit(dados.team()[0] if not dados.team().is_empty() else null)
		_redesenhar()


## Invocar = ir para o slot 1. Se a equipe estiver cheia e ela estiver de fora,
## entra no lugar de quem estava na frente.
func _invocar(criatura: CreatureData) -> void:
	var dados := GameManager.player
	if dados == null:
		return
	if not criatura.is_alive():
		_rodape.text = "%s está sem condições. Descanse num acampamento antes." % criatura.display_name()
		return

	if not dados.is_equipped(criatura.uid) and dados.team_is_full():
		dados.unequip_creature(dados.team_uids[0])
	if not dados.is_equipped(criatura.uid):
		dados.equip_creature(criatura.uid)
	dados.set_team_slot(0, criatura.uid)

	AudioManager.tocar(&"captura_sucesso")
	_rodape.text = "%s está te acompanhando." % criatura.display_name()
	criatura_invocada.emit(criatura)
	_redesenhar()


func _evoluir(criatura: CreatureData) -> void:
	var antes := criatura.display_name()
	if not criatura.evolve():
		_rodape.text = "%s ainda não pode evoluir." % antes
		return
	AudioManager.tocar(&"nivel")
	Notify.good("%s evoluiu para %s!" % [antes, criatura.display_name()])
	_rodape.text = "%s evoluiu para %s." % [antes, criatura.display_name()]
	criatura_invocada.emit(GameManager.player.team()[0] if not GameManager.player.team().is_empty() else null)
	GameManager.save_now("evolução")
	_redesenhar()


func _usar_item(item_id: String) -> void:
	var dados := GameManager.player
	if dados == null:
		return
	var item := DataManager.get_item(item_id)
	var efeito := String(item.get("effect", ""))
	var valor := float(item.get("effect_value", 0.0))

	match efeito:
		"heal_percent":
			var alvo := _mais_ferida(dados)
			if alvo == null:
				_rodape.text = "Ninguém precisa de cura agora."
				return
			var curado := alvo.heal(DamageCalculator.compute_heal(alvo.max_hp(), valor))
			dados.consume_item(item_id)
			AudioManager.tocar(&"cura")
			_rodape.text = "%s recuperou %d de vida." % [alvo.display_name(), curado]
		"heal_team_percent":
			var equipe := dados.team()
			if equipe.is_empty():
				_rodape.text = "Sua equipe está vazia."
				return
			dados.consume_item(item_id)
			var total := 0
			for criatura in equipe:
				total += criatura.heal(DamageCalculator.compute_heal(criatura.max_hp(), valor))
			AudioManager.tocar(&"cura")
			_rodape.text = "A equipe recuperou %d de vida no total." % total
		_:
			if String(item.get("category", "")) == "capture":
				_rodape.text = "%s só funciona durante uma batalha." % item.get("name", item_id)
			else:
				_rodape.text = String(item.get("description", "Sem uso direto."))
			return

	GameManager.save_now("uso de item")
	_redesenhar()


static func _mais_ferida(dados: PlayerData) -> CreatureData:
	var melhor: CreatureData = null
	for criatura in dados.collection:
		if criatura.hp_ratio() >= 1.0:
			continue
		if melhor == null or criatura.hp_ratio() < melhor.hp_ratio():
			melhor = criatura
	return melhor


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("cancel") or event.is_action_pressed("inventory"):
		get_viewport().set_input_as_handled()
		fechar()
