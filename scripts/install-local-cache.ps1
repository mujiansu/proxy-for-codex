[CmdletBinding()]
param(
    [string]$MarketplaceRoot,

    [switch]$SkipConfig
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$pluginRoot = [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
if (-not $MarketplaceRoot) {
    $repoMarketplace = Join-Path $pluginRoot '.agents\plugins\marketplace.json'
    $MarketplaceRoot = if (Test-Path -LiteralPath $repoMarketplace -PathType Leaf) {
        $pluginRoot
    } else {
        [System.IO.Path]::GetFullPath((Join-Path $pluginRoot '..'))
    }
}
$marketplacePath = Join-Path $MarketplaceRoot '.agents\plugins\marketplace.json'
$configPath = Join-Path $env:USERPROFILE '.codex\config.toml'
$pluginName = 'proxy-for-codex'
$legacyPluginNames = @('codex-with-proxy', 'codex-proxy-launcher')
$mcpServerName = 'proxy_for_codex'
$legacyMcpServerNames = @('codex_with_proxy', 'codex_proxy_launcher')
$cacheRoot = Join-Path $env:USERPROFILE ".codex\plugins\cache\dsh-local\$pluginName"
$legacyCacheRoots = @(
    foreach ($legacyPluginName in $legacyPluginNames) {
        Join-Path $env:USERPROFILE ".codex\plugins\cache\dsh-local\$legacyPluginName"
    }
)
$pluginVersion = '0.4.0'
$cacheTarget = Join-Path $cacheRoot $pluginVersion
$stamp = Get-Date -Format 'yyyyMMdd-HHmmssfff'
$backupRoot = Join-Path $pluginRoot ("backups\install-$pluginVersion-$stamp")
$requiredPluginTools = @(
    'settings.read',
    'settings.update',
    'get_codex_proxy_status',
    'configure_codex_proxy',
    'clear_codex_proxy',
    'launch_proxy_for_codex'
)
$obsoletePluginTools = @(
    'launch_codex_with_proxy',
    'install_codex_proxy_shortcut'
)

function Set-RequiredEnabledTools {
    param(
        [string]$Text,
        [string]$TableHeader,
        [string[]]$RequiredTools,
        [string[]]$ObsoleteTools
    )
    $newline = if ($Text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $lines = [System.Collections.Generic.List[string]]::new(
        [string[]]($Text -split "`r?`n")
    )
    $tableStart = -1
    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -eq $TableHeader) {
            $tableStart = $index
            break
        }
    }
    if ($tableStart -lt 0) {
        throw "MCP table not found: $TableHeader"
    }
    $tableEnd = $lines.Count
    for ($index = $tableStart + 1; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -match '^\[') {
            $tableEnd = $index
            break
        }
    }

    $arrayStart = -1
    for ($index = $tableStart + 1; $index -lt $tableEnd; $index++) {
        if ($lines[$index] -match '^\s*enabled_tools\s*=\s*\[') {
            $arrayStart = $index
            break
        }
    }
    $existingTools = [System.Collections.Generic.List[string]]::new()
    $arrayEnd = -1
    if ($arrayStart -ge 0) {
        for ($index = $arrayStart + 1; $index -lt $tableEnd; $index++) {
            if ($lines[$index] -match '^\s*\]\s*$') {
                $arrayEnd = $index
                break
            }
            $match = [regex]::Match($lines[$index], '^\s*"(?<name>[^"]+)"\s*,?\s*$')
            if ($match.Success -and $match.Groups['name'].Value -notin $existingTools) {
                $existingTools.Add($match.Groups['name'].Value)
            }
        }
    }

    $missingTools = @($RequiredTools | Where-Object { $_ -notin $existingTools })
    $obsoleteToolsPresent = @($existingTools | Where-Object { $_ -in $ObsoleteTools })
    if (
        $arrayEnd -ge 0 -and
        $missingTools.Count -eq 0 -and
        $obsoleteToolsPresent.Count -eq 0
    ) {
        return [pscustomobject]@{
            Text = $Text
            Changed = $false
            Tools = @($existingTools)
        }
    }
    $allTools = @($RequiredTools) + @(
        $existingTools |
            Where-Object {
                $_ -notin $RequiredTools -and
                $_ -notin $ObsoleteTools
            }
    )
    $arrayLines = [System.Collections.Generic.List[string]]::new()
    $arrayLines.Add('enabled_tools = [')
    foreach ($tool in $allTools) {
        $arrayLines.Add('  "' + $tool + '",')
    }
    $arrayLines.Add(']')
    if ($arrayStart -ge 0 -and $arrayEnd -ge 0) {
        $removeCount = $arrayEnd - $arrayStart + 1
        $lines.RemoveRange($arrayStart, $removeCount)
        $lines.InsertRange($arrayStart, $arrayLines)
    } else {
        $lines.InsertRange($tableEnd, $arrayLines)
    }
    return [pscustomobject]@{
        Text = ($lines -join $newline)
        Changed = $true
        Tools = @($allTools)
    }
}

