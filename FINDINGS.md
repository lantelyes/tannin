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

## 2026-11-18: the app (first version)

`Tannin.app` is built by `scripts/bundle.sh` from the `TanninApp` target and reads live state through `TanninCore`.

- **Screens that exist and show real data from this Mac:** Overview (status sentence, This Mac, Windows games),
  Games, per-game settings (presets, switches, "Changed" markers, launch-options preview, Save), Engine (Steam Play
  on/off with Remove, update freeze, Wine engine, D3DMetal with Replace, Steam bridge), Logs (filter, search,
  "Copy Details for a Bug Report"), the "Add Steam Play to Steam?" sheet, a Settings window with the menu bar
  switch, and the menu bar item.
- **Checked by looking at them:** the app can write images of its own screens (`TANNIN_SNAPSHOT_DIR=<folder>`),
  which needs no screen-recording permission. Overview, game settings, Engine, Logs and the sheet were viewed in
  light and dark; they follow the approved Cellar layout in ink and amber. The icon is the polyphenol ring.
- **Not exercised yet from the app:** Save, Add/Remove Steam Play, the freeze switch and Replace all call the same
  core functions the CLI used successfully, but nobody has clicked them in the app yet.
- **Not built yet:** the first-run setup checklist with download progress (the CLI does setup today), games that
  are not installed, the unsupported-game state, engine update checks, notifications, launch at login.
- The game settings screen shows only D3DMetal as the graphics layer, because that is the only one wired up.

## 2026-11-18: the app rebuilt in the Source List design

The first version's look was rejected as not Mac-native. The user chose option 2, "Source List", with the blue
accent, from the design canvas. `Sources/TanninApp` was rebuilt from system controls
only; the section above describes an app that no longer exists.

**What the core gained**

- **Steam's library, read from Steam's own files.** `appcache/appinfo.vdf` on this Mac is format 29 (magic
  `0x07564429`, 716 apps). `tannin game list --all` gives 1 installed Windows game (LEGO Builder's Journey, 64-bit
  by its PE header) and 102 not installed. "Not installed" means: type "game", no `macos` platform, a folder in
  `appcache/librarycache`, no app manifest. That rule has not been compared with Steam's own library list.
  A game with a Mac build it cannot use (Spec Ops: The Line, 32-bit Mac app) is not listed until it is installed.
- **Artwork.** Steam keeps images either directly in `librarycache/<appid>/` or one folder down under a hash; the
  file names are the same. With both handled, 99 of 102 not-installed games have a banner.
- **Setup without Python.** The x86_64 ntdll patch is three byte runs (9 + 753 + 31 bytes) in
  `NtdllRecipe.swift`. A test applies it to the installed engine's clean ntdll and gets the pinned patched hash
  `77ab70fe…efaa`. `tannin setup` prints the six steps; all six read "done" on this Mac.
  The live runner was not rebuilt with the new code path (it is in use), so `Runner.build` through the recipe has
  been run only in that test, not end to end.
- **Downloads** report progress and can be cancelled, keeping the `.part` file; tested against `file://` pins,
  including resuming a partial file. Not tried against the real 479 MB engine download.

**What the app is now**

- Minimum macOS 26. Sidebar: Windows Games, a collapsed "Not Installed" section with its count, Engine, Logs,
  status at the bottom, search over both game sections. A game's page has its Steam artwork under the toolbar and
  sidebar, Play or Install in Steam, a status line, Preset, and grouped settings. Engine and Logs as drawn. A
  "Set Up Tannin" window with the six steps opens at launch when the engine, toolkit or bridge is missing, and
  from the app menu at any time.
- **Checked by looking at real window captures** (`scripts/snapshots.sh <folder>`, which uses `screencapture`
  and so needs Screen Recording permission for the terminal): the game page with real data, and with prepared
  data the Engine, Logs, empty, not-installed, 32-bit notice, Steam-updated, Add Steam Play sheet and setup
  screens, each in light and dark. The app's own drawing of its window (`cacheDisplay`) cannot render the glass
  sidebar and toolbar, which is why the system capture is used.
