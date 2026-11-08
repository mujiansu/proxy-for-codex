---
name: proxy-for-codex-setup
description: Install and validate the Proxy for Codex plugin on Windows. Use when the user wants Codex to start with an HTTP or HTTPS proxy.
---

# Proxy for Codex Setup

1. Confirm that the plugin was installed from the Proxy for Codex marketplace.
2. Open the plugin details page and use its native settings when available.
   Configure the HTTP proxy URL and HTTPS proxy URL independently, then
   confirm the bypass list.
3. Otherwise call `get_codex_proxy_status`, then use
   `configure_codex_proxy` only when the user supplied a proxy URL.
4. Tell the user to fully close and reopen Codex once. Later launches from
   normal Windows entry points will inherit the proxy.
5. After the restart, call `get_codex_proxy_status` and confirm
   `currentProcessUsesProxy` is true.
6. Report the configuration path, restart evidence, backups, and validation
   evidence.

Never add a stop, close, or restart operation. An existing Codex process keeps
its original environment.
