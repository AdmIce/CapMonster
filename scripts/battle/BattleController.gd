class_name BattleController
extends Node3D
## Conduz o combate. A batalha acontece no próprio mapa, no lugar onde o
## encontro rolou: a câmera aproxima, os times se posicionam e as criaturas
## trocam golpes sozinhas.
##
## Divisão de responsabilidade: o BattleActor decide *quando* quer agir e como
## isso parece; este controlador decide *em quem* e aplica a regra. Toda conta
## passa por DamageCalculator.
##
## A equipe do jogador luta em automático, menos as duas habilidades da criatura
## líder, que são botões - é a decisão que impede o combate de virar só uma barra
## encolhendo. Com o modo AUTO ligado, elas também disparam sozinhas.

signal batalha_iniciada(aliados: Array, inimigos: Array)
signal batalha_encerrada(vitoria: bool, resumo: Dictionary)
signal estado_mudou()
signal mensagem(texto: String)

const DISTANCIA_ENTRE_TIMES := 2.8
const ESPACO_LATERAL := 1.7
## Multiplica o zoom do jogador durante a luta. Precisa ser MAIOR que 1: o
## enquadramento ortográfico é `tamanho / zoom`, então zoom maior aproxima.
## Estava 0.78 aqui, o que afastava a câmera em vez de aproximar.
const ZOOM_BATALHA := 1.3
const ATRASO_ENCERRAR := 1.4

var em_batalha: bool = false
## Ligado pelo AutoPilot: faz as habilidades do líder saírem sozinhas.
var auto_habilidades: bool = false

var _player: PlayerController = null
var _camera: CameraRig = null
var _aliados: Array[BattleActor] = []
var _inimigos: Array[BattleActor] = []
var _origem_selvagem: WildCreature = null
## Preenchido só em batalha de chefe: id do encontro em maps.json e o mapa dele.
var _encontro_id: String = ""
var _encontro_mapa: String = ""
var _encontro_tier: String = ""
var _encontro_recompensas: Dictionary = {}
var _foco: Node3D = null
var _zoom_anterior: float = 1.0
var _modo_anterior: CameraRig.Modo = CameraRig.Modo.ISOMETRICA
var _encerrando: bool = false
var _rng := RandomNumberGenerator.new()


func setup(player: PlayerController, camera: CameraRig) -> void:
	_player = player
	_camera = camera
	_rng.randomize()
	# Usado pela ferramenta de captura de tela para fotografar durante a luta.
	add_to_group("battle")


func aliados() -> Array[BattleActor]:
	return _aliados


func inimigos() -> Array[BattleActor]:
	return _inimigos


func lider() -> BattleActor:
	for ator in _aliados:
		if ator.esta_vivo():
			return ator
	return null


# --- início -------------------------------------------------------------------

## `equipe_inimiga` são CreatureData já prontos. `selvagem` é o nó do mapa que
## originou o encontro (pode ser nulo em batalhas de chefe, mais tarde).
func iniciar(equipe_inimiga: Array, posicao: Vector3, selvagem: WildCreature = null) -> bool:
	if em_batalha or equipe_inimiga.is_empty():
		return false
	var dados := GameManager.player
	if dados == null:
		return false

	var equipe := dados.team()
	var vivos: Array[CreatureData] = []
	for criatura in equipe:
		if criatura.is_alive():
			vivos.append(criatura)
	if vivos.is_empty():
		Notify.bad("Sua equipe está sem condições de lutar.")
		return false

	em_batalha = true
	_encerrando = false
	_origem_selvagem = selvagem

	_player.input_enabled = false
	_player.auto_input = Vector2.ZERO

	_montar_times(vivos, equipe_inimiga, posicao)
	_focar_camera(posicao)

	for ator in _aliados + _inimigos:
		ator.iniciar()

	var nomes: Array[String] = []
	for criatura in equipe_inimiga:
		nomes.append("%s Nv.%d" % [criatura.display_name(), criatura.level])
	mensagem.emit("Encontro: %s" % ", ".join(nomes))
	GameLog.info(GameLog.Channel.BATTLE, "Batalha iniciada contra %s." % ", ".join(nomes))

	batalha_iniciada.emit(_aliados, _inimigos)
	return true


