extends Node3D
## Abertura do jogo: o posto de pesquisa do Professor Elir.
##
## Sequência: o professor explica o mundo -> as três iniciais se materializam nos
## pedestais -> o jogador escolhe -> o professor se despede -> mundo.
##
## Todo o texto e as cores do cenário vêm de data/intro.json. O cenário em si é
## montado com primitivas, como o resto do protótipo.

enum Etapa { ABERTURA, ESCOLHA, ENCERRAMENTO }

const PEDESTAL_X := [-2.7, 0.0, 2.7]
const PEDESTAL_Z := -3.2
const PEDESTAL_ALTURA := 0.95

var _intro: Dictionary = {}
var _etapa: Etapa = Etapa.ABERTURA

var _pedestais: Array[Node3D] = []
var _modelos: Array[Node3D] = []
var _luzes: Array[OmniLight3D] = []

var _dialogo: DialoguePanel = null
var _seletor: StarterPicker = null
var _painel_seletor: Control = null
var _botao_pular: Button = null
var _dica: Label = null
var _fase: float = 0.0


func _ready() -> void:
	if GameManager.player == null:
		GameLog.error(GameLog.Channel.SYSTEM, "Abertura carregada sem personagem criado.")
		SceneFlow.goto_main_menu()
		return

	_intro = DataManager.get_intro()
	_montar_ambiente()
	_montar_cenario()
	_montar_personagens()
	_montar_interface()
	_iniciar_abertura()

	if OS.is_debug_build() and OS.get_cmdline_user_args().has("--smoke-intro"):
		_executar_teste_automatico()


func _process(delta: float) -> void:
	_fase += delta
	for i in _modelos.size():
		var modelo := _modelos[i]
		if not is_instance_valid(modelo):
			continue
		modelo.rotation.y += delta * 0.4
		modelo.position.y = PEDESTAL_ALTURA + sin(_fase * 1.6 + float(i)) * 0.05


# --- cenário ------------------------------------------------------------------

func _cenario_config() -> Dictionary:
	return _intro.get("cenario", {})


func _montar_ambiente() -> void:
	var cfg := _cenario_config()

	var ceu_material := ProceduralSkyMaterial.new()
	ceu_material.sky_top_color = _cor(cfg.get("sky_top", "#2A3A46"))
	ceu_material.sky_horizon_color = _cor(cfg.get("sky_horizon", "#6E6A58"))
	ceu_material.ground_bottom_color = _cor(cfg.get("cor_chao", "#3E4A3C")).darkened(0.5)
	ceu_material.ground_horizon_color = _cor(cfg.get("sky_horizon", "#6E6A58"))

	var ceu := Sky.new()
	ceu.sky_material = ceu_material

	var ambiente := Environment.new()
	ambiente.background_mode = Environment.BG_SKY
	ambiente.sky = ceu
	ambiente.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	ambiente.ambient_light_energy = float(cfg.get("ambient_energy", 0.42))
	ambiente.tonemap_mode = Environment.TONE_MAPPER_FILMIC

	var mundo := WorldEnvironment.new()
	mundo.environment = ambiente
	add_child(mundo)

	var sol := DirectionalLight3D.new()
	sol.light_color = Color("#FFE2BC")
	sol.light_energy = 0.85
	sol.rotation_degrees = Vector3(-46, 28, 0)
	sol.shadow_enabled = true
	add_child(sol)

	# Lampião do posto: é ele que dá o clima de interior à noite.
	var lampiao := OmniLight3D.new()
	lampiao.light_color = Color("#FFC98A")
	lampiao.light_energy = 2.4
	lampiao.omni_range = 14.0
	lampiao.position = Vector3(0, 3.8, 0.4)
	lampiao.shadow_enabled = true
	add_child(lampiao)

	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = 42.0
	camera.position = Vector3(0, 3.2, 7.0)
	camera.rotation_degrees = Vector3(-15, 0, 0)
	camera.current = true
	add_child(camera)


