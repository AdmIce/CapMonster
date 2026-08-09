class_name ChatPanel
extends Control
## A janela de conversa, no canto inferior esquerdo.
##
## Fechada, ela é só o registro das últimas linhas, apagado e sem capturar
## clique — o mundo continua sendo o assunto da tela. Enter abre a caixa de
## digitação; Esc fecha sem mandar. Aberta, ela fica opaca, rola e recebe mouse.
##
## **Enquanto você digita, o personagem não anda.** O controlador é desligado na
## abertura e religado no fechamento. Sem isso, escrever "was" faria o boneco
## correr — é a mesma armadilha do foco de botão que já ligava o modo automático
## sozinho, e aqui ela seria constante.

const LARGURA := 460
const ALTURA_REGISTRO := 172
## Fechado ele fica translúcido para não tapar o mundo, mas não tanto que o
## texto vire mancha: 0.62 deixava o pergaminho lavado sobre a grama clara.
const OPACIDADE_PARADO := 0.85
## Piso do desbotamento por silêncio. Zero seria sumir de vez e fazer o jogador
## achar que perdeu mensagem.
const OPACIDADE_APAGADA := 0.3

## Quantas frases guardar para as setas cima/baixo.
const HISTORICO_DIGITADO := 20

## Tempo até o registro desbotar depois da última mensagem, quando fechado.
const SEGUNDOS_ATE_APAGAR := 12.0

var _registro: RichTextLabel = null
var _caixa: LineEdit = null
var _linha_entrada: Control = null
var _rotulo_canal: Label = null
var _painel: PanelContainer = null

var _jogador: PlayerController = null
var _aberto: bool = false
var _silencio: float = 0.0

## Ultimas linhas digitadas, da mais nova para a mais antiga, navegadas com as
## setas. Repetir um comando longo na mao a cada tentativa e o tipo de atrito
## que faz a pessoa parar de usar o chat.
var _digitadas: Array[String] = []
var _indice_historico: int = -1


## Altura reservada para a linha de digitação. Ela fica guardada mesmo com o
## chat fechado: sem isso os cartões da equipe pulavam para baixo toda vez que
## alguém apertava Enter.
const ALTURA_ENTRADA := 44


func _init() -> void:
	# Dentro de um contêiner as âncoras não valem — quem manda é o tamanho
	# mínimo. Sem ele o chat nasceria com zero de altura e ninguém veria nada.
	custom_minimum_size = Vector2(LARGURA, ALTURA_REGISTRO + ALTURA_ENTRADA)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	_construir()
	Chat.mensagem.connect(_ao_receber)
	Chat.historico_limpo.connect(_redesenhar)
	_redesenhar()
	aplicar_estado()


## O HUD entrega o controlador para o chat poder travar o movimento.
func ligar(jogador: PlayerController) -> void:
	_jogador = jogador


func _construir() -> void:
	var coluna := Design.vbox(Design.S_XS)
	coluna.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(coluna)

	_painel = Design.card(Design.TEXT_MUTED)
	_painel.custom_minimum_size = Vector2(LARGURA, ALTURA_REGISTRO)
	coluna.add_child(_painel)

	_registro = RichTextLabel.new()
	_registro.bbcode_enabled = true
	_registro.scroll_following = true
	_registro.fit_content = false
	_registro.selection_enabled = true
	_registro.custom_minimum_size = Vector2(LARGURA - Design.S_LG * 2, ALTURA_REGISTRO - Design.S_MD * 2)
	_registro.add_theme_font_size_override("normal_font_size", Design.FS_LABEL)
	var fonte := Design.ui_font()
	if fonte != null:
		_registro.add_theme_font_override("normal_font", fonte)
	_painel.add_child(_registro)

	_linha_entrada = Design.hbox(Design.S_XS)
	coluna.add_child(_linha_entrada)

	_rotulo_canal = Design.label("", Design.FS_LABEL, Design.GOLD_CLARO)
	Design.sobre_o_mundo(_rotulo_canal, 3)
	_linha_entrada.add_child(_rotulo_canal)

	_caixa = Design.line_edit("mensagem...", Chat.LIMITE_CARACTERES)
	_caixa.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_caixa.custom_minimum_size = Vector2(LARGURA - 90, 0)
	_caixa.text_submitted.connect(_ao_enviar)
	_linha_entrada.add_child(_caixa)


# --- abrir e fechar -----------------------------------------------------------

func aberto() -> bool:
	return _aberto


func abrir(prefixo: String = "") -> void:
	if _aberto:
		return
	_aberto = true
	_caixa.text = prefixo
	aplicar_estado()
	_caixa.grab_focus()
	_caixa.caret_column = _caixa.text.length()


func fechar() -> void:
	if not _aberto:
		return
	_aberto = false
	_caixa.text = ""
	_caixa.release_focus()
	aplicar_estado()