## Batalha de chefe: monta o time inimigo a partir do bloco `mini_boss`/`boss`
## do mapa (chefe + escoltas) e guarda o que precisa para creditar a vitória.
func iniciar_chefe(encontro: Dictionary, map_id: String, tier: String) -> bool:
	if em_batalha:
		return false
	var especie := StringName(encontro.get("species", ""))
	if not DataManager.has_species(especie):
		GameLog.error(GameLog.Channel.BATTLE, "Chefe com espécie desconhecida: %s" % especie)
		return false

	var equipe_inimiga: Array = [CreatureFactory.create(especie, int(encontro.get("level", 10)))]
	for escolta in encontro.get("escorts", []):
		var criatura := CreatureFactory.create(
			StringName(escolta.get("species", "")), int(escolta.get("level", 5))
		)
		if criatura != null:
			equipe_inimiga.append(criatura)

	_encontro_id = String(encontro.get("id", ""))
	_encontro_mapa = map_id
	_encontro_tier = tier
	_encontro_recompensas = (encontro.get("rewards", {}) as Dictionary).duplicate(true)

	var pos: Array = encontro.get("pos", [0, 0])
	var iniciou := iniciar(equipe_inimiga, Vector3(pos[0], 0.0, pos[1]), null)
	if iniciou:
		var intro := String(encontro.get("intro", ""))
		if intro != "":
			mensagem.emit(intro)
		if _camera != null:
			_camera.tremer(0.4, 0.7)
		AudioManager.tocar(&"critico")
	return iniciou


func _montar_times(equipe: Array[CreatureData], inimigos_data: Array, centro: Vector3) -> void:
	var eixo := Vector3(centro.x - _player.global_position.x, 0.0, centro.z - _player.global_position.z)
	if eixo.length() < 0.5:
		eixo = Vector3.FORWARD
	eixo = eixo.normalized()
	var lateral := Vector3(-eixo.z, 0.0, eixo.x)

	for i in equipe.size():
		var deslocamento := float(i) - float(equipe.size() - 1) * 0.5
		var posicao := centro - eixo * DISTANCIA_ENTRE_TIMES + lateral * deslocamento * ESPACO_LATERAL
		var ator := BattleActor.create(equipe[i], true, posicao)
		# Só o líder tem habilidade manual; o resto age sozinho.
		ator.skills_automaticas = i != 0 or auto_habilidades
		_conectar(ator)
		add_child(ator)
		_aliados.append(ator)
		ator.look_at_from_position(posicao, posicao - eixo, Vector3.UP)

	for i in inimigos_data.size():
		var deslocamento := float(i) - float(inimigos_data.size() - 1) * 0.5
		var posicao := centro + eixo * DISTANCIA_ENTRE_TIMES + lateral * deslocamento * ESPACO_LATERAL
		var ator := BattleActor.create(inimigos_data[i], false, posicao)
		_conectar(ator)
		add_child(ator)
		_inimigos.append(ator)
		ator.look_at_from_position(posicao, posicao + eixo, Vector3.UP)


func _conectar(ator: BattleActor) -> void:
	ator.quer_atacar.connect(_ao_querer_atacar)
	ator.quer_usar_habilidade.connect(_ao_querer_habilidade)
	ator.morreu.connect(_ao_morrer)
	ator.enfureceu.connect(_ao_enfurecer)


func _ao_enfurecer(ator: BattleActor) -> void:
	mensagem.emit("%s se enfureceu!" % ator.data.display_name())
	FloatingText3D.mostrar(
		self,
		ator.global_position + Vector3(0, ator.altura_do_topo() + 0.5, 0),
		FloatingText3D.aviso("FÚRIA!")
	)
	ImpactBurst.disparar(self, ator.global_position + Vector3(0, 0.8, 0), Color("#FF6B4A"), 2.0)
	if _camera != null:
		_camera.tremer(0.35, 0.5)
	AudioManager.tocar(&"critico")