function Remove-TomlTable {
    param(
        [string]$Text,
        [string]$TableHeader
    )
    $newline = if ($Text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $lines = [System.Collections.Generic.List[string]]::new(
        [string[]]($Text -split "`r?`n")
    )
    $tableStart = -1
    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -eq $TableHeader) {
            $tableStart = $index
            break
        }
    }
    if ($tableStart -lt 0) {
        return [pscustomobject]@{
            Text = $Text
            Changed = $false
        }
    }
    $tableEnd = $lines.Count
    for ($index = $tableStart + 1; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -match '^\[') {
            $tableEnd = $index
            break
        }
    }
    $lines.RemoveRange($tableStart, $tableEnd - $tableStart)
    return [pscustomobject]@{
        Text = ($lines -join $newline)
        Changed = $true
    }
}

if (-not (Test-Path -LiteralPath $marketplacePath -PathType Leaf)) {
    throw "Marketplace manifest not found: $marketplacePath"
}
$marketplace = Get-Content -LiteralPath $marketplacePath -Raw | ConvertFrom-Json
$recognizedPluginNames = @($pluginName) + $legacyPluginNames
$marketplaceEntry = @($marketplace.plugins) |
    Where-Object { $_.name -in $recognizedPluginNames } |
    Select-Object -First 1
if (-not $marketplaceEntry) {
    throw "$pluginName is not registered in the dsh-local marketplace"
}
if ($marketplaceEntry.name -in $legacyPluginNames) {
    $marketplaceEntry.name = $pluginName
    $marketplaceEntry.interface.displayName = 'Proxy for Codex'
    [System.IO.File]::WriteAllText(
        $marketplacePath,
        ($marketplace | ConvertTo-Json -Depth 20) + [Environment]::NewLine,
        [System.Text.UTF8Encoding]::new($false)
    )
}

New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
if (Test-Path -LiteralPath $configPath -PathType Leaf) {
    Copy-Item -LiteralPath $configPath -Destination (Join-Path $backupRoot 'config.toml')
}
if (Test-Path -LiteralPath $cacheTarget -PathType Container) {
    & robocopy $cacheTarget (Join-Path $backupRoot "cache-$pluginVersion") /E /MT:16 /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) {
        throw "Cache backup failed with exit code $LASTEXITCODE"
    }
}

New-Item -ItemType Directory -Path $cacheTarget -Force | Out-Null
& robocopy $pluginRoot $cacheTarget /E /MT:16 `
    /IS `
    /XD (Join-Path $pluginRoot '.plugin-validation') `
        (Join-Path $pluginRoot '.test-runs') `
        (Join-Path $pluginRoot 'backups') `
        (Join-Path $pluginRoot 'server\node_modules') `
    /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) {
    throw "Plugin cache copy failed with exit code $LASTEXITCODE"
}

