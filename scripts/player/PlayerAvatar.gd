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

enum State { IDLE, WALK, RUN, INTERACT, SENTADO }

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
const KIT_MODULAR := "modular"

## --- kit modular ---------------------------------------------------------------
##
## Quaternius Universal Base Characters + Modular Character Outfits + Universal
## Animation Library (CC0). O que ele tem de diferente dos outros dois: corpo,
## cabelo e roupa sao arquivos separados que **compartilham o mesmo esqueleto**
## -- 65 ossos, conferidos um a um antes de trazer o pacote. Por isso a montagem
## aqui nao instancia um personagem pronto: ela pendura pecas num esqueleto so.
##
## E o unico kit em que tirar a roupa deixa um corpo por baixo, em vez de deixar
## um buraco. Nos KayKit a armadura esta assada na malha do tronco.
const PASTA_MODULAR := "res://assets/models/personagens/"

## Medido em cena: o osso `root` fica nos pes e o topo do rig em 1,60; com o
## cranio, 1,72 ate a cabeca.
const ALTURA_DO_RIG_MODULAR := 1.72

## Este kit e mais alto que os outros de proposito.
##
## Medida do osso mais alto de cada kit ja montado: Cavaleiro (KayKit) 1,445 m,
## Andarilho (Kenney) 1,890 m, Aventureiro em ALTURA_ALVO 1,581 m. Ou seja: em
## altura o novo nao era menor que o KayKit -- o que engana e a proporcao. O
## KayKit e chibi, de cabeca enorme, e ocupa muito mais espaco visual; o modular
## e realista e magro, e "le" como pequeno ao lado dele.
##
## 2,0 poe o osso mais alto em ~1,86, na mesma faixa do Kenney, que e o
## personagem com que a comparacao acontece na pratica.
const ALTURA_ALVO_MODULAR := 2.0

## Estes tambem olham para +Z, igual aos KayKit -- eu tinha assumido o contrario
## e o personagem andava de costas. Nao da para ver isso numa foto parada: so
## andando, e foi assim que apareceu.
const GIRO_MODULAR := 180.0

const ANIM_MODULAR := {
	"parado": "Idle",
	"andando": "Walk",
	"correndo": "Jog_Fwd",
	"interagir": "Interact",
	"sentar_desce": "Sitting_Enter",
	"sentado": "Sitting_Idle",
	"sentar_levanta": "Sitting_Exit",
	# Pose de dirigir: sentado com as maos a frente. E a que mais se parece com
	# alguem na sela; "sentar no chao" em cima do cavalo ficaria deitado.
	"montado": "Driving",
}

## Cabelos, e a ordem importa: o indice 0 e o que sai quando ninguem escolhe.
##
## Eu tinha posto "nenhum" primeiro, achando que careca devia ser uma escolha --
## e o efeito foi o contrario: todo personagem criado sem passar por esta linha
## nascia careca. Careca continua existindo, no fim, onde e escolha de verdade.
const CABELOS_MODULARES: Array[String] = [
	"Hair_SimpleParted", "Hair_Long", "Hair_Buns", "Hair_Buzzed", "Hair_BuzzedFemale", "Hair_Beard", "",
]

## Roupas, por corpo. A ordem segue a mesma regra do cabelo: o indice 0 e o
## padrao de quem nao escolhe, entao "sem roupa" fica no fim. Com ele na frente,
## todo personagem novo nascia pelado.
##
## Os nomes de arquivo nao sao simetricos entre os dois
## (o masculino tem `Feet_Boots` e `Acc_Pauldron`, o feminino tem `Feet` e
## `Acc_Pauldrons`), entao a lista e declarada inteira em vez de montada por
## template -- template exigiria adivinhar, e adivinhar erra em silencio.
const ROUPAS_MODULARES := {
	"masculino": [
		{ "nome": "Camponês", "pecas": ["Male_Peasant_Body", "Male_Peasant_Arms", "Male_Peasant_Legs", "Male_Peasant_Feet"] },
		{ "nome": "Patrulheiro", "pecas": ["Male_Ranger_Body", "Male_Ranger_Arms", "Male_Ranger_Legs", "Male_Ranger_Feet_Boots", "Male_Ranger_Acc_Pauldron"] },
		{ "nome": "Sem roupa", "pecas": [] },
	],
	"feminino": [
		{ "nome": "Camponesa", "pecas": ["Female_Peasant_Body", "Female_Peasant_Arms", "Female_Peasant_Legs", "Female_Peasant_Feet"] },
		{ "nome": "Patrulheira", "pecas": ["Female_Ranger_Body", "Female_Ranger_Arms", "Female_Ranger_Legs", "Female_Ranger_Feet", "Female_Ranger_Acc_Pauldrons"] },
		{ "nome": "Sem roupa", "pecas": [] },
	],
}

