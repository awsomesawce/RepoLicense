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
