[CmdletBinding()]
param(
    [ValidateSet(
        'status',
        'configure',
        'settings-read',
        'settings-update',
        'clear',
        'launch'
    )]
    [string]$Action = 'status',

    [string]$ProxyUrl,
    [string]$HttpProxy,
    [string]$HttpsProxy,
    [string]$NoProxy = 'localhost,127.0.0.1,::1',

    [string]$DesktopLauncher = 'auto',
    [string]$CodexExecutable = 'auto',

    [string]$Confirmation,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$boundScriptParameters = @($PSBoundParameters.Keys)
$applyConfirmation = 'APPLY CODEX PROXY'
$clearConfirmation = 'REMOVE CODEX PROXY'
$launchConfirmation = 'LAUNCH CODEX WITH PROXY'
$pluginVersion = '0.4.0'
$proxyVariableNames = @(
    'HTTP_PROXY',
    'HTTPS_PROXY',
    'NO_PROXY',
    'http_proxy',
    'https_proxy',
    'no_proxy'
)

function Get-ProxyForCodexHome {
    if ($env:PROXY_FOR_CODEX_HOME) {
        return [System.IO.Path]::GetFullPath($env:PROXY_FOR_CODEX_HOME)
    }
    if ($env:CODEX_WITH_PROXY_HOME) {
        return [System.IO.Path]::GetFullPath($env:CODEX_WITH_PROXY_HOME)
    }
    if ($env:CODEX_PROXY_LAUNCHER_HOME) {
        return [System.IO.Path]::GetFullPath($env:CODEX_PROXY_LAUNCHER_HOME)
    }
    $current = Join-Path $env:USERPROFILE '.proxy-for-codex'
    foreach ($legacyName in @('.codex-with-proxy', '.codex-proxy-launcher')) {
        $legacy = Join-Path $env:USERPROFILE $legacyName
        if (
            -not (Test-Path -LiteralPath $current -PathType Container) -and
            (Test-Path -LiteralPath $legacy -PathType Container)
        ) {
            Copy-Item -LiteralPath $legacy -Destination $current -Recurse
            break
        }
    }
    return $current
}

$proxyForCodexHome = Get-ProxyForCodexHome
$configPath = Join-Path $proxyForCodexHome 'config.json'
$backupRoot = Join-Path $proxyForCodexHome 'backups'
$environmentBackupRoot = Join-Path $proxyForCodexHome 'environment-backups'
$launchEvidenceRoot = Join-Path $proxyForCodexHome 'launches'
$environmentStorePath = if ($env:PROXY_FOR_CODEX_ENVIRONMENT_STORE) {
    [System.IO.Path]::GetFullPath($env:PROXY_FOR_CODEX_ENVIRONMENT_STORE)
} elseif ($env:CODEX_WITH_PROXY_ENVIRONMENT_STORE) {
    [System.IO.Path]::GetFullPath($env:CODEX_WITH_PROXY_ENVIRONMENT_STORE)
} elseif ($env:CODEX_PROXY_ENVIRONMENT_STORE) {
    [System.IO.Path]::GetFullPath($env:CODEX_PROXY_ENVIRONMENT_STORE)
} else {
    $null
}

function New-Directory {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Read-ProxyConfig {
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
        return $null
    }
    try {
        $value = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
    } catch {
        throw "Invalid Proxy for Codex config at $configPath`: $($_.Exception.Message)"
    }
    if ($null -eq $value -or $value.schemaVersion -ne 1) {
        throw "Unsupported Proxy for Codex config schema at $configPath"
    }
    return $value
}

function Write-ProxyConfig {
    param([object]$Record)
    New-Directory $proxyForCodexHome
    [System.IO.File]::WriteAllText(
        $configPath,
        ($Record | ConvertTo-Json -Depth 8) + [Environment]::NewLine,
        [System.Text.UTF8Encoding]::new($false)
    )
}

function Backup-ProxyConfig {
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
        return $null
    }
    New-Directory $backupRoot
    $directory = Join-Path $backupRoot ('config-' + (Get-Date -Format 'yyyyMMdd-HHmmssfff'))
    New-Directory $directory
    Copy-Item -LiteralPath $configPath -Destination (Join-Path $directory 'config.json')
    return $directory
}

function Get-ProxyValue {
    param(
        [AllowNull()][object]$ConfiguredValue,
        [string]$Fallback
    )
    if ($null -ne $ConfiguredValue -and -not [string]::IsNullOrWhiteSpace([string]$ConfiguredValue)) {
        return [string]$ConfiguredValue
    }
    return $Fallback
}

function Assert-ProxyUrl {
    param(
        [string]$Name,
        [AllowNull()][string]$Value
    )
    if ([string]::IsNullOrWhiteSpace($Value)) {
        return
    }
    try {
        $uri = [System.Uri]$Value
    } catch {
        throw "$Name is not a valid URL: $Value"
    }
    if ($uri.Scheme -notin @('http', 'https')) {
        throw "$Name must use http:// or https://"
    }
    if ([string]::IsNullOrWhiteSpace($uri.Host)) {
        throw "$Name must include a host"
    }
}

