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
