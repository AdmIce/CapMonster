class_name BattleHUD
extends CanvasLayer
## Interface do combate.
##
## Em cima: os inimigos. Embaixo: a equipe, as duas habilidades da criatura
## líder (com a recarga desenhada dentro do próprio botão) e as ações de item,
## captura e fuga.
##
## Botão só existe quando faz alguma coisa: se não houver poção no inventário, o
## botão fica desabilitado dizendo isso; se não der para capturar, ele explica
## por quê em vez de sumir.

const ITEM_CURA := "vital_draught"
const ITEM_CAPTURA := "binding_core"

var _controller: BattleController = null

var _raiz: Control = null
var _linha_inimigos: HBoxContainer = null
var _linha_aliados: HBoxContainer = null
var _linha_habilidades: HBoxContainer = null
var _rotulo_log: Label = null
var _botao_item: Button = null
var _botao_captura: Button = null
var _botao_fuga: Button = null

var _cartoes: Array = []            ## { ator, barra, texto }
var _botoes_skill: Array = []       ## { indice, botao, barra }


func _ready() -> void:
	layer = 20
	_build()
	visible = false


func bind(controller: BattleController) -> void:
	_controller = controller
	controller.batalha_iniciada.connect(_ao_iniciar)
	controller.batalha_encerrada.connect(_ao_encerrar)
	controller.mensagem.connect(_ao_mensagem)


# --- construção ---------------------------------------------------------------

func _build() -> void:
	_raiz = Control.new()
	_raiz.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_raiz)

	# Inimigos no topo.
	var topo := Control.new()
	topo.set_anchors_preset(Control.PRESET_TOP_WIDE)
	topo.offset_top = Design.S_LG
	topo.offset_bottom = 110
	_raiz.add_child(topo)

	var centro_topo := CenterContainer.new()
	centro_topo.set_anchors_preset(Control.PRESET_FULL_RECT)
	topo.add_child(centro_topo)

	_linha_inimigos = Design.hbox(Design.S_SM)
	centro_topo.add_child(_linha_inimigos)

	# Registro curto do que acabou de acontecer.
	var faixa_log := Control.new()
	faixa_log.set_anchors_preset(Control.PRESET_TOP_WIDE)
	faixa_log.offset_top = 116
	faixa_log.offset_bottom = 146
	_raiz.add_child(faixa_log)

	var centro_log := CenterContainer.new()
	centro_log.set_anchors_preset(Control.PRESET_FULL_RECT)
	faixa_log.add_child(centro_log)

	var cartao_log := Design.card(Design.BORDER)
	centro_log.add_child(cartao_log)

	_rotulo_log = Design.label("", Design.FS_LABEL, Design.TEXT_MUTED)
	cartao_log.add_child(_rotulo_log)

	# Painel de baixo.
	var base := Control.new()
	base.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	base.offset_left = Design.S_LG
	base.offset_right = -Design.S_LG
	base.offset_top = -168
	base.offset_bottom = -Design.S_LG
	_raiz.add_child(base)

	var cartao := Design.panel(Color(0.043, 0.055, 0.067, 0.94))
	cartao.set_anchors_preset(Control.PRESET_FULL_RECT)
	base.add_child(cartao)

	var colunas := Design.hbox(Design.S_LG)
	cartao.add_child(colunas)

	_linha_aliados = Design.hbox(Design.S_SM)
	_linha_aliados.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	colunas.add_child(_linha_aliados)

	var acoes := Design.vbox(Design.S_SM)
	# Em janela estreita a coluna de ações cede espaço para os cartões da equipe
	# em vez de empurrá-los para fora do painel.
	Responsivo.largura(acoes, 430, 0.42)
	colunas.add_child(acoes)

	acoes.add_child(Design.label("HABILIDADES DO LÍDER", Design.FS_CAPTION, Design.TEXT_DIM))
	_linha_habilidades = Design.hbox(Design.S_SM)
	acoes.add_child(_linha_habilidades)

	var linha_acoes := Design.hbox(Design.S_SM)
	acoes.add_child(linha_acoes)

	_botao_item = Design.button("Poção")
	_botao_item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_botao_item.pressed.connect(_ao_usar_item)
	linha_acoes.add_child(_botao_item)

	_botao_captura = Design.button("Capturar", "primary")
	_botao_captura.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_botao_captura.pressed.connect(_ao_capturar)
	linha_acoes.add_child(_botao_captura)

	_botao_fuga = Design.button("Fugir", "ghost")
	_botao_fuga.pressed.connect(_ao_fugir)
	linha_acoes.add_child(_botao_fuga)


