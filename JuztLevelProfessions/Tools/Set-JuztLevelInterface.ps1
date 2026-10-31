# Offline TOC compatibility utility for JuztLevel Professions.
# It is not loaded by WoW or executed by the addon. PowerShell 5.1+.
# Get the actual current interface in WoW using:
#   /run print(select(4, GetBuildInfo()))
# Example (in a PowerShell terminal):
#   .\Set-JuztLevelInterface.ps1 -InterfaceVersion 16001
# If a client does not accept comma-separated manifests:
#   .\Set-JuztLevelInterface.ps1 -InterfaceVersion 16001 -SingleVersion
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [Parameter(Mandatory=$true)]
    [ValidateRange(1000,999999)]
    [int]$InterfaceVersion,

    [Parameter(Mandatory=$false)]
    [string]$AddonRoot = (Join-Path $PSScriptRoot '..'),

    [switch]$SingleVersion
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$resolvedRoot = (Resolve-Path -LiteralPath $AddonRoot -ErrorAction Stop).Path
$toc = Join-Path $resolvedRoot 'JuztLevelProfessions.toc'
if (-not (Test-Path -LiteralPath $toc -PathType Leaf)) {
    throw "TOC was not found: $toc"
}

# Only edit the manifest; never change sources, SavedVariables, or native gates.
$utf8 = New-Object System.Text.UTF8Encoding($false)
$raw = [System.IO.File]::ReadAllText($toc)
$pattern = '(?m)^## Interface: *([^\r\n]*)$'
$directiveMatches = [regex]::Matches($raw, $pattern)
if ($directiveMatches.Count -ne 1) {
    throw "Expected exactly one Interface directive, found $($directiveMatches.Count). No changes made."
}
$existing = $directiveMatches[0].Groups[1].Value
if ($existing -notmatch '^\s*\d+(\s*,\s*\d+)*\s*$') {
    throw "Unexpected Interface directive: $existing. No changes made."
}
$versions = New-Object 'System.Collections.Generic.List[int]'
$versions.Add($InterfaceVersion)
if (-not $SingleVersion) {
    foreach ($entry in $existing.Split(',')) {
        $value = [int]::Parse($entry.Trim())
        if ($value -gt 0 -and -not $versions.Contains($value)) {
            $versions.Add($value)
        }
    }
}
# The explicitly supplied current interface comes first, followed by old
# declarations in their existing order. Unknown future versions are never guessed.
$newDirective = '## Interface: ' + (($versions | ForEach-Object { [string]$_ }) -join ', ')
$newRaw = $raw.Remove($directiveMatches[0].Index, $directiveMatches[0].Length).Insert($directiveMatches[0].Index, $newDirective)
if ($newRaw -eq $raw) {
    Write-Output "Unchanged: $newDirective"
    return
}
if ($PSCmdlet.ShouldProcess($toc, "Update TOC Interface to $newDirective")) {
    $backup = "$toc.$([guid]::NewGuid().ToString('N')).bak"
    Copy-Item -LiteralPath $toc -Destination $backup -ErrorAction Stop
    try {
        [System.IO.File]::WriteAllText($toc, $newRaw, $utf8)
    }
    catch {
        Copy-Item -LiteralPath $backup -Destination $toc -Force
        throw
    }
    Write-Output "Updated: $newDirective"
    Write-Output "Backup: $backup"
    Write-Output 'Close the game completely before changing TOC. This declares loader compatibility; it does not certify APIs.'
}
