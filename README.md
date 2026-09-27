# WinTravelOptimizer

A declarative Windows 11 optimizer for a mobile laptop used as an RDP/SSH
terminal: battery economy, fewer background services, privacy settings, and
separate power behaviour on battery and on AC. Tuned on a Chuwi MiniBook X
(Intel N100), usable on any Windows 11 laptop.

One PowerShell script, no dependencies. License: [MIT](LICENSE).

## Quick start

1. Download `WinTravelOptimizer-<version>.zip` from Releases and unpack it.
2. Double-click **`Start-WinTravelOptimizer.cmd`** and confirm the UAC prompt.
3. In the menu choose **5 Install** to get Desktop and Start Menu shortcuts,
   then **3 Apply** and pick a profile. Every apply shows a preview of the
   changes first and asks for confirmation.

```
  ================================================================
    WinTravelOptimizer v3.7               battery | privacy | power
  ================================================================
   Profile: FullPower     Privacy: On    Power: AC, battery 100%
   Installed: yes

   [1] Status        check drift from the active profile
   [2] Preview       show what a profile would change
   [3] Apply         apply a profile (preview first, then confirm)
   [4] Privacy       turn the privacy layer on or off
   [5] Install       copy to Program Files, add Desktop and Start Menu shortcuts
   [6] Uninstall     remove the installed copy and shortcuts
   [7] Log           open the log file
   [Q] Quit
```

## Profiles

| Profile | What it does |
|---|---|
| **Travel** | Battery economy, background services and telemetry off, Windows Update paused, Defender real-time protection off, selected built-in apps removed |
| **RDP-Terminal** | Travel + lighter local UI effects (no transparency, animations or visual effects) |
| **Emergency** | Maximum battery saving: stronger CPU efficiency, turbo off, 30% brightness, Bluetooth off, shorter timeouts |
| **FullPower** | Travel on battery; on AC full performance: CPU performance preference and aggressive turbo, GPU and Wi-Fi at maximum performance, display never turns off, no sleep, closing the lid does nothing, opening it turns the display on |
| **Maintenance** | Travel with Windows Update, Store updates and Defender back on, Windows default power plan |
| **Default** | Windows default values: the rollback |

Profiles inherit from each other (RDP-Terminal, Emergency, FullPower and
Maintenance are based on Travel, Travel on Default), so each profile only
lists what differs.

**Privacy layer** (on by default, independent of the profile, `-Privacy On|Off`):
diagnostic data limits, no advertising ID, suggestions or consumer content,
local-only search, no activity history or cross-device features, location off,
app access to personal data (contacts, calendar, email, messages, call history,
account info, etc.) denied, error reports kept local, Edge and Office telemetry
off. Camera and microphone stay under user control. Location off means the
time zone is not set automatically.

## How it works

Every setting is described once in a table with a target value per profile:
services (start type), scheduled tasks, registry values (policies and user
settings), Defender preferences, the Bluetooth adapter. Power plans set
battery (DC) and AC values on top of the current scheme; profiles without a
plan restore the Windows default schemes.

- **Preview** compares the current value of every setting with the profile
  and lists only the differences.
- **Apply** changes only what differs and then reads each value back: a change
  counts as done only if it is really in place, otherwise it is reported as
  FAIL with the reason.
- **Status** compares the system with the applied profile and shows what
  Windows or other software changed back since then.
- **Default** returns everything the table touches to Windows defaults.
  Removed built-in apps are not reinstalled (use the Store or winget).

State and log: `C:\ProgramData\WinTravelOptimizer`.

## Command line

The script asks for administrator rights itself (UAC).

```powershell
.\WinTravelOptimizer.ps1                              # menu
.\WinTravelOptimizer.ps1 -Mode Travel                 # preview, no changes
.\WinTravelOptimizer.ps1 -Apply -Mode Travel          # apply (asks to confirm)
.\WinTravelOptimizer.ps1 -Apply -Mode Travel -NoConfirm
.\WinTravelOptimizer.ps1 -Status                      # drift from the applied profile
.\WinTravelOptimizer.ps1 -Apply -Mode Travel -Privacy Off
.\WinTravelOptimizer.ps1 -Install                     # Program Files + shortcuts
.\WinTravelOptimizer.ps1 -Uninstall                   # removes the copy and shortcuts
```

`-Install` copies the script to `C:\Program Files\WinTravelOptimizer` and
creates shortcuts on the public Desktop and in the Start Menu that run it as
administrator. `-Uninstall` removes them; applied settings stay (apply
`Default` first to roll them back).

## Please note

- Travel and the profiles based on it deliberately turn off Windows Update and
  Defender real-time protection to save battery and CPU. Use **Maintenance**
  regularly to install updates, and consider the security trade-off for your
  situation.
- Defender settings do not apply while Tamper Protection is on; the script
  warns about it.
- Some policies are honoured only on Pro/Enterprise/Education editions (for
  example the lowest diagnostic data level).
- The script changes system-wide settings. Preview first; `Default` is the
  rollback. Provided as is, without warranty (see [LICENSE](LICENSE)).

## Building the release archive

```sh
./bundle.sh   # -> bin/WinTravelOptimizer-<version>.zip and bin/SHA256SUMS
```

The archive contains `WinTravelOptimizer.ps1`, `Start-WinTravelOptimizer.cmd`,
`README.txt` and `LICENSE`.
