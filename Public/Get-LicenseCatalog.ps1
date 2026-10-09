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