const ANIM_PARADO := "Idle"
const ANIM_ANDANDO := "Walking_A"
const ANIM_CORRENDO := "Running_A"
const ANIM_INTERAGIR := "Interact"

## Sentar no chao, em tres tempos: desce, fica, levanta. Os KayKit trazem os
## tres; os Kenney so tem parado/correndo/pulo, e para eles `sentar()` devolve
## false -- o descanso acontece igual, o personagem so nao senta. Fingir uma
## pose com o modelo errado ficaria pior do que nao ter.
const ANIM_SENTAR_DESCE := "Sit_Floor_Down"
const ANIM_SENTADO := "Sit_Floor_Idle"
const ANIM_SENTAR_LEVANTA := "Sit_Floor_StandUp"

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
	# Kit modular, no fim da lista de proposito: quem ja tem personagem salvo
	# guarda o **indice** da escolha, e inserir no meio trocaria o corpo de todo
	# mundo que ja estava jogando.
	{ "kit": KIT_MODULAR, "arquivo": "Superhero_Male_FullBody", "sexo": "masculino", "nome": "Aventureiro" },
	{ "kit": KIT_MODULAR, "arquivo": "Superhero_Female_FullBody", "sexo": "feminino", "nome": "Aventureira" },
]
## Nome antigo, mantido para a tela de criação não precisar de dois caminhos.
const BODY_TYPES: Array[String] = [
	"Cavaleiro", "Bárbaro", "Ladina", "Maga",
	"Andarilho", "Andarilha", "Fugitivo", "Autômata",
	"Aventureiro", "Aventureira",
]

const SKIN_TONES: Array[Color] = [Color("#F0D2B4"), Color("#C08E62"), Color("#8A5C3C")]
const HAIR_COLORS: Array[Color] = [Color("#2B2320"), Color("#8A5A2B"), Color("#C7B49A")]
const HAIR_STYLES: Array[String] = ["cropped", "tied", "long"]
const HAIR_LABELS: Array[String] = ["Curto", "Preso", "Comprido"]

## Nomes dos cabelos do kit modular, na ordem de CABELOS_MODULARES.
const CABELOS_MODULARES_NOMES: Array[String] = [
	"Repartido", "Comprido", "Coques", "Raspado", "Curtinho", "Barba", "Careca",
]


## Os cabelos que este personagem tem, por indice de corpo.
##
## Cada kit tem os seus: o KayKit troca tres penteados desenhados a mao, o
## modular troca a malha inteira e tem seis. Uma lista fixa para os dois
## significava mostrar tres opcoes num personagem que tem seis -- foi o que
## escondeu metade dos cabelos novos.
static func rotulos_de_cabelo(indice_do_corpo: int) -> Array[String]:
	var escolha: Dictionary = PERSONAGENS[clampi(indice_do_corpo, 0, PERSONAGENS.size() - 1)]
	if String(escolha.get("kit", KIT_KAYKIT)) == KIT_MODULAR:
		return CABELOS_MODULARES_NOMES
	return HAIR_LABELS


