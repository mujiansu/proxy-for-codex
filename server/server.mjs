#!/usr/bin/env node

import { execFile } from 'node:child_process';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { z } from 'zod';

const VERSION = '0.4.0';
const APPLY_CONFIRMATION = 'APPLY CODEX PROXY';
const CLEAR_CONFIRMATION = 'REMOVE CODEX PROXY';
const LAUNCH_CONFIRMATION = 'LAUNCH CODEX WITH PROXY';
const SETTINGS_READ_TOOL = 'settings.read';
const SETTINGS_UPDATE_TOOL = 'settings.update';
const execFileAsync = promisify(execFile);
const serverDir = dirname(fileURLToPath(import.meta.url));
const pluginRoot = resolve(serverDir, '..');
const runtimeScript = join(pluginRoot, 'scripts', 'proxy-for-codex.ps1');
const powershell = process.env.PROXY_FOR_CODEX_POWERSHELL
  || process.env.CODEX_WITH_PROXY_POWERSHELL
  || process.env.CODEX_PROXY_POWERSHELL
  || join(process.env.SystemRoot || 'C:\\Windows', 'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe');

const server = new McpServer({
  name: 'proxy-for-codex',
  version: VERSION,
});

const settingsValuesSchema = z.object({
  httpProxy: z.string().trim().min(1).max(4096),
  httpsProxy: z.string().trim().min(1).max(4096),
  noProxy: z.string().trim().max(4096),
  desktopLauncher: z.string().trim().max(4096),
  codexExecutable: z.string().trim().max(4096),
}).strict();

const settingsReadOutputSchema = {
  schema: z.object({
    type: z.literal('object'),
    properties: z.record(z.string(), z.record(z.string(), z.unknown())),
    required: z.array(z.string()).optional(),
  }),
  values: z.record(z.string(), z.unknown()),
  layout: z.array(z.record(z.string(), z.unknown())).optional(),
};

const settingsUpdateOutputSchema = {
  values: z.record(z.string(), z.unknown()),
};

const settingsSchema = {
  type: 'object',
  properties: {
    httpProxy: {
      type: 'string',
      title: 'HTTP proxy URL',
      description: 'Value written to HTTP_PROXY for future ChatGPT/Codex launches. Credentials shown as <redacted> must be re-entered if this value is changed.',
      maxLength: 4096,
      pattern: '^https?://',
    },
    httpsProxy: {
      type: 'string',
      title: 'HTTPS proxy URL',
      description: 'Value written to HTTPS_PROXY for future ChatGPT/Codex launches. Credentials shown as <redacted> must be re-entered if this value is changed.',
      maxLength: 4096,
      pattern: '^https?://',
    },
    noProxy: {
      type: 'string',
      title: 'Bypass list',
      description: 'Comma-separated hosts that should connect directly.',
      maxLength: 4096,
    },
    desktopLauncher: {
      type: 'string',
      title: 'ChatGPT/Codex executable',
      description: 'Use auto to detect the desktop launcher, or enter an explicit executable path.',
      maxLength: 4096,
    },
    codexExecutable: {
      type: 'string',
      title: 'Codex app-server executable',
      description: 'Use auto to detect the Codex app-server, or enter an explicit executable path.',
      maxLength: 4096,
    },
  },
  required: [
    'httpProxy',
    'httpsProxy',
    'noProxy',
    'desktopLauncher',
    'codexExecutable',
  ],
};

const settingsLayout = [
  {
    kind: 'group',
    title: 'Proxy',
    items: [
      { kind: 'property', property: 'httpProxy' },
      { kind: 'property', property: 'httpsProxy' },
      { kind: 'property', property: 'noProxy' },
    ],
  },
  {
    kind: 'group',
    title: 'Codex integration',
    items: [
      { kind: 'tool', tool: 'get_codex_proxy_status' },
    ],
  },
  {
    kind: 'group',
    title: 'Advanced paths',
    items: [
      { kind: 'property', property: 'desktopLauncher' },
      { kind: 'property', property: 'codexExecutable' },
    ],
  },
];

