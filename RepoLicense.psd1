# Module manifest for module 'RepoLicense'
@{
    RootModule           = 'RepoLicense.psm1'
    ModuleVersion        = '0.1.0'
    GUID                 = '38496f5a-ef60-4f39-b531-21fcb1062e66'
    Author               = 'Carl Capodice'
    CompanyName          = ''
    Copyright            = '(c) 2026 Carl Capodice'
    Description          = 'Checks git repositories for a license file. When none is found, suggests a license and fetches its full text from the GitHub Licenses API.'
    PowerShellVersion    = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')
    FunctionsToExport    = @('Test-GitRepoLicense', 'Get-LicenseCatalog', 'Add-GitRepoLicense')
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()
    PrivateData          = @{
        PSData = @{
            LicenseUri = 'https://opensource.org/licenses/MIT'
            ProjectUri = 'https://github.com/awsomesawce/RepoLicense'
            Tags       = @('git', 'license', 'licensing', 'github', 'open-source')
        }
    }
}
