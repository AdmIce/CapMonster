class_name Design
extends RefCounted
## The internal design system: one palette, one spacing scale, one set of
## widget factories. Every screen builds its UI through these helpers, which is
## what keeps margins, radii, type sizes and colours identical across the game.
##
## Screens are built in code rather than in .tscn files on purpose: the layout
## rules live here, so a change to (for example) button padding updates every
## screen at once instead of 20 scene files drifting apart.

# --- spacing scale ------------------------------------------------------------
const S_XS := 4
const S_SM := 8
const S_MD := 12
const S_LG := 16
const S_XL := 24
const S_XXL := 32
const S_HUGE := 48

# --- radii --------------------------------------------------------------------
const R_SM := 4
const R_MD := 8
const R_LG := 12

# --- paleta -------------------------------------------------------------------
#
# A interface usa os painéis de pergaminho do UI Pack RPG do Kenney, então o
# texto é escuro sobre claro. As cores TEXT_* abaixo valem DENTRO de painel.
# Para texto solto sobre o fundo escuro ou sobre o mundo 3D, use as TEXT_CLARO_*.
const BACKGROUND := Color("#0B0D10")
const SURFACE := Color("#161A20")
const SURFACE_RAISED := Color("#1E242C")
const SURFACE_SUNKEN := Color("#0F1216")
const BORDER := Color("#2A323C")
const BORDER_STRONG := Color("#3C4753")

const TEXT := Color("#3B2E22")
const TEXT_MUTED := Color("#6B5B49")
const TEXT_DIM := Color("#8B7A66")

## Texto sobre fundo escuro (tela de título, cabeçalhos fora de painel, mundo).
const TEXT_CLARO := Color("#EFE7D8")
const TEXT_CLARO_MUTED := Color("#B9AE9C")
const TEXT_CLARO_DIM := Color("#8B8375")

const ACCENT := Color("#4F8A6B")
const ACCENT_HOVER := Color("#5FA37E")
const ACCENT_PRESSED := Color("#3F7057")
const GOLD := Color("#B07A1E")
const GOLD_CLARO := Color("#F2C75C")
const DANGER := Color("#A63A2B")
const HEALTH := Color("#4E8A34")
const HEALTH_LOW := Color("#A63A2B")
const XP := Color("#3A6E96")

## Tintas aplicadas nos painéis do pacote para diferenciar hierarquia.
const TINTA_NEUTRA := Color.WHITE
const TINTA_DESTAQUE := Color(1.0, 0.98, 0.9)
const TINTA_APAGADA := Color(0.86, 0.84, 0.8)

# --- type scale ---------------------------------------------------------------
const FS_DISPLAY := 46
const FS_TITLE := 30
const FS_HEADING := 20
const FS_BODY := 15
const FS_LABEL := 13
const FS_CAPTION := 11

const DISPLAY_FONT_PATH := "res://assets/fonts/display.ttf"
const UI_FONT_PATH := "res://assets/fonts/ui.ttf"

static var _display_font: Font = null
static var _ui_font: Font = null
static var _fonts_resolved: bool = false


static func _resolve_fonts() -> void:
	if _fonts_resolved:
		return
	_fonts_resolved = true
	if ResourceLoader.exists(DISPLAY_FONT_PATH):
		_display_font = load(DISPLAY_FONT_PATH)
	if ResourceLoader.exists(UI_FONT_PATH):
		_ui_font = load(UI_FONT_PATH)


static func display_font() -> Font:
	_resolve_fonts()
	return _display_font


static func ui_font() -> Font:
	_resolve_fonts()
	return _ui_font


# --- style boxes --------------------------------------------------------------

