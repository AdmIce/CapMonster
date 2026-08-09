class_name PlayerAvatar
extends Node3D
## O personagem do jogador.
##
## Base: KayKit Adventurers (CC0, Kay Lousberg) - humanoide de verdade, com
## esqueleto de 41 ossos e 76 animações prontas. Usamos `Idle`, `Walking_A`,
## `Running_A` e `Interact`; o resto fica disponível para o combate depois.
##
## O que é nosso: as escolhas de aparência. As peças do modelo vêm nomeadas
## (`_Head`, `_Body`, `_ArmLeft`, `_LegLeft`, `_Cape`, `_Hat`…), então dá para
## tingir pele e roupa separado, esconder as armas que vêm no pacote (o jogo é de
## treinador, não de guerreiro) e trocar o chapéu por um dos três cabelos.
##
## A altura é medida do modelo montado em tempo de execução e ajustada para
## ALTURA_ALVO. Chutar escala foi o que fez o personagem anterior nascer gigante
## e flutuando.
##
## Sem o `.glb`, cai num boneco de primitivas: o jogo não quebra por falta de asset.

enum State { IDLE, WALK, RUN, INTERACT }

const PASTA := "res://assets/models/characters/"
const ALTURA_ALVO := 1.7

## Altura do rig, medida nas inverseBindMatrices dos quatro modelos (todos usam
## o mesmo esqueleto): o osso `root` fica exatamente nos pés, em y = 0, e o osso
## `head` em y = 1,241 — com o crânio, dá ~1,46 até o topo.
##
## Não use o AABB da malha para isso: numa malha com esqueleto ele é da pose de
## bind (vai até -1,12 aqui) e não tem relação com onde o personagem pisa. Foi
## exatamente esse erro que deixou os bonecos flutuando.
const ALTURA_DO_RIG := 1.46

## Quanto girar o modelo importado para o rosto apontar para -Z, que é a frente
## no resto do projeto. Os modelos do KayKit vêm olhando para +Z.
const GIRO_PARA_FRENTE := 180.0

## Dois kits de personagem convivem, e eles não se parecem em nada por dentro:
## o KayKit é um .glb com as animações embutidas; o Kenney é .fbx com o modelo
## num arquivo e cada animação no seu. Por isso os nomes de animação não são
## constantes globais: cada montagem grava os seus em `_anim_*`.
const KIT_KAYKIT := "kaykit"
const KIT_KENNEY := "kenney"

const ANIM_PARADO := "Idle"
const ANIM_ANDANDO := "Walking_A"
const ANIM_CORRENDO := "Running_A"
const ANIM_INTERAGIR := "Interact"

const PASTA_KENNEY := "res://3d/personagens/"

## Altura do personagem Kenney com escala 1, medida em cena.
##
## Nem a AABB da malha (0,0105) nem a pose de descanso dos ossos (0,009) servem
## aqui: o importador de FBX entrega as duas colapsadas, e o nó `Root` ainda traz
## uma escala de 100 por cima. Restou plantar o modelo ao lado do jogador com
## `--modelo=<caminho>:<escala>` e comparar — 0,30 deu cerca de um metro.
const ALTURA_NATURAL_KENNEY := 3.33

## O pacote nomeia as animações com o nó de origem na frente.
const ANIM_KENNEY := {
	"parado": {"arquivo": "idle", "nome": "Root|Idle"},
	"andando": {"arquivo": "run", "nome": "Root|Run"},
	"correndo": {"arquivo": "run", "nome": "Root|Run"},
	"interagir": {"arquivo": "jump", "nome": "Root|Jump"},
}

