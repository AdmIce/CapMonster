class_name NpcSprite
extends Node3D
## Um NPC desenhado à mão, em vez de montado com caixas pelo HumanoidBuilder.
##
## O corpo é um `Sprite3D` de frente para a câmera. Isso é de propósito, e não
## uma economia: arte 2D em mundo 3D só funciona quando o desenho nunca é visto
## de lado — girar a figura mostraria que ela é uma folha de papel.
##
## O desenho e o recorte dos quadros saem de dois arquivos irmãos gerados pelo
## `tools/converter_spr.py`:
##
##   assets/npc/<nome>.png    a folha com todos os quadros lado a lado
##   assets/npc/<nome>.json   {"altura": N, "quadros": [{x, y, w, h}, ...]}
##
## Quais quadros formam a animação é escolha de quem declara o NPC, não deste
## script. Folhas convertidas costumam trazer quadros que não são o personagem
## — a de exemplo termina com a assinatura da artista — e adivinhar isso por
## tamanho seria um palpite que quebra na próxima folha.

## Altura do NPC no mundo, em metros. Igual à do HumanoidBuilder, senão um NPC
## de sprite fica visivelmente maior ou menor que o vizinho de caixas.
const ALTURA_PADRAO := 1.75

## Segundos que cada quadro fica na tela. Devagar de propósito: são poses de
## respirar, não de andar, e trocar rápido vira tremida.
const SEGUNDOS_POR_QUADRO := 0.55

var _sprite: Sprite3D = null
var _quadros: Array[Rect2i] = []
var _atual: int = 0
var _tempo: float = 0.0
var _escala: float = 1.0


## `quadros` são índices dentro do JSON. Vazio usa todos, na ordem do arquivo.
static func criar(caminho_png: String, quadros: Array = [], altura: float = ALTURA_PADRAO) -> NpcSprite:
	var no := NpcSprite.new()
	no.name = "CorpoSprite"
	no._montar(caminho_png, quadros, altura)
	return no


## Existe um NPC de sprite para este caminho? Quem chama decide o que fazer sem
## o desenho — aqui o caminho é sempre dado por JSON, e JSON erra.
static func disponivel(caminho_png: String) -> bool:
	return caminho_png != "" and ResourceLoader.exists(caminho_png) \
			and FileAccess.file_exists(caminho_png.get_basename() + ".json")


func _montar(caminho_png: String, quadros: Array, altura: float) -> void:
	if not disponivel(caminho_png):
		push_warning("NpcSprite: falta o png ou o json de %s" % caminho_png)
		return

	var textura: Texture2D = load(caminho_png)
	var dados := _ler_json(caminho_png.get_basename() + ".json")
	var todos: Array = dados.get("quadros", [])
	if todos.is_empty():
		push_warning("NpcSprite: %s nao tem quadros" % caminho_png)
		return

	var escolhidos: Array = quadros if not quadros.is_empty() else range(todos.size())
	for indice in escolhidos:
		var i := int(indice)
		if i < 0 or i >= todos.size():
			push_warning("NpcSprite: quadro %d nao existe em %s" % [i, caminho_png])
			continue
		var q: Dictionary = todos[i]
		_quadros.append(Rect2i(int(q.get("x", 0)), int(q.get("y", 0)), int(q.get("w", 0)), int(q.get("h", 0))))
	if _quadros.is_empty():
		return

	# A escala vem do quadro mais alto, e não de cada um: calculada por quadro,
	# um desenho com o braço abaixado encolheria o NPC inteiro no meio da
	# animação.
	var mais_alto := 0
	for r in _quadros:
		mais_alto = maxi(mais_alto, r.size.y)
	_escala = altura / float(maxi(1, mais_alto))

	_sprite = Sprite3D.new()
	_sprite.texture = textura
	_sprite.region_enabled = true
	_sprite.pixel_size = _escala
	# Sempre de frente para a câmera, mas em pé: sem travar o Y, olhar de cima
	# deitava o NPC no chão.
	_sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	# Pixel art precisa de vizinho mais próximo; com filtro linear o contorno
	# do desenho vira borrão em qualquer aproximação da câmera.
	_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	# Recorta o transparente em vez de misturar: sem isto o retângulo invisível
	# do sprite apaga o que está atrás dele conforme a câmera gira.
	_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	# Dupla face porque a folha não tem volume: sem sombra o NPC flutua, já que
	# é ela que diz onde uma coisa toca o chão. O mapa de sombra é desenhado do
	# ponto de vista da luz, então a folha encara a lâmpada em vez da câmera —
	# a silhueta que cai no chão continua sendo a do personagem.
	_sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	add_child(_sprite)

	_aplicar_quadro()


func _process(delta: float) -> void:
	if _quadros.size() < 2:
		return
	_tempo += delta
	if _tempo < SEGUNDOS_POR_QUADRO:
		return
	_tempo = 0.0
	_atual = (_atual + 1) % _quadros.size()
	_aplicar_quadro()


func _aplicar_quadro() -> void:
	if _sprite == null or _quadros.is_empty():
		return
	var r := _quadros[_atual]
	_sprite.region_rect = Rect2(r)
	# O sprite é centrado, então metade da altura o coloca com os pés no chão.
	# Recalculado a cada quadro: quadros de alturas diferentes ancorados pelo
	# centro fariam o NPC subir e descer sozinho.
	_sprite.position.y = r.size.y * _escala * 0.5


func _ler_json(caminho: String) -> Dictionary:
	var arquivo := FileAccess.open(caminho, FileAccess.READ)
	if arquivo == null:
		return {}
	var resultado: Variant = JSON.parse_string(arquivo.get_as_text())
	arquivo.close()
	return resultado if resultado is Dictionary else {}