static func panel_style(
	fill: Color = SURFACE,
	radius: int = R_MD,
	border_width: int = 1,
	border_color: Color = BORDER
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.border_color = border_color
	style.content_margin_left = S_LG
	style.content_margin_right = S_LG
	style.content_margin_top = S_MD
	style.content_margin_bottom = S_MD
	return style


static func empty_style() -> StyleBoxEmpty:
	return StyleBoxEmpty.new()


static func accent_bar_style(fill: Color, radius: int = R_SM) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.content_margin_left = 0
	style.content_margin_right = 0
	style.content_margin_top = 0
	style.content_margin_bottom = 0
	return style


# --- widgets ------------------------------------------------------------------

static func label(
	text: String,
	size: int = FS_BODY,
	color: Color = TEXT,
	use_display_font: bool = false
) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", color)
	var font := display_font() if use_display_font else ui_font()
	if font != null:
		node.add_theme_font_override("font", font)
	return node


## `color` existe porque o mesmo título aparece dentro de painel (texto escuro
## sobre pergaminho) e solto sobre o fundo escuro das telas cheias.
static func heading(text: String, size: int = FS_HEADING, color: Color = TEXT) -> Label:
	var node := label(text.to_upper(), size, color, true)
	node.add_theme_constant_override("line_spacing", 2)
	return node


static func caption(text: String, color: Color = TEXT_DIM) -> Label:
	return label(text, FS_CAPTION, color)


static func body(text: String, color: Color = TEXT_MUTED) -> Label:
	var node := label(text, FS_BODY, color)
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return node


## `focavel` fica desligado de propósito.
##
## Botão com foco de teclado é acionado pelo `ui_accept` do Godot, que vem
## mapeado em Espaço e Enter — as mesmas teclas de interagir e de avançar
## diálogo neste jogo. Com foco, andar pelo mundo ou fechar uma fala acabava
## "clicando" no botão em foco sozinho: foi assim que o modo AUTO ficava ligando
## e desligando e que a loja vendia item sem ninguém mandar.
##
## Só ligue em tela onde navegar por teclado importa e não há jogo rodando atrás
## (o menu principal, por exemplo).
static func button(text: String, variant: String = "default", focavel: bool = false) -> Button:
	var node := Button.new()
	node.text = text
	node.focus_mode = Control.FOCUS_ALL if focavel else Control.FOCUS_NONE
	node.custom_minimum_size = Vector2(0, 40)
	node.add_theme_font_size_override("font_size", FS_BODY)
	var font := ui_font()
	if font != null:
		node.add_theme_font_override("font", font)
	_style_button(node, variant)
	return node


## Botões do pacote: `buttonLong_*` com a variante `_pressed` no estado apertado.
## O hover é o mesmo desenho com um clareamento leve — o pacote não traz peça de
## hover, e inventar uma cor chapada quebraria a leitura.
const BOTAO_VARIANTE := {
	"default": "grey",
	"primary": "brown",
	"danger": "brown",
	"ghost": "grey",
}

const BOTAO_TEXTO := {
	"default": Color("#3B2E22"),
	"primary": Color("#F6EEDF"),
	"danger": Color("#F3D2CB"),
	"ghost": Color("#6B5B49"),
}


static func _style_button(node: Button, variant: String) -> void:
	if _aplicar_pele_botao(node, variant):
		return
	_style_button_chapado(node, variant)


static func _aplicar_pele_botao(node: Button, variant: String) -> bool:
	if not UISkin.disponivel():
		return false
	var pecas := String(BOTAO_VARIANTE.get(variant, "grey"))
	var tinta_danger := Color(1.0, 0.72, 0.66)

	var estados: Array[String] = ["normal", "hover", "pressed", "focus", "disabled"]
	for state in estados:
		var pressionado := state == "pressed"
		var tinta := TINTA_NEUTRA
		match state:
			"hover":
				tinta = Color(1.12, 1.1, 1.05)
			"disabled":
				tinta = Color(0.75, 0.73, 0.7, 0.75)
		if variant == "danger":
			tinta *= tinta_danger
		var estilo := UISkin.botao(pecas, pressionado, tinta)
		if estilo == null:
			return false
		estilo = estilo.duplicate()
		estilo.content_margin_left = S_LG
		estilo.content_margin_right = S_LG
		estilo.content_margin_top = S_SM
		estilo.content_margin_bottom = S_SM
		if variant == "ghost" and state == "normal":
			estilo.modulate_color = Color(1, 1, 1, 0.0)
		node.add_theme_stylebox_override(state, estilo)

	var cor_texto: Color = BOTAO_TEXTO.get(variant, TEXT)
	node.add_theme_color_override("font_color", cor_texto)
	node.add_theme_color_override("font_hover_color", cor_texto)
	node.add_theme_color_override("font_pressed_color", cor_texto)
	node.add_theme_color_override("font_focus_color", cor_texto)
	node.add_theme_color_override("font_disabled_color", Color(cor_texto.r, cor_texto.g, cor_texto.b, 0.45))
	return true


static func _style_button_chapado(node: Button, variant: String) -> void:
	var base := SURFACE_RAISED
	var hover := Color("#28303A")
	var pressed := Color("#141A20")
	var border := BORDER_STRONG
	var text_color := TEXT_CLARO

	match variant:
		"primary":
			base = ACCENT
			hover = ACCENT_HOVER
			pressed = ACCENT_PRESSED
			border = ACCENT_HOVER
			text_color = Color("#0B0D10")
		"danger":
			base = Color("#2A1A18")
			hover = Color("#3A211D")
			pressed = Color("#1E1312")
			border = DANGER
			text_color = Color("#E0A79C")
		"ghost":
			base = Color(0, 0, 0, 0)
			hover = Color(1, 1, 1, 0.06)
			pressed = Color(0, 0, 0, 0.25)
			border = Color(0, 0, 0, 0)
			text_color = TEXT_CLARO_MUTED

	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var fill := base
		match state:
			"hover":
				fill = hover
			"pressed":
				fill = pressed
			"disabled":
				fill = Color(base.r, base.g, base.b, base.a * 0.4)
		var style := panel_style(fill, R_SM, 1, border)
		style.content_margin_left = S_LG
		style.content_margin_right = S_LG
		style.content_margin_top = S_SM
		style.content_margin_bottom = S_SM
		if state == "focus":
			style.border_color = ACCENT_HOVER
			style.border_width_left = 2
			style.border_width_top = 2
			style.border_width_right = 2
			style.border_width_bottom = 2
		node.add_theme_stylebox_override(state, style)

	node.add_theme_color_override("font_color", text_color)
	node.add_theme_color_override("font_hover_color", text_color)
	node.add_theme_color_override("font_pressed_color", text_color)
	node.add_theme_color_override("font_focus_color", text_color)
	node.add_theme_color_override("font_disabled_color", TEXT_DIM)


## Painel de pergaminho. `fill` e `radius` continuam na assinatura porque dezenas
## de chamadas antigas os passam, mas com a pele ligada eles são ignorados: quem
## manda é a imagem. Sem o pacote, cai no retângulo chapado de antes.
static func panel(fill: Color = SURFACE, radius: int = R_MD) -> PanelContainer:
	var node := PanelContainer.new()
	var estilo := _painel_skin("beige", TINTA_NEUTRA)
	node.add_theme_stylebox_override("panel", estilo if estilo != null else panel_style(fill, radius))
	return node


## Painel afundado, para trilhos, listas e caixas de texto.
static func panel_inset(fill: Color = SURFACE_SUNKEN, radius: int = R_SM) -> PanelContainer:
	var node := PanelContainer.new()
	var estilo := _painel_inset_skin("beige", TINTA_NEUTRA)
	node.add_theme_stylebox_override("panel", estilo if estilo != null else panel_style(fill, radius))
	return node


## Painel com uma cor de destaque — usado nos cartões que codificam raridade ou
## elemento. Sem a pele, vira o retângulo com borda colorida de antes.
static func card_style(destaque: Color, realcado: bool = false) -> StyleBox:
	var estilo := _painel_skin("beigeLight" if realcado else "beige", _tinta_de_cartao(destaque))
	if estilo != null:
		return estilo
	return panel_style(SURFACE_RAISED if realcado else SURFACE, R_SM, 2 if realcado else 1, destaque)


static func card(destaque: Color, realcado: bool = false) -> PanelContainer:
	var node := PanelContainer.new()
	node.add_theme_stylebox_override("panel", card_style(destaque, realcado))
	return node


## A tinta multiplica a arte do pergaminho, então uma cor de destaque escura não
## "colore" o cartão: ela apaga o cartão inteiro num tom de barro. O destaque
## entra como véu — matiz preservada, brilho forçado para cima.
static func _tinta_de_cartao(destaque: Color) -> Color:
	var veu := destaque.lerp(Color.WHITE, 0.72)
	var luz := veu.get_luminance()
	if luz < 0.8:
		veu = veu.lerp(Color.WHITE, (0.8 - luz) / maxf(0.01, 1.0 - luz))
	return veu


static func _painel_skin(variante: String, tinta: Color) -> StyleBox:
	if not UISkin.disponivel():
		return null
	var estilo := UISkin.painel(variante, tinta)
	if estilo == null:
		return null
	estilo = estilo.duplicate()
	estilo.content_margin_left = S_LG
	estilo.content_margin_right = S_LG
	estilo.content_margin_top = S_MD
	estilo.content_margin_bottom = S_MD
	return estilo


static func _painel_inset_skin(variante: String, tinta: Color) -> StyleBox:
	if not UISkin.disponivel():
		return null
	var estilo := UISkin.painel_inset(variante, tinta)
	if estilo == null:
		return null
	estilo = estilo.duplicate()
	estilo.content_margin_left = S_MD
	estilo.content_margin_right = S_MD
	estilo.content_margin_top = S_SM
	estilo.content_margin_bottom = S_SM
	return estilo


## Contorno escuro atrás do texto. Obrigatório para rótulo solto por cima do
## mundo 3D: ali o fundo muda de cor a cada passo e nenhuma cor de fonte sozinha
## se garante contra grama clara e sombra escura ao mesmo tempo.
static func sobre_o_mundo(node: Label, espessura: int = 4) -> Label:
	node.add_theme_constant_override("outline_size", espessura)
	node.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.06, 0.85))
	return node