function Get-SafeProxySummary {
    param(
        [string]$Name,
        [AllowNull()][object]$Value
    )
    if ([string]::IsNullOrWhiteSpace([string]$Value)) {
        return [ordered]@{
            name = $Name
            present = $false
        }
    }
    try {
        $uri = [System.Uri]([string]$Value)
        $credentials = if ([string]::IsNullOrWhiteSpace($uri.UserInfo)) {
            ''
        } else {
            '<redacted>@'
        }
        $port = if ($uri.IsDefaultPort) { '' } else { ':' + $uri.Port }
        return [ordered]@{
            name = $Name
            present = $true
            display = $uri.Scheme + '://' + $credentials + $uri.Host + $port
            hasCredentials = -not [string]::IsNullOrWhiteSpace($uri.UserInfo)
        }
    } catch {
        return [ordered]@{
            name = $Name
            present = $true
            validUri = $false
        }
    }
}

function Get-SafeBypassSummary {
    param(
        [string]$Name,
        [AllowNull()][object]$Value
    )
    $text = if ($null -eq $Value) { '' } else { ([string]$Value).Trim() }
    return [ordered]@{
        name = $Name
        present = -not [string]::IsNullOrWhiteSpace($text)
        value = $text
    }
}

function Get-UserEnvironmentValue {
    param([string]$Name)
    if ($environmentStorePath) {
        if (-not (Test-Path -LiteralPath $environmentStorePath -PathType Leaf)) {
            return $null
        }
        $store = Get-Content -LiteralPath $environmentStorePath -Raw | ConvertFrom-Json
        $entry = @($store.values) |
            Where-Object { $_.name -ceq $Name } |
            Select-Object -First 1
        if ($entry) {
            return [string]$entry.value
        }
        return $null
    }
    try {
        return [Environment]::GetEnvironmentVariable($Name, 'User')
    } catch {
        return $null
    }
}

function Set-UserEnvironmentValue {
    param(
        [string]$Name,
        [AllowNull()][string]$Value
    )
    if ($environmentStorePath) {
        $values = [System.Collections.Generic.List[object]]::new()
        if (Test-Path -LiteralPath $environmentStorePath -PathType Leaf) {
            $store = Get-Content -LiteralPath $environmentStorePath -Raw | ConvertFrom-Json
            foreach ($entry in @($store.values)) {
                $values.Add([ordered]@{
                    name = [string]$entry.name
                    value = $entry.value
                })
            }
        }
        $existing = $values |
            Where-Object { $_.name -ceq $Name } |
            Select-Object -First 1
        if ($existing) {
            $existing.value = $Value
        } else {
            $values.Add([ordered]@{
                name = $Name
                value = $Value
            })
        }
        $record = [ordered]@{
            version = 1
            values = @($values)
        }
        New-Directory (Split-Path -Parent $environmentStorePath)
        [System.IO.File]::WriteAllText(
            $environmentStorePath,
            ($record | ConvertTo-Json -Depth 4) + [Environment]::NewLine,
            [System.Text.UTF8Encoding]::new($false)
        )
        return
    }
    [Environment]::SetEnvironmentVariable($Name, $Value, 'User')
}

function Get-UserEnvironmentSnapshot {
    $record = [ordered]@{ capturedAt = (Get-Date).ToUniversalTime().ToString('o') }
    foreach ($name in $proxyVariableNames) {
        $record[$name] = Get-UserEnvironmentValue $name
    }
    return $record
}

function Write-EnvironmentBackup {
    New-Directory $environmentBackupRoot
    $directory = Join-Path $environmentBackupRoot ('environment-' + (Get-Date -Format 'yyyyMMdd-HHmmssfff'))
    New-Directory $directory
    $record = Get-UserEnvironmentSnapshot
    [System.IO.File]::WriteAllText(
        (Join-Path $directory 'environment.json'),
        ($record | ConvertTo-Json -Depth 4) + [Environment]::NewLine,
        [System.Text.UTF8Encoding]::new($false)
    )
    return (Join-Path $directory 'environment.json')
}

function Get-LatestEnvironmentBackup {
    if (-not (Test-Path -LiteralPath $environmentBackupRoot -PathType Container)) {
        return $null
    }
    return Get-ChildItem -LiteralPath $environmentBackupRoot -Directory |
        Sort-Object LastWriteTime -Descending |
        ForEach-Object { Join-Path $_.FullName 'environment.json' } |
        Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
        Select-Object -First 1
}