- **Differences from the drawings, on purpose:** Graphics Layer is plain text, not a pop-up, because D3DMetal is
  the only choice. "Check for Tannin Update" and the Wine row's "Check for Updates" are not there; the
  Steam-updated note offers Show Logs and Remove Steam Play instead. "Save Changes" appears only when something
  changed. The Game Porting Toolkit cannot be chosen while a download is running.
- **Not exercised yet:** nobody has clicked Play, Install in Steam, Save Changes, the freeze switch, Add or Remove
  Steam Play, Replace, or any setup step in the new app. Whether Steam installs a not-installed game without the
  game first being assigned to Tannin's runner is still unknown. The menu bar item and the Settings window were
  not looked at.

## 2026-11-18: new icon

The ink-and-amber ring no longer fitted the app. The user chose option D, "Hex Play", from the "Icon" page of the
design canvas: a blue six-sided tile with a play triangle on a light tile. `scripts/make-icon.swift` draws it and
`scripts/bundle.sh` builds `AppIcon.icns` from it; the 1024 px drawing was viewed and matches the option. The menu
bar item now uses the same mark as a template image (`MenuBarGlyph.swift`); it has not been looked at in the real
menu bar. The Dark and Tinted appearances on the canvas are not built: they need a layered Icon Composer file,
which is a manual step. With the `.icns` alone, macOS shows the default appearance.

## 2026-11-18: setup run from nothing, and a release zip

- **Setup from a bare home folder now passes as a test** (`TANNIN_E2E_SETUP=1 swift test --filter SetupFromScratch`):
  engine unpacked, NotProton release downloaded from GitHub with progress, Valve files placed, ntdll patched from the
  Swift recipe, runner built and verified, D3DMetal imported and linked. It runs in a temporary home and never
  touches Steam. The engine archive and Valve's packages were borrowed from this Mac's download folder, so the
  479 MB engine download itself was not repeated; the last step, adding Steam Play, is not part of it.
- **A bug that test found:** `Hashing.fileSize` read the size through `URL.resourceValues`, which remembers its answer
  on the URL value. With download progress switched on (the app's path, never the CLI's), a finished 73 MB download
  was measured at a stale 160 to 300 KB, called too short and deleted. Setup from the app could not have got past
  the Steam bridge step. Fixed by asking the file system each time; there is a test for it.
- **Release zip:** `scripts/package.sh` makes `dist/Tannin-0.1.0.zip` (about 1 MB, arm64 only, no bundled libraries).
  The unzipped app's signature verifies. It is ad-hoc signed: this Mac has no Developer ID certificate, so anyone who
  downloads it has to choose Open Anyway in System Settings once. Not tried on a second Mac.

## 2026-11-18: published

- The project is public at https://github.com/lantelyes/tannin, and `v0.1.0` is out as a pre-release with
  `Tannin-0.1.0.zip`. This replaces the earlier "local git only" rule.
- Before the first push the local commits were rewritten to carry GitHub's private email address; names, dates,
  messages and the final tree are unchanged. Checked on GitHub afterwards: every commit shows only that address,
  only `main` and the tag were pushed, and the file list matches.
- The release was downloaded without signing in: the SHA-256 matches, the app unzips with a valid ad-hoc signature,
  and `spctl` rejects it, which is the expected "Open Anyway" case described in the README. Opening the downloaded
  copy by hand, and everything on a second Mac, is still untried.
- The app's bundle identifier is now `io.github.lantelyes.Tannin`.

## 2026-11-18: this Mac reset to a fresh state, by hand

Done so the release can be tried from nothing. There is no reset command yet; these are the steps a future
"Reset" in Tannin has to cover.

1. The games were uninstalled in Steam itself while Steam Play was still on (`steam://uninstall/<appid>` opens
   Steam's own dialog). Steam removed the game's Windows environment (`compatdata/<appid>`) along with it.
2. `tannin steam disable --yes` put back Valve's Steam.app (team `MXGJJ98X76`, signature valid, no
   `DYLD_INSERT_LIBRARIES`) and removed the update freeze. This is the second time that path has worked.
3. Moved to the Trash: `~/Library/Application Support/Tannin`, `~/Library/Application Support/notproton`,
   `Steam/compatibilitytools.d/notproton-tannin`, `Steam/steamapps/compatdata/notproton-template`.
