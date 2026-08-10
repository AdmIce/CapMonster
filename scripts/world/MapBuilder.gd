class_name MapBuilder
extends RefCounted
## Turns a map entry from data/maps.json into actual 3D geometry.
##
## Everything here is placeholder art built from primitives, but the *layout* is
## real data: swapping a prop for an imported model later means changing one
## `_make_*` function, not re-authoring the map.
##
## Scatter is deterministic (seeded RNG) so a map looks identical every run and
## between machines. Points that land inside a declared clearing, on a path, or
## close to an interactable are rejected, which keeps walkways open.

const PROP_MIN_DISTANCE_TO_INTERACTABLE := 3.0
const SCATTER_MAX_ATTEMPTS_PER_ITEM := 12


## Um mapa pode ser um cenário inteiro vindo de um `.glb`, em vez de geometria
## montada peça por peça. Quando é o caso, chão, terreno, marcos e espalhados
## não têm o que fazer — sairiam por cima do modelo.
static func tem_modelo(map_data: Dictionary) -> bool:
	return not (map_data.get("modelo", {}) as Dictionary).is_empty()


## Coloca o cenário do `.glb` e dá colisão a ele.
##
##   "modelo": { "arquivo": "res://...glb", "escala": 1.0, "pos": [0,0,0], "yaw": 0 }
static func build_modelo(parent: Node3D, map_data: Dictionary) -> void:
	var config: Dictionary = map_data.get("modelo", {})
	if config.is_empty():
		return

	var caminho := String(config.get("arquivo", ""))
	if not ResourceLoader.exists(caminho):
		GameLog.error(GameLog.Channel.WORLD, "Cenário não encontrado: %s" % caminho)
		return

	var cena: PackedScene = load(caminho)
	var no: Node3D = cena.instantiate()
	no.name = "Cenario"
	no.scale = Vector3.ONE * float(config.get("escala", 1.0))
	var pos: Array = config.get("pos", [0.0, 0.0, 0.0])
	if pos.size() == 3:
		no.position = Vector3(pos[0], pos[1], pos[2])
	no.rotation_degrees.y = float(config.get("yaw", 0.0))
	parent.add_child(no)

	# Cenário de banco de modelos costuma vir com bagagem que não serve num jogo:
	# a esfera de HDRI que o autor usou para iluminar a cena envolve tudo e vira
	# um teto preto em volta do mapa. `esconder` tira pelo nome do nó.
	var esconder: Array = config.get("esconder", [])
	if not esconder.is_empty():
		for descendente in _descendentes(no):
			for pedaco in esconder:
				if descendente is VisualInstance3D and String(descendente.name).contains(String(pedaco)):
					(descendente as VisualInstance3D).visible = false

	# Mapa interno tem teto, e teto tapa a câmera. Em vez de caçar o nome do nó
	# do telhado — que muda a cada modelo — some com tudo que está acima da
	# altura declarada. É o que todo jogo com interior faz.
	var teto := float(config.get("esconder_acima", 0.0))
	if teto > 0.0:
		_tirar_o_telhado(no, teto)

	if OS.is_debug_build():
		for descendente in _descendentes(no):
			if descendente is MeshInstance3D and (descendente as MeshInstance3D).mesh != null:
				var m := descendente as MeshInstance3D
				var c := m.global_transform * m.mesh.get_aabb()
				GameLog.verbose(GameLog.Channel.WORLD, "  peca %-22s %6.1f x %5.1f x %6.1f  visivel=%s" % [
					m.name, c.size.x, c.size.y, c.size.z, m.visible])

	if bool(config.get("colisao", true)):
		_colidir_com_o_cenario(no)


## Esconde as malhas que ficam inteiramente acima de `altura`, em metros de
## mundo. Só as que estão **inteiramente** acima: uma parede que vai do chão ao
## teto tem de continuar aparecendo, senão o quarto perde os lados.
static func _tirar_o_telhado(raiz: Node3D, altura: float) -> void:
	var escondidas := 0
	var mais_alto := 0.0
	for descendente in _descendentes(raiz):
		if not (descendente is MeshInstance3D):
			continue
		var malha := descendente as MeshInstance3D
		if malha.mesh == null:
			continue
		# Do espaço da malha para o do mundo: o modelo vem com escala embutida,
		# e comparar a altura crua contra metros daria resultado sem sentido.
		var caixa := malha.global_transform * malha.mesh.get_aabb()
		mais_alto = maxf(mais_alto, caixa.position.y + caixa.size.y)
		if caixa.position.y > altura:
			malha.visible = false
			escondidas += 1
	# Dizer quanto cortou e qual e o ponto mais alto do cenario: sem isto,
	# "o teto continua ai" nao tem como ser respondido sem abrir o editor.
	GameLog.info(
		GameLog.Channel.WORLD,
		"Telhado: %d peca(s) escondida(s) acima de %.1f m; cenario vai ate %.1f m." % [escondidas, altura, mais_alto]
	)


