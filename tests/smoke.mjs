import { spawn } from 'node:child_process';
import { mkdir, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { createInterface } from 'node:readline';
import { fileURLToPath } from 'node:url';

const testDir = dirname(fileURLToPath(import.meta.url));
const pluginRoot = resolve(testDir, '..');
const mcpEntrypoint = join(pluginRoot, 'scripts', 'launch-mcp.mjs');
const runRoot = join(tmpdir(), `cpl-mcp-${Date.now()}`);
const withProxyHome = join(runRoot, 'with-proxy-home');
const environmentStore = join(runRoot, 'user-environment.json');
const expectedTools = new Set([
  'settings.read',
  'settings.update',
  'get_codex_proxy_status',
  'configure_codex_proxy',
  'clear_codex_proxy',
  'launch_proxy_for_codex',
]);

await mkdir(runRoot, { recursive: true });

const child = spawn(process.execPath, [mcpEntrypoint], {
  cwd: pluginRoot,
  env: {
    ...process.env,
    PROXY_FOR_CODEX_HOME: withProxyHome,
    PROXY_FOR_CODEX_ENVIRONMENT_STORE: environmentStore,
  },
  stdio: ['pipe', 'pipe', 'pipe'],
  windowsHide: true,
});

const lines = createInterface({ input: child.stdout });
const pending = new Map();
const stderr = [];

child.stderr.on('data', (chunk) => {
  stderr.push(chunk.toString());
});

lines.on('line', (line) => {
  let message;
  try {
    message = JSON.parse(line);
  } catch {
    return;
  }
  if (message.id && pending.has(message.id)) {
    pending.get(message.id)(message);
    pending.delete(message.id);
  }
});

function request(id, method, params = {}) {
  return new Promise((resolveRequest, rejectRequest) => {
    const timer = setTimeout(() => {
      pending.delete(id);
      rejectRequest(new Error(`Timed out waiting for ${method}`));
    }, 30_000);
    pending.set(id, (message) => {
      clearTimeout(timer);
      if (message.error) {
        rejectRequest(new Error(`${method}: ${message.error.message}`));
        return;
      }
      resolveRequest(message.result);
    });
    child.stdin.write(`${JSON.stringify({ jsonrpc: '2.0', id, method, params })}\n`);
  });
}

function parseToolResult(result, toolName) {
  if (result.isError) {
    throw new Error(result.content?.[0]?.text || `${toolName} failed`);
  }
  return result.structuredContent
    ?? JSON.parse(result.content?.[0]?.text || '{}');
}

try {
  const initialized = await request(1, 'initialize', {
    protocolVersion: '2025-11-25',
    capabilities: {},
    clientInfo: {
      name: 'proxy-for-codex-smoke',
      version: '0.4.0',
    },
  });
  child.stdin.write(`${JSON.stringify({
    jsonrpc: '2.0',
    method: 'notifications/initialized',
    params: {},
  })}\n`);

  const settingsCapability = (
    initialized.capabilities?.experimental?.['openai/settings']
    || initialized.capabilities?.extensions?.['openai/settings']
  );
  if (
    settingsCapability?.readTool !== 'settings.read'
    || settingsCapability?.updateTool !== 'settings.update'
  ) {
    throw new Error(`Missing openai/settings capability: ${JSON.stringify(initialized)}`);
  }

  const listed = await request(2, 'tools/list');
  const listedTools = listed.tools || [];
  const names = new Set(listedTools.map((tool) => tool.name));
  const missing = [...expectedTools].filter((name) => !names.has(name));
  const unexpected = [...names].filter((name) => !expectedTools.has(name));
  if (missing.length > 0 || unexpected.length > 0) {
    throw new Error(`Unexpected MCP tool set; missing: ${missing.join(', ') || 'none'}; extra: ${unexpected.join(', ') || 'none'}`);
  }
  const settingsReadTool = listedTools.find((tool) => tool.name === 'settings.read');
  const settingsUpdateTool = listedTools.find((tool) => tool.name === 'settings.update');
  if (
    !settingsReadTool?.outputSchema
    || settingsReadTool.annotations?.readOnlyHint !== true
    || settingsReadTool._meta?.ui?.visibility?.[0] !== 'app'
    || !settingsUpdateTool?.outputSchema
    || settingsUpdateTool._meta?.ui?.visibility?.[0] !== 'app'
  ) {
    throw new Error(`Unexpected settings tool metadata: ${JSON.stringify(listedTools)}`);
  }

  const settingsBefore = parseToolResult(
    await request(3, 'tools/call', {
      name: 'settings.read',
      arguments: {},
    }),
    'settings.read',
  );
  if (
    settingsBefore.schema?.type !== 'object'
    || settingsBefore.values?.httpProxy !== 'http://127.0.0.1:7897'
    || settingsBefore.values?.httpsProxy !== 'http://127.0.0.1:7897'
    || Object.hasOwn(settingsBefore.values || {}, 'proxyUrl')
    || Object.hasOwn(settingsBefore.values || {}, 'applyMode')
    || Object.hasOwn(settingsBefore.values || {}, 'shortcutLocations')
    || !Object.hasOwn(settingsBefore.schema?.properties || {}, 'httpProxy')
    || !Object.hasOwn(settingsBefore.schema?.properties || {}, 'httpsProxy')
    || Object.hasOwn(settingsBefore.schema?.properties || {}, 'proxyUrl')
    || Object.hasOwn(settingsBefore.schema?.properties || {}, 'applyMode')
    || Object.hasOwn(settingsBefore.schema?.properties || {}, 'shortcutLocations')
    || !Array.isArray(settingsBefore.layout)
  ) {
    throw new Error(`Unexpected initial settings: ${JSON.stringify(settingsBefore)}`);
  }

  const initialStatus = parseToolResult(
    await request(4, 'tools/call', {
      name: 'get_codex_proxy_status',
      arguments: {},
    }),
    'get_codex_proxy_status',
  );
  if (initialStatus.configured !== false) {
    throw new Error(`Expected an unconfigured Proxy for Codex instance: ${JSON.stringify(initialStatus)}`);
  }

  const configured = parseToolResult(
    await request(5, 'tools/call', {
      name: 'configure_codex_proxy',
      arguments: {
        proxyUrl: 'http://127.0.0.1:7897',
        noProxy: 'localhost,127.0.0.1,::1',
        desktopLauncher: 'auto',
        codexExecutable: 'auto',
        confirmation: 'APPLY CODEX PROXY',
      },
    }),
    'configure_codex_proxy',
  );
  if (
    configured.httpProxy?.present !== true
    || configured.requiresRestart !== true
    || configured.launchPolicy !== 'normal-windows-entrypoints'
  ) {
    throw new Error(`Unexpected configure result: ${JSON.stringify(configured)}`);
  }

  const settingsUpdated = parseToolResult(
    await request(6, 'tools/call', {
      name: 'settings.update',
      arguments: {
        set: {
          noProxy: 'localhost,127.0.0.1,::1,.local',
        },
      },
    }),
    'settings.update',
  );
  if (
    settingsUpdated.values?.noProxy !== 'localhost,127.0.0.1,::1,.local'
    || settingsUpdated.values?.httpProxy !== 'http://127.0.0.1:7897'
    || settingsUpdated.values?.httpsProxy !== 'http://127.0.0.1:7897'
    || Object.hasOwn(settingsUpdated.values || {}, 'applyMode')
    || Object.hasOwn(settingsUpdated.values || {}, 'shortcutLocations')
  ) {
    throw new Error(`Unexpected settings update: ${JSON.stringify(settingsUpdated)}`);
  }

  const independentSettings = parseToolResult(
    await request(7, 'tools/call', {
      name: 'settings.update',
      arguments: {
        set: {
          httpProxy: 'http://127.0.0.1:7898',
        },
      },
    }),
    'settings.update',
  );
  if (
    independentSettings.values?.httpProxy !== 'http://127.0.0.1:7898'
    || independentSettings.values?.httpsProxy !== 'http://127.0.0.1:7897'
  ) {
    throw new Error(`HTTP and HTTPS proxy settings were not independent: ${JSON.stringify(independentSettings)}`);
  }

  const configuredStatus = parseToolResult(
    await request(8, 'tools/call', {
      name: 'get_codex_proxy_status',
      arguments: {},
    }),
    'get_codex_proxy_status',
  );
  if (
    configuredStatus.configured !== true
    || configuredStatus.launchPolicy !== 'normal-windows-entrypoints'
    || configuredStatus.userEnvironmentUsesProxy !== true
    || configuredStatus.nextLaunchUsesProxy !== true
    || configuredStatus.noProxy !== 'localhost,127.0.0.1,::1,.local'
    || configuredStatus.httpProxy?.display !== 'http://127.0.0.1:7898'
    || configuredStatus.httpsProxy?.display !== 'http://127.0.0.1:7897'
    || configuredStatus.environment?.user?.NO_PROXY?.value !== 'localhost,127.0.0.1,::1,.local'
    || configuredStatus.environment?.user?.HTTP_PROXY?.display !== 'http://127.0.0.1:7898'
    || configuredStatus.environment?.user?.HTTPS_PROXY?.display !== 'http://127.0.0.1:7897'
    || !Object.hasOwn(configuredStatus, 'proxyConnections')
    || Object.hasOwn(configuredStatus, 'shortcuts')
    || Object.hasOwn(configuredStatus, 'applyMode')
  ) {
    throw new Error(`Unexpected configured status: ${JSON.stringify(configuredStatus)}`);
  }

  const cleared = parseToolResult(
    await request(9, 'tools/call', {
      name: 'clear_codex_proxy',
      arguments: {
        confirmation: 'REMOVE CODEX PROXY',
      },
    }),
    'clear_codex_proxy',
  );
  if (cleared.ok !== true) {
    throw new Error(`Unexpected clear result: ${JSON.stringify(cleared)}`);
  }

  console.log(JSON.stringify({
    ok: true,
    server: initialized.serverInfo,
    tools: [...expectedTools],
    initialConfigured: initialStatus.configured,
    launchPolicy: configured.launchPolicy,
    settingsUpdated: settingsUpdated.values.noProxy,
    configuredReady: configuredStatus.ready,
    cleared: cleared.ok,
  }, null, 2));
} catch (error) {
  if (stderr.length > 0) {
    process.stderr.write(stderr.join(''));
  }
  console.error(error.message);
  process.exitCode = 1;
} finally {
  child.kill();
  await rm(runRoot, { recursive: true, force: true });
}
