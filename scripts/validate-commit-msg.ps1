# scripts/validate-commit-msg.ps1
# Validates that a commit message follows the Conventional Commits format:
#   type(scope): description
# Intended for use as a lefthook `commit-msg` hook:
#   run: pwsh -NoProfile -File scripts/validate-commit-msg.ps1 {1}
param(
    [Parameter(Mandatory = $true)]
    [string]$MsgFile
)

$msg = (Get-Content -LiteralPath $MsgFile -Raw).Trim()

# Strip comment lines (git appends them when --verbose is used).
$subject = ($msg -split "`r?`n" | Where-Object { $_ -notmatch '^\s*#' } | Select-Object -First 1).Trim()

$pattern = '^(feat|fix|docs|style|refactor|perf|test|chore|security|build|ci)(\(.+\))?(!)?: .+'
if ([string]::IsNullOrWhiteSpace($subject) -or $subject -notmatch $pattern) {
    Write-Error @"
Commit message does not follow Conventional Commits.

Expected:  type(scope): description
Examples:  feat: add lefthook git hooks
            fix(catalog): handle empty API response
            docs: clarify -Force behavior in README

Types: feat, fix, docs, style, refactor, perf, test, chore, security, build, ci
"@
    exit 1
}
