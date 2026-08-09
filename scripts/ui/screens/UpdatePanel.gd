class_name UpdatePanel
extends CanvasLayer
## Aviso de versão nova, com o que mudou e o botão de atualizar.
##
## Só aparece quando existe release mais nova de verdade — nada de "você está em
## dia!" toda vez que o jogo abre. Atualizar é escolha: dá para jogar a versão
## atual e atualizar depois, mas o aviso diz o custo disso quando o jogo é
## online (versões diferentes conversando mal).

signal fechado()

var _titulo: Label = null
var _notas: RichTextLabel = null
var _barra: ProgressBar = null
var _botao: Button = null
var _depois: Button = null
var _estado: Label = null


static func mostrar(pai: Node, info: Dictionary) -> UpdatePanel:
	var painel := UpdatePanel.new()
	painel.name = "UpdatePanel"
	pai.add_child(painel)
	painel._preencher(info)
	return painel


func _ready() -> void:
	layer = 70
	process_mode = Node.PROCESS_MODE_ALWAYS
	_construir()
	Atualizador.progresso.connect(_ao_progredir)
	Atualizador.falhou.connect(_ao_falhar)


func _construir() -> void:
	var raiz := Control.new()
	raiz.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(raiz)

	var scrim := ColorRect.new()
	scrim.color = Color(0.02, 0.03, 0.04, 0.78)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	raiz.add_child(scrim)

	var centro := CenterContainer.new()
	centro.set_anchors_preset(Control.PRESET_FULL_RECT)
	raiz.add_child(centro)

	var cartao := Design.panel(Design.SURFACE)
	Responsivo.caixa(cartao, Vector2(560, 460), Vector2(0.7, 0.8))
	centro.add_child(cartao)

	var coluna := Design.vbox(Design.S_MD)
	cartao.add_child(coluna)

	_titulo = Design.heading("Atualização disponível")
	coluna.add_child(_titulo)
	coluna.add_child(Design.divider())

	_notas = RichTextLabel.new()
	_notas.bbcode_enabled = false
	_notas.fit_content = false
	_notas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_notas.custom_minimum_size = Vector2(0, 190)
	_notas.add_theme_font_size_override("normal_font_size", Design.FS_LABEL)
	_notas.add_theme_color_override("default_color", Design.TEXT)
	var fonte := Design.ui_font()
	if fonte != null:
		_notas.add_theme_font_override("normal_font", fonte)
	coluna.add_child(_notas)

	_barra = Design.meter(Design.XP, 8)
	_barra.value = 0.0
	_barra.visible = false
	coluna.add_child(_barra)

	_estado = Design.caption("")
	coluna.add_child(_estado)

	coluna.add_child(Design.divider())
	var acoes := Design.hbox(Design.S_SM)
	coluna.add_child(acoes)

	_depois = Design.button("Jogar assim mesmo", "ghost")
	_depois.pressed.connect(_fechar)
	acoes.add_child(_depois)
	acoes.add_child(Design.expander())

	_botao = Design.button("Atualizar e reiniciar", "primary")
	_botao.pressed.connect(_atualizar)
	acoes.add_child(_botao)


func _preencher(info: Dictionary) -> void:
	_titulo.text = ("Versão %s disponível" % info.get("versao", "?")).to_upper()
	var notas := String(info.get("notas", "")).strip_edges()
	_notas.text = notas if notas != "" else "Sem notas nesta versão."
	_estado.text = "Você está na %s. Num jogo online, versões diferentes podem não conversar direito." % (
		Atualizador.versao_local()
	)


func _atualizar() -> void:
	_botao.disabled = true
	_depois.disabled = true
	_barra.visible = true
	_estado.text = "Baixando..."
	AudioManager.tocar_ui(&"ui_clique")
	Atualizador.aplicar()


func _ao_progredir(bytes: int, total: int) -> void:
	if total <= 0:
		_estado.text = "Baixando... %.1f MB" % (bytes / 1048576.0)
		return
	_barra.value = clampf(float(bytes) / float(total), 0.0, 1.0)
	_estado.text = "Baixando... %.1f de %.1f MB" % [bytes / 1048576.0, total / 1048576.0]


func _ao_falhar(motivo: String) -> void:
	_barra.visible = false
	_botao.disabled = false
	_depois.disabled = false
	_estado.text = motivo
	_estado.add_theme_color_override("font_color", Design.DANGER)


func _fechar() -> void:
	fechado.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cancel") and not _botao.disabled:
		get_viewport().set_input_as_handled()
		_fechar()