## Idem para a roupa. No modular ela depende do corpo, porque a malha e cortada
## para ele: a roupa masculina nao serve no corpo feminino.
static func rotulos_de_roupa(indice_do_corpo: int) -> Array[String]:
	var escolha: Dictionary = PERSONAGENS[clampi(indice_do_corpo, 0, PERSONAGENS.size() - 1)]
	if String(escolha.get("kit", KIT_KAYKIT)) == KIT_MODULAR:
		var nomes: Array[String] = []
		for conjunto in ROUPAS_MODULARES.get(String(escolha.get("sexo", "masculino")), []):
			nomes.append(String(conjunto.get("nome", "?")))
		return nomes
	var padrao: Array[String] = []
	for outfit in OUTFITS:
		padrao.append(String(outfit["name"]))
	return padrao
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
## Nome da animacao de passagem tocando agora (sentar/levantar). Enquanto tem
## uma, o estado de locomocao nao manda na animacao -- senao o quadro seguinte
## voltaria para "parado" e cortaria a descida pela metade.
var _transicao: String = ""
var _depois_da_transicao: String = ""
## Nomes das tres animacoes de sentar do kit em uso. Comecam nos do KayKit e
## sao trocados por quem monta outro kit -- eram constantes fixas, e com um
## terceiro kit no jogo uma constante fixa seria o mesmo que dizer "so o KayKit
## senta".
var _anim_sentar_desce: String = ANIM_SENTAR_DESCE
var _anim_sentado: String = ANIM_SENTADO
var _anim_sentar_levanta: String = ANIM_SENTAR_LEVANTA
## Pose de quem esta montado. Vazia nos kits que nao tem: ali o personagem
## monta em pe, que e feio, mas e melhor do que uma pose de sentar no chao em
## cima de um cavalo.
var _anim_montado: String = ""
var _speed_ratio: float = 0.0
var _interact_timer: float = 0.0

var _raiz: Node3D = null
var _animador: AnimationPlayer = null
var _asas: Asas = null
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
	elif OS.is_debug_build():
		# "Por que este personagem esta menor que o outro?" nao se responde
		# olhando: kits diferentes tem proporcao diferente, e a foto engana.
		# Medido pelo osso mais alto ja escalado -- a AABB de malha com pele e da
		# pose de vinculo e nao diz onde o personagem pisa.
		call_deferred("_relatar_altura")


func _relatar_altura() -> void:
	var esqueleto := _achar_esqueleto(_raiz)
	if esqueleto == null:
		return
	var topo := -INF
	var chao := INF
	for i in esqueleto.get_bone_count():
		var y: float = (esqueleto.global_transform * esqueleto.get_bone_global_pose(i)).origin.y
		topo = maxf(topo, y)
		chao = minf(chao, y)
	# O osso mais baixo tem de ficar em zero ou acima. Negativo quer dizer
	# personagem enterrado, que e o tipo de erro que se ve e nao se mede.
	# E o ponto mais baixo da **malha**, que e outra coisa: o osso do pe fica no
	# tornozelo, e a sola desce abaixo dele. E a sola que encosta no chao.
	var sola := INF
	for no in _todos(_raiz):
		if no is MeshInstance3D and (no as MeshInstance3D).mesh != null:
			var malha := no as MeshInstance3D
			var caixa := malha.global_transform * malha.mesh.get_aabb()
			sola = minf(sola, caixa.position.y)

	GameLog.verbose(GameLog.Channel.SYSTEM,
		"Altura montada: %.3f m; osso mais baixo %.3f m; malha mais baixa %.3f m." % [topo, chao, sola])


## Verdadeiro quando o personagem escolhido aceita cabelo, tom de pele e roupa.
##
## Os protagonistas do Kenney nao aceitam: a aparencia deles e uma textura
## inteira, nao pecas nomeadas que dao para tingir. Mostrar esses controles com
## eles selecionados seria interface que nao faz nada — e o jogo nao tem disso.
static func aceita_personalizacao(indice: int) -> bool:
	var escolha: Dictionary = PERSONAGENS[clampi(indice, 0, PERSONAGENS.size() - 1)]
	var kit := String(escolha.get("kit", KIT_KAYKIT))
	# O modular aceita pelo caminho oposto ao do KayKit: la se tinge peca
	# nomeada, aqui se troca a malha inteira. Para quem escolhe, da no mesmo --
	# os dois controles fazem alguma coisa.
	return kit == KIT_KAYKIT or kit == KIT_MODULAR


func appearance() -> Dictionary:
	return _appearance.duplicate()


func _index(chave: String, total: int) -> int:
	return clampi(int(_appearance.get(chave, 0)), 0, total - 1)


func _outfit() -> Dictionary:
	return OUTFITS[_index("outfit", OUTFITS.size())]


# --- modelo importado ---------------------------------------------------------

func _montar_modelo() -> bool:
	var escolha: Dictionary = PERSONAGENS[_index("body", PERSONAGENS.size())]
	match String(escolha.get("kit", KIT_KAYKIT)):
		KIT_KENNEY:
			return _montar_kenney(escolha)
		KIT_MODULAR:
			return _montar_modular(escolha)
		_:
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
	_montar_asas(modelo)
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


