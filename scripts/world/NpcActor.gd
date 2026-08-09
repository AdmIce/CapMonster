class_name NpcActor
extends Interactable
## Um morador com quem dá para conversar.
##
## O visual sai do HumanoidBuilder usando as cores declaradas em maps.json, e o
## texto das falas também vem de lá: esta classe só entrega o diálogo.

signal dialogue_requested(speaker: String, lines: Array)
signal shop_requested(config: Dictionary)

const IDLE_SWAY_SPEED := 1.6

var npc_id: String = ""
var speaker_name: String = "Morador"
var role: String = "villager"
var lines: Array = []
var heals_team: bool = false
## Preenchido quando o NPC tem `shop` no maps.json.
var shop: Dictionary = {}
## Caminho de um desenho em `assets/npc/`. Vazio monta o corpo de caixas.
var sprite: String = ""
## Quais quadros do desenho entram na animação; vazio usa todos. Ver NpcSprite.
var sprite_quadros: Array = []

var _body: Node3D = null
var _phase: float = 0.0
var _desenhado: bool = false


static func create(data: Dictionary) -> NpcActor:
	var npc := NpcActor.new()
	npc.npc_id = data.get("id", "")
	npc.speaker_name = data.get("name", "Morador")
	npc.role = data.get("role", "villager")
	npc.lines = (data.get("lines", []) as Array).duplicate()
	npc.heals_team = bool(data.get("heals", false))
	npc.shop = (data.get("shop", {}) as Dictionary).duplicate(true)
	npc.title = npc.speaker_name
	npc.verb = "Negociar com" if not npc.shop.is_empty() else "Falar com"
	npc.name = "Npc_%s" % npc.npc_id
	npc.set_meta("colors", data.get("colors", {}))
	npc.sprite = str(data.get("sprite", ""))
	npc.sprite_quadros = (data.get("sprite_quadros", []) as Array).duplicate()
	var pos: Array = data.get("pos", [0, 0])
	npc.position = Vector3(pos[0], 0.0, pos[1])
	npc.rotation_degrees.y = float(data.get("yaw", 0))
	return npc


func _ready() -> void:
	super._ready()
	# Um desenho declarado que não existe no disco cairia numa figura invisível.
	# Voltar para o corpo de caixas deixa o NPC conversável do mesmo jeito, e o
	# aviso do NpcSprite diz o que faltou.
	if NpcSprite.disponivel(sprite):
		_body = NpcSprite.criar(sprite, sprite_quadros)
		_desenhado = true
	else:
		if sprite != "":
			push_warning("NpcActor %s: desenho '%s' nao encontrado, usando o corpo padrao." % [npc_id, sprite])
		_body = HumanoidBuilder.build(get_meta("colors", {}), role)
	add_child(_body)
	_build_collider()


func _process(delta: float) -> void:
	if _body == null:
		return
	_phase += delta * IDLE_SWAY_SPEED
	_body.position.y = sin(_phase) * 0.02
	# NPC desenhado não balança: ele já tem animação própria nos quadros, e
	# girar uma figura que está sempre de frente para a câmera não faz nada
	# além de arrastar o desenho de lado.
	if not _desenhado:
		_body.rotation_degrees.y = sin(_phase * 0.45) * 3.0


func _build_collider() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = GameLayers.WORLD
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = 0.42
	cylinder.height = 1.8
	shape.shape = cylinder
	shape.position = Vector3(0, 0.9, 0)
	body.add_child(shape)
	add_child(body)


func _perform(_by: Node3D) -> void:
	# Mercador abre a loja direto: obrigar a passar por duas falas toda vez que
	# você quer comprar um núcleo cansa rápido.
	if not shop.is_empty():
		GameLog.verbose(GameLog.Channel.WORLD, "Abrindo a loja de %s." % speaker_name)
		shop_requested.emit(shop)
		return
	if lines.is_empty():
		return
	GameLog.verbose(GameLog.Channel.WORLD, "Conversando com %s." % speaker_name)
	dialogue_requested.emit(speaker_name, lines)
