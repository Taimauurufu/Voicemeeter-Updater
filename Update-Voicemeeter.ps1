<#
    Voicemeeter Updater  v1.0.0
    https://github.com/Taimauurufu/Voicemeeter-Updater
    Updates Voicemeeter (Standard, Banana or Potato) with a SINGLE restart.

    VB-Audio's procedure is: uninstall -> restart -> install -> restart.
    This script does:        uninstall -> install  -> ONE restart (you choose now or later).

    HOW TO USE
      Right-click this file -> "Run with PowerShell", then accept the admin prompt.

    WHAT IT DOES
      1. Detects your edition and version, and checks the latest one on vb-audio.com.
         If you are already up to date, it stops there and changes nothing.
      2. Downloads the official package and checks VB-Audio's digital signature.
      3. Backs up your settings (Documents\Voicemeeter + the current live config) and startup shortcut.
      4. Closes Voicemeeter properly (Remote API "Shutdown", so your settings are saved).
      5. Silent uninstall + silent install of the new version.
      6. Restores the "run at startup" shortcut if the uninstaller removed it.
      7. Asks you: restart now, or later.
      8. At your next logon, checks the Voicemeeter audio devices. When the driver itself was updated,
         Windows sometimes creates them only at the restart and names them all "Speakers" (apps then
         can't tell them apart). If so, it repairs them automatically: quick reinstall, no restart,
         then Voicemeeter and your tools are started again.
      VB-CABLE / VB-CABLE A+B / Hi-Fi Cable are never touched.

    OPTIONS (from a PowerShell prompt)
      -CheckOnly                   only tell me if an update is available
      -Force                       reinstall even if already up to date
      -Edition Standard|Banana|Potato   install / switch to this edition

    Files: download in %TEMP%\VoicemeeterUpdater, logs + backups in %LOCALAPPDATA%\VoicemeeterUpdater
    Not affiliated with VB-Audio. Use at your own risk.
#>
[CmdletBinding()]
param(
    [switch]$CheckOnly,
    [switch]$Force,
    [ValidateSet('Standard', 'Banana', 'Potato')][string]$Edition,
    # internal: paths of the user who launched the script (kept when elevating)
    [string]$UserDocs, [string]$UserStartup, [string]$UserData, [string]$UserName,
    # internal: device-name check run once at the first logon after the restart
    [switch]$PostRestartCheck, [switch]$RegisterPostRestartCheck, [string]$SetupPath
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

# ---------------------------------------------------------------- elevation
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"",
           '-UserDocs',    "`"$([Environment]::GetFolderPath('MyDocuments'))`"",
           '-UserStartup', "`"$([Environment]::GetFolderPath('Startup'))`"",
           '-UserData',    "`"$env:LOCALAPPDATA`"",
           '-UserName',    "`"$env:USERDOMAIN\$env:USERNAME`"")
    if ($CheckOnly) { $a += '-CheckOnly' }
    if ($Force)     { $a += '-Force' }
    if ($Edition)   { $a += '-Edition', $Edition }
    try { Start-Process powershell.exe -Verb RunAs -ArgumentList $a }
    catch { Write-Host 'Administrator rights are required to update Voicemeeter.' -ForegroundColor Red; Read-Host 'Press Enter to close' | Out-Null }
    exit
}
if (-not $UserDocs)    { $UserDocs    = [Environment]::GetFolderPath('MyDocuments') }
if (-not $UserStartup) { $UserStartup = [Environment]::GetFolderPath('Startup') }
if (-not $UserData)    { $UserData    = $env:LOCALAPPDATA }
if (-not $UserName)    { $UserName    = "$env:USERDOMAIN\$env:USERNAME" }
$Unattended = $PostRestartCheck -or $RegisterPostRestartCheck

$Host.UI.RawUI.WindowTitle = 'Voicemeeter Updater'
$Work    = Join-Path $env:TEMP 'VoicemeeterUpdater'
$Data    = Join-Path $UserData 'VoicemeeterUpdater'
$Stamp   = Get-Date -Format 'yyyy-MM-dd_HHmmss'
$Log     = Join-Path $Data "update_$Stamp.log"
$Marker  = Join-Path $Data 'restart-pending.txt'
$Docs    = Join-Path $UserDocs 'Voicemeeter'
New-Item -ItemType Directory -Force $Work, $Data | Out-Null

$Editions = [ordered]@{
    Standard = @{ Page = 'https://vb-audio.com/Voicemeeter/index.htm';  Setup = 'VoicemeeterSetup' }
    Banana   = @{ Page = 'https://vb-audio.com/Voicemeeter/banana.htm'; Setup = 'VoicemeeterProSetup' }
    Potato   = @{ Page = 'https://vb-audio.com/Voicemeeter/potato.htm'; Setup = 'Voicemeeter8Setup' }
}
$AppProcs = 'voicemeeter', 'voicemeeter_x64', 'voicemeeterpro', 'voicemeeterpro_x64', 'voicemeeter8', 'voicemeeter8x64'
$CheckTask = 'Voicemeeter Updater - post-restart check'

# ---------------------------------------------------------------- helpers
function Log([string]$msg, [string]$color = 'Gray') {
    Write-Host $msg -ForegroundColor $color
    Add-Content -Path $Log -Value ('{0}  {1}' -f (Get-Date -Format 'HH:mm:ss'), $msg) -Encoding UTF8
}
function Done([int]$code = 0) {
    Log "Log file: $Log" DarkGray
    if (-not $Unattended) { Read-Host 'Press Enter to close' | Out-Null }
    exit $code
}
function Fail([string]$msg) { Log "ERROR: $msg" Red; Done 1 }

function ConvertTo-Version($v) {
    if (-not $v) { return $null }
    try { [version](("$v" -replace '\s', '') -replace ',', '.') } catch { $null }
}

function Get-InstalledVoicemeeter {
    $keys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    foreach ($k in Get-ItemProperty $keys -ErrorAction SilentlyContinue) {
        if ("$($k.UninstallString)" -notmatch '(?i)^"?([^"]*\\(Voicemeeter(?:8|Pro)?Setup)\.exe)') { continue }
        $setup = $Matches[1]; $name = $Matches[2]
        $ed = ($Editions.Keys | Where-Object { $Editions[$_].Setup -eq $name } | Select-Object -First 1)
        $ver = if (Test-Path $setup) { ConvertTo-Version (Get-Item $setup).VersionInfo.FileVersion } else { $null }
        return [pscustomobject]@{ Edition = $ed; Version = $ver; Setup = $setup; Dir = Split-Path $setup }
    }
    $null
}

function Get-Latest([string]$ed) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $html = (Invoke-WebRequest $Editions[$ed].Page -UseBasicParsing).Content
    $best = [regex]::Matches($html, '(Voicemeeter\w*Setup_v(\d+))\.zip') |
            Sort-Object { [int]$_.Groups[2].Value } | Select-Object -Last 1
    if (-not $best) { return $null }
    $digits = $best.Groups[2].Value
    [pscustomobject]@{
        Zip     = "$($best.Groups[1].Value).zip"
        Url     = "https://download.vb-audio.com/Download_CABLE/$($best.Groups[1].Value).zip"
        Version = if ($digits.Length -eq 4) { [version]($digits.ToCharArray() -join '.') } else { $null }
    }
}

