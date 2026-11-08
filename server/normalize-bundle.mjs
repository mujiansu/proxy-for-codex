import { readFile, writeFile } from 'node:fs/promises';

const bundleUrl = new URL('./server.bundle.mjs', import.meta.url);
const text = await readFile(bundleUrl, 'utf8');
const normalized = text
  .split(/\r?\n/)
  .map((line) => line.replace(/[ \t]+$/u, ''))
  .join('\n');
await writeFile(bundleUrl, normalized, 'utf8');
