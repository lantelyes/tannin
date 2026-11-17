# Tannin

Free Steam Play for Mac: install and play Windows games from the native Mac Steam client, on a free
Wine engine with Apple's D3DMetal.

**Status: early proof of concept.** See `FINDINGS.md` for what has actually been shown to work.

## What it is made of

| Piece | Source | How Tannin gets it |
|---|---|---|
| Steam add-on and Steam bridge | NotProton 1.2.6 | Downloaded, SHA-256 pinned |
| Wine engine | winecx-gptk 4.8.3 (Wine 11.19, CrossOver 26.3 sources) | Downloaded, SHA-256 pinned |
| D3DMetal | Apple Game Porting Toolkit 4 | You download it from Apple; Tannin imports it and checks Apple's signature |
| Steam client files | Valve | Downloaded from Valve's servers, SHA-256 pinned |

Tannin changes `Steam.app` to load the add-on. Valve does not support this. `tannin steam disable`
puts back a copy of Steam signed by Valve.

## Build

```sh
swift build
swift test
.build/debug/tannin doctor
```

Requires Apple silicon, macOS 15 or later, Rosetta 2 and Xcode's Swift toolchain.

## Licence

GPL-3.0. See `LICENSE` and `NOTICE`.
