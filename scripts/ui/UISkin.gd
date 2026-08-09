class_name UISkin
extends RefCounted
## Pele da interface: transforma os PNGs do UI Pack RPG do Kenney (CC0) em
## StyleBox prontos para o `Design` usar.
##
## Por que existe uma camada só para isso:
##  · as barras do pacote vêm em três pedaços (esquerda/meio/direita). Aqui elas
##    são coladas numa textura só, com margens de 9-slice, para virar uma
##    StyleBoxTexture que estica sem deformar as pontas;
##  · cada StyleBox é criado uma vez e reaproveitado — a interface é reconstruída
##    a cada abertura de painel, e criar dezenas de StyleBox por vez seria
##    desperdício;
##  · se o pacote sumir, tudo devolve `null` e o Design cai no visual chapado de
##    antes. O jogo não quebra por falta de asset.

const PASTA := "res://assets/ui/rpg/"

## Margens de 9-slice medidas nas imagens do pacote.
const MARGEM_PAINEL := 18
const MARGEM_PAINEL_INSET := 14
const MARGEM_BOTAO := 16
const MARGEM_BARRA := 9

## Altura das peças de barra no pacote.
const ALTURA_BARRA := 18
const LARGURA_PONTA := 9
const LARGURA_MEIO := 18

static var _cache: Dictionary = {}
static var _disponivel: int = -1  ## -1 = não checado, 0 = não, 1 = sim


## Falso quando o pacote não está no projeto: o Design usa isso para decidir
## entre a pele com imagem e o visual chapado.
static func disponivel() -> bool:
	if _disponivel == -1:
		_disponivel = 1 if ResourceLoader.exists(PASTA + "panel_beige.png") else 0
		if _disponivel == 0:
			GameLog.warn(GameLog.Channel.UI, "Pacote de UI ausente; usando o visual chapado.")
	return _disponivel == 1


static func textura(nome: String) -> Texture2D:
	var caminho := PASTA + nome + ".png"
	if not ResourceLoader.exists(caminho):
		return null
	return load(caminho)


# --- painéis e botões ---------------------------------------------------------

## `variante`: beige | beigeLight | brown | blue
static func painel(variante: String = "beige", tinta: Color = Color.WHITE) -> StyleBoxTexture:
	return _estilo("panel_" + variante, MARGEM_PAINEL, tinta)


## Painel afundado, para listas e trilhos.
static func painel_inset(variante: String = "beige", tinta: Color = Color.WHITE) -> StyleBoxTexture:
	return _estilo("panelInset_" + variante, MARGEM_PAINEL_INSET, tinta)


## `estado`: normal | pressed. `variante`: brown | beige | grey | blue
static func botao(variante: String = "brown", pressionado: bool = false, tinta: Color = Color.WHITE) -> StyleBoxTexture:
	var nome := "buttonLong_" + variante + ("_pressed" if pressionado else "")
	return _estilo(nome, MARGEM_BOTAO, tinta)


static func _estilo(nome: String, margem: int, tinta: Color) -> StyleBoxTexture:
	var chave := "%s|%d|%s" % [nome, margem, tinta.to_html()]
	if _cache.has(chave):
		return _cache[chave]

	var tex := textura(nome)
	if tex == null:
		_cache[chave] = null
		return null

	var estilo := StyleBoxTexture.new()
	estilo.texture = tex
	estilo.texture_margin_left = margem
	estilo.texture_margin_right = margem
	estilo.texture_margin_top = margem
	estilo.texture_margin_bottom = margem
	estilo.modulate_color = tinta
	_cache[chave] = estilo
	return estilo


# --- barras -------------------------------------------------------------------

## `cor`: Back | Red | Green | Blue | Yellow
##
## As três peças viram uma textura só de 36x18: ponta esquerda, meio e ponta
## direita. Com margem 9 nos lados, só o meio estica.
static func barra(cor: String) -> StyleBoxTexture:
	var chave := "estilo_barra|" + cor
	if _cache.has(chave):
		return _cache[chave]

	var tex := textura_de_barra(cor)
	if tex == null:
		_cache[chave] = null
		return null

	var estilo := StyleBoxTexture.new()
	estilo.texture = tex
	estilo.texture_margin_left = MARGEM_BARRA
	estilo.texture_margin_right = MARGEM_BARRA
	estilo.texture_margin_top = 0
	estilo.texture_margin_bottom = 0
	_cache[chave] = estilo
	return estilo


## A mesma barra como textura crua, para quem monta a peça com NinePatchRect em
## vez de StyleBox (a moldura do jogador).
static func textura_de_barra(cor: String) -> Texture2D:
	var chave := "barra|" + cor
	if _cache.has(chave):
		return _cache[chave]

	var esquerda := textura("bar%s_horizontalLeft" % cor)
	var meio := _meio_da_barra(cor)
	var direita := textura("bar%s_horizontalRight" % cor)
	if esquerda == null or meio == null or direita == null:
		_cache[chave] = null
		return null

	var largura := LARGURA_PONTA * 2 + LARGURA_MEIO
	var imagem := Image.create(largura, ALTURA_BARRA, false, Image.FORMAT_RGBA8)
	imagem.fill(Color(0, 0, 0, 0))
	_colar(imagem, esquerda, 0)
	_colar(imagem, meio, LARGURA_PONTA)
	_colar(imagem, direita, LARGURA_PONTA + LARGURA_MEIO)

	var tex := ImageTexture.create_from_image(imagem)
	_cache[chave] = tex
	return tex


## O pacote batizou o meio de todas as barras de `_horizontalMid`, menos o da
## azul, que saiu como `barBlue_horizontalBlue`. Sem este desvio a barra de XP
## voltava nula e caía calada no visual chapado.
static func _meio_da_barra(cor: String) -> Texture2D:
	var meio := textura("bar%s_horizontalMid" % cor)
	if meio != null:
		return meio
	return textura("bar%s_horizontal%s" % [cor, cor])


static func _colar(destino: Image, origem: Texture2D, x: int) -> void:
	var fonte := origem.get_image()
	if fonte == null:
		return
	if fonte.is_compressed():
		fonte.decompress()
	fonte.convert(Image.FORMAT_RGBA8)
	destino.blit_rect(fonte, Rect2i(Vector2i.ZERO, fonte.get_size()), Vector2i(x, 0))


## Nome da barra do pacote que mais combina com uma cor lógica do jogo.
static func barra_para(papel: String) -> String:
	match papel:
		"vida":
			return "Red"
		"xp":
			return "Blue"
		"aliado":
			return "Green"
		"recarga":
			return "Yellow"
		_:
			return "Back"
