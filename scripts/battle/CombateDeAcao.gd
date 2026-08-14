class_name CombateDeAcao
extends RefCounted
## As contas do combate em tempo real.
##
## Fica separado do jogador e do monstro de propósito: os dois batem um no
## outro, e a regra de quanto dói é a mesma nos dois sentidos. Com a conta
## dentro de cada um, ela viraria duas contas que divergem na primeira mexida.
##
## Reaproveita o `DamageCalculator` que o combate por turnos usava — a fórmula
## de ataque contra defesa continua valendo; o que mudou é **quando** ela roda:
## antes era num turno, agora é no golpe.

## Alcance do golpe corpo a corpo, em metros. Medido contra o personagem de
## 1,87 m: 2,4 acerta quem está encostado e quem está um passo à frente, sem
## acertar quem já saiu de perto.
const ALCANCE := 2.4

## Quanto o alvo pode estar fora da mira e ainda ser acertado, em graus para
## cada lado. Um cone estreito demais faz o jogador errar coisa que está
## visivelmente na frente dele, e isso lê como bug, não como perícia.
const ABERTURA_GRAUS := 70.0

## Segundos entre um golpe e outro. É o que separa "combate" de "segurar o
## botão": sem espera, o dano por segundo vira a taxa de quadros da máquina.
const ESPERA_ENTRE_GOLPES := 0.55

## Potência do golpe básico, na escala que o DamageCalculator espera.
const FORCA_DO_GOLPE := 1.0


## Alvos ao alcance e dentro do cone, do mais próximo para o mais distante.
##
## Ordenado porque o golpe acerta **um** alvo: acertar todos de uma vez faria
## um grupo de monstros ser mais fácil que um sozinho, que é o contrário do que
## se espera.
static func alvos_na_frente(quem: Node3D, candidatos: Array) -> Array:
	var origem := quem.global_position
	var frente := -quem.global_transform.basis.z
	var encontrados: Array = []

	for alvo in candidatos:
		if alvo == null or not is_instance_valid(alvo):
			continue
		if not (alvo is Node3D):
			continue

		var ate: Vector3 = (alvo as Node3D).global_position - origem
		ate.y = 0.0
		var distancia := ate.length()
		if distancia > ALCANCE or distancia < 0.001:
			continue
		if rad_to_deg(frente.angle_to(ate.normalized())) > ABERTURA_GRAUS:
			continue
		encontrados.append({"alvo": alvo, "distancia": distancia})

	encontrados.sort_custom(func(a, b): return a["distancia"] < b["distancia"])

	var lista: Array = []
	for entrada in encontrados:
		lista.append(entrada["alvo"])
	return lista


## Dano de um golpe, com a variação e o crítico que o resto do jogo já usa.
static func golpe(ataque: int, defesa: int, elemento_de: String = "", elemento_para: String = "") -> DamageCalculator.Resultado:
	return DamageCalculator.compute(ataque, defesa, FORCA_DO_GOLPE, elemento_de, elemento_para)
