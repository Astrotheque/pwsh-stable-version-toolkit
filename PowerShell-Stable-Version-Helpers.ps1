<# =================== PowerShell Stable Version Helpers =================== #>

function Get-LatestPwshVersion {
    <#
    .SYNOPSIS
      Returns the latest stable PowerShell version from GitHub Releases.
    .PARAMETER AsString
      Return as a plain string instead of [version].
    .OUTPUTS
      [version] (default) or [string]
    #>
    [CmdletBinding()]
    param([switch]$AsString)

    $uri     = 'https://api.github.com/repos/PowerShell/PowerShell/releases/latest'
    $headers = @{ 'User-Agent' = 'pwsh-version-check' }

    try {
        $resp = Invoke-RestMethod -Uri $uri -Headers $headers -ErrorAction Stop
        $tag  = $resp.tag_name
        if (-not $tag) { throw "Response missing tag_name." }
        $ver  = ($tag -replace '^v')
        if ($AsString) { return $ver }
        return [version]$ver
    }
    catch {
        throw "Failed to query latest stable pwsh version: $($_.Exception.Message)"
    }
}

function Get-InstalledPwshVersion {
    <#
    .SYNOPSIS
      Returns the currently running PowerShell version.
    .OUTPUTS
      [version]
    #>
    [CmdletBinding()]
    param()
    return $PSVersionTable.PSVersion
}

function Test-PwshUpdate {
    <#
    .SYNOPSIS
      Compares local pwsh vs latest stable and reports if an update is available.
    .OUTPUTS
      [pscustomobject] with Current, Latest, IsUpdateAvailable
    #>
    [CmdletBinding()]
    param()

    $current = Get-InstalledPwshVersion
    $latest  = Get-LatestPwshVersion
    [pscustomobject]@{
        Current           = $current
        Latest            = $latest
        IsUpdateAvailable = ($latest -gt $current)
    }
}

function Get-LatestPwshMsiUri {
    <#
    .SYNOPSIS
      Returns the MSI download URL for the latest stable pwsh for your architecture.
    .PARAMETER Arch
      'x64' (default) or 'arm64'
    .OUTPUTS
      [string] MSI URL
    #>
    [CmdletBinding()]
    param([ValidateSet('x64','arm64')] [string] $Arch = 'x64')

    $uri     = 'https://api.github.com/repos/PowerShell/PowerShell/releases/latest'
    $headers = @{ 'User-Agent' = 'pwsh-version-check' }

    try {
        $resp = Invoke-RestMethod -Uri $uri -Headers $headers -ErrorAction Stop
        $pattern = "PowerShell-.*-win-$Arch\.msi$"
        $asset   = @($resp.assets) | Where-Object { $_.name -match $pattern } | Select-Object -First 1
        if (-not $asset) { throw "MSI asset for arch '$Arch' not found." }
        return $asset.browser_download_url
    }
    catch {
        throw "Failed to resolve MSI URL: $($_.Exception.Message)"
    }
}

<# =================== Usage examples =================== #>

# 1) Show local vs latest
Test-PwshUpdate

# 2) Just the latest as a string
# (Get-LatestPwshVersion -AsString)

# 3) Get the stable MSI link for x64 (or -Arch arm64)
# Get-LatestPwshMsiUri -Arch x64

# 4) Quick one-liner notify
# $t = Test-PwshUpdate; if ($t.IsUpdateAvailable) { "Update available: $($t.Current) → $($t.Latest)" } else { "Up to date ($($t.Current))" }
