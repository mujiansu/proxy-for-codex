# Security

## Scope

The plugin affects future Windows processes that inherit the current user's
environment. It does not claim that an already-running Codex process can be
updated. The user must fully close and reopen Codex once.

Disabling a plugin does not run a cleanup command. Users should clear
plugin-managed user-environment values before disabling the plugin.

## No lifecycle control

The plugin does not expose a stop, terminate, close, or restart operation. If
Codex is already running, launch is blocked.

## Confirmation phrases

- Configuration: `APPLY CODEX PROXY`
- Clear: `REMOVE CODEX PROXY`
- Launch: `LAUNCH CODEX WITH PROXY`

These phrases prevent accidental mutation while keeping the actions callable
from a new Codex chat.

The native settings tools are app-only and excluded from model visibility.
Saving from the plugin details page is an explicit user action, so it does not
weaken the phrase guard on model-facing mutation tools.

## Credential handling

Proxy credentials are never returned by status or launch evidence. The output
shows `<redacted>@` and a `hasCredentials` flag.

Structured settings also return `<redacted>@`. If that placeholder is submitted
without re-entering the complete proxy URL, the update is rejected.

The config file can contain a proxy URL with credentials because the plugin
must use it. Keep `%USERPROFILE%\.proxy-for-codex` private. Do not commit
it to source control.

## Environment restoration

Before configuration, the plugin snapshots all six proxy environment names in
uppercase and lowercase. Clear restores the latest snapshot only for values
that still match the plugin-managed value. Externally changed values are
preserved.

## Process ownership

The plugin closes no processes. In its optional direct launch operation, it may
start a ChatGPT/Codex process only when no existing desktop host or desktop
app-server is detected.
