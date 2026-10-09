# RepoLicense.psm1
# Checks git repositories for a license file; suggests a license and fetches
# its full text from the GitHub Licenses API when none is found.
# Works on Windows PowerShell 5.1 and PowerShell 7+.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Dot-source private helpers first, then public functions, and export the
# public ones by file name (each file defines one function).
$Private = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Private' '*.ps1') -ErrorAction SilentlyContinue)
$Public  = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Public' '*.ps1') -ErrorAction SilentlyContinue)

foreach ($file in @($Private) + @($Public)) { . $file.FullName }

Export-ModuleMember -Function $Public.BaseName
