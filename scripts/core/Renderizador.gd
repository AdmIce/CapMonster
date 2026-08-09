extends Node
## Escolhe com qual renderizador o jogo roda, e se protege de escolher errado.
##
## O padrão do projeto é **compatibilidade (OpenGL)** porque ele roda em
## praticamente qualquer máquina. O motivo é concreto: numa Intel HD P4600 sem
## Vulkan, a Godot cai sozinha para Direct3D 12, e nessa placa o D3D12 falha ao
## traduzir todos os compute shaders do Forward+ — o jogo abre tela preta e
## fecha, sem nem chegar no menu. Um jogo que não abre é pior que um jogo com
## sombra mais simples.
##
## Quem tem placa boa liga "qualidade alta" nas configurações. Trocar exige
## reiniciar: o renderizador é escolhido antes do primeiro quadro existir, então
## o jogo se relança sozinho com o argumento certo.
##
## **Modo de segurança.** Antes de relançar em qualidade, o jogo marca a troca
## como *não confirmada*; a marca só vira confirmada depois de alguns segundos
## rodando. Se a qualidade não abrir, a próxima execução vê a marca pendente e
## volta para compatibilidade sozinha. Sem isso, escolher qualidade numa máquina
## incompatível deixaria o jogo permanentemente sem abrir, e a única saída seria
## apagar o arquivo de configuração na mão.

const CHAVE := "renderizador"                 ## "compatibilidade" | "qualidade"
const CHAVE_CONFIRMADO := "renderizador_ok"
const ARG_APLICADO := "--renderizador-aplicado"

const COMPATIBILIDADE := "compatibilidade"
const QUALIDADE := "qualidade"

## Tempo rodando até considerar que o renderizador escolhido presta.
const SEGUNDOS_PARA_CONFIRMAR := 8.0


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return

	# A checagem de "já fui relançado" vem **antes** do modo de segurança. Fora
	# desta ordem, o processo relançado lia a marca pendente que ele mesmo tinha
	# acabado de gravar, concluía que a qualidade tinha falhado e desfazia a
	# escolha — a opção voltava sozinha para compatibilidade a cada tentativa.
	if OS.get_cmdline_args().has(ARG_APLICADO):
		_agendar_confirmacao()
		return

	var desejado := _desejado()
	if desejado == _atual():
		_agendar_confirmacao()
		return

	_relancar(desejado)


## O que está gravado, já passado pelo modo de segurança.
func _desejado() -> String:
	var escolhido := String(SaveManager.get_setting(CHAVE, COMPATIBILIDADE))
	if escolhido != QUALIDADE:
		return COMPATIBILIDADE
	if bool(SaveManager.get_setting(CHAVE_CONFIRMADO, true)):
		return QUALIDADE

	GameLog.warn(
		GameLog.Channel.SYSTEM,
		"Renderizador: a última tentativa em qualidade alta não chegou a rodar. Voltando para compatibilidade."
	)
	SaveManager.set_setting(CHAVE, COMPATIBILIDADE)
	SaveManager.set_setting(CHAVE_CONFIRMADO, true)
	return COMPATIBILIDADE


## Como saber em que modo estamos: o Forward+ desenha através de um
## RenderingDevice, e o modo compatibilidade não tem nenhum — `null` ali é o
## teste mais direto que a 4.3 oferece (não existe `get_rendering_method()`).
func _atual() -> String:
	return QUALIDADE if RenderingServer.get_rendering_device() != null else COMPATIBILIDADE


## O que o jogador escolheu — e não o que está rodando agora.
##
## A diferença importa: no editor (e em qualquer execução em que o relançamento
## não aconteceu) o modo em execução continua sendo o do projeto, mas a escolha
## já está gravada. Mostrar o modo em execução na caixinha fazia ela voltar
## desmarcada sozinha e parecer que a configuração não salvava.
func escolhido() -> String:
	return QUALIDADE if String(SaveManager.get_setting(CHAVE, COMPATIBILIDADE)) == QUALIDADE else COMPATIBILIDADE


func em_qualidade() -> bool:
	return _atual() == QUALIDADE


## Grava a escolha. Devolve verdadeiro quando ela exige reinício.
func definir(modo: String) -> bool:
	var alvo := QUALIDADE if modo == QUALIDADE else COMPATIBILIDADE
	SaveManager.set_setting(CHAVE, alvo)
	SaveManager.set_setting(CHAVE_CONFIRMADO, true)
	return alvo != _atual()


## Grava e reinicia **agora**. Mandar o jogador fechar e abrir na mão é pedir
## para ele descobrir depois que não pegou.
##
## Devolve falso quando não deu para reiniciar — no editor, onde relançar abriria
## outra janela do editor. Aí a escolha fica gravada e vale na próxima abertura.
func aplicar_agora(modo: String) -> bool:
	if not definir(modo):
		return true   # já está rodando assim, nada a fazer
	if _no_editor():
		GameLog.info(
			GameLog.Channel.SYSTEM,
			"Renderizador: '%s' gravado. Rodando pelo editor, então só vale no jogo exportado." % modo
		)
		return false
	_relancar(modo)
	return true


## `OS.has_feature("standalone")` é da Godot 3 e não existe na 4: usar aquilo
## dava sempre falso no jogo exportado, e o relançamento nunca acontecia — a
## opção de qualidade parecia não salvar. Na 4 quem responde é o tag "editor".
func _no_editor() -> bool:
	return OS.has_feature("editor")


func _relancar(modo: String) -> void:
	if _no_editor():
		# Relançar abriria outra janela do editor. Só avisa.
		GameLog.info(
			GameLog.Channel.SYSTEM,
			"Renderizador: '%s' pedido, mas trocar só vale no jogo exportado." % modo
		)
		return

	var argumentos := PackedStringArray([ARG_APLICADO])
	if modo == QUALIDADE:
		argumentos.append_array(["--rendering-method", "forward_plus", "--rendering-driver", "vulkan"])
		# Marca pendente: só a execução que sobreviver alguns segundos confirma.
		SaveManager.set_setting(CHAVE_CONFIRMADO, false)
	else:
		argumentos.append_array(["--rendering-method", "gl_compatibility", "--rendering-driver", "opengl3"])

	# Os argumentos do jogador vêm junto, e **depois do separador** — é o `--`
	# que faz a Godot devolvê-los em `get_cmdline_user_args()`. Sem isso, quem
	# abriu o jogo com uma opção de linha de comando a perdia só porque o
	# renderizador trocou.
	var do_usuario := PackedStringArray()
	for extra in OS.get_cmdline_user_args():
		if extra != ARG_APLICADO:
			do_usuario.append(extra)
	if not do_usuario.is_empty():
		argumentos.append("--")
		argumentos.append_array(do_usuario)

	GameLog.info(GameLog.Channel.SYSTEM, "Renderizador: reiniciando em modo %s." % modo)
	if OS.create_instance(argumentos) <= 0:
		GameLog.error(GameLog.Channel.SYSTEM, "Renderizador: não consegui reiniciar o jogo.")
		SaveManager.set_setting(CHAVE_CONFIRMADO, true)
		return
	get_tree().quit()


func _agendar_confirmacao() -> void:
	if bool(SaveManager.get_setting(CHAVE_CONFIRMADO, true)):
		return
	await get_tree().create_timer(SEGUNDOS_PARA_CONFIRMAR).timeout
	SaveManager.set_setting(CHAVE_CONFIRMADO, true)
	GameLog.info(GameLog.Channel.SYSTEM, "Renderizador: qualidade alta confirmada nesta máquina.")