## Publica de proposito: o HUD passa `Design.ignore_mouse` no proprio galho
## inteiro depois de montar, e isso apagaria a captura de mouse do chat. Ele
## chama isto em seguida para devolver.
func aplicar_estado() -> void:
	_linha_entrada.visible = _aberto
	_rotulo_canal.text = "[%s]" % Chat.NOME_CANAL.get(Chat.canal_atual, "Geral")
	modulate.a = 1.0 if _aberto else OPACIDADE_PARADO
	_silencio = 0.0

	# Fechado o chat não pode roubar clique do mundo nem rolagem do zoom.
	var filtro := Control.MOUSE_FILTER_STOP if _aberto else Control.MOUSE_FILTER_IGNORE
	_painel.mouse_filter = filtro
	_registro.mouse_filter = filtro
	_caixa.mouse_filter = filtro
	_linha_entrada.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_registro.scroll_active = _aberto

	if _jogador != null and is_instance_valid(_jogador):
		_jogador.input_enabled = not _aberto


func _ao_enviar(texto: String) -> void:
	var limpo := texto.strip_edges()
	if limpo != "" and (_digitadas.is_empty() or _digitadas[0] != limpo):
		_digitadas.insert(0, limpo)
		if _digitadas.size() > HISTORICO_DIGITADO:
			_digitadas.resize(HISTORICO_DIGITADO)
	_indice_historico = -1

	Chat.enviar(texto)
	# Mandar mantém a caixa aberta, como em todo jogo online: conversa é uma
	# sequência de frases, não uma frase só.
	_caixa.text = ""
	_rotulo_canal.text = "[%s]" % Chat.NOME_CANAL.get(Chat.canal_atual, "Geral")


# --- desenho ------------------------------------------------------------------

func _ao_receber(linha: Dictionary) -> void:
	_registro.append_text(_formatar(linha) + "\n")
	_silencio = 0.0
	if not _aberto:
		modulate.a = OPACIDADE_PARADO


func _redesenhar() -> void:
	_registro.clear()
	for linha in Chat.historico:
		_registro.append_text(_formatar(linha) + "\n")


func _formatar(linha: Dictionary) -> String:
	var canal: int = int(linha.get("canal", Chat.Canal.GERAL))
	var cor: String = Chat.COR_CANAL.get(canal, "#E8DCC4")
	var hora := String(linha.get("hora", ""))
	var texto := String(linha.get("texto", ""))

	if canal == Chat.Canal.SISTEMA:
		return "[color=#8B7A66]%s[/color] [color=%s]%s[/color]" % [hora, cor, texto]

	var autor := String(linha.get("autor", "?"))
	var etiqueta := ""
	match canal:
		Chat.Canal.LOCAL:
			etiqueta = "[Local] "
		Chat.Canal.SUSSURRO:
			# Quem mandou vê "para Fulano"; quem recebeu vê "Fulano sussurra".
			etiqueta = "[para %s] " % linha.get("alvo", "?") if linha.get("proprio", false) else "[sussurro] "
	return "[color=#8B7A66]%s[/color] [color=%s]%s%s:[/color] [color=#3B2E22]%s[/color]" % [
		hora, cor, etiqueta, autor, texto
	]


## `passo` positivo anda para tras no tempo (mais antigo), como em terminal.
func _navegar_historico(passo: int) -> void:
	if _digitadas.is_empty():
		return
	_indice_historico = clampi(_indice_historico + passo, -1, _digitadas.size() - 1)
	_caixa.text = "" if _indice_historico < 0 else _digitadas[_indice_historico]
	_caixa.caret_column = _caixa.text.length()


func _rolar(linhas: int) -> void:
	var barra := _registro.get_v_scroll_bar()
	if barra != null:
		barra.value += linhas * 20.0


func _process(delta: float) -> void:
	if _aberto:
		return
	# Sem conversa por um tempo, o registro sai da frente sozinho. Volta assim que
	# alguém falar de novo, ou quando o chat abrir.
	_silencio += delta
	if _silencio > SEGUNDOS_ATE_APAGAR:
		modulate.a = lerpf(modulate.a, OPACIDADE_APAGADA, clampf(delta * 1.5, 0.0, 1.0))


# --- entrada ------------------------------------------------------------------
#
# `_input` e não `_unhandled_input`: com a caixa em foco, o LineEdit consome o
# Enter antes de chegar ao não-tratado, e o Esc nunca fecharia o chat.

func _input(event: InputEvent) -> void:
	if _aberto:
		if event.is_action_pressed("cancel"):
			get_viewport().set_input_as_handled()
			fechar()
			return
		if event is InputEventKey and (event as InputEventKey).pressed:
			match (event as InputEventKey).keycode:
				KEY_UP:
					get_viewport().set_input_as_handled()
					_navegar_historico(1)
				KEY_DOWN:
					get_viewport().set_input_as_handled()
					_navegar_historico(-1)
				KEY_PAGEUP:
					get_viewport().set_input_as_handled()
					_rolar(-4)
				KEY_PAGEDOWN:
					get_viewport().set_input_as_handled()
					_rolar(4)
		return

	if event.is_action_pressed("chat"):
		get_viewport().set_input_as_handled()
		abrir()
	elif event.is_action_pressed("chat_comando"):
		get_viewport().set_input_as_handled()
		abrir("/")