4. Two leftovers of the Steam add-on that were not on the list beforehand, also trashed:
   `Steam/steamapps/compatdata/.notproton-template.lock`, and `Steam/steamapps/common/Steam.dll`, a symlink the
   add-on makes to Steam's own `legacycompat/Steam.dll`.
5. Tannin's settings: `defaults delete` empties a domain but leaves an empty `.plist` behind in
   `~/Library/Preferences`; those were trashed too. `tccutil reset All <bundle id>` only works for an identifier
   macOS still knows an app for.

Afterwards `tannin setup` shows Rosetta and Steam done and everything else to do, no Windows game is installed, and
`compatdata` and `compatibilitytools.d` are empty.

Also learned: no game was ever assigned to Tannin's runner in Steam's `config.vdf`, yet LEGO Builder's Journey
installed and ran. The add-on makes Windows games installable without a per-game compatibility setting, so
"Install in Steam" does not need to write one.

## 2026-11-18: in-app updates, built but not yet switched on

What exists, and how far each part has been taken. Nothing here has been published and no release was made.

- **Sparkle 2.10.1** is inside the app (`scripts/bundle.sh` embeds the framework as its authors sign it and signs the
  app last). The app builds, starts and passes `codesign --verify --deep --strict`. **Updating is off**: the public
  half of the update key is still empty in `bundle.sh`, so the built app has no feed, "Check for Updates…" is
  disabled and Settings shows only the version. No update has been downloaded or installed by any build yet.
- **Screens**, as picked on the design canvas: a sidebar row while an update is waiting, an Updates group in
  Settings, an "Update to Tannin x…" line in the menu bar item, and the Steam-updated notice reporting a quiet check.
  All were photographed from prepared data by `scripts/snapshots.sh` (42 pictures, light and dark) and compared with
  the boards. They have never been driven by a real check; the menu bar line was not photographed at all.
- One sentence differs from the board on purpose. The board says "Tannin 0.2.1 works with the new Steam"; the app
  says "Tannin 0.2.1 is available", because the feed says a newer Tannin exists, not which Steam builds it supports.
- **Move to Applications.** The copy, the set-aside of an older copy, the clearing of the download mark and the
  undo are in `TanninCore` (`AppMove`) with six tests on scratch folders. The question was photographed. **Not
  tried:** the move from a really downloaded copy that macOS runs from its hidden folder, the lookup of that copy's
  real place (`SecTranslocateCreateOriginalPathForURL`, found by name at run time), opening the new copy as a second
  instance, and trashing the copy that was running. The plan is to try exactly that before any release.
- **A bug found on the way:** the notice row on a game's page squeezed its buttons to slivers a few points wide
  whenever its text was long. Fixed; it had been that way since the rebuild and no screenshot had shown it.
