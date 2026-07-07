param(
    [string]$Version = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$FilesRoot = Join-Path $RepoRoot "files"
$ManifestPath = Join-Path $RepoRoot "update_manifest.txt"

if (!(Test-Path -LiteralPath $FilesRoot -PathType Container)) {
    throw "Missing files folder: $FilesRoot"
}

if ([string]::IsNullOrWhiteSpace($Version)) {
    $Version = Get-Date -Format "yyyy.MM.dd.HHmm"
}

$Lines = New-Object System.Collections.Generic.List[string]
$Lines.Add("# ProTanki GitHub auto-update manifest")
$Lines.Add("# Rebuild with: powershell -ExecutionPolicy Bypass -File tools\\Build-Manifest.ps1")
$Lines.Add("version=$Version")

Get-ChildItem -LiteralPath $FilesRoot -Recurse -File |
    Sort-Object FullName |
    ForEach-Object {
        $Relative = $_.FullName.Substring($FilesRoot.Length + 1).Replace("\", "/")
        $Hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        $Length = $_.Length
        $Lines.Add("file=$Relative|$Hash|$Length")
    }

Set-Content -LiteralPath $ManifestPath -Value $Lines -Encoding ASCII

Write-Host "Wrote $ManifestPath"
Write-Host "Version: $Version"
Write-Host "Files: $($Lines.Count - 3)"