const settingsCapability = {
  'openai/settings': {
    readTool: SETTINGS_READ_TOOL,
    updateTool: SETTINGS_UPDATE_TOOL,
  },
};

function assertWindows() {
  if (process.platform !== 'win32') {
    throw new Error('Proxy for Codex currently supports Windows only');
  }
}

function compactError(error) {
  return [
    error?.message,
    error?.stdout?.trim(),
    error?.stderr?.trim(),
  ].filter(Boolean).join('\n');
}

async function runWithProxy(action, parameters = {}, extraArgs = []) {
  assertWindows();
  const args = [
    '-NoProfile',
    '-NonInteractive',
    '-ExecutionPolicy',
    'Bypass',
    '-File',
    runtimeScript,
    '-Action',
    action,
  ];
  for (const [name, value] of Object.entries(parameters)) {
    if (value === null || value === undefined || value === '') continue;
    if (Array.isArray(value)) {
      args.push(`-${name}`, value.join(','));
    } else if (value === true) {
      args.push(`-${name}`);
    } else if (value !== false) {
      args.push(`-${name}`, String(value));
    }
  }
  args.push(...extraArgs);
  try {
    const { stdout } = await execFileAsync(powershell, args, {
      cwd: pluginRoot,
      env: process.env,
      windowsHide: true,
      maxBuffer: 2 * 1024 * 1024,
      timeout: 120_000,
    });
    const text = stdout.trim();
    if (!text) throw new Error(`Proxy for Codex action ${action} returned no output`);
    return JSON.parse(text);
  } catch (error) {
    throw new Error(`Proxy for Codex action ${action} failed:\n${compactError(error)}`);
  }
}

function textResult(value) {
  return {
    content: [{
      type: 'text',
      text: typeof value === 'string' ? value : JSON.stringify(value, null, 2),
    }],
  };
}

function structuredResult(value) {
  return {
    content: [{
      type: 'text',
      text: JSON.stringify(value, null, 2),
    }],
    structuredContent: value,
  };
}

function errorResult(error) {
  return {
    isError: true,
    content: [{ type: 'text', text: error.message }],
  };
}

function getSettingsPayload(raw) {
  return {
    schema: settingsSchema,
    values: raw?.values || {},
    layout: settingsLayout,
  };
}

server.server.registerCapabilities({
  experimental: settingsCapability,
  extensions: settingsCapability,
});

server.registerTool(
  SETTINGS_READ_TOOL,
  {
    title: 'Read Proxy for Codex settings',
    description: 'Return the native plugin settings schema and current redacted proxy configuration. This tool is called by the plugin details page.',
    inputSchema: {},
    outputSchema: settingsReadOutputSchema,
    annotations: {
      readOnlyHint: true,
      openWorldHint: false,
    },
    _meta: {
      ui: {
        visibility: ['app'],
      },
    },
  },
  async () => {
    try {
      return structuredResult(getSettingsPayload(await runWithProxy('settings-read')));
    } catch (error) {
      return errorResult(error);
    }
  },
);

server.registerTool(
  SETTINGS_UPDATE_TOOL,
  {
    title: 'Update Proxy for Codex settings',
    description: 'Persist changes made on the native plugin settings page. This tool is app-only so model calls continue to use the confirmation-guarded configuration tool.',
    inputSchema: {
      set: settingsValuesSchema.partial().refine(
        (value) => Object.keys(value).length > 0,
        'At least one setting must be provided',
      ),
    },
    outputSchema: settingsUpdateOutputSchema,
    annotations: {
      readOnlyHint: false,
      destructiveHint: false,
      openWorldHint: false,
    },
    _meta: {
      ui: {
        visibility: ['app'],
      },
    },
  },
  async ({ set }) => {
    try {
      const parameters = {};
      if (Object.hasOwn(set, 'httpProxy')) parameters.HttpProxy = set.httpProxy;
      if (Object.hasOwn(set, 'httpsProxy')) parameters.HttpsProxy = set.httpsProxy;
      if (Object.hasOwn(set, 'noProxy')) parameters.NoProxy = set.noProxy;
      if (Object.hasOwn(set, 'desktopLauncher')) {
        parameters.DesktopLauncher = set.desktopLauncher;
      }
      if (Object.hasOwn(set, 'codexExecutable')) {
        parameters.CodexExecutable = set.codexExecutable;
      }
      const updated = await runWithProxy('settings-update', parameters);
      return structuredResult({ values: updated?.values || {} });
    } catch (error) {
      return errorResult(error);
    }
  },
);

