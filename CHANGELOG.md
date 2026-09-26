# Changelog

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