## Gera colisão a partir das próprias malhas do cenário.
##
## Modelo comprado não vem com corpo de colisão nem com o sufixo `-col` que o
## importador do Godot entende. Sem isto o quarto seria papel de parede: o
## jogador atravessaria as paredes e sairia andando no vazio.
##
## A lista de malhas é montada **antes** de criar as colisões porque
## `create_trimesh_collision` pendura um `StaticBody3D` novo em cada malha —
## caminhar e criar ao mesmo tempo faria a varredura encontrar o que ela mesma
## acabou de criar.
static func _colidir_com_o_cenario(raiz: Node3D) -> void:
	var malhas: Array[MeshInstance3D] = []
	for no in _descendentes(raiz):
		if no is MeshInstance3D:
			malhas.append(no as MeshInstance3D)

	for malha in malhas:
		malha.create_trimesh_collision()

	# O corpo nasce na camada 1; o jogo separa mundo, jogador e criaturas em
	# camadas próprias, e sem isto o cenário não pararia ninguém.
	for no in _descendentes(raiz):
		if no is StaticBody3D:
			var corpo := no as StaticBody3D
			corpo.collision_layer = GameLayers.WORLD
			corpo.collision_mask = 0


static func _descendentes(no: Node) -> Array[Node]:
	var todos: Array[Node] = []
	for filho in no.get_children():
		todos.append(filho)
		todos.append_array(_descendentes(filho))
	return todos


static func build_ground(parent: Node3D, map_data: Dictionary) -> void:
	var bounds: Dictionary = map_data.get("bounds", {})
	var width: float = float(bounds.get("max_x", 10)) - float(bounds.get("min_x", -10))
	var depth: float = float(bounds.get("max_z", 10)) - float(bounds.get("min_z", -10))
	var center := Vector3(
		(float(bounds.get("min_x", 0)) + float(bounds.get("max_x", 0))) * 0.5,
		0.0,
		(float(bounds.get("min_z", 0)) + float(bounds.get("max_z", 0))) * 0.5
	)

	var plane := PlaneMesh.new()
	plane.size = Vector2(width, depth)
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	ground.mesh = plane
	ground.position = center
	ground.material_override = _material(_color(map_data.get("ambient", {}).get("ground_color", "#4E7A44")))
	parent.add_child(ground)


static func build_terrain(parent: Node3D, map_data: Dictionary) -> void:
	var container := Node3D.new()
	container.name = "Terrain"
	parent.add_child(container)

	var index := 0
	for patch in map_data.get("terrain", []):
		index += 1
		var rect: Array = patch.get("rect", [0, 0, 1, 1])
		var kind: String = patch.get("kind", "grass")
		var color := _color(patch.get("color", "#4E7A44"))

		var size := Vector2(absf(rect[2] - rect[0]), absf(rect[3] - rect[1]))
		if size.x <= 0.0 or size.y <= 0.0:
			continue
		var center := Vector3((rect[0] + rect[2]) * 0.5, 0.0, (rect[1] + rect[3]) * 0.5)

		var plane := PlaneMesh.new()
		plane.size = size
		var node := MeshInstance3D.new()
		node.name = "%s_%d" % [kind, index]
		node.mesh = plane
		# Small stagger avoids z-fighting between overlapping patches.
		node.position = center + Vector3(0, 0.01 + index * 0.004, 0)

		var material := _material(color)
		match kind:
			"water":
				node.position.y = -0.06
				material.metallic = 0.25
				material.roughness = 0.15
				material.albedo_color = Color(color.r, color.g, color.b, 0.88)
				material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				_add_box_collider(container, rect, 1.6, "WaterBlock_%d" % index)
			"lava":
				material.emission_enabled = true
				material.emission = color
				material.emission_energy_multiplier = 1.4
				_add_box_collider(container, rect, 1.6, "LavaBlock_%d" % index)
			"path", "sand":
				material.roughness = 0.95
		node.material_override = material
		container.add_child(node)