## Pendura as asas nas costas, no osso do tronco.
##
## Os dois kits nomeiam o esqueleto de forma diferente, então procura por uma
## lista de candidatos em vez de cravar um nome. Sem osso servível elas entram
## direto no modelo: ficam paradas em relação ao corpo, o que é pior que
## acompanhar a animação, mas melhor que não ter asa.
const OSSOS_DAS_COSTAS := ["chest", "spine", "Spine", "spine_02", "mixamorig:Spine1", "Bip01_Spine1"]


## Asas desligadas por decisão do dono do jogo: "não vamos usar por enquanto".
##
## Um interruptor em vez de apagar o código: o `Asas.gd` continua inteiro e
## testado, e voltar atrás é trocar este `false`. Apagar custaria refazer a
## batida das penas, o encaixe no osso das costas e a briga com a capa.
##
## O voo (dois toques no espaço) continua funcionando -- é outra coisa, e não
## foi ela que ele mandou tirar.
const USAR_ASAS := false


func _montar_asas(modelo: Node3D) -> void:
	if not USAR_ASAS:
		# Sem asas, a capa volta: ela só tinha sido escondida porque as duas
		# disputavam o mesmo lugar nas costas.
		return

	# A capa ocupa exatamente o espaço das asas: com as duas, uma atravessa a
	# outra a cada passo. O lugar nas costas é um só, e agora é das asas.
	for no in _todos(modelo):
		if no is MeshInstance3D and String(no.name).contains("_Cape"):
			(no as MeshInstance3D).visible = false

	_asas = Asas.criar()
	var esqueleto := _achar_esqueleto(modelo)
	var osso := -1
	if esqueleto != null:
		for nome in OSSOS_DAS_COSTAS:
			osso = esqueleto.find_bone(nome)
			if osso != -1:
				break

	if esqueleto == null or osso == -1:
		modelo.add_child(_asas)
		_asas.position.y = ALTURA_ALVO * 0.62
		return

	var suporte := BoneAttachment3D.new()
	suporte.name = "SuporteAsas"
	esqueleto.add_child(suporte)
	# `bone_idx` só depois de entrar na árvore: definido antes, o
	# BoneAttachment3D tenta desligar um sinal que ainda não ligou.
	suporte.bone_idx = osso
	suporte.add_child(_asas)


## Troca a pose das asas. O controlador chama isto todo quadro.
func definir_voo(voando: bool, delta: float) -> void:
	if _asas != null and is_instance_valid(_asas):
		_asas.definir_voo(voando, delta)


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
## Monta o personagem modular: um corpo, um cabelo e um conjunto de roupa,
## todos pendurados no **mesmo** esqueleto.
##
## E o unico kit que nao instancia um personagem pronto. As pecas vem em
## arquivos separados, cada uma com a sua propria copia do esqueleto; usar todas
## daria varios esqueletos animados em paralelo, que e desperdicio e sai de
## sincronia. Em vez disso, so as malhas sao aproveitadas: elas mudam de pai
## para o esqueleto do corpo e passam a ser deformadas por ele.
func _montar_modular(escolha: Dictionary) -> bool:
	var caminho := PASTA_MODULAR + "corpos/" + String(escolha["arquivo"]) + ".gltf"
	if not ResourceLoader.exists(caminho):
		GameLog.warn(GameLog.Channel.SYSTEM, "Corpo '%s' ausente; usando o boneco simples." % caminho)
		return false

	var instancia := (load(caminho) as PackedScene).instantiate()
	if not (instancia is Node3D):
		instancia.queue_free()
		return false

	var modelo := instancia as Node3D
	_raiz.add_child(modelo)

	var esqueleto := _achar_esqueleto(modelo)
	if esqueleto == null:
		GameLog.warn(GameLog.Channel.SYSTEM, "Corpo modular sem Skeleton3D: %s" % caminho)
		modelo.queue_free()
		return false

	_vestir_modular(esqueleto, escolha)

	modelo.scale = Vector3.ONE * (ALTURA_ALVO_MODULAR / ALTURA_DO_RIG_MODULAR)
	modelo.position.y = 0.0
	modelo.rotation_degrees.y = GIRO_MODULAR

	_animador = _montar_animador_modular(modelo)
	_montar_asas(modelo)
	_usando_modelo = true
	_tocar(_anim_parado)
	# Depois de tudo montado: so ai da para saber onde fica a sola, porque a
	# bota faz parte da roupa e muda o ponto mais baixo.
	call_deferred("_assentar_no_chao", modelo)
	return true


