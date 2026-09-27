<#
WinTravelOptimizer.ps1 v3.7
Declarative Windows 11 optimizer for a mobile RDP/SSH terminal.
Target: Chuwi Minibook X N100 | KISS principle

Every setting is described once in $Settings with a target value per profile.
Profiles inherit missing values: RDP-Terminal, Emergency, FullPower, Maintenance -> Travel -> Default.
FullPower = Travel on battery, full performance on AC (no display off, no sleep, lid ignored).
Default = stock Windows values, so applying it is the rollback.
Removed AppX packages are not restored (reinstall via Store/winget when needed).
Defender and Windows Update are switched off on purpose in Travel and its children.
Privacy hardening is a separate layer (-Privacy On|Off), independent of the profile and
remembered between runs; Off returns those settings to Windows defaults.

Usage:
    Menu:            .\WinTravelOptimizer.ps1   (no parameters; or Start-WinTravelOptimizer.cmd, or the shortcut)
    Install:         .\WinTravelOptimizer.ps1 -Install    (Program Files + Desktop/Start Menu shortcuts)
    Uninstall:       .\WinTravelOptimizer.ps1 -Uninstall  (removes the copy and shortcuts, keeps settings)
    Dry run (diff):  .\WinTravelOptimizer.ps1 -Mode Travel
    Apply:           .\WinTravelOptimizer.ps1 -Apply -Mode Travel
    Silent:          .\WinTravelOptimizer.ps1 -Apply -Mode Travel -NoConfirm
    Rollback:        .\WinTravelOptimizer.ps1 -Apply -Mode Default
    Status (drift):  .\WinTravelOptimizer.ps1 -Status
    Privacy layer:   .\WinTravelOptimizer.ps1 -Apply -Mode Travel -Privacy On

Profiles: Travel | RDP-Terminal | Emergency | FullPower | Maintenance | Default
#>

param(
    [switch]$Apply,
    [switch]$NoConfirm,
    [switch]$Status,
    [ValidateSet('Travel', 'RDP-Terminal', 'Emergency', 'FullPower', 'Maintenance', 'Default')]
    [string]$Mode = 'Travel',
    [ValidateSet('On', 'Off')]
    [string]$Privacy,
    [switch]$Install,
    [switch]$Uninstall
)

