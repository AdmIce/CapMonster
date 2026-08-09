extends Node
## Atualização automática pelas Releases do GitHub.
##
## O problema que isto resolve: sem ele, cada correção vira "manda o .exe de
## novo no zap" — e metade das pessoas continua jogando a versão velha, o que
## num jogo online significa cliente e servidor discordando.
##
## Como funciona:
##   1. o jogo pergunta ao GitHub qual é a última release do repositório;
##   2. se a versão de lá for maior que a daqui, avisa e mostra o que mudou;
##   3. baixando, ele grava os arquivos novos ao lado do jogo e reinicia.
##
## **Por que um .bat para trocar os arquivos.** No Windows não dá para
## sobrescrever um .exe que está rodando. Então o jogo baixa para uma pasta
## temporária, escreve um script que espera o processo morrer, copia por cima e
## reabre o jogo. É feio e é o jeito que funciona.
##
## Nada aqui é obrigatório: se o GitHub estiver fora do ar, ou sem internet, o
## jogo continua abrindo normalmente e o painel simplesmente não aparece.

signal verificacao_terminou(disponivel: bool, info: Dictionary)
signal progresso(bytes: int, total: int)
signal falhou(motivo: String)

const REPOSITORIO := "AdmIce/CapMonster"
const API := "https://api.github.com/repos/%s/releases/latest" % REPOSITORIO

## Nomes dos arquivos que uma release precisa trazer. O .pck é o jogo; o .exe é
## o motor, e só muda quando a versão da Godot muda — por isso é opcional.
const ARQUIVO_CONTEUDO := "CapMonster.pck"
const ARQUIVO_MOTOR := "CapMonster.exe"

const PASTA_TEMP := "user://atualizacao/"

var ultima_info: Dictionary = {}

var _http: HTTPRequest = null
var _baixando: Array[Dictionary] = []
var _baixados: Array[String] = []


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.name = "HTTP"
	# Sem isto, um download de 80 MB estoura o limite padrão e volta vazio.
	_http.use_threads = true
	add_child(_http)


func versao_local() -> String:
	return String(ProjectSettings.get_setting("application/config/version", "0.0.0"))


## Pergunta ao GitHub. O resultado chega em `verificacao_terminou`.
func verificar() -> void:
	if _http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return
	_http.request_completed.connect(_ao_receber_release, CONNECT_ONE_SHOT)
	var erro := _http.request(API, ["Accept: application/vnd.github+json", "User-Agent: CapMonster"])
	if erro != OK:
		_http.request_completed.disconnect(_ao_receber_release)
		verificacao_terminou.emit(false, {})


func _ao_receber_release(resultado: int, codigo: int, _cabecalhos: PackedStringArray, corpo: PackedByteArray) -> void:
	if resultado != HTTPRequest.RESULT_SUCCESS or codigo != 200:
		# Sem internet, repositório sem release ainda, GitHub fora do ar. Nada
		# disso é erro do jogador, então não vira aviso na cara dele.
		GameLog.info(GameLog.Channel.SYSTEM, "Atualizador: não consegui consultar as releases (código %d)." % codigo)
		verificacao_terminou.emit(false, {})
		return

	var dados: Variant = JSON.parse_string(corpo.get_string_from_utf8())
	if not (dados is Dictionary):
		verificacao_terminou.emit(false, {})
		return

	var release: Dictionary = dados
	var remota := String(release.get("tag_name", "")).lstrip("vV")
	var arquivos: Dictionary = {}
	for anexo in release.get("assets", []):
		arquivos[String(anexo.get("name", ""))] = String(anexo.get("browser_download_url", ""))

	if not arquivos.has(ARQUIVO_CONTEUDO):
		GameLog.warn(
			GameLog.Channel.SYSTEM,
			"Atualizador: a release %s não tem %s anexado." % [remota, ARQUIVO_CONTEUDO]
		)
		verificacao_terminou.emit(false, {})
		return

	ultima_info = {
		"versao": remota,
		"nome": String(release.get("name", remota)),
		"notas": String(release.get("body", "")).strip_edges(),
		"arquivos": arquivos,
	}

	var nova := comparar(remota, versao_local()) > 0
	GameLog.info(GameLog.Channel.SYSTEM, "Atualizador: local %s, GitHub %s%s." % [
		versao_local(), remota, "  (atualização disponível)" if nova else ""
	])
	verificacao_terminou.emit(nova, ultima_info)

	# `-- --atualizar-agora` dispensa o clique no botão. É como o caminho de
	# baixar-e-trocar é testado de verdade: sem isso só dava para conferir a
	# detecção, e a troca de arquivos é justamente a parte que pode dar errado.
	if nova and OS.is_debug_build() and OS.get_cmdline_user_args().has("--atualizar-agora"):
		aplicar()


## Compara "1.2.10" com "1.3.0" numericamente por parte.
##
## Comparar como texto diria que "1.10" < "1.9", que é justamente o caso em que
## um erro desses aparece: na décima correção.
static func comparar(a: String, b: String) -> int:
	var pa := a.split(".")
	var pb := b.split(".")
	for i in maxi(pa.size(), pb.size()):
		var na := int(pa[i]) if i < pa.size() else 0
		var nb := int(pb[i]) if i < pb.size() else 0
		if na != nb:
			return 1 if na > nb else -1
	return 0


