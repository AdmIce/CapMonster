#!/usr/bin/env python3
"""Static sanity checks over the GDScript sources.

This is not a GDScript parser. It catches the specific mistakes that are cheap
to make and expensive to find by hand:

  * mixed tabs/spaces indentation (Godot rejects the file outright)
  * unbalanced brackets / unterminated strings
  * duplicate class_name registrations
  * `SomeClass.member` where SomeClass is one of OUR class_names or autoloads
    and `member` is declared nowhere in that script or its project-local
    ancestors (engine-inherited members are reported as warnings, not errors)
  * autoload names used in code that are not registered in project.godot
  * scene files pointing at scripts that do not exist

Usage:
    python tools/check_scripts.py
Exit code 0 = clean, 1 = at least one error.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

CLASS_NAME_RE = re.compile(r"^class_name\s+([A-Za-z_]\w*)", re.M)
EXTENDS_RE = re.compile(r"^extends\s+([A-Za-z_]\w*)", re.M)
FUNC_RE = re.compile(r"^\s*(?:static\s+)?func\s+([A-Za-z_]\w*)", re.M)
VAR_RE = re.compile(r"^\s*(?:@export[^\n]*\s+)?(?:static\s+)?var\s+([A-Za-z_]\w*)", re.M)
CONST_RE = re.compile(r"^\s*const\s+([A-Za-z_]\w*)", re.M)
ENUM_RE = re.compile(r"^\s*enum\s+([A-Za-z_]\w*)", re.M)
SIGNAL_RE = re.compile(r"^\s*signal\s+([A-Za-z_]\w*)", re.M)
# Inner classes: `class Resultado extends RefCounted` is reachable as Owner.Resultado.
INNER_CLASS_RE = re.compile(r"^\s*class\s+([A-Za-z_]\w*)", re.M)
AUTOLOAD_RE = re.compile(r"^([A-Za-z_]\w*)\s*=\s*\"\*?res://(.+?)\"", re.M)
EXT_SCRIPT_RE = re.compile(r'path="(res://[^"]+\.gd)"')

# Members inherited from engine classes that we reference on our own types.
ENGINE_ALLOWLIST = {
    "new", "instantiate", "duplicate", "call", "bind", "emit", "connect",
    "free", "queue_free", "get_children", "add_child", "get_node", "size",
    "get_tree", "name", "position", "visible", "process_mode", "layer",
}

# Engine base classes with a small enough member surface that an unresolved
# reference is almost certainly a typo rather than an inherited member.
STRICT_BASES = {"RefCounted", "Object", "Resource"}


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


class Script:
    def __init__(self, path: Path, root: Path) -> None:
        self.path = path
        self.rel = path.relative_to(root).as_posix()
        self.text = path.read_text(encoding="utf-8")
        self.code = strip_strings_and_comments(self.text)
        match = CLASS_NAME_RE.search(self.text)
        self.class_name = match.group(1) if match else None
        extends = EXTENDS_RE.search(self.text)
        self.extends = extends.group(1) if extends else None
        self.members: set[str] = set()
        for pattern in (FUNC_RE, VAR_RE, CONST_RE, ENUM_RE, SIGNAL_RE, INNER_CLASS_RE):
            self.members.update(pattern.findall(self.text))


def strip_strings_and_comments(text: str) -> str:
    """Blanks out string literals and comments so member scans do not read prose."""
    out: list[str] = []
    i = 0
    length = len(text)
    while i < length:
        ch = text[i]
        if ch == "#":
            while i < length and text[i] != "\n":
                i += 1
            continue
        if ch in "\"'":
            quote = ch
            triple = text[i:i + 3] == quote * 3
            marker = quote * 3 if triple else quote
            i += len(marker)
            while i < length and text[i:i + len(marker)] != marker:
                if text[i] == "\\":
                    i += 1
                i += 1
            i += len(marker)
            out.append('""')
            continue
        out.append(ch)
        i += 1
    return "".join(out)


def check_indentation(script: Script, report: Report) -> None:
    uses_tabs = False
    for number, line in enumerate(script.text.splitlines(), start=1):
        stripped = line.lstrip("\t")
        indent = line[: len(line) - len(stripped)]
        if indent:
            uses_tabs = True
        leading = len(line) - len(line.lstrip())
        prefix = line[:leading]
        if "\t" in prefix and " " in prefix:
            report.error(f"{script.rel}:{number}: mixed tabs and spaces in the indentation")
        elif prefix and " " in prefix and uses_tabs:
            report.error(f"{script.rel}:{number}: space indentation in a tab-indented file")


def check_brackets(script: Script, report: Report) -> None:
    pairs = {")": "(", "]": "[", "}": "{"}
    stack: list[tuple[str, int]] = []
    line = 1
    for ch in script.code:
        if ch == "\n":
            line += 1
        elif ch in "([{":
            stack.append((ch, line))
        elif ch in ")]}":
            if not stack:
                report.error(f"{script.rel}:{line}: stray '{ch}'")
            elif stack[-1][0] != pairs[ch]:
                report.error(f"{script.rel}:{line}: '{ch}' closes '{stack[-1][0]}' from line {stack[-1][1]}")
                stack.pop()
            else:
                stack.pop()
    for ch, opened in stack:
        report.error(f"{script.rel}:{opened}: '{ch}' is never closed")


def check_quotes(script: Script, report: Report) -> None:
    for number, line in enumerate(script.text.splitlines(), start=1):
        code = strip_strings_and_comments(line)
        if code.count('"') % 2 or code.count("'") % 2:
            report.error(f"{script.rel}:{number}: unterminated string literal")


def collect_autoloads(project_file: Path, report: Report) -> dict[str, str]:
    if not project_file.exists():
        report.error("project.godot is missing")
        return {}
    text = project_file.read_text(encoding="utf-8")
    section = text.split("[autoload]", 1)
    if len(section) < 2:
        report.warn("project.godot declares no autoloads")
        return {}
    body = section[1].split("\n[", 1)[0]
    return {name: path for name, path in AUTOLOAD_RE.findall(body)}


def check_scene_scripts(root: Path, report: Report) -> None:
    for scene in sorted(root.rglob("*.tscn")):
        text = scene.read_text(encoding="utf-8")
        for script_path in EXT_SCRIPT_RE.findall(text):
            target = root / script_path.replace("res://", "")
            if not target.exists():
                report.error(f"{scene.relative_to(root).as_posix()}: missing script {script_path}")


def resolve_members(name: str, by_class: dict[str, Script]) -> tuple[set[str], bool]:
    """All members of `name` plus its project-local ancestors.

    Returns (members, reaches_engine_base) - the flag tells the caller whether an
    unresolved reference could still be a legitimate engine-inherited member.
    """
    members: set[str] = set()
    cursor = name
    seen: set[str] = set()
    while cursor in by_class and cursor not in seen:
        seen.add(cursor)
        script = by_class[cursor]
        members |= script.members
        cursor = script.extends or ""
    reaches_engine = cursor not in by_class and cursor not in STRICT_BASES
    return members, reaches_engine


def check_references(scripts: list[Script], autoloads: dict[str, Script], report: Report) -> None:
    by_class = {s.class_name: s for s in scripts if s.class_name}
    targets: dict[str, Script] = dict(by_class)
    targets.update(autoloads)

    for script in scripts:
        for match in re.finditer(r"\b([A-Z]\w*)\.([A-Za-z_]\w*)", script.code):
            owner, member = match.group(1), match.group(2)
            if owner not in targets:
                continue
            if member in ENGINE_ALLOWLIST:
                continue
            source = targets[owner]
            lookup = source.class_name if source.class_name else owner
            if lookup in by_class:
                members, reaches_engine = resolve_members(lookup, by_class)
            else:
                # Autoload: every reference from outside is a project member by
                # construction, so an unresolved one is a typo.
                members, reaches_engine = source.members, False
            if member in members:
                continue
            line = script.code[: match.start()].count("\n") + 1
            message = f"{script.rel}:{line}: {owner}.{member} is not declared in {source.rel}"
            if reaches_engine:
                report.warn(message + " (may be inherited from an engine class)")
            else:
                report.error(message)


def check_autoload_usage(
    scripts: list[Script], autoload_names: set[str], class_names: set[str], report: Report
) -> None:
    known_prefixes = {
        "Vector2", "Vector2i", "Vector3", "Vector3i", "Color", "Rect2", "Rect2i",
        "Input", "InputMap", "OS", "Engine", "Time", "JSON", "FileAccess", "DirAccess",
        "ResourceLoader", "ProjectSettings", "DisplayServer", "AudioServer", "TextServer",
    }
    for script in scripts:
        for match in re.finditer(r"\b([A-Z]\w*)\.(?:[A-Za-z_]\w*)", script.code):
            owner = match.group(1)
            if owner in known_prefixes or owner in autoload_names or owner in class_names:
                continue
            if owner.endswith("Manager") and owner not in autoload_names:
                line = script.code[: match.start()].count("\n") + 1
                report.warn(f"{script.rel}:{line}: '{owner}' looks like a manager but is not an autoload")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=None)
    args = parser.parse_args()

    root = Path(args.root) if args.root else Path(__file__).resolve().parent.parent
    report = Report()

    scripts = [Script(path, root) for path in sorted(root.rglob("*.gd"))]
    if not scripts:
        report.error("no .gd files found")
        print_report(report, root)
        return 1

    seen: dict[str, str] = {}
    for script in scripts:
        if script.class_name:
            if script.class_name in seen:
                report.error(f"duplicate class_name '{script.class_name}' in {script.rel} and {seen[script.class_name]}")
            seen[script.class_name] = script.rel
        check_indentation(script, report)
        check_brackets(script, report)
        check_quotes(script, report)

    autoload_paths = collect_autoloads(root / "project.godot", report)
    by_path = {s.rel: s for s in scripts}
    autoloads: dict[str, Script] = {}
    for name, rel in autoload_paths.items():
        if rel not in by_path:
            report.error(f"project.godot: autoload {name} points at a missing script res://{rel}")
            continue
        autoloads[name] = by_path[rel]

    check_scene_scripts(root, report)
    check_references(scripts, autoloads, report)
    check_autoload_usage(scripts, set(autoloads.keys()), set(seen.keys()), report)

    print(f"scripts: {len(scripts)}  classes: {len(seen)}  autoloads: {len(autoloads)}")
    print_report(report, root)
    return 0 if report.ok() else 1


def print_report(report: Report, root: Path) -> None:
    for w in report.warnings:
        print(f"WARN  {w}")
    for e in report.errors:
        print(f"ERROR {e}")
    if report.ok():
        print(f"OK    {root} passed ({len(report.warnings)} warning(s))")
    else:
        print(f"FAIL  {len(report.errors)} error(s), {len(report.warnings)} warning(s)")


if __name__ == "__main__":
    sys.exit(main())
