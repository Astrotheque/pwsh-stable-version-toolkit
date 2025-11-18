Set-StrictMode -Version Latest

function Get-InstalledPwshVersion {
    <#
    .SYNOPSIS
      Returns the currently running PowerShell version.

    .DESCRIPTION
      Lightweight helper used by both VS Code-centric and generic checks.
      Uses $PSVersionTable.PSVersion as the single source of truth.

    .OUTPUTS
      [version]
    #>
    [CmdletBinding()]
    param()
    return $PSVersionTable.PSVersion
}

function Get-LatestPwshStableInfo {
    <#
    .SYNOPSIS
      Returns latest stable PowerShell version and release date from GitHub.

    .DESCRIPTION
      Queries the official PowerShell GitHub Releases API for the latest
      non-preview release. This is treated as the canonical "latest stable"
      for all other comparisons.

    .OUTPUTS
      PSCustomObject with:
        Version     [version]
        Tag         [string]
        PublishedAt [datetime]
    #>
    [CmdletBinding()]
    param()

    $uri     = 'https://api.github.com/repos/PowerShell/PowerShell/releases/latest'
    $headers = @{ 'User-Agent' = 'PwshStableInfo' }

    try {
        $resp = Invoke-RestMethod -Uri $uri -Headers $headers -ErrorAction Stop
        $tag  = $resp.tag_name
        if (-not $tag) { throw "Response missing tag_name." }

        [pscustomobject]@{
            Version     = [version]($tag -replace '^v')
            Tag         = $tag
            PublishedAt = Get-Date $resp.published_at
        }
    }
    catch {
        throw "Failed to query latest stable PowerShell release: $($_.Exception.Message)"
    }
}

function Get-LatestPwshPreviewInfo {
    <#
    .SYNOPSIS
      Returns latest preview (next-candidate) PowerShell release info from GitHub.

    .DESCRIPTION
      This is used for *informational* "what's next" context only.
      No preview builds are ever installed or executed by this module.

    .OUTPUTS
      PSCustomObject with:
        Version     [string]  (same as Tag)
        Tag         [string]
        PublishedAt [datetime]

      Or $null if no preview releases are found in the recent history.
    #>
    [CmdletBinding()]
    param()

    $uri     = 'https://api.github.com/repos/PowerShell/PowerShell/releases?per_page=15'
    $headers = @{ 'User-Agent' = 'PwshStableInfo' }

    try {
        $resp = Invoke-RestMethod -Uri $uri -Headers $headers -ErrorAction Stop

        # Find the most recent prerelease / preview tag, if any.
        $preview = $resp |
            Where-Object { $_.prerelease -eq $true -or $_.tag_name -match 'preview' } |
            Sort-Object { Get-Date $_.published_at } -Descending |
            Select-Object -First 1

        if (-not $preview) { return $null }

        [pscustomobject]@{
            Version     = $preview.tag_name
            Tag         = $preview.tag_name
            PublishedAt = Get-Date $preview.published_at
        }
    }
    catch {
        throw "Failed to query latest preview PowerShell release: $($_.Exception.Message)"
    }
}

