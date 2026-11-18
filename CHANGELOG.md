# What's new in Tannin

Every release, newest first, in plain words. `scripts/release.sh` refuses to make a release that
has no section here, and the same text becomes the notes shown in the update window.

## 0.3.0 (18 November 2026)

- Each game can choose its graphics layer: **D3DMetal** (Apple's), **DXMT** or **DXVK**. It starts on
  Automatic, which uses D3DMetal for 64-bit games and DXMT for 32-bit ones. The choice is on the
  game's page, with the settings that belong to that layer.
- **32-bit games that need Steam now start.** Until now they quit at once.
- Apple's Game Porting Toolkit is optional. Without it games run on DXMT; games that use
  Direct3D 12 still need it. You can skip it in setup and add it later on the Engine page.
- After updating, open **Engine** and press **Add** under "After the Update". It takes a few
  seconds, downloads nothing and does not change Steam.
- The game's page says which layer Automatic uses and, when the game's log shows it, which layer
  the game ran on last time.

## 0.2.1 (18 November 2026)

- Nothing new to use. This release exists to prove that Tannin updates itself from its real
  website, before anyone else is asked to rely on that.

## 0.2.0 (18 November 2026)

- Tannin can update itself. Choose **Tannin › Check for Updates…**, or let it check once a day.
  It always asks before installing anything.
- If Tannin is not in your Applications folder, it offers to move itself there when it opens.
  It has to be there to update.
- When a Steam update turns Steam Play off, Tannin looks for a newer Tannin straight away and
  tells you whether there is one.
- Settings has an Updates section, and Tannin has a small website with these notes.

## 0.1.0 (18 November 2026)

- The first test build.