## Levanta o modelo ate a sola encostar em y = 0.
##
## O osso do pe fica no tornozelo, nao na sola -- alinhar o esqueleto em zero
## deixa o pe 1 cm enterrado, que e pouco no numero e obvio na tela. Medido em
## cena porque depende do calcado: a bota do Patrulheiro desce mais que o pe
## descalco.
##
## So vale para o kit modular. Nos KayKit a AABB da malha e da pose de vinculo e
## devolve -1,3 m, que nao tem relacao com onde o personagem pisa -- corrigir
## por ela jogaria o personagem para o alto.
func _assentar_no_chao(modelo: Node3D) -> void:
	if not is_instance_valid(modelo) or not modelo.is_inside_tree():
		return
	var sola := INF
	for no in _todos(modelo):
		if no is MeshInstance3D and (no as MeshInstance3D).mesh != null:
			var malha := no as MeshInstance3D
			sola = minf(sola, (malha.global_transform * malha.mesh.get_aabb()).position.y)
	if sola == INF or absf(sola) < 0.001:
		return
	# Em relacao ao avatar, que esta nos pes do personagem.
	modelo.position.y -= sola - global_position.y
	GameLog.verbose(GameLog.Channel.SYSTEM, "Personagem assentado: sola estava em %.3f m." % sola)


func _vestir_modular(esqueleto: Skeleton3D, escolha: Dictionary) -> void:
	var sexo := String(escolha.get("sexo", "masculino"))
	var conjuntos: Array = ROUPAS_MODULARES.get(sexo, [])
	if not conjuntos.is_empty():
		var conjunto: Dictionary = conjuntos[_index("outfit", conjuntos.size())]
		var pecas: Array = conjunto.get("pecas", [])
		for peca in pecas:
			_pendurar_peca(esqueleto, "roupas/" + String(peca))
		if not pecas.is_empty():
			# A ordem importa: primeiro a pele que falta nas pecas, depois o
			# encolhimento -- senao o encolhimento seria copiado junto e o
			# antebraco tambem afundaria.
			_emprestar_a_pele(esqueleto)
			_encolher_o_corpo(esqueleto)

	var cabelo := CABELOS_MODULARES[_index("hair", CABELOS_MODULARES.size())]
	if cabelo != "":
		_pendurar_peca(esqueleto, "cabelos/" + cabelo)


## Da a textura de pele do corpo as superficies de roupa que vieram sem nenhuma.
##
## As pecas do pacote misturam pano e pele na mesma malha: a manga do
## Patrulheiro e uma superficie, o antebraco de fora e outra. A do pano vem com
## a textura da roupa; a da pele vem **sem textura**, branca, porque o autor
## esperava que ela usasse a textura do corpo -- e essa ligacao nao atravessa o
## `.gltf`.
##
## Era o que aparecia como "a roupa em algumas partes sem textura". Medido: em
## `Male_Ranger_Arms`, a superficie 1 chega com albedo branco e nada mais.
func _emprestar_a_pele(esqueleto: Skeleton3D) -> void:
	var pele := _material_da_pele(esqueleto)
	if pele == null:
		return

	for no in esqueleto.get_children():
		if not (no is MeshInstance3D):
			continue
		var malha := no as MeshInstance3D
		if malha.mesh == null or String(malha.name).begins_with("SuperHero"):
			continue
		for i in malha.mesh.get_surface_count():
			var material := malha.get_active_material(i)
			if material is StandardMaterial3D and (material as StandardMaterial3D).albedo_texture != null:
				continue
			malha.set_surface_override_material(i, pele)


func _material_da_pele(esqueleto: Skeleton3D) -> StandardMaterial3D:
	for no in esqueleto.get_children():
		if no is MeshInstance3D and String(no.name).begins_with("SuperHero"):
			var material := (no as MeshInstance3D).get_active_material(0)
			if material is StandardMaterial3D:
				return (material as StandardMaterial3D).duplicate() as StandardMaterial3D
	return null


