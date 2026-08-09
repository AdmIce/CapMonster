extends Node
## Autoload: AudioManager
##
## Três barramentos (BGM, SFX, UI) pendurados no Master, criados em código para
## não depender de um default_bus_layout.tres que ninguém lembra de versionar.
##
## Os sons atuais vêm do Starter Kit do Kenney (CC0) e são **placeholders**: são
## efeitos de city builder reaproveitados. O que importa aqui é a arquitetura -
## trocar por som definitivo é editar o dicionário BIBLIOTECA, nada mais.
##
## Quem toca som nunca carrega arquivo: pede por nome lógico
## (AudioManager.tocar(&"golpe")), então trocar o arquivo não mexe em quem chama.

const PASTA := "res://assets/audio/"

## nome lógico -> lista de arquivos (sorteia entre eles, evita repetição robótica)
const BIBLIOTECA := {
	&"golpe": ["placement-a.ogg", "placement-b.ogg", "placement-c.ogg", "placement-d.ogg"],
	&"abate": ["removal-a.ogg", "removal-b.ogg", "removal-c.ogg"],
	&"critico": ["removal-d.ogg"],
	&"ui_clique": ["rotate.ogg"],
	&"ui_alternar": ["toggle.ogg"],
	&"captura_sucesso": ["toggle.ogg"],
	&"captura_falha": ["removal-b.ogg"],
	&"nivel": ["rotate.ogg"],
	&"vitoria": ["toggle.ogg"],
	&"cura": ["placement-a.ogg"],
}

## Ajustes por som, já que a origem é toda de um kit de city builder.
const AJUSTES := {
	&"golpe": { "tom": 1.0, "volume": -6.0 },
	&"abate": { "tom": 0.82, "volume": -3.0 },
	&"critico": { "tom": 1.25, "volume": -1.0 },
	&"captura_sucesso": { "tom": 1.35, "volume": 0.0 },
	&"captura_falha": { "tom": 0.75, "volume": -4.0 },
	&"nivel": { "tom": 1.5, "volume": -2.0 },
	&"vitoria": { "tom": 1.15, "volume": 0.0 },
	&"cura": { "tom": 1.4, "volume": -8.0 },
}

const AMBIENTE := "ambience.ogg"
const VOZES_SFX := 10

var _bus_bgm: int = 0
var _bus_sfx: int = 0
var _bus_ui: int = 0

var _tocador_bgm: AudioStreamPlayer = null
var _vozes: Array[AudioStreamPlayer] = []
var _proxima_voz: int = 0
var _cache: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _faltando_avisado: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_criar_barramentos()

	_tocador_bgm = AudioStreamPlayer.new()
	_tocador_bgm.bus = "BGM"
	add_child(_tocador_bgm)

	for i in VOZES_SFX:
		var voz := AudioStreamPlayer.new()
		voz.bus = "SFX"
		add_child(voz)
		_vozes.append(voz)

	aplicar_volumes()


func _criar_barramentos() -> void:
	for nome in ["BGM", "SFX", "UI"]:
		if AudioServer.get_bus_index(nome) != -1:
			continue
		var indice := AudioServer.bus_count
		AudioServer.add_bus(indice)
		AudioServer.set_bus_name(indice, nome)
		AudioServer.set_bus_send(indice, "Master")
	_bus_bgm = AudioServer.get_bus_index("BGM")
	_bus_sfx = AudioServer.get_bus_index("SFX")
	_bus_ui = AudioServer.get_bus_index("UI")


## Relê os volumes das configurações. Chamado pelo painel de configurações.
func aplicar_volumes() -> void:
	_definir(0, float(SaveManager.get_setting("master_volume", 0.8)))
	_definir(_bus_bgm, float(SaveManager.get_setting("bgm_volume", 0.5)))
	_definir(_bus_sfx, float(SaveManager.get_setting("sfx_volume", 0.8)))
	_definir(_bus_ui, float(SaveManager.get_setting("sfx_volume", 0.8)))


static func _definir(bus: int, valor: float) -> void:
	if bus < 0:
		return
	var v := clampf(valor, 0.0, 1.0)
	AudioServer.set_bus_mute(bus, v <= 0.001)
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(0.001, v)))


# --- reprodução ---------------------------------------------------------------

func tocar(nome: StringName) -> void:
	var stream := _sortear(nome)
	if stream == null:
		return
	var voz := _vozes[_proxima_voz]
	_proxima_voz = (_proxima_voz + 1) % _vozes.size()

	var ajuste: Dictionary = AJUSTES.get(nome, {})
	voz.stream = stream
	voz.pitch_scale = float(ajuste.get("tom", 1.0)) * _rng.randf_range(0.94, 1.06)
	voz.volume_db = float(ajuste.get("volume", -4.0))
	voz.play()


func tocar_ui(nome: StringName) -> void:
	tocar(nome)


## Ambiente do mapa. Toca em laço; chamar de novo com o mesmo arquivo não
## reinicia (senão trocar de tela cortaria a trilha).
func tocar_ambiente(arquivo: String = AMBIENTE) -> void:
	var stream := _carregar(arquivo)
	if stream == null:
		return
	if _tocador_bgm.stream == stream and _tocador_bgm.playing:
		return
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	_tocador_bgm.stream = stream
	_tocador_bgm.volume_db = -10.0
	_tocador_bgm.play()


func parar_ambiente() -> void:
	_tocador_bgm.stop()


func _sortear(nome: StringName) -> AudioStream:
	var lista: Array = BIBLIOTECA.get(nome, [])
	if lista.is_empty():
		return null
	return _carregar(String(lista[_rng.randi_range(0, lista.size() - 1)]))


func _carregar(arquivo: String) -> AudioStream:
	if _cache.has(arquivo):
		return _cache[arquivo]
	var caminho := PASTA + arquivo
	if not ResourceLoader.exists(caminho):
		if not _faltando_avisado.has(arquivo):
			_faltando_avisado[arquivo] = true
			GameLog.warn(GameLog.Channel.SYSTEM, "Áudio ausente: %s" % caminho)
		_cache[arquivo] = null
		return null
	var stream: AudioStream = load(caminho)
	_cache[arquivo] = stream
	return stream
