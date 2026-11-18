# Where these files come from

Copied from NotProton (https://github.com/NotProtonNot/NotProton), directory `ntdll-patch/`,
tag `v1.2.6` (commit `e380d11a774bcabb70cc99d4f2dc30882f7eadab`), fetched 2026-11-17.

Licence: GPL-3.0, same as NotProton. Copyright remains with the NotProton authors.

Files: `apply.py`, `build-ntdll.sh`, `build.sh`, `build32.sh`, `build64.sh`, `detour.c`, `detour32.c`,
`link.ld`, `link32.ld`, `link64.ld`, `resolve.py`, `shim.S`, `shim32.S`, `shim64.S`.

What they do: `resolve.py` finds the place in a Wine `ntdll.dll` where a small detour can be attached,
`build.sh` / `build32.sh` compile that detour for the exact file, and `apply.py` writes the patched copy.
The detour makes a game's `steamclient64.dll` hand its calls to the Steam bridge (`lsteamclient.dll`).

They need `python3` with `capstone`, and Homebrew `mingw-w64`. Build outputs go next to the sources and are
ignored by git.

## Tannin's change to `shim32.S` (2026-11-18)

Upstream's 32-bit entry code runs `mov ebx, ebp` and then `mov esi, WM_REG`. On winecx 4.8.3 the resolver finds
`wm` in `ebx`, so the second instruction read the frame pointer instead and the detour crashed every 32-bit
process on its first module load. Tannin's copy reads `WM_REG` first. Every other file is unchanged.

## Tannin's own addition

`make-recipe.py` is Tannin's (GPL-3.0). It compares a clean ntdll with the copy `apply.py` produced and prints the
differing bytes as Swift source for `Sources/TanninCore/NtdllRecipe.swift`. The app and the CLI apply that recipe
themselves, so the Python tools are only needed when deriving a patch for a new engine.