function Broadcast-EnvironmentChange {
    if ($environmentStorePath) {
        return
    }
    if (-not ('CodexProxyEnvironmentBroadcast' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class CodexProxyEnvironmentBroadcast {
    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern IntPtr SendMessageTimeout(
        IntPtr hWnd,
        uint Msg,
        UIntPtr wParam,
        string lParam,
        uint fuFlags,
        uint uTimeout,
        out UIntPtr lpdwResult);
}
'@
    }
    $result = [UIntPtr]::Zero
    [void][CodexProxyEnvironmentBroadcast]::SendMessageTimeout(
        [IntPtr]0xffff,
        0x001A,
        [UIntPtr]::Zero,
        'Environment',
        0x0002,
        5000,
        [ref]$result
    )
}

function Get-ProxyEnvironmentExpectation {
    param([object]$Config)
    $proxy = Get-ProxyValue $Config.proxyUrl $null
    return [ordered]@{
        HTTP_PROXY = Get-ProxyValue $Config.httpProxy $proxy
        HTTPS_PROXY = Get-ProxyValue $Config.httpsProxy $proxy
        NO_PROXY = Get-ProxyValue $Config.noProxy $null
    }
}

function Test-ConfiguredProxyEnvironment {
    param(
        [object]$Config,
        [ValidateSet('process', 'user')]
        [string]$Scope
    )
    $expected = Get-ProxyEnvironmentExpectation $Config
    $actual = [ordered]@{}
    foreach ($name in @('HTTP_PROXY', 'HTTPS_PROXY', 'NO_PROXY')) {
        $actual[$name] = if ($Scope -eq 'process') {
            [Environment]::GetEnvironmentVariable($name, 'Process')
        } else {
            Get-UserEnvironmentValue $name
        }
    }
    $httpMatches = [string]$actual.HTTP_PROXY -eq [string]$expected.HTTP_PROXY
    $httpsMatches = [string]$actual.HTTPS_PROXY -eq [string]$expected.HTTPS_PROXY
    return [ordered]@{
        usesConfiguredProxy = $httpMatches -and $httpsMatches
        httpProxyMatches = $httpMatches
        httpsProxyMatches = $httpsMatches
        noProxyMatches = [string]$actual.NO_PROXY -eq [string]$expected.NO_PROXY
    }
}

function Set-ManagedUserEnvironment {
    param([object]$Config)
    $proxy = Get-ProxyValue $Config.proxyUrl $null
    $http = Get-ProxyValue $Config.httpProxy $proxy
    $https = Get-ProxyValue $Config.httpsProxy $proxy
    $noProxy = Get-ProxyValue $Config.noProxy $null
    if ([string]::IsNullOrWhiteSpace($proxy) -and
        [string]::IsNullOrWhiteSpace($http) -and
        [string]::IsNullOrWhiteSpace($https)) {
        throw 'No proxy URL is configured'
    }
    if (-not $DryRun) {
        Set-UserEnvironmentValue 'HTTP_PROXY' $http
        Set-UserEnvironmentValue 'HTTPS_PROXY' $https
        Set-UserEnvironmentValue 'NO_PROXY' $noProxy
        Set-UserEnvironmentValue 'http_proxy' $http
        Set-UserEnvironmentValue 'https_proxy' $https
        Set-UserEnvironmentValue 'no_proxy' $noProxy
        Broadcast-EnvironmentChange
    }
}

function Remove-ManagedUserEnvironment {
    param([object]$Config)
    $proxy = Get-ProxyValue $Config.proxyUrl $null
    $expected = @(
        [pscustomobject]@{
            Name = 'HTTP_PROXY'
            Value = Get-ProxyValue $Config.httpProxy $proxy
        },
        [pscustomobject]@{
            Name = 'HTTPS_PROXY'
            Value = Get-ProxyValue $Config.httpsProxy $proxy
        },
        [pscustomobject]@{
            Name = 'NO_PROXY'
            Value = Get-ProxyValue $Config.noProxy $null
        },
        [pscustomobject]@{
            Name = 'http_proxy'
            Value = Get-ProxyValue $Config.httpProxy $proxy
        },
        [pscustomobject]@{
            Name = 'https_proxy'
            Value = Get-ProxyValue $Config.httpsProxy $proxy
        },
        [pscustomobject]@{
            Name = 'no_proxy'
            Value = Get-ProxyValue $Config.noProxy $null
        }
    )
    $backupPath = Get-LatestEnvironmentBackup
    $previous = if ($backupPath) {
        Get-Content -LiteralPath $backupPath -Raw | ConvertFrom-Json
    } else {
        $null
    }
    $changed = [System.Collections.Generic.List[string]]::new()
    $preserved = [System.Collections.Generic.List[string]]::new()
    foreach ($name in $proxyVariableNames) {
        $current = Get-UserEnvironmentValue $name
        $expectedValue = (
            $expected |
                Where-Object { $_.Name -eq $name } |
                Select-Object -First 1
        ).Value
        if ([string]$current -ne [string]$expectedValue) {
            if (-not [string]::IsNullOrWhiteSpace([string]$current)) {
                $preserved.Add($name)
            }
            continue
        }
        $restoreValue = if ($null -ne $previous) {
            [string]$previous.$name
        } else {
            $null
        }
        if ([string]::IsNullOrWhiteSpace($restoreValue)) {
            $restoreValue = $null
        }
        if (-not $DryRun) {
            Set-UserEnvironmentValue $name $restoreValue
        }
        $changed.Add($name)
    }
    if ($changed.Count -gt 0 -and -not $DryRun) {
        Broadcast-EnvironmentChange
    }
    return [ordered]@{
        changed = @($changed)
        preserved = @($preserved)
        restoredFrom = $backupPath
    }
}

function Expand-ConfiguredPath {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) {
        return $null
    }
    $text = ([string]$Value).Trim()
    if (-not $text -or $text -ieq 'auto') {
        return $null
    }
    return [Environment]::ExpandEnvironmentVariables($text)
}

