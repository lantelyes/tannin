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

## Bridgeplay baseline

Not run yet. Waiting on the Game Porting Toolkit disk image and the user at the keyboard.
