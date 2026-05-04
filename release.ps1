# release.ps1 -- one-command release helper for Cairn.
#
# Usage (from the Cairn folder, in a PowerShell terminal):
#   .\release.ps1 "fix: Cairn-Settings handles nil panel gracefully"
#   .\release.ps1 "fix: ..." -DryRun     # preview, no files touched, no git
#   .\release.ps1 "fix: ..." -NoPush     # bump + commit + tag locally only
#
# What it does:
#   1. Compute a YYMMDDHHMM stamp from the current local clock.
#   2. Rewrite "## Version:" in Cairn.toc.
#   3. git add -A
#   4. git commit -m <message>
#   5. git tag -a <stamp> -m <stamp>     (annotated -- never lightweight)
#   6. git push origin HEAD
#   7. git push origin <stamp>
#   8. Print the GitHub Actions URL so you can watch the run.
#
# IMPORTANT -- Cairn lib MINORs are NOT auto-bumped:
#   Cairn libraries (Cairn-Settings-1.0.lua, Cairn-DB-1.0.lua, etc.) use
#   small-integer MINORs (1, 2, 3...) declared as
#       local MAJOR, MINOR = "Cairn-X-1.0", 3
#   Bump those MANUALLY in the affected file BEFORE running this script,
#   only when that specific library's API or behavior changes.
#
#   The CallbackHandler-1.0 shim at Libs/CallbackHandler-1.0/ is pinned at
#   MINOR=7 by design (loses to ElvUI's bundled MINOR=8, beats WoWAce's
#   MINOR=6). Never change it casually -- see Cairn/README.md for context.
#
# If PowerShell blocks the script with an execution policy error:
#     Set-ExecutionPolicy -Scope CurrentUser RemoteSigned

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Message,

    [switch]$DryRun,

    [switch]$NoPush
)

$ErrorActionPreference = 'Stop'

# ---------- Configuration ------------------------------------------------

$AddonName       = 'Cairn'
$RepoOwner       = 'ChronicTinkerer'
$VersionStampFmt = 'yyMMddHHmm'   # produces a 10-digit YYMMDDHHMM stamp

# Cairn only auto-bumps the TOC. Lib MINORs are managed by hand (see header).
$FilesToBump = @(
    @{
        Path        = 'Cairn.toc'
        Pattern     = '(?m)^(## Version:\s*)\d+'
        Description = 'TOC Version'
    }
)

# --------------------------------------------------------------------------

function Invoke-Git {
    param([Parameter(Mandatory = $true)][string[]]$Args)
    & git @Args
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Args -join ' ') failed (exit $LASTEXITCODE)"
    }
}

Push-Location $PSScriptRoot
try {
    $stamp = Get-Date -Format $VersionStampFmt

    Write-Host ''
    Write-Host "Release $AddonName -> $stamp" -ForegroundColor Cyan
    Write-Host "Commit message: $Message"     -ForegroundColor Cyan
    Write-Host ''

    foreach ($entry in $FilesToBump) {
        if (-not (Test-Path $entry.Path)) {
            throw "Missing file: $($entry.Path)"
        }
        $content = Get-Content $entry.Path -Raw
        $matches = [regex]::Matches($content, $entry.Pattern)
        if ($matches.Count -eq 0) {
            throw "Pattern not found in $($entry.Path): $($entry.Pattern)"
        }
        if ($matches.Count -gt 1) {
            throw "Pattern matched $($matches.Count) places in $($entry.Path); expected exactly 1."
        }
        $oldLine = $matches[0].Value
        $newLine = $matches[0].Groups[1].Value + $stamp
        Write-Host "  $($entry.Description) [$($entry.Path)]"
        Write-Host "    before: $oldLine"
        Write-Host "    after:  $newLine"
    }
    Write-Host ''

    if ($DryRun) {
        Write-Host 'DRY RUN. No files modified, no git actions.' -ForegroundColor Yellow
        return
    }

    foreach ($entry in $FilesToBump) {
        $content = Get-Content $entry.Path -Raw
        $updated = [regex]::Replace($content, $entry.Pattern, '${1}' + $stamp)
        Set-Content -Path $entry.Path -Value $updated -NoNewline
    }
    Write-Host 'Files updated.' -ForegroundColor Green
    Write-Host ''

    Invoke-Git @('add', '-A')
    Invoke-Git @('commit', '-m', $Message)
    Invoke-Git @('tag', '-a', $stamp, '-m', $stamp)

    if ($NoPush) {
        Write-Host ''
        Write-Host "Tag $stamp created locally. -NoPush set; not pushing." -ForegroundColor Yellow
        Write-Host "When ready:" -ForegroundColor Yellow
        Write-Host "  git push origin HEAD"        -ForegroundColor Yellow
        Write-Host "  git push origin $stamp"      -ForegroundColor Yellow
        return
    }

    Invoke-Git @('push', 'origin', 'HEAD')
    Invoke-Git @('push', 'origin', $stamp)

    Write-Host ''
    Write-Host "Released $stamp" -ForegroundColor Green
    Write-Host "Watch the run: https://github.com/$RepoOwner/$AddonName/actions" -ForegroundColor Green
}
finally {
    Pop-Location
}