- **Website** in `docs/` (landing page, What's New, the notes the update window shows), with one stylesheet, no
  scripts and no fonts or anything else loaded from other sites. Rendered in Chrome at desktop and phone width, light
  and dark, and compared with the boards. GitHub Pages is not turned on, so none of it is public as a website.
  `whats-new.html` and `notes/` are written by `scripts/make-notes.swift` from `CHANGELOG.md`.
- **`scripts/release.sh`** has only ever been run as `--dry-run`. That run listed the five things a real release
  would refuse on today (uncommitted work, main not pushed, Pages off, no update key, no certificate), then built and
  zipped 0.2.0 ad-hoc signed, and wrote the feed, the notes and the Download button into `build/release-dry-run/`.
  The parts after the typed "yes" (tag, GitHub release, fetching the download back, pushing main, waiting for the
  live feed) have never run. Neither has signing with the certificate or with the update key.
- Observed while photographing: on macOS 27 an alert is drawn across two windows (the panel and a glass window
  behind it), so `screencapture -l` of the alert's own window comes out empty. The picture is taken of that part of
  the screen instead.
- Tests: 54 pass here. The tests workflow on GitHub passed on its first run (Swift 6.3 on `macos-26`).

## 2026-11-18: the update key, the certificate, and the local update test

Done with the user at the Mac. Test builds 0.1.90, 0.1.91 and 0.1.92 were signed with the certificate and read
their feed from `http://localhost:8765/`, served from a scratch folder on this Mac. Nothing was published.

- **Update key:** made with Sparkle's `generate_keys`; the private half is in the login Keychain only. The public
  half is in `scripts/bundle.sh`, so builds now carry a feed address and updating is on.
- **Certificate "Tannin Local Signing":** self-signed, code-signing use, valid to November 2036, made with
  `/usr/bin/openssl` and imported with `security import -T /usr/bin/codesign`; the temporary files were deleted in
  the same step. **`codesign` uses it without it being trusted** (macOS lists it as `CSSMERR_TP_NOT_TRUSTED`, and
  signing works). The app's requirement becomes `identifier "io.github.lantelyes.Tannin" and certificate leaf =
  H"9bf3abaf…5fbf"`, the same for every build.
- **A downloaded copy.** 0.1.90 was put in Downloads carrying the mark Safari puts on downloads. macOS refused it,
  the user chose Open Anyway, and Tannin, running from macOS's hidden folder, asked to move itself. **The move
  worked:** Tannin reopened from `/Applications`, no file in the copy still carried the download mark, and the copy
  in Downloads was gone. So `SecTranslocateCreateOriginalPathForURL` found by name, opening the new copy as a second
  instance, and trashing the running original all work on macOS 27.2. (The Trash could not be read from the
  terminal to see the old copy in it.)
- **The update.** Check for Updates… offered 0.1.91 with its notes, and Install Update replaced the app and
  relaunched it as 0.1.91 with the same signing requirement and no download mark. **macOS showed nothing extra:**
  no password prompt, no Gatekeeper warning, no "was prevented from modifying apps" notice. A second update, to
  0.1.92, went the same way.
- **Refusals.** A download with one byte changed, and the genuine download offered with a signature made by a
  different key, were each refused with "The update is improperly signed and could not be validated", and the
  installed version did not change.
- **Daily check.** With the stored last-check time wound back three days, the update window opened by itself
  about five seconds after launch. In a control launch straight afterwards, without winding back, it did not.
- **Settings with real data:** after a real check the Updates group read "Tannin 0.1.92 is available / You have
  0.1.91" with an Update… button. The sidebar row, the menu bar line and the Steam-updated notice have still only
  been seen with prepared data, because this Mac is not set up and has no Steam Play.
- **Found by the test:** Sparkle's licence text was copied into the app read-only, and the download mark cannot
  be taken off a read-only file. `bundle.sh` now makes everything in the app writable.
- **Not done yet:** whether the permission to change Steam survives an update (needs setup and Add Steam Play
  first); Sparkle declining to update a copy still running from Downloads (the move was accepted, so that path was
  not taken); anything on a second Mac; anything against the real feed address.
- **Left on this Mac after the test:** `/Applications/Tannin.app` is test build 0.1.92, which reads its feed from
  `localhost` only (the test server is stopped, so its checks find nothing). It is replaced when 0.2.0 is
  installed. `scripts/local-feed.sh <version>` builds, signs and serves a further test version when the Steam
  permission test is done.

## 2026-11-18: 0.2.0 released, and the website is on

- GitHub Pages serves `docs/` at https://lantelyes.github.io/tannin/ (http redirects to https). Every page and
  image answered 200 and the live landing page was byte-identical to `docs/index.html`.
- A dry run with the real key and certificate found a fault in `release.sh` itself: it compared the certificate's
  fingerprint in the wrong letter case and so rejected a correctly signed app. Fixed before the real run.
- The user ran `scripts/release.sh 0.2.0` and typed the yes. Result: tag `v0.2.0`, a pre-release with
  `Tannin-0.2.0.zip`, and the feed, notes and Download button on the website.
- Checked afterwards from the outside, without signing in: the download's SHA-256 equals the published one; the
  signature in the live feed verifies against that download with the update key; the app inside is 0.2.0, arm64,
  signed by "Tannin Local Signing" with the same requirement as the test builds, and carries the real feed address
  and no local-test setting.
- **Not shown yet:** an installed 0.2.0 finding and installing an update from the live feed. That is what 0.2.1
  is for. The copy in `/Applications` on this Mac is still the local test build.