## Os quatro personagens do pacote, na ordem em que aparecem na criação.
const PERSONAGENS: Array[Dictionary] = [
	{ "kit": KIT_KAYKIT, "arquivo": "Knight", "nome": "Cavaleiro", "prefixo": "Knight" },
	{ "kit": KIT_KAYKIT, "arquivo": "Barbarian", "nome": "Bárbaro", "prefixo": "Barbarian" },
	{ "kit": KIT_KAYKIT, "arquivo": "Rogue", "nome": "Ladina", "prefixo": "Rogue" },
	{ "kit": KIT_KAYKIT, "arquivo": "Mage", "nome": "Maga", "prefixo": "Mage" },
	{ "kit": KIT_KENNEY, "pele": "skaterMaleA", "nome": "Andarilho" },
	{ "kit": KIT_KENNEY, "pele": "skaterFemaleA", "nome": "Andarilha" },
	{ "kit": KIT_KENNEY, "pele": "criminalMaleA", "nome": "Fugitivo" },
	{ "kit": KIT_KENNEY, "pele": "cyborgFemaleA", "nome": "Autômata" },
]
## Nome antigo, mantido para a tela de criação não precisar de dois caminhos.
const BODY_TYPES: Array[String] = [
	"Cavaleiro", "Bárbaro", "Ladina", "Maga",
	"Andarilho", "Andarilha", "Fugitivo", "Autômata",
]

const SKIN_TONES: Array[Color] = [Color("#F0D2B4"), Color("#C08E62"), Color("#8A5C3C")]
const HAIR_COLORS: Array[Color] = [Color("#2B2320"), Color("#8A5A2B"), Color("#C7B49A")]
const HAIR_STYLES: Array[String] = ["cropped", "tied", "long"]
const HAIR_LABELS: Array[String] = ["Curto", "Preso", "Comprido"]
const OUTFITS: Array[Dictionary] = [
	{ "name": "Casaco de Campo", "main": Color("#9FC4DC"), "trim": Color("#C9922F"), "legs": Color("#8FA6BC") },
	{ "name": "Traje de Batedor", "main": Color("#AFC79B"), "trim": Color("#D9C98A"), "legs": Color("#93A882") },
	{ "name": "Manto da Serra", "main": Color("#C3A8BE"), "trim": Color("#9AA3AD"), "legs": Color("#A08CA0") },
]

## Peças que o pacote traz na mão do personagem e que não fazem sentido aqui.
const ARMAS := [
	"Sword", "Axe", "Knife", "Crossbow", "Shield", "Throwable", "Spellbook",
	"Wand", "Staff", "Mug", "Badge", "Rectangle", "Round", "Spike",
]

var _appearance: Dictionary = {}
var _state: State = State.IDLE
var _speed_ratio: float = 0.0
var _interact_timer: float = 0.0

var _raiz: Node3D = null
var _animador: AnimationPlayer = null
var _usando_modelo: bool = false
var _animacao_atual: String = ""
var _anim_parado: String = ANIM_PARADO
var _anim_andando: String = ANIM_ANDANDO
var _anim_correndo: String = ANIM_CORRENDO
var _anim_interagir: String = ANIM_INTERAGIR
var _fase: float = 0.0


func _ready() -> void:
	if _raiz == null:
		_reconstruir()


## Reconstruir o corpo custa carregar o GLB inteiro, então só acontece quando a
## aparência **muda de verdade**.
##
## As duas armadilhas que isso fecha:
##   · o `_ready` montava o boneco padrão e quem criou mandava a aparência real
##     logo em seguida — dois carregamentos por spawn, e descartar o primeiro
##     esqueleto enchia o log de erro de desconexão;
##   · o boneco de outro jogador recebe a ficha dele junto com **cada pacote de
##     posição**, 15 vezes por segundo. Sem esta comparação, era um GLB
##     recarregado 15 vezes por segundo por jogador na tela.
func apply_appearance(appearance: Dictionary) -> void:
	if _raiz != null and _appearance == appearance:
		return
	_appearance = appearance.duplicate()
	if not is_node_ready():
		return   # ainda vai entrar na árvore: o _ready monta com o que ficou aqui
	_reconstruir()


func _reconstruir() -> void:
	var appearance := _appearance
	if _raiz != null:
		_raiz.queue_free()
	_raiz = Node3D.new()
	_raiz.name = "Corpo"
	add_child(_raiz)
	_animador = null
	_usando_modelo = false
	_animacao_atual = ""

	if not _montar_modelo():
		_montar_primitivas()


