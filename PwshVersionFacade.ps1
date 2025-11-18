<#
.SYNOPSIS
    Facade script to check PowerShell versions inside VS Code and optionally open
    the latest STABLE installer download page, with optional JSONL logging.

.DESCRIPTION
    This script acts as a "facade" over:
      - PwshStableInfo.psm1
      - PowerShell-Stable-Version-Helpers.ps1

    Behavior:
      1. Automatically imports PwshStableInfo.psm1.
      2. Automatically dot-sources PowerShell-Stable-Version-Helpers.ps1.
      3. Shows a human-friendly status (Show-VSCodePwshStatus) if available.
      4. Uses helper functions to determine if a newer STABLE PowerShell
         version exists.
      5. If an update is available:
           - Interactive mode: prompts whether to open the official MSI URL.
           - NonInteractive mode: logs that an update is available and exits.
      6. Optionally writes JSONL log entries suitable for log aggregators.

    NOTES (2025-11-17):
      - Logging support added:
          * JSONL format (one JSON object per line).
          * Default log directory is "<scriptRoot>\logs" unless overridden.
      - NonInteractive switch added to support automation/scheduled runs:
          * No prompts.
          * Never auto-installs; only logs state.
      - Preview (prerelease) builds are used for *information only* and are
        never used as update targets.

.PARAMETER EnableLogging
    When set, writes structured JSONL log entries about the check outcome.

.PARAMETER LogDirectory
    Optional directory path where log files will be written.
    Defaults to "<scriptRoot>\logs" if not specified.

.PARAMETER NonInteractive
    When set, runs without prompts:
      - Does NOT ask the user to open the installer URL.
      - Logs that an update is available (if so) and exits.

#>

[CmdletBinding()]
param(
    [switch]$EnableLogging,
    [string]$LogDirectory,
    [switch]$NonInteractive
)

Set-StrictMode -Version Latest

# Resolve paths relative to this script location
$rootPath   = Split-Path -Parent $PSCommandPath
$modulePath = Join-Path $rootPath 'PwshStableInfo.psm1'
$helperPath = Join-Path $rootPath 'PowerShell-Stable-Version-Helpers.ps1'

if (-not $LogDirectory) {
    $LogDirectory = Join-Path $rootPath 'logs'
}

# Unique ID for this execution (helps correlate log entries)
$runId = [guid]::NewGuid().ToString()

# Precompute today's log path for visibility
$logPath = Join-Path $LogDirectory ("PwshVersionFacade_{0}.jsonl" -f (Get-Date -Format "yyyyMMdd"))



# region Logging helpers
function Write-FacadeLogEntry {
    <#
    .SYNOPSIS
        Writes a JSONL log entry if logging is enabled.

    .DESCRIPTION
        Each log entry is a single JSON object written as one line (JSONL),
        with an ISO-8601 timestamp, a runId for this execution, and an
        eventType for later filtering.

        IMPORTANT:
        - If Data is a hashtable, we flatten via .Keys.
        - If Data is a PSCustomObject or other object, we use its properties.
        - We avoid serializing hashtable internals like Keys/Values/IsReadOnly.

    .PARAMETER LogDirectory
        Directory where log files are written.

    .PARAMETER LogPath
        Full path to the log file (precomputed).

    .PARAMETER Enabled
        Boolean controlling whether logging is active.

    .PARAMETER RunId
        Unique identifier for this execution of the facade.

    .PARAMETER EventType
        Short string describing the type of event (e.g. "CheckResult").

    .PARAMETER Data
        Hashtable or PSCustomObject with additional event fields.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string] $LogDirectory,
        [Parameter(Mandatory=$true)][string] $LogPath,
        [Parameter(Mandatory=$true)][bool]   $Enabled,
        [Parameter(Mandatory=$true)][string] $RunId,
        [Parameter(Mandatory=$true)][string] $EventType,
        [Parameter(Mandatory=$false)]        $Data
    )

    if (-not $Enabled) { return }

    try {
        if (-not (Test-Path -LiteralPath $LogDirectory)) {
            New-Item -ItemType Directory -Path $LogDirectory | Out-Null
        }

        $entry = [ordered]@{
            timestamp = (Get-Date).ToString("o")
            runId     = $RunId
            eventType = $EventType
        }

        if ($Data) {
            if ($Data -is [hashtable]) {
                foreach ($key in $Data.Keys) {
                    $entry[$key] = $Data[$key]
                }
            }
            else {
                foreach ($prop in $Data.PSObject.Properties) {
                    $entry[$prop.Name] = $prop.Value
                }
            }
        }

        $json = $entry | ConvertTo-Json -Depth 10 -Compress
        Add-Content -LiteralPath $LogPath -Value $json
    }
    catch {
        Write-Warning "Logging error: $($_.Exception.Message)"
    }
}
# endregion Logging helpers

Write-Host ""
Write-Host "=== PowerShell Version Facade ===" -ForegroundColor Cyan