func _montar_cenario() -> void:
	var cfg := _cenario_config()
	var chao_cor := _cor(cfg.get("cor_chao", "#3E4A3C"))
	var parede_cor := _cor(cfg.get("cor_parede", "#2A3230"))
	var madeira := _cor(cfg.get("cor_madeira", "#5A4632"))

	var chao := PlaneMesh.new()
	chao.size = Vector2(20, 18)
	add_child(_malha(chao, chao_cor, Vector3(0, 0, -1)))

	var parede := BoxMesh.new()
	parede.size = Vector3(20, 6, 0.4)
	add_child(_malha(parede, parede_cor, Vector3(0, 3, -8)))

	var lateral := BoxMesh.new()
	lateral.size = Vector3(0.4, 6, 18)
	add_child(_malha(lateral, parede_cor.darkened(0.1), Vector3(-9.8, 3, -1)))
	add_child(_malha(lateral, parede_cor.darkened(0.1), Vector3(9.8, 3, -1)))

	# Bancada e caixaria: o suficiente para o lugar parecer usado.
	var bancada := BoxMesh.new()
	bancada.size = Vector3(4.4, 0.18, 1.3)
	add_child(_malha(bancada, madeira, Vector3(-5.4, 1.0, -4.2)))
	for x in [-7.2, -3.6]:
		var perna := BoxMesh.new()
		perna.size = Vector3(0.16, 1.0, 1.1)
		add_child(_malha(perna, madeira.darkened(0.25), Vector3(x, 0.5, -4.2)))

	for i in 4:
		var caixa := BoxMesh.new()
		caixa.size = Vector3(0.9, 0.7, 0.9)
		add_child(_malha(
			caixa, madeira.darkened(0.1 + float(i) * 0.04),
			Vector3(6.0 + float(i % 2) * 1.1, 0.35 + float(i / 2) * 0.7, -5.0 - float(i % 2) * 0.5)
		))

	# Frascos na bancada, com brilho fraco.
	for i in 5:
		var frasco := _malha(
			_cilindro(0.11, 0.34), Color("#8FD0C8"),
			Vector3(-7.0 + float(i) * 0.8, 1.26, -4.2)
		)
		var material: StandardMaterial3D = frasco.material_override
		material.emission_enabled = true
		material.emission = Color("#6FBFB4")
		material.emission_energy_multiplier = 0.5
		add_child(frasco)

	_montar_pedestais(madeira)


func _montar_pedestais(madeira: Color) -> void:
	for i in PEDESTAL_X.size():
		var pedestal := Node3D.new()
		pedestal.position = Vector3(PEDESTAL_X[i], 0, PEDESTAL_Z)
		add_child(pedestal)

		pedestal.add_child(_malha(_cilindro(0.62, 0.14), madeira.lightened(0.1), Vector3(0, 0.07, 0)))
		pedestal.add_child(_malha(_cilindro(0.42, 0.78), madeira, Vector3(0, 0.5, 0)))
		pedestal.add_child(_malha(_cilindro(0.58, 0.12), madeira.lightened(0.16), Vector3(0, 0.92, 0)))

		var luz := OmniLight3D.new()
		luz.light_color = Color("#CFE3EC")
		luz.light_energy = 0.0
		luz.omni_range = 5.0
		luz.position = Vector3(0, 1.5, 0)
		pedestal.add_child(luz)

		_pedestais.append(pedestal)
		_luzes.append(luz)


func _montar_personagens() -> void:
	var professor: Dictionary = _intro.get("professor", {})
	var figura := HumanoidBuilder.build(professor.get("colors", {}), "researcher")
	var no_professor := Node3D.new()
	no_professor.position = Vector3(-3.9, 0, -0.6)
	no_professor.rotation_degrees.y = 160
	no_professor.add_child(figura)
	add_child(no_professor)

	var avatar := PlayerAvatar.new()
	avatar.apply_appearance(GameManager.player.appearance)
	var no_jogador := Node3D.new()
	no_jogador.position = Vector3(3.4, 0, 0.8)
	no_jogador.rotation_degrees.y = -122
	no_jogador.add_child(avatar)
	add_child(no_jogador)


# --- interface ----------------------------------------------------------------

func _montar_interface() -> void:
	_dialogo = DialoguePanel.new()
	add_child(_dialogo)
	_dialogo.finished.connect(_ao_terminar_fala)

	var camada := CanvasLayer.new()
	camada.layer = 30
	add_child(camada)

	var raiz := Control.new()
	raiz.set_anchors_preset(Control.PRESET_FULL_RECT)
	raiz.mouse_filter = Control.MOUSE_FILTER_IGNORE
	camada.add_child(raiz)

	_botao_pular = Design.button("Pular abertura", "ghost")
	_botao_pular.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_botao_pular.offset_left = -190
	_botao_pular.offset_top = Design.S_LG
	_botao_pular.offset_right = -Design.S_LG
	_botao_pular.offset_bottom = Design.S_LG + 40
	_botao_pular.pressed.connect(avancar_para_escolha)
	raiz.add_child(_botao_pular)

	_dica = Design.caption(str(_intro.get("dica_final", "")))
	_dica.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_dica.offset_top = Design.S_LG + 6
	_dica.offset_bottom = Design.S_LG + 26
	_dica.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dica.visible = false
	raiz.add_child(_dica)

	_painel_seletor = Control.new()
	_painel_seletor.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_painel_seletor.offset_left = Design.S_XL
	_painel_seletor.offset_right = -Design.S_XL
	_painel_seletor.offset_top = -286
	_painel_seletor.offset_bottom = -Design.S_XL
	_painel_seletor.visible = false
	_painel_seletor.modulate.a = 0.0
	raiz.add_child(_painel_seletor)

	_seletor = StarterPicker.new()
	_seletor.set_anchors_preset(Control.PRESET_FULL_RECT)
	_seletor.selection_changed.connect(_ao_trocar_selecao)
	_seletor.chosen.connect(_ao_escolher)
	_painel_seletor.add_child(_seletor)


# --- roteiro ------------------------------------------------------------------

func _nome_professor() -> String:
	return str(_intro.get("professor", {}).get("name", "Professor"))