function Wait-Setup([int]$timeoutSec = 600) {
    $t = 0
    while (Get-Process | Where-Object { $_.Name -like 'Voicemeeter*Setup*' }) {
        Start-Sleep 2; $t += 2
        if ($t -ge $timeoutSec) { Log "The setup is still running after $timeoutSec s." Yellow; return }
    }
}

function Test-RestartPending {
    if (-not (Test-Path $Marker)) { return $false }
    $boot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
    try { $t = [datetime](Get-Content $Marker -Raw).Trim() } catch { $t = [datetime]::MinValue }
    if ($boot -gt $t) { Remove-Item $Marker -Force; return $false }
    $true
}

function Ask-Restart([string]$text) {
    Add-Type -AssemblyName System.Windows.Forms
    $owner = New-Object System.Windows.Forms.Form
    $owner.TopMost = $true
    $answer = [System.Windows.Forms.MessageBox]::Show($owner, $text, 'Voicemeeter Updater',
        [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
    $owner.Dispose()
    if ($answer -eq [System.Windows.Forms.DialogResult]::Yes) {
        Log 'Restarting now...' Cyan
        shutdown.exe /r /t 0
        exit 0
    }
    Log 'Restart postponed. Voicemeeter may not work correctly until you restart Windows.' Yellow
}

function Close-Voicemeeter([string]$installDir, [string]$saveTo) {
    $running = Get-Process -Name $AppProcs -ErrorAction SilentlyContinue
    $dll = Join-Path $installDir $(if ([Environment]::Is64BitProcess) { 'VoicemeeterRemote64.dll' } else { 'VoicemeeterRemote.dll' })
    if ($running -and (Test-Path $dll)) {
        try {
            # use a copy of the DLL so the uninstaller can delete the original
            $copy = Join-Path $Work ("vmr_$Stamp" + [IO.Path]::GetExtension($dll))
            Copy-Item $dll $copy -Force
            $cls = 'VMR' + ($Stamp -replace '\D', '')
            Add-Type -Name $cls -Namespace VMUpd -MemberDefinition @"
[DllImport(@"$copy")] public static extern int VBVMR_Login();
[DllImport(@"$copy")] public static extern int VBVMR_Logout();
[DllImport(@"$copy")] public static extern int VBVMR_IsParametersDirty();
[DllImport(@"$copy", CharSet = CharSet.Ansi)] public static extern int VBVMR_SetParameters(string p);
"@
            $api = "VMUpd.$cls" -as [type]
            if ($api::VBVMR_Login() -eq 0) {
                Start-Sleep -Milliseconds 300
                [void]$api::VBVMR_IsParametersDirty()
                if ($saveTo) { [void]$api::VBVMR_SetParameters("Command.Save = `"$saveTo`";"); Start-Sleep 2 }
                [void]$api::VBVMR_SetParameters('Command.Shutdown = 1;')
                Start-Sleep -Milliseconds 500
                [void]$api::VBVMR_Logout()
                Log 'Voicemeeter asked to shut down (settings saved).'
            }
        } catch { Log "Remote API not available ($($_.Exception.Message)), closing windows instead." Yellow }
        for ($i = 0; $i -lt 30 -and (Get-Process -Name $AppProcs -ErrorAction SilentlyContinue); $i++) { Start-Sleep -Milliseconds 500 }
    }
    # everything else started from the Voicemeeter folder (Macro Buttons, VBAN2MIDI, ...).
    # Third-party tools (e.g. Equalizer APO's VoicemeeterClient) are left alone.
    $prefix = $installDir.TrimEnd('\') + '\'
    $fromPackage = {
        Get-CimInstance Win32_Process | Where-Object {
            $_.ExecutablePath -and $_.ExecutablePath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) -and
            $_.Name -notlike '*setup*' } |
        ForEach-Object { Get-Process -Id $_.ProcessId -ErrorAction SilentlyContinue }
    }
    $others = & $fromPackage
    if ($others) {
        $others | ForEach-Object { [void]$_.CloseMainWindow() }
        Start-Sleep 4
        & $fromPackage | Stop-Process -Force -ErrorAction SilentlyContinue
    }
}

function Backup-StartupLinks([string]$to) {
    $list = @()
    $shell = New-Object -ComObject WScript.Shell
    foreach ($dir in $UserStartup, [Environment]::GetFolderPath('CommonStartup')) {
        if (-not (Test-Path $dir)) { continue }
        foreach ($lnk in Get-ChildItem $dir -Filter *.lnk) {
            if ($shell.CreateShortcut($lnk.FullName).TargetPath -match '(?i)\\VB\\Voicemeeter\\') {
                $copy = Join-Path $to ('startup_' + $lnk.Name)
                Copy-Item $lnk.FullName $copy -Force
                $list += [pscustomobject]@{ Original = $lnk.FullName; Copy = $copy }
            }
        }
    }
    $list
}
function Restore-StartupLinks($list) {
    foreach ($l in $list) {
        if (-not (Test-Path $l.Original)) { Copy-Item $l.Copy $l.Original; Log 'Startup shortcut restored.' }
    }
}

function Uninstall-Install([pscustomobject]$inst, [string]$setupExe) {
    if ($inst -and (Test-Path $inst.Setup)) {
        Log "Uninstalling Voicemeeter $($inst.Edition) $($inst.Version) (silent)..."
        Start-Process $inst.Setup -ArgumentList '-u', '-h' -WorkingDirectory $inst.Dir -Wait
        Wait-Setup
        # a leftover Voicemeeter virtual device would make the installer refuse to install
        Get-PnpDevice -Class MEDIA -PresentOnly -ErrorAction SilentlyContinue |
            Where-Object { $_.FriendlyName -match 'Voicemeeter' } | ForEach-Object {
                Log "Removing leftover device: $($_.FriendlyName)" Yellow
                pnputil /remove-device "$($_.InstanceId)" | Out-Null
            }
    }
    Log "Installing $(Split-Path $setupExe -Leaf) (silent)..."
    Start-Process $setupExe -ArgumentList '-i', '-h' -WorkingDirectory (Split-Path $setupExe) -Wait
    Wait-Setup
}

# Voicemeeter virtual audio devices (single VAIO driver, 8 in / 8 out) and their names in Windows
function Get-VaioEndpoints {
    foreach ($flow in 'Render', 'Capture') {
        foreach ($k in Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\$flow" -ErrorAction SilentlyContinue) {
            if ((Get-ItemProperty $k.PSPath -ErrorAction SilentlyContinue).DeviceState -ne 1) { continue }
            $props = Get-Item "$($k.PSPath)\Properties" -ErrorAction SilentlyContinue
            if (-not $props) { continue }
            $ref = "$($props.GetValue('{233164c8-1b2c-4c7d-bc68-b671687a2567},1'))"
            if ($ref -notmatch '(?i)vbvoicemeetervaio\w*?_(in|out)(\d+)') { continue }
            [pscustomobject]@{ Flow = $flow; Channel = "$($Matches[1])$($Matches[2])"
                               Name = "$($props.GetValue('{a45c254e-df1c-4efd-8020-67d146a850e0},2'))" }
        }
    }
}
# After a driver update, Windows may create the new devices only at the restart, AFTER the
# installer tried to name them: they all show up as "Speakers" (same name = apps can't tell them apart).
function Test-VaioNames {
    $eps = @(Get-VaioEndpoints)
    foreach ($g in $eps | Group-Object Flow, Name | Where-Object Count -gt 1) {
        "$($g.Count) $($g.Group[0].Flow) devices share the name '$($g.Group[0].Name)'"
    }
    foreach ($e in $eps | Where-Object { $_.Name -notmatch '(?i)voicemeeter' }) {
        "$($e.Flow) channel $($e.Channel) is named '$($e.Name)'"
    }
}

# start programs as the normal (non-admin) user, in the user's session
function Start-AsUser($procs) {
    # skip what is still running (some clients survive a Voicemeeter restart)
    $alive = @(Get-CimInstance Win32_Process | ForEach-Object { $_.CommandLine })
    $procs = @($procs | Where-Object { $alive -notcontains $_.CommandLine })
    if (-not $procs) { return }
    $cmd = Join-Path $Data 'relaunch.cmd'
    $lines = @('@echo off')
    foreach ($p in $procs) {
        $dir = Split-Path $p.ExecutablePath
        $lines += "start `"`" /D `"$dir`" $($p.CommandLine)"
        $lines += 'timeout /t 3 /nobreak >nul'
    }
    Set-Content -Path $cmd -Value $lines -Encoding Default
    $name = 'Voicemeeter Updater - relaunch'
    $act = New-ScheduledTaskAction -Execute 'cmd.exe' -Argument "/c `"$cmd`""
    $prn = New-ScheduledTaskPrincipal -UserId $UserName -LogonType Interactive -RunLevel Limited
    Register-ScheduledTask -TaskName $name -Action $act -Principal $prn -Force | Out-Null
    Start-ScheduledTask -TaskName $name
    Start-Sleep ([Math]::Min(30, 4 * @($procs).Count + 2))
    Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction SilentlyContinue
}

function Register-PostRestartCheck([string]$setupExe) {
    $copyScript = Join-Path $Data 'VoicemeeterUpdater.ps1'
    if ($PSCommandPath -ne $copyScript) { Copy-Item $PSCommandPath $copyScript -Force }
    $setupDir = Join-Path $Data 'setup'
    if (Test-Path $setupDir) { Remove-Item $setupDir -Recurse -Force }
    New-Item -ItemType Directory -Force $setupDir | Out-Null
    Copy-Item $setupExe $setupDir
    $setupCopy = Join-Path $setupDir (Split-Path $setupExe -Leaf)
    $arg = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Minimized -File `"$copyScript`" -PostRestartCheck " +
           "-SetupPath `"$setupCopy`" -UserDocs `"$UserDocs`" -UserStartup `"$UserStartup`" -UserData `"$UserData`" -UserName `"$UserName`""
    $act = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $arg
    $trg = New-ScheduledTaskTrigger -AtLogOn -User $UserName
    $trg.Delay = 'PT45S'
    $prn = New-ScheduledTaskPrincipal -UserId $UserName -LogonType Interactive -RunLevel Highest
    $set = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 30)
    Register-ScheduledTask -TaskName $CheckTask -Action $act -Trigger $trg -Principal $prn -Settings $set -Force | Out-Null
    Log 'A check of the Voicemeeter devices will run once, at your next logon.'
}
function Remove-PostRestartCheck {
    Unregister-ScheduledTask -TaskName $CheckTask -Confirm:$false -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $Data 'setup') -Recurse -Force -ErrorAction SilentlyContinue
}

function Show-Message([string]$text, [string]$icon = 'Information') {
    Add-Type -AssemblyName System.Windows.Forms
    $owner = New-Object System.Windows.Forms.Form
    $owner.TopMost = $true
    [void][System.Windows.Forms.MessageBox]::Show($owner, $text, 'Voicemeeter Updater', 'OK', $icon)
    $owner.Dispose()
}

# ---------------------------------------------------------------- internal modes
if ($RegisterPostRestartCheck) {
    if (-not $SetupPath -or -not (Test-Path $SetupPath)) { Fail 'RegisterPostRestartCheck needs -SetupPath.' }
    Register-PostRestartCheck $SetupPath
    Done
}

if ($PostRestartCheck) {
    Log '=== Voicemeeter Updater: device check after the restart ===' Cyan
    for ($t = 0; -not (Get-VaioEndpoints) -and $t -lt 120; $t += 5) { Start-Sleep 5 }
    $problems = @(Test-VaioNames)
    if (-not $problems) {
        Log 'Voicemeeter audio devices are fine. Nothing to do.' Green
        Remove-PostRestartCheck
        Done
    }
    $problems | ForEach-Object { Log "Problem: $_" Yellow }
    $inst = Get-InstalledVoicemeeter
    $sig = if ($SetupPath -and (Test-Path $SetupPath)) { Get-AuthenticodeSignature $SetupPath } else { $null }
    if (-not $inst -or -not $sig -or $sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'BUREL VINCENT') {
        Remove-PostRestartCheck
        Show-Message "Windows gave the Voicemeeter audio devices wrong names after the update.`n`nPlease reinstall Voicemeeter (run the updater with -Force)." 'Warning'
        Done 1
    }
    Log 'Repairing: Voicemeeter is reinstalled once more (same version, no restart needed)...' Cyan
    # remember what was running, to start it again afterwards (Voicemeeter, Macro Buttons, clients...)
    $prefix = $inst.Dir.TrimEnd('\') + '\'
    $running = @(Get-CimInstance Win32_Process | Where-Object {
            $_.Name -notlike '*setup*' -and $_.CommandLine -and $_.ExecutablePath -and
            ($_.Name -like 'voicemeeter*' -or $_.ExecutablePath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) } |
        Sort-Object { if ($_.Name -match '^voicemeeter(8|pro)?(x64|_x64)?\.exe$') { 0 } else { 1 } })
    $seen = @{}
    $running = @($running | Where-Object { -not $seen.ContainsKey($_.CommandLine) -and ($seen[$_.CommandLine] = $true) } |
        Select-Object ExecutablePath, CommandLine)
    $links = Backup-StartupLinks $Data
    Close-Voicemeeter $inst.Dir $null
    Uninstall-Install $inst $SetupPath
    Start-Sleep 5
    Restore-StartupLinks $links
    $left = @(Test-VaioNames)
    Start-AsUser $running
    Remove-PostRestartCheck
    if ($left) {
        $left | ForEach-Object { Log "Still wrong: $_" Red }
        Show-Message "Voicemeeter was reinstalled but some audio devices still have wrong names.`n`nSee the log: $Log" 'Warning'
        Done 1
    }
    Log 'Voicemeeter audio devices repaired.' Green
    Show-Message "Voicemeeter audio devices were repaired (Windows had reset their names after the driver update).`n`nEverything is ready."
    Done
}

# ---------------------------------------------------------------- 1. state
Log '==============================================' Cyan
Log '  Voicemeeter Updater v1.0.0 (one restart only)' Cyan
Log '==============================================' Cyan

if (Test-RestartPending) {
    Log 'Voicemeeter was already updated, but Windows has not been restarted since.' Yellow
    Ask-Restart "Voicemeeter was already updated.`n`nWindows must be restarted to finish the update.`nSave your work first.`n`nRestart now?"
    Done
}

$inst = Get-InstalledVoicemeeter
if ($inst) { Log "Installed : Voicemeeter $($inst.Edition) $($inst.Version)" }
else       { Log 'Installed : none' }

$target = if ($Edition) { $Edition } elseif ($inst -and $inst.Edition) { $inst.Edition } else { $null }
if (-not $target) {
    if ($CheckOnly) { Log 'Voicemeeter is not installed.' Yellow; Done }
    Write-Host ''
    Write-Host 'Voicemeeter is not installed. Which edition do you want to install?'
    Write-Host '  1 = Voicemeeter (Standard)   2 = Banana   3 = Potato   Q = quit'
    switch ((Read-Host 'Choice').Trim()) {
        '1' { $target = 'Standard' } '2' { $target = 'Banana' } '3' { $target = 'Potato' }
        default { Log 'Cancelled.'; Done }
    }
}

try { $latest = Get-Latest $target } catch { Fail "Cannot reach vb-audio.com ($($_.Exception.Message))" }
if (-not $latest) { Fail "Download link not found on $($Editions[$target].Page) (the website may have changed)." }
Log "Latest    : Voicemeeter $target $(if ($latest.Version) { $latest.Version } else { $latest.Zip })"

$sameEdition = $inst -and $inst.Edition -eq $target
if ($sameEdition -and $inst.Version -and $latest.Version -and $inst.Version -ge $latest.Version -and -not $Force) {
    Log 'You are up to date. Nothing to do.' Green
    Done
}
if ($CheckOnly) {
    if ($inst -and -not $sameEdition) { Log "Voicemeeter $target can be installed (it would replace $($inst.Edition))." Yellow }
    else { Log 'An update is available. Run the script without -CheckOnly to install it.' Yellow }
    Done
}

Write-Host ''
if ($inst -and -not $sameEdition) { Log "This will REPLACE Voicemeeter $($inst.Edition) with Voicemeeter $target." Yellow }
Write-Host 'Voicemeeter will be closed: audio going through it stops until Windows is restarted.' -ForegroundColor Yellow
if ((Read-Host 'Continue? (Y/N)').Trim() -notmatch '^[yYoO]') { Log 'Cancelled.'; Done }

# ---------------------------------------------------------------- 2. download
$zipPath = Join-Path $Work $latest.Zip
$extract = Join-Path $Work ([IO.Path]::GetFileNameWithoutExtension($latest.Zip))
if (-not (Test-Path $zipPath) -or (Get-Item $zipPath).Length -lt 5MB) {
    Log "Downloading $($latest.Url) ..."
    if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
        & curl.exe -L --fail --silent --show-error -o $zipPath $latest.Url
        if ($LASTEXITCODE -ne 0) { Fail 'Download failed.' }
    } else {
        try { Invoke-WebRequest $latest.Url -OutFile $zipPath -UseBasicParsing } catch { Fail "Download failed ($($_.Exception.Message))" }
    }
}
if (Test-Path $extract) { Remove-Item $extract -Recurse -Force }
Expand-Archive -Path $zipPath -DestinationPath $extract -Force
$setup = Get-ChildItem $extract -Recurse -Filter "$($Editions[$target].Setup).exe" | Select-Object -First 1
if (-not $setup) { Fail "$($Editions[$target].Setup).exe not found in the package." }

$sig = Get-AuthenticodeSignature $setup.FullName
if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'BUREL VINCENT') {
    Fail "The installer signature is not VB-Audio's ($($sig.Status)). Stopping for safety."
}
$newVer = ConvertTo-Version $setup.VersionInfo.FileVersion
Log "Package OK: $($setup.Name) $newVer, signed by VB-Audio (Vincent Burel)." Green
if ($sameEdition -and $inst.Version -and $newVer -and $inst.Version -ge $newVer -and -not $Force) {
    Log 'You are up to date. Nothing to do.' Green
    Done
}

# ---------------------------------------------------------------- 3. backup
$backup = Join-Path $Data "backup_$Stamp"
New-Item -ItemType Directory -Force $backup | Out-Null
if (Test-Path $Docs) {
    robocopy $Docs (Join-Path $backup 'Documents_Voicemeeter') /E /R:1 /W:1 /NFL /NDL /NJH /NJS /NP `
        /XF *.mp3 *.wav *.wma *.aac *.m4a *.flac *.ogg *.aif *.aiff | Out-Null
}
$startupLinks = Backup-StartupLinks $backup
Log "Settings backed up to $backup" Green

# ---------------------------------------------------------------- 4. close
Log 'Closing Voicemeeter...'
$installDir = if ($inst) { $inst.Dir } else { $null }
if ($installDir) { Close-Voicemeeter $installDir (Join-Path $backup 'CurrentSettings.xml') }

# ---------------------------------------------------------------- 5. uninstall + install
Uninstall-Install $inst $setup.FullName

$now = Get-InstalledVoicemeeter
if ($now -and $now.Edition -eq $target -and $now.Version -eq $newVer) {
    Log "Voicemeeter $target $newVer installed." Green
} else {
    # Fallback: the installer can refuse while the old driver is still loaded -> install at next boot
    Log 'The installer did not finish now: it will run automatically at the next Windows start.' Yellow
    $pending = Join-Path $env:ProgramData 'VoicemeeterUpdater\pending'
    if (Test-Path $pending) { Remove-Item $pending -Recurse -Force }
    New-Item -ItemType Directory -Force $pending | Out-Null
    Copy-Item $setup.FullName $pending
    $exe = Join-Path $pending $setup.Name
    $act = New-ScheduledTaskAction -Execute 'cmd.exe' -Argument "/c `"`"$exe`" -i -h & schtasks /delete /tn `"Voicemeeter Updater - finish install`" /f`""
    $trg = New-ScheduledTaskTrigger -AtStartup
    $prn = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -RunLevel Highest
    Register-ScheduledTask -TaskName 'Voicemeeter Updater - finish install' -Action $act -Trigger $trg -Principal $prn -Force | Out-Null
}
Set-Content -Path $Marker -Value (Get-Date -Format 's')
Register-PostRestartCheck $setup.FullName

# ---------------------------------------------------------------- 6. restore
Restore-StartupLinks $startupLinks
if (Test-Path (Join-Path $backup 'Documents_Voicemeeter')) {
    # only brings back files that disappeared, never overwrites
    robocopy (Join-Path $backup 'Documents_Voicemeeter') $Docs /E /XC /XN /XO /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
}
# keep the last 3 backups
Get-ChildItem $Data -Directory -Filter 'backup_*' | Sort-Object Name -Descending | Select-Object -Skip 3 |
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

# ---------------------------------------------------------------- 7. restart
Log ''
Log 'Update done. ONE restart is needed to load the new audio driver.' Cyan
Ask-Restart "Voicemeeter $target $newVer has been installed.`n`nWindows must be restarted to finish the update (audio driver).`nSave your work first.`n`nRestart now?`n`nYes = restart now`nNo = restart later"
Done