if ($EnableLogging) {
    Write-Host ("Logging enabled. Log file: {0}" -f $logPath) -ForegroundColor DarkGray
}

Write-FacadeLogEntry -LogDirectory $LogDirectory -LogPath $logPath -Enabled $EnableLogging -RunId $runId `
    -EventType "Start" -Data @{
        rootPath       = $rootPath
        modulePath     = $modulePath
        helperPath     = $helperPath
        nonInteractive = $NonInteractive
    }

# 1) Import VS Code status module (PwshStableInfo.psm1)
if (Test-Path -LiteralPath $modulePath) {
    try {
        Import-Module $modulePath -Force -ErrorAction Stop
        Write-Host "Loaded module: $modulePath"
        Write-FacadeLogEntry -LogDirectory $LogDirectory -LogPath $logPath -Enabled $EnableLogging -RunId $runId `
            -EventType "ModuleLoaded" -Data @{ path = $modulePath }
    }
    catch {
        Write-Warning "Failed to load module PwshStableInfo.psm1: $($_.Exception.Message)"
        Write-FacadeLogEntry -LogDirectory $LogDirectory -LogPath $logPath -Enabled $EnableLogging -RunId $runId `
            -EventType "ModuleLoadError" -Data @{ path = $modulePath; error = $_.Exception.Message }
    }
}
else {
    Write-Warning "Module not found at: $modulePath"
    Write-FacadeLogEntry -LogDirectory $LogDirectory -LogPath $logPath -Enabled $EnableLogging -RunId $runId `
        -EventType "ModuleMissing" -Data @{ path = $modulePath }
}

# 2) Dot-source helpers (PowerShell-Stable-Version-Helpers.ps1)
if (Test-Path -LiteralPath $helperPath) {
    try {
        . $helperPath
        Write-Host "Dot-sourced helpers: $helperPath"
        Write-FacadeLogEntry -LogDirectory $LogDirectory -LogPath $logPath -Enabled $EnableLogging -RunId $runId `
            -EventType "HelpersLoaded" -Data @{ path = $helperPath }
    }
    catch {
        Write-Warning "Failed to dot-source PowerShell-Stable-Version-Helpers.ps1: $($_.Exception.Message)"
        Write-FacadeLogEntry -LogDirectory $LogDirectory -LogPath $logPath -Enabled $EnableLogging -RunId $runId `
            -EventType "HelpersLoadError" -Data @{ path = $helperPath; error = $_.Exception.Message }
    }
}
else {
    Write-Warning "Helper script not found at: $helperPath"
    Write-FacadeLogEntry -LogDirectory $LogDirectory -LogPath $logPath -Enabled $EnableLogging -RunId $runId `
        -EventType "HelpersMissing" -Data @{ path = $helperPath }
}

Write-Host ""

# 3) Show VS Code status if available
$showStatusCmd = Get-Command -Name Show-VSCodePwshStatus -ErrorAction SilentlyContinue
if ($showStatusCmd) {
    Show-VSCodePwshStatus
}
else {
    # Fallback: minimal info using $PSVersionTable if module is missing
    Write-Host "Show-VSCodePwshStatus not available. Showing basic version info." -ForegroundColor Yellow
    Write-Host ("Current PowerShell version: {0}" -f $PSVersionTable.PSVersion)
    Write-Host ""
}

# 4) Determine if an update is available (STABLE only)
#    Prefer Test-PwshUpdate from the helper script if present.
$updateCheckCmd = Get-Command -Name Test-PwshUpdate -ErrorAction SilentlyContinue
$insightCmd     = Get-Command -Name Get-PwshStableInsight -ErrorAction SilentlyContinue

$currentVersion = $null
$latestStable   = $null
$isUpdateNeeded = $false

if ($updateCheckCmd) {
    # Use the helper script's comparison
    $status = Test-PwshUpdate
    $currentVersion = $status.Current
    $latestStable   = $status.Latest
    $isUpdateNeeded = [bool]$status.IsUpdateAvailable
}
elseif ($insightCmd) {
    # Fallback: derive from PwshStableInfo
    $insight = Get-PwshStableInsight
    $currentVersion = $insight.CurrentVersion
    $latestStable   = $insight.LatestStableVersion
    $isUpdateNeeded = -not $insight.IsUpToDate
}
else {
    Write-Warning "Neither Test-PwshUpdate nor Get-PwshStableInsight is available. Cannot determine update status."
    Write-FacadeLogEntry -LogDirectory $LogDirectory -LogPath $logPath -Enabled $EnableLogging -RunId $runId `
        -EventType "UpdateCheckError" -Data @{ reason = "No helper functions available" }

    Write-Host "================================" -ForegroundColor Cyan
    return
}

Write-Host ""
Write-Host ("Current pwsh version : {0}" -f $currentVersion)
Write-Host ("Latest STABLE        : {0}" -f $latestStable)