## Verdadeiro quando o personagem escolhido aceita cabelo, tom de pele e roupa.
##
## Os protagonistas do Kenney nao aceitam: a aparencia deles e uma textura
## inteira, nao pecas nomeadas que dao para tingir. Mostrar esses controles com
## eles selecionados seria interface que nao faz nada — e o jogo nao tem disso.
static func aceita_personalizacao(indice: int) -> bool:
	var escolha: Dictionary = PERSONAGENS[clampi(indice, 0, PERSONAGENS.size() - 1)]
	return String(escolha.get("kit", KIT_KAYKIT)) == KIT_KAYKIT


func appearance() -> Dictionary:
	return _appearance.duplicate()


func _index(chave: String, total: int) -> int:
	return clampi(int(_appearance.get(chave, 0)), 0, total - 1)


func _outfit() -> Dictionary:
	return OUTFITS[_index("outfit", OUTFITS.size())]


# --- modelo importado ---------------------------------------------------------

func _montar_modelo() -> bool:
	var escolha: Dictionary = PERSONAGENS[_index("body", PERSONAGENS.size())]
	if String(escolha.get("kit", KIT_KAYKIT)) == KIT_KENNEY:
		return _montar_kenney(escolha)
	return _montar_kaykit(escolha)


func _montar_kaykit(escolha: Dictionary) -> bool:
	_anim_parado = ANIM_PARADO
	_anim_andando = ANIM_ANDANDO
	_anim_correndo = ANIM_CORRENDO
	_anim_interagir = ANIM_INTERAGIR
	var caminho: String = PASTA + String(escolha["arquivo"]) + ".glb"
	if not ResourceLoader.exists(caminho):
		GameLog.warn(GameLog.Channel.SYSTEM, "Modelo '%s' ausente; usando o boneco simples." % caminho)
		return false

	var instancia := (load(caminho) as PackedScene).instantiate()
	if not (instancia is Node3D):
		instancia.queue_free()
		return false

	var modelo := instancia as Node3D
	_raiz.add_child(modelo)

	_esconder_armas(modelo)
	_pintar(modelo, String(escolha["prefixo"]))
	_montar_cabelo(modelo, String(escolha["prefixo"]))
	# `root` já está nos pés: escala e pronto, sem deslocamento vertical.
	modelo.scale = Vector3.ONE * (ALTURA_ALVO / ALTURA_DO_RIG)
	modelo.position.y = 0.0
	# Os modelos do KayKit olham para +Z; o projeto inteiro assume que o rosto
	# aponta para -Z (é o que o PlayerController e a câmera esperam). Girar aqui
	# conserta o "andar de costas" sem contaminar o resto do código.
	modelo.rotation_degrees.y = GIRO_PARA_FRENTE

	_animador = _achar_animador(modelo)
	_usando_modelo = true
	_tocar(_anim_parado)
	return true


static func _todos(no: Node) -> Array[Node]:
	var lista: Array[Node] = [no]
	for filho in no.get_children():
		lista.append_array(_todos(filho))
	return lista


## O pacote é de aventureiros: vem espada, escudo, machado, cajado. Nada disso
## cabe num treinador de criaturas.
static func _esconder_armas(modelo: Node3D) -> void:
	for no in _todos(modelo):
		if not (no is MeshInstance3D):
			continue
		for arma in ARMAS:
			if String(no.name).contains(arma):
				(no as MeshInstance3D).visible = false
				break


## Tinge por cima da textura do personagem: multiplicar mantém o desenho do
## rosto e das dobras, e ainda deixa pele e roupa mudarem de cor.
func _pintar(modelo: Node3D, prefixo: String) -> void:
	var pele: Color = SKIN_TONES[_index("skin", SKIN_TONES.size())]
	var outfit := _outfit()

	var tintas := {
		prefixo + "_Head": pele,
		prefixo + "_ArmLeft": pele,
		prefixo + "_ArmRight": pele,
		prefixo + "_Body": outfit["main"],
		prefixo + "_LegLeft": outfit["legs"],
		prefixo + "_LegRight": outfit["legs"],
		prefixo + "_Cape": outfit["trim"],
	}

	for no in _todos(modelo):
		if not (no is MeshInstance3D):
			continue
		var peca := no as MeshInstance3D
		if not tintas.has(peca.name):
			continue
		peca.material_override = _tingir(peca, tintas[peca.name])