server.registerTool(
  'get_codex_proxy_status',
  {
    title: 'Get Proxy for Codex status',
    description: 'Read the configured proxy, normal-launch readiness, restart requirement, detected ChatGPT/Codex paths, and running-process state. Proxy credentials are redacted.',
    inputSchema: {},
    annotations: {
      readOnlyHint: true,
      openWorldHint: false,
    },
  },
  async () => {
    try {
      return textResult(await runWithProxy('status'));
    } catch (error) {
      return errorResult(error);
    }
  },
);

server.registerTool(
  'configure_codex_proxy',
  {
    title: 'Configure Codex proxy',
    description: 'Save proxy settings for future Codex launches. Persistent user environment variables make Codex launched from normal Windows entry points inherit the proxy after one full restart. This never restarts Codex.',
    inputSchema: {
      proxyUrl: z.string().trim().min(1).max(4096).describe(
        'HTTP or HTTPS proxy URL, for example http://127.0.0.1:7897.',
      ),
      httpProxy: z.string().trim().max(4096).optional().describe(
        'Optional HTTP_PROXY override. Defaults to proxyUrl.',
      ),
      httpsProxy: z.string().trim().max(4096).optional().describe(
        'Optional HTTPS_PROXY override. Defaults to proxyUrl.',
      ),
      noProxy: z.string().trim().max(4096).default('localhost,127.0.0.1,::1'),
      desktopLauncher: z.string().trim().max(4096).default('auto'),
      codexExecutable: z.string().trim().max(4096).default('auto'),
      confirmation: z.literal(APPLY_CONFIRMATION),
    },
    annotations: {
      readOnlyHint: false,
      destructiveHint: false,
      openWorldHint: false,
    },
  },
  async (input) => {
    try {
      return textResult(await runWithProxy('configure', input));
    } catch (error) {
      return errorResult(error);
    }
  },
);

server.registerTool(
  'clear_codex_proxy',
  {
    title: 'Clear Codex proxy configuration',
    description: 'Remove plugin-managed proxy settings. In user-environment mode, values are removed only when they still match what this plugin wrote, so unrelated user proxy settings are preserved.',
    inputSchema: {
      confirmation: z.literal(CLEAR_CONFIRMATION),
    },
    annotations: {
      readOnlyHint: false,
      destructiveHint: true,
      openWorldHint: false,
    },
  },
  async ({ confirmation }) => {
    try {
      return textResult(await runWithProxy('clear', { confirmation }));
    } catch (error) {
      return errorResult(error);
    }
  },
);

server.registerTool(
  'launch_proxy_for_codex',
  {
    title: 'Launch Codex with proxy',
    description: 'Launch a new ChatGPT/Codex desktop process with the saved proxy variables. Refuses to act when any ChatGPT/Codex host or desktop app-server is already running. It never stops or restarts an existing process.',
    inputSchema: {
      confirmation: z.literal(LAUNCH_CONFIRMATION),
    },
    annotations: {
      readOnlyHint: false,
      destructiveHint: false,
      openWorldHint: false,
    },
  },
  async ({ confirmation }) => {
    try {
      return textResult(await runWithProxy('launch', { confirmation }));
    } catch (error) {
      return errorResult(error);
    }
  },
);

const transport = new StdioServerTransport();
await server.connect(transport);
