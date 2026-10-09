# RepoLicense.psm1
# Checks git repositories for a license file; suggests a license and fetches
# its full text from the GitHub Licenses API when none is found.
# Works on Windows PowerShell 5.1 and PowerShell 7+.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-RepoLicenseCacheDir {
    <#
    .SYNOPSIS
        Returns the per-user cache directory used by this module.
    .DESCRIPTION
        Uses $env:LOCALAPPDATA\RepoLicense on Windows and ~/.cache/RepoLicense
        everywhere else. Creates the directory if it does not exist.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    if ($env:LOCALAPPDATA) {
        $dir = Join-Path $env:LOCALAPPDATA 'RepoLicense'
    }
    else {
        $dir = Join-Path (Join-Path $HOME '.cache') 'RepoLicense'
    }

    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    return $dir
}

function Get-GitRepoRoot {
    <#
    .SYNOPSIS
        Resolves the top-level directory of the git repository containing a path.
    .DESCRIPTION
        Runs `git rev-parse --show-toplevel` for the given path. Throws a
        terminating error when the path is not inside a git repository.
    .PARAMETER Path
        Any file or directory path inside (or at) the repository.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $item = Get-Item -LiteralPath $Path -ErrorAction Stop
    $workDir = if ($item -is [System.IO.DirectoryInfo]) { $item.FullName } else { $item.DirectoryName }

    $toplevel = & git -C $workDir rev-parse --show-toplevel 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($toplevel)) {
        throw "Path '$Path' is not inside a git repository. (git rev-parse --show-toplevel failed.)"
    }
    return $toplevel.Trim()
}

function Test-GitRepoLicense {
    <#
    .SYNOPSIS
        Checks whether a git repository already has a license file.
    .DESCRIPTION
        Resolves the git repository root for -Path (default: current directory)
        and scans it for common license file names: LICENSE*, LICENCE*,
        COPYING*, UNLICENSE* (case-insensitive).
    .PARAMETER Path
        A path inside the git repository to check. Defaults to the current directory.
    .EXAMPLE
        PS> Test-GitRepoLicense
        Checks the repository in the current directory.
    .EXAMPLE
        PS> Test-GitRepoLicense -Path C:\src\my-project
        Checks the repository containing C:\src\my-project.
    .OUTPUTS
        System.Management.Automation.PSCustomObject with RepoRoot, HasLicense,
        and LicenseFiles properties.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Position = 0)]
        [string]$Path = (Get-Location).Path
    )

    $repoRoot = Get-GitRepoRoot -Path $Path

    $matches = @(
        Get-ChildItem -LiteralPath $repoRoot -File -ErrorAction SilentlyContinue |
            Where-Object {
                ($_.Name -like 'LICENSE*') -or
                ($_.Name -like 'LICENCE*') -or
                ($_.Name -like 'COPYING*') -or
                ($_.Name -like 'UNLICENSE*')
            } |
            Select-Object -ExpandProperty Name
    )

    [pscustomobject]@{
        RepoRoot     = $repoRoot
        HasLicense   = [bool]$matches.Count
        LicenseFiles = [string[]]$matches
    }
}