function Get-DesktopLauncherCandidatePaths {
    $paths = [System.Collections.Generic.List[string]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    foreach ($candidate in @(
        $env:CODEX_DESKTOP_LAUNCHER,
        (Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\chatgpt-desktop.exe'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\ChatGPT.exe')
    )) {
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            continue
        }
        $expanded = [Environment]::ExpandEnvironmentVariables([string]$candidate)
        try {
            $full = [System.IO.Path]::GetFullPath($expanded)
        } catch {
            continue
        }
        if ($seen.Add($full)) {
            $paths.Add($full)
        }
    }
    try {
        foreach ($package in @(Get-AppxPackage -Name 'OpenAI.Codex' -ErrorAction Stop)) {
            if ($package.InstallLocation) {
                $full = Join-Path $package.InstallLocation 'app\ChatGPT.exe'
                if ($seen.Add($full)) {
                    $paths.Add($full)
                }
            }
        }
    } catch {
        # Get-AppxPackage can be unavailable in a restricted host.
    }
    return @($paths)
}

function Resolve-DesktopLauncher {
    param([AllowNull()][object]$Configured)
    $explicit = Expand-ConfiguredPath $Configured
    if ($explicit) {
        if (-not (Test-Path -LiteralPath $explicit -PathType Leaf)) {
            throw "Configured desktop launcher was not found: $explicit"
        }
        return [ordered]@{
            path = $explicit
            source = 'configured'
        }
    }
    foreach ($candidate in @(Get-DesktopLauncherCandidatePaths)) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return [ordered]@{
                path = $candidate
                source = 'auto-discovery'
            }
        }
    }
    return [ordered]@{
        path = $null
        source = 'not-detected'
    }
}

function Resolve-CodexExecutable {
    param([AllowNull()][object]$Configured)
    $explicit = Expand-ConfiguredPath $Configured
    if ($explicit) {
        if (-not (Test-Path -LiteralPath $explicit -PathType Leaf)) {
            throw "Configured Codex executable was not found: $explicit"
        }
        return [ordered]@{
            path = $explicit
            source = 'configured'
        }
    }
    $roots = @(
        (Join-Path $env:LOCALAPPDATA 'OpenAI\Codex\bin'),
        (Join-Path $env:LOCALAPPDATA 'Programs\OpenAI\Codex\bin')
    )
    $candidates = @(
        foreach ($root in $roots) {
            if (Test-Path -LiteralPath $root -PathType Container) {
                Get-ChildItem -LiteralPath $root -Filter 'codex.exe' -File -Recurse -ErrorAction SilentlyContinue
            }
        }
    ) | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($candidates) {
        return [ordered]@{
            path = [string]$candidates.FullName
            source = 'installation-scan'
        }
    }
    return [ordered]@{
        path = $null
        source = 'not-detected'
    }
}

function Get-CodexProcessState {
    $hosts = @(
        Get-Process -Name ChatGPT -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Path -and (
                    $_.Path -match '(?i)\\WindowsApps\\OpenAI\.Codex_' -or
                    $_.Path -match '(?i)\\app\\ChatGPT\.exe$'
                )
            }
    )
    $appServers = @(
        Get-Process -Name codex -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Path -and
                $_.Path -notmatch '(?i)\\\.vscode\\|\\extensions\\openai\.chatgpt-' -and
                $_.Path -match '(?i)\\OpenAI\\Codex\\bin\\'
            }
    )
    return [ordered]@{
        desktopHostCount = $hosts.Count
        appServerCount = $appServers.Count
        anyRunning = ($hosts.Count + $appServers.Count) -gt 0
        desktopHostPids = @($hosts | ForEach-Object { [int]$_.Id })
        appServerPids = @($appServers | ForEach-Object { [int]$_.Id })
    }
}

