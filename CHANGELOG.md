# What's new in Tannin

Every release, newest first. `scripts/release.sh` won't make a release that has no section here, and
the same text becomes the notes shown in the update window.

## 0.7.0 (November 19, 2026)

- The setup window now shows the same seven game covers for everyone, in full color. They no longer
  start gray and fill in as setup runs.
- The covers download from Steam (about 450 KB) the first time the setup window opens, and are saved
  on your Mac. Until they load, each one shows as a tinted placeholder.
- Fixed the setup window briefly showing the Set Up button again between the Wine and Steam bridge
  downloads.
- Fixed Resume and Try Again restarting the progress bar from zero.
- The setup window no longer changes size.
- Rewrote the text throughout the app, the website, and these notes.
- Renamed Prepare Effects in the Background to Compile Shaders in the Background.
- Error alerts now say what Tannin couldn't do.

## 0.6.0 (November 18, 2026)

- New Engines & Renderers page. It lists your Wine versions and the three renderers (D3DMetal, DXMT,
  DXVK) and shows how many games use each. This is also where you add, replace, or remove D3DMetal.
- "Graphics layer" is now called "renderer".
- Each game's page now starts with its Wine version and renderer. You can install another Wine
  version or add D3DMetal from there.
- Adding D3DMetal is simpler. A sheet links to Apple's download and accepts the disk image by drag
  and drop.
- You can now remove D3DMetal. Games then run on DXMT.
- Steam Play has its own page, with the update freeze and the Steam bridge.
- New setup window. One button downloads everything, then asks before adding Steam Play. The Game
  Porting Toolkit step is gone.
- Setup now reports the real download size, about 650 MB.
- A game's page now tells you when the game needs Direct3D 12 and D3DMetal isn't installed.
- Your games keep their existing settings.

## 0.5.0 (November 18, 2026)

- New Fixed Window setting on a game's page, under Advanced. Some older games, such as Silent Hunter
  III, need a 4:3 resolution that a Mac display doesn't have, and quit with an error. Choose a size
  and the game runs in a window of that size.
- When a game quits for that reason, its page offers Use 1024 × 768.
- Changing Fixed Window doesn't require quitting Steam. The game has to have been played once first.

## 0.4.0 (November 18, 2026)

- You can install Wine 11.17 alongside 11.19 from the Engine page. Your games don't change until you
  switch them.
- Each game can use its own Wine version. Once a second version is installed, a game's page has a
  Wine Version row where you can keep the default or pick another.
- Before a game switches Wine versions, Tannin backs up its Windows environment (its settings, and
  for some games their saves). To go back, choose More > Restore Windows Environment.
- On the Engine page you can make another installed version the default, show it in Finder, or
  remove it. Removing a version first switches the games that use it.

## 0.3.0 (November 18, 2026)

- Each game can choose its graphics layer: Apple's D3DMetal, DXMT, or DXVK. Games start on
  Automatic, which uses D3DMetal for 64-bit games and DXMT for 32-bit games.
- Fixed 32-bit games that need Steam quitting at launch.
- Apple's Game Porting Toolkit is now optional. Without it, games run on DXMT. Direct3D 12 games
  still need it. You can skip it in setup and add it later on the Engine page.
- After updating, open Engine and click Add under "After the Update". It takes a few seconds and
  doesn't download anything or change Steam.
- A game's page shows which layer Automatic uses and, when the game's log says, which layer it last
  ran on.

## 0.2.1 (November 18, 2026)

- No changes. This release tests that Tannin can update itself from its website.

## 0.2.0 (November 18, 2026)

- Tannin can update itself. Choose Tannin > Check for Updates, or let it check once a day. It asks
  before installing.
- If Tannin isn't in your Applications folder, it offers to move itself there, because it can only
  update from Applications.
- When a Steam update turns Steam Play off, Tannin checks for a Tannin update right away and tells
  you if there is one.
- Settings has a new Updates section, and Tannin has a website with these notes.

## 0.1.0 (November 18, 2026)

- The first test build.
