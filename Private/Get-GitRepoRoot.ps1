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
