# RepoLicense

A PowerShell module that checks your git repositories for a license file. When
none is found, it suggests a license and fetches the full license text from the
GitHub Licenses API (`https://api.github.com/licenses`).

Works on Windows PowerShell 5.1 and PowerShell 7+.

## Install

Clone the repo and import the manifest:

```powershell
git clone https://github.com/awsomesawce/RepoLicense.git
Import-Module ./RepoLicense/RepoLicense.psd1
```

> Publishing to the PowerShell Gallery (`Publish-Module`) is a planned future
> step — for now, import from a local clone.

## Functions

| Function | What it does |
|---|---|
| `Test-GitRepoLicense [-Path]` | Resolves the git repo root and reports whether a license file (`LICENSE*`, `LICENCE*`, `COPYING*`, `UNLICENSE*`) exists. |
| `Get-LicenseCatalog` | Lists popular open-source licenses from the GitHub API, with one-line descriptions. Caches the list per-user and falls back to the cache when offline. |
| `Add-GitRepoLicense [-Path] [-LicenseKey] [-AuthorName] [-Year] [-Force] [-IncludeInGit]` | Main workflow: checks for a license, offers an interactive menu (MIT recommended) when no `-LicenseKey` is given, downloads the license text, fills in year/author, and writes a UTF-8 `LICENSE` file in the repo root. |

## Examples

```powershell
# 1. Check the current repo for a license
Test-GitRepoLicense

# RepoRoot     HasLicense LicenseFiles
# --------     ---------- ------------
# C:/src/demo      False   {}

# 2. Browse the license catalog
Get-LicenseCatalog | Format-Table Key, Name

# 3. Add the MIT license non-interactively and stage it
Add-GitRepoLicense -LicenseKey mit -IncludeInGit

# 4. Interactive mode: pick from a numbered menu (MIT is the default)
Add-GitRepoLicense -Path C:\src\my-project
```

## Offline behavior

`Get-LicenseCatalog` caches the license list under
`$env:LOCALAPPDATA\RepoLicense` (Windows) or `~/.cache/RepoLicense` (other
platforms). If the GitHub API can't be reached, the cached list is used;
downloading actual license *text* requires a connection.

## License

MIT — see [LICENSE](LICENSE).
