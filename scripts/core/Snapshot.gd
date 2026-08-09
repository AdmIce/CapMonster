extends Node
## Ferramenta de desenvolvimento: tira uma foto da tela e fecha o jogo.
##
##   godot --path . -- --snapshot          (6 s, padrão)
##   godot --path . -- --snapshot=12       (espera 12 s antes de fotografar)
##
## Existe porque o modo headless usa um renderizador falso e não desenha nada:
## para conferir se um modelo importado ficou com a textura certa, ou se o HUD
## está no lugar, é preciso rodar com janela. Isso automatiza o "abrir, olhar,
## fechar".
##
## O arquivo sai em user://snapshot.png, que no Windows fica em
## %APPDATA%\Godot\app_userdata\<nome do projeto>\snapshot.png
##
## De propósito sem `class_name`: o Boot carrega este script por caminho
## (preload), então ele funciona mesmo antes de o editor reindexar as classes.
## Só é instanciado atrás de OS.is_debug_build().

const CAMINHO := "user://snapshot.png"
const ESPERA_PADRAO := 6.0

var _restante: float = ESPERA_PADRAO
var _capturando: bool = false
## Com `--snapshot-batalha`, espera uma luta começar antes de fotografar. Sem
## isso é sorte pegar o combate no ar: uma batalha dura poucos segundos.
var _esperar_batalha: bool = false
var _limite_espera: float = 90.0


## Lê a linha de comando. Devolve false quando `--snapshot` não foi pedido -
## nesse caso quem chamou deve descartar a instância.
func configurar_a_partir_da_linha_de_comando() -> bool:
	var pedido := false
	for argumento in OS.get_cmdline_user_args():
		if argumento == "--snapshot":
			pedido = true
		elif argumento.begins_with("--snapshot="):
			_restante = maxf(0.5, float(argumento.split("=")[1]))
			pedido = true
		elif argumento == "--snapshot-batalha":
			_esperar_batalha = true
			pedido = true
	return pedido


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameLog.info(GameLog.Channel.SYSTEM, "Snapshot: fotografando em %.1f s." % _restante)


func _process(delta: float) -> void:
	if _capturando:
		return

	if _esperar_batalha:
		_limite_espera -= delta
		if _limite_espera <= 0.0:
			GameLog.warn(GameLog.Channel.SYSTEM, "Snapshot: nenhuma batalha começou a tempo.")
			_capturando = true
			_capturar()
		elif _batalha_em_andamento():
			GameLog.info(GameLog.Channel.SYSTEM, "Snapshot: batalha detectada, fotografando.")
			_capturando = true
			_capturar()
		return

	_restante -= delta
	if _restante <= 0.0:
		_capturando = true
		_capturar()


func _batalha_em_andamento() -> bool:
	for no in get_tree().get_nodes_in_group("battle"):
		if no.get("em_batalha") == true:
			return true
	return false


func _capturar() -> void:
	# Espera o quadro terminar de ser desenhado, senão a imagem sai vazia.
	await RenderingServer.frame_post_draw
	var imagem := get_viewport().get_texture().get_image()
	var erro := imagem.save_png(CAMINHO)
	if erro == OK:
		GameLog.info(
			GameLog.Channel.SYSTEM,
			"Snapshot salvo em %s" % ProjectSettings.globalize_path(CAMINHO)
		)
	else:
		GameLog.error(GameLog.Channel.SYSTEM, "Snapshot falhou (erro %d)." % erro)
	get_tree().quit()
