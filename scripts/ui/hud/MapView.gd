class_name MapView
extends Control
## Desenha o mapa atual a partir dos mesmos dados que constroem o mundo.
##
## Nada aqui é imagem pintada à mão: terreno, zonas, portões, acampamentos e
## chefes saem direto do `maps.json`, e as criaturas saem do grupo
## `wild_creature`. Isso significa que o mapa nunca fica desatualizado em relação
## ao que existe de fato — mexer no JSON muda o mundo e o mapa junto.
##
## O mesmo controle serve de minimapa no canto e de mapa grande em tela cheia:
## só muda o tamanho e o `detalhado`, que liga nomes e legenda.

const COR_FUNDO := Color("#0E1319")
const COR_BORDA := Color("#3C4753")
const COR_LIMITE := Color("#1A222C")
const COR_JOGADOR := Color("#F2C75C")
const COR_CURA := Color("#6FA84A")
const COR_PORTAO := Color("#C9922F")
const COR_CHEFE := Color("#C21F2B")
const COR_NPC := Color("#4A8FB8")
const COR_ZONA := Color("#4F8A6B")

## Cor de cada peça do tilemap, por prefixo do modelo. A vila é feita de peças,
## não de retângulos de terreno, então precisa desta tradução.
const CORES_DE_PECA := {
	"road": Color("#3A3F46"),
	"pavement": Color("#6E7681"),
	"grass": Color("#3E6B44"),
	"building": Color("#7A6A8A"),
}

var map_data: Dictionary = {}
var detalhado: bool = false

## Quando ligado, o mapa cobre o controle inteiro em vez de caber dentro dele.
## O minimapa e redondo: cabendo, sobram faixas vazias em cima e embaixo, que
## dentro de um circulo viram duas fatias pretas sem sentido nenhum.
var preencher: bool = false

var _player: Node3D = null
var _escala: float = 1.0
var _origem := Vector2.ZERO


func configurar(dados: Dictionary, jogador: Node3D, grande: bool = false) -> void:
	map_data = dados
	_player = jogador
	detalhado = grande
	queue_redraw()


func _process(_delta: float) -> void:
	# O jogador e as criaturas se mexem; redesenhar sempre é barato porque tudo
	# aqui é vetor, não textura.
	if visible and _player != null:
		queue_redraw()


# --- conversão ----------------------------------------------------------------

func _preparar() -> bool:
	var limites: Dictionary = map_data.get("bounds", {})
	if limites.is_empty() or size.x <= 4.0 or size.y <= 4.0:
		return false
	var largura := float(limites.get("max_x", 1)) - float(limites.get("min_x", 0))
	var profundidade := float(limites.get("max_z", 1)) - float(limites.get("min_z", 0))
	if largura <= 0.0 or profundidade <= 0.0:
		return false

	var margem := 0.0 if preencher else 8.0
	var horizontal := (size.x - margem * 2.0) / largura
	var vertical := (size.y - margem * 2.0) / profundidade
	_escala = maxf(horizontal, vertical) if preencher else minf(horizontal, vertical)
	# Centraliza o mapa dentro do controle.
	_origem = Vector2(
		(size.x - largura * _escala) * 0.5 - float(limites.get("min_x", 0)) * _escala,
		(size.y - profundidade * _escala) * 0.5 - float(limites.get("min_z", 0)) * _escala
	)
	return true


func _ponto(x: float, z: float) -> Vector2:
	return _origem + Vector2(x * _escala, z * _escala)


func _retangulo(rect: Array) -> Rect2:
	if rect.size() != 4:
		return Rect2()
	var a := _ponto(minf(rect[0], rect[2]), minf(rect[1], rect[3]))
	var b := _ponto(maxf(rect[0], rect[2]), maxf(rect[1], rect[3]))
	return Rect2(a, b - a)


# --- desenho ------------------------------------------------------------------

func _draw() -> void:
	if not _preparar():
		return

	var fundo := StyleBoxFlat.new()
	fundo.bg_color = COR_FUNDO
	fundo.corner_radius_top_left = Design.R_SM
	fundo.corner_radius_top_right = Design.R_SM
	fundo.corner_radius_bottom_left = Design.R_SM
	fundo.corner_radius_bottom_right = Design.R_SM
	fundo.border_width_left = 1
	fundo.border_width_top = 1
	fundo.border_width_right = 1
	fundo.border_width_bottom = 1
	fundo.border_color = COR_BORDA
	draw_style_box(fundo, Rect2(Vector2.ZERO, size))

	var limites: Dictionary = map_data.get("bounds", {})
	draw_rect(
		_retangulo([
			limites.get("min_x", 0), limites.get("min_z", 0),
			limites.get("max_x", 0), limites.get("max_z", 0)
		]),
		COR_LIMITE
	)

	_desenhar_terreno()
	_desenhar_tilemap()
	_desenhar_zonas()
	_desenhar_criaturas()
	_desenhar_pontos()
	_desenhar_jogador()


func _desenhar_terreno() -> void:
	for patch in map_data.get("terrain", []):
		var cor := Color.html(String(patch.get("color", "#4E7A44")))
		draw_rect(_retangulo(patch.get("rect", [])), Color(cor.r, cor.g, cor.b, 0.75))


