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

## 2026-11-17: D3DMetal 4.0 beta 3 on the Wine 11.19 runner (no Steam involved)

- **The download.** `Game_Porting_Toolkit_4.0_beta_3.dmg` is an outer image; the evaluation environment is an inner
  image, "Evaluation environment for Windows games 4.0 beta 3.dmg", holding `redist/lib/{external,wine}`.
  `D3DMetal.framework` reports `CFBundleShortVersionString = 4.0b3` and passes
  `codesign -v -R='anchor apple generic and identifier "com.apple.D3DMetal"'`.
- **Layout.** The Unix halves in `wine/x86_64-unix` are relative symlinks to `../../external/libd3dshared.dylib`
  (`d3d10`, `d3d11`, `d3d12`, `d3d12core`, `dxgi`, `nvapi64`, `nvngx-on-metalfx`). Apple's Read Me says to `ditto`
  `redist/lib/` over the Wine `lib/` folder, which is what `tannin gptk import` does. Wine's own `d3d10/11/12`,
  `d3d12core` and `dxgi` DLLs (DXMT-based in this engine) are kept in `lib/tannin-stock` so it can be undone.
- **It runs.** `Tools/smoke/d3d12smoke.c`, a small Direct3D 12 program built with mingw, on the runner with
  `CX_APPLEGPTK_LIBD3DSHARED_PATH` and `CX_ACTIVE_GRAPHICS_BACKEND=d3dmetal` set:
  - `CreateDXGIFactory1` and `D3D12CreateDevice` both return 0.
  - Adapter: "AMD Compatibility Mode" (vendor 0x1002, device 0x66af, 25559 MB), which is how D3DMetal presents itself.
  - Maximum feature level 0xc200 (12_2).
  - Ray tracing tier reads 0 with and without `D3DM_SUPPORT_DXR=1`. Not understood yet; to be checked in a real game.
  - stderr carries one Apple Neural Engine "Bad argument" message; the program still exits 0.
- **Permission.** `tannin doctor --probe-steam` reports the terminal is not yet allowed to change Steam.app
  (App Management has not been granted). Steam.app is unchanged and still Valve-signed.

## 2026-11-17: Steam Play added to Steam (build 1794536281)

- **Steam update.** Started unmodified, Steam downloaded a 246 MB update and applied it on its own restart:
  build 1788652215 to 1794536281. It switched package variant ("macos-signed-2"), leaving the old
  `steam_client_signed_osx.manifest` behind, so the installed build is the highest version among the manifests,
  not the one in any single file.
- **App Management.** After the user allowed the terminal app and restarted it, `tannin doctor --probe-steam`
  reports "Allowed".
- **`tannin steam enable --yes` worked first time.** Afterwards Steam.app is ad-hoc signed
  (`flags=0x2(adhoc)`, `codesign --verify --strict` passes), `notproton.dylib` is in `Contents/MacOS`, and
  `LSEnvironment` holds the two added keys next to the original `LC_ALL`. The original Info.plist is in
  `~/Library/Application Support/Tannin/Backups/`.
- **The add-on loads on this Steam build.** `notproton.log`, seconds after Steam started:
  - `sigdb: loaded 25 signatures from …/1790904859.json`
  - `resolver: steamclient.dylib 18/18 signatures resolved, 3/3 optional`
  - `install_thread: ready, 13/13 hooks installed`; `steamui.dylib ready, 3/3 hooks installed`
  - `wrote 5 file(s) to …/compatibilitytools.d/notproton-tannin`, then "already registered from disk"
  - One error line: `webui: no room left to serve NotProton.OpenPrefixLog#1`. Effect unknown so far.
- **Update freeze** turned on afterwards (`tannin steam freeze on`).
- D3DMetal also starts without `CX_ACTIVE_GRAPHICS_BACKEND=d3dmetal` set (same smoke-test output), so a first
  game run needs no launch options.

## 2026-11-17: first game, LEGO Builder's Journey (appid 1544360)

**The user reports it "worked fully".** Installed and started from its own entry in the native Steam library.

- **Install.** With the add-on active the library page offered Install. Steam downloaded the Windows build:
  1,046,505,616 bytes downloaded, 4,322,970,119 on disk, `StateFlags 4`. No tool mapping was set by hand; the
  add-on gives a Windows-only game the first listed tool.