func _iniciar_abertura() -> void:
	var falas: Array = (_intro.get("falas_abertura", []) as Array).duplicate()
	falas.append(_intro.get("fala_escolha", "Escolha uma."))
	_etapa = Etapa.ABERTURA
	_dialogo.open(_nome_professor(), falas)


## Encerra a explicação e vai direto para a escolha. É o que o botão "Pular
## abertura" chama, e também o caminho usado pelo teste automático.
func avancar_para_escolha() -> void:
	if _etapa != Etapa.ABERTURA:
		return
	_dialogo.close()


## Confirma uma das iniciais pelo índice, sem passar pelo clique.
func escolher_por_indice(indice: int) -> void:
	if _etapa != Etapa.ESCOLHA or _seletor == null:
		return
	_seletor.select(indice)
	var especie := _seletor.selected_species()
	if especie != null:
		_ao_escolher(especie)


## Percorre a abertura inteira sozinho para o smoke test headless conseguir
## exercitar os pedestais, o seletor e a entrada no mundo.
func _executar_teste_automatico() -> void:
	await get_tree().create_timer(0.6).timeout
	avancar_para_escolha()
	await get_tree().create_timer(1.4).timeout
	escolher_por_indice(0)
	await get_tree().create_timer(0.8).timeout
	if _etapa == Etapa.ENCERRAMENTO:
		_dialogo.close()


func _ao_terminar_fala() -> void:
	match _etapa:
		Etapa.ABERTURA:
			_revelar_criaturas()
		Etapa.ENCERRAMENTO:
			_entrar_no_mundo()
		_:
			pass


func _revelar_criaturas() -> void:
	_etapa = Etapa.ESCOLHA
	_botao_pular.visible = false
	_dica.visible = true

	for i in _seletor.species_list.size():
		if i >= _pedestais.size():
			break
		var especie: CreatureSpecies = _seletor.species_list[i]
		var modelo := CreatureModelBuilder.build(especie)
		modelo.position = Vector3(0, PEDESTAL_ALTURA, 0)
		modelo.scale = Vector3.ZERO
		_pedestais[i].add_child(modelo)
		_modelos.append(modelo)

		var cor := DataManager.get_element_color(especie.element)
		_luzes[i].light_color = cor

		var surgir := create_tween()
		surgir.tween_interval(0.18 * float(i))
		surgir.tween_property(modelo, "scale", Vector3.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		var brilho := create_tween()
		brilho.tween_interval(0.18 * float(i))
		brilho.tween_property(_luzes[i], "light_energy", 1.1, 0.6)

	_painel_seletor.visible = true
	var entrada := create_tween()
	entrada.tween_interval(0.5)
	entrada.tween_property(_painel_seletor, "modulate:a", 1.0, 0.35)
	_seletor.select(0)


## Realça o pedestal da criatura em foco - o resto abaixa a luz.
func _ao_trocar_selecao(index: int, _especie: CreatureSpecies) -> void:
	for i in _luzes.size():
		var alvo := 2.0 if i == index else 0.7
		var tween := create_tween()
		tween.tween_property(_luzes[i], "light_energy", alvo, 0.25)
	for i in _modelos.size():
		if not is_instance_valid(_modelos[i]):
			continue
		var escala := 1.18 if i == index else 0.95
		var tween := create_tween()
		tween.tween_property(_modelos[i], "scale", Vector3.ONE * escala, 0.25)


func _ao_escolher(especie: CreatureSpecies) -> void:
	var criatura := GameManager.choose_starter(especie.id)
	if criatura == null:
		Notify.bad("Não foi possível entregar essa criatura.")
		return

	_etapa = Etapa.ENCERRAMENTO
	_dica.visible = false
	var saida := create_tween()
	saida.tween_property(_painel_seletor, "modulate:a", 0.0, 0.25)
	saida.tween_callback(func(): _painel_seletor.visible = false)

	var falas: Array = []
	var confirmacao := str(_intro.get("fala_confirmacao", "{criatura}."))
	falas.append(confirmacao.replace("{criatura}", especie.name))
	for fala in _intro.get("falas_encerramento", []):
		falas.append(fala)
	_dialogo.open(_nome_professor(), falas)


func _entrar_no_mundo() -> void:
	GameManager.begin_session()
	GameManager.save_now("novo jogo")
	SceneFlow.goto_world()


# --- utilidades ---------------------------------------------------------------

static func _cor(hex: String) -> Color:
	return Color.html(hex) if hex.begins_with("#") else Color.WHITE


static func _malha(mesh: Mesh, cor: Color, posicao: Vector3) -> MeshInstance3D:
	var no := MeshInstance3D.new()
	no.mesh = mesh
	no.position = posicao
	var material := StandardMaterial3D.new()
	material.albedo_color = cor
	material.roughness = 0.9
	no.material_override = material
	return no


static func _cilindro(raio: float, altura: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = raio
	mesh.bottom_radius = raio
	mesh.height = altura
	mesh.radial_segments = 14
	return mesh
