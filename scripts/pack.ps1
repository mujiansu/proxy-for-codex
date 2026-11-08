[CmdletBinding()]
param(
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
$pluginRoot = [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
if (-not $OutputPath) {
    $OutputPath = Join-Path (
        Split-Path -Parent $pluginRoot
    ) 'outputs\proxy-for-codex-0.4.0.zip'
}
$outputFull = [System.IO.Path]::GetFullPath($OutputPath)
$outputDirectory = Split-Path -Parent $outputFull
$pluginParent = Split-Path -Parent $pluginRoot
$pluginFolderName = Split-Path -Leaf $pluginRoot
$excludedDirectories = @(
    '.git',
    '.plugin-validation',
    '.test-runs',
    '.dsh-codex-bridge',
    'backups',
    'node_modules'
)

New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
if (Test-Path -LiteralPath $outputFull -PathType Leaf) {
    Remove-Item -LiteralPath $outputFull -Force
}

Add-Type -AssemblyName System.IO.Compression

function Get-PackagedFiles {
    param([string]$Directory)
    foreach ($entry in Get-ChildItem -LiteralPath $Directory -Force) {
        if ($entry.PSIsContainer) {
            if ($excludedDirectories -contains $entry.Name) {
                continue
            }
            Get-PackagedFiles -Directory $entry.FullName
            continue
        }
        $entry
    }
}

$archiveStream = [System.IO.File]::Open(
    $outputFull,
    [System.IO.FileMode]::CreateNew,
    [System.IO.FileAccess]::ReadWrite,
    [System.IO.FileShare]::None
)
try {
    $zip = [System.IO.Compression.ZipArchive]::new(
        $archiveStream,
        [System.IO.Compression.ZipArchiveMode]::Create,
        $false
    )
    try {
        Get-PackagedFiles -Directory $pluginRoot | ForEach-Object {
            $relative = $_.FullName.Substring($pluginParent.Length + 1).Replace('\', '/')
            $entry = $zip.CreateEntry(
                $relative,
                [System.IO.Compression.CompressionLevel]::Optimal
            )
            $input = [System.IO.File]::OpenRead($_.FullName)
            try {
                $output = $entry.Open()
                try {
                    $input.CopyTo($output)
                } finally {
                    $output.Dispose()
                }
            } finally {
                $input.Dispose()
            }
        }
    } finally {
        $zip.Dispose()
    }
} finally {
    $archiveStream.Dispose()
}

$hash = Get-FileHash -LiteralPath $outputFull -Algorithm SHA256
[pscustomobject]@{
    ok = $true
    zip = $outputFull
    sha256 = $hash.Hash
    length = (Get-Item -LiteralPath $outputFull).Length
} | ConvertTo-Json