## Encolhe a pele por dentro da roupa.
##
## Roupa e corpo sao malhas separadas modeladas quase na mesma superficie, e
## "quase" e o problema: o peito e os bracos furavam a roupa em movimento, que e
## o que se via como "roupa bugada". Deslocar cada vertice para dentro ao longo
## da normal e o remedio padrao para isso, e o material ja sabe fazer (`grow`).
##
## Um centimetro basta e nao deforma nada visivel -- so o que ja estava
## escondido sob a roupa e que passou a ficar escondido de verdade.
##
## Nao mexe na cabeca nem nas maos porque nao precisa: elas nao tem roupa por
## cima, e um centimetro nelas nao muda nada na tela.
const ENCOLHIMENTO_SOB_A_ROUPA := 0.01


func _encolher_o_corpo(esqueleto: Skeleton3D) -> void:
	for no in esqueleto.get_children():
		if not (no is MeshInstance3D):
			continue
		var malha := no as MeshInstance3D
		# So a pele: as pecas de roupa entraram como irmas e nao podem encolher
		# junto, senao o problema so muda de lado.
		if not String(malha.name).begins_with("SuperHero"):
			continue
		var material := malha.get_active_material(0)
		if material == null or not (material is StandardMaterial3D):
			continue
		var copia := (material as StandardMaterial3D).duplicate() as StandardMaterial3D
		copia.grow = true
		copia.grow_amount = -ENCOLHIMENTO_SOB_A_ROUPA
		malha.material_override = copia


## Tira as malhas de um arquivo de peca e prende no esqueleto que ja existe.
##
## `skeleton` precisa ser reapontado na mao: a malha vinha com um caminho para o
## esqueleto do proprio arquivo, e depois da mudanca de pai esse caminho aponta
## para um no que foi jogado fora -- a peca aparece em T, parada, enquanto o
## corpo anda.
func _pendurar_peca(esqueleto: Skeleton3D, relativo: String) -> void:
	var caminho := PASTA_MODULAR + relativo + ".gltf"
	if not ResourceLoader.exists(caminho):
		GameLog.warn(GameLog.Channel.SYSTEM, "Peça ausente: %s" % caminho)
		return

	var cena := (load(caminho) as PackedScene).instantiate()
	var malhas: Array[MeshInstance3D] = []
	for no in _todos(cena):
		if no is MeshInstance3D:
			malhas.append(no as MeshInstance3D)

	for malha in malhas:
		malha.get_parent().remove_child(malha)
		esqueleto.add_child(malha)
		malha.skeleton = NodePath("..")

	if OS.is_debug_build():
		for m in malhas:
			if m.mesh == null:
				continue
			for i in m.mesh.get_surface_count():
				var mat := m.get_active_material(i)
				var textura := "SEM MATERIAL"
				if mat is StandardMaterial3D:
					var t: Texture2D = (mat as StandardMaterial3D).albedo_texture
					textura = t.resource_path.get_file() if t != null else "SEM TEXTURA (cor %s)" % (mat as StandardMaterial3D).albedo_color
				GameLog.verbose(GameLog.Channel.SYSTEM, "  %s sup%d -> %s" % [m.name, i, textura])

	cena.queue_free()