# --- ciclo da batalha ---------------------------------------------------------

func _ao_iniciar(aliados: Array, inimigos: Array) -> void:
	visible = true
	_montar_cartoes(_linha_inimigos, inimigos, false)
	_montar_cartoes(_linha_aliados, aliados, true)
	_montar_habilidades()
	_atualizar_acoes()


func _ao_encerrar(vitoria: bool, resumo: Dictionary) -> void:
	visible = false
	_cartoes.clear()
	_botoes_skill.clear()
	if resumo.get("fuga", false) or resumo.get("capturado", false):
		return
	if vitoria:
		_mostrar_vitoria(resumo)


## Painel de vitória. Aparece só quando houve luta até o fim - fuga e captura
## têm o próprio retorno e não merecem uma tela por cima.
func _mostrar_vitoria(resumo: Dictionary) -> void:
	var camada := CanvasLayer.new()
	camada.layer = 65
	get_tree().current_scene.add_child(camada)

	var raiz := Control.new()
	raiz.set_anchors_preset(Control.PRESET_FULL_RECT)
	raiz.mouse_filter = Control.MOUSE_FILTER_IGNORE
	camada.add_child(raiz)

	var centro := CenterContainer.new()
	centro.set_anchors_preset(Control.PRESET_FULL_RECT)
	centro.mouse_filter = Control.MOUSE_FILTER_IGNORE
	raiz.add_child(centro)

	var cartao := Design.panel(Color(0.043, 0.055, 0.067, 0.95))
	Responsivo.largura(cartao, 400, 0.5)
	centro.add_child(cartao)

	var coluna := Design.vbox(Design.S_SM)
	cartao.add_child(coluna)

	var titulo := Design.label(
		"CHEFE DERROTADO" if String(resumo.get("chefe", "")) != "" else "VITÓRIA",
		Design.FS_TITLE, Design.ACCENT, true
	)
	titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	coluna.add_child(titulo)
	coluna.add_child(Design.divider())

	_linha_resumo(coluna, "XP por criatura", "+%d" % int(resumo.get("xp", 0)), Design.XP)
	_linha_resumo(coluna, "Ouro", "+%d" % int(resumo.get("ouro", 0)), Design.GOLD)

	var itens: Array = resumo.get("itens", [])
	for texto in itens:
		_linha_resumo(coluna, String(texto), "", Design.TEXT)

	var evolucoes: Array = resumo.get("evolucoes", [])
	if not evolucoes.is_empty():
		coluna.add_child(Design.divider())
		coluna.add_child(Design.label("PRONTAS PARA EVOLUIR", Design.FS_CAPTION, Design.TEXT_DIM))
		for nome in evolucoes:
			coluna.add_child(Design.label(String(nome), Design.FS_BODY, Design.GOLD))
		coluna.add_child(Design.caption("Abra a Mochila (I) para evoluir."))

	Design.ignore_mouse(raiz)
	cartao.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(cartao, "modulate:a", 1.0, 0.25)
	tween.tween_interval(2.8)
	tween.tween_property(cartao, "modulate:a", 0.0, 0.5)
	tween.tween_callback(camada.queue_free)


func _linha_resumo(pai: VBoxContainer, rotulo: String, valor: String, cor: Color) -> void:
	var linha := Design.hbox(Design.S_MD)
	var nome := Design.label(rotulo, Design.FS_BODY, Design.TEXT_MUTED)
	nome.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	linha.add_child(nome)
	if valor != "":
		linha.add_child(Design.label(valor, Design.FS_BODY, cor))
	pai.add_child(linha)


func _ao_mensagem(texto: String) -> void:
	if _rotulo_log != null:
		_rotulo_log.text = texto


