---
name: proxy-for-codex
description: Configure, inspect, or use Proxy for Codex on Windows. Use when ChatGPT/Codex should access remote services through an HTTP or HTTPS proxy without restarting an existing process.
---

# Use Proxy for Codex

Use `get_codex_proxy_status` first.

When the plugin details page is available, direct the user to its native
settings for the HTTP proxy URL, HTTPS proxy URL, bypass list, and launch mode.
Changing one proxy field preserves the other. Those settings reuse the same
validated configuration path and are the preferred configuration UI.

Use `configure_codex_proxy` only with the exact confirmation
`APPLY CODEX PROXY`. The tool stores persistent user environment variables so
future launches from normal Windows entry points inherit the proxy. Tell the
user to fully close and reopen Codex once. Do not create or recommend a separate
proxy shortcut.

Use `launch_proxy_for_codex` only when the user asks to start Codex and no
ChatGPT/Codex process is running. If it returns `blocked-running`, tell the
user to close the app through its own UI. Do not close or restart it.

Use `clear_codex_proxy` with `REMOVE CODEX PROXY` when the user asks to remove
the configuration.
