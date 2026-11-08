# Operations

## Install

Add the repository marketplace and install the plugin from Codex:

```powershell
codex plugin marketplace add https://github.com/mujiansu/proxy-for-codex.git --sparse .agents/plugins
codex plugin add proxy-for-codex@proxy-for-codex
```

The installed plugin includes a bundled MCP runtime, so no separate
`npm install` is required.

## Check status

Call `get_codex_proxy_status` from the plugin.

The result includes:

- Whether a configuration exists
- Redacted proxy summaries
- Detected desktop launcher and Codex executable
- Running ChatGPT/Codex counts
- Process and user proxy environment summaries

## Configure normal Codex launches

The primary path is the plugin details page:

1. Open the Proxy for Codex plugin settings.
2. Set the HTTP proxy URL and HTTPS proxy URL independently. Both default to
   `http://127.0.0.1:7897` for a common local-proxy setup.
3. Save the settings.
4. Fully close and reopen Codex once.

The settings page reads and writes the same configuration file and backups
used by the MCP tools. Updating only the HTTP or HTTPS field preserves the
other effective value. The page does not expose stored proxy credentials; a
value shown as `<redacted>` must be re-entered before changing that field.

The plugin's Codex MCP configuration must include `settings.read` and
`settings.update` in `enabled_tools`. The installer repairs an existing
five-tool whitelist in place and preserves the original configuration in its
installation backup.

When working through the model, call `configure_codex_proxy` with:

```text
proxyUrl: http://127.0.0.1:7897
confirmation: APPLY CODEX PROXY
```

Fully close and reopen Codex once. Later launches from the normal Windows entry
points inherit the proxy.

After reopening, call `get_codex_proxy_status`. The expected state is
`currentProcessUsesProxy: true`.

Codex can scrub proxy variables from MCP tool subprocesses even when its main
network process is using the proxy. In that case,
`processEnvironmentInheritedProxy` may be false while
`proxyConnections.connectionCount` is greater than zero. Either signal sets
`currentProcessUsesProxy` when the configured proxy is active.

## Clear

Call `clear_codex_proxy` with:

```text
confirmation: REMOVE CODEX PROXY
```

The script removes values only when they still match what the plugin wrote. If
a value was changed externally, it is preserved. The latest environment backup
is used to restore previous values.

## Launch blocked

`status: blocked-running` means the ChatGPT/Codex host or application server is
already running. Close it through the app's own UI and then start Codex from its
normal Windows entry point. The plugin does not stop it.

## Backups

```text
%USERPROFILE%\.proxy-for-codex\backups\
%USERPROFILE%\.proxy-for-codex\environment-backups\
```

Installation backups are created under the plugin's `backups` directory.