static func vbox(separation: int = S_MD) -> VBoxContainer:
	var node := VBoxContainer.new()
	node.add_theme_constant_override("separation", separation)
	return node


static func hbox(separation: int = S_MD) -> HBoxContainer:
	var node := HBoxContainer.new()
	node.add_theme_constant_override("separation", separation)
	return node


static func spacer(size: int = S_MD, vertical: bool = true) -> Control:
	var node := Control.new()
	if vertical:
		node.custom_minimum_size = Vector2(0, size)
	else:
		node.custom_minimum_size = Vector2(size, 0)
	return node


static func expander() -> Control:
	var node := Control.new()
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return node


static func divider() -> Panel:
	var node := Panel.new()
	node.custom_minimum_size = Vector2(0, 2)
	var style := StyleBoxFlat.new()
	# Linha na cor da madeira do pacote, não no cinza-azulado do tema antigo.
	style.bg_color = Color("#A08A6E")
	node.add_theme_stylebox_override("panel", style)
	return node


## A thin progress bar. Used for HP, XP and cast bars so they read as one family.
## Barra de progresso. Com a pele ligada usa as barras do pacote (que têm ponta
## arredondada e brilho); `fill` vira apenas a escolha de qual cor do pacote
## pegar, e não uma cor chapada.
static func meter(fill: Color, height: int = 6, background: Color = SURFACE_SUNKEN) -> ProgressBar:
	var node := ProgressBar.new()
	node.show_percentage = false
	# As peças do pacote têm 18px de altura: abaixo disso a arte fica espremida.
	node.custom_minimum_size = Vector2(0, maxi(height, 14) if UISkin.disponivel() else height)
	node.min_value = 0.0
	node.max_value = 1.0
	# Range snaps to `step`; without this a 0..1 bar would only ever be 0 or 1.
	node.step = 0.001
	node.value = 1.0
	aplicar_cor_de_barra(node, fill, background)
	return node


