# Tannin

Free Steam Play for Mac: install and play Windows games from the native Mac Steam client, on a free
Wine engine with Apple's D3DMetal.

**Status: early test build.** One game has been run end to end on one Mac. Expect rough edges, and see
`FINDINGS.md` for what has actually been shown to work.

## What you need

- A Mac with Apple silicon, on macOS 26 or later.
- Steam for Mac, installed in Applications and signed in at least once.
- Apple's **Game Porting Toolkit** disk image. It is free with an Apple account:
  [download it from Apple](https://developer.apple.com/download/all/?q=game%20porting%20toolkit)
  ("Evaluation environment for Windows games", 4.0 beta 3 or newer). Tannin never includes it.
- About 2 GB of free disk space, before any games.

## Install

1. Download `Tannin-<version>.zip` from the [Releases page](https://github.com/lantelyes/tannin/releases) and open it.
2. Move **Tannin** to your Applications folder and open it.
3. macOS will say it could not verify Tannin, because this build is not signed with an Apple developer
   certificate. Open **System Settings › Privacy & Security**, scroll down, and click **Open Anyway**.
   You only do this once.
4. Follow **Set Up Tannin**. It downloads the Wine engine and the Steam bridge (about 550 MB), asks
   for the Game Porting Toolkit disk image, and last of all asks before it adds Steam Play to Steam.
   When macOS asks whether Tannin may change other apps, allow it.

Then install a Windows game from your Steam library and press Play, in Steam or in Tannin.

## What it does to Steam, and how to undo it

Tannin adds one file to `Steam.app`, changes two lines of its settings and signs Steam again on your
Mac, so that Steam loads the add-on that makes Windows games installable. **Valve does not support
this.** It also stops Steam updating itself, because a Steam update turns the add-on off.

To undo it, open Tannin and choose **Engine › Remove Steam Play**. Steam is replaced with a copy
signed by Valve, and Tannin checks that signature first. Your games, saves and account are not touched.

Known limits: 32-bit games start but have no Steam overlay, achievements or cloud saves. A Steam
update needs a new Tannin before Steam Play works again.

## What it is made of

| Piece | Source | How Tannin gets it |
|---|---|---|
| Steam add-on and Steam bridge | NotProton 1.2.6 | Downloaded, SHA-256 pinned |
| Wine engine | winecx-gptk 4.8.3 (Wine 11.19, CrossOver 26.3 sources) | Downloaded, SHA-256 pinned |
| D3DMetal | Apple Game Porting Toolkit 4 | You download it from Apple; Tannin imports it and checks Apple's signature |
| Steam client files | Valve | Downloaded from Valve's servers, SHA-256 pinned |

Nothing is used before its hash has been checked. CrossOver itself is never used.

## Build it yourself

```sh
swift build
swift test
scripts/bundle.sh        # build/Tannin.app
scripts/package.sh       # dist/Tannin-<version>.zip, for a release
.build/debug/tannin doctor
```

Needs Xcode's Swift toolchain (Swift 6.2 or later). The command line tool `tannin` does everything
the app does.

## Licence

GPL-3.0. See `LICENSE` and `NOTICE`. Tannin is not affiliated with or endorsed by Valve, Apple or
CodeWeavers. Steam is a trademark of Valve Corporation.