# Elevate: restart as administrator with the same parameters (UAC prompt).
$me = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (!$me.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
    foreach ($k in $PSBoundParameters.Keys) {
        $v = $PSBoundParameters[$k]
        if ($v -is [switch]) { if ($v) { $argList += "-$k" } } else { $argList += "-$k", "`"$v`"" }
    }
    try { Start-Process powershell.exe -Verb RunAs -ArgumentList $argList } catch { Write-Host 'Administrator rights are required.' -ForegroundColor Red; Start-Sleep 3 }
    exit
}

$Version = '3.7'
$Root = "$env:ProgramData\WinTravelOptimizer"
$LogFile = "$Root\optimizer.log"
$StateFile = "$Root\profile.json"
if (!(Test-Path $Root)) { New-Item -ItemType Directory -Path $Root -Force | Out-Null }

$Absent = '<absent>'
$Parent = @{ 'RDP-Terminal' = 'Travel'; Emergency = 'Travel'; FullPower = 'Travel'; Maintenance = 'Travel'; Travel = 'Default' }

# Helpers
function Log($Msg) { Add-Content -Path $LogFile -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | $Msg" -Encoding UTF8 }
function info($Msg) { Write-Host $Msg -ForegroundColor Cyan }
function ok($Msg) { Write-Host $Msg -ForegroundColor Green }
function warn($Msg) { Write-Host $Msg -ForegroundColor Yellow }
function err($Msg) { Write-Host $Msg -ForegroundColor Red }
function dim($Msg) { Write-Host $Msg -ForegroundColor DarkGray }

function Confirm-Step($Question, [bool]$Default = $true) {
    if ($NoConfirm) { return $Default }
    $p = if ($Default) { '[Y/n]' } else { '[y/N]' }
    $r = Read-Host "$Question $p"
    if ([string]::IsNullOrWhiteSpace($r)) { return $Default }
    return $r.ToLower() -eq 'y'
}

function Fmt($v) {
    if ($null -eq $v) { return '<none>' }
    "$v"
}

# ============================================
# SETTINGS TABLE
# ============================================
# Value per profile; a missing profile inherits from its parent.
# Windows does not ship some values (edition/OOBE dependent): there Default = $null lets Windows decide.
# reg: $null = value must not exist. svc: Automatic | AutomaticDelayed | Manual | Disabled.
function Svc($Name, $V) { @{ Kind = 'svc'; Id = $Name; V = $V } }
function Tsk($Path, $V) { @{ Kind = 'task'; Id = $Path; V = $V } }
function Reg($Path, $Name, $V, $Type = 'DWord') { @{ Kind = 'reg'; Id = "$Path\$Name"; Path = $Path; Name = $Name; Type = $Type; V = $V } }
function MpPref($Name, $V) { @{ Kind = 'mp'; Id = $Name; V = $V } }
function Dev($Class, $V) { @{ Kind = 'dev'; Id = $Class; V = $V } }

# Disabled from Travel on; value = Windows default start type
$OffServices = [ordered]@{
    XboxGipSvc = 'Manual'; XblAuthManager = 'Manual'; XblGameSave = 'Manual'; XboxNetApiSvc = 'Manual'
    WSearch = 'AutomaticDelayed'
    MapsBroker = 'AutomaticDelayed'
    ClickToRunSvc = 'Automatic'
    edgeupdate = 'AutomaticDelayed'; edgeupdatem = 'Manual'
    WerSvc = 'Manual'; Fax = 'Manual'; RetailDemo = 'Manual'; PhoneSvc = 'Manual'; WalletService = 'Manual'
    WMPNetworkSvc = 'Manual'; Spooler = 'Automatic'; WbioSrvc = 'Manual'
}

# Disabled in Travel, back to default in Maintenance
$UpdateServices = [ordered]@{ wuauserv = 'Manual'; UsoSvc = 'AutomaticDelayed'; BITS = 'Manual' }

$OffTasks = @(
    '\Microsoft\Windows\Maps\MapsUpdateTask'
    '\Microsoft\Office\Office Automatic Updates 2.0'
    '\Microsoft\Office\Office Feature Updates'
    '\Microsoft\Office\Office Feature Updates Logon'
)

$UpdateTasks = @(
    '\Microsoft\Windows\WindowsUpdate\Scheduled Start'
    '\Microsoft\Windows\Windows Defender\Windows Defender Scheduled Scan'
)

$Pol = 'HKLM:\SOFTWARE\Policies\Microsoft'
$Cv = 'HKCU:\Software\Microsoft\Windows\CurrentVersion'
$Ux = 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'
$PauseFrom = '2026-01-01T00:00:00Z'
$PauseTill = '2046-01-01T00:00:00Z'

$Settings = @(
    foreach ($n in $OffServices.Keys) { Svc $n @{ Travel = 'Disabled'; Default = $OffServices[$n] } }
    foreach ($n in $UpdateServices.Keys) { Svc $n @{ Travel = 'Disabled'; Maintenance = $UpdateServices[$n]; Default = $UpdateServices[$n] } }
    foreach ($t in $OffTasks) { Tsk $t @{ Travel = 'Disabled'; Default = 'Enabled' } }
    foreach ($t in $UpdateTasks) { Tsk $t @{ Travel = 'Disabled'; Maintenance = 'Enabled'; Default = 'Enabled' } }

    # Background activity
    Reg "$Pol\Windows\AppPrivacy" 'LetAppsRunInBackground' @{ Travel = 2; Default = $null }
    Reg "$Pol\Dsh" 'AllowNewsAndInterests' @{ Travel = 0; Default = $null }
    Reg "$Pol\Edge" 'StartupBoostEnabled' @{ Travel = 0; Default = $null }
    Reg "$Pol\Edge" 'BackgroundModeEnabled' @{ Travel = 0; Default = $null }
    Reg "$Pol\Windows\OneDrive" 'DisableFileSyncNGSC' @{ Travel = 1; Default = $null }
    Reg "$Pol\Windows\GameDVR" 'AllowGameDVR' @{ Travel = 0; Default = $null }
    Reg 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' @{ Travel = 0; Default = 1 }
    Reg 'HKCU:\Software\Microsoft\Office\16.0\Common\General' 'PreloadApp' @{ Travel = 0; Default = $null }
    Reg 'HKCU:\Software\Microsoft\Office\16.0\Common\General' 'DisableBootToOfficeStart' @{ Travel = 1; Default = $null }

    # Network traffic on mobile links: no P2P update sharing, no Store auto-updates
    Reg "$Pol\Windows\DeliveryOptimization" 'DODownloadMode' @{ Travel = 0; Default = $null }
    Reg "$Pol\WindowsStore" 'AutoDownload' @{ Travel = 2; Maintenance = $null; Default = $null }

    # Windows Update: policy (Pro+) and pause (works on Home too)
    Reg "$Pol\Windows\WindowsUpdate\AU" 'NoAutoUpdate' @{ Travel = 1; Maintenance = $null; Default = $null }
    Reg $Ux 'FlightSettingsMaxPauseDays' @{ Travel = 7300; Maintenance = $null; Default = $null }
    foreach ($kind in 'Updates', 'FeatureUpdates', 'QualityUpdates') {
        Reg $Ux "Pause$($kind)StartTime" @{ Travel = $PauseFrom; Maintenance = $null; Default = $null } 'String'
    }
    Reg $Ux 'PauseUpdatesExpiryTime' @{ Travel = $PauseTill; Maintenance = $null; Default = $null } 'String'
    Reg $Ux 'PauseFeatureUpdatesEndTime' @{ Travel = $PauseTill; Maintenance = $null; Default = $null } 'String'
    Reg $Ux 'PauseQualityUpdatesEndTime' @{ Travel = $PauseTill; Maintenance = $null; Default = $null } 'String'

    # Defender (blocked while Tamper Protection is on)
    MpPref 'DisableRealtimeMonitoring' @{ Travel = $true; Maintenance = $false; Default = $false }
    MpPref 'MAPSReporting' @{ Travel = 0; Maintenance = 2; Default = 2 }
    MpPref 'SubmitSamplesConsent' @{ Travel = 2; Maintenance = 1; Default = 1 }
    Reg "$Pol\Windows Defender\Real-Time Protection" 'DisableRealtimeMonitoring' @{ Travel = 1; Maintenance = $null; Default = $null }

    # Local UI effects (RDP-Terminal only, apply after sign-out)
    Reg "$Cv\Explorer\VisualEffects" 'VisualFXSetting' @{ 'RDP-Terminal' = 2; Default = $null }
    Reg "$Cv\Themes\Personalize" 'EnableTransparency' @{ 'RDP-Terminal' = 0; Default = 1 }
    Reg 'HKCU:\Control Panel\Desktop\WindowMetrics' 'MinAnimate' @{ 'RDP-Terminal' = '0'; Default = '1' } 'String'

    # Radios
    Dev 'Bluetooth' @{ Emergency = 'Off'; Default = 'On' }
)

# ============================================
# PRIVACY LAYER (-Privacy On|Off, independent of the profile)
# ============================================
# Entries carry only Privacy/Default values. Policies are fully honoured on Enterprise/Education;
# Home/Pro ignore some of them (e.g. AllowTelemetry=0 acts as 1).
# Location is off entirely: automatic time zone will not work while Privacy is On.
function Priv($Path, $Values, $Type = 'DWord') { foreach ($n in $Values.Keys) { Reg $Path $n @{ Privacy = $Values[$n]; Default = $null } $Type } }

$PrivacyServices = [ordered]@{ DiagTrack = 'Automatic'; dmwappushservice = 'Manual' }

$PrivacyTasks = @(
    '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser'
    '\Microsoft\Windows\Application Experience\ProgramDataUpdater'
    '\Microsoft\Windows\Autochk\Proxy'
    '\Microsoft\Windows\Customer Experience Improvement Program\Consolidator'
    '\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip'
    '\Microsoft\Windows\Feedback\Siuf\DmClient'
    '\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload'
    '\Microsoft\Office\OfficeTelemetryAgentLogOn2016'
    '\Microsoft\Office\OfficeTelemetryAgentFallBack2016'
)

$HkcuPol = 'HKCU:\Software\Policies\Microsoft'

$Settings += @(
    foreach ($n in $PrivacyServices.Keys) { Svc $n @{ Privacy = 'Disabled'; Default = $PrivacyServices[$n] } }
    foreach ($t in $PrivacyTasks) { Tsk $t @{ Privacy = 'Disabled'; Default = 'Enabled' } }

    # Telemetry and diagnostics
    Priv "$Pol\Windows\DataCollection" ([ordered]@{
        AllowTelemetry = 0; AllowDeviceNameInTelemetry = 0; DisableOneSettingsDownloads = 1
        DoNotShowFeedbackNotifications = 1; DisableTelemetryOptInChangeNotification = 1
        LimitDiagnosticLogCollection = 1; LimitDumpCollection = 1
    })
    Priv "$Pol\Windows\AppCompat" ([ordered]@{ AITEnable = 0; DisableInventory = 1; DisableUAR = 1 })
    # Error reports stay local (Reliability Monitor, WER archive); nothing is sent without asking
    Priv "$Pol\Windows\Windows Error Reporting" @{ DontSendAdditionalData = 1 }
    Priv "$Pol\Windows\Windows Error Reporting\Consent" @{ DefaultConsent = 1 }
    Priv "$Pol\Windows\HandwritingErrorReports" @{ PreventHandwritingErrorReports = 1 }
    Priv "$Pol\MRT" @{ DontReportInfectionInformation = 1 }
    Priv "$Pol\Windows\OOBE" @{ DisablePrivacyExperience = 1 }

    # Ads, suggestions, consumer content
    Priv "$Pol\Windows\AdvertisingInfo" @{ DisabledByGroupPolicy = 1 }
    Priv "$Pol\Windows\CloudContent" ([ordered]@{
        DisableWindowsConsumerFeatures = 1; DisableSoftLanding = 1
        DisableCloudOptimizedContent = 1; DisableConsumerAccountStateContent = 1
    })
    Priv "$HkcuPol\Windows\CloudContent" ([ordered]@{ DisableTailoredExperiencesWithDiagnosticData = 1; DisableWindowsSpotlightFeatures = 1 })
    Reg "$Cv\AdvertisingInfo" 'Enabled' @{ Privacy = 0; Default = $null }
    Reg "$Cv\ContentDeliveryManager" 'SilentInstalledAppsEnabled' @{ Privacy = 0; Default = $null }
    Reg "$Cv\ContentDeliveryManager" 'SystemPaneSuggestionsEnabled' @{ Privacy = 0; Default = $null }

    # Search: local only
    Priv "$Pol\Windows\Windows Search" ([ordered]@{
        AllowCortana = 0; AllowCloudSearch = 0; AllowSearchToUseLocation = 0; DisableWebSearch = 1; ConnectedSearchUseWeb = 0
    })
    Priv "$HkcuPol\Windows\Explorer" @{ DisableSearchBoxSuggestions = 1 }
    Reg "$Cv\Search" 'BingSearchEnabled' @{ Privacy = 0; Default = $null }

    # Activity history, cross-device, location, input
    Priv "$Pol\Windows\System" ([ordered]@{
        EnableActivityFeed = 0; PublishUserActivities = 0; UploadUserActivities = 0; AllowCrossDeviceClipboard = 0; EnableCdp = 0
    })
    Priv "$Pol\Windows\LocationAndSensors" ([ordered]@{ DisableLocation = 1; DisableWindowsLocationProvider = 1; DisableLocationScripting = 1 })
    Priv "$Pol\Windows\Messaging" @{ AllowMessageSync = 0 }
    Priv "$Pol\InputPersonalization" @{ AllowInputPersonalization = 0 }
    Priv "$Pol\Windows\TabletPC" @{ PreventHandwritingDataSharing = 1 }
    Priv "$Pol\Speech" @{ AllowSpeechModelUpdate = 0 }

    # App access to personal data (2 = force deny); camera and microphone stay user-controlled
    Priv "$Pol\Windows\AppPrivacy" ([ordered]@{
        LetAppsAccessAccountInfo = 2; LetAppsAccessCalendar = 2; LetAppsAccessCallHistory = 2; LetAppsAccessContacts = 2
        LetAppsAccessEmail = 2; LetAppsAccessMessaging = 2; LetAppsAccessPhone = 2; LetAppsAccessTasks = 2
        LetAppsAccessMotion = 2; LetAppsGetDiagnosticInfo = 2; LetAppsActivateWithVoice = 2
    })

    # Edge
    Priv "$Pol\Edge" ([ordered]@{
        DiagnosticData = 0; PersonalizationReportingEnabled = 0; UserFeedbackAllowed = 0
        EdgeShoppingAssistantEnabled = 0; ShowMicrosoftRewards = 0
    })

    # Office
    Priv "$HkcuPol\Office\16.0\Common" ([ordered]@{ QMEnable = 0; LinkedIn = 0 })
    Priv "$HkcuPol\Office\16.0\Common\Feedback" ([ordered]@{ Enabled = 0; SurveyEnabled = 0; IncludeEmail = 0 })
    Priv "$HkcuPol\Office\16.0\Common\Privacy" @{ ControllerConnectedServicesEnabled = 2 }
    Priv "$HkcuPol\Office\16.0\osm" ([ordered]@{ Enablelogging = 0; EnableUpload = 0; EnableFileObfuscation = 1 })
    Priv "$HkcuPol\Office\Common\ClientTelemetry" ([ordered]@{ SendTelemetry = 3; DisableTelemetry = 1 })
)

# ============================================
# POWER PLANS (values on top of the current scheme)
# ============================================
# Keys are battery (DC) values; "AC." keys are values on mains power.
# Profiles without a plan get Windows default schemes back (powercfg /restoredefaultschemes).
$PowerKeys = @{
    EnergySaverAt   = 'SUB_ENERGYSAVER ESBATTTHRESHOLD'                                                # % battery
    CpuEpp          = 'SUB_PROCESSOR PERFEPP'                                                          # 0 perf .. 100 efficiency
    CpuBoost        = 'SUB_PROCESSOR PERFBOOSTMODE'                                                    # 0 off, 1 on, 2 aggressive
    Gpu             = '44f3beca-a7c0-460e-9df2-bb8b99e0cba6 3619c3f2-afb2-4afc-b0e9-e7fef372de36'      # Intel: 0 max battery, 2 max performance
    Wifi            = '19cbb8fa-5279-450e-9fac-8a3d5fedd0c1 12bbebe6-58d6-4636-95bb-3217ef867c1a'      # 0 max performance, 3 max saving
    StandbyNetwork  = 'fea3413e-7e05-4911-9a71-700331f1c294 f15576e8-98b7-4186-b944-eafa664402d9'      # 0 disconnect
    Brightness      = '7516b95f-f776-4464-8c53-06167f40cc99 aded5e82-b909-4619-9949-f5d71dac0bcb'      # %
    WakeTimers      = 'SUB_SLEEP RTCWAKE'
    Lid             = 'SUB_BUTTONS LIDACTION'                                                          # 0 nothing, 1 sleep, 2 hibernate
    LidOpen         = '4f971e89-eebd-4455-a8de-9e59040e7347 99ff10e7-23b1-4c07-a9d1-5c3206d741b4'      # 1 turn on the display
    DisplayOff      = 'SUB_VIDEO VIDEOIDLE'                                                            # seconds, 0 never
    Sleep           = 'SUB_SLEEP STANDBYIDLE'
    Hibernate       = 'SUB_SLEEP HIBERNATEIDLE'
}

$PowerPlans = @{
    Travel = [ordered]@{
        EnergySaverAt = 30; CpuEpp = 70; Gpu = 0; Wifi = 3; StandbyNetwork = 0; WakeTimers = 0
        Lid = 2; DisplayOff = 180; Sleep = 300; Hibernate = 600
    }
    Emergency = [ordered]@{
        EnergySaverAt = 100; CpuEpp = 90; CpuBoost = 0; Gpu = 0; Wifi = 3; StandbyNetwork = 0; WakeTimers = 0
        Brightness = 30; Lid = 2; DisplayOff = 60; Sleep = 180; Hibernate = 300
    }
    FullPower = [ordered]@{
        EnergySaverAt = 30; CpuEpp = 70; Gpu = 0; Wifi = 3; StandbyNetwork = 0; WakeTimers = 0
        Lid = 2; LidOpen = 1; DisplayOff = 180; Sleep = 300; Hibernate = 600
        'AC.CpuEpp' = 0; 'AC.CpuBoost' = 2; 'AC.Gpu' = 2; 'AC.Wifi' = 0
        'AC.Lid' = 0; 'AC.LidOpen' = 1; 'AC.DisplayOff' = 0; 'AC.Sleep' = 0; 'AC.Hibernate' = 0
    }
}
$PowerOf = @{ Travel = 'Travel'; 'RDP-Terminal' = 'Travel'; Emergency = 'Emergency'; FullPower = 'FullPower' }

# ============================================
# APPX (removed in every profile except Default, never restored)
# ============================================
$AppxPatterns = @(
    'Microsoft.Xbox*', 'Microsoft.GamingApp', 'Microsoft.BingNews', 'Microsoft.BingWeather',
    'Microsoft.GetHelp', 'Microsoft.Getstarted', 'Microsoft.People', 'Microsoft.WindowsMaps',
    'Microsoft.YourPhone', 'Microsoft.ZuneMusic', 'Microsoft.ZuneVideo',
    'Microsoft.MicrosoftSolitaireCollection', 'Clipchamp.Clipchamp', 'Microsoft.MicrosoftOfficeHub',
    'MSTeams', 'Microsoft.Teams', 'Microsoft.Copilot', 'Microsoft.549981C3F5F10',
    'Microsoft.WindowsFeedbackHub', 'Microsoft.PowerAutomateDesktop'
)

# ============================================
# ENGINE
# ============================================
function Get-Target($e) {
    if ($e.V.Contains('Privacy')) { if ($PrivacyOn) { return $e.V['Privacy'] } else { return $e.V['Default'] } }
    $m = $Mode
    while ($m) {
        if ($e.V.Contains($m)) { return $e.V[$m] }
        $m = $Parent[$m]
    }
}

function Split-TaskPath($p) {
    $i = $p.LastIndexOf('\')
    @{ Folder = $p.Substring(0, $i + 1); Name = $p.Substring($i + 1) }
}

function Get-Current($e) {
    switch ($e.Kind) {
        'svc' {
            $s = Get-CimInstance Win32_Service -Filter "Name='$($e.Id)'" -ErrorAction SilentlyContinue
            if (!$s) { return $Absent }
            if ($s.StartMode -eq 'Auto') { if ($s.DelayedAutoStart) { return 'AutomaticDelayed' } else { return 'Automatic' } }
            return "$($s.StartMode)"
        }
        'task' {
            $p = Split-TaskPath $e.Id
            $t = Get-ScheduledTask -TaskPath $p.Folder -TaskName $p.Name -ErrorAction SilentlyContinue
            if (!$t) { return $Absent }
            if ($t.State -eq 'Disabled') { return 'Disabled' } else { return 'Enabled' }
        }
        'reg' {
            $v = (Get-ItemProperty -Path $e.Path -Name $e.Name -ErrorAction SilentlyContinue).($e.Name)
            if ($v -is [byte[]]) { return (($v | ForEach-Object { $_.ToString('X2') }) -join '') }
            return $v
        }
        'mp' {
            $mp = Get-MpPreference -ErrorAction SilentlyContinue
            if (!$mp) { return $Absent }
            return "$($mp.($e.Id))"
        }
        'dev' {
            $d = @(Get-PnpDevice -Class $e.Id -PresentOnly -ErrorAction SilentlyContinue)
            if (!$d) { return $Absent }
            if (@($d | Where-Object { $_.ConfigManagerErrorCode -ne 22 }).Count) { return 'On' } else { return 'Off' }
        }
    }
}

function Set-Value($e, $v) {
    switch ($e.Kind) {
        'svc' {
            $start = @{ Automatic = 'auto'; AutomaticDelayed = 'delayed-auto'; Manual = 'demand'; Disabled = 'disabled' }[$v]
            if ($v -eq 'Disabled') { Stop-Service $e.Id -Force -ErrorAction SilentlyContinue }
            $out = sc.exe config $e.Id start= $start 2>&1
            if ($LASTEXITCODE) { throw ($out -join ' ').Trim() }
            if ($v -like 'Automatic*') { Start-Service $e.Id -ErrorAction SilentlyContinue }
        }
        'task' {
            $p = Split-TaskPath $e.Id
            if ($v -eq 'Disabled') { Disable-ScheduledTask -TaskPath $p.Folder -TaskName $p.Name -ErrorAction Stop | Out-Null }
            else { Enable-ScheduledTask -TaskPath $p.Folder -TaskName $p.Name -ErrorAction Stop | Out-Null }
        }
        'reg' {
            if ($null -eq $v) { Remove-ItemProperty -Path $e.Path -Name $e.Name -ErrorAction SilentlyContinue; return }
            if (!(Test-Path $e.Path)) { New-Item -Path $e.Path -Force | Out-Null }
            $data = $v
            if ($e.Type -eq 'Binary') { $data = [byte[]]($v -split '(..)' -ne '' | ForEach-Object { [Convert]::ToByte($_, 16) }) }
            New-ItemProperty -Path $e.Path -Name $e.Name -Value $data -PropertyType $e.Type -Force -ErrorAction Stop | Out-Null
        }
        'mp' {
            $arg = @{ $e.Id = $v }
            Set-MpPreference @arg -ErrorAction Stop
        }
        'dev' {
            $d = Get-PnpDevice -Class $e.Id -PresentOnly -ErrorAction Stop
            if ($v -eq 'Off') { $d | Where-Object { $_.ConfigManagerErrorCode -ne 22 } | Disable-PnpDevice -Confirm:$false -ErrorAction Stop }
            else { $d | Where-Object { $_.ConfigManagerErrorCode -eq 22 } | Enable-PnpDevice -Confirm:$false -ErrorAction Stop }
        }
    }
}

# Compare, then (apply mode) change and verify by reading back. Only verified changes count as done.
function Sync($Label, $From, $To, [scriptblock]$SetBlock, [scriptblock]$GetBlock) {
    if ((Fmt $From) -eq (Fmt $To)) { return }
    $line = "$Label : $(Fmt $From) -> $(Fmt $To)"
    $script:Diff++
    if ($Run -eq 'status') { warn "DRIFT $line"; return }
    if ($Run -eq 'dry') { warn "WOULD $line"; return }
    $why = $null
    try { & $SetBlock } catch { $why = $_.Exception.Message }
    $now = & $GetBlock
    if ((Fmt $now) -eq (Fmt $To)) {
        ok "SET   $line"; Log "OK: $line"; $script:Changed++
    } else {
        if (!$why) { $why = "still $(Fmt $now)" }
        err "FAIL  $line ($why)"; Log "FAIL: $line - $why"; $script:Failed++
    }
}

function Invoke-Settings {
    info '--- Settings ---'
    $missing = 0
    foreach ($e in $Settings) {
        $want = Get-Target $e
        $have = Get-Current $e
        if ("$have" -eq $Absent) { $missing++; continue }
        Sync "$($e.Kind) $($e.Id)" $have $want { Set-Value $e $want } { Get-Current $e }
    }
    if ($missing) { dim "($missing items not present on this system, skipped)" }
}

function Get-PowerValue($Key, [bool]$Ac) {
    $sub, $set = $Key -split ' '
    $out = powercfg /qh SCHEME_CURRENT $sub $set 2>$null
    # The last two hex indexes in the output are the AC and DC values (locale independent)
    $m = [regex]::Matches(($out -join "`n"), '0x[0-9a-fA-F]{8}')
    if ($LASTEXITCODE -or $m.Count -lt 2) { return $Absent }
    [Convert]::ToInt32($m[$m.Count - $(if ($Ac) { 2 } else { 1 })].Value, 16)
}

function Set-PowerValue($Key, $Value, [bool]$Ac) {
    $sub, $set = $Key -split ' '
    $verb = if ($Ac) { '/setacvalueindex' } else { '/setdcvalueindex' }
    $out = powercfg $verb SCHEME_CURRENT $sub $set $Value 2>&1
    if ($LASTEXITCODE) { throw ($out -join ' ').Trim() }
    powercfg /setactive SCHEME_CURRENT | Out-Null
}

function Get-Hibernation { (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' -ErrorAction SilentlyContinue).HibernateEnabled }

function Reset-Power {
    $out = powercfg /restoredefaultschemes 2>&1
    if ($LASTEXITCODE) { err "FAIL  power: restore default schemes ($out)"; Log "FAIL: power defaults - $out"; $script:Failed++ }
    else { ok 'SET   power: Windows default schemes restored'; Log 'OK: power defaults'; $script:Changed++ }
}

function Invoke-Power {
    info '--- Power ---'
    if (!$PowerOf.Contains($Mode)) {
        if ($Run -eq 'apply') { Reset-Power } else { dim 'power: Windows default schemes (not compared)' }
        return
    }
    # Switching between plans: start from defaults so keys of the previous plan do not linger
    $prev = if ($Recorded) { $PowerOf[$Recorded.Profile] } else { $null }
    if ($Recorded -and $prev -ne $PowerOf[$Mode]) {
        if ($Run -eq 'apply') { Reset-Power } else { dim 'power: default schemes will be restored first' }
    }
    Sync 'power Hibernation' (Get-Hibernation) 1 { powercfg /hibernate on 2>&1 | Out-Null } { Get-Hibernation }
    $plan = $PowerPlans[$PowerOf[$Mode]]
    foreach ($k in $plan.Keys) {
        $ac = $k -like 'AC.*'
        $name = $k -replace '^AC\.', ''
        $label = if ($ac) { "power AC $name" } else { "power DC $name" }
        $key = $PowerKeys[$name]
        $have = Get-PowerValue $key $ac
        if ("$have" -eq $Absent) { dim "($label not readable here, skipped)"; continue }
        $want = $plan[$k]
        Sync $label $have $want { Set-PowerValue $key $want $ac } { Get-PowerValue $key $ac }
    }
}

function Test-Bloat($Name) {
    foreach ($p in $AppxPatterns) { if ($Name -like $p) { return $true } }
    $false
}

# Removal for all users finishes asynchronously: poll for up to 15 seconds.
function Wait-AppxGone($p) {
    for ($i = 0; $i -lt 15; $i++) {
        if (!(Get-AppxPackage -AllUsers -Name $p.Name | Where-Object { $_.PackageFullName -eq $p.PackageFullName })) { return 'removed' }
        Start-Sleep 1
    }
    'installed'
}

function Invoke-Appx {
    info '--- AppX ---'
    if ($Mode -eq 'Default') { dim 'appx: not managed in Default (reinstall removed apps via Store/winget)'; return }
    foreach ($p in @(Get-AppxPackage -AllUsers | Where-Object { !$_.NonRemovable -and (Test-Bloat $_.Name) })) {
        Sync "appx $($p.Name)" 'installed' 'removed' `
            { Remove-AppxPackage -Package $p.PackageFullName -AllUsers -ErrorAction Stop } `
            { Wait-AppxGone $p }
    }
    foreach ($p in @(Get-AppxProvisionedPackage -Online | Where-Object { Test-Bloat $_.DisplayName })) {
        Sync "appx-provisioned $($p.DisplayName)" 'provisioned' 'removed' `
            { Remove-AppxProvisionedPackage -Online -PackageName $p.PackageName -ErrorAction Stop | Out-Null } `
            { if (Get-AppxProvisionedPackage -Online | Where-Object { $_.PackageName -eq $p.PackageName }) { 'provisioned' } else { 'removed' } }
    }
}

# ============================================
# MAIN
# ============================================
$InstallDir = "$env:ProgramFiles\WinTravelOptimizer"
$Shortcuts = @(
    (Join-Path ([Environment]::GetFolderPath('CommonDesktopDirectory')) 'WinTravelOptimizer.lnk')
    (Join-Path ([Environment]::GetFolderPath('CommonPrograms')) 'WinTravelOptimizer.lnk')
)

function Get-Recorded {
    if (Test-Path $StateFile) { return Get-Content $StateFile -Raw | ConvertFrom-Json }
    $null
}

# One run over the whole table: 'status', 'dry' or 'apply'. Results: $script:Diff, $script:Changed, $script:Failed.
function Invoke-Optimizer($RunMode, $ProfileName, $PrivacyChoice) {
    $script:Recorded = Get-Recorded
    $script:Run = $RunMode
    $script:Mode = $ProfileName
    $script:PrivacyOn = $true
    if ($PrivacyChoice) { $script:PrivacyOn = $PrivacyChoice -eq 'On' }
    elseif ($Recorded -and $Recorded.Privacy) { $script:PrivacyOn = $Recorded.Privacy -eq 'On' }
    $script:PrivacyText = if ($PrivacyOn) { 'On' } else { 'Off' }
    $script:Diff = 0; $script:Changed = 0; $script:Failed = 0

    Write-Host "`n===== WinTravelOptimizer v$Version =====" -ForegroundColor Cyan
    Write-Host "Mode: $($Run.ToUpper()) | Profile: $Mode | Privacy: $PrivacyText" -ForegroundColor $(if ($Run -eq 'apply') { 'Yellow' } else { 'Green' })
    if ($Recorded) { dim "Recorded: $($Recorded.Profile), privacy $($Recorded.Privacy) (applied $($Recorded.Date), v$($Recorded.Version))" }
    Write-Host ''

    $rt = $Settings | Where-Object { $_.Kind -eq 'mp' -and $_.Id -eq 'DisableRealtimeMonitoring' }
    if ((Get-Target $rt) -and (Get-MpComputerStatus -ErrorAction SilentlyContinue).IsTamperProtected) {
        warn 'Tamper Protection is ON: Defender settings will not apply.'
        warn 'Turn it off: Windows Security > Virus & threat protection > Manage settings.'
        Write-Host ''
    }

    Invoke-Settings
    Invoke-Power
    Invoke-Appx
    Write-Host ''

    switch ($Run) {
        'apply' {
            @{ Profile = $Mode; Privacy = $PrivacyText; Date = (Get-Date -Format 's'); Version = $Version } | ConvertTo-Json | Set-Content $StateFile
            if ($Failed) { warn "Profile '$Mode' applied with errors: $Changed changed, $Failed failed (see $LogFile)" }
            else { ok "Profile '$Mode' applied: $Changed changed" }
            dim 'Visual effects apply after sign-out; services and policies are fully in effect after reboot.'
        }
        'dry' {
            if ($Diff) { warn "$Diff changes planned." } else { ok "System already matches '$Mode'." }
        }
        'status' {
            if ($Diff) { warn "$Diff settings drifted from '$Mode'. Re-apply to fix." } else { ok "System matches '$Mode'." }
            Write-Host ''
            info 'Active power requests:'
            powercfg /requests 2>$null | Out-Host
        }
    }
    Log "Done: Run=$Run Profile=$Mode Diff=$Diff Changed=$Changed Failed=$Failed"
}

# ============================================
# INSTALL / UNINSTALL
# ============================================
function Install-Self {
    $target = Join-Path $InstallDir 'WinTravelOptimizer.ps1'
    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
    if ($PSCommandPath -ne $target) { Copy-Item $PSCommandPath $target -Force }
    $icon = "$env:SystemRoot\System32\powercpl.dll,0"
    if (!(Test-Path "$env:SystemRoot\System32\powercpl.dll")) { $icon = "$env:SystemRoot\System32\shell32.dll,43" }
    $shell = New-Object -ComObject WScript.Shell
    foreach ($lnk in $Shortcuts) {
        $sc = $shell.CreateShortcut($lnk)
        $sc.TargetPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
        $sc.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$target`""
        $sc.WorkingDirectory = $InstallDir
        $sc.IconLocation = $icon
        $sc.Description = 'WinTravelOptimizer: battery, privacy and performance profiles'
        $sc.Save()
        # "Run as administrator" flag of the shell link (byte 0x15, bit 0x20): no second window on start.
        $b = [IO.File]::ReadAllBytes($lnk)
        $b[0x15] = $b[0x15] -bor 0x20
        [IO.File]::WriteAllBytes($lnk, $b)
        ok "  shortcut: $lnk"
    }
    ok "Installed to $target"
    Log "Installed to $target"
}

function Uninstall-Self {
    foreach ($lnk in $Shortcuts) { if (Test-Path $lnk) { Remove-Item $lnk -Force; ok "  removed: $lnk" } }
    if (Test-Path $InstallDir) { Remove-Item $InstallDir -Recurse -Force; ok "  removed: $InstallDir" }
    ok 'Uninstalled. Applied settings are kept; apply the Default profile first to roll them back.'
    dim "State and log stay in $Root"
    Log 'Uninstalled'
}

# ============================================
# MENU
# ============================================
$ProfileInfo = [ordered]@{
    'Travel'       = 'battery economy, background services and telemetry off, updates paused'
    'RDP-Terminal' = 'Travel + lighter UI effects for remote sessions'
    'Emergency'    = 'maximum battery saving, Bluetooth off'
    'FullPower'    = 'Travel on battery; on AC full performance, display always on, lid ignored'
    'Maintenance'  = 'Travel with Windows Update and Defender back on'
    'Default'      = 'Windows defaults (rollback)'
}

function Show-Banner {
    Clear-Host
    $line = '=' * 64
    Write-Host ''
    Write-Host "  $line" -ForegroundColor Magenta
    Write-Host ('  ' + ("  WinTravelOptimizer v$Version").PadRight(40) + 'battery | privacy | power  ') -ForegroundColor White -BackgroundColor DarkBlue
    Write-Host "  $line" -ForegroundColor Magenta
    $r = Get-Recorded
    $prof = if ($r) { $r.Profile } else { 'none' }
    $priv = if ($r -and $r.Privacy) { $r.Privacy } else { '-' }
    $bat = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue
    $power = if (!$bat) { 'AC (no battery)' } elseif ($bat.BatteryStatus -eq 2) { "AC, battery $($bat.EstimatedChargeRemaining)%" } else { "battery $($bat.EstimatedChargeRemaining)%" }
    $inst = if (Test-Path (Join-Path $InstallDir 'WinTravelOptimizer.ps1')) { 'yes' } else { 'no' }
    Write-Host '   Profile: ' -NoNewline -ForegroundColor Gray; Write-Host $prof.PadRight(14) -NoNewline -ForegroundColor Green
    Write-Host 'Privacy: ' -NoNewline -ForegroundColor Gray; Write-Host $priv.PadRight(6) -NoNewline -ForegroundColor Green
    Write-Host 'Power: ' -NoNewline -ForegroundColor Gray; Write-Host $power -ForegroundColor Green
    Write-Host '   Installed: ' -NoNewline -ForegroundColor Gray; Write-Host $inst -NoNewline -ForegroundColor Green
    if ((Get-MpComputerStatus -ErrorAction SilentlyContinue).IsTamperProtected) {
        Write-Host '   Tamper Protection ON (Defender settings will not apply)' -ForegroundColor Yellow
    } else { Write-Host '' }
    Write-Host ''
}

function Show-Item($Key, $Name, $Text) {
    Write-Host '   [' -NoNewline -ForegroundColor DarkGray
    Write-Host $Key -NoNewline -ForegroundColor Yellow
    Write-Host '] ' -NoNewline -ForegroundColor DarkGray
    Write-Host $Name.PadRight(14) -NoNewline -ForegroundColor White
    Write-Host $Text -ForegroundColor Gray
}

function Pause-Menu { Write-Host ''; Read-Host '   Press Enter to return to the menu' | Out-Null }

function Select-Profile($Title) {
    Show-Banner
    Write-Host "   $Title" -ForegroundColor Cyan
    Write-Host ''
    $names = @($ProfileInfo.Keys)
    for ($i = 0; $i -lt $names.Count; $i++) { Show-Item ($i + 1) $names[$i] $ProfileInfo[$names[$i]] }
    Show-Item 'B' 'Back' ''
    Write-Host ''
    $c = Read-Host '   Select'
    $n = 0
    if ([int]::TryParse($c, [ref]$n) -and $n -ge 1 -and $n -le $names.Count) { return $names[$n - 1] }
    $null
}

# Preview, then apply after confirmation.
function Invoke-ApplyFlow($ProfileName, $PrivacyChoice) {
    Invoke-Optimizer 'dry' $ProfileName $PrivacyChoice | Out-Host
    if ($script:Diff -eq 0) { return }
    Write-Host ''
    $a = Read-Host "   Apply these $($script:Diff) changes to '$ProfileName'? [y/N]"
    if ($a -notmatch '^(y|yes)$') { warn '   Cancelled.'; return }
    Invoke-Optimizer 'apply' $ProfileName $PrivacyChoice | Out-Host
}

function Show-Menu {
    while ($true) {
        Show-Banner
        Show-Item 1 'Status' 'check drift from the active profile'
        Show-Item 2 'Preview' 'show what a profile would change'
        Show-Item 3 'Apply' 'apply a profile (preview first, then confirm)'
        Show-Item 4 'Privacy' 'turn the privacy layer on or off'
        Show-Item 5 'Install' 'copy to Program Files, add Desktop and Start Menu shortcuts'
        Show-Item 6 'Uninstall' 'remove the installed copy and shortcuts'
        Show-Item 7 'Log' 'open the log file'
        Show-Item 'Q' 'Quit' ''
        Write-Host ''
        switch ((Read-Host '   Select').Trim().ToUpper()) {
            '1' {
                $r = Get-Recorded
                if ($r) { Invoke-Optimizer 'status' $r.Profile $null | Out-Host } else { warn '   No profile applied yet.' }
                Pause-Menu
            }
            '2' { $p = Select-Profile 'Preview which profile?'; if ($p) { Invoke-Optimizer 'dry' $p $null | Out-Host; Pause-Menu } }
            '3' { $p = Select-Profile 'Apply which profile?'; if ($p) { Invoke-ApplyFlow $p $null; Pause-Menu } }
            '4' {
                $r = Get-Recorded
                if (!$r) { warn '   Apply a profile first.'; Pause-Menu; continue }
                $cur = if ($r.Privacy) { $r.Privacy } else { 'On' }
                $new = if ($cur -eq 'On') { 'Off' } else { 'On' }
                $a = Read-Host "   Privacy is $cur. Turn it $new (profile $($r.Profile) stays)? [y/N]"
                if ($a -match '^(y|yes)$') { Invoke-ApplyFlow $r.Profile $new }
                Pause-Menu
            }
            '5' { Install-Self; Pause-Menu }
            '6' { Uninstall-Self; Pause-Menu }
            '7' { if (Test-Path $LogFile) { Start-Process notepad.exe $LogFile } else { warn '   No log yet.'; Pause-Menu } }
            'Q' { return }
        }
    }
}

# ============================================
# MAIN
# ============================================
if ($Install) { Install-Self; exit 0 }
if ($Uninstall) { Uninstall-Self; exit 0 }
if ($PSBoundParameters.Count -eq 0) { Show-Menu; exit 0 }

$RunMode = if ($Status) { 'status' } elseif ($Apply) { 'apply' } else { 'dry' }
$ProfileName = $Mode
if ($Status -and !$PSBoundParameters.ContainsKey('Mode')) {
    $r = Get-Recorded
    if ($r) { $ProfileName = $r.Profile } else { warn "No profile recorded, comparing with '$Mode'" }
}
if ($RunMode -eq 'apply' -and !(Confirm-Step "Apply profile '$ProfileName'? This will modify system settings.")) { warn 'Aborted.'; exit 0 }
Invoke-Optimizer $RunMode $ProfileName $Privacy | Out-Host
if ($RunMode -eq 'dry' -and $script:Diff) { dim 'Use -Apply to execute.' }
if ($script:Failed) { exit 1 }
