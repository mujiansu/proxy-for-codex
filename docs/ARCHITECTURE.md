# Architecture

## Boundary

Proxy for Codex only configures proxy access and optional process startup.
It does not delegate tasks, manage chats, or control the Codex process lifecycle.

The plugin is loaded after Codex starts, so it cannot change the environment of
the process that loaded it. It persists proxy variables in the current user's
environment. After one full restart, normal Codex entry points inherit them.

The plugin never terminates, closes, or restarts an existing Codex process.

## Call chain

```text
Codex MCP client
  -> proxy_for_codex MCP server
  -> scripts/proxy-for-codex.ps1
  -> config + environment backup
  -> user-environment update
```

Native settings chain:

```text
Plugin details page
  -> settings.read
  -> settings.update
  -> scripts/proxy-for-codex.ps1 -Action settings-update
  -> shared configuration and environment backup path
```

`settings.read` and `settings.update` are advertised through
`openai/settings` and marked app-only so model-driven changes continue to use
the confirmation-guarded `configure_codex_proxy` tool.

Normal launch chain after one restart:

```text
Normal Codex entry point
  -> Windows starts ChatGPT/Codex
  -> inherited HTTP_PROXY / HTTPS_PROXY / NO_PROXY
```

Optional process-scoped launch chain:

```text
launch_proxy_for_codex MCP tool
  -> proxy-for-codex.ps1 -Action launch
  -> reject if ChatGPT/Codex is already running
  -> set process-local HTTP_PROXY / HTTPS_PROXY / NO_PROXY
  -> Start-Process detected ChatGPT/Codex executable
```

No shortcut is installed for this optional tool.

## Discovery

Desktop launcher candidates:

- `%LOCALAPPDATA%\Microsoft\WindowsApps\chatgpt-desktop.exe`
- `%LOCALAPPDATA%\Microsoft\WindowsApps\ChatGPT.exe`
- `OpenAI.Codex` AppX package `app\ChatGPT.exe`
- Explicit `desktopLauncher` config value

Codex app-server candidates:

- `%LOCALAPPDATA%\OpenAI\Codex\bin\**\codex.exe`
- `%LOCALAPPDATA%\Programs\OpenAI\Codex\bin\**\codex.exe`
- Explicit `codexExecutable` config value

VS Code extension copies of `codex.exe` are excluded from process checks.