## A batalha sempre usa o enquadramento de combate, mesmo que a exploração
## esteja em terceira pessoa: de trás do personagem não dá para ler dois times
## lado a lado. O modo escolhido pelo jogador volta ao fim da luta.
func _focar_camera(centro: Vector3) -> void:
	if _camera == null:
		return
	_foco = Node3D.new()
	_foco.position = centro
	add_child(_foco)

	_modo_anterior = _camera.modo
	_camera.definir_modo(CameraRig.Modo.ISOMETRICA)
	_zoom_anterior = float(SaveManager.get_setting("camera_zoom", 1.0))
	_camera.set_zoom(_zoom_anterior * ZOOM_BATALHA)
	_camera.follow(_foco, false)


# --- ações --------------------------------------------------------------------

func _ao_querer_atacar(ator: BattleActor) -> void:
	if _encerrando or not ator.esta_vivo():
		return
	var alvo := _escolher_alvo(ator)
	if alvo == null:
		return
	ator.tocar_ataque(alvo.global_position)
	_resolver_dano(ator, alvo, DamageCalculator.BASIC_ATTACK_POWER, ator.data.element())


func _ao_querer_habilidade(ator: BattleActor, skill_id: String) -> void:
	if _encerrando or not ator.esta_vivo():
		return
	_executar_habilidade(ator, skill_id)


## Chamado pelos botões do HUD. `indice` é 0 ou 1 (as duas skills do líder).
func usar_habilidade_manual(indice: int) -> bool:
	var ator := lider()
	if ator == null or _encerrando:
		return false
	var skills := ator.data.skill_ids()
	if indice < 0 or indice >= skills.size():
		return false
	if not ator.habilidade_pronta(skills[indice]):
		return false
	_executar_habilidade(ator, skills[indice])
	return true


func _executar_habilidade(ator: BattleActor, skill_id: String) -> void:
	var skill := DataManager.get_skill(skill_id)
	if skill.is_empty():
		return
	ator.consumir_recarga(skill_id)

	var elemento := String(skill.get("element", ator.data.element()))
	ator.tocar_conjuracao(DataManager.get_element_color(elemento))
	mensagem.emit("%s usou %s" % [ator.data.display_name(), skill.get("name", skill_id)])

	var tipo := String(skill.get("kind", "damage"))
	var alvo_tipo := String(skill.get("target", "enemy_single"))
	var potencia := float(skill.get("power", 0.0))

	match alvo_tipo:
		"enemy_single":
			var alvo := _escolher_alvo(ator)
			if alvo != null:
				_aplicar_em_inimigo(ator, alvo, skill, potencia, elemento, tipo)
		"enemy_all":
			for alvo in _time_oposto(ator):
				if alvo.esta_vivo():
					_aplicar_em_inimigo(ator, alvo, skill, potencia, elemento, tipo)
		"ally_lowest":
			var alvo := _aliado_mais_ferido(ator)
			if alvo != null:
				_aplicar_cura(alvo, potencia)
		"ally_all":
			for alvo in _time_proprio(ator):
				if not alvo.esta_vivo():
					continue
				if tipo == "heal":
					_aplicar_cura(alvo, potencia)
				else:
					_aplicar_modificador(alvo, skill)
		"self":
			if tipo == "heal":
				_aplicar_cura(ator, potencia)
			else:
				_aplicar_modificador(ator, skill)

	_verificar_fim()


func _aplicar_em_inimigo(
	ator: BattleActor, alvo: BattleActor, skill: Dictionary,
	potencia: float, elemento: String, tipo: String
) -> void:
	if potencia > 0.0:
		_resolver_dano(ator, alvo, potencia, elemento)
	if tipo == "debuff":
		_aplicar_modificador(alvo, skill)


