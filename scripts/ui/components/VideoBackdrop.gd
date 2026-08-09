class_name VideoBackdrop
extends Control
## Fundo de vídeo em laço para as telas cheias (título e criação de personagem).
##
## A Godot 4 só reproduz **Ogg Theora** (.ogv) de fábrica: MP4/H.264 não toca,
## nem com o arquivo dentro do projeto. Por isso o vídeo entra convertido em
## `assets/video/` e este nó só o procura lá.
##
## Se o arquivo não existir, o nó não faz nada e a tela fica com o fundo liso de
## antes — o menu não pode depender de um asset opcional para abrir.
##
## Por cima do vídeo vai sempre um véu escuro: o vídeo é cenário, e sem ele o
## texto do menu ficaria disputando contraste com um céu que muda de cor.

const PASTA := "res://assets/video/"

## Quanto do vídeo o véu apaga. Menos que isto e o título some no céu claro.
const VEU := 0.62

var _player: VideoStreamPlayer = null


## `nome` sem extensão. Devolve o nó mesmo quando o vídeo não existe, para quem
## chamou não precisar testar nulo.
static func criar(nome: String) -> VideoBackdrop:
	var node := VideoBackdrop.new()
	node.set_anchors_preset(Control.PRESET_FULL_RECT)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node._montar(nome)
	return node


func _montar(nome: String) -> void:
	var caminho := PASTA + nome + ".ogv"
	if not ResourceLoader.exists(caminho):
		GameLog.info(GameLog.Channel.UI, "Sem vídeo de fundo em %s; usando o fundo liso." % caminho)
		return

	_player = VideoStreamPlayer.new()
	_player.stream = load(caminho)
	_player.set_anchors_preset(Control.PRESET_FULL_RECT)
	_player.expand = true
	# Sem som: a trilha do menu é do AudioManager, e duas fontes brigando é ruído.
	_player.volume_db = -80.0
	_player.autoplay = true
	_player.loop = true
	_player.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_player)

	var veu := ColorRect.new()
	veu.color = Color(0.03, 0.04, 0.06, VEU)
	veu.set_anchors_preset(Control.PRESET_FULL_RECT)
	veu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(veu)


func tocando() -> bool:
	return _player != null and _player.is_playing()
