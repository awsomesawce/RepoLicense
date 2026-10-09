# Pester tests for the RepoLicense module (Pester 5+).
# Run from the repo root:  Invoke-Pester ./Tests
# Network-dependent tests are tagged 'Network' and can be skipped offline:
#   Invoke-Pester ./Tests -ExcludeTagFilter Network

BeforeAll {
    $manifest = Join-Path $PSScriptRoot '..' 'RepoLicense.psd1'
    Import-Module $manifest -Force

    $script:fakeLicenseBody = @'
MIT License

Copyright (c) [year] [fullname]

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
'@
}

Describe 'Test-GitRepoLicense' {
    BeforeAll {
        $script:repo = Join-Path ([System.IO.Path]::GetTempPath()) ("RepoLicenseTest_{0}" -f [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:repo | Out-Null
        & git init $script:repo 2>$null | Out-Null
    }
    AfterAll {
        Remove-Item -LiteralPath $script:repo -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'returns HasLicense=$false on a fresh git repo' {
        $result = Test-GitRepoLicense -Path $script:repo
        $result.HasLicense | Should -Be $false
        $result.LicenseFiles.Count | Should -Be 0
        $result.RepoRoot | Should -Not -BeNullOrEmpty
    }

    It 'returns HasLicense=$true after a LICENSE file is created' {
        'placeholder' | Set-Content -LiteralPath (Join-Path $script:repo 'LICENSE')
        try {
            $result = Test-GitRepoLicense -Path $script:repo
            $result.HasLicense | Should -Be $true
            $result.LicenseFiles | Should -Contain 'LICENSE'
        }
        finally {
            Remove-Item -LiteralPath (Join-Path $script:repo 'LICENSE') -Force -ErrorAction SilentlyContinue
        }
    }

    It 'throws a terminating error when the path is not a git repo' {
        $notARepo = Join-Path ([System.IO.Path]::GetTempPath()) ("NotARepo_{0}" -f [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $notARepo | Out-Null
        try {
            { Test-GitRepoLicense -Path $notARepo } | Should -Throw
        }
        finally {
            Remove-Item -LiteralPath $notARepo -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Add-GitRepoLicense' {
    BeforeAll {
        $script:repo = Join-Path ([System.IO.Path]::GetTempPath()) ("RepoLicenseAdd_{0}" -f [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:repo | Out-Null
        & git init $script:repo 2>$null | Out-Null
        & git -C $script:repo config user.email 'test@example.com' 2>$null | Out-Null
        & git -C $script:repo config user.name 'Test Author' 2>$null | Out-Null

        # Mock the web calls so these tests work offline.
        Mock -ModuleName RepoLicense -CommandName Invoke-RestMethod -MockWith {
            @(
                [pscustomobject]@{ key = 'mit'; name = 'MIT License'; spdx_id = 'MIT' },
                [pscustomobject]@{ key = 'apache-2.0'; name = 'Apache License 2.0'; spdx_id = 'Apache-2.0' }
            )
        } -ParameterFilter { $Uri -match '/licenses$' }
        Mock -ModuleName RepoLicense -CommandName Invoke-RestMethod -MockWith {
            [pscustomobject]@{
                key     = 'mit'
                name    = 'MIT License'
                spdx_id = 'MIT'
                body    = $script:fakeLicenseBody
            }
        } -ParameterFilter { $Uri -match '/licenses/mit$' }
    }
    AfterAll {
        Remove-Item -LiteralPath $script:repo -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'writes a LICENSE file with year/author placeholders replaced (mocked web call)' {
        $path = Add-GitRepoLicense -Path $script:repo -LicenseKey 'mit' -AuthorName 'Test Author' -Year 2026 -Force
        $path | Should -Exist
        $content = Get-Content -LiteralPath $path -Raw
        $content | Should -Match 'Copyright \(c\) 2026 Test Author'
        $content | Should -Not -Match '\[year\]'
        $content | Should -Not -Match '\[fullname\]'
    }

    It 'warns and writes nothing when a license exists and -Force is not given' {
        'existing' | Set-Content -LiteralPath (Join-Path $script:repo 'LICENSE')
        try {
            Add-GitRepoLicense -Path $script:repo -LicenseKey 'mit' -AuthorName 'Nobody' -Year 2026 -WarningVariable w 3>$null
            $w | Should -Not -BeNullOrEmpty
            (Get-Content -LiteralPath (Join-Path $script:repo 'LICENSE') -Raw) | Should -BeLike '*existing*'
        }
        finally {
            Remove-Item -LiteralPath (Join-Path $script:repo 'LICENSE') -Force -ErrorAction SilentlyContinue
        }
    }

    It 'stages the LICENSE file with -IncludeInGit' {
        $path = Add-GitRepoLicense -Path $script:repo -LicenseKey 'mit' -AuthorName 'Test Author' -Year 2026 -Force -IncludeInGit
        $staged = @( & git -C $script:repo diff --cached --name-only )
        $staged | Should -Contain 'LICENSE'
    }
}

Describe 'Get-LicenseCatalog (network)' -Tag 'Network' {
    It 'returns license entries with Key, Name, SpdxId, Description from the live API' {
        $catalog = Get-LicenseCatalog
        $catalog.Count | Should -BeGreaterThan 5
        $mit = $catalog | Where-Object { $_.Key -eq 'mit' }
        $mit | Should -Not -BeNullOrEmpty
        $mit.Description | Should -Not -BeNullOrEmpty
    }
}
