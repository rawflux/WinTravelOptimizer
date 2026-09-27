WinTravelOptimizer
==================

Declarative Windows 11 optimizer for a mobile RDP/SSH terminal laptop
(tuned for Chuwi MiniBook X N100): battery economy, background services,
telemetry and privacy, power plans for battery and AC.

Start:     double-click Start-WinTravelOptimizer.cmd (asks for administrator rights).
           Without parameters an interactive menu opens.
Install:   menu item 5 - copies the script to
           C:\Program Files\WinTravelOptimizer and creates shortcuts on the
           Desktop and in the Start Menu (they run as administrator).
Uninstall: menu item 6 - removes the copy and the shortcuts. Applied settings
           are kept; apply the Default profile first to roll them back.

Profiles:
  Travel        battery economy, background services and telemetry off,
                Windows Update paused, Defender real-time protection off
  RDP-Terminal  Travel + lighter UI effects for remote sessions
  Emergency     maximum battery saving, Bluetooth off
  FullPower     Travel on battery; on AC full performance, display always on,
                closing the lid does nothing
  Maintenance   Travel with Windows Update and Defender back on
  Default       Windows defaults (rollback)

Privacy layer (on by default, independent of the profile): telemetry limits,
no ads or suggestions, local-only search, no activity history, app access to
personal data denied, Edge and Office telemetry off.

Every change is verified by reading it back; "Status" shows settings that
Windows changed back since the profile was applied.

Command line (administrator PowerShell):
  .\WinTravelOptimizer.ps1                        menu
  .\WinTravelOptimizer.ps1 -Mode Travel           preview (no changes)
  .\WinTravelOptimizer.ps1 -Apply -Mode Travel    apply
  .\WinTravelOptimizer.ps1 -Status                check drift
  .\WinTravelOptimizer.ps1 -Apply -Mode Travel -Privacy Off
  .\WinTravelOptimizer.ps1 -Install | -Uninstall

Notes:
  - Removed built-in apps are not restored by Default; reinstall them from
    the Store or with winget if needed.
  - Defender settings do not apply while Tamper Protection is on.
  - State and log: C:\ProgramData\WinTravelOptimizer
