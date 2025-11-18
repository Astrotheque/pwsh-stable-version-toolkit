<#
.SYNOPSIS
    Validates PwshVersionFacade JSONL log files against the documented schema.

.DESCRIPTION
    This script validates JSONL log files produced by PwshVersionFacade.ps1
    against the event / field contract described in LOG_SCHEMA.md.

    It performs the following checks:
      * Each non-empty line is valid JSON.
      * Each entry has required base fields:
          - timestamp (string)
          - runId    (string)
          - eventType (string from the allowed set)
      * For specific eventType values, additional fields are required:
          - CheckResult
              - currentVersion
              - latestStable
              - updateNeeded (boolean)
          - NoUpdateNeeded, UpdateAvailable, NonInteractiveSkip, IncompleteData, End
              - currentVersion
              - latestStable
          - UserPrompt
              - prompt
              - response
          - UserSkippedUpdate
              - currentVersion
              - latestStable
              - response
          - OpenInstallerUrl
              - url
          - OpenUrlError
              - url
              - error
          - MsiUrlError
              - error
          - UpdateCheckError
              - reason

    NOTE:
        This script does NOT use a JSON Schema engine directly. The SchemaPath
        parameter is used to ensure the schema file exists and is valid JSON,
        but the validation rules are implemented in PowerShell so that no
        external assemblies are required.

.PARAMETER SchemaPath
    Path to log.schema.json. The file is read and parsed to confirm it is
    valid JSON, but its contents are not interpreted by a JSON Schema engine.

.PARAMETER LogPath
    Path or wildcard glob for JSONL log files (e.g., .\logs\PwshVersionFacade_*.jsonl).

.PARAMETER FailFast
    When specified, validation stops on the first error and exits with code 1.
    When omitted, all entries are checked and a summary result is reported.

.EXAMPLE
    PS> .\Validate-LogSchema.ps1 -SchemaPath .\log.schema.json -LogPath .\logs\PwshVersionFacade_20251117.jsonl

    Validates a single JSONL log file.

.EXAMPLE
    PS> .\Validate-LogSchema.ps1 -SchemaPath .\log.schema.json -LogPath .\logs\PwshVersionFacade_*.jsonl -FailFast

    Validates all matching log files and stops at the first error.

.NOTES
    This script is intended as a lightweight validator that does not depend on
    external JSON Schema libraries. For full JSON Schema validation, use the
    Node.js or Python examples in the project documentation.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SchemaPath,

    [Parameter(Mandatory = $true)]
    [string]$LogPath,

    [switch]$FailFast
)

Set-StrictMode -Version Latest

function Write-ValidationMessage {
    param(
        [string]$FilePath,
        [int]$LineNumber,
        [string]$Message,
        [ValidateSet("Error","Warning","Info")]
        [string]$Level = "Error"
    )

    $prefix = "[$Level] $FilePath (line $LineNumber):"
    switch ($Level) {
        "Error"   { Write-Error   "$prefix $Message" }
        "Warning" { Write-Warning "$prefix $Message" }
        "Info"    { Write-Host    "$prefix $Message" }
    }
}

# region: Resolve inputs

$resolvedSchema = Resolve-Path -LiteralPath $SchemaPath -ErrorAction SilentlyContinue
if (-not $resolvedSchema) {
    Write-Error "Schema file not found: $SchemaPath"
    exit 1
}
$resolvedSchema = $resolvedSchema.ProviderPath

$logFiles = Get-ChildItem -Path $LogPath -File -ErrorAction SilentlyContinue
if (-not $logFiles) {
    Write-Error "No log files found matching path: $LogPath"
    exit 1
}

# Confirm schema JSON is syntactically valid (for sanity)
try {
    $null = Get-Content -LiteralPath $resolvedSchema -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
} catch {
    Write-Error "Schema file '$resolvedSchema' is not valid JSON: $($_.Exception.Message)"
    exit 1
}

# endregion

# Allowed event types
$validEventTypes = @(
    "Start",
    "ModuleLoaded",
    "ModuleLoadError",
    "ModuleMissing",
    "HelpersLoaded",
    "HelpersLoadError",
    "HelpersMissing",
    "CheckResult",
    "NoUpdateNeeded",
    "UpdateAvailable",
    "NonInteractiveSkip",
    "UserPrompt",
    "UserSkippedUpdate",
    "OpenInstallerUrl",
    "OpenUrlError",
    "MsiUrlError",
    "IncompleteData",
    "UpdateCheckError",
    "End"
)

$hasErrors = $false

