# Changelog

## 0.4.0 - 2026-11-08

- Renamed the project and plugin to Proxy for Codex.
- Unified identifiers as `proxy-for-codex` and `proxy_for_codex`.
- Renamed the public GitHub repository to `proxy-for-codex`.
- Added a repository marketplace so Codex can install the plugin directly from
  GitHub without cloning the project or running `npm install`.
- Bundled the MCP runtime and simplified the README around direct installation.
- Migrated the runtime directory to `%USERPROFILE%\.proxy-for-codex`.
- Added compatibility for the previous Codex with Proxy naming, plus the
  original launcher runtime directory, environment variables, marketplace
  entry, MCP configuration, and cache path.

## 0.3.0 - 2026-11-08

- Removed the dedicated `Codex (Proxy)` shortcut and its installation tool.
- Simplified configuration to persistent user environment proxies for all
  normal Codex entry points.
- Removed launch-mode and shortcut-location settings while preserving
  compatibility with older configuration files.
- Updated the installer to remove the obsolete shortcut tool from existing
  Codex MCP tool whitelists and point the MCP server at version `0.3.0`.

## 0.2.0 - 2026-11-08

- Made user-environment mode the default so normal Codex entry points use the
  configured proxy after one full restart.
- Added current-process, next-launch, and restart-required status fields.
- Kept the dedicated shortcut and direct launch tools as optional
  process-scoped fallbacks.
- Added native plugin settings through `openai/settings`, with app-only
  `settings.read` and `settings.update` tools.
- Split proxy configuration into independent HTTP and HTTPS settings while
  retaining `proxyUrl` compatibility for existing configurations and MCP calls.
- Updated the installer to repair existing MCP tool whitelists so Codex renders
  the native settings section.
- Added light and dark listing/composer icons plus a multi-size Windows ICO.
- Made the optional fallback shortcut use a stable copy of the plugin icon.
- Added isolated user-environment testing without modifying real Windows proxy
  variables.
- Updated onboarding, documentation, validation, and package versioning.

## 0.1.0 - 2026-11-08

- Added a standalone Proxy for Codex plugin.
- Added shortcut mode for process-scoped proxy startup.
- Added explicit opt-in user-environment mode.
- Added automatic discovery of ChatGPT/Codex and Codex app-server executables.
- Added five MCP tools for status, configure, clear, shortcut installation, and
  non-destructive proxy launch.
- Added configuration, environment, and launch evidence backups.
- Added explicit confirmation phrases and proxy credential redaction.
- Added MCP smoke tests, isolated PowerShell tests, ZIP packaging, and local
  cache installation.
