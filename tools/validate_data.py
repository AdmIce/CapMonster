#!/usr/bin/env python3
"""Validate the JSON game database in /data.

Catches the mistakes that are expensive to find at runtime: broken cross
references (a creature pointing at a skill that does not exist), spawn tables
referencing unknown species, gates pointing at unknown maps, evolutions that
loop, spawn_maps that disagree with the zone tables, and so on.

Usage:
    python tools/validate_data.py
    python tools/validate_data.py --data path/to/data

Exit code 0 = clean, 1 = at least one error.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

HEX_RE = re.compile(r"^#[0-9A-Fa-f]{6}$")

VALID_BODIES = {"quadruped", "biped", "floating", "serpent", "avian", "hulk"}
VALID_FEATURES = {"horns", "tail", "wings", "crest", "gem", "plates", "mane", "orbs"}
VALID_SKILL_KINDS = {"damage", "heal", "buff", "debuff"}
VALID_SKILL_TARGETS = {"enemy_single", "enemy_all", "ally_lowest", "ally_all", "self"}
VALID_ITEM_CATEGORIES = {"capture", "consumable", "material", "pet", "quest"}
VALID_TERRAIN = {"grass", "path", "water", "rock", "sand", "ash", "lava"}
VALID_SCATTER = {"tree", "bush", "rock", "reed", "stump", "crystal", "ashtree", "vent"}
VALID_LANDMARKS = {"hut", "signpost", "ruin_wall", "arch", "banner", "pillar", "campfire"}
VALID_ROLES = {"offense", "defense", "speed", "support"}


class Report:
    def __init__(self) -> None:
        self.errors: list[str] = []
        self.warnings: list[str] = []

    def error(self, msg: str) -> None:
        self.errors.append(msg)

    def warn(self, msg: str) -> None:
        self.warnings.append(msg)

    def ok(self) -> bool:
        return not self.errors


def load(data_dir: Path, name: str, report: Report):
    path = data_dir / name
    if not path.exists():
        report.error(f"{name}: file is missing")
        return None
    try:
        with path.open(encoding="utf-8") as fh:
            return json.load(fh)
    except json.JSONDecodeError as exc:
        report.error(f"{name}: invalid JSON at line {exc.lineno} col {exc.colno}: {exc.msg}")
        return None


def check_color(report: Report, where: str, value) -> None:
    if not isinstance(value, str) or not HEX_RE.match(value):
        report.error(f"{where}: '{value}' is not a #RRGGBB colour")


def validate_elements(doc, report: Report) -> set[str]:
    ids: set[str] = set()
    for el in doc.get("elements", []):
        eid = el.get("id")
        if not eid:
            report.error("elements.json: element without id")
            continue
        if eid in ids:
            report.error(f"elements.json: duplicate element '{eid}'")
        ids.add(eid)
        check_color(report, f"elements.json/{eid}.color", el.get("color"))

    chart = doc.get("chart", {})
    for attacker, row in chart.items():
        if attacker not in ids:
            report.error(f"elements.json: chart row '{attacker}' is not a declared element")
        for defender, mult in row.items():
            if defender not in ids:
                report.error(f"elements.json: chart {attacker} -> unknown element '{defender}'")
            if not isinstance(mult, (int, float)) or mult <= 0:
                report.error(f"elements.json: chart {attacker}->{defender} multiplier must be > 0")

    # Reciprocity: if A is strong against B, B should not also be strong against A,
    # unless the pair is declared as an intentional mutual rivalry.
    mutual = {frozenset(pair) for pair in doc.get("intentional_mutual_pairs", [])}
    for attacker, row in chart.items():
        for defender, mult in row.items():
            if attacker == defender or frozenset((attacker, defender)) in mutual:
                continue
            back = chart.get(defender, {}).get(attacker)
            if mult > 1.0 and back is not None and back > 1.0:
                report.warn(f"elements.json: {attacker} and {defender} are both strong against each other")
    return ids


def validate_rarities(doc, report: Report) -> set[str]:
    ids: set[str] = set()
    orders: set[int] = set()
    for r in doc.get("rarities", []):
        rid = r.get("id")
        if not rid:
            report.error("rarities.json: rarity without id")
            continue
        if rid in ids:
            report.error(f"rarities.json: duplicate rarity '{rid}'")
        ids.add(rid)
        order = r.get("order")
        if not isinstance(order, int):
            report.error(f"rarities.json/{rid}: 'order' must be an int")
        elif order in orders:
            report.error(f"rarities.json/{rid}: duplicate order {order}")
        else:
            orders.add(order)
        check_color(report, f"rarities.json/{rid}.color", r.get("color"))
        for key in ("stat_multiplier", "capture_modifier", "spawn_weight_modifier"):
            if not isinstance(r.get(key), (int, float)):
                report.error(f"rarities.json/{rid}: missing numeric '{key}'")
    return ids


def validate_skills(doc, elements: set[str], report: Report) -> set[str]:
    ids: set[str] = set()
    for s in doc.get("skills", []):
        sid = s.get("id")
        if not sid:
            report.error("skills.json: skill without id")
            continue
        if sid in ids:
            report.error(f"skills.json: duplicate skill '{sid}'")
        ids.add(sid)
        if s.get("element") not in elements:
            report.error(f"skills.json/{sid}: unknown element '{s.get('element')}'")
        if s.get("kind") not in VALID_SKILL_KINDS:
            report.error(f"skills.json/{sid}: kind must be one of {sorted(VALID_SKILL_KINDS)}")
        if s.get("target") not in VALID_SKILL_TARGETS:
            report.error(f"skills.json/{sid}: target must be one of {sorted(VALID_SKILL_TARGETS)}")
        if not isinstance(s.get("cooldown"), (int, float)) or s["cooldown"] <= 0:
            report.error(f"skills.json/{sid}: cooldown must be > 0")
        if s.get("kind") == "damage" and not s.get("power"):
            report.error(f"skills.json/{sid}: damage skill needs a non-zero power")
        if s.get("kind") in ("buff", "debuff"):
            if "stat" not in s or "stat_change" not in s or "duration" not in s:
                report.error(f"skills.json/{sid}: buff/debuff needs stat, stat_change and duration")
    return ids


def validate_creatures(doc, elements, rarities, skills, report: Report) -> dict:
    species: dict = {}
    for c in doc.get("creatures", []):
        cid = c.get("id")
        if not cid:
            report.error("creatures.json: creature without id")
            continue
        if cid in species:
            report.error(f"creatures.json: duplicate creature '{cid}'")
        species[cid] = c

        if c.get("element") not in elements:
            report.error(f"creatures.json/{cid}: unknown element '{c.get('element')}'")
        if c.get("rarity") not in rarities:
            report.error(f"creatures.json/{cid}: unknown rarity '{c.get('rarity')}'")
        if c.get("role") not in VALID_ROLES:
            report.error(f"creatures.json/{cid}: role must be one of {sorted(VALID_ROLES)}")

        stats = c.get("base_stats", {})
        for key in ("hp", "attack", "defense", "speed"):
            if not isinstance(stats.get(key), (int, float)) or stats[key] <= 0:
                report.error(f"creatures.json/{cid}: base_stats.{key} must be > 0")

        creature_skills = c.get("skills", [])
        if len(creature_skills) < 2:
            report.error(f"creatures.json/{cid}: needs a primary and a secondary skill")
        for sid in creature_skills:
            if sid not in skills:
                report.error(f"creatures.json/{cid}: unknown skill '{sid}'")

        rate = c.get("capture_rate")
        if not isinstance(rate, (int, float)) or not (0.0 <= rate <= 1.0):
            report.error(f"creatures.json/{cid}: capture_rate must be within 0..1")
        if c.get("capturable") and rate == 0.0:
            report.error(f"creatures.json/{cid}: marked capturable but capture_rate is 0")
        if not c.get("capturable") and rate > 0.0:
            report.warn(f"creatures.json/{cid}: capture_rate > 0 on a non-capturable species")

        vis = c.get("visual", {})
        if vis.get("body") not in VALID_BODIES:
            report.error(f"creatures.json/{cid}: visual.body must be one of {sorted(VALID_BODIES)}")
        for key in ("primary", "secondary", "accent"):
            check_color(report, f"creatures.json/{cid}.visual.{key}", vis.get(key))
        for feat in vis.get("features", []):
            if feat not in VALID_FEATURES:
                report.error(f"creatures.json/{cid}: unknown visual feature '{feat}'")

    # Evolutions resolve, do not self-loop, and do not form cycles.
    for cid, c in species.items():
        evo = c.get("evolution")
        if not evo:
            continue
        target = evo.get("to")
        if target not in species:
            report.error(f"creatures.json/{cid}: evolves into unknown species '{target}'")
            continue
        if target == cid:
            report.error(f"creatures.json/{cid}: evolves into itself")
        if not isinstance(evo.get("level"), int) or evo["level"] < 2:
            report.error(f"creatures.json/{cid}: evolution.level must be an int >= 2")
        seen = {cid}
        cursor = target
        while cursor:
            if cursor in seen:
                report.error(f"creatures.json/{cid}: evolution chain loops at '{cursor}'")
                break
            seen.add(cursor)
            nxt = species.get(cursor, {}).get("evolution")
            cursor = nxt.get("to") if nxt else None

    starters = [c for c in species.values() if c.get("starter")]
    if len(starters) != 3:
        report.error(f"creatures.json: expected exactly 3 starters, found {len(starters)}")
    else:
        roles = {c.get("role") for c in starters}
        if len(roles) != 3:
            report.warn(f"creatures.json: starters should cover three distinct roles, got {sorted(roles)}")

    return species


def validate_items(doc, report: Report) -> dict:
    """Returns id -> item, so callers can price shop stock."""
    ids: dict = {}
    for i in doc.get("items", []):
        iid = i.get("id")
        if not iid:
            report.error("items.json: item without id")
            continue
        if iid in ids:
            report.error(f"items.json: duplicate item '{iid}'")
        ids[iid] = i
        if i.get("category") not in VALID_ITEM_CATEGORIES:
            report.error(f"items.json/{iid}: category must be one of {sorted(VALID_ITEM_CATEGORIES)}")
        check_color(report, f"items.json/{iid}.color", i.get("color"))
        if i.get("category") == "capture" and not isinstance(i.get("capture_power"), (int, float)):
            report.error(f"items.json/{iid}: capture item needs numeric 'capture_power'")
    for iid in doc.get("starting_inventory", {}):
        if iid not in ids:
            report.error(f"items.json: starting_inventory references unknown item '{iid}'")
    return ids


def _validate_tilemap(m, mid: str, report: Report) -> None:
    """Checks the ASCII tile map: every symbol has a legend entry and every
    referenced .glb actually exists on disk."""
    tilemap = m.get("tilemap")
    if not tilemap:
        return

    rows = tilemap.get("rows", [])
    if not rows:
        report.error(f"maps.json/{mid}/tilemap: 'rows' is empty")
        return

    largura = len(rows[0])
    for i, linha in enumerate(rows):
        if len(linha) != largura:
            report.error(
                f"maps.json/{mid}/tilemap: row {i} has {len(linha)} chars, expected {largura}"
            )

    legend = tilemap.get("legend", {})
    model_dir = tilemap.get("model_dir", "res://assets/models/city/")
    raiz = Path(__file__).resolve().parent.parent
    pasta = raiz / model_dir.replace("res://", "")

    usados = set()
    for linha in rows:
        for simbolo in linha:
            if simbolo == " ":
                continue
            if simbolo not in legend:
                report.error(f"maps.json/{mid}/tilemap: symbol '{simbolo}' has no legend entry")
            else:
                usados.add(simbolo)

    for simbolo, definicao in legend.items():
        nome = definicao.get("model", "")
        if not nome:
            report.error(f"maps.json/{mid}/tilemap: legend '{simbolo}' has no model")
            continue
        if not (pasta / f"{nome}.glb").exists():
            report.error(f"maps.json/{mid}/tilemap: model '{nome}.glb' not found in {model_dir}")
        if simbolo not in usados:
            report.warn(f"maps.json/{mid}/tilemap: legend '{simbolo}' is never used")

    if tilemap.get("step", 0) <= 0 or tilemap.get("scale", 0) <= 0:
        report.error(f"maps.json/{mid}/tilemap: step and scale must be > 0")


def rect_inside(rect, bounds) -> bool:
    x1, z1, x2, z2 = rect
    return (
        bounds["min_x"] <= min(x1, x2)
        and max(x1, x2) <= bounds["max_x"]
        and bounds["min_z"] <= min(z1, z2)
        and max(z1, z2) <= bounds["max_z"]
    )


def validate_maps(doc, species, items, report: Report) -> dict:
    maps: dict = {}
    referenced_species: dict[str, set[str]] = {}

    for m in doc.get("maps", []):
        mid = m.get("id")
        if not mid:
            report.error("maps.json: map without id")
            continue
        if mid in maps:
            report.error(f"maps.json: duplicate map '{mid}'")
        maps[mid] = m
        referenced_species[mid] = set()

        bounds = m.get("bounds")
        if not bounds or any(k not in bounds for k in ("min_x", "max_x", "min_z", "max_z")):
            report.error(f"maps.json/{mid}: bounds must define min_x, max_x, min_z, max_z")
            continue
        if bounds["min_x"] >= bounds["max_x"] or bounds["min_z"] >= bounds["max_z"]:
            report.error(f"maps.json/{mid}: bounds are inverted or empty")

        def check_pos(where, pos):
            if not (isinstance(pos, list) and len(pos) == 2):
                report.error(f"maps.json/{mid}/{where}: pos must be [x, z]")
                return
            if not (bounds["min_x"] <= pos[0] <= bounds["max_x"] and bounds["min_z"] <= pos[1] <= bounds["max_z"]):
                report.error(f"maps.json/{mid}/{where}: pos {pos} is outside the map bounds")

        for name, pos in m.get("spawn_points", {}).items():
            check_pos(f"spawn_points.{name}", pos)
        if "start" not in m.get("spawn_points", {}):
            report.error(f"maps.json/{mid}: missing the 'start' spawn point")

        for t in m.get("terrain", []):
            if t.get("kind") not in VALID_TERRAIN:
                report.error(f"maps.json/{mid}: terrain kind '{t.get('kind')}' is not supported")
            check_color(report, f"maps.json/{mid}.terrain.color", t.get("color"))
            if not rect_inside(t.get("rect", [0, 0, 0, 0]), bounds):
                report.warn(f"maps.json/{mid}: terrain rect {t.get('rect')} spills outside bounds")

        for s in m.get("scatter", []):
            if s.get("kind") not in VALID_SCATTER:
                report.error(f"maps.json/{mid}: scatter kind '{s.get('kind')}' is not supported")
            check_color(report, f"maps.json/{mid}.scatter.color", s.get("color"))
            if not isinstance(s.get("count"), int) or s["count"] <= 0:
                report.error(f"maps.json/{mid}: scatter '{s.get('kind')}' needs a positive count")
            if not isinstance(s.get("seed"), int):
                report.error(f"maps.json/{mid}: scatter '{s.get('kind')}' needs an int seed (determinism)")

        for l in m.get("landmarks", []):
            if l.get("kind") not in VALID_LANDMARKS:
                report.error(f"maps.json/{mid}: landmark kind '{l.get('kind')}' is not supported")
            check_pos(f"landmark.{l.get('kind')}", l.get("pos"))

        npc_ids = set()
        for n in m.get("npcs", []):
            nid = n.get("id")
            if nid in npc_ids:
                report.error(f"maps.json/{mid}: duplicate npc id '{nid}'")
            npc_ids.add(nid)
            check_pos(f"npc.{nid}", n.get("pos"))
            if not n.get("lines"):
                report.error(f"maps.json/{mid}/npc.{nid}: needs at least one dialogue line")

            loja = n.get("shop")
            if loja:
                if not loja.get("vende"):
                    report.error(f"maps.json/{mid}/npc.{nid}: shop with an empty 'vende' list")
                for item_id in loja.get("vende", []):
                    if item_id not in items:
                        report.error(f"maps.json/{mid}/npc.{nid}: shop sells unknown item '{item_id}'")
                    elif int(items[item_id].get("value", 0)) <= 0:
                        report.error(
                            f"maps.json/{mid}/npc.{nid}: '{item_id}' has value 0 and cannot be priced"
                        )
                margem = loja.get("margem_venda", 0.4)
                if not isinstance(margem, (int, float)) or not (0.0 < margem <= 1.0):
                    report.error(f"maps.json/{mid}/npc.{nid}: 'margem_venda' must be within 0..1")
            for key in ("skin", "hair", "outfit", "trim"):
                check_color(report, f"maps.json/{mid}/npc.{nid}.colors.{key}", n.get("colors", {}).get(key))

        for h in m.get("heal_points", []):
            check_pos(f"heal_point.{h.get('id')}", h.get("pos"))

        for z in m.get("zones", []):
            zid = z.get("id")
            check_rect = z.get("rect", [0, 0, 0, 0])
            if not rect_inside(check_rect, bounds):
                report.error(f"maps.json/{mid}/zone.{zid}: rect {check_rect} is outside the map bounds")
            lo, hi = z.get("level_range", [0, 0])
            if lo < 1 or hi < lo:
                report.error(f"maps.json/{mid}/zone.{zid}: bad level_range {z.get('level_range')}")
            if not isinstance(z.get("max_alive"), int) or z["max_alive"] < 1:
                report.error(f"maps.json/{mid}/zone.{zid}: max_alive must be >= 1")
            total = 0
            for row in z.get("table", []):
                sid = row.get("species")
                if sid not in species:
                    report.error(f"maps.json/{mid}/zone.{zid}: unknown species '{sid}'")
                    continue
                if not species[sid].get("obtainable", True):
                    report.error(f"maps.json/{mid}/zone.{zid}: '{sid}' is flagged non-obtainable but spawns in the wild")
                referenced_species[mid].add(sid)
                total += row.get("weight", 0)
            if total <= 0:
                report.error(f"maps.json/{mid}/zone.{zid}: spawn table weights must sum to > 0")

        _validate_tilemap(m, mid, report)

        # Mapas seguros (vila, hub) não têm chefe. Só é erro faltar chefe num
        # mapa que tem zona de encontro.
        for encounter_key in ("mini_boss", "boss"):
            enc = m.get(encounter_key)
            if not enc:
                if m.get("zones"):
                    report.error(f"maps.json/{mid}: missing '{encounter_key}'")
                continue
            sid = enc.get("species")
            if sid not in species:
                report.error(f"maps.json/{mid}/{encounter_key}: unknown species '{sid}'")
            elif species[sid].get("capturable"):
                report.error(f"maps.json/{mid}/{encounter_key}: boss species '{sid}' must not be capturable")
            check_pos(encounter_key, enc.get("pos"))
            for esc in enc.get("escorts", []):
                if esc.get("species") not in species:
                    report.error(f"maps.json/{mid}/{encounter_key}: unknown escort '{esc.get('species')}'")
            for iid in enc.get("rewards", {}).get("items", {}):
                if iid not in items:
                    report.error(f"maps.json/{mid}/{encounter_key}: reward references unknown item '{iid}'")

    # Second pass: gates resolve, and spawn_maps agree with the zone tables.
    for mid, m in maps.items():
        for g in m.get("gates", []):
            target = g.get("to_map")
            if target not in maps:
                report.error(f"maps.json/{mid}/gate.{g.get('id')}: unknown destination map '{target}'")
                continue
            spawn = g.get("to_spawn")
            if spawn not in maps[target].get("spawn_points", {}):
                report.error(
                    f"maps.json/{mid}/gate.{g.get('id')}: destination '{target}' has no spawn point '{spawn}'"
                )
            req_boss = g.get("requires", {}).get("boss_defeated")
            if req_boss and req_boss not in maps:
                report.error(f"maps.json/{mid}/gate.{g.get('id')}: requires boss of unknown map '{req_boss}'")

    for sid, c in species.items():
        declared = set(c.get("spawn_maps", []))
        actual = {mid for mid, used in referenced_species.items() if sid in used}
        for mid in declared:
            if mid not in maps:
                report.error(f"creatures.json/{sid}: spawn_maps lists unknown map '{mid}'")
        if declared - {m for m in declared if m not in maps} != actual:
            missing = actual - declared
            extra = (declared & set(maps)) - actual
            if missing:
                report.error(f"creatures.json/{sid}: spawns in {sorted(missing)} but spawn_maps does not list it")
            if extra:
                report.error(f"creatures.json/{sid}: spawn_maps lists {sorted(extra)} but no zone table uses it")

    return maps


def validate_quests(doc, maps, items, report: Report) -> None:
    ids: set[str] = set()
    for q in doc.get("quests", []):
        qid = q.get("id")
        if not qid:
            report.error("quests.json: quest without id")
            continue
        if qid in ids:
            report.error(f"quests.json: duplicate quest '{qid}'")
        ids.add(qid)
        if q.get("map") and q["map"] not in maps:
            report.error(f"quests.json/{qid}: unknown map '{q['map']}'")
        obj = q.get("objective", {})
        if not obj.get("type"):
            report.error(f"quests.json/{qid}: objective needs a type")
        for iid in q.get("rewards", {}).get("items", {}):
            if iid not in items:
                report.error(f"quests.json/{qid}: reward references unknown item '{iid}'")
    for q in doc.get("quests", []):
        for req in q.get("requires", []):
            if req not in ids:
                report.error(f"quests.json/{q.get('id')}: requires unknown quest '{req}'")


def validate_intro(doc, report: Report) -> None:
    professor = doc.get("professor", {})
    if not professor.get("name"):
        report.error("intro.json: the professor needs a 'name'")
    for key in ("skin", "hair", "outfit", "trim"):
        check_color(report, f"intro.json/professor.colors.{key}", professor.get("colors", {}).get(key))

    for key in ("cor_chao", "cor_parede", "cor_madeira", "sky_top", "sky_horizon"):
        check_color(report, f"intro.json/cenario.{key}", doc.get("cenario", {}).get(key))

    if len(doc.get("falas_abertura", [])) < 2:
        report.error("intro.json: 'falas_abertura' needs at least two lines")
    if not doc.get("fala_escolha"):
        report.error("intro.json: missing 'fala_escolha'")
    confirmacao = doc.get("fala_confirmacao", "")
    if "{criatura}" not in confirmacao:
        report.warn("intro.json: 'fala_confirmacao' does not use the {criatura} placeholder")
    if not doc.get("falas_encerramento"):
        report.error("intro.json: missing 'falas_encerramento'")


def validate_progression(doc, report: Report) -> None:
    for section in ("player", "creature"):
        cfg = doc.get(section, {})
        if not isinstance(cfg.get("max_level"), int) or cfg["max_level"] < 2:
            report.error(f"progression.json/{section}: max_level must be an int >= 2")
        if not isinstance(cfg.get("base_xp"), (int, float)) or cfg["base_xp"] <= 0:
            report.error(f"progression.json/{section}: base_xp must be > 0")
        if not isinstance(cfg.get("exponent"), (int, float)) or cfg["exponent"] <= 0:
            report.error(f"progression.json/{section}: exponent must be > 0")
    combat = doc.get("combat", {})
    if not 0.0 <= combat.get("critical_chance", -1) <= 1.0:
        report.error("progression.json/combat: critical_chance must be within 0..1")
    if combat.get("defense_softening", 0) <= 0:
        report.error("progression.json/combat: defense_softening must be > 0")
    idle = doc.get("idle", {})
    if idle.get("max_offline_hours", 0) <= 0:
        report.error("progression.json/idle: max_offline_hours must be > 0")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data", default=None, help="path to the data directory")
    args = parser.parse_args()

    data_dir = Path(args.data) if args.data else Path(__file__).resolve().parent.parent / "data"
    report = Report()

    elements_doc = load(data_dir, "elements.json", report)
    rarities_doc = load(data_dir, "rarities.json", report)
    skills_doc = load(data_dir, "skills.json", report)
    creatures_doc = load(data_dir, "creatures.json", report)
    items_doc = load(data_dir, "items.json", report)
    maps_doc = load(data_dir, "maps.json", report)
    quests_doc = load(data_dir, "quests.json", report)
    progression_doc = load(data_dir, "progression.json", report)
    intro_doc = load(data_dir, "intro.json", report)

    if not report.ok():
        print_report(report, data_dir)
        return 1

    elements = validate_elements(elements_doc, report)
    rarities = validate_rarities(rarities_doc, report)
    skills = validate_skills(skills_doc, elements, report)
    species = validate_creatures(creatures_doc, elements, rarities, skills, report)
    items = validate_items(items_doc, report)
    maps = validate_maps(maps_doc, species, items, report)
    validate_quests(quests_doc, maps, items, report)
    validate_progression(progression_doc, report)
    validate_intro(intro_doc, report)

    print(f"species: {len(species)}  skills: {len(skills)}  items: {len(items)}  maps: {len(maps)}")
    print_report(report, data_dir)
    return 0 if report.ok() else 1


def print_report(report: Report, data_dir: Path) -> None:
    for w in report.warnings:
        print(f"WARN  {w}")
    for e in report.errors:
        print(f"ERROR {e}")
    if report.ok():
        print(f"OK    {data_dir} is consistent ({len(report.warnings)} warning(s))")
    else:
        print(f"FAIL  {len(report.errors)} error(s), {len(report.warnings)} warning(s)")


if __name__ == "__main__":
    sys.exit(main())
