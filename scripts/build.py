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
import argparse
import os
import random
import subprocess
import time

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCAN_DIRS = ["core", "games"]
ENTRY_MODULE = "core/dispatch"

# A dev build keeps the URL the testing loadstring already points at; a prod
# build writes somewhere else so releasing can never silently replace the
# build someone is mid-test on.
OUTPUT_PATHS = {
    "dev": os.path.join(REPO_ROOT, "dist", "out.lua"),
    "prod": os.path.join(REPO_ROOT, "dist", "out.prod.lua"),
}

# Debug tooling is not hidden in a prod build, it is absent: these modules
# never reach the bundle. core/debug_tab is the only thing that imports
# them, and main.luau only imports core/debug_tab when IsDev.
DEBUG_PREFIX = "core/debug_"

# Placeholder character used to splice shuffled-string references back into
# the code template. Not valid in Luau source, so it can't collide with
# anything real.
PLACEHOLDER = "\x01"


def git_commit():
    """Short HEAD sha, or "dirty"/"unknown" when that can't be established.

    Note this is HEAD at BUILD time, so a build made before committing
    reports the previous commit - the +N suffix flags that case.
    """
    try:
        sha = subprocess.check_output(
            ["git", "rev-parse", "--short", "HEAD"], cwd=REPO_ROOT, text=True
        ).strip()
    except Exception:
        return "unknown"

    try:
        dirty = subprocess.check_output(
            ["git", "status", "--porcelain"], cwd=REPO_ROOT, text=True
        ).strip()
    except Exception:
        dirty = ""

    return sha + "+" if dirty else sha


def collect_modules(env):
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
                if env == "prod" and key.startswith(DEBUG_PREFIX):
                    continue
                with open(full_path, encoding="utf-8") as f:
                    modules[key] = f.read().rstrip("\n")

    # Stamped in rather than read from disk, so the flag the bundle runs on
    # is the flag it was built with - core/build_env.luau on disk only ever
    # describes a local main.luau run.
    #
    # The commit goes in too, because "is the log I'm reading from the build
    # I just shipped?" has been unanswerable several times now, and guessing
    # wrong costs a whole round trip through the game.
    modules["core/build_env"] = (
        'return { Env = "%s", IsDev = %s, Commit = "%s", BuiltAt = "%s" }'
        % (
            env,
            "true" if env == "dev" else "false",
            git_commit(),
            time.strftime("%Y-%m-%d %H:%M:%S"),
        )
    )
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


def build(env):
    modules = collect_modules(env)
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

    output_path = OUTPUT_PATHS[env]
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    with open(output_path, "w", encoding="utf-8", newline="\n") as f:
        f.write(output)

    print(
        f"Built {output_path} [{env}] from {len(modules)} modules, "
        f"{len(literals)} strings shuffled"
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--env",
        choices=sorted(OUTPUT_PATHS),
        default="dev",
        help="dev (default) keeps the debug tab; prod leaves it out of the bundle",
    )
    build(parser.parse_args().env)
