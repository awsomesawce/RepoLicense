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