## Cada peça da vila vira um quadradinho, colorido pelo tipo do modelo.
func _desenhar_tilemap() -> void:
	var tilemap: Dictionary = map_data.get("tilemap", {})
	var linhas: Array = tilemap.get("rows", [])
	if linhas.is_empty():
		return

	var legenda: Dictionary = tilemap.get("legend", {})
	var passo := float(tilemap.get("step", 5.0))
	var origem: Array = tilemap.get("origin", [0, 0])
	var lado := passo * _escala

	for linha_indice in linhas.size():
		var linha := String(linhas[linha_indice])
		for coluna in linha.length():
			var simbolo := linha[coluna]
			if not legenda.has(simbolo):
				continue
			var modelo := String(legenda[simbolo].get("model", ""))
			var cor := Color("#3E6B44")
			for prefixo in CORES_DE_PECA.keys():
				if modelo.begins_with(prefixo):
					cor = CORES_DE_PECA[prefixo]
					break
			var centro := _ponto(
				float(origem[0]) + float(coluna) * passo,
				float(origem[1]) + float(linha_indice) * passo
			)
			draw_rect(Rect2(centro - Vector2(lado, lado) * 0.5, Vector2(lado, lado)), cor)


func _desenhar_zonas() -> void:
	for zona in map_data.get("zones", []):
		var rect := _retangulo(zona.get("rect", []))
		draw_rect(rect, Color(COR_ZONA.r, COR_ZONA.g, COR_ZONA.b, 0.12))
		draw_rect(rect, Color(COR_ZONA.r, COR_ZONA.g, COR_ZONA.b, 0.5), false, 1.0)
		if not detalhado:
			continue
		var faixa: Array = zona.get("level_range", [1, 1])
		_texto(
			rect.position + Vector2(4, 13),
			"%s  Nv.%d-%d" % [zona.get("name", ""), int(faixa[0]), int(faixa[1])],
			10, Color(1, 1, 1, 0.55)
		)


func _desenhar_criaturas() -> void:
	if not is_inside_tree():
		return
	for no in get_tree().get_nodes_in_group("wild_creature"):
		if not is_instance_valid(no):
			continue
		var criatura := no as WildCreature
		if criatura == null or criatura.data == null:
			continue
		var cor := DataManager.get_element_color(criatura.data.element())
		var p := _ponto(criatura.global_position.x, criatura.global_position.z)
		draw_circle(p, 2.5 if detalhado else 2.0, Color(cor.r, cor.g, cor.b, 0.9))


func _desenhar_pontos() -> void:
	for ponto in map_data.get("heal_points", []):
		_marcador(ponto.get("pos", []), COR_CURA, String(ponto.get("name", "")))

	for portao in map_data.get("gates", []):
		var liberado := _portao_liberado(portao)
		_marcador(
			portao.get("pos", []),
			COR_PORTAO if liberado else Color(COR_PORTAO.r, COR_PORTAO.g, COR_PORTAO.b, 0.35),
			String(portao.get("name", "")) + ("" if liberado else "  (selado)")
		)

	for chave in ["mini_boss", "boss"]:
		var chefe: Dictionary = map_data.get(chave, {})
		if chefe.is_empty():
			continue
		var caido := _chefe_caido(chave)
		_marcador(
			chefe.get("pos", []),
			Color(COR_CHEFE.r, COR_CHEFE.g, COR_CHEFE.b, 0.35) if caido else COR_CHEFE,
			String(chefe.get("name", "")) + ("  (derrotado)" if caido else ""),
			5.0
		)

	for npc in map_data.get("npcs", []):
		_marcador(npc.get("pos", []), COR_NPC, String(npc.get("name", "")), 3.0)


static func _portao_liberado(portao: Dictionary) -> bool:
	var dados := GameManager.player
	if dados == null:
		return false
	var exigido := String(portao.get("requires", {}).get("boss_defeated", ""))
	return exigido == "" or dados.is_boss_defeated(exigido)


func _chefe_caido(chave: String) -> bool:
	var dados := GameManager.player
	if dados == null:
		return false
	var mapa := String(map_data.get("id", ""))
	return dados.is_mini_boss_defeated(mapa) if chave == "mini_boss" else dados.is_boss_defeated(mapa)


func _marcador(pos: Array, cor: Color, rotulo: String, raio: float = 4.0) -> void:
	if pos.size() != 2:
		return
	var p := _ponto(float(pos[0]), float(pos[1]))
	draw_circle(p, raio + 1.0, Color(0, 0, 0, 0.6))
	draw_circle(p, raio, cor)
	if detalhado and rotulo != "":
		_texto(p + Vector2(raio + 4, 4), rotulo, 11, Color(1, 1, 1, 0.8))


## Seta na direção para onde o jogador está virado.
func _desenhar_jogador() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var p := _ponto(_player.global_position.x, _player.global_position.z)
	var angulo := _player.rotation.y
	# O modelo olha para -Z; no mapa, -Z é para cima.
	var frente := Vector2(-sin(angulo), -cos(angulo))
	var lado := Vector2(-frente.y, frente.x)
	var tamanho := 7.0 if detalhado else 5.5

	draw_colored_polygon(PackedVector2Array([
		p + frente * tamanho,
		p - frente * tamanho * 0.6 + lado * tamanho * 0.6,
		p - frente * tamanho * 0.6 - lado * tamanho * 0.6,
	]), COR_JOGADOR)


func _texto(pos: Vector2, texto: String, tamanho: int, cor: Color) -> void:
	var fonte := Design.ui_font()
	if fonte == null:
		fonte = ThemeDB.fallback_font
	if fonte == null:
		return
	draw_string(fonte, pos + Vector2(1, 1), texto, HORIZONTAL_ALIGNMENT_LEFT, -1, tamanho, Color(0, 0, 0, 0.7))
	draw_string(fonte, pos, texto, HORIZONTAL_ALIGNMENT_LEFT, -1, tamanho, cor)