static func build_blockers(parent: Node3D, map_data: Dictionary) -> void:
	var container := Node3D.new()
	container.name = "Blockers"
	parent.add_child(container)
	var index := 0
	for blocker in map_data.get("blockers", []):
		index += 1
		_add_box_collider(container, blocker.get("rect", [0, 0, 1, 1]), 3.0, "Blocker_%d" % index)


static func build_landmarks(parent: Node3D, map_data: Dictionary) -> void:
	var container := Node3D.new()
	container.name = "Landmarks"
	parent.add_child(container)

	for landmark in map_data.get("landmarks", []):
		var pos: Array = landmark.get("pos", [0, 0])
		var origin := Vector3(pos[0], 0.0, pos[1])
		var yaw: float = float(landmark.get("yaw", 0))
		var scale: float = float(landmark.get("scale", 1.0))
		var color := _color(landmark.get("color", "#7A6A55"))

		var node: Node3D = null
		match landmark.get("kind", "pillar"):
			"hut":
				node = _make_hut(color, _color(landmark.get("roof_color", "#6E4A3C")))
			"signpost":
				node = _make_signpost(color)
			"ruin_wall":
				node = _make_ruin_wall(color)
			"arch":
				node = _make_arch(color)
			"banner":
				node = _make_banner(color)
			"campfire":
				node = _make_campfire(color)
			_:
				node = _make_pillar(color)

		node.position = origin
		node.rotation_degrees.y = yaw
		node.scale = Vector3.ONE * scale
		container.add_child(node)


static func build_scatter(parent: Node3D, map_data: Dictionary, avoid_points: Array) -> void:
	var container := Node3D.new()
	container.name = "Scatter"
	parent.add_child(container)

	var clearings: Array = map_data.get("clearings", [])
	var paths: Array = []
	for patch in map_data.get("terrain", []):
		if patch.get("kind", "") in ["path", "water", "lava"]:
			paths.append(patch.get("rect", [0, 0, 0, 0]))

	for group in map_data.get("scatter", []):
		var rng := RandomNumberGenerator.new()
		rng.seed = int(group.get("seed", 0))
		var rect: Array = group.get("rect", [0, 0, 1, 1])
		var kind: String = group.get("kind", "rock")
		var color := _color(group.get("color", "#5A6B48"))
		var trunk_color := _color(group.get("trunk_color", "#4B3B2A"))
		var collides: bool = bool(group.get("collides", true))
		var placed := 0
		var target: int = int(group.get("count", 0))

		for _attempt in target * SCATTER_MAX_ATTEMPTS_PER_ITEM:
			if placed >= target:
				break
			var point := Vector2(
				rng.randf_range(minf(rect[0], rect[2]), maxf(rect[0], rect[2])),
				rng.randf_range(minf(rect[1], rect[3]), maxf(rect[1], rect[3]))
			)
			if _point_in_any_rect(point, clearings, true) or _point_in_any_rect(point, paths, false):
				continue
			if _too_close(point, avoid_points, PROP_MIN_DISTANCE_TO_INTERACTABLE):
				continue

			var scale := rng.randf_range(float(group.get("min_scale", 0.9)), float(group.get("max_scale", 1.3)))
			var node := _make_prop(kind, color, trunk_color, rng)
			node.position = Vector3(point.x, 0.0, point.y)
			node.rotation_degrees.y = rng.randf_range(0.0, 360.0)
			node.scale = Vector3.ONE * scale
			container.add_child(node)
			if collides:
				_add_cylinder_collider(container, point, _collider_radius(kind) * scale, 2.5)
			placed += 1

		if placed < target:
			GameLog.verbose(
				GameLog.Channel.WORLD,
				"Espalhamento '%s' colocou %d/%d (o resto caiu em área reservada)." % [kind, placed, target]
			)