# --- download -----------------------------------------------------------------

## Baixa os arquivos da última verificação e reinicia o jogo aplicando.
func aplicar() -> void:
	if ultima_info.is_empty():
		falhou.emit("Nenhuma atualização verificada.")
		return

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PASTA_TEMP))
	_baixados.clear()
	_baixando.clear()

	var arquivos: Dictionary = ultima_info.get("arquivos", {})
	for nome in [ARQUIVO_CONTEUDO, ARQUIVO_MOTOR]:
		if arquivos.has(nome):
			_baixando.append({"nome": nome, "url": String(arquivos[nome])})

	_proximo_download()


func _proximo_download() -> void:
	if _baixando.is_empty():
		_finalizar()
		return

	var item: Dictionary = _baixando.pop_front()
	var destino := PASTA_TEMP + String(item["nome"])
	_http.download_file = ProjectSettings.globalize_path(destino)
	_http.request_completed.connect(_ao_baixar.bind(String(item["nome"])), CONNECT_ONE_SHOT)

	var erro := _http.request(String(item["url"]), ["User-Agent: CapMonster"])
	if erro != OK:
		_http.request_completed.disconnect(_ao_baixar)
		falhou.emit("Não consegui começar o download de %s." % item["nome"])


func _ao_baixar(resultado: int, codigo: int, _c: PackedStringArray, _b: PackedByteArray, nome: String) -> void:
	_http.download_file = ""
	if resultado != HTTPRequest.RESULT_SUCCESS or codigo >= 400:
		falhou.emit("Falha ao baixar %s (código %d)." % [nome, codigo])
		return
	_baixados.append(nome)
	_proximo_download()


func _process(_delta: float) -> void:
	if _http != null and _http.download_file != "":
		progresso.emit(_http.get_downloaded_bytes(), _http.get_body_size())


func _finalizar() -> void:
	if _baixados.is_empty():
		falhou.emit("Nada foi baixado.")
		return
	if OS.has_feature("editor"):
		GameLog.info(GameLog.Channel.SYSTEM, "Atualizador: baixado, mas trocar arquivo só vale no jogo exportado.")
		falhou.emit("No editor a troca de arquivos não é aplicada.")
		return

	var script := _escrever_script()
	if script == "":
		falhou.emit("Não consegui preparar a troca dos arquivos.")
		return

	GameLog.info(GameLog.Channel.SYSTEM, "Atualizador: aplicando e reiniciando.")
	OS.create_process("cmd.exe", ["/c", script], false)
	get_tree().quit()


## Escreve o .bat que espera o jogo fechar, copia os arquivos e reabre.
##
## Três detalhes do Windows que este script tem que respeitar, todos aprendidos
## errando:
##
##  · **barra invertida.** `globalize_path` devolve `C:/Users/...`, e o `cmd` não
##    executa um .bat escrito com barra normal — ele lê o caminho como opção. O
##    script era escrito certinho e simplesmente não rodava;
##  · **`%~f0`, não `%%~f0`.** O `%%` só é escape dentro de bloco `for`; no
##    corpo do script ele sai literal e o arquivo nunca se apaga;
##  · **tentar de novo.** O jogo ainda está morrendo quando o script começa, e
##    enquanto o processo existe o Windows não deixa sobrescrever o .pck nem o
##    .exe. Uma espera fixa é aposta; repetir até conseguir é garantia.
func _escrever_script() -> String:
	var executavel := _windows(OS.get_executable_path())
	var pasta_jogo := _windows(OS.get_executable_path().get_base_dir())
	var origem := _windows(ProjectSettings.globalize_path(PASTA_TEMP).rstrip("/\\"))
	var caminho := _windows(ProjectSettings.globalize_path(PASTA_TEMP + "aplicar.bat"))

	var linhas: Array[String] = [
		"@echo off",
		"setlocal",
		'set "ORIGEM=%s"' % origem,
		'set "DESTINO=%s"' % pasta_jogo,
	]

	var indice := 0
	for nome in _baixados:
		indice += 1
		var rotulo := "copiar%d" % indice
		var pronto := "pronto%d" % indice
		linhas.append_array([
			"set TENTATIVA%d=0" % indice,
			":%s" % rotulo,
			"set /a TENTATIVA%d+=1" % indice,
			'copy /y "%%ORIGEM%%\\%s" "%%DESTINO%%\\%s" >nul 2>&1' % [nome, nome],
			"if not errorlevel 1 goto %s" % pronto,
			"ping 127.0.0.1 -n 2 >nul",
			"if %%TENTATIVA%d%% lss 30 goto %s" % [indice, rotulo],
			":%s" % pronto,
		])

	linhas.append('start "" "%s"' % executavel)
	linhas.append('del "%~f0"')

	var arquivo := FileAccess.open(PASTA_TEMP + "aplicar.bat", FileAccess.WRITE)
	if arquivo == null:
		return ""
	arquivo.store_string("\r\n".join(linhas) + "\r\n")
	arquivo.close()
	return caminho


static func _windows(caminho: String) -> String:
	return caminho.replace("/", "\\")
