class_name GuardaRoupa
extends Control
## Monta roupa no personagem e grava o resultado em `data/roupas.json`.
##
## Existe porque acertar roupa por descrição não funciona. A conversa era "está
## bugado" → eu chuto → foto → "ainda está ruim", e cada volta custava uma
## exportação. Aqui você marca as peças, vê no personagem na hora e salva.
##
## O que dá para fazer:
##   - ligar e desligar cada peça, **de qualquer conjunto** (o corpo do Camponês
##     por baixo do colete do Patrulheiro é o caso que motivou isto)
##   - subir, descer e escalar a peça selecionada, para quando ela flutua
##   - salvar, e o jogo passa a usar
##
## O que **não** dá, e é honesto dizer: arrastar peça pelo espaço. Elas são
## skinadas — deformam com o esqueleto —, então a posição vem do osso e não do
## nó. O deslocamento aqui é ajuste fino de centímetros, não mudança de lugar.
##
## Só existe em build de debug: é ferramenta de quem faz o jogo.

const PASSO_DESLOCAMENTO := 0.01
const LIMITE_DESLOCAMENTO := 0.25
const ESCALA_MIN := 0.90
const ESCALA_MAX := 1.10

var _jogador: PlayerController = null
var _sexo := "masculino"
var _indice_conjunto := 0
var _conjuntos: Array = []
var _pecas_ligadas: Array[String] = []
var _ajustes: Dictionary = {}
var _peca_selecionada := ""

var _lista: VBoxContainer = null
var _rodape: Label = null
var _titulo: Label = null
## A HUD, para esconder enquanto a ferramenta esta aberta. Recebida de fora: a
## primeira versao procurava por um grupo "hud" que nao existe, e a funcao nao
## fazia nada em silencio -- que e pior do que nao ter a funcao.
var _hud: CanvasLayer = null


static func criar(jogador: PlayerController, hud: CanvasLayer = null) -> GuardaRoupa:
	var no := GuardaRoupa.new()
	no.name = "GuardaRoupa"
	no._jogador = jogador
	no._hud = hud
	return no


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_carregar_do_personagem()
	_montar()
	# A HUD sai enquanto a ferramenta esta aberta: ela fica exatamente por cima
	# do painel, e aqui o que interessa e o personagem, nao o ouro.
	_mostrar_hud(false)


## Começa do que o personagem está vestindo agora: abrir a ferramenta não pode
## desfazer a escolha de quem abriu.
func _carregar_do_personagem() -> void:
	if GameManager.player == null:
		return
	var indice_corpo := int(GameManager.player.appearance.get("body", 0))
	var escolha: Dictionary = PlayerAvatar.PERSONAGENS[clampi(indice_corpo, 0, PlayerAvatar.PERSONAGENS.size() - 1)]
	_sexo = String(escolha.get("sexo", "masculino"))
	_conjuntos = DataManager.conjuntos_de_roupa(_sexo)
	if _conjuntos.is_empty():
		return
	_indice_conjunto = clampi(int(GameManager.player.appearance.get("outfit", 0)), 0, _conjuntos.size() - 1)
	_recarregar_conjunto()


func _recarregar_conjunto() -> void:
	var conjunto: Dictionary = _conjuntos[_indice_conjunto]
	_pecas_ligadas.clear()
	for peca in conjunto.get("pecas", []):
		_pecas_ligadas.append(String(peca))
	_ajustes = (conjunto.get("ajustes", {}) as Dictionary).duplicate(true)


func _montar() -> void:
	var scrim := ColorRect.new()
	scrim.color = Color(0, 0, 0, 0.35)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scrim)

	# Encostado à direita: o personagem fica visível à esquerda enquanto se
	# mexe. Uma janela no meio da tela tapava justamente o que se quer ver.
	var painel := Design.panel(Design.SURFACE)
	painel.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	# 470 e nao 420: com quatro botoes de ajuste por linha, 420 cortava o ultimo
	# contra a borda da tela.
	painel.offset_left = -470
	add_child(painel)

	var coluna := Design.vbox(Design.S_MD)
	painel.add_child(coluna)

	_titulo = Design.heading("Guarda-roupa")
	coluna.add_child(_titulo)
	coluna.add_child(Design.caption(
		"Marque as peças e veja no personagem. Elas podem vir de conjuntos diferentes."
	))
	coluna.add_child(Design.divider())

	var linha_conjunto := Design.hbox(Design.S_SM)
	for i in _conjuntos.size():
		var indice := i
		var botao := Design.button(String(_conjuntos[i].get("nome", "?")))
		botao.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		botao.pressed.connect(func():
			_indice_conjunto = indice
			_recarregar_conjunto()
			_redesenhar()
			_aplicar()
		)
		linha_conjunto.add_child(botao)
	coluna.add_child(linha_conjunto)
	coluna.add_child(Design.divider())

	_lista = Design.vbox(Design.S_XS)
	coluna.add_child(Responsivo.rolagem(_lista))

	coluna.add_child(Design.divider())
	_rodape = Design.caption("")
	_rodape.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	coluna.add_child(_rodape)

	var acoes := Design.hbox(Design.S_SM)
	var salvar := Design.button("Salvar", "primary")
	salvar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	salvar.pressed.connect(_salvar)
	acoes.add_child(salvar)

	var fechar := Design.button("Fechar")
	fechar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fechar.pressed.connect(queue_free)
	acoes.add_child(fechar)
	coluna.add_child(acoes)

	_redesenhar()


