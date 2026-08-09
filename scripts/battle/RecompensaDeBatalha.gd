class_name RecompensaDeBatalha
extends RefCounted
## Quanto vale derrotar uma criatura.
##
## Existe para a conta ser **uma só**, feita nos dois lados. Antes o cliente
## calculava e mandava o número pronto, e o dono do mundo aplicava o que
## chegasse: um cliente alterado pedia um milhão de ouro e recebia um milhão de
## ouro, porque não havia com o que comparar.
##
## Agora o cliente manda o que derrotou — espécie e nível — e o dono refaz a
## conta com o banco de dados dele. Mentir sobre o número deixou de funcionar; o
## que ainda dá para mentir é sobre *ter* derrotado, e isso só fecha movendo a
## batalha inteira para o servidor. Mas o estrago fica limitado ao que a tabela
## do jogo permite, em vez de ser um campo livre.
##
## O limite de nível é o teto disso: ninguém derrota criatura acima do que os
## mapas geram, e sem ele bastaria pedir a recompensa de uma criatura nível
## 9999 para o problema voltar inteiro.
const NIVEL_MAXIMO := 100

## Quanto de XP do total vai para o jogador (o resto é das criaturas).
const FRACAO_DO_JOGADOR := 0.35

## Ouro por criatura: uma base mais um tanto por nível.
const OURO_BASE := 8
const OURO_POR_NIVEL := 4


## Recebe `[{"especie": "id", "nivel": 5}, ...]` e devolve
## `{"ouro": N, "xp_total": N, "xp_do_jogador": N}`.
##
## Espécie que não existe no banco de dados é ignorada em silêncio: vale zero, e
## quem pediu não ganha nada por inventar nome.
static func calcular(derrotados: Array) -> Dictionary:
	var ouro := 0
	var xp_total := 0

	for entrada in derrotados:
		if not (entrada is Dictionary):
			continue
		var especie := StringName(String((entrada as Dictionary).get("especie", "")))
		var nivel := clampi(int((entrada as Dictionary).get("nivel", 1)), 1, NIVEL_MAXIMO)
		if DataManager.get_species(especie) == null:
			continue

		var criatura := CreatureFactory.create(especie, nivel)
		if criatura == null:
			continue
		xp_total += CreatureFactory.xp_reward(criatura)
		ouro += OURO_BASE + nivel * OURO_POR_NIVEL

	return {
		"ouro": ouro,
		"xp_total": xp_total,
		"xp_do_jogador": maxi(1, int(round(float(xp_total) * FRACAO_DO_JOGADOR))) if xp_total > 0 else 0,
	}


## A lista que o cliente manda, montada a partir dos atores derrotados.
static func listar(derrotados: Array) -> Array:
	var lista: Array = []
	for dados in derrotados:
		if dados is CreatureData:
			lista.append({
				"especie": String((dados as CreatureData).species_id),
				"nivel": (dados as CreatureData).level,
			})
	return lista
