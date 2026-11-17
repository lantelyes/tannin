# Findings

What has actually been run on this Mac, as opposed to read in someone else's source.

Machine: M2 Max, 32 GB, macOS 27.2.1, Rosetta 2 installed.

## 2026-11-17: clean slate

- Stopped Bourbon's Windows `steam.exe` (the only Wine process running).
- Moved to the Trash: `/Applications/CrossOver.app`, `~/Library/Application Support/CrossOver`,
  `/Applications/NotProton.app`, `~/Library/Application Support/notproton`.
- NotProton's `--remove-everything` was deliberately not run. NotProton had installed nothing (Steam untouched,
  its support folder held only `app.log`), and that uninstaller re-signs and then replaces Steam.app.
- `~/Library/Application Support/notproton` and `.../NotProton` are the same folder: the volume is case-insensitive.
- Steam.app afterwards: `Identifier=com.valvesoftware.steam`, `TeamIdentifier=MXGJJ98X76`, `codesign --verify --strict`
  passes, no `DYLD_INSERT_LIBRARIES` in `LSEnvironment`. Steam client build on disk: 1788652215.
- A Finder "move to Trash" request from the terminal hung waiting on a macOS prompt; a plain move into `~/.Trash` worked.

## 2026-11-17: engine, bridge patch, kit, runner (Steam not touched)

- **Engine.** `frankea/winecx-gptk` `runtime-v4.8.3` downloaded and matched its pinned SHA-256
  (`08ffabd7…8818`, 479,015,992 bytes). Unpacked layout is as expected. It runs under Rosetta and reports
  `wine-11.19`. The loader is not code-signed at all, so there is no hardened runtime to block library injection.
  The engine ships its own `lsteamclient.dll`/`.so`; the runner replaces them with NotProton's.
- **ntdll patch on Wine 11.19.** NotProton v1.2.6's `resolve.py` found the hook in both files without changes
  ("not a pinned build", but it resolves by pattern):
  - x86_64: clean `53692da9…1ed8`, hook RVA `0x64f06`, detour 832 bytes in section padding at `0x9d920`,
    patched `77ab70fe…efaa`.
  - i386: clean `404264bc…6473`, hook RVA `0x62810`, detour 1376 bytes at `0x9b410`, patched `712c793e…6475`.
  - Re-running `resolve.py` on the patched x86_64 file shows the hook as `jmp 0x9d920`. File sizes are unchanged;
    723 and 1230 bytes differ.
  - Built with Homebrew mingw-w64 14.0.0_3 (GCC 16.2.0). The linker prints "stripping non-representable symbol"
    for the four absolute addresses; the output is still produced.
  - This is a static check only. Whether the detour does its job is not known until a Steamworks game runs.
- **Kit.** NotProton 1.2.6 zip matched its pin (`595e6d62…188a`). Its payload holds `notproton.dylib`, `bridge/`,
  `overlay-shim.dylib`, `iconmaker`, `appinfo`, `run`, `fonts/`, `signatures/` (three files: 1788400362, 1789086785,
  1790904859). Both Valve packages and all ten Valve files matched their pins.
- **Runner.** Assembled at `~/Library/Application Support/notproton/runners/crossover-tannin-1/CrossOver` as an APFS
  clone. `tannin runner verify` passes everything except D3DMetal (no toolkit imported yet).
- **Boot test.** With the patched ntdll in place, `wineboot --init` in a throwaway prefix exited 0 and
  `wine cmd /c ver` printed `Microsoft Windows 10.0.19045`. The prefix's `system32/ntdll.dll` is the patched file.
  So the patch does not break normal process start-up.
- **Launch script facts confirmed from the real payload:** runner root is
  `runners/crossover-<build>/CrossOver`; `WINEMSYNC` defaults to 0 unless a defaults file sets it, so Tannin writes
  `defaults-override-tannin-1-rosetta` with `WINEMSYNC=1`.

Not done yet: importing the Game Porting Toolkit and linking D3DMetal, adding Steam Play to Steam, running a game.

## Bridgeplay baseline

Not run yet. Waiting on the Game Porting Toolkit disk image and the user at the keyboard.