function Get-ConfiguredProxyConnectionState {
    param(
        [object]$Config,
        [object]$ProcessState
    )
    $proxy = Get-ProxyValue $Config.proxyUrl $null
    $ports = [System.Collections.Generic.List[int]]::new()
    $seenPorts = [System.Collections.Generic.HashSet[int]]::new()
    foreach ($candidate in @(
        $proxy,
        (Get-ProxyValue $Config.httpProxy $null),
        (Get-ProxyValue $Config.httpsProxy $null)
    )) {
        if ([string]::IsNullOrWhiteSpace([string]$candidate)) {
            continue
        }
        try {
            $uri = [System.Uri]([string]$candidate)
        } catch {
            continue
        }
        if ($uri.Scheme -notin @('http', 'https')) {
            continue
        }
        $port = if ($uri.IsDefaultPort) {
            if ($uri.Scheme -eq 'https') { 443 } else { 80 }
        } else {
            $uri.Port
        }
        if ($port -gt 0 -and $seenPorts.Add($port)) {
            $ports.Add($port)
        }
    }
    $processIds = @(
        @($ProcessState.desktopHostPids) +
        @($ProcessState.appServerPids) |
            ForEach-Object { [int]$_ } |
            Sort-Object -Unique
    )
    if ($ports.Count -eq 0 -or $processIds.Count -eq 0) {
        return [ordered]@{
            available = $true
            connectionCount = 0
            ports = @($ports)
            processIds = @($processIds)
        }
    }
    try {
        $connections = @(
            foreach ($port in $ports) {
                Get-NetTCPConnection -RemotePort $port -State Established -ErrorAction Stop
            }
        ) | Where-Object { $_.OwningProcess -in $processIds }
        return [ordered]@{
            available = $true
            connectionCount = @($connections).Count
            ports = @($ports)
            processIds = @($processIds)
        }
    } catch {
        return [ordered]@{
            available = $false
            connectionCount = 0
            ports = @($ports)
            processIds = @($processIds)
        }
    }
}

function New-LaunchEvidence {
    param(
        [object]$Config,
        [string]$Status,
        [AllowNull()][object]$StartedProcess,
        [AllowNull()][string]$Message
    )
    New-Directory $launchEvidenceRoot
    $path = Join-Path $launchEvidenceRoot ((Get-Date -Format 'yyyyMMdd-HHmmssfff') + '.json')
    $proxy = Get-ProxyValue $Config.proxyUrl $null
    $record = [ordered]@{
        schemaVersion = 1
        at = (Get-Date).ToUniversalTime().ToString('o')
        status = $Status
        httpProxy = Get-SafeProxySummary 'HTTP_PROXY' (Get-ProxyValue $Config.httpProxy $proxy)
        httpsProxy = Get-SafeProxySummary 'HTTPS_PROXY' (Get-ProxyValue $Config.httpsProxy $proxy)
        noProxyConfigured = -not [string]::IsNullOrWhiteSpace([string]$Config.noProxy)
        launcherPid = if ($StartedProcess) { [int]$StartedProcess.Id } else { $null }
        message = $Message
    }
    [System.IO.File]::WriteAllText(
        $path,
        ($record | ConvertTo-Json -Depth 6) + [Environment]::NewLine,
        [System.Text.UTF8Encoding]::new($false)
    )
    return $record
}

function Get-StatusRecord {
    $config = Read-ProxyConfig
    $processState = Get-CodexProcessState
    if (-not $config) {
        return [ordered]@{
            ok = $true
            pluginVersion = $pluginVersion
            configured = $false
            configPath = $configPath
            dataHome = $proxyForCodexHome
            process = $processState
            confirmationPhrases = [ordered]@{
                configure = $applyConfirmation
                clear = $clearConfirmation
                launch = 'LAUNCH CODEX WITH PROXY'
            }
        }
    }
    $launcher = Resolve-DesktopLauncher $config.desktopLauncher
    $codex = Resolve-CodexExecutable $config.codexExecutable
    $proxy = Get-ProxyValue $config.proxyUrl $null
    $processProxyState = Test-ConfiguredProxyEnvironment $config 'process'
    $userProxyState = Test-ConfiguredProxyEnvironment $config 'user'
    $activeProxyState = Get-ConfiguredProxyConnectionState $config $processState
    $currentProcessUsesProxy = (
        $processProxyState.usesConfiguredProxy -or
        $activeProxyState.connectionCount -gt 0
    )
    $normalLaunchReady = [bool]$userProxyState.usesConfiguredProxy
    $restartRequired = (
        $processState.anyRunning -and
        -not $currentProcessUsesProxy
    )
    $statusMessage = if ($currentProcessUsesProxy) {
        'This Codex process is using the configured proxy. Normal future launches are ready.'
    } else {
        'The proxy is saved for normal Codex launches. Fully quit and reopen Codex once.'
    }
    return [ordered]@{
        ok = $true
        pluginVersion = $pluginVersion
        configured = $true
        configPath = $configPath
        dataHome = $proxyForCodexHome
        launchPolicy = 'normal-windows-entrypoints'
        proxyUrl = Get-SafeProxySummary 'proxyUrl' $proxy
        httpProxy = Get-SafeProxySummary 'HTTP_PROXY' (Get-ProxyValue $config.httpProxy $proxy)
        httpsProxy = Get-SafeProxySummary 'HTTPS_PROXY' (Get-ProxyValue $config.httpsProxy $proxy)
        noProxy = $config.noProxy
        desktopLauncher = $launcher
        codexExecutable = $codex
        process = $processState
        currentProcessUsesProxy = [bool]$currentProcessUsesProxy
        proxyConnections = $activeProxyState
        processEnvironmentInheritedProxy = [bool]$processProxyState.usesConfiguredProxy
        userEnvironmentUsesProxy = [bool]$userProxyState.usesConfiguredProxy
        nextLaunchUsesProxy = [bool]$userProxyState.usesConfiguredProxy
        restartRequired = [bool]$restartRequired
        message = $statusMessage
        environment = [ordered]@{
            user = [ordered]@{
                HTTP_PROXY = Get-SafeProxySummary 'HTTP_PROXY' (Get-UserEnvironmentValue 'HTTP_PROXY')
                HTTPS_PROXY = Get-SafeProxySummary 'HTTPS_PROXY' (Get-UserEnvironmentValue 'HTTPS_PROXY')
                NO_PROXY = Get-SafeBypassSummary 'NO_PROXY' (Get-UserEnvironmentValue 'NO_PROXY')
            }
            process = [ordered]@{
                HTTP_PROXY = Get-SafeProxySummary 'HTTP_PROXY' $env:HTTP_PROXY
                HTTPS_PROXY = Get-SafeProxySummary 'HTTPS_PROXY' $env:HTTPS_PROXY
                NO_PROXY = Get-SafeBypassSummary 'NO_PROXY' $env:NO_PROXY
            }
        }
        ready = [bool]$normalLaunchReady
        notes = @(
            'Persistent user proxy variables let normal Codex entry points use the proxy after one full restart.',
            'No dedicated proxy shortcut is created or required.',
            'An already-running Codex process keeps its original environment until it is fully closed and reopened.'
        )
    }
}