Write-FacadeLogEntry -LogDirectory $LogDirectory -LogPath $logPath -Enabled $EnableLogging -RunId $runId `
    -EventType "CheckResult" -Data @{
        currentVersion = $currentVersion
        latestStable   = $latestStable
        updateNeeded   = $isUpdateNeeded
    }

if (-not $currentVersion -or -not $latestStable) {
    Write-Warning "Version information incomplete. Skipping update prompt."
    Write-FacadeLogEntry -LogDirectory $LogDirectory -LogPath $logPath -Enabled $EnableLogging -RunId $runId `
        -EventType "IncompleteData" -Data @{
            currentVersion = $currentVersion
            latestStable   = $latestStable
        }
    Write-Host "================================" -ForegroundColor Cyan
    return
}

if (-not $isUpdateNeeded) {
    Write-Host ""
    Write-Host "Result: You are up to date with the latest stable PowerShell." -ForegroundColor Green

    Write-FacadeLogEntry -LogDirectory $LogDirectory -LogPath $logPath -Enabled $EnableLogging -RunId $runId `
        -EventType "NoUpdateNeeded" -Data @{
            currentVersion = $currentVersion
            latestStable   = $latestStable
        }

    Write-Host "================================" -ForegroundColor Cyan
    return
}

Write-Host ""
Write-Host "Result: A newer STABLE PowerShell version is available." -ForegroundColor Yellow
Write-Host ("         {0}  ->  {1}" -f $currentVersion, $latestStable)

Write-FacadeLogEntry -LogDirectory $LogDirectory -LogPath $logPath -Enabled $EnableLogging -RunId $runId `
    -EventType "UpdateAvailable" -Data @{
        currentVersion = $currentVersion
        latestStable   = $latestStable
    }

# 5) Interactive vs non-interactive behavior
if ($NonInteractive) {
    # Automation mode: do not prompt; just log the state.
    Write-Host "NonInteractive mode: skipping update prompt." -ForegroundColor DarkGray
    Write-FacadeLogEntry -LogDirectory $LogDirectory -LogPath $logPath -Enabled $EnableLogging -RunId $runId `
        -EventType "NonInteractiveSkip" -Data @{
            currentVersion = $currentVersion
            latestStable   = $latestStable
        }

    Write-Host "================================" -ForegroundColor Cyan
    return
}

# Interactive: ask user whether to open MSI URL
$openChoice = Read-Host "Open the official download page for the latest STABLE MSI now? (Y/N)"

Write-FacadeLogEntry -LogDirectory $LogDirectory -LogPath $logPath -Enabled $EnableLogging -RunId $runId `
    -EventType "UserPrompt" -Data @{
        prompt   = "Open the official download page for the latest STABLE MSI now? (Y/N)"
        response = $openChoice
    }

if ($openChoice -match '^(y|yes)$') {
    # Determine MSI URL using helper if available; otherwise open the generic releases page.
    $msiUrl = $null
    $msiCmd = Get-Command -Name Get-LatestPwshMsiUri -ErrorAction SilentlyContinue

    if ($msiCmd) {
        try {
            # Assuming x64; adjust if you later add arch detection.
            $msiUrl = Get-LatestPwshMsiUri -Arch x64
        }
        catch {
            Write-Warning "Failed to resolve MSI URL via Get-LatestPwshMsiUri: $($_.Exception.Message)"
            Write-FacadeLogEntry -LogDirectory $LogDirectory -LogPath $logPath -Enabled $EnableLogging -RunId $runId `
                -EventType "MsiUrlError" -Data @{ error = $_.Exception.Message }
        }
    }

    if (-not $msiUrl) {
        # Fallback: open the generic latest releases page
        $msiUrl = "https://github.com/PowerShell/PowerShell/releases/latest"
    }

    Write-Host ("Opening: {0}" -f $msiUrl)
    Write-FacadeLogEntry -LogDirectory $LogDirectory -LogPath $logPath -Enabled $EnableLogging -RunId $runId `
        -EventType "OpenInstallerUrl" -Data @{ url = $msiUrl }

    try {
        Start-Process $msiUrl
    }
    catch {
        Write-Warning "Failed to open URL: $($_.Exception.Message)"
        Write-FacadeLogEntry -LogDirectory $LogDirectory -LogPath $logPath -Enabled $EnableLogging -RunId $runId `
            -EventType "OpenUrlError" -Data @{ url = $msiUrl; error = $_.Exception.Message }
    }
}
else {
    Write-Host "Update skipped by user choice." -ForegroundColor DarkGray

    Write-FacadeLogEntry -LogDirectory $LogDirectory -LogPath $logPath -Enabled $EnableLogging -RunId $runId `
        -EventType "UserSkippedUpdate" -Data @{
            currentVersion = $currentVersion
            latestStable   = $latestStable
            response       = $openChoice
        }
}

Write-Host "================================" -ForegroundColor Cyan
Write-FacadeLogEntry -LogDirectory $LogDirectory -LogPath $logPath -Enabled $EnableLogging -RunId $runId `
    -EventType "End" -Data @{ currentVersion = $currentVersion; latestStable = $latestStable }
