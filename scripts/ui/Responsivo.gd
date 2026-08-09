class_name Responsivo
extends Node
## Faz a interface caber em qualquer tamanho de janela.
##
## O projeto usa stretch `canvas_items` com aspecto `expand`: janela menor não
## encolhe a interface, ela dá **menos espaço lógico**. Ou seja, todo tamanho
## mínimo escrito à mão em pixel ("este cartão tem 860 de largura") vira conteúdo
## cortado assim que alguém reduz a janela ou joga em 1366x768.
##
## Em vez de espalhar conta de viewport por dez telas, quem precisa de um tamanho
## "de projeto" registra aqui: o mínimo pedido nunca passa de uma fração da tela
## e é recalculado quando a janela muda.
##
## Uso só em nós de vida longa (os painéis, criados uma vez). Para conteúdo que é
## redesenhado a cada abertura — cartões, grades — use `colunas()` e `escala()`
## na hora de desenhar, que leem o tamanho atual sem precisar de sinal.

## Resolução de referência: é para ela que os números das telas foram escritos.
const BASE := Vector2(1280.0, 720.0)

## Abaixo disto a interface não tem mais como se reorganizar, só encolher fonte.
## O jogo trava o tamanho da janela aqui para não existir estado quebrado.
const MIN_JANELA := Vector2i(1024, 640)


## Escala da interface escolhida pelo jogador. Abaixo de 0.7 os textos ficam
## ilegíveis; acima de 1.25 os painéis não cabem mais na tela de projeto.
const ESCALA_MIN := 0.7
const ESCALA_MAX := 1.25
const CHAVE_ESCALA := "escala_interface"


## Aplica a escala da interface na janela.
##
## `content_scale_factor` é o botão certo para isto: com o stretch em
## `canvas_items`, baixar o fator aumenta o espaço lógico disponível — ou seja, a
## interface encolhe e sobra mais mundo — **sem** mexer na resolução do 3D. Mudar
## tamanho de fonte painel por painel daria o mesmo efeito visual e quebraria
## todos os tamanhos mínimos escritos até aqui.
static func aplicar_escala(node: Node, valor: float) -> void:
	var janela := node.get_window() if node != null else null
	if janela == null:
		return
	janela.content_scale_factor = clampf(valor, ESCALA_MIN, ESCALA_MAX)


static func escala_salva() -> float:
	return clampf(float(SaveManager.get_setting(CHAVE_ESCALA, 1.0)), ESCALA_MIN, ESCALA_MAX)


## Tamanho lógico atual da viewport (já com o stretch aplicado).
static func tela(node: Node) -> Vector2:
	if node == null or not node.is_inside_tree():
		return BASE
	var vp := node.get_viewport()
	if vp == null:
		return BASE
	var tamanho := vp.get_visible_rect().size
	return tamanho if tamanho.x > 1.0 and tamanho.y > 1.0 else BASE


## 1.0 na resolução de referência, menor em janela apertada. Nunca passa de 1:
## em tela grande a interface fica do mesmo tamanho e sobra mundo, que é o
## sentido do aspecto `expand`.
static func escala(node: Node) -> float:
	var t := tela(node)
	return clampf(minf(t.x / BASE.x, t.y / BASE.y), 0.62, 1.0)


## Quantos cartões de `largura_card` cabem em `disponivel`, respeitando o
## espaçamento entre eles. Sempre pelo menos 1 — grade com 0 coluna trava.
static func colunas(disponivel: float, largura_card: float, separacao: float, maximo: int = 6) -> int:
	if largura_card <= 0.0:
		return 1
	var cabem := int(floor((disponivel + separacao) / (largura_card + separacao)))
	return clampi(cabem, 1, maxi(1, maximo))


## Fixa a largura mínima de um painel sem deixar que ela estoure a tela.
static func largura(node: Control, desejada: float, fracao: float = 0.92) -> void:
	caixa(node, Vector2(desejada, node.custom_minimum_size.y), Vector2(fracao, 1.0))


## Idem para os dois eixos. `fracao` é quanto da tela o painel pode ocupar, no
## máximo: 0.9 deixa uma borda visível do mundo em volta, que é o que faz a tela
## parecer um painel e não uma troca de cena.
##
## O vigia entra como **filho** do painel de propósito. Ligar o `size_changed` do
## viewport a um Callable estático com o painel embutido mantinha o painel vivo
## para sempre (era o "ObjectDB instances leaked at exit" no fim de cada partida);
## sendo um nó filho, ele morre junto e o Godot desfaz a ligação sozinho.
static func caixa(node: Control, desejada: Vector2, fracao: Vector2 = Vector2(0.92, 0.9)) -> void:
	var vigia := Responsivo.new()
	vigia.name = "Responsivo"
	vigia._alvo = node
	vigia._desejada = desejada
	vigia._fracao = fracao
	node.add_child(vigia)


var _alvo: Control = null
var _desejada := Vector2.ZERO
var _fracao := Vector2.ONE


func _ready() -> void:
	get_viewport().size_changed.connect(_aplicar)
	_aplicar()


func _aplicar() -> void:
	if _alvo == null or not is_instance_valid(_alvo):
		return
	var t := tela(self)
	_alvo.custom_minimum_size = Vector2(
		minf(_desejada.x, t.x * _fracao.x) if _desejada.x > 0.0 else 0.0,
		minf(_desejada.y, t.y * _fracao.y) if _desejada.y > 0.0 else 0.0
	)


## Envolve um conteúdo numa rolagem vertical que ocupa o espaço que sobrar.
##
## É o remédio para o corte silencioso: painel com conteúdo mais alto que a
## janela simplesmente sumia com o final (as habilidades da criatura, os botões
## de evoluir). Com rolagem, encolher a janela custa um scroll, não conteúdo.
static func rolagem(conteudo: Control) -> ScrollContainer:
	var caixa_rolagem := ScrollContainer.new()
	caixa_rolagem.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	caixa_rolagem.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	caixa_rolagem.size_flags_vertical = Control.SIZE_EXPAND_FILL
	conteudo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	caixa_rolagem.add_child(conteudo)
	return caixa_rolagem
