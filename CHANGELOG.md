# Changelog

## 1.1.0-beta (unreleased)

- **VB-Audio Matrix and Matrix Coconut** support (experimental: not tested on a real update yet)
- Updates every VB-Audio product found (Voicemeeter and/or Matrix) in one run, with a single restart
- Each product stays **in its installed edition** (read from the installer Windows keeps for uninstalling, cross-checked with the programs present); the edition only changes with `-Edition`
- Post-restart device check covers the Matrix virtual audio devices too
- `-Edition` accepts `Matrix` and `Coconut`; with nothing installed, the menu offers all 5 products

## 1.0.0-beta (2026-09-26)

First public beta. Fully tested on Voicemeeter Potato (Windows 11 x64). Standard and Banana are supported, but a full update has not been tested on them yet.

- Updates Voicemeeter Standard, Banana or Potato with a single restart (silent uninstall + install)
- Checks the installer's VB-Audio digital signature
- Backs up `Documents\Voicemeeter`, the live configuration (Remote API `Command.Save`) and the startup shortcut
- Closes Voicemeeter cleanly through the Remote API (`Command.Shutdown`), so the last settings are saved
- Asks "restart now or later"
- One-time check at the next logon that repairs the Voicemeeter devices when Windows names them all "Speakers" after a driver update (no extra restart)
- Options: `-CheckOnly`, `-Force`, `-Edition`
- `Update-Voicemeeter.bat`: an all-in-one version you can simply double-click, built from the `.ps1` by `tools\Build-Bat.ps1`