## Troca a cor de uma barra já criada, respeitando a pele.
static func aplicar_cor_de_barra(node: ProgressBar, fill: Color, background: Color = SURFACE_SUNKEN) -> void:
	if UISkin.disponivel():
		var fundo := UISkin.barra("Back")
		var frente := UISkin.barra(_barra_do_pacote(fill))
		if fundo != null and frente != null:
			node.add_theme_stylebox_override("background", fundo)
			node.add_theme_stylebox_override("fill", frente)
			return
	node.add_theme_stylebox_override("background", accent_bar_style(background, R_SM))
	node.add_theme_stylebox_override("fill", accent_bar_style(fill, R_SM))


## Casa a cor lógica pedida com a peça de barra mais próxima do pacote.
static func _barra_do_pacote(cor: Color) -> String:
	if cor.is_equal_approx(HEALTH):
		return "Green"
	if cor.is_equal_approx(HEALTH_LOW) or cor.is_equal_approx(DANGER):
		return "Red"
	if cor.is_equal_approx(XP):
		return "Blue"
	if cor.is_equal_approx(GOLD) or cor.is_equal_approx(GOLD_CLARO):
		return "Yellow"
	if cor.is_equal_approx(ACCENT):
		return "Green"
	# Desconhecida: decide pelo matiz.
	var h := cor.h
	if h < 0.06 or h > 0.92:
		return "Red"
	if h < 0.18:
		return "Yellow"
	if h < 0.45:
		return "Green"
	return "Blue"