foreach ($logFile in $logFiles) {
    Write-Host "Validating log file: $($logFile.FullName)"

    $lineNumber = 0

    Get-Content -LiteralPath $logFile.FullName | ForEach-Object {
        $lineNumber++
        $line = $_

        if ([string]::IsNullOrWhiteSpace($line)) {
            return
        }

        $entry = $null
        try {
            $entry = $line | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            Write-ValidationMessage -FilePath $logFile.FullName -LineNumber $lineNumber -Message "Invalid JSON: $($_.Exception.Message)" -Level "Error"
            $hasErrors = $true
            if ($FailFast) { break }
            return
        }

        # ----- Base field: timestamp -----
        if (-not ($entry.PSObject.Properties.Name -contains 'timestamp')) {
            Write-ValidationMessage -FilePath $logFile.FullName -LineNumber $lineNumber -Message "Missing required field 'timestamp'." -Level "Error"
            $hasErrors = $true
            if ($FailFast) { break }
        }
        elseif (
            -not ($entry.timestamp -is [string]) -and
            -not ($entry.timestamp -is [datetime])
        ) {
            # In JSON, timestamp is an ISO-8601 string. PowerShell's ConvertFrom-Json
            # will typically parse that into [datetime]. We accept either [string]
            # or [datetime] here, since both indicate a valid timestamp value.
            Write-ValidationMessage -FilePath $logFile.FullName -LineNumber $lineNumber `
            -Message "'timestamp' should be an ISO-8601 value (string or datetime as parsed by PowerShell)." -Level "Error"
            $hasErrors = $true
            if ($FailFast) { break }
        }

        # ----- Base field: runId -----
        if (-not ($entry.PSObject.Properties.Name -contains 'runId')) {
            Write-ValidationMessage -FilePath $logFile.FullName -LineNumber $lineNumber -Message "Missing required field 'runId'." -Level "Error"
            $hasErrors = $true
            if ($FailFast) { break }
        }
        elseif (-not ($entry.runId -is [string])) {
            Write-ValidationMessage -FilePath $logFile.FullName -LineNumber $lineNumber -Message "'runId' should be a string." -Level "Error"
            $hasErrors = $true
            if ($FailFast) { break }
        }

        # ----- Base field: eventType -----
        if (-not ($entry.PSObject.Properties.Name -contains 'eventType')) {
            Write-ValidationMessage -FilePath $logFile.FullName -LineNumber $lineNumber -Message "Missing required field 'eventType'." -Level "Error"
            $hasErrors = $true
            if ($FailFast) { break }
            return
        }

        $eventType = [string]$entry.eventType

        if (-not ($validEventTypes -contains $eventType)) {
            Write-ValidationMessage -FilePath $logFile.FullName -LineNumber $lineNumber -Message "Invalid eventType '$eventType'." -Level "Error"
            $hasErrors = $true
            if ($FailFast) { break }
            return
        }

        # ----- Per-event validation -----
        switch ($eventType) {
            "CheckResult" {
                foreach ($field in 'currentVersion','latestStable','updateNeeded') {
                    if (-not ($entry.PSObject.Properties.Name -contains $field)) {
                        Write-ValidationMessage -FilePath $logFile.FullName -LineNumber $lineNumber -Message "CheckResult missing required field '$field'." -Level "Error"
                        $hasErrors = $true
                        if ($FailFast) { break }
                    }
                }
                if ($entry.PSObject.Properties.Name -contains 'updateNeeded' -and -not ($entry.updateNeeded -is [bool])) {
                    Write-ValidationMessage -FilePath $logFile.FullName -LineNumber $lineNumber -Message "CheckResult 'updateNeeded' should be boolean." -Level "Error"
                    $hasErrors = $true
                    if ($FailFast) { break }
                }
            }
            { $_ -in @("NoUpdateNeeded","UpdateAvailable","NonInteractiveSkip","IncompleteData","End") } {
                foreach ($field in 'currentVersion','latestStable') {
                    if (-not ($entry.PSObject.Properties.Name -contains $field)) {
                        Write-ValidationMessage -FilePath $logFile.FullName -LineNumber $lineNumber -Message "$eventType missing required field '$field'." -Level "Error"
                        $hasErrors = $true
                        if ($FailFast) { break }
                    }
                }
            }
            "UserPrompt" {
                foreach ($field in 'prompt','response') {
                    if (-not ($entry.PSObject.Properties.Name -contains $field)) {
                        Write-ValidationMessage -FilePath $logFile.FullName -LineNumber $lineNumber -Message "UserPrompt missing required field '$field'." -Level "Error"
                        $hasErrors = $true
                        if ($FailFast) { break }
                    }
                }
            }
            "UserSkippedUpdate" {
                foreach ($field in 'currentVersion','latestStable','response') {
                    if (-not ($entry.PSObject.Properties.Name -contains $field)) {
                        Write-ValidationMessage -FilePath $logFile.FullName -LineNumber $lineNumber -Message "UserSkippedUpdate missing required field '$field'." -Level "Error"
                        $hasErrors = $true
                        if ($FailFast) { break }
                    }
                }
            }
            "OpenInstallerUrl" {
                if (-not ($entry.PSObject.Properties.Name -contains 'url')) {
                    Write-ValidationMessage -FilePath $logFile.FullName -LineNumber $lineNumber -Message "OpenInstallerUrl missing required field 'url'." -Level "Error"
                    $hasErrors = $true
                    if ($FailFast) { break }
                }
            }
            "OpenUrlError" {
                foreach ($field in 'url','error') {
                    if (-not ($entry.PSObject.Properties.Name -contains $field)) {
                        Write-ValidationMessage -FilePath $logFile.FullName -LineNumber $lineNumber -Message "OpenUrlError missing required field '$field'." -Level "Error"
                        $hasErrors = $true
                        if ($FailFast) { break }
                    }
                }
            }
            "MsiUrlError" {
                if (-not ($entry.PSObject.Properties.Name -contains 'error')) {
                    Write-ValidationMessage -FilePath $logFile.FullName -LineNumber $lineNumber -Message "MsiUrlError missing required field 'error'." -Level "Error"
                    $hasErrors = $true
                    if ($FailFast) { break }
                }
            }
            "UpdateCheckError" {
                if (-not ($entry.PSObject.Properties.Name -contains 'reason')) {
                    Write-ValidationMessage -FilePath $logFile.FullName -LineNumber $lineNumber -Message "UpdateCheckError missing required field 'reason'." -Level "Error"
                    $hasErrors = $true
                    if ($FailFast) { break }
                }
            }
            default {
                # Other event types (Start, ModuleLoaded, etc.) only need base fields.
            }
        }

        if ($FailFast -and $hasErrors) {
            break
        }
    }

    if ($FailFast -and $hasErrors) {
        break
    }
}

if ($hasErrors) {
    Write-Host "Log schema validation completed with errors." -ForegroundColor Red
    exit 1
}
else {
    Write-Host "Log schema validation completed successfully." -ForegroundColor Green
    exit 0
}
