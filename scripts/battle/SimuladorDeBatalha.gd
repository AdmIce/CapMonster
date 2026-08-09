class_name SimuladorDeBatalha
extends RefCounted
## Mede o equilíbrio do combate rodando muitas batalhas sem abrir o jogo.
##
##   godot --headless --path . --quit-after 400 -- --simular=300
##
## Mora em `scripts/` e nao em `tools/` de proposito: em `--script` os autoloads
## nao existem, e sem DataManager nao ha banco de dados nenhum para simular.
##
## Por que existe: o combate nunca foi ajustado com número. "Está difícil" e
## "está fácil" são impressões de quem jogou dez minutos com uma criatura, e
## dez minutos não distinguem uma zona injusta de uma sequência de azar. Aqui
## cada confronto roda centenas de vezes e sai uma taxa de vitória.
##
## O que é simulado: a troca de golpes básicos, que é o que decide a luta --
## ataque, defesa, elemento, crítico, variação e intervalo entre golpes, tudo
## pelas mesmas funções que o jogo usa. O que fica de fora: habilidades e itens,
## que o jogador escolhe. Ou seja, o número que sai é o **piso** -- com
## habilidade, o jogador vai melhor do que isto.

const RODADAS_PADRAO := 300
## Se a luta passa disto, é empate por cansaço: ninguém consegue matar ninguém.
const LIMITE_DE_SEGUNDOS := 180.0
const PASSO := 0.1

var _rng := RandomNumberGenerator.new()
## A criatura com que o jogador entra: a primeira inicial. É o pior caso do
## começo — quem já evoluiu vai melhor do que este número.
var _minha_especie: StringName = &""


## Roda tudo e imprime a tabela. Chamado pelo Boot com `-- --simular`.
func rodar(rodadas: int = RODADAS_PADRAO) -> void:
	_rng.seed = 20260809   # semente fixa: duas execuções dão o mesmo número

	var iniciais := DataManager.get_starters()
	if iniciais.is_empty():
		print("Sem criatura inicial definida; nada a simular.")
		return
	_minha_especie = (iniciais[0] as CreatureSpecies).id

	print("\n=== Equilíbrio do combate (%d batalhas por confronto) ===" % rodadas)
	print("Jogador leva %s no nível da zona, só no golpe básico (sem habilidade, sem item).\n" % String(_minha_especie))

	for id_do_mapa in DataManager.map_ids():
		var mapa := DataManager.get_map(id_do_mapa)
		var zonas: Array = mapa.get("zones", [])
		if zonas.is_empty():
			continue
		print("-- %s" % mapa.get("name", mapa.get("id", "?")))
		for zona in zonas:
			_medir_zona(zona, rodadas)
		print("")


func _medir_zona(zona: Dictionary, rodadas: int) -> void:
	var faixa: Array = zona.get("level_range", [1, 1])
	var nivel := int(round((float(faixa[0]) + float(faixa[-1])) * 0.5))

	# O jogador chega com a criatura no nível da zona: é o caso justo, e é o que
	# o jogo empurra ao subir de nível junto com o mapa.
	var linhas: Array = []
	for entrada in zona.get("table", []):
		var especie := StringName(String(entrada.get("species", "")))
		if DataManager.get_species(especie) == null:
			continue
		var resultado := _duelo(_minha_especie, especie, nivel, rodadas)
		linhas.append("     %-14s nv%-3d vitória %5.1f%%   %4.1f s   vida restante %4.1f%%" % [
			String(especie), nivel, resultado["vitorias"], resultado["segundos"], resultado["vida"]
		])
	print("   %s (nível %s)" % [zona.get("name", zona.get("id", "?")), nivel])
	for linha in linhas:
		print(linha)


## O jogador leva a criatura inicial dele contra a criatura selvagem da zona.
##
## Nao e o mesmo bicho dos dois lados, e a diferenca importa. O espelho parecia
## a medida justa, mas ele responde outra pergunta: no espelho, quem esta um
## golpe a frente vence com ~1/N da vida, sendo N o numero de golpes para matar.
## Com N perto de 10, sobrar 10% de vida e aritmetica, nao desequilibrio -- e
## baixar o dano aumenta N e deixa a luta **mais** apertada, o contrario do que
## se quer. O que diz se a zona e justa e o confronto real.
func _duelo(minha: StringName, especie: StringName, nivel: int, rodadas: int) -> Dictionary:
	var vitorias := 0
	var soma_segundos := 0.0
	var soma_vida := 0.0

	for i in rodadas:
		var meu: CreatureData = CreatureFactory.create(minha, nivel)
		var dele: CreatureData = CreatureFactory.create(especie, nivel)
		if meu == null or dele == null:
			return {"vitorias": 0.0, "segundos": 0.0, "vida": 0.0}

		var t := 0.0
		# Tipo explicito: `_dano` e um script carregado, entao o retorno chega como
		# Variant e o Godot 4 recusa inferir dele.
		var prox_meu := DamageCalculator.attack_interval(meu.speed())
		var prox_dele := DamageCalculator.attack_interval(dele.speed())

		while t < LIMITE_DE_SEGUNDOS and meu.is_alive() and dele.is_alive():
			t += PASSO
			# **Quem bate tem de estar vivo.** Sem esta checagem o golpe do morto
			# ainda sai: os dois batem no mesmo tique, morrem juntos e a luta nao
			# conta para ninguem. Deu 15-29% de vitoria num duelo espelhado, que
			# tem de dar 50 -- foi assim que o erro apareceu.
			if t >= prox_meu and meu.is_alive() and dele.is_alive():
				dele.apply_damage(_golpe(meu, dele))
				prox_meu = t + DamageCalculator.attack_interval(meu.speed())
			if t >= prox_dele and dele.is_alive() and meu.is_alive():
				meu.apply_damage(_golpe(dele, meu))
				prox_dele = t + DamageCalculator.attack_interval(dele.speed())

		if meu.is_alive() and not dele.is_alive():
			vitorias += 1
			soma_vida += meu.hp_ratio() * 100.0
		soma_segundos += t

	return {
		"vitorias": float(vitorias) / float(rodadas) * 100.0,
		"segundos": soma_segundos / float(rodadas),
		"vida": soma_vida / float(maxi(1, vitorias)),
	}


func _golpe(atacante: CreatureData, alvo: CreatureData) -> int:
	var resultado := DamageCalculator.compute(
		atacante.attack(),
		alvo.defense(),
		DamageCalculator.BASIC_ATTACK_POWER,
		atacante.element(),
		alvo.element(),
		_rng
	)
	return resultado.amount