function Get-SettingsRecord {
    $config = Read-ProxyConfig
    $defaultProxy = 'http://127.0.0.1:7897'
    $httpProxy = $defaultProxy
    $httpsProxy = $defaultProxy
    $noProxy = 'localhost,127.0.0.1,::1'
    $desktopLauncher = 'auto'
    $codexExecutable = 'auto'
    if ($config) {
        $legacyProxy = Get-ProxyValue $config.proxyUrl $defaultProxy
        $httpSummary = Get-SafeProxySummary 'HTTP_PROXY' (
            Get-ProxyValue $config.httpProxy $legacyProxy
        )
        $httpsSummary = Get-SafeProxySummary 'HTTPS_PROXY' (
            Get-ProxyValue $config.httpsProxy $legacyProxy
        )
        $httpProxy = if ($httpSummary.present -and $httpSummary.display) {
            [string]$httpSummary.display
        } else {
            ''
        }
        $httpsProxy = if ($httpsSummary.present -and $httpsSummary.display) {
            [string]$httpsSummary.display
        } else {
            ''
        }
        $noProxy = [string]$config.noProxy
        $desktopLauncher = if ([string]::IsNullOrWhiteSpace([string]$config.desktopLauncher)) {
            'auto'
        } else {
            [string]$config.desktopLauncher
        }
        $codexExecutable = if ([string]::IsNullOrWhiteSpace([string]$config.codexExecutable)) {
            'auto'
        } else {
            [string]$config.codexExecutable
        }
    }
    return [ordered]@{
        ok = $true
        configured = [bool]$config
        configPath = $configPath
        values = [ordered]@{
            httpProxy = $httpProxy
            httpsProxy = $httpsProxy
            noProxy = $noProxy
            desktopLauncher = $desktopLauncher
            codexExecutable = $codexExecutable
        }
    }
}

function Save-ProxyConfiguration {
    param(
        [object]$Record,
        [string]$ActionName
    )
    $launcher = Resolve-DesktopLauncher $Record.desktopLauncher
    $codex = Resolve-CodexExecutable $Record.codexExecutable
    $configBackup = Backup-ProxyConfig
    $environmentBackup = Get-LatestEnvironmentBackup
    if (-not $environmentBackup) {
        $environmentBackup = Write-EnvironmentBackup
    }
    if (-not $DryRun) {
        Write-ProxyConfig $Record
        Set-ManagedUserEnvironment $Record
    }
    $processProxyState = Test-ConfiguredProxyEnvironment $Record 'process'
    return [ordered]@{
        ok = $true
        action = $ActionName
        dryRun = [bool]$DryRun
        configPath = $configPath
        configBackup = $configBackup
        environmentBackup = $environmentBackup
        launchPolicy = 'normal-windows-entrypoints'
        currentProcessUsesProxy = [bool]$processProxyState.usesConfiguredProxy
        nextLaunchUsesProxy = $true
        requiresRestart = $true
        message = 'Proxy saved for normal Codex launches. Fully quit and reopen Codex once; later launches from any normal Windows entry point will inherit it.'
        proxyUrl = Get-SafeProxySummary 'proxyUrl' $Record.proxyUrl
        httpProxy = Get-SafeProxySummary 'HTTP_PROXY' (
            Get-ProxyValue $Record.httpProxy $Record.proxyUrl
        )
        httpsProxy = Get-SafeProxySummary 'HTTPS_PROXY' (
            Get-ProxyValue $Record.httpsProxy $Record.proxyUrl
        )
        noProxy = $Record.noProxy
        desktopLauncher = $launcher
        codexExecutable = $codex
    }
}