## O tocador de animacoes do kit modular.
##
## As animacoes vem num arquivo so, separado dos corpos, e as faixas apontam
## para `Armature/Skeleton3D:<osso>`. O corpo tem exatamente essa hierarquia, e
## e por isso que o tocador entra na raiz do modelo: com `root_node` em outro
## lugar, as faixas nao acham osso nenhum e o personagem fica em T sem erro
## nenhum no console.
func _montar_animador_modular(modelo: Node3D) -> AnimationPlayer:
	var caminho := PASTA_MODULAR + "animacoes/UAL1_Standard.glb"
	if not ResourceLoader.exists(caminho):
		GameLog.warn(GameLog.Channel.SYSTEM, "Biblioteca de animações ausente: %s" % caminho)
		return null

	var cena := (load(caminho) as PackedScene).instantiate()
	var origem := _achar_animador(cena)
	if origem == null:
		cena.queue_free()
		return null

	var biblioteca := AnimationLibrary.new()
	var nomes: Dictionary = {}
	for papel in ANIM_MODULAR:
		var nome := String(ANIM_MODULAR[papel])
		if not origem.has_animation(nome):
			continue
		var animacao: Animation = origem.get_animation(nome).duplicate(true)
		# Sentar e interagir tocam uma vez; o resto e ciclo. Em laco, "sentar"
		# faria o personagem sentar e levantar para sempre.
		animacao.loop_mode = Animation.LOOP_NONE if papel in ["interagir", "sentar_desce", "sentar_levanta"] else Animation.LOOP_LINEAR
		biblioteca.add_animation(nome, animacao)
		nomes[papel] = nome
	cena.queue_free()

	if biblioteca.get_animation_list().is_empty():
		GameLog.warn(GameLog.Channel.SYSTEM, "Nenhuma animação modular foi carregada.")
		return null

	var reserva := String(biblioteca.get_animation_list()[0])
	_anim_parado = String(nomes.get("parado", reserva))
	_anim_andando = String(nomes.get("andando", _anim_parado))
	_anim_correndo = String(nomes.get("correndo", _anim_andando))
	_anim_interagir = String(nomes.get("interagir", _anim_parado))
	_anim_sentar_desce = String(nomes.get("sentar_desce", ""))
	_anim_sentado = String(nomes.get("sentado", ""))
	_anim_sentar_levanta = String(nomes.get("sentar_levanta", _anim_parado))
	_anim_montado = String(nomes.get("montado", ""))

	var animador := AnimationPlayer.new()
	animador.name = "Animador"
	modelo.add_child(animador)
	animador.root_node = animador.get_path_to(modelo)
	animador.add_animation_library("", biblioteca)
	return animador


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
	_montar_asas(modelo)
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
	# Sentado nao anda. Sem isto, o primeiro quadro depois de sentar ja voltaria
	# para "parado", porque o controlador continua reportando velocidade zero.
	if _state == State.SENTADO:
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
	# Passagem em andamento (sentando ou levantando): quem manda e ela, ate
	# terminar. `_ao_terminar_animacao` devolve o controle.
	if _transicao != "":
		return
	if _state == State.SENTADO:
		_tocar(_anim_sentado)
		_animador.speed_scale = 1.0
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


# --- sentar -------------------------------------------------------------------

## Este personagem sabe sentar? Os Kenney nao sabem, e quem chama precisa poder
## seguir em frente sem a pose em vez de travar esperando uma animacao que nao
## existe.
func pode_sentar() -> bool:
	return _animador != null and _animador.has_animation(_anim_sentado)


## Senta no chao. Devolve false quando o modelo nao tem a animacao.
func sentar() -> bool:
	if not pode_sentar():
		return false
	_state = State.SENTADO
	_tocar_uma_vez(_anim_sentar_desce, _anim_sentado)
	return true


func levantar() -> void:
	if _state != State.SENTADO:
		return
	_state = State.IDLE
	_tocar_uma_vez(_anim_sentar_levanta, _anim_parado)


## Toca uma animacao **uma vez** e emenda na seguinte quando ela acabar.
##
## O `_tocar` normal forca laco em tudo, o que serve para andar e parar mas
## deixaria o personagem descendo para o chao eternamente.
func _tocar_uma_vez(nome: String, depois: String) -> void:
	if _animador == null or not _animador.has_animation(nome):
		# Sem a animacao de passagem, vai direto para a pose final -- senta de
		# um quadro para o outro, que e feio mas funciona.
		_transicao = ""
		_tocar(depois)
		return

	if not _animador.animation_finished.is_connected(_ao_terminar_animacao):
		_animador.animation_finished.connect(_ao_terminar_animacao)

	var animacao := _animador.get_animation(nome)
	if animacao != null:
		animacao.loop_mode = Animation.LOOP_NONE
	_transicao = nome
	_depois_da_transicao = depois
	_animacao_atual = nome
	_animador.speed_scale = 1.0
	_animador.play(nome, 0.15)


func _ao_terminar_animacao(nome: StringName) -> void:
	if String(nome) != _transicao:
		return
	_transicao = ""
	_tocar(_depois_da_transicao)


# --- montaria -----------------------------------------------------------------

## Este personagem tem pose de montaria?
func pode_montar() -> bool:
	return _animador != null and _anim_montado != "" and _animador.has_animation(_anim_montado)


## Entra na pose de quem esta na sela. Devolve false quando o kit nao tem a
## pose -- quem chamou decide se monta em pe mesmo ou se nem monta.
func montar() -> bool:
	if not pode_montar():
		return false
	_state = State.SENTADO
	_transicao = ""
	_tocar(_anim_montado)
	return true


func desmontar() -> void:
	if _state != State.SENTADO:
		return
	_state = State.IDLE
	_transicao = ""
	_tocar(_anim_parado)
