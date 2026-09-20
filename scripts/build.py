#!/usr/bin/env python3
"""Bundles core/*.luau + games/*.luau into a single, obfuscated dist/out.lua.

Every source file (except main.luau, the local-dev entry point) is written
against an `import(path)` function instead of calling readfile/loadstring
itself. This script packs each of those files into an in-memory module
table and provides that same `import` function backed by the table, so the
bundle behaves identically to running main.luau locally.

After assembling the bundle, every string literal in it is pulled out into
a shuffled lookup table and replaced with a call to fetch it back out by
its new (shuffled) position, so the source no longer reads as plaintext at
a glance. This is a speed bump, not real security: anyone willing to run
the bundle and print the strings table gets everything back. Layer a real
obfuscator (e.g. Prometheus, https://github.com/prometheus-lua/Prometheus)
on top of this output for anything that actually needs to resist reversing.
"""
import os
import random

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUTPUT_PATH = os.path.join(REPO_ROOT, "dist", "out.lua")
SCAN_DIRS = ["core", "games"]
ENTRY_MODULE = "core/dispatch"

# Placeholder character used to splice shuffled-string references back into
# the code template. Not valid in Luau source, so it can't collide with
# anything real.
PLACEHOLDER = "\x01"


def collect_modules():
    modules = {}
    for scan_dir in SCAN_DIRS:
        base = os.path.join(REPO_ROOT, scan_dir)
        for root, _, files in os.walk(base):
            for filename in files:
                if not filename.endswith(".luau"):
                    continue
                full_path = os.path.join(root, filename)
                rel_path = os.path.relpath(full_path, REPO_ROOT)
                key = rel_path.replace(os.sep, "/")[: -len(".luau")]
                with open(full_path, encoding="utf-8") as f:
                    modules[key] = f.read().rstrip("\n")
    return modules


def assemble(modules):
    lines = [
        "local modules = {}",
        "local cache = {}",
        "local function import(path)",
        "    if cache[path] == nil then",
        "        cache[path] = modules[path]()",
        "    end",
        "    return cache[path]",
        "end",
    ]
    for key in sorted(modules):
        lines.append(f'modules["{key}"] = function()')
        lines.append(modules[key])
        lines.append("end")
    lines.append(f'import("{ENTRY_MODULE}")(import)')
    return "\n".join(lines)


def extract_strings(source):
    """Strips `--` line comments and replaces every short-string literal
    ('...' or "...") with a PLACEHOLDER-wrapped index, returning the
    resulting template plus the list of literals it pulled out (each kept
    exactly as written, quotes included, so it drops back into a Lua table
    unchanged). Refuses to run on long strings/comments (`[[...]]`,
    `--[[...]]`), which need real bracket-depth tracking this scanner
    doesn't do; none exist in this repo today.
    """
    if "[[" in source:
        raise SystemExit(
            "build.py's obfuscator can't handle long strings/comments "
            "([[...]]) - remove them or extend extract_strings() first"
        )

    out = []
    literals = []
    i, n = 0, len(source)
    while i < n:
        ch = source[i]
        if ch == "-" and source[i : i + 2] == "--":
            end = source.find("\n", i)
            i = n if end == -1 else end
            continue
        if ch in "\"'":
            quote = ch
            j = i + 1
            while j < n and source[j] != quote:
                if source[j] == "\\":
                    j += 1
                j += 1
            literal = source[i : j + 1]
            literals.append(literal)
            out.append(f"{PLACEHOLDER}{len(literals) - 1}{PLACEHOLDER}")
            i = j + 1
            continue
        out.append(ch)
        i += 1

    template = "".join(out)
    # Drop lines left blank once their trailing comment was removed.
    template = "\n".join(line for line in template.split("\n") if line.strip())
    return template, literals


def shuffle_strings(template, literals):
    shuffled_order = list(range(len(literals)))
    random.shuffle(shuffled_order)

    # position_of[original_index] = 1-based slot in the shuffled Lua table.
    position_of = {orig: slot + 1 for slot, orig in enumerate(shuffled_order)}

    def replace(match_index):
        return f"S({position_of[match_index]})"

    parts = template.split(PLACEHOLDER)
    for idx in range(1, len(parts), 2):
        parts[idx] = replace(int(parts[idx]))
    code = "".join(parts)

    table_entries = ", ".join(literals[orig] for orig in shuffled_order)
    header = f"local STR = {{{table_entries}}}\nlocal function S(i) return STR[i] end"
    return header, code


def build():
    modules = collect_modules()
    if ENTRY_MODULE not in modules:
        raise SystemExit(f"entry module {ENTRY_MODULE} not found")

    assembled = assemble(modules)
    template, literals = extract_strings(assembled)
    header, code = shuffle_strings(template, literals)

    banner = (
        "-- AUTO-GENERATED by scripts/build.py. Do not edit directly;\n"
        "-- edit the source files under core/ and games/, then rebuild."
    )
    output = f"{banner}\n{header}\n{code}\n"

    os.makedirs(os.path.dirname(OUTPUT_PATH), exist_ok=True)
    with open(OUTPUT_PATH, "w", encoding="utf-8", newline="\n") as f:
        f.write(output)

    print(f"Built {OUTPUT_PATH} from {len(modules)} modules, {len(literals)} strings shuffled")


if __name__ == "__main__":
    build()