## Reaproveita a textura original da peça e só multiplica a cor por cima.
static func _tingir(peca: MeshInstance3D, cor: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	var original := peca.get_active_material(0)
	if original is BaseMaterial3D:
		material.albedo_texture = (original as BaseMaterial3D).albedo_texture
	material.albedo_color = cor
	material.roughness = 0.9
	return material


## Cabelo pendurado no osso da cabeça, para acompanhar a animação.
func _montar_cabelo(modelo: Node3D, prefixo: String) -> void:
	var esqueleto := _achar_esqueleto(modelo)
	if esqueleto == null:
		return
	var osso := esqueleto.find_bone("head")
	if osso == -1:
		return

	# Chapéu e elmo saem: o lugar é do cabelo escolhido.
	for no in _todos(modelo):
		if no is MeshInstance3D and (String(no.name).contains("_Hat") or String(no.name).contains("_Helmet")):
			(no as MeshInstance3D).visible = false

	var suporte := BoneAttachment3D.new()
	suporte.name = "SuporteCabelo"
	esqueleto.add_child(suporte)
	# `bone_idx` só depois de entrar na árvore: definido antes, o
	# BoneAttachment3D tenta desligar um sinal do esqueleto que ele ainda não
	# ligou, e a Godot escreve "Attempt to disconnect a nonexistent connection"
	# uma vez por osso. Era o que enchia o arquivo de log de ruído — justo o
	# arquivo que a gente usa para diagnosticar a máquina dos outros.
	suporte.bone_idx = osso

	var cor: Color = HAIR_COLORS[_index("hair_color", HAIR_COLORS.size())]
	var estilo: String = HAIR_STYLES[_index("hair", HAIR_STYLES.size())]
	var cabelo := Node3D.new()
	cabelo.name = "Cabelo"
	suporte.add_child(cabelo)

	match estilo:
		"tied":
			cabelo.add_child(_malha(_esfera(), cor, Vector3(0, 0.11, 0), Vector3(0.2, 0.12, 0.2)))
			cabelo.add_child(_malha(_capsula(0.035, 0.18), cor, Vector3(0, 0.06, 0.13), Vector3.ONE, Vector3(30, 0, 0)))
		"long":
			cabelo.add_child(_malha(_esfera(), cor, Vector3(0, 0.11, 0), Vector3(0.21, 0.15, 0.21)))
			cabelo.add_child(_malha(_capsula(0.075, 0.2), cor, Vector3(0, -0.02, 0.07), Vector3.ONE))
		_:
			cabelo.add_child(_malha(_esfera(), cor, Vector3(0, 0.12, 0), Vector3(0.19, 0.1, 0.19)))


static func _achar_esqueleto(no: Node) -> Skeleton3D:
	for filho in _todos(no):
		if filho is Skeleton3D:
			return filho as Skeleton3D
	return null


## Monta um protagonista do pacote Kenney (CC0).
##
## Três diferenças em relação ao KayKit, todas resolvidas aqui:
##  · a pele é uma **textura**, não peças nomeadas — trocar de personagem é
##    trocar o PNG, então nada de tingir braço e perna separado;
##  · as animações moram em arquivos próprios (`idle.fbx`, `run.fbx`,
##    `jump.fbx`), e precisam ser copiadas para um tocador nosso;
##  · a escala vem medida em cena, porque o importador de FBX entrega AABB e
##    pose de descanso colapsadas (ver ALTURA_NATURAL_KENNEY).
func _montar_kenney(escolha: Dictionary) -> bool:
	var caminho := PASTA_KENNEY + "Model/characterMedium.fbx"
	if not ResourceLoader.exists(caminho):
		GameLog.warn(GameLog.Channel.SYSTEM, "Modelo '%s' ausente; usando o boneco simples." % caminho)
		return false

	var instancia := (load(caminho) as PackedScene).instantiate()
	if not (instancia is Node3D):
		instancia.queue_free()
		return false

	var modelo := instancia as Node3D
	_raiz.add_child(modelo)

	_vestir_kenney(modelo, String(escolha.get("pele", "skaterMaleA")))
	modelo.scale = Vector3.ONE * (ALTURA_ALVO / ALTURA_NATURAL_KENNEY)
	modelo.position.y = 0.0
	modelo.rotation_degrees.y = GIRO_PARA_FRENTE

	_animador = _montar_animador_kenney(modelo)
	_usando_modelo = true
	_tocar(_anim_parado)
	return true


## A pele é um PNG de paleta: filtro nearest, senão as faixas de cor borram uma
## na outra e o personagem fica lavado.
func _vestir_kenney(modelo: Node3D, pele: String) -> void:
	var caminho := PASTA_KENNEY + "Skins/" + pele + ".png"
	if not ResourceLoader.exists(caminho):
		GameLog.warn(GameLog.Channel.SYSTEM, "Pele '%s' ausente." % caminho)
		return

	var material := StandardMaterial3D.new()
	material.albedo_texture = load(caminho)
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.roughness = 0.9
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED

	for no in _todos(modelo):
		if no is MeshInstance3D:
			(no as MeshInstance3D).material_override = material


## Copia as animações dos arquivos avulsos para um tocador plantado no modelo.
##
## As faixas apontam para `Root/Skeleton3D:<osso>`, caminho relativo à raiz da
## cena de animação — que é igual à do modelo. Por isso o tocador entra como
## filho da raiz do modelo com `root_node` apontando para ela: qualquer outro
## lugar e as faixas não encontram os ossos, a animação "toca" e nada se move.
func _montar_animador_kenney(modelo: Node3D) -> AnimationPlayer:
	var biblioteca := AnimationLibrary.new()
	var nomes: Dictionary = {}

	for papel in ANIM_KENNEY:
		var receita: Dictionary = ANIM_KENNEY[papel]
		var arquivo := PASTA_KENNEY + "Animations/" + String(receita["arquivo"]) + ".fbx"
		if not ResourceLoader.exists(arquivo):
			continue
		var cena := (load(arquivo) as PackedScene).instantiate()
		var tocador := _achar_animador(cena)
		if tocador != null:
			var origem := String(receita["nome"])
			if tocador.has_animation(origem):
				var animacao: Animation = tocador.get_animation(origem).duplicate(true)
				animacao.loop_mode = Animation.LOOP_LINEAR if papel != "interagir" else Animation.LOOP_NONE
				biblioteca.add_animation(String(papel), animacao)
				nomes[papel] = String(papel)
		cena.queue_free()

	if biblioteca.get_animation_list().is_empty():
		GameLog.warn(GameLog.Channel.SYSTEM, "Nenhuma animação do pacote Kenney foi carregada.")
		return null

	# Sem a animação pedida, cai no que existir: melhor um personagem parado numa
	# pose errada do que travado em T.
	var reserva := String(biblioteca.get_animation_list()[0])
	_anim_parado = String(nomes.get("parado", reserva))
	_anim_andando = String(nomes.get("andando", _anim_parado))
	_anim_correndo = String(nomes.get("correndo", _anim_andando))
	_anim_interagir = String(nomes.get("interagir", _anim_parado))

	var animador := AnimationPlayer.new()
	animador.name = "Animador"
	modelo.add_child(animador)
	animador.root_node = animador.get_path_to(modelo)
	animador.add_animation_library("", biblioteca)
	return animador


static func _achar_animador(no: Node) -> AnimationPlayer:
	for filho in _todos(no):
		if filho is AnimationPlayer:
			return filho as AnimationPlayer
	return null


# --- boneco de reserva --------------------------------------------------------

func _montar_primitivas() -> void:
	var outfit := _outfit()
	var pele: Color = SKIN_TONES[_index("skin", SKIN_TONES.size())]
	var cabelo: Color = HAIR_COLORS[_index("hair_color", HAIR_COLORS.size())]

	_raiz.add_child(_malha(_capsula(0.22, 0.6), outfit["main"], Vector3(0, 0.92, 0), Vector3.ONE))
	_raiz.add_child(_malha(_cilindro(0.24, 0.07), outfit["trim"], Vector3(0, 0.72, 0), Vector3.ONE))
	_raiz.add_child(_malha(_esfera(), pele, Vector3(0, 1.35, 0), Vector3.ONE * 0.24))
	_raiz.add_child(_malha(_esfera(), cabelo, Vector3(0, 1.41, 0), Vector3(0.27, 0.18, 0.27)))
	_raiz.add_child(_malha(_capsula(0.06, 0.42), pele, Vector3(0.28, 1.06, 0), Vector3.ONE))
	_raiz.add_child(_malha(_capsula(0.06, 0.42), pele, Vector3(-0.28, 1.06, 0), Vector3.ONE))
	_raiz.add_child(_malha(_capsula(0.07, 0.56), outfit["legs"], Vector3(0.1, 0.4, 0), Vector3.ONE))
	_raiz.add_child(_malha(_capsula(0.07, 0.56), outfit["legs"], Vector3(-0.1, 0.4, 0), Vector3.ONE))


# --- animação -----------------------------------------------------------------

func set_locomotion(speed_ratio: float, is_running: bool) -> void:
	_speed_ratio = clampf(speed_ratio, 0.0, 1.0)
	if _interact_timer > 0.0:
		return
	if _speed_ratio < 0.05:
		_state = State.IDLE
	elif is_running:
		_state = State.RUN
	else:
		_state = State.WALK


func play_interact() -> void:
	_state = State.INTERACT
	_interact_timer = 0.6


func current_state() -> State:
	return _state


func _process(delta: float) -> void:
	if _interact_timer > 0.0:
		_interact_timer -= delta
		if _interact_timer <= 0.0:
			_state = State.IDLE

	if _usando_modelo:
		_atualizar_animacao()
	else:
		_animar_primitivas(delta)


func _atualizar_animacao() -> void:
	if _animador == null:
		return
	match _state:
		State.RUN:
			_tocar(_anim_correndo)
			_animador.speed_scale = lerpf(0.9, 1.25, _speed_ratio)
		State.WALK:
			_tocar(_anim_andando)
			_animador.speed_scale = lerpf(0.85, 1.35, _speed_ratio)
		State.INTERACT:
			_tocar(_anim_interagir)
			_animador.speed_scale = 1.0
		_:
			_tocar(_anim_parado)
			_animador.speed_scale = 1.0


func _tocar(nome: String) -> void:
	if _animacao_atual == nome or _animador == null or not _animador.has_animation(nome):
		return
	_animacao_atual = nome
	var animacao := _animador.get_animation(nome)
	if animacao != null:
		animacao.loop_mode = Animation.LOOP_LINEAR
	# Mistura curta: sem isso a troca parado/andando dá um estalo.
	_animador.play(nome, 0.18)


func _animar_primitivas(delta: float) -> void:
	if _raiz == null:
		return
	_fase += delta * (2.0 + _speed_ratio * 8.0)
	_raiz.position.y = absf(sin(_fase)) * (0.02 + _speed_ratio * 0.06)


# --- primitivas ---------------------------------------------------------------

static func _malha(
	mesh: Mesh, cor: Color, posicao: Vector3, escala: Vector3, rotacao := Vector3.ZERO
) -> MeshInstance3D:
	var no := MeshInstance3D.new()
	no.mesh = mesh
	no.position = posicao
	no.scale = escala
	no.rotation_degrees = rotacao
	var material := StandardMaterial3D.new()
	material.albedo_color = cor
	material.roughness = 0.9
	no.material_override = material
	return no


static func _esfera() -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radial_segments = 12
	mesh.rings = 7
	return mesh


static func _capsula(raio: float, altura: float) -> CapsuleMesh:
	var mesh := CapsuleMesh.new()
	mesh.radius = raio
	mesh.height = maxf(altura, raio * 2.0 + 0.01)
	mesh.radial_segments = 10
	mesh.rings = 4
	return mesh


static func _cilindro(raio: float, altura: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = raio
	mesh.bottom_radius = raio
	mesh.height = altura
	mesh.radial_segments = 10
	return mesh
