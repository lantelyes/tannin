#!/usr/bin/env python3
# Development tool. Turns a clean ntdll and its patched copy (made with apply.py) into the Swift source for
# Sources/TanninCore/NtdllRecipe.swift, so the app can apply the same patch without Python.
#
#   python3 -I make-recipe.py <arch> <clean ntdll.dll> <patched ntdll.dll>
#
# The recipe holds only the bytes that differ: Tannin's detour and the jump to it. No Wine code is copied.
import hashlib
import sys


def runs(clean, patched, gap=4):
    out, i, n = [], 0, len(clean)
    while i < n:
        if clean[i] == patched[i]:
            i += 1
            continue
        start = end = i
        while i < n and i - end <= gap:
            if clean[i] != patched[i]:
                end = i
            i += 1
        out.append((start, patched[start:end + 1]))
    return out


def main():
    if len(sys.argv) != 4:
        raise SystemExit(f"usage: {sys.argv[0]} <arch> <clean> <patched>")
    arch = sys.argv[1]
    clean = open(sys.argv[2], "rb").read()
    patched = open(sys.argv[3], "rb").read()
    if len(clean) != len(patched):
        raise SystemExit("the patched file has a different length; this recipe format does not cover that")
    print("        NtdllRecipe(")
    print(f'            arch: "{arch}",')
    print(f'            cleanSHA256: "{hashlib.sha256(clean).hexdigest()}",')
    print(f'            patchedSHA256: "{hashlib.sha256(patched).hexdigest()}",')
    print(f"            size: {len(clean)},")
    print("            runs: [")
    for offset, data in runs(clean, patched):
        text = data.hex()
        lines = [text[i:i + 96] for i in range(0, len(text), 96)]
        print(f"                Run(offset: {offset}, hex: \"\"\"")
        for line in lines:
            print(f"                    {line}")
        print('                    """),')
    print("            ]")
    print("        ),")


main()