function Invoke-SettingsUpdate {
    $previousConfig = Read-ProxyConfig
    $defaultProxy = 'http://127.0.0.1:7897'
    $httpProxyChanged = $boundScriptParameters -contains 'HttpProxy'
    $httpsProxyChanged = $boundScriptParameters -contains 'HttpsProxy'
    $previousLegacyProxy = if ($previousConfig) {
        Get-ProxyValue $previousConfig.proxyUrl $defaultProxy
    } else {
        $defaultProxy
    }
    $previousHttpProxy = if ($previousConfig) {
        Get-ProxyValue $previousConfig.httpProxy $previousLegacyProxy
    } else {
        $defaultProxy
    }
    $previousHttpsProxy = if ($previousConfig) {
        Get-ProxyValue $previousConfig.httpsProxy $previousLegacyProxy
    } else {
        $defaultProxy
    }
    if ($httpProxyChanged -and $HttpProxy -match '(?i)<redacted>') {
        throw 'Re-enter the complete HTTP proxy URL when changing a credential-bearing proxy'
    }
    if ($httpsProxyChanged -and $HttpsProxy -match '(?i)<redacted>') {
        throw 'Re-enter the complete HTTPS proxy URL when changing a credential-bearing proxy'
    }
    if ($httpProxyChanged -or $httpsProxyChanged) {
        $proxyUrl = $null
        $httpProxy = if ($httpProxyChanged) {
            $HttpProxy.Trim()
        } else {
            $previousHttpProxy
        }
        $httpsProxy = if ($httpsProxyChanged) {
            $HttpsProxy.Trim()
        } else {
            $previousHttpsProxy
        }
        if ([string]::IsNullOrWhiteSpace([string]$httpProxy) -or
            [string]::IsNullOrWhiteSpace([string]$httpsProxy)) {
            throw 'HTTP proxy URL and HTTPS proxy URL are both required'
        }
    } elseif ($previousConfig) {
        $proxyUrl = $previousConfig.proxyUrl
        $httpProxy = $previousConfig.httpProxy
        $httpsProxy = $previousConfig.httpsProxy
    } else {
        $proxyUrl = $null
        $httpProxy = $defaultProxy
        $httpsProxy = $defaultProxy
    }
    $noProxy = if ($boundScriptParameters -contains 'NoProxy') {
        $NoProxy.Trim()
    } elseif ($previousConfig -and $null -ne $previousConfig.noProxy) {
        [string]$previousConfig.noProxy
    } else {
        'localhost,127.0.0.1,::1'
    }
    $desktopValue = if ($boundScriptParameters -contains 'DesktopLauncher') {
        $DesktopLauncher
    } elseif ($previousConfig) {
        [string]$previousConfig.desktopLauncher
    } else {
        'auto'
    }
    $codexValue = if ($boundScriptParameters -contains 'CodexExecutable') {
        $CodexExecutable
    } elseif ($previousConfig) {
        [string]$previousConfig.codexExecutable
    } else {
        'auto'
    }
    Assert-ProxyUrl 'proxyUrl' $proxyUrl
    Assert-ProxyUrl 'httpProxy' $httpProxy
    Assert-ProxyUrl 'httpsProxy' $httpsProxy
    if ([string]::IsNullOrWhiteSpace([string]$proxyUrl) -and
        [string]::IsNullOrWhiteSpace([string]$httpProxy) -and
        [string]::IsNullOrWhiteSpace([string]$httpsProxy)) {
        throw 'At least one of proxyUrl, httpProxy, or httpsProxy is required'
    }
    $record = [ordered]@{
        schemaVersion = 1
        proxyUrl = if ([string]::IsNullOrWhiteSpace([string]$proxyUrl)) { $null } else { ([string]$proxyUrl).Trim() }
        httpProxy = if ([string]::IsNullOrWhiteSpace([string]$httpProxy)) { $null } else { ([string]$httpProxy).Trim() }
        httpsProxy = if ([string]::IsNullOrWhiteSpace([string]$httpsProxy)) { $null } else { ([string]$httpsProxy).Trim() }
        noProxy = if ([string]::IsNullOrWhiteSpace([string]$noProxy)) { $null } else { ([string]$noProxy).Trim() }
        desktopLauncher = if ([string]::IsNullOrWhiteSpace([string]$desktopValue)) { 'auto' } else { ([string]$desktopValue).Trim() }
        codexExecutable = if ([string]::IsNullOrWhiteSpace([string]$codexValue)) { 'auto' } else { ([string]$codexValue).Trim() }
        updatedAt = (Get-Date).ToUniversalTime().ToString('o')
    }
    $saved = Save-ProxyConfiguration $record 'settings-update'
    $settings = Get-SettingsRecord
    return [ordered]@{
        ok = $true
        action = 'settings-update'
        configPath = $saved.configPath
        values = $settings.values
    }
}