func _aplicar_modificador(alvo: BattleActor, skill: Dictionary) -> void:
	var stat := String(skill.get("stat", ""))
	if stat == "":
		return
	var quantidade := float(skill.get("stat_change", 0.0))
	alvo.aplicar_modificador(stat, quantidade, float(skill.get("duration", 5.0)))
	var sinal := "+" if quantidade > 0.0 else ""
	FloatingText3D.mostrar(
		self,
		alvo.global_position + Vector3(0, alvo.altura_do_topo(), 0),
		FloatingText3D.aviso("%s%d%% %s" % [sinal, int(round(quantidade * 100.0)), _nome_do_stat(stat)])
	)


func _aplicar_cura(alvo: BattleActor, potencia: float) -> void:
	var quantidade := DamageCalculator.compute_heal(alvo.data.max_hp(), potencia)
	var curado := alvo.data.heal(quantidade)
	if curado <= 0:
		return
	FloatingText3D.mostrar(
		self,
		alvo.global_position + Vector3(0, alvo.altura_do_topo(), 0),
		FloatingText3D.cura(curado)
	)
	estado_mudou.emit()


func _resolver_dano(atacante: BattleActor, alvo: BattleActor, potencia: float, elemento: String) -> void:
	var resultado := DamageCalculator.compute(
		atacante.ataque_efetivo(),
		alvo.defesa_efetiva(),
		potencia,
		elemento,
		alvo.data.element(),
		_rng
	)
	alvo.data.apply_damage(resultado.amount)
	alvo.tocar_dano()

	var topo := alvo.global_position + Vector3(0, alvo.altura_do_topo(), 0)
	FloatingText3D.mostrar(self, topo, FloatingText3D.dano(resultado))
	ImpactBurst.disparar(
		self,
		alvo.global_position + Vector3(0, alvo.altura_do_topo() * 0.6, 0),
		DataManager.get_element_color(elemento),
		1.6 if resultado.critical else (1.2 if resultado.is_effective() else 0.8)
	)

	# Só golpe que importa sacode a tela: crítico e super-efetivo. Tremer em todo
	# ataque básico deixaria a câmera vibrando o combate inteiro.
	if _camera != null:
		if resultado.critical:
			_camera.tremer(0.3, 0.32)
		elif resultado.is_effective():
			_camera.tremer(0.16, 0.22)
	AudioManager.tocar(&"critico" if resultado.critical else &"golpe")

	estado_mudou.emit()
	_verificar_fim()


# --- itens, captura e fuga ----------------------------------------------------

func usar_item(item_id: String) -> bool:
	var dados := GameManager.player
	if dados == null or dados.item_count(item_id) <= 0:
		return false
	var item := DataManager.get_item(item_id)
	var efeito := String(item.get("effect", ""))
	var valor := float(item.get("effect_value", 0.0))

	match efeito:
		"heal_percent":
			var alvo := _aliado_mais_ferido(null)
			if alvo == null:
				return false
			dados.consume_item(item_id)
			_aplicar_cura(alvo, valor)
		"heal_team_percent":
			dados.consume_item(item_id)
			for ator in _aliados:
				if ator.esta_vivo():
					_aplicar_cura(ator, valor)
		_:
			return false

	mensagem.emit("Usou %s" % item.get("name", item_id))
	return true


## Só dá para tentar com um inimigo em campo: núcleo não segura dois.
func pode_capturar() -> bool:
	var vivos := _vivos(_inimigos)
	if vivos.size() != 1:
		return false
	var especie := vivos[0].data.species()
	return especie != null and especie.is_capturable


