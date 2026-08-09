class_name OnlinePanel
extends CanvasLayer
## Tela de "jogar junto": hospedar uma partida ou entrar na de um amigo.
##
## Nada aqui é enfeite — o botão hospeda de verdade, o campo de endereço conecta
## de verdade e a lista mostra quem está online agora. O estado vem todo do
## autoload `Rede`, então esta tela pode abrir e fechar sem perder conexão.
##
## Sobre jogar pela internet: a porta precisa chegar ao host. Numa rede local
## (mesmo wi-fi) funciona direto. Pela internet é preciso liberar a porta no
## roteador do host ou hospedar num servidor com IP público — o texto do rodapé
## diz isso ao jogador em vez de deixar ele descobrir com um erro.

signal fechado()

const PORTA := Rede.PORTA_PADRAO

var _endereco: LineEdit = null
var _estado: Label = null
var _lista: VBoxContainer = null
var _botao_hospedar: Button = null
var _botao_entrar: Button = null
var _botao_sair: Button = null


func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	_construir()
	Rede.estado_mudou.connect(_atualizar)
	_atualizar()


func _construir() -> void:
	var raiz := Control.new()
	raiz.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(raiz)

	var scrim := ColorRect.new()
	scrim.color = Color(0.02, 0.03, 0.04, 0.76)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	raiz.add_child(scrim)

	var centro := CenterContainer.new()
	centro.set_anchors_preset(Control.PRESET_FULL_RECT)
	raiz.add_child(centro)

	var cartao := Design.panel(Design.SURFACE)
	Responsivo.largura(cartao, 520, 0.6)
	centro.add_child(cartao)

	var coluna := Design.vbox(Design.S_MD)
	cartao.add_child(coluna)

	var cabecalho := Design.hbox(Design.S_SM)
	coluna.add_child(cabecalho)
	var titulo := Design.heading("Jogar junto")
	titulo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cabecalho.add_child(titulo)
	var fechar := Design.button("Fechar  (Esc)", "ghost")
	fechar.pressed.connect(_fechar)
	cabecalho.add_child(fechar)

	_estado = Design.body("")
	coluna.add_child(_estado)
	coluna.add_child(Design.divider())

	_botao_hospedar = Design.button("Abrir meu mundo (porta %d)" % PORTA, "primary")
	_botao_hospedar.pressed.connect(_hospedar)
	coluna.add_child(_botao_hospedar)

	coluna.add_child(Design.label("ENTRAR NO MUNDO DE ALGUÉM", Design.FS_CAPTION, Design.TEXT_DIM))
	var linha := Design.hbox(Design.S_SM)
	coluna.add_child(linha)

	# 64 caracteres: cabe IPv4, IPv6 curto e nome de domínio de um servidor.
	_endereco = Design.line_edit("IP do host, ex.: 192.168.0.10", 64)
	_endereco.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_endereco.text = String(SaveManager.get_setting("ultimo_host", ""))
	_endereco.text_submitted.connect(func(_t): _entrar())
	linha.add_child(_endereco)

	_botao_entrar = Design.button("Entrar")
	_botao_entrar.pressed.connect(_entrar)
	linha.add_child(_botao_entrar)

	_botao_sair = Design.button("Desconectar", "danger")
	_botao_sair.pressed.connect(func(): Rede.desligar())
	coluna.add_child(_botao_sair)

	coluna.add_child(Design.divider())
	coluna.add_child(Design.label("QUEM ESTÁ ONLINE", Design.FS_CAPTION, Design.TEXT_DIM))
	_lista = Design.vbox(Design.S_XS)
	coluna.add_child(_lista)

	coluna.add_child(Design.divider())
	# Parênteses no `%`: ele tem precedência maior que o `+`, então sem eles o
	# formato tentaria se aplicar só ao último pedaço da frase.
	coluna.add_child(Design.body(
		("Na mesma rede (mesmo wi-fi) basta o IP local do host. Pela internet, o "
		+ "host precisa liberar a porta %d no roteador — ou o mundo precisa rodar "
		+ "num servidor com IP público.") % PORTA,
		Design.TEXT_MUTED
	))


func _hospedar() -> void:
	AudioManager.tocar_ui(&"ui_clique")
	if Rede.hospedar(PORTA):
		Notify.good("Mundo aberto. Passe o seu IP para o seu amigo.")
	else:
		Notify.bad(Rede.erro)


func _entrar() -> void:
	var alvo := _endereco.text.strip_edges()
	if alvo == "":
		Notify.bad("Escreva o IP do host primeiro.")
		return
	AudioManager.tocar_ui(&"ui_clique")
	SaveManager.set_setting("ultimo_host", alvo)
	if not Rede.entrar(alvo, PORTA):
		Notify.bad(Rede.erro)


func _atualizar() -> void:
	if _estado == null:
		return

	match Rede.estado:
		Rede.Estado.HOSPEDANDO:
			_estado.text = "Hospedando na porta %d  ·  %d jogador(es) no mundo." % [
				PORTA, Rede.jogadores.size()
			]
		Rede.Estado.CONECTANDO:
			_estado.text = "Conectando..."
		Rede.Estado.CONECTADO:
			_estado.text = "Conectado  ·  %d jogador(es) no mundo." % Rede.jogadores.size()
		_:
			_estado.text = Rede.erro if Rede.erro != "" else "Você está jogando sozinho."

	var ligado := Rede.online()
	_botao_hospedar.disabled = ligado
	_botao_entrar.disabled = ligado
	_endereco.editable = not ligado
	_botao_sair.visible = ligado

	for filho in _lista.get_children():
		_lista.remove_child(filho)
		filho.queue_free()

	if Rede.jogadores.is_empty():
		_lista.add_child(Design.caption("ninguém ainda"))
		return

	for id in Rede.jogadores:
		var info: Dictionary = Rede.jogadores[id]
		var linha := Design.hbox(Design.S_SM)
		var nome := Design.label(
			String(info.get("nome", "?")) + ("  (você)" if id == Rede.meu_id() else ""),
			Design.FS_BODY, Design.TEXT
		)
		nome.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		linha.add_child(nome)
		linha.add_child(Design.caption(DataManager.get_map_name(String(info.get("mapa", "")))))
		_lista.add_child(linha)


func _fechar() -> void:
	AudioManager.tocar_ui(&"ui_alternar")
	fechado.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cancel"):
		get_viewport().set_input_as_handled()
		_fechar()
