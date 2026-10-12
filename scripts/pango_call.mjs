import fs from 'node:fs/promises';
import path from 'node:path';
import readline from 'node:readline';
import { fileURLToPath } from 'node:url';
import { spawn } from 'node:child_process';

// JSON-RPC stdio client. Every invocation initializes the real local pango-mcp
// server and retains the request/response pair for repeatable verification.
const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const toolName = process.argv[2];
const argFile = process.argv[3];
if (!toolName || (argFile && !path.isAbsolute(argFile))) {
  throw new Error('Usage: node pango_call.mjs <tool-name|tools/list> [absolute-arguments.json]');
}
const serverFile = process.env.PANGO_MCP_SERVER;
const envFile = process.env.PANGO_MCP_ENV_FILE;
if (!serverFile || !envFile) {
  throw new Error('Set PANGO_MCP_SERVER and PANGO_MCP_ENV_FILE to local installation paths before using the MCP client.');
}
const child = spawn(process.execPath, [serverFile], {
  cwd: path.dirname(serverFile), shell: false, windowsHide: true,
  env: { ...process.env, PANGO_MCP_ENV_FILE: envFile }, stdio: ['pipe', 'pipe', 'pipe'],
});
let nextId = 0;
const pending = new Map();
let stderr = '';
child.stderr.setEncoding('utf8');
child.stderr.on('data', (chunk) => { stderr += chunk; });
const lines = readline.createInterface({ input: child.stdout, crlfDelay: Infinity });
lines.on('line', (line) => {
  if (!line.trim()) return;
  try {
    const response = JSON.parse(line);
    const waiter = pending.get(response.id);
    if (waiter) {
      pending.delete(response.id);
      clearTimeout(waiter.timer);
      if (response.error) waiter.reject(new Error(JSON.stringify(response.error)));
      else waiter.resolve(response.result);
    }
  } catch (error) {
    for (const waiter of pending.values()) waiter.reject(error);
    pending.clear();
  }
});
const failPending = (error) => {
  for (const waiter of pending.values()) {
    clearTimeout(waiter.timer);
    waiter.reject(error);
  }
  pending.clear();
};
child.on('error', failPending);
child.on('close', (code) => {
  if (pending.size) failPending(new Error(`pango-mcp exited ${code}: ${stderr}`));
});
function rpc(method, params, timeoutMs = 120000) {
  const id = ++nextId;
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      pending.delete(id);
      reject(new Error(`Timed out waiting for ${method}`));
    }, timeoutMs);
    pending.set(id, { resolve, reject, timer });
    child.stdin.write(JSON.stringify({ jsonrpc: '2.0', id, method, params }) + '\n');
  });
}
const startedAt = new Date().toISOString();
let record;
let outputPath;
try {
  const initialized = await rpc('initialize', {
    protocolVersion: '2025-11-25', capabilities: {},
    clientInfo: { name: 'pangu50k-j8-diag-client', version: '1.0.0' },
  });
  child.stdin.write(JSON.stringify({ jsonrpc: '2.0', method: 'notifications/initialized' }) + '\n');
  const args = argFile ? JSON.parse(await fs.readFile(argFile, 'utf8')) : {};
  const environment = toolName === 'fpga_env' || toolName === 'tools/list'
    ? null : await rpc('tools/call', { name: 'fpga_env', arguments: {} });
  const method = toolName === 'tools/list' ? 'tools/list' : 'tools/call';
  const params = method === 'tools/list' ? {} : { name: toolName, arguments: args };
  const result = await rpc(method, params, (Number(args.timeoutSec ?? 900) + 60) * 1000);
  record = { startedAt, completedAt: new Date().toISOString(), serverFile, initialized,
    environment, request: { method, params }, response: result, stderr };
  const logs = path.join(projectRoot, 'reports', 'mcp');
  await fs.mkdir(logs, { recursive: true });
  outputPath = path.join(logs, `${startedAt.replace(/[:.]/g, '-')}-${toolName.replaceAll('/', '_')}-${process.pid}.json`);
  await fs.writeFile(outputPath, JSON.stringify(record, null, 2) + '\n');
  const value = result.structuredContent ?? result;
  const { full: _full, transcript: _transcript, ...brief } = value;
  console.log(JSON.stringify({ ...(process.env.PANGO_MCP_FULL_OUTPUT === '1' ? value : brief), mcpLog: outputPath }, null, 2));
  if (result.isError || value.ok === false) process.exitCode = 1;
} finally {
  child.stdin.end();
  lines.close();
  child.kill();
}