func tentar_captura(item_id: String = "binding_core") -> bool:
	var dados := GameManager.player
	if dados == null or _encerrando:
		return false
	if not pode_capturar():
		Notify.warn("Só dá para usar o núcleo com um alvo em campo.")
		return false
	if dados.item_count(item_id) <= 0:
		Notify.warn("Você não tem %s." % DataManager.get_item_name(item_id))
		return false

	Ficha.pedir("usar_item", {"item": item_id})
	var alvo := _vivos(_inimigos)[0]
	var potencia := float(DataManager.get_item(item_id).get("capture_power", 1.0))
	var chance := CreatureFactory.capture_chance(alvo.data, potencia)
	var sucesso := _rng.randf() < chance

	GameLog.info(
		GameLog.Channel.CAPTURE,
		"Tentativa em %s (chance %.0f%%): %s" % [
			alvo.data.display_name(), chance * 100.0, "sucesso" if sucesso else "falhou"
		]
	)
	mensagem.emit("Núcleo lançado em %s..." % alvo.data.display_name())
	_encerrando = true  # trava outras ações enquanto a animação corre
	await _animar_captura(alvo, sucesso)
	_encerrando = false

	var topo := alvo.global_position + Vector3(0, alvo.altura_do_topo(), 0)
	if not sucesso:
		FloatingText3D.mostrar(self, topo, FloatingText3D.aviso("escapou!"))
		mensagem.emit("%s escapou do núcleo." % alvo.data.display_name())
		AudioManager.tocar(&"captura_falha")
		return false

	FloatingText3D.mostrar(self, topo, FloatingText3D.aviso("capturado!"))
	AudioManager.tocar(&"captura_sucesso")
	# Quem grava a criatura na coleção é a Ficha: jogando sozinho isso acontece
	# aqui mesmo, e numa partida é o servidor que passa a ter o bicho.
	Ficha.pedir("capturar", {"criatura": alvo.data.to_dict()})
	QuestManager.registrar_captura(alvo.data)
	Notify.good("%s foi capturado!" % alvo.data.display_name())
	mensagem.emit("%s entrou para a sua coleção." % alvo.data.display_name())
	GameManager.save_now("captura")
	_finalizar(true, true)
	return true


