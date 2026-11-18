# What's new in Tannin

Every release, newest first, in plain words. `scripts/release.sh` refuses to make a release that
has no section here, and the same text becomes the notes shown in the update window.

## 0.6.0 (not released yet)

- **Engines & Renderers**, a new page. The Wine engines and the three renderers are two lists that
  work the same way, and each row says how many of your games use it. Apple's D3DMetal is a renderer
  like DXMT and DXVK: it is added, replaced and removed there. "Graphics layer" is now "renderer".
- **A game's page starts with what it runs on:** its Wine version and its renderer, side by side.
  The settings under them are named for the renderer the game really gets.
- **Both can be fetched from the game's page.** The Renderer pop-up offers D3DMetal when it is not on
  your Mac. The Wine Version pop-up offers a version that is not installed; Tannin downloads it with
  Steam left open, then asks before it moves the game.
- **Adding D3DMetal** is a small sheet that says where to get Apple's Game Porting Toolkit and takes
  the disk image, which can also be dropped on it. It says why when a disk image is not accepted.
- **D3DMetal can be removed.** Games then run on DXMT. Your disk image is not touched.
- **Steam Play has a page of its own**, with the switch, the update freeze and the Steam bridge.
- **Setup is five steps.** The Game Porting Toolkit step is gone; nothing in setup needs anything
  from you until the last step.
- When a game asks for Direct3D 12 and stops because D3DMetal is not there, its page says so.
- Nothing on your Mac moves with this update, and every game keeps the choice it had.

## 0.5.0 (18 November 2026)

- **Fixed Window**, a new setting on a game's page under Advanced. Some old games insist on a
  screen shape a Mac's display does not have and stop with an error; Silent Hunter III is one.
  Choose a size and the game runs in a window of that size, which it takes for the whole screen.
- When a game stops for that reason, its page says so and offers **Use 1024 × 768**.
- The setting is kept with the game, not in Steam, so Steam does not have to quit to save it. A
  game has to have been started once before it can be set.

## 0.4.0 (18 November 2026)

- **A second Wine version.** Wine 11.17 can be installed beside 11.19 from the Engine page, with
  one button. Nothing changes for your games until you say so.
- **A Wine version per game.** Once a second version is installed, a game's page has a Wine
  Version row. A game on "Default" follows the default engine; any other choice pins it.
- **A way back.** Before a game moves to another Wine version, Tannin keeps a copy of its Windows
  environment (its settings, and for some games their saves). **More › Restore Windows
  Environment…** puts it back.
- The Engine page can make another installed engine the default, show it in Finder, or remove it.
  Removing one first moves the games that use it.

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
