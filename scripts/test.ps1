[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$pluginRoot = Split-Path -Parent $PSScriptRoot
$checks = [System.Collections.Generic.List[object]]::new()

function Add-Check {
    param(
        [string]$Name,
        [scriptblock]$Test
    )
    try {
        $detail = & $Test
        $checks.Add([pscustomobject]@{
            name = $Name
            ok = $true
            detail = $detail
        })
    } catch {
        $checks.Add([pscustomobject]@{
            name = $Name
            ok = $false
            detail = $_.Exception.Message
        })
    }
}

Add-Check 'PowerShell syntax' {
    foreach ($relative in @(
        'proxy-for-codex.ps1',
        'generate-icons.ps1',
        'install-local-cache.ps1',
        'pack.ps1',
        'test.ps1'
    )) {
        $parseErrors = $null
        [System.Management.Automation.Language.Parser]::ParseFile(
            (Join-Path $PSScriptRoot $relative),
            [ref]$null,
            [ref]$parseErrors
        ) | Out-Null
        if ($parseErrors.Count -gt 0) {
            throw (($parseErrors | ForEach-Object Message) -join '; ')
        }
    }
    '5 PowerShell files'
}

Add-Check 'JSON manifests' {
    foreach ($relative in @(
        'plugin.json',
        '.codex-plugin\plugin.json',
        '.mcp.json',
        'mcp.json',
        'server\package.json',
        'config\proxy.example.json',
        '.agents\plugins\marketplace.json'
    )) {
        Get-Content -LiteralPath (Join-Path $pluginRoot $relative) -Raw |
            ConvertFrom-Json |
            Out-Null
    }
    '7 manifests parsed'
}

Add-Check 'Direct-install marketplace' {
    $marketplace = Get-Content -LiteralPath (
        Join-Path $pluginRoot '.agents\plugins\marketplace.json'
    ) -Raw | ConvertFrom-Json
    $entry = @($marketplace.plugins) |
        Where-Object { $_.name -eq 'proxy-for-codex' } |
        Select-Object -First 1
    if (
        $marketplace.name -ne 'proxy-for-codex' -or
        -not $entry -or
        $entry.source.source -ne 'url' -or
        $entry.source.url -ne 'https://github.com/mujiansu/proxy-for-codex.git' -or
        $entry.policy.installation -ne 'AVAILABLE'
    ) {
        throw 'Proxy for Codex is not exposed as a direct-install GitHub marketplace'
    }
    'GitHub marketplace ready'
}

Add-Check 'Plugin icon assets' {
    $svgFiles = @(
        'assets\proxy-icon.svg',
        'assets\logo.svg',
        'assets\logo-dark.svg',
        'assets\composer-icon.svg',
        'assets\composer-icon-dark.svg'
    )
    foreach ($relative in $svgFiles) {
        [xml]$svg = Get-Content -LiteralPath (Join-Path $pluginRoot $relative) -Raw
        $viewBox = @(([string]$svg.svg.viewBox) -split '\s+')
        if ($viewBox.Count -ne 4) {
            throw "SVG is missing a numeric viewBox: $relative"
        }
        $width = [double]$viewBox[2]
        $height = [double]$viewBox[3]
        if ($width -lt 48 -or $height -lt 48 -or $width -ne $height) {
            throw "SVG must be square and at least 48x48: $relative"
        }
    }

    $icoPath = Join-Path $pluginRoot 'assets\proxy-icon.ico'
    $bytes = [System.IO.File]::ReadAllBytes($icoPath)
    if (
        $bytes.Length -lt 22 -or
        $bytes[0] -ne 0 -or
        $bytes[1] -ne 0 -or
        $bytes[2] -ne 1 -or
        $bytes[3] -ne 0
    ) {
        throw 'Windows icon has an invalid ICO header'
    }
    $iconCount = [System.BitConverter]::ToUInt16($bytes, 4)
    if ($iconCount -lt 5) {
        throw "Windows icon has too few sizes: $iconCount"
    }
    $iconDimensions = @(
        for ($index = 0; $index -lt $iconCount; $index++) {
            $offset = 6 + (16 * $index)
            $width = if ($bytes[$offset] -eq 0) { 256 } else { [int]$bytes[$offset] }
            $height = if ($bytes[$offset + 1] -eq 0) { 256 } else { [int]$bytes[$offset + 1] }
            if ($width -ne $height) {
                throw "Windows icon entry is not square: $width x $height"
            }
            $width
        }
    )
    if ('16' -notin @($iconDimensions) -or '256' -notin @($iconDimensions)) {
        throw "Windows icon sizes were unexpected: $($iconDimensions -join ', ')"
    }

    foreach ($manifestRelative in @('plugin.json', '.codex-plugin\plugin.json')) {
        $manifest = Get-Content -LiteralPath (
            Join-Path $pluginRoot $manifestRelative
        ) -Raw | ConvertFrom-Json
        $interface = $null
        $extensionsProperty = $manifest.PSObject.Properties['extensions']
        if ($extensionsProperty -and $extensionsProperty.Value.'com.openai') {
            $interface = $extensionsProperty.Value.'com.openai'.interface
        } else {
            $interfaceProperty = $manifest.PSObject.Properties['interface']
            if ($interfaceProperty) {
                $interface = $interfaceProperty.Value
            }
        }
        if (-not $interface) {
            throw "Missing interface metadata in $manifestRelative"
        }
        foreach ($field in @(
            'composerIcon',
            'composerIconDark',
            'logo',
            'logoDark'
        )) {
            $relative = [string]$interface.$field
            if (-not $relative) {
                throw "Missing $field in $manifestRelative"
            }
            $assetPath = Join-Path $pluginRoot ($relative -replace '^\./', '')
            if (-not (Test-Path -LiteralPath $assetPath -PathType Leaf)) {
                throw "Missing icon asset referenced by $manifestRelative`: $relative"
            }
        }
    }
    "5 SVG files, $iconCount ICO sizes"
}

Add-Check 'Node syntax' {
    foreach ($relative in @(
        'server\server.mjs',
        'server\server.bundle.mjs',
        'server\normalize-bundle.mjs',
        'scripts\launch-mcp.mjs',
        'tests\smoke.mjs'
    )) {
        node --check (Join-Path $pluginRoot $relative)
        if ($LASTEXITCODE -ne 0) {
            throw "node --check failed for $relative"
        }
    }
    '5 JavaScript files'
}

$tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$testRoot = Join-Path $tempRoot ('cpl-test-' + (Get-Date -Format 'HHmmssfff'))
$withProxyHome = Join-Path $testRoot 'with-proxy-home'
$environmentStore = Join-Path $testRoot 'user-environment.json'
$scriptPath = Join-Path $PSScriptRoot 'proxy-for-codex.ps1'
$oldWithProxyHome = $env:PROXY_FOR_CODEX_HOME
$oldEnvironmentStore = $env:PROXY_FOR_CODEX_ENVIRONMENT_STORE

try {
    New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
    $env:PROXY_FOR_CODEX_HOME = $withProxyHome
    $env:PROXY_FOR_CODEX_ENVIRONMENT_STORE = $environmentStore

    $initialEnvironmentJson = @'
{
  "version": 1,
  "values": [
    { "name": "HTTP_PROXY", "value": "http://before.example:8080" },
    { "name": "HTTPS_PROXY", "value": "http://before.example:8080" },
    { "name": "NO_PROXY", "value": "localhost" },
    { "name": "http_proxy", "value": "http://before.example:8080" },
    { "name": "https_proxy", "value": "http://before.example:8080" },
    { "name": "no_proxy", "value": "localhost" }
  ]
}
'@
    [System.IO.File]::WriteAllText(
        $environmentStore,
        $initialEnvironmentJson + [Environment]::NewLine,
        [System.Text.UTF8Encoding]::new($false)
    )

    $beforeEnvironment = [ordered]@{}
    foreach ($name in @(
        'HTTP_PROXY',
        'HTTPS_PROXY',
        'NO_PROXY',
        'http_proxy',
        'https_proxy',
        'no_proxy'
    )) {
        $beforeEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'User')
    }

    Add-Check 'Isolated default status' {
        $raw = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $scriptPath -Action status
        if ($LASTEXITCODE -ne 0) {
            throw 'status failed'
        }
        $status = $raw | ConvertFrom-Json
        if ($status.configured -ne $false) {
            throw 'status was not unconfigured'
        }
        'unconfigured'
    }

    Add-Check 'Legacy environment compatibility' {
        $legacyHome = Join-Path $testRoot 'legacy-with-proxy-home'
        $newHome = $env:PROXY_FOR_CODEX_HOME
        $oldLegacyHome = $env:CODEX_WITH_PROXY_HOME
        try {
            Remove-Item Env:PROXY_FOR_CODEX_HOME -ErrorAction SilentlyContinue
            $env:CODEX_WITH_PROXY_HOME = $legacyHome
            $raw = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $scriptPath -Action status
            if ($LASTEXITCODE -ne 0) {
                throw 'legacy status failed'
            }
            $status = $raw | ConvertFrom-Json
            if (
                [string]::Compare(
                    [System.IO.Path]::GetFullPath([string]$status.dataHome),
                    [System.IO.Path]::GetFullPath($legacyHome),
                    $true
                ) -ne 0
            ) {
                throw 'legacy home environment variable was ignored'
            }
        } finally {
            $env:PROXY_FOR_CODEX_HOME = $newHome
            $env:CODEX_WITH_PROXY_HOME = $oldLegacyHome
        }
        'legacy environment accepted'
    }

    Add-Check 'Default user-environment configuration' {
        $credentialProxy = 'http://example-user:' + ('test-' + 'only') + '@127.0.0.1:7897'
        $raw = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $scriptPath `
            -Action configure `
            -ProxyUrl $credentialProxy `
            -NoProxy 'localhost,127.0.0.1,::1' `
            -DesktopLauncher auto `
            -CodexExecutable auto `
            -Confirmation 'APPLY CODEX PROXY'
        if ($LASTEXITCODE -ne 0) {
            throw 'configure failed'
        }
        $result = $raw | ConvertFrom-Json
        if (
            $result.httpProxy.present -ne $true -or
            $result.requiresRestart -ne $true
        ) {
            throw 'configure output was unexpected'
        }
        $stored = Get-Content -LiteralPath $environmentStore -Raw | ConvertFrom-Json
        $http = @($stored.values) | Where-Object { $_.name -ceq 'HTTP_PROXY' } | Select-Object -First 1
        $https = @($stored.values) | Where-Object { $_.name -ceq 'HTTPS_PROXY' } | Select-Object -First 1
        if (
            $http.value -ne $credentialProxy -or
            $https.value -ne $credentialProxy
        ) {
            throw 'user environment was not updated in the isolated store'
        }
        'user-environment'
    }

    Add-Check 'Credential redaction' {
        $raw = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $scriptPath -Action status
        if ($LASTEXITCODE -ne 0) {
            throw 'status failed'
        }
        $text = $raw -join [Environment]::NewLine
        $status = $text | ConvertFrom-Json
        if (
            $text -notmatch 'redacted' -or
            $status.proxyUrl.hasCredentials -ne $true -or
            $status.userEnvironmentUsesProxy -ne $true -or
            $status.nextLaunchUsesProxy -ne $true
        ) {
            throw 'configured status or proxy credential redaction was unexpected'
        }
        'redacted'
    }

    Add-Check 'User-environment reconfiguration' {
        $raw = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $scriptPath `
            -Action configure `
            -ProxyUrl 'http://127.0.0.1:7898' `
            -NoProxy 'localhost,127.0.0.1,::1' `
            -DesktopLauncher auto `
            -CodexExecutable auto `
            -Confirmation 'APPLY CODEX PROXY'
        if ($LASTEXITCODE -ne 0) {
            throw 'reconfiguration failed'
        }
        $stored = Get-Content -LiteralPath $environmentStore -Raw | ConvertFrom-Json
        $http = @($stored.values) | Where-Object { $_.name -ceq 'HTTP_PROXY' } | Select-Object -First 1
        if ($http.value -ne 'http://127.0.0.1:7898') {
            throw 'user environment was not updated during reconfiguration'
        }
        $backups = @(Get-ChildItem -LiteralPath (Join-Path $withProxyHome 'environment-backups') -Directory)
        if ($backups.Count -ne 1) {
            throw "reconfiguration created an ambiguous environment backup chain: $($backups.Count)"
        }
        'single original backup retained'
    }

    Add-Check 'Clear and environment isolation' {
        $raw = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $scriptPath `
            -Action clear `
            -Confirmation 'REMOVE CODEX PROXY'
        if ($LASTEXITCODE -ne 0) {
            throw 'clear failed'
        }
        $stored = Get-Content -LiteralPath $environmentStore -Raw | ConvertFrom-Json
        foreach ($name in @(
            'HTTP_PROXY',
            'HTTPS_PROXY',
            'NO_PROXY',
            'http_proxy',
            'https_proxy',
            'no_proxy'
        )) {
            $entry = @($stored.values) |
                Where-Object { $_.name -ceq $name } |
                Select-Object -First 1
            $expectedValue = if ($name -match '^NO_PROXY$|^no_proxy$') {
                'localhost'
            } else {
                'http://before.example:8080'
            }
            if ([string]$entry.value -ne $expectedValue) {
                throw "isolated user environment was not restored: $name"
            }
        }
        foreach ($name in @($beforeEnvironment.Keys)) {
            $after = [Environment]::GetEnvironmentVariable($name, 'User')
            if ([string]$after -ne [string]$beforeEnvironment[$name]) {
                throw "user environment changed unexpectedly: $name"
            }
        }
        'cleared without user environment changes'
    }

    Add-Check 'MCP initialize and tools' {
        $raw = & node (Join-Path $pluginRoot 'tests\smoke.mjs') 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw ($raw -join [Environment]::NewLine)
        }
        $result = ($raw -join [Environment]::NewLine) | ConvertFrom-Json
        if ($result.ok -ne $true -or @($result.tools).Count -ne 6) {
            throw 'MCP smoke output was unexpected'
        }
        '6 tools, structured settings, capabilities'
    }
} finally {
    $env:PROXY_FOR_CODEX_HOME = $oldWithProxyHome
    $env:PROXY_FOR_CODEX_ENVIRONMENT_STORE = $oldEnvironmentStore
    if (Test-Path -LiteralPath $testRoot) {
        $resolvedTestRoot = [System.IO.Path]::GetFullPath($testRoot)
        if (-not $resolvedTestRoot.StartsWith(
            $tempRoot,
            [System.StringComparison]::OrdinalIgnoreCase
        ) -or (Split-Path -Leaf $resolvedTestRoot) -notmatch '^cpl-test-') {
            throw 'Refusing to remove test path outside the expected temp directory'
        }
        Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
    }
}

$failed = @($checks | Where-Object { -not $_.ok })
$checks | ConvertTo-Json -Depth 5
if ($failed.Count -gt 0) {
    throw "$($failed.Count) checks failed"
}