## Núcleo voa até o alvo, engole a criatura, chacoalha três vezes e decide.
func _animar_captura(alvo: BattleActor, sucesso: bool) -> void:
	var cor := DataManager.get_item_color("binding_core")
	var nucleo := MeshInstance3D.new()
	var esfera := SphereMesh.new()
	esfera.radius = 0.28
	esfera.height = 0.56
	nucleo.mesh = esfera
	var material := StandardMaterial3D.new()
	material.albedo_color = cor
	material.emission_enabled = true
	material.emission = cor
	material.emission_energy_multiplier = 1.6
	nucleo.material_override = material

	var origem := _player.global_position + Vector3(0, 1.2, 0)
	var destino := alvo.global_position + Vector3(0, alvo.altura_do_topo() * 0.5, 0)
	nucleo.position = origem
	add_child(nucleo)

	var arremesso := create_tween()
	arremesso.tween_property(nucleo, "position", destino, 0.32).set_trans(Tween.TRANS_QUAD)
	await arremesso.finished

	ImpactBurst.disparar(self, destino, cor, 1.2)
	var engolir := create_tween()
	engolir.tween_property(alvo, "scale", Vector3.ONE * 0.05, 0.22).set_trans(Tween.TRANS_BACK)
	await engolir.finished
	alvo.visible = false

	for i in 3:
		var chacoalho := create_tween()
		chacoalho.tween_property(nucleo, "rotation_degrees:z", 26.0, 0.13)
		chacoalho.tween_property(nucleo, "rotation_degrees:z", -26.0, 0.13)
		chacoalho.tween_property(nucleo, "rotation_degrees:z", 0.0, 0.09)
		await chacoalho.finished

	if sucesso:
		var selar := create_tween()
		selar.tween_property(nucleo, "scale", Vector3.ONE * 0.2, 0.25)
		await selar.finished
		nucleo.queue_free()
		return

	# Falhou: a criatura volta ao tamanho normal e o núcleo se despedaça.
	alvo.visible = true
	alvo.scale = Vector3.ONE * 0.05
	var voltar := create_tween()
	voltar.tween_property(alvo, "scale", Vector3.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	ImpactBurst.disparar(self, destino, cor, 1.4)
	nucleo.queue_free()
	await voltar.finished


func fugir() -> void:
	if _encerrando:
		return
	mensagem.emit("Você recuou.")
	_finalizar(false, false, true)


# --- fim ----------------------------------------------------------------------

func _ao_morrer(ator: BattleActor) -> void:
	estado_mudou.emit()
	mensagem.emit("%s foi derrubado." % ator.data.display_name())
	_verificar_fim()


func _verificar_fim() -> void:
	if _encerrando or not em_batalha:
		return
	if _vivos(_inimigos).is_empty():
		_finalizar(true, false)
	elif _vivos(_aliados).is_empty():
		_finalizar(false, false)


func _finalizar(vitoria: bool, capturado: bool, fuga: bool = false) -> void:
	if _encerrando:
		return
	_encerrando = true
	for ator in _aliados + _inimigos:
		ator.encerrar()

	var resumo := { "vitoria": vitoria, "capturado": capturado, "fuga": fuga, "xp": 0, "ouro": 0 }
	if vitoria and not fuga:
		resumo = _distribuir_recompensas(resumo, capturado)

	await get_tree().create_timer(ATRASO_ENCERRAR).timeout
	# O jogo pode ter sido fechado durante a pausa; sem isto a corrotina volta
	# mexendo em nós já liberados.
	if not is_inside_tree():
		return
	_limpar(vitoria or capturado, fuga)
	batalha_encerrada.emit(vitoria, resumo)

	if not vitoria and not fuga:
		_tratar_derrota()


func _distribuir_recompensas(resumo: Dictionary, capturado: bool) -> Dictionary:
	var dados := GameManager.player
	var xp_total := 0
	var ouro := 0
	for ator in _inimigos:
		# Quem foi capturado não conta como derrotado.
		if capturado and ator.data.is_alive():
			continue
		xp_total += CreatureFactory.xp_reward(ator.data)
		ouro += 8 + ator.data.level * 4

	# Cada inimigo abatido conta para as missões de "derrote N criaturas".
	for ator in _inimigos:
		if capturado and ator.data.is_alive():
			continue
		QuestManager.registrar_derrota(ator.data)

	var sobreviventes := _vivos(_aliados)
	var xp_cada := DamageCalculator.split_xp(xp_total, sobreviventes.size())
	var subiu := false
	for ator in sobreviventes:
		var niveis := ator.data.grant_xp(xp_cada)
		if niveis > 0:
			subiu = true
			FloatingText3D.mostrar(
				self,
				ator.global_position + Vector3(0, ator.altura_do_topo() + 0.4, 0),
				FloatingText3D.aviso("Nv.%d!" % ator.data.level)
			)
	if subiu:
		AudioManager.tocar(&"nivel")

	Ficha.pedir("recompensa", {
		"ouro": ouro,
		"xp": maxi(1, int(round(float(xp_total) * 0.35))),
	})

	resumo["xp"] = xp_cada
	resumo["ouro"] = ouro
	resumo["chefe"] = _encontro_id
	resumo["evolucoes"] = _evolucoes_disponiveis(dados)

	if _encontro_id != "":
		resumo = _creditar_chefe(dados, resumo)

	GameLog.info(GameLog.Channel.BATTLE, "Vitória: %d XP por criatura, %d de ouro." % [xp_cada, ouro])
	AudioManager.tocar(&"vitoria")
	GameManager.save_now("fim de batalha")
	return resumo


## Nomes de quem passou do nível de evolução, para a tela de vitória avisar.
static func _evolucoes_disponiveis(dados: PlayerData) -> Array:
	var prontas: Array = []
	for criatura in dados.collection:
		if criatura.can_evolve():
			prontas.append(criatura.display_name())
	return prontas


func _creditar_chefe(dados: PlayerData, resumo: Dictionary) -> Dictionary:
	if _encontro_tier == "mini":
		dados.mark_mini_boss_defeated(_encontro_mapa)
	else:
		dados.mark_boss_defeated(_encontro_mapa)

	var ouro_extra := int(_encontro_recompensas.get("gold", 0))
	var xp_extra := int(_encontro_recompensas.get("player_xp", 0))
	if ouro_extra > 0:
		resumo["ouro"] = int(resumo.get("ouro", 0)) + ouro_extra

	var premios: Dictionary = {}
	var itens: Array[String] = []
	for item_id in _encontro_recompensas.get("items", {}).keys():
		var quantidade := int(_encontro_recompensas["items"][item_id])
		premios[String(item_id)] = quantidade
		itens.append("%dx %s" % [quantidade, DataManager.get_item_name(String(item_id))])
	resumo["itens"] = itens

	# Um pedido só com tudo do chefe: ouro, XP e itens numa ida de rede.
	Ficha.pedir("recompensa", {"ouro": ouro_extra, "xp": xp_extra, "itens": premios})

	QuestManager.registrar_encontro_nomeado(_encontro_id)
	GameLog.info(GameLog.Channel.BATTLE, "Chefe derrotado: %s (%s)." % [_encontro_id, _encontro_mapa])
	return resumo


func _tratar_derrota() -> void:
	var dados := GameManager.player
	if dados == null:
		return
	dados.heal_all()
	Notify.bad("Sua equipe foi derrotada. Você acordou no acampamento.")
	GameLog.info(GameLog.Channel.BATTLE, "Derrota: voltando ao ponto de cura.")
	GameManager.save_now("derrota")


func _limpar(remover_selvagem: bool, fuga: bool) -> void:
	em_batalha = false

	if _camera != null:
		_camera.set_zoom(_zoom_anterior)
		_camera.follow(_player, false)
		_camera.definir_modo(_modo_anterior)
	if _foco != null and is_instance_valid(_foco):
		_foco.queue_free()
		_foco = null

	for ator in _aliados + _inimigos:
		if is_instance_valid(ator):
			ator.queue_free()
	_aliados.clear()
	_inimigos.clear()
	_encontro_id = ""
	_encontro_mapa = ""
	_encontro_tier = ""
	_encontro_recompensas.clear()

	if _origem_selvagem != null and is_instance_valid(_origem_selvagem):
		if remover_selvagem:
			_origem_selvagem.despawn()
		else:
			# Fuga ou derrota: a criatura continua no mapa, mas dá um tempo antes
			# de puxar outro encontro.
			_origem_selvagem.definir_recarga_de_encontro(8.0 if fuga else 5.0)
	_origem_selvagem = null

	if _player != null and is_instance_valid(_player):
		_player.input_enabled = true


# --- seleção ------------------------------------------------------------------

func _time_proprio(ator: BattleActor) -> Array[BattleActor]:
	return _aliados if ator.is_ally else _inimigos


func _time_oposto(ator: BattleActor) -> Array[BattleActor]:
	return _inimigos if ator.is_ally else _aliados


static func _vivos(time: Array[BattleActor]) -> Array[BattleActor]:
	var resultado: Array[BattleActor] = []
	for ator in time:
		if is_instance_valid(ator) and ator.esta_vivo():
			resultado.append(ator)
	return resultado


## Foca fogo em quem está mais fraco, mas às vezes troca de alvo - assim o
## combate não vira sempre a mesma fila.
func _escolher_alvo(ator: BattleActor) -> BattleActor:
	var candidatos := _vivos(_time_oposto(ator))
	if candidatos.is_empty():
		return null
	if candidatos.size() > 1 and _rng.randf() < 0.25:
		return candidatos[_rng.randi_range(0, candidatos.size() - 1)]
	var melhor: BattleActor = candidatos[0]
	for candidato in candidatos:
		if candidato.data.current_hp < melhor.data.current_hp:
			melhor = candidato
	return melhor


func _aliado_mais_ferido(ator: BattleActor) -> BattleActor:
	var time := _vivos(_aliados) if ator == null else _vivos(_time_proprio(ator))
	if time.is_empty():
		return null
	var melhor: BattleActor = time[0]
	for candidato in time:
		if candidato.data.hp_ratio() < melhor.data.hp_ratio():
			melhor = candidato
	return melhor


static func _nome_do_stat(stat: String) -> String:
	match stat:
		"attack":
			return "ATQ"
		"defense":
			return "DEF"
		"speed":
			return "VEL"
		_:
			return stat.to_upper()
