@{
    # Only fail on real problems; informational findings stay out of the way.
    Severity = @('Error', 'Warning')

    ExcludeRules = @(
        # Write-Host is intentional here: Add-GitRepoLicense renders an
        # interactive numbered license-picker menu in the console.
        'PSAvoidUsingWriteHost'
    )
}
