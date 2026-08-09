class_name ShopPanel
extends CanvasLayer
## A loja de um mercador.
##
## Duas colunas: o que ele vende (preço = `value` do item) e o que você pode
## vender (uma fração desse valor, definida por `margem_venda` no maps.json).
##
## Existe porque até agora o ouro não tinha destino: você acumulava vitória após
## vitória e o número só subia. Comprar núcleo é o que transforma ouro em
## chance de captura, que é o laço central do jogo.
##
## O estoque é dado, não código: `npcs[].shop.vende` em maps.json.

signal fechado()

const MARGEM_PADRAO := 0.4

var _titulo: String = "Loja"
var _vende: Array = []
var _margem: float = MARGEM_PADRAO

var _coluna_compra: VBoxContainer = null
var _coluna_venda: VBoxContainer = null
var _ouro: Label = null
var _rodape: Label = null


func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


func abrir(config: Dictionary) -> void:
	_titulo = String(config.get("titulo", "Loja"))
	_vende = (config.get("vende", []) as Array).duplicate()
	_margem = clampf(float(config.get("margem_venda", MARGEM_PADRAO)), 0.05, 1.0)
	_construir()
	visible = true
	get_tree().paused = true
	AudioManager.tocar_ui(&"ui_alternar")
	_atualizar()


func fechar() -> void:
	visible = false
	get_tree().paused = false
	AudioManager.tocar_ui(&"ui_alternar")
	fechado.emit()


func esta_aberto() -> bool:
	return visible


# --- construção ---------------------------------------------------------------

func _construir() -> void:
	for filho in get_children():
		filho.queue_free()

	var raiz := Control.new()
	raiz.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(raiz)

	var scrim := ColorRect.new()
	scrim.color = Color(0.02, 0.03, 0.04, 0.74)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	raiz.add_child(scrim)

	var centro := CenterContainer.new()
	centro.set_anchors_preset(Control.PRESET_FULL_RECT)
	raiz.add_child(centro)

	var cartao := Design.panel(Design.SURFACE)
	Responsivo.caixa(cartao, Vector2(860, 520), Vector2(0.92, 0.86))
	centro.add_child(cartao)

	var coluna := Design.vbox(Design.S_MD)
	cartao.add_child(coluna)

	var cabecalho := Design.hbox(Design.S_MD)
	coluna.add_child(cabecalho)
	cabecalho.add_child(Design.heading(_titulo))
	cabecalho.add_child(Design.expander())

	_ouro = Design.label("", Design.FS_BODY, Design.GOLD)
	cabecalho.add_child(_ouro)

	var fechar_botao := Design.button("Fechar  (Esc)", "ghost")
	fechar_botao.pressed.connect(fechar)
	cabecalho.add_child(fechar_botao)

	coluna.add_child(Design.divider())

	var colunas := Design.hbox(Design.S_LG)
	colunas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	coluna.add_child(colunas)

	colunas.add_child(_montar_lado("COMPRAR", true))
	colunas.add_child(_montar_lado("VENDER", false))

	coluna.add_child(Design.divider())
	_rodape = Design.body("Vender dá %d%% do valor do item." % int(round(_margem * 100.0)))
	coluna.add_child(_rodape)


func _montar_lado(titulo: String, compra: bool) -> Control:
	var painel := Design.panel(Design.SURFACE_SUNKEN)
	painel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var coluna := Design.vbox(Design.S_SM)
	painel.add_child(coluna)
	coluna.add_child(Design.label(titulo, Design.FS_CAPTION, Design.TEXT_DIM))

	var rolagem := ScrollContainer.new()
	rolagem.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rolagem.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	coluna.add_child(rolagem)

	var lista := Design.vbox(Design.S_XS)
	lista.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rolagem.add_child(lista)

	if compra:
		_coluna_compra = lista
	else:
		_coluna_venda = lista
	return painel


# --- conteúdo -----------------------------------------------------------------

func _atualizar() -> void:
	var dados := GameManager.player
	if dados == null:
		return
	_ouro.text = "%d de ouro" % dados.gold

	for lista in [_coluna_compra, _coluna_venda]:
		for filho in lista.get_children():
			lista.remove_child(filho)
			filho.queue_free()

	for item_id in _vende:
		_coluna_compra.add_child(_linha(String(item_id), true, dados))

	var vendaveis := 0
	for item_id in dados.inventory.keys():
		var item := DataManager.get_item(String(item_id))
		# Item de missão não se vende: o jogador se arrependeria na hora.
		if String(item.get("category", "")) == "quest":
			continue
		if int(item.get("value", 0)) <= 0:
			continue
		_coluna_venda.add_child(_linha(String(item_id), false, dados))
		vendaveis += 1
	if vendaveis == 0:
		_coluna_venda.add_child(Design.caption("Você não tem nada que ele queira."))


func _linha(item_id: String, compra: bool, dados: PlayerData) -> Control:
	var item := DataManager.get_item(item_id)
	var cor := DataManager.get_item_color(item_id)
	var preco := _preco(item_id, compra)
	var quantidade := dados.item_count(item_id)

	var cartao := Design.card(cor)

	var linha := Design.hbox(Design.S_SM)
	cartao.add_child(linha)

	var texto := Design.vbox(0)
	texto.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var nome := Design.label(String(item.get("name", item_id)), Design.FS_LABEL, Design.TEXT)
	texto.add_child(nome)
	var detalhe := "você tem %d" % quantidade if quantidade > 0 else "você não tem"
	texto.add_child(Design.caption(detalhe))
	linha.add_child(texto)

	linha.add_child(Design.label("%d" % preco, Design.FS_BODY, Design.GOLD))

	var botao := Design.button("Comprar" if compra else "Vender", "primary" if compra else "default")
	botao.custom_minimum_size = Vector2(96, 34)
	botao.focus_mode = Control.FOCUS_NONE
	if compra:
		botao.disabled = dados.gold < preco
		botao.pressed.connect(func(): _comprar(item_id))
	else:
		botao.disabled = quantidade <= 0
		botao.pressed.connect(func(): _vender(item_id))
	linha.add_child(botao)

	return cartao


func _preco(item_id: String, compra: bool) -> int:
	var valor := int(DataManager.get_item(item_id).get("value", 0))
	if compra:
		return maxi(1, valor)
	return maxi(1, int(round(float(valor) * _margem)))


# --- ações --------------------------------------------------------------------

func _comprar(item_id: String) -> void:
	var dados := GameManager.player
	var preco := _preco(item_id, true)
	if not dados.spend_gold(preco):
		_rodape.text = "Ouro insuficiente."
		return
	dados.add_item(item_id, 1)
	AudioManager.tocar(&"ui_clique")
	_rodape.text = "Comprou %s por %d de ouro." % [DataManager.get_item_name(item_id), preco]
	GameManager.save_now("compra")
	_atualizar()


func _vender(item_id: String) -> void:
	var dados := GameManager.player
	if not dados.consume_item(item_id, 1):
		return
	var preco := _preco(item_id, false)
	dados.add_gold(preco)
	AudioManager.tocar(&"ui_clique")
	_rodape.text = "Vendeu %s por %d de ouro." % [DataManager.get_item_name(item_id), preco]
	GameManager.save_now("venda")
	_atualizar()


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("cancel") or event.is_action_pressed("inventory")):
		get_viewport().set_input_as_handled()
		fechar()
