# Validation

## 0.4.0

The regression script verifies:

- PowerShell syntax
- Seven JSON manifests, including the direct-install marketplace
- Square SVG listing icons and the multi-size Windows ICO
- Node syntax for the MCP source, bundled runtime, bundle normalizer, launcher,
  and smoke test
- MCP startup without `server/node_modules`
- Unconfigured status in an isolated launcher home
- User-environment mode as the default configuration
- Isolated user-environment writes, matching status, and restoration
- Repeated configuration while retaining the original environment backup
- Proxy credential redaction
- Clear behavior without changing the real user proxy environment
- MCP initialize, `openai/settings` capability advertisement, app-only
  visibility, native settings read/update, independent HTTP and HTTPS proxy
  values, and the six remaining tools
- Legacy runtime directory and environment-variable compatibility

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\test.ps1
```

The launch operation is deliberately not exercised while the current Codex
desktop host is running. A live proxy launch requires closing Codex through
its own UI, which is outside this plugin's lifecycle scope.