func _montar_cartoes(linha: HBoxContainer, atores: Array, aliado: bool) -> void:
	for filho in linha.get_children():
		linha.remove_child(filho)
		filho.queue_free()

	for ator in atores:
		var combatente: BattleActor = ator
		var cor := DataManager.get_rarity_color(combatente.data.rarity())
		var cartao := Design.card(cor, aliado)
		cartao.custom_minimum_size = Vector2(178, 0)
		linha.add_child(cartao)

		var coluna := Design.vbox(3)
		cartao.add_child(coluna)

		var cabecalho := Design.hbox(Design.S_XS)
		var ponto := Panel.new()
		ponto.custom_minimum_size = Vector2(8, 8)
		ponto.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		ponto.add_theme_stylebox_override(
			"panel", Design.panel_style(DataManager.get_element_color(combatente.data.element()), 4, 0)
		)
		cabecalho.add_child(ponto)
		var nome := Design.label(combatente.data.display_name(), Design.FS_LABEL, Design.TEXT)
		nome.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nome.clip_text = true
		cabecalho.add_child(nome)
		cabecalho.add_child(Design.label("Nv.%d" % combatente.data.level, Design.FS_CAPTION, Design.TEXT_MUTED))
		coluna.add_child(cabecalho)

		var barra := Design.meter(Design.HEALTH if aliado else Design.DANGER, 6)
		barra.value = combatente.data.hp_ratio()
		coluna.add_child(barra)

		var texto := Design.caption("%d / %d" % [combatente.data.current_hp, combatente.data.max_hp()])
		coluna.add_child(texto)

		_cartoes.append({ "ator": combatente, "barra": barra, "texto": texto })

	Design.ignore_mouse(linha)


func _montar_habilidades() -> void:
	for filho in _linha_habilidades.get_children():
		_linha_habilidades.remove_child(filho)
		filho.queue_free()
	_botoes_skill.clear()

	var lider := _controller.lider()
	if lider == null:
		return
	var skills := lider.data.skill_ids()
	for i in skills.size():
		var indice := i
		var skill := DataManager.get_skill(skills[i])
		var botao := Design.button(skill.get("name", skills[i]))
		botao.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		botao.custom_minimum_size = Vector2(0, 46)
		botao.tooltip_text = "%s · %s" % [
			DataManager.get_skill_kind_name(skill.get("kind", "")), skill.get("description", "")
		]
		botao.pressed.connect(func(): _controller.usar_habilidade_manual(indice))
		_linha_habilidades.add_child(botao)

		var barra := Design.meter(Design.XP, 4)
		barra.value = 1.0
		barra.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		barra.offset_top = -6
		barra.offset_bottom = -2
		barra.offset_left = 6
		barra.offset_right = -6
		barra.mouse_filter = Control.MOUSE_FILTER_IGNORE
		botao.add_child(barra)

		_botoes_skill.append({ "indice": indice, "botao": botao, "barra": barra, "id": skills[i] })


func _process(_delta: float) -> void:
	if not visible or _controller == null or not _controller.em_batalha:
		return

	for cartao in _cartoes:
		var ator: BattleActor = cartao["ator"]
		if not is_instance_valid(ator):
			continue
		var barra: ProgressBar = cartao["barra"]
		barra.value = lerpf(barra.value, ator.data.hp_ratio(), 0.25)
		(cartao["texto"] as Label).text = "%d / %d" % [ator.data.current_hp, ator.data.max_hp()]

	var lider := _controller.lider()
	for entrada in _botoes_skill:
		var botao: Button = entrada["botao"]
		var barra: ProgressBar = entrada["barra"]
		if lider == null:
			botao.disabled = true
			continue
		var skill_id: String = entrada["id"]
		var recarga := lider.recarga_restante(skill_id)
		var total := float(DataManager.get_skill(skill_id).get("cooldown", 1.0))
		barra.value = 1.0 if recarga <= 0.0 else clampf(1.0 - recarga / maxf(0.01, total), 0.0, 1.0)
		botao.disabled = recarga > 0.0
		botao.text = DataManager.get_skill(skill_id).get("name", skill_id) if recarga <= 0.0 else "%.1fs" % recarga

	_atualizar_acoes()


func _atualizar_acoes() -> void:
	var dados := GameManager.player
	if dados == null:
		return

	var pocoes := dados.item_count(ITEM_CURA)
	_botao_item.disabled = pocoes <= 0
	_botao_item.text = "Poção (%d)" % pocoes if pocoes > 0 else "Sem poção"

	var nucleos := dados.item_count(ITEM_CAPTURA)
	var pode := _controller.pode_capturar()
	_botao_captura.disabled = not pode or nucleos <= 0
	if nucleos <= 0:
		_botao_captura.text = "Sem núcleo"
	elif not pode:
		_botao_captura.text = "Capturar (1 alvo)"
	else:
		_botao_captura.text = "Capturar (%d)" % nucleos


# --- ações --------------------------------------------------------------------

func _ao_usar_item() -> void:
	_controller.usar_item(ITEM_CURA)
	_atualizar_acoes()


func _ao_capturar() -> void:
	_controller.tentar_captura(ITEM_CAPTURA)
	_atualizar_acoes()


func _ao_fugir() -> void:
	_controller.fugir()