## Monta um mapa feito de peças modulares a partir de um desenho em texto.
##
## O bloco `tilemap` traz uma legenda (caractere -> modelo) e as linhas do mapa.
## Editar a vila é editar o desenho, sem tocar em código nem abrir o editor:
##
##   "rows": [ "TT....TT",
##             "T.AA+BB.",
##             "....|..." ]
##
## A linha 0 é o norte (-Z). Cada peça do kit ocupa 1x1 na origem, então `scale`
## multiplica e `step` deve valer o mesmo, senão abre fresta entre as peças.
static func build_tilemap(parent: Node3D, map_data: Dictionary) -> void:
	var tilemap: Dictionary = map_data.get("tilemap", {})
	var rows: Array = tilemap.get("rows", [])
	if rows.is_empty():
		return

	var container := Node3D.new()
	container.name = "Tilemap"
	parent.add_child(container)

	var legenda: Dictionary = tilemap.get("legend", {})
	var passo := float(tilemap.get("step", 5.0))
	var escala := float(tilemap.get("scale", passo))

	# As peças do kit têm a placa de chão ACIMA da origem: na grama o topo fica em
	# y=0.06 no modelo, que com escala 5 vira 0.30 no mundo. Todo o resto do jogo
	# (jogador, companheiro, criaturas) anda em y=0 fixo, então sem descer o
	# tabuleiro o personagem afunda até o tornozelo. `surface` é a espessura da
	# placa em unidades do modelo — muda com o kit, por isso mora no JSON.
	var superficie := float(tilemap.get("surface", 0.06))
	container.position.y = -superficie * escala
	var origem: Array = tilemap.get("origin", [0, 0])
	var pasta := String(tilemap.get("model_dir", "res://assets/models/city/"))

	var cache: Dictionary = {}
	var colocadas := 0
	var faltando: Dictionary = {}
	var material := _material_do_kit(tilemap)

	for linha_indice in rows.size():
		var linha := String(rows[linha_indice])
		for coluna in linha.length():
			var simbolo := linha[coluna]
			if simbolo == " " or not legenda.has(simbolo):
				if simbolo != " " and not legenda.has(simbolo):
					faltando[simbolo] = true
				continue

			var definicao: Dictionary = legenda[simbolo]
			var nome := String(definicao.get("model", ""))
			if nome == "":
				continue

			var cena: PackedScene = cache.get(nome, null)
			if cena == null:
				var caminho := pasta + nome + ".glb"
				if not ResourceLoader.exists(caminho):
					faltando[nome] = true
					continue
				cena = load(caminho)
				cache[nome] = cena

			var peca := cena.instantiate()
			if not (peca is Node3D):
				peca.queue_free()
				continue

			var no := peca as Node3D
			no.position = Vector3(
				float(origem[0]) + float(coluna) * passo,
				0.0,
				float(origem[1]) + float(linha_indice) * passo
			)
			no.rotation_degrees.y = float(definicao.get("yaw", 0))
			no.scale = Vector3.ONE * escala
			if material != null:
				_aplicar_material(no, material)
			container.add_child(no)
			colocadas += 1

			if bool(definicao.get("collides", false)):
				var altura := float(definicao.get("height", 1.0)) * escala
				_add_tile_collider(container, no.position, passo * 0.92, altura)

	if not faltando.is_empty():
		GameLog.warn(
			GameLog.Channel.WORLD,
			"Tilemap: símbolos/modelos sem correspondência: %s" % ", ".join(faltando.keys())
		)
	GameLog.info(GameLog.Channel.WORLD, "Tilemap: %d peça(s) montada(s)." % colocadas)


## O kit inteiro pinta todos os modelos com uma única textura de paleta: as UVs
## de cada peça apontam para um quadradinho de cor dela. Aplicar esse material na
## mão em vez de confiar no que veio embutido no .glb resolve dois problemas de
## uma vez - importação de textura embutida que sai branca, e material duplicado
## por peça (aqui é um só, compartilhado pelas 143).
static func _material_do_kit(tilemap: Dictionary) -> StandardMaterial3D:
	var caminho := String(tilemap.get("colormap", "res://assets/models/city/colormap.png"))
	if caminho == "" or not ResourceLoader.exists(caminho):
		return null
	var textura: Texture2D = load(caminho)
	if textura == null:
		return null

	var material := StandardMaterial3D.new()
	material.albedo_texture = textura
	material.roughness = 0.92
	material.metallic = 0.0
	# A paleta é um atlas de cores chapadas: filtrar mistura quadradinhos
	# vizinhos e suja a cor. Nearest mantém cada peça na cor certa.
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	return material


