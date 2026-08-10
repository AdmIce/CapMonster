class_name ObjetoDeCena
extends Interactable
## Um móvel com que dá para conversar.
##
## A televisão e a cama do quarto inicial não são NPCs nem portões: são pedaços
## do `.glb` do cenário, sem nó nenhum de jogo. Este script põe um interagível
## invisível por cima deles, declarado no maps.json — o modelo continua sendo
## só arte, e a lógica mora no JSON.
##
## Também é o que segura a ordem da abertura. A cama só funciona depois da
## televisão porque ela **exige uma marca** que a televisão deixa: sem isso o
## jogador deitaria na cama no primeiro segundo e pularia a abertura inteira sem
## saber que existia.

signal dialogo_pedido(quem: String, falas: Array)
signal acao_pedida(acao: String)

var objeto_id: String = ""
var falas: Array = []
## Ação disparada depois da fala. Hoje: "dormir".
var acao: String = ""
## Marca gravada na ficha do jogador ao interagir. Serve para outro objeto exigir.
var marca: String = ""
## Marca que precisa existir para este objeto funcionar.
var exige_marca: String = ""
## O que dizer quando a marca ainda não existe.
var recado_bloqueado: String = ""


static func criar(dados: Dictionary) -> ObjetoDeCena:
	var no := ObjetoDeCena.new()
	no.objeto_id = String(dados.get("id", ""))
	no.title = String(dados.get("name", "Objeto"))
	no.verb = String(dados.get("verb", "Olhar"))
	no.falas = (dados.get("lines", []) as Array).duplicate()
	no.acao = String(dados.get("acao", ""))
	no.marca = String(dados.get("marca", ""))
	no.exige_marca = String(dados.get("exige_marca", ""))
	no.recado_bloqueado = String(dados.get("recado_bloqueado", ""))
	no.radius = float(dados.get("raio", 2.2))
	no.name = "Objeto_%s" % no.objeto_id

	var pos: Array = dados.get("pos", [0, 0])
	var altura := float(dados.get("altura", 0.0))
	no.position = Vector3(pos[0], altura, pos[1])
	return no


func is_available() -> bool:
	if exige_marca == "":
		return true
	if GameManager.player == null:
		return false
	return bool(GameManager.player.get_flag(exige_marca, false))


func unavailable_reason() -> String:
	return recado_bloqueado


func _perform(_by: Node3D) -> void:
	if marca != "" and GameManager.player != null:
		GameManager.player.set_flag(marca, true)

	if not falas.is_empty():
		dialogo_pedido.emit(title, falas)

	if acao != "":
		acao_pedida.emit(acao)