function Get-PwshStableInsight {
    <#
    .SYNOPSIS
      Returns a summary of current vs latest stable, plus info about the next stable candidate.

    .DESCRIPTION
      Combines:
        - Current running pwsh
        - Latest stable from GitHub Releases
        - Latest preview (treated as "next candidate" only)

      NOTE (2025-11-17):
        NextStableNote was updated to be more contextual:
        - When a preview exists, the note now includes the preview tag
          and its publish date.
        - When no preview exists, the note explicitly states that and
          still clarifies that next stable timing is not pre-announced.

    .OUTPUTS
      PSCustomObject with:
        CurrentVersion
        LatestStableVersion
        LatestStableTag
        LatestStableDate
        IsUpToDate
        NextCandidateTag
        NextCandidateDate
        NextStableNote
    #>
    [CmdletBinding()]
    param()

    $current = Get-InstalledPwshVersion
    $stable  = Get-LatestPwshStableInfo
    $preview = Get-LatestPwshPreviewInfo

    # NOTE (2025-11-17): NextStableNote is now dynamic, but still honest.
    # We do *not* have a formal "next stable date" feed, so we never guess.
    # Instead:
    #   - If a preview exists, mention its tag and publish date explicitly.
    #   - If no preview exists, clearly say so.
    $note =
        if ($preview) {
            "Next stable version date is not formally announced. " +
            "The latest preview ($($preview.Tag), " +
            "published $($preview.PublishedAt.ToString('yyyy-MM-dd'))) " +
            "is treated as the next candidate for planning purposes, " +
            "but release timing can change."
        }
        else {
            "Next stable version date is not formally announced, and " +
            "no preview releases are currently detected. " +
            "Monitor the official PowerShell GitHub releases for updates."
        }

    [pscustomobject]@{
        CurrentVersion      = $current
        LatestStableVersion = $stable.Version
        LatestStableTag     = $stable.Tag
        LatestStableDate    = $stable.PublishedAt
        IsUpToDate          = ($current -ge $stable.Version)
        NextCandidateTag    = if ($preview) { $preview.Tag } else { $null }
        NextCandidateDate   = if ($preview) { $preview.PublishedAt } else { $null }
        NextStableNote      = $note
    }
}

function Show-VSCodePwshStatus {
    <#
    .SYNOPSIS
      Shows VS Code + PowerShell version status for the current terminal.

    .DESCRIPTION
      - Detects whether we are running inside a VS Code integrated terminal.
      - Displays:
          * current pwsh version and path
          * latest stable version and release date
          * whether the current version is up to date
          * latest preview (as "next stable candidate") and its date
          * an explanatory NextStableNote (see Get-PwshStableInsight)

      This is intended as a quick, human-friendly compliance/status check
      whenever you're in VS Code.

    .EXAMPLE
      Show-VSCodePwshStatus

      # Prints a status block with all relevant information.
    #>
    [CmdletBinding()]
    param()

    $inVSCode = $env:TERM_PROGRAM -eq 'vscode'
    $vscodePid = $env:VSCODE_PID

    $pwshPath = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
    if (-not $pwshPath) {
        $pwshPath = (Get-Process -Id $PID).Path
    }

    $insight = Get-PwshStableInsight

    Write-Host ""
    Write-Host "=== VS Code PowerShell Status ===" -ForegroundColor Cyan
    Write-Host ("In VS Code Terminal : {0}" -f $inVSCode)
    if ($inVSCode -and $vscodePid) {
        Write-Host ("VS Code Host PID    : {0}" -f $vscodePid)
    }
    Write-Host ("Pwsh Path           : {0}" -f $pwshPath)
    Write-Host ("Current Version     : {0}" -f $insight.CurrentVersion)
    Write-Host ""
    Write-Host ("Latest Stable       : {0}  ({1})" -f $insight.LatestStableVersion, $insight.LatestStableTag)
    Write-Host ("Stable Release Date : {0}" -f $insight.LatestStableDate.ToString("yyyy-MM-dd"))
    Write-Host ("Up To Date          : {0}" -f $insight.IsUpToDate)
    Write-Host ""
    if ($insight.NextCandidateTag) {
        Write-Host ("Next Stable Candidate : {0}" -f $insight.NextCandidateTag)
        if ($insight.NextCandidateDate) {
            Write-Host ("Preview Release Date  : {0}" -f $insight.NextCandidateDate.ToString("yyyy-MM-dd"))
        }
    }
    else {
        Write-Host "Next Stable Candidate : (none published yet)"
    }
    Write-Host ""
    Write-Host $insight.NextStableNote -ForegroundColor DarkGray
    Write-Host "================================" -ForegroundColor Cyan
}
