# Voicemeeter Updater

Update **Voicemeeter** (Standard, Banana, Potato) and **VB-Audio Matrix** (Matrix, Coconut) with **one restart instead of two**.

VB-Audio's recommended way to update is *uninstall → restart → install → restart*. This PowerShell script uninstalls the old version and installs the new one in the same Windows session, for every VB-Audio product it finds. After that, **a single restart** finishes the job, and you choose whether it happens now or later.

> **🧪 Beta.** Fully tested on Voicemeeter **Potato** (Windows 11 x64). Standard, Banana, Matrix and Matrix Coconut are supported but not fully tested yet (see [Tested](#tested)). If something goes wrong, please [open an issue](../../issues) and attach the log from `%LOCALAPPDATA%\VoicemeeterUpdater`.

> Not affiliated with VB-Audio. Voicemeeter and Matrix are © Vincent Burel / VB-Audio Software. This script only automates the official installer downloaded from [vb-audio.com](https://vb-audio.com/Voicemeeter/).

---

## Quick start

1. Download **`Update-Voicemeeter.bat`** from the [Releases page](../../releases) (take the most recent one).
2. **Double-click it**, then accept the admin prompt.
3. Confirm with `Y` and wait about 1 minute.
4. When asked, choose **Restart now** or **Later**.

If you are already on the latest version, the script tells you so and **changes nothing**.

> **"Windows protected your PC"?** This is SmartScreen, which shows up for any file downloaded from the internet that isn't signed. Click **More info → Run anyway**. You can open the `.bat` in Notepad to read it first: it is a small launcher followed by the PowerShell script.

<details>
<summary>Prefer the plain PowerShell script?</summary>

Download `Update-Voicemeeter.ps1` instead. Double-clicking a `.ps1` only opens it in an editor, so right-click it and choose **Run with PowerShell**, or run this in the download folder:

```powershell
powershell -ExecutionPolicy Bypass -File .\Update-Voicemeeter.ps1
```
Both files do exactly the same thing: `tools\Build-Bat.ps1` builds the `.bat` from the `.ps1`.
</details>

## What it does

| Step | Details |
|---|---|
| 1. Check | Finds every VB-Audio product installed (Voicemeeter and/or Matrix) with its **edition** and version, and reads the latest one on vb-audio.com. Each product is updated **in its own edition**: a Banana user gets Banana, never Potato. It stops here if everything is up to date. |
| 2. Download | Gets the **official** packages and checks that the installer carries **VB-Audio's digital signature**. It refuses to continue otherwise. |
| 3. Backup | Saves `Documents\Voicemeeter` (settings, scenes, Macro Buttons…) and the Matrix settings folder, the **current live Voicemeeter configuration** (exported through its Remote API) and the "run at startup" shortcuts. |
| 4. Close | Asks Voicemeeter to shut down through its Remote API, so your last changes are saved. It then closes Matrix, Macro Buttons, VBAN2MIDI and the other tools from the VB-Audio folders. |
| 5. Update | Stops Windows audio for a few seconds, runs a silent uninstall, starts audio again, then runs a silent install of each new version. |
| 6. Restore | Puts back the startup shortcut, which the uninstaller deletes, and any settings file that disappeared. Nothing is overwritten. |
| 7. Restart | Asks **restart now or later**. |
| 8. After the restart | Checks the virtual audio devices once, at your next logon, and repairs them if needed (see below). |

**Never touched:** VB-CABLE, VB-CABLE A+B / C+D, Hi-Fi Cable, and third-party tools such as Equalizer APO.

### The "all devices are called Speakers" problem

When an update also changes the version of the **Voicemeeter VAIO driver** (Matrix has the same kind of driver), Windows keeps the old driver loaded until the restart. The new audio devices then only appear **after** the restart, which is too late for the installer to give them their names. The result:

- all Voicemeeter outputs are named **"Speakers (VB-Audio Voicemeeter VAIO)"**, and the inputs "Voicemeeter Out 1…8";
- VB-Audio's `VBDeviceCheck.exe` reports `Pin Name redundancy`;
- apps using **MME** see the same name 8 times and all end up on the same device.

**Since v1.1.0-beta, this is prevented at the source.** The problem, and a possible Windows crash (blue screen `0xD1` in the old VAIO driver), happens when an app (Discord, a game, a browser...) still uses a Voicemeeter device while the old driver is removed. The script now stops Windows audio for a few seconds during the driver swap, so the old driver is released cleanly and the new devices are named right away.

As a safety net, the script also schedules a **one-time check at your next logon**. If the names are wrong, it reinstalls Voicemeeter silently once more. The new driver is already loaded at that point, so **no extra restart is needed**. It then starts again what was running (Voicemeeter, Macro Buttons, clients…) and shows a "repaired" message. If the names are fine, the check simply deletes itself.

## Options

Run these from a PowerShell window:

```powershell
.\Update-Voicemeeter.bat -CheckOnly          # only tell me if an update is available
.\Update-Voicemeeter.bat -Force              # reinstall even if up to date (also fixes broken device names)
.\Update-Voicemeeter.bat -Edition Potato     # install or switch edition: Standard | Banana | Potato | Matrix | Coconut
.\Update-Voicemeeter.bat -Yes -Restart Later # no questions, restart later yourself (Restart: Ask | Now | Later)
```
The same options work with `Update-Voicemeeter.ps1`.

The edition only changes when you ask for it with `-Edition`. If neither Voicemeeter nor Matrix is installed, the script asks what to install.

## Files and traces

| Where | What |
|---|---|
| `%LOCALAPPDATA%\VoicemeeterUpdater` | Logs (`update_<date>.log`), the last 3 backups, and a copy of the script + installer until the post-restart check has run |
| `%TEMP%\VoicemeeterUpdater` | Downloaded package |
| Task Scheduler | `Voicemeeter Updater - post-restart check`: one-shot, deletes itself |
| Task Scheduler | `Voicemeeter Updater - finish install (<product>)`: only if Windows refused the new driver before the restart; runs once at boot, then deletes itself |

## Troubleshooting

- **Device names are still wrong:** run the script with `-Force`, then check with `C:\Program Files (x86)\VB\Voicemeeter\VBDeviceCheck.exe`. You should get 0 errors.
- **Settings look different:** your backups are in `%LOCALAPPDATA%\VoicemeeterUpdater\backup_<date>`. `CurrentSettings.xml` can be loaded from Voicemeeter's menu (*Load Settings*).
- **Windows default device / per-app outputs changed:** reinstalling creates new audio devices, so pick them again in Windows sound settings.
- **"Download link not found":** vb-audio.com changed its page. Please open an issue.

## Requirements

- Windows 10 or 11, 64-bit, Windows PowerShell 5.1 (built in)
- Administrator rights
- Internet access to `vb-audio.com` and `download.vb-audio.com`

## Tested

- Windows 11 x64, Voicemeeter **Potato** 3.1.2.2 → 3.1.3.0, including the automatic device-name repair.
- **Standard** and **Banana**: package detection, download links, signatures and silent-install switches are checked, but a full update has not been run yet.
- **Matrix / Matrix Coconut** (experimental): detection, download links, signatures and silent-install switches are checked, but a full update has not been run yet.

Feedback is welcome.

## Credits

Made by [Taimauurufu](https://github.com/Taimauurufu), co-written with **Claude** (Anthropic's AI assistant), including the investigation of the device-name problem.

## License

[MIT](LICENSE). Use at your own risk.