$configTable = "[plugins.`"$pluginName@dsh-local`"]"
$mcpTable = "[plugins.`"$pluginName@dsh-local`".mcp_servers.$mcpServerName]"
if (-not $SkipConfig) {
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
        throw "Codex config not found: $configPath"
    }
    $originalConfigText = Get-Content -LiteralPath $configPath -Raw
    $configText = $originalConfigText
    for ($index = 0; $index -lt $legacyPluginNames.Count; $index++) {
        $legacyPluginName = $legacyPluginNames[$index]
        $legacyMcpServerName = $legacyMcpServerNames[$index]
        $legacyConfigTable = "[plugins.`"$legacyPluginName@dsh-local`"]"
        $legacyMcpTable = "[plugins.`"$legacyPluginName@dsh-local`".mcp_servers.$legacyMcpServerName]"
        if ($configText.Contains($mcpTable) -and $configText.Contains($legacyMcpTable)) {
            $configText = (Remove-TomlTable $configText $legacyMcpTable).Text
        } else {
            $configText = $configText.Replace($legacyMcpTable, $mcpTable)
        }
        if ($configText.Contains($configTable) -and $configText.Contains($legacyConfigTable)) {
            $configText = (Remove-TomlTable $configText $legacyConfigTable).Text
        } else {
            $configText = $configText.Replace($legacyConfigTable, $configTable)
        }
    }
    $configIdentityChanged = $configText -cne $originalConfigText
    $append = [System.Collections.Generic.List[string]]::new()
    if (-not $configText.Contains($configTable)) {
        $append.Add('')
        $append.Add($configTable)
        $append.Add('enabled = true')
    }
    if (-not $configText.Contains($mcpTable)) {
        $append.Add('')
        $append.Add($mcpTable)
        $append.Add('enabled = true')
        $append.Add('tool_timeout_sec = 120')
        $append.Add('default_tools_approval_mode = "approve"')
        $append.Add('enabled_tools = [')
        foreach ($tool in $requiredPluginTools) {
            $append.Add('  "' + $tool + '",')
        }
        $append.Add(']')
    }
    $newText = if ($append.Count -gt 0) {
        $configText.TrimEnd() +
            [Environment]::NewLine +
            ($append -join [Environment]::NewLine) +
            [Environment]::NewLine
    } else {
        $configText
    }
    $beforeCacheRewrite = $newText
    $cachePathEvaluator = [System.Text.RegularExpressions.MatchEvaluator]{
        param([System.Text.RegularExpressions.Match]$match)
        return $cacheTarget
    }
    foreach ($root in @($cacheRoot) + $legacyCacheRoots) {
        $versionedCachePattern = (
            [regex]::Escape($root) +
            '[\\/][0-9]+\.[0-9]+\.[0-9]+'
        )
        $newText = [regex]::Replace(
            $newText,
            $versionedCachePattern,
            $cachePathEvaluator
        )
    }
    $cachePathChanged = $newText -cne $beforeCacheRewrite
    $toolPolicy = Set-RequiredEnabledTools `
        $newText `
        $mcpTable `
        $requiredPluginTools `
        $obsoletePluginTools
    if (
        $append.Count -gt 0 -or
        $configIdentityChanged -or
        $cachePathChanged -or
        $toolPolicy.Changed
    ) {
        [System.IO.File]::WriteAllText(
            $configPath,
            $toolPolicy.Text.TrimEnd() + [Environment]::NewLine,
            [System.Text.UTF8Encoding]::new($false)
        )
    }
}

$configHash = if (Test-Path -LiteralPath $configPath -PathType Leaf) {
    (Get-FileHash -LiteralPath $configPath -Algorithm SHA256).Hash
} else {
    $null
}

[pscustomobject]@{
    ok = $true
    cacheTarget = $cacheTarget
    configPath = $configPath
    configSha256 = $configHash
    backup = $backupRoot
    configSkipped = [bool]$SkipConfig
} | ConvertTo-Json