static func _aplicar_material(no: Node, material: StandardMaterial3D) -> void:
	if no is MeshInstance3D:
		(no as MeshInstance3D).material_override = material
	for filho in no.get_children():
		_aplicar_material(filho, material)


static func _add_tile_collider(parent: Node3D, centro: Vector3, lado: float, altura: float) -> void:
	var corpo := StaticBody3D.new()
	corpo.collision_layer = GameLayers.WORLD
	corpo.collision_mask = 0
	corpo.position = centro + Vector3(0, altura * 0.5, 0)
	var forma := CollisionShape3D.new()
	var caixa := BoxShape3D.new()
	caixa.size = Vector3(lado, altura, lado)
	forma.shape = caixa
	corpo.add_child(forma)
	parent.add_child(corpo)


## Quanto baixar a exposição e o ambiente no modo compatibilidade.
##
## O renderizador de compatibilidade não comprime as luzes acima de 1 como o
## Forward+ faz: tudo que é claro satura em branco, e a cena inteira sai lavada.
## Medindo o mesmo enquadramento nos dois, a média de brilho era 211 contra 166 —
## o caminho de terra virava papel. Estes dois fatores põem os dois modos na
## mesma faixa.
##
## Não é "escurecer por escurecer": é desfazer a saturação que a falta de
## tonemap causa. Em Forward+ nada disso é aplicado.
const EXPOSICAO_COMPATIBILIDADE := 0.70
const AMBIENTE_COMPATIBILIDADE := 0.85


## Verdadeiro no modo compatibilidade. O Forward+ desenha através de um
## RenderingDevice; a compatibilidade não tem nenhum.
static func em_compatibilidade() -> bool:
	return RenderingServer.get_rendering_device() == null


static func _ajustar_ao_renderizador(environment: Environment) -> void:
	if not em_compatibilidade():
		return
	environment.tonemap_exposure = EXPOSICAO_COMPATIBILIDADE
	environment.ambient_light_energy *= AMBIENTE_COMPATIBILIDADE


static func build_environment(parent: Node3D, map_data: Dictionary) -> void:
	var ambient: Dictionary = map_data.get("ambient", {})

	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = _color(ambient.get("sky_top", "#6FA6D6"))
	sky_material.sky_horizon_color = _color(ambient.get("sky_horizon", "#CFE0DC"))
	sky_material.ground_bottom_color = _color(ambient.get("ground_color", "#4E7A44")).darkened(0.4)
	sky_material.ground_horizon_color = _color(ambient.get("sky_horizon", "#CFE0DC"))
	sky_material.sun_angle_max = 24.0

	var sky := Sky.new()
	sky.sky_material = sky_material

	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky

	# Mapa fechado (`"fundo"` no ambient): fora das paredes vira escuridão, e não
	# campo verde com céu por cima. Num interior, enxergar o mundo pelas frestas
	# denuncia que o quarto é uma casquinha solta no meio do nada.
	#
	# Só o **fundo** muda: o céu continua existindo como fonte de luz ambiente,
	# senão o quarto perderia a iluminação junto com a paisagem.
	var fundo := String(ambient.get("fundo", ""))
	GameLog.verbose(GameLog.Channel.WORLD, "Ambiente: fundo='%s' (chaves: %s)" % [fundo, ", ".join(PackedStringArray(ambient.keys()))])
	if fundo != "":
		environment.background_mode = Environment.BG_COLOR
		environment.background_color = _color(fundo)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = float(ambient.get("ambient_energy", 0.55))
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_white = 1.2
	_ajustar_ao_renderizador(environment)

	if bool(ambient.get("fog_enabled", false)):
		environment.fog_enabled = true
		environment.fog_light_color = _color(ambient.get("fog_color", "#A9C6BC"))
		environment.fog_density = float(ambient.get("fog_density", 0.003))
		environment.fog_sky_affect = 0.2

	var world_environment := WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	world_environment.environment = environment
	parent.add_child(world_environment)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = _color(ambient.get("sun_color", "#FFF3DC"))
	sun.light_energy = float(ambient.get("sun_energy", 1.1))
	sun.rotation_degrees = Vector3(
		float(ambient.get("sun_pitch", -50)), float(ambient.get("sun_yaw", -35)), 0.0
	)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 70.0
	sun.shadow_bias = 0.04
	parent.add_child(sun)


# --- props --------------------------------------------------------------------