function Get-LicenseCatalog {
    <#
    .SYNOPSIS
        Lists popular open-source licenses from the GitHub Licenses API.
    .DESCRIPTION
        Fetches https://api.github.com/licenses with Invoke-RestMethod and a
        User-Agent header (required by the GitHub API). The response is cached
        under a per-user cache directory; if the web request fails, the cache
        is used instead. Throws a helpful error when offline with no cache.
    .EXAMPLE
        PS> Get-LicenseCatalog | Format-Table Key, Name
        Lists available licenses and their keys.
    .OUTPUTS
        Objects with Key, Name, SpdxId, and Description properties.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param()

    $cacheDir  = Get-RepoLicenseCacheDir
    $cacheFile = Join-Path $cacheDir 'licenses.json'
    $licenses  = $null

    # GitHub's API requires TLS 1.2, which Windows PowerShell 5.1 does not
    # enable by default.
    if ($PSVersionTable.PSEdition -eq 'Desktop') {
        [Net.ServicePointManager]::SecurityProtocol =
            [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    }

    try {
        $headers = @{ 'User-Agent' = 'RepoLicense-PSModule/0.1.0' }
        $licenses = Invoke-RestMethod -Uri 'https://api.github.com/licenses' -Headers $headers -ErrorAction Stop
        # Refresh the cache on success (UTF-8, no BOM).
        $json = $licenses | ConvertTo-Json -Depth 5
        [System.IO.File]::WriteAllText($cacheFile, $json, (New-Object System.Text.UTF8Encoding($false)))
        Write-Verbose 'License catalog fetched from api.github.com and cached.'
    }
    catch {
        if (Test-Path -LiteralPath $cacheFile) {
            Write-Warning "Could not reach api.github.com ($($_.Exception.Message)). Using cached license list."
            $licenses = Get-Content -LiteralPath $cacheFile -Raw -ErrorAction Stop | ConvertFrom-Json
        }
        else {
            throw "Could not reach api.github.com and no cached license list exists. Check your internet connection and try again. ($($_.Exception.Message))"
        }
    }

    $oneLiners = [ordered]@{
        'mit'          = 'Permissive: do anything, just keep the copyright notice. (recommended default)'
        'apache-2.0'   = 'Permissive with a patent grant; keep notices and state changes.'
        'gpl-3.0'      = 'Copyleft: derivatives must stay open source under the GPL.'
        'bsd-3-clause' = 'Permissive; keep the copyright notice, no endorsement via the project name.'
        'bsd-2-clause' = 'Permissive "Simplified" BSD; keep the copyright notice.'
        'lgpl-3.0'     = 'Weak copyleft: library changes stay open, apps linking it can be proprietary.'
        'agpl-3.0'     = 'Copyleft including network use: SaaS deployments must share source.'
        'mpl-2.0'      = 'Weak copyleft per file: modified files stay open.'
        'unlicense'    = 'Public-domain dedication; do anything, no conditions.'
        'cc0-1.0'      = 'Public-domain dedication from Creative Commons.'
    }

    $catalog = foreach ($lic in $licenses) {
        $desc = ''
        if ($oneLiners.Contains($lic.key)) { $desc = $oneLiners[$lic.key] }
        [pscustomobject]@{
            Key         = [string]$lic.key
            Name        = [string]$lic.name
            SpdxId      = [string]$lic.spdx_id
            Description = $desc
        }
    }

    # Show the well-known licenses first, then the rest alphabetically.
    $common = $catalog | Where-Object { $oneLiners.Contains($_.Key) } |
        Sort-Object { [array]::IndexOf(@($oneLiners.Keys), $_.Key) }
    $rest = $catalog | Where-Object { -not $oneLiners.Contains($_.Key) } | Sort-Object Key
    @($common) + @($rest)
}

function Add-GitRepoLicense {
    <#
    .SYNOPSIS
        Adds a license file to a git repository that does not have one.
    .DESCRIPTION
        Runs Test-GitRepoLicense on -Path. If a license already exists and
        -Force is not given, writes a warning and returns without changes.
        Otherwise it picks a license (from -LicenseKey, or an interactive
        numbered menu with MIT as the recommended default), downloads the
        full license text from the GitHub Licenses API, fills in the year and
        author placeholders, and writes a UTF-8 (no BOM) LICENSE file in the
        repository root. With -IncludeInGit, the file is staged via `git add`.
    .PARAMETER Path
        A path inside the git repository. Defaults to the current directory.
    .PARAMETER LicenseKey
        The license key, e.g. 'mit', 'apache-2.0', 'gpl-3.0'. Omit for an
        interactive menu.
    .PARAMETER AuthorName
        Name used for the copyright line. Defaults to `git config user.name`;
        prompts when that is unset.
    .PARAMETER Year
        Year used for the copyright line. Defaults to the current year.
    .PARAMETER Force
        Overwrite even when a license file already exists.
    .PARAMETER IncludeInGit
        Stage the new LICENSE file with `git add`.
    .EXAMPLE
        PS> Add-GitRepoLicense -LicenseKey mit -IncludeInGit
        Adds the MIT license to the current repo and stages it.
    .EXAMPLE
        PS> Add-GitRepoLicense -Path C:\src\my-project
        Shows an interactive license menu for C:\src\my-project.
    .OUTPUTS
        System.String — the full path of the written LICENSE file.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([string])]
    param(
        [Parameter(Position = 0)]
        [string]$Path = (Get-Location).Path,

        [Parameter(Position = 1)]
        [string]$LicenseKey,

        [string]$AuthorName,

        [int]$Year = (Get-Date).Year,

        [switch]$Force,

        [switch]$IncludeInGit
    )

    $check = Test-GitRepoLicense -Path $Path
    $repoRoot = $check.RepoRoot

    if ($check.HasLicense -and -not $Force) {
        Write-Warning ("Repository already has a license file ({0}). Use -Force to overwrite." -f ($check.LicenseFiles -join ', '))
        return
    }

    $catalog = Get-LicenseCatalog

    if (-not $LicenseKey) {
        Write-Host ''
        Write-Host 'No license key supplied. Choose a license:'
        Write-Host ''
        for ($i = 0; $i -lt $catalog.Count; $i++) {
            $marker = if ($catalog[$i].Key -eq 'mit') { '  <-- recommended default' } else { '' }
            Write-Host ("  {0,2}. {1,-15} {2}{3}" -f ($i + 1), $catalog[$i].Key, $catalog[$i].Description, $marker)
        }
        Write-Host ''
        $defaultIndex = [array]::FindIndex($catalog, [Predicate[object]]{ param($c) $c.Key -eq 'mit' })
        if ($defaultIndex -lt 0) { $defaultIndex = 0 }
        $answer = Read-Host ("Select a license [1-{0}] (default: {1})" -f $catalog.Count, ($defaultIndex + 1))
        if ([string]::IsNullOrWhiteSpace($answer)) {
            $LicenseKey = $catalog[$defaultIndex].Key
        }
        elseif ($answer -match '^\d+$' -and [int]$answer -ge 1 -and [int]$answer -le $catalog.Count) {
            $LicenseKey = $catalog[[int]$answer - 1].Key
        }
        else {
            Write-Warning "Unrecognized selection '$answer'. Falling back to the default (mit)."
            $LicenseKey = 'mit'
        }
    }

    if (-not $AuthorName) {
        $cfgName = & git -C $repoRoot config user.name 2>$null
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($cfgName)) {
            $AuthorName = $cfgName.Trim()
        }
        else {
            $AuthorName = Read-Host 'Author name for the copyright line'
        }
    }

    if ($PSVersionTable.PSEdition -eq 'Desktop') {
        [Net.ServicePointManager]::SecurityProtocol =
            [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    }

    try {
        $detail = Invoke-RestMethod `
            -Uri ("https://api.github.com/licenses/{0}" -f $LicenseKey) `
            -Headers @{ 'User-Agent' = 'RepoLicense-PSModule/0.1.0' } `
            -ErrorAction Stop
    }
    catch {
        throw "Could not download the '$LicenseKey' license text from api.github.com. Check your internet connection and try again. ($($_.Exception.Message))"
    }

    $body = [string]$detail.body
    # Fill in [year]/[yyyy]/<year> and [fullname]/<fullname>/<copyright holders>.
    $body = $body -replace '\[year\]|\[yyyy\]|<year>', $Year
    $body = $body -replace '\[fullname\]|<fullname>|<copyright holders>', $AuthorName
    if (-not $body.EndsWith("`n")) { $body += "`n" }

    $licensePath = Join-Path $repoRoot 'LICENSE'
    if ($PSCmdlet.ShouldProcess($licensePath, "Write $LicenseKey license text")) {
        [System.IO.File]::WriteAllText($licensePath, $body, (New-Object System.Text.UTF8Encoding($false)))
        Write-Verbose "Wrote license to $licensePath"
    }

    if ($IncludeInGit -and $PSCmdlet.ShouldProcess($licensePath, 'git add')) {
        & git -C $repoRoot add 'LICENSE' 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Warning 'License file written, but `git add LICENSE` failed.'
        }
    }

    return $licensePath
}

Export-ModuleMember -Function @('Test-GitRepoLicense', 'Get-LicenseCatalog', 'Add-GitRepoLicense')