func _redesenhar() -> void:
	for filho in _lista.get_children():
		filho.queue_free()

	for peca in DataManager.pecas_de_roupa(_sexo):
		var nome := String(peca)
		var linha := Design.hbox(Design.S_XS)

		var marca := Design.check(_rotulo_curto(nome), _pecas_ligadas.has(nome))
		marca.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		marca.toggled.connect(func(ligado: bool):
			if ligado and not _pecas_ligadas.has(nome):
				_pecas_ligadas.append(nome)
			elif not ligado:
				_pecas_ligadas.erase(nome)
			_peca_selecionada = nome
			_aplicar()
			_atualizar_rodape()
		)
		linha.add_child(marca)

		# Sobe, desce e escala: só aparecem na peça ligada, porque numa peça
		# desligada eles não teriam o que mexer.
		if _pecas_ligadas.has(nome):
			linha.add_child(_botao_ajuste(nome, "▲", Vector3(0, PASSO_DESLOCAMENTO, 0)))
			linha.add_child(_botao_ajuste(nome, "▼", Vector3(0, -PASSO_DESLOCAMENTO, 0)))
			linha.add_child(_botao_escala(nome, "+", 0.01))
			linha.add_child(_botao_escala(nome, "−", -0.01))

		_lista.add_child(linha)

	_atualizar_rodape()


func _botao_ajuste(peca: String, texto: String, passo: Vector3) -> Button:
	var botao := Design.button(texto)
	botao.custom_minimum_size = Vector2(34, 0)
	botao.pressed.connect(func():
		var atual := _deslocamento(peca) + passo
		atual = atual.clampf(-LIMITE_DESLOCAMENTO, LIMITE_DESLOCAMENTO)
		_gravar_ajuste(peca, "deslocamento", [atual.x, atual.y, atual.z])
		_peca_selecionada = peca
		_aplicar()
		_atualizar_rodape()
	)
	return botao


func _botao_escala(peca: String, texto: String, passo: float) -> Button:
	var botao := Design.button(texto)
	botao.custom_minimum_size = Vector2(34, 0)
	botao.pressed.connect(func():
		var atual := clampf(_escala(peca) + passo, ESCALA_MIN, ESCALA_MAX)
		_gravar_ajuste(peca, "escala", atual)
		_peca_selecionada = peca
		_aplicar()
		_atualizar_rodape()
	)
	return botao


func _deslocamento(peca: String) -> Vector3:
	var lista: Array = _ajustes.get(peca, {}).get("deslocamento", [])
	if lista.size() != 3:
		return Vector3.ZERO
	return Vector3(float(lista[0]), float(lista[1]), float(lista[2]))


func _escala(peca: String) -> float:
	return float(_ajustes.get(peca, {}).get("escala", 1.0))


func _gravar_ajuste(peca: String, chave: String, valor: Variant) -> void:
	if not _ajustes.has(peca):
		_ajustes[peca] = {}
	(_ajustes[peca] as Dictionary)[chave] = valor


## Escreve no conjunto em memória e remonta o personagem. É o "ver na hora":
## sem isto a ferramenta seria um editor de texto com botões.
func _aplicar() -> void:
	if _conjuntos.is_empty():
		return
	var conjunto: Dictionary = _conjuntos[_indice_conjunto]
	conjunto["pecas"] = _pecas_ligadas.duplicate()
	conjunto["ajustes"] = _ajustes.duplicate(true)

	if _jogador != null and is_instance_valid(_jogador) and GameManager.player != null:
		var aparencia: Dictionary = GameManager.player.appearance.duplicate()
		aparencia["outfit"] = _indice_conjunto
		# Forçar a remontagem: `apply_appearance` sai cedo quando nada mudou, e
		# aqui o que mudou foi a roupa por baixo, não a aparência.
		_jogador.avatar.apply_appearance({})
		_jogador.avatar.apply_appearance(aparencia)


func _atualizar_rodape() -> void:
	if _peca_selecionada == "":
		_rodape.text = "%d peça(s) vestida(s)." % _pecas_ligadas.size()
		return
	var d := _deslocamento(_peca_selecionada)
	_rodape.text = "%s — altura %+.2f m, escala %.2fx" % [
		_rotulo_curto(_peca_selecionada), d.y, _escala(_peca_selecionada)
	]


## "Male_Ranger_Acc_Pauldron" vira "Ranger Acc Pauldron": o prefixo de sexo é o
## mesmo em todas e só ocupa espaço na lista.
func _rotulo_curto(peca: String) -> String:
	var texto := peca.replace("Male_", "").replace("Female_", "")
	return texto.replace("_", " ")


func _salvar() -> void:
	var caminho := "res://data/roupas.json"
	var arquivo := FileAccess.open(caminho, FileAccess.READ)
	if arquivo == null:
		_rodape.text = "Não consegui abrir %s." % caminho
		return
	var doc: Variant = JSON.parse_string(arquivo.get_as_text())
	arquivo.close()
	if not (doc is Dictionary):
		_rodape.text = "roupas.json não é um objeto JSON."
		return

	(doc as Dictionary)["conjuntos"][_sexo] = _conjuntos

	# `res://` só é gravável rodando pelo projeto; no jogo exportado ele é
	# somente leitura. Dizer isso é melhor do que falhar em silêncio.
	var saida := FileAccess.open(caminho, FileAccess.WRITE)
	if saida == null:
		_rodape.text = "Sem permissão de escrita — isto só funciona rodando pelo projeto, não no .exe."
		return
	saida.store_string(JSON.stringify(doc, "  "))
	saida.close()
	_rodape.text = "Salvo em data/roupas.json. Commite o arquivo para o resto da equipe ver."
	GameLog.info(GameLog.Channel.SYSTEM, "Guarda-roupa salvo em %s." % caminho)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cancel"):
		get_viewport().set_input_as_handled()
		queue_free()


func _mostrar_hud(visivel: bool) -> void:
	if _hud != null and is_instance_valid(_hud):
		_hud.visible = visivel


func _exit_tree() -> void:
	_mostrar_hud(true)