static func _make_prop(kind: String, color: Color, trunk_color: Color, rng: RandomNumberGenerator) -> Node3D:
	match kind:
		"tree":
			return _make_tree(color, trunk_color, rng)
		"ashtree":
			return _make_ashtree(color, trunk_color)
		"bush":
			return _make_bush(color, rng)
		"reed":
			return _make_reed(color, rng)
		"stump":
			return _make_stump(trunk_color)
		"crystal":
			return _make_crystal(color, rng)
		"vent":
			return _make_vent(color)
		_:
			return _make_rock(color, rng)


static func _collider_radius(kind: String) -> float:
	match kind:
		"tree", "ashtree":
			return 0.55
		"rock":
			return 0.7
		"crystal":
			return 0.5
		"stump":
			return 0.45
		_:
			return 0.4


static func _make_tree(color: Color, trunk_color: Color, rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	root.add_child(_mesh(_cylinder(0.22, 2.2, 0.16), trunk_color, Vector3(0, 1.1, 0)))
	var canopy_height := rng.randf_range(2.2, 3.0)
	root.add_child(_mesh(_cone(1.5, canopy_height), color, Vector3(0, 2.0 + canopy_height * 0.4, 0)))
	root.add_child(_mesh(_cone(1.15, canopy_height * 0.75), color.lightened(0.08), Vector3(0, 3.0 + canopy_height * 0.5, 0)))
	return root


static func _make_ashtree(color: Color, trunk_color: Color) -> Node3D:
	var root := Node3D.new()
	root.add_child(_mesh(_cylinder(0.18, 2.6, 0.1), trunk_color, Vector3(0, 1.3, 0)))
	root.add_child(_mesh(_cylinder(0.07, 1.2, 0.04), color, Vector3(0.4, 2.4, 0.1), Vector3(0, 0, -42)))
	root.add_child(_mesh(_cylinder(0.07, 1.0, 0.04), color, Vector3(-0.35, 2.6, -0.15), Vector3(0, 0, 38)))
	return root


static func _make_bush(color: Color, rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	for i in 3:
		root.add_child(_mesh(
			SphereMesh.new(), color.lightened(float(i) * 0.05),
			Vector3(rng.randf_range(-0.28, 0.28), 0.28 + float(i) * 0.07, rng.randf_range(-0.28, 0.28)),
			Vector3.ONE * rng.randf_range(0.45, 0.72)
		))
	return root


static func _make_reed(color: Color, rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	for i in 5:
		var height := rng.randf_range(0.7, 1.3)
		root.add_child(_mesh(
			_cylinder(0.035, height, 0.01), color,
			Vector3(rng.randf_range(-0.24, 0.24), height * 0.5, rng.randf_range(-0.24, 0.24)),
			Vector3(rng.randf_range(-9, 9), 0, rng.randf_range(-9, 9))
		))
	return root


static func _make_stump(color: Color) -> Node3D:
	var root := Node3D.new()
	root.add_child(_mesh(_cylinder(0.42, 0.6, 0.38), color, Vector3(0, 0.3, 0)))
	root.add_child(_mesh(_cylinder(0.36, 0.06, 0.36), color.lightened(0.18), Vector3(0, 0.62, 0)))
	return root


static func _make_rock(color: Color, rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	root.add_child(_mesh(
		SphereMesh.new(), color,
		Vector3(0, 0.34, 0),
		Vector3(rng.randf_range(0.9, 1.4), rng.randf_range(0.6, 1.0), rng.randf_range(0.9, 1.4)),
		Vector3(rng.randf_range(-12, 12), 0, rng.randf_range(-12, 12))
	))
	root.add_child(_mesh(
		SphereMesh.new(), color.darkened(0.12),
		Vector3(rng.randf_range(-0.4, 0.4), 0.16, rng.randf_range(-0.4, 0.4)),
		Vector3.ONE * rng.randf_range(0.3, 0.55)
	))
	return root


static func _make_crystal(color: Color, rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	for i in 3:
		var height := rng.randf_range(0.9, 1.9)
		var shard := _mesh(
			_cone(0.24, height), color,
			Vector3(rng.randf_range(-0.3, 0.3), height * 0.45, rng.randf_range(-0.3, 0.3)),
			Vector3.ONE,
			Vector3(rng.randf_range(-14, 14), rng.randf_range(0, 360), rng.randf_range(-14, 14))
		)
		var material: StandardMaterial3D = shard.material_override
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 0.55
		root.add_child(shard)
	return root


static func _make_vent(color: Color) -> Node3D:
	var root := Node3D.new()
	root.add_child(_mesh(TorusMesh.new(), color, Vector3(0, 0.06, 0), Vector3(0.5, 0.2, 0.5)))
	var glow := _mesh(_cylinder(0.22, 0.05, 0.22), Color("#D2603A"), Vector3(0, 0.05, 0))
	var material: StandardMaterial3D = glow.material_override
	material.emission_enabled = true
	material.emission = Color("#D2603A")
	material.emission_energy_multiplier = 1.6
	root.add_child(glow)
	return root


# --- landmarks ----------------------------------------------------------------

static func _make_hut(wall: Color, roof: Color) -> Node3D:
	var root := Node3D.new()
	var body := BoxMesh.new()
	body.size = Vector3(3.4, 2.2, 3.0)
	root.add_child(_mesh(body, wall, Vector3(0, 1.1, 0)))
	var roof_mesh := _cone(2.9, 1.5)
	root.add_child(_mesh(roof_mesh, roof, Vector3(0, 2.9, 0), Vector3.ONE, Vector3(0, 45, 0)))
	var door := BoxMesh.new()
	door.size = Vector3(0.9, 1.4, 0.1)
	root.add_child(_mesh(door, wall.darkened(0.45), Vector3(0, 0.7, -1.53)))
	_attach_collider(root, 1.9, 2.4)
	return root


static func _make_signpost(color: Color) -> Node3D:
	var root := Node3D.new()
	root.add_child(_mesh(_cylinder(0.08, 1.8, 0.08), color, Vector3(0, 0.9, 0)))
	var board := BoxMesh.new()
	board.size = Vector3(1.2, 0.42, 0.08)
	root.add_child(_mesh(board, color.lightened(0.22), Vector3(0.35, 1.55, 0)))
	_attach_collider(root, 0.3, 1.8)
	return root


static func _make_ruin_wall(color: Color) -> Node3D:
	var root := Node3D.new()
	var heights := [2.4, 1.6, 2.0, 1.1]
	for i in heights.size():
		var block := BoxMesh.new()
		block.size = Vector3(1.0, heights[i], 0.7)
		root.add_child(_mesh(block, color.darkened(float(i) * 0.04), Vector3(-1.5 + float(i) * 1.02, heights[i] * 0.5, 0)))
	_attach_collider(root, 2.2, 2.4)
	return root


static func _make_arch(color: Color) -> Node3D:
	var root := Node3D.new()
	for side in [-1.0, 1.0]:
		root.add_child(_mesh(_cylinder(0.45, 4.0, 0.55), color, Vector3(side * 2.4, 2.0, 0)))
		_attach_collider(root, 0.6, 4.0, Vector3(side * 2.4, 0, 0))
	var top := BoxMesh.new()
	top.size = Vector3(6.0, 0.8, 1.1)
	root.add_child(_mesh(top, color.lightened(0.08), Vector3(0, 4.2, 0)))
	return root


static func _make_banner(color: Color) -> Node3D:
	var root := Node3D.new()
	root.add_child(_mesh(_cylinder(0.06, 3.2, 0.06), Color("#5A4632"), Vector3(0, 1.6, 0)))
	var cloth := BoxMesh.new()
	cloth.size = Vector3(0.7, 1.5, 0.05)
	root.add_child(_mesh(cloth, color, Vector3(0.3, 2.3, 0)))
	return root


static func _make_pillar(color: Color) -> Node3D:
	var root := Node3D.new()
	root.add_child(_mesh(_cylinder(0.6, 3.2, 0.7), color, Vector3(0, 1.6, 0)))
	root.add_child(_mesh(_cylinder(0.8, 0.3, 0.8), color.lightened(0.1), Vector3(0, 3.3, 0)))
	_attach_collider(root, 0.8, 3.4)
	return root


const FOGUEIRA := "res://assets/models/props/fogueira.glb"
## O modelo nasce com 3,76 m de altura (medido: malha de 94 unidades a 0,04 de
## escala). Fogueira de acampamento tem uns 60 cm, e o personagem tem 1,75 —
## sem encolher, ela ficaria do dobro da altura de quem senta ao lado dela.
const ESCALA_FOGUEIRA := 0.45


## A fogueira dos acampamentos e dos marcos. Uma função só, usada pelos dois:
## eram duas montagens à mão iguais, e trocar o modelo em um e esquecer o outro
## deixaria dois desenhos de fogueira no mesmo jogo.
static func criar_fogueira(cor_da_luz: Color = Color("#F0A64E")) -> Node3D:
	var root := Node3D.new()
	root.name = "Fogueira"

	if ResourceLoader.exists(FOGUEIRA):
		var modelo: Node3D = (load(FOGUEIRA) as PackedScene).instantiate()
		modelo.scale = Vector3.ONE * ESCALA_FOGUEIRA
		root.add_child(modelo)
	else:
		# Sem o modelo, um monte de pedras: melhor uma fogueira feia do que um
		# acampamento invisível com que dá para conversar.
		GameLog.warn(GameLog.Channel.WORLD, "Modelo da fogueira não encontrado; usando o desenho antigo.")
		for i in 6:
			var angle := TAU * float(i) / 6.0
			root.add_child(_mesh(
				SphereMesh.new(), Color("#6E6558"),
				Vector3(cos(angle) * 0.7, 0.12, sin(angle) * 0.7),
				Vector3.ONE * 0.32
			))

	# A luz continua sendo nossa: a chama do modelo é malha, não ilumina nada, e
	# é a luz que faz o acampamento parecer quente de longe.
	var light := OmniLight3D.new()
	light.light_color = cor_da_luz
	light.light_energy = 1.6
	light.omni_range = 8.0
	light.position = Vector3(0, 1.0, 0)
	root.add_child(light)
	return root


static func _make_campfire(_color: Color) -> Node3D:
	return criar_fogueira()


# --- geometry helpers ---------------------------------------------------------

static func _add_box_collider(parent: Node3D, rect: Array, height: float, node_name: String) -> void:
	var size := Vector3(absf(rect[2] - rect[0]), height, absf(rect[3] - rect[1]))
	if size.x <= 0.0 or size.z <= 0.0:
		return
	var body := StaticBody3D.new()
	body.name = node_name
	body.collision_layer = GameLayers.WORLD
	body.collision_mask = 0
	body.position = Vector3((rect[0] + rect[2]) * 0.5, height * 0.5 - 0.2, (rect[1] + rect[3]) * 0.5)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	parent.add_child(body)


static func _add_cylinder_collider(parent: Node3D, point: Vector2, radius: float, height: float) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = GameLayers.WORLD
	body.collision_mask = 0
	body.position = Vector3(point.x, height * 0.5, point.y)
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = maxf(0.2, radius)
	cylinder.height = height
	shape.shape = cylinder
	body.add_child(shape)
	parent.add_child(body)


static func _attach_collider(root: Node3D, radius: float, height: float, offset: Vector3 = Vector3.ZERO) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = GameLayers.WORLD
	body.collision_mask = 0
	body.position = offset + Vector3(0, height * 0.5, 0)
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = radius
	cylinder.height = height
	shape.shape = cylinder
	body.add_child(shape)
	root.add_child(body)


static func _point_in_any_rect(point: Vector2, rects: Array, is_wrapped: bool) -> bool:
	for entry in rects:
		var rect: Array = entry.get("rect", []) if is_wrapped else entry
		if rect.size() != 4:
			continue
		if (
			point.x >= minf(rect[0], rect[2]) and point.x <= maxf(rect[0], rect[2])
			and point.y >= minf(rect[1], rect[3]) and point.y <= maxf(rect[1], rect[3])
		):
			return true
	return false


static func _too_close(point: Vector2, avoid_points: Array, distance: float) -> bool:
	var squared := distance * distance
	for other in avoid_points:
		if point.distance_squared_to(other) < squared:
			return true
	return false


static func _mesh(
	mesh: Mesh, color: Color, position: Vector3, scale: Vector3 = Vector3.ONE,
	rotation_deg: Vector3 = Vector3.ZERO
) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = position
	node.scale = scale
	node.rotation_degrees = rotation_deg
	node.material_override = _material(color)
	return node


static func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	material.metallic = 0.0
	return material


static func _cylinder(top: float, height: float, bottom: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = 10
	return mesh


static func _cone(radius: float, height: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 10
	return mesh


static func _color(hex: String) -> Color:
	return Color.html(hex) if hex.begins_with("#") else Color.WHITE