function Invoke-Configure {
    if ($Confirmation -ne $applyConfirmation) {
        throw "confirmation must exactly match `"$applyConfirmation`""
    }
    Assert-ProxyUrl 'proxyUrl' $ProxyUrl
    Assert-ProxyUrl 'httpProxy' $HttpProxy
    Assert-ProxyUrl 'httpsProxy' $HttpsProxy
    if ([string]::IsNullOrWhiteSpace($ProxyUrl) -and
        [string]::IsNullOrWhiteSpace($HttpProxy) -and
        [string]::IsNullOrWhiteSpace($HttpsProxy)) {
        throw 'At least one of proxyUrl, httpProxy, or httpsProxy is required'
    }
    $record = [ordered]@{
        schemaVersion = 1
        proxyUrl = if ([string]::IsNullOrWhiteSpace($ProxyUrl)) { $null } else { $ProxyUrl.Trim() }
        httpProxy = if ([string]::IsNullOrWhiteSpace($HttpProxy)) { $null } else { $HttpProxy.Trim() }
        httpsProxy = if ([string]::IsNullOrWhiteSpace($HttpsProxy)) { $null } else { $HttpsProxy.Trim() }
        noProxy = if ([string]::IsNullOrWhiteSpace($NoProxy)) { $null } else { $NoProxy.Trim() }
        desktopLauncher = if ([string]::IsNullOrWhiteSpace($DesktopLauncher)) { 'auto' } else { $DesktopLauncher.Trim() }
        codexExecutable = if ([string]::IsNullOrWhiteSpace($CodexExecutable)) { 'auto' } else { $CodexExecutable.Trim() }
        updatedAt = (Get-Date).ToUniversalTime().ToString('o')
    }
    return Save-ProxyConfiguration $record 'configure'
}

function Invoke-Clear {
    if ($Confirmation -ne $clearConfirmation) {
        throw "confirmation must exactly match `"$clearConfirmation`""
    }
    $config = Read-ProxyConfig
    if (-not $config) {
        return [ordered]@{
            ok = $true
            action = 'clear'
            alreadyUnconfigured = $true
        }
    }
    $configBackup = Backup-ProxyConfig
    $processProxyState = Test-ConfiguredProxyEnvironment $config 'process'
    $environment = Remove-ManagedUserEnvironment $config
    if (-not $DryRun -and (Test-Path -LiteralPath $configPath -PathType Leaf)) {
        Remove-Item -LiteralPath $configPath -Force
    }
    return [ordered]@{
        ok = $true
        action = 'clear'
        dryRun = [bool]$DryRun
        configBackup = $configBackup
        environment = $environment
        restartRequired = [bool]$processProxyState.usesConfiguredProxy
        message = 'Proxy settings were removed. Fully quit and reopen Codex to stop using the proxy in the current process.'
    }
}

function Invoke-Launch {
    if ($Confirmation -ne 'LAUNCH CODEX WITH PROXY') {
        throw 'confirmation must exactly match "LAUNCH CODEX WITH PROXY"'
    }
    $config = Read-ProxyConfig
    if (-not $config) {
        throw 'Configure the proxy before launching Codex'
    }
    $processState = Get-CodexProcessState
    if ($processState.anyRunning) {
        $record = New-LaunchEvidence $config 'blocked-running' $null (
            'ChatGPT/Codex is already running. Proxy for Codex will not stop or restart it.'
        )
        return [ordered]@{
            ok = $false
            action = 'launch'
            status = 'blocked-running'
            process = $processState
            evidence = $record
            message = 'Close the existing ChatGPT/Codex app yourself, then start it from a normal Codex entry point.'
        }
    }
    $launcher = Resolve-DesktopLauncher $config.desktopLauncher
    if (-not $launcher.path) {
        throw 'ChatGPT/Codex desktop launcher was not detected'
    }
    $proxy = Get-ProxyValue $config.proxyUrl $null
    $http = Get-ProxyValue $config.httpProxy $proxy
    $https = Get-ProxyValue $config.httpsProxy $proxy
    if ($DryRun) {
        return [ordered]@{
            ok = $true
            action = 'launch'
            dryRun = $true
            status = 'ready'
            desktopLauncher = $launcher
            httpProxy = Get-SafeProxySummary 'HTTP_PROXY' $http
            httpsProxy = Get-SafeProxySummary 'HTTPS_PROXY' $https
            noProxyConfigured = -not [string]::IsNullOrWhiteSpace([string]$config.noProxy)
        }
    }
    $env:HTTP_PROXY = $http
    $env:HTTPS_PROXY = $https
    $env:NO_PROXY = $config.noProxy
    $env:http_proxy = $http
    $env:https_proxy = $https
    $env:no_proxy = $config.noProxy
    $started = Start-Process `
        -FilePath $launcher.path `
        -WorkingDirectory (Split-Path -Parent $launcher.path) `
        -PassThru
    $evidence = New-LaunchEvidence $config 'launched' $started $null
    return [ordered]@{
        ok = $true
        action = 'launch'
        status = 'launched'
        desktopLauncher = $launcher
        launcherPid = [int]$started.Id
        evidence = $evidence
    }
}

$result = switch ($Action) {
    'status' { Get-StatusRecord }
    'configure' { Invoke-Configure }
    'settings-read' { Get-SettingsRecord }
    'settings-update' { Invoke-SettingsUpdate }
    'clear' { Invoke-Clear }
    'launch' { Invoke-Launch }
}

$result | ConvertTo-Json -Depth 10