- **First Play.** The launch script built the prefix template (Wine showed its "Wine Mono Installer" download
  dialog once; this engine does not bundle Mono), cloned the prefix, staged the bridge into
  `pfx/drive_c/Program Files (x86)/Steam`, cloned the runner into `notproton/launchers/1544360/runner`, and started
  `steam.exe` (the bridge's helper), which started `Builder's Journey.exe`. About two minutes from Play to the game
  process on this first run.
- **Running.** The game process sat near 90% CPU with about 1.3 GB resident. Its log shows
  `overlay_shim ensure_mtl4_queue_hooks: AGXG14XFamilyCommandQueue_mtlnext` and a `WineMetalLayer` in BGRA8Unorm,
  i.e. frames presented through Metal 4.
- **D3DMetal was the graphics layer.** A D3DMetal shader cache appeared at
  `$(getconf DARWIN_USER_CACHE_DIR)d3dm/Builder's Journey.exe/shaders.cache/MTLGPUFamilyApple8_0`.
- **Exit.** `game exited status=0`, `session health: healthy`, prefix killed, no Wine processes left behind.
  Steam recorded the session (`LastPlayed` updated).
- **Launch options:** none were set. `WINEMSYNC=1` came from Tannin's defaults file, as the log states.
- **Log noise that did not matter:** `winebth` driver failed to load; during template creation, two
  `Unhandled exception c0000005` lines and `Failed to start RpcSs service`; one Apple Neural Engine message.

Not verified: Steam overlay, achievements and cloud saves (the bridge's job); ray tracing and DLSS options in
the game; whether Mono's download can be avoided or pre-seeded.

## 2026-11-17: undo and redo

- **`tannin steam disable --yes`** downloaded Valve's `appdmg_osx.zip` (pinned hash matched), checked the Steam.app
  inside it (`TeamIdentifier=MXGJJ98X76`, `Identifier=com.valvesoftware.steam`, `codesign --verify --strict` passes)
  and swapped it in. The modified bundle was kept at
  `~/Library/Application Support/Tannin/Backups/Steam.app.replaced-2026-11-17T164621Z`. The update freeze was removed.
- Afterwards: Valve-signed, hardened runtime flag back (`flags=0x10000(runtime)`), no `notproton.dylib`,
  `LSEnvironment` back to just `LC_ALL`. Game files and the game's prefix were untouched.
- **Stock Steam started normally**: no new lines in the add-on's log, bootstrapper reports "No update necessary:
  current version 6.1, package version 6.1".
- **`tannin steam enable --yes` again**, freeze on, Steam restarted: 18/18 signatures resolved, 13/13 hooks installed,
  as before.

The mechanism milestones (M1 to M7) are all met. Current state: Steam Play on, updates frozen.

## 2026-11-17: the "Wine Mono Installer" dialog was Tannin's fault (32-bit ntdll detour)

The user asked whether the first-launch Mono download could be avoided. It should never have appeared.

- The engine already bundles Wine Mono 11.3.0 as a shared install (`share/wine/mono/wine-mono-11.3.0`, 225 MB).
  On a fresh prefix Wine only has to install its small support package from there.
- **Untouched engine:** fresh `wineboot --init`: no access violations, no Mono errors, no dialog.
- **Runner with both ntdll files patched:** the same boot logs three `Unhandled exception code c0000005 … addr
  0x7bfab4c2`, then `REMOVEUSERINSTALLS returned 1627` and `install_wine_mono MsiInstallProduct failed, err=1627`.
  Wine then falls back to downloading the full Mono MSI, which is the dialog.
- **Runner with only the 64-bit ntdll patched:** no access violations, no Mono errors.
- So the **i386 detour crashes 32-bit programs on this engine.** `0x7bfab4c2 - 0x9b410` (the detour's RVA) is
  `0x7bf100b2`: the crash is 0xb2 into the detour with 32-bit ntdll loaded at 0x7bf10000, not at the 0x7bc00000 the
  detour's fixed addresses assume. That last step is inference from the arithmetic, not a debugger trace.
- **Fix:** `Runner.patchedArchitectures = ["x86_64"]`. The 32-bit ntdll stays as the engine ships it and no i386
  copy is staged, so the launch script skips its i386 comparison.
- **Cost:** 32-bit games start, but get no Steam bridge until a relocation-safe 32-bit detour exists.
- This also explains the two `c0000005` lines and "Failed to start RpcSs service" seen in the first game run's
  template build. The game ran anyway because it is 64-bit.
- The Mono MSI Wine downloaded (`~/.cache/wine/wine-mono-11.3.0-x86.msi`, sha256 `df2dfc16…18d3`) matches the hash
  embedded in this Wine's own installer code.
- Not yet re-tested through Steam: the next Play will rebuild the prefix template (the ntdll changed) and should
  show no dialog.

## Bridgeplay baseline

Not run yet. Waiting on the Game Porting Toolkit disk image and the user at the keyboard.