static func line_edit(placeholder: String, max_length: int = 16) -> LineEdit:
	var node := LineEdit.new()
	node.placeholder_text = placeholder
	node.max_length = max_length
	node.custom_minimum_size = Vector2(0, 40)
	node.add_theme_font_size_override("font_size", FS_BODY)
	node.add_theme_color_override("font_color", TEXT)
	node.add_theme_color_override("font_placeholder_color", TEXT_DIM)
	node.add_theme_color_override("caret_color", ACCENT_PRESSED)
	var pele := _painel_inset_skin("beige", TINTA_NEUTRA)
	if pele != null:
		node.add_theme_stylebox_override("normal", pele)
		node.add_theme_stylebox_override("focus", _painel_inset_skin("beigeLight", TINTA_DESTAQUE))
	else:
		node.add_theme_stylebox_override("normal", panel_style(SURFACE_SUNKEN, R_SM, 1, BORDER_STRONG))
		node.add_theme_stylebox_override("focus", panel_style(SURFACE_SUNKEN, R_SM, 1, ACCENT))
	return node


static func check(text: String, pressed: bool) -> CheckButton:
	var node := CheckButton.new()
	node.text = text
	node.button_pressed = pressed
	node.focus_mode = Control.FOCUS_NONE
	node.add_theme_font_size_override("font_size", FS_BODY)
	node.add_theme_color_override("font_color", TEXT_MUTED)
	node.add_theme_color_override("font_hover_color", TEXT)
	node.add_theme_color_override("font_pressed_color", TEXT)
	return node


## Small rounded chip used for element / rarity tags.
static func chip(text: String, color: Color) -> PanelContainer:
	var container := PanelContainer.new()
	var style := panel_style(Color(color.r, color.g, color.b, 0.16), R_SM, 1, Color(color.r, color.g, color.b, 0.55))
	style.content_margin_left = S_SM
	style.content_margin_right = S_SM
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	container.add_theme_stylebox_override("panel", style)
	container.add_child(label(text.to_upper(), FS_CAPTION, color.lightened(0.25)))
	return container


## Full-screen root used by every menu screen: solid background + centred content.
static func screen_root(node: Control) -> Panel:
	var background := Panel.new()
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	var style := StyleBoxFlat.new()
	style.bg_color = BACKGROUND
	background.add_theme_stylebox_override("panel", style)
	node.add_child(background)
	return background


## Makes a whole subtree click-through. Needed whenever decorative UI sits on
## top of the world or inside a Button - Control defaults to MOUSE_FILTER_STOP,
## which would silently swallow the click.
static func ignore_mouse(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		ignore_mouse(child)


static func margin(all: int) -> MarginContainer:
	var node := MarginContainer.new()
	node.add_theme_constant_override("margin_left", all)
	node.add_theme_constant_override("margin_right", all)
	node.add_theme_constant_override("margin_top", all)
	node.add_theme_constant_override("margin_bottom", all)
	return node
