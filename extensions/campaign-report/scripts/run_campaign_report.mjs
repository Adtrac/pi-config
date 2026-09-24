#!/usr/bin/env node

import { mkdtemp, readFile, writeFile } from "node:fs/promises";
import { spawn } from "node:child_process";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const baseDir = dirname(dirname(fileURLToPath(import.meta.url)));
const scriptsDir = join(baseDir, "scripts");
const prepareSqlScript = join(scriptsDir, "prepare_campaign_snapshot_sql.py");
const renderScript = join(scriptsDir, "render_campaign_report.py");
const htmlScript = join(scriptsDir, "markdown_to_light_html.py");
const protocolVersion = "2024-11-05";
const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function parseArgs(argv) {
  const args = { campaignId: "", mcpConfig: join(process.env.HOME ?? "", ".pi", "agent", "mcp.json"), open: true };

  for (let i = 0; i < argv.length; i += 1) {
    const value = argv[i];
    if (!args.campaignId && !value.startsWith("--")) {
      args.campaignId = value;
      continue;
    }
    if (value === "--mcp-config") {
      args.mcpConfig = argv[i + 1];
      i += 1;
      continue;
    }
    if (value === "--no-open") {
      args.open = false;
      continue;
    }
    throw new Error(`Unknown argument: ${value}`);
  }

  if (!args.campaignId) {
    throw new Error("Usage: run_campaign_report.mjs <campaign-id> [--mcp-config <path>] [--no-open]");
  }
  if (!uuidPattern.test(args.campaignId)) {
    throw new Error(`Invalid campaign UUID: ${args.campaignId}`);
  }
  if (!args.mcpConfig) {
    throw new Error("MCP config path is required");
  }

  return args;
}

function runCommand(command, args, options = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, {
      cwd: options.cwd,
      env: { ...process.env, ...(options.env ?? {}) },
      stdio: ["ignore", "pipe", "pipe"],
    });

    let stdout = "";
    let stderr = "";

    child.stdout.on("data", (chunk) => {
      stdout += chunk.toString();
    });

    child.stderr.on("data", (chunk) => {
      stderr += chunk.toString();
    });

    child.on("error", (error) => {
      reject(error);
    });

    child.on("close", (code) => {
      if (code === 0 || options.allowFailure) {
        resolve({ stdout, stderr, code: code ?? 0 });
        return;
      }

      reject(new Error(stderr.trim() || stdout.trim() || `${command} exited with code ${code}`));
    });
  });
}

class McpClient {
  constructor(command, args, env) {
    this.nextId = 1;
    this.buffer = "";
    this.pending = new Map();
    this.stderr = "";
    this.child = spawn(command, args, {
      env: { ...process.env, ...env },
      stdio: ["pipe", "pipe", "pipe"],
    });

    this.child.stdout.on("data", (chunk) => {
      this.buffer += chunk.toString();
      this.processBuffer();
    });

    this.child.stderr.on("data", (chunk) => {
      this.stderr += chunk.toString();
    });

    this.child.on("error", (error) => {
      this.rejectPending(error);
    });

    this.child.on("close", (code) => {
      if (code !== 0) {
        this.rejectPending(
          new Error(this.stderr.trim() || `MCP server exited with code ${code}`),
        );
      }
    });
  }

  rejectPending(error) {
    for (const pending of this.pending.values()) {
      pending.reject(error);
    }
    this.pending.clear();
  }

  processBuffer() {
    while (true) {
      const newlineIndex = this.buffer.indexOf("\n");
      if (newlineIndex === -1) {
        return;
      }

      const line = this.buffer.slice(0, newlineIndex).trim();
      this.buffer = this.buffer.slice(newlineIndex + 1);
      if (!line) {
        continue;
      }

      const message = JSON.parse(line);
      this.handleMessage(message);
    }
  }

  handleMessage(message) {
    if (message.id !== undefined) {
      const pending = this.pending.get(message.id);
      if (!pending) {
        return;
      }
      this.pending.delete(message.id);
      if (message.error) {
        pending.reject(new Error(message.error.message || JSON.stringify(message.error)));
        return;
      }
      pending.resolve(message.result);
    }
  }

  send(message) {
    this.child.stdin.write(`${JSON.stringify(message)}\n`);
  }

  request(method, params) {
    const id = this.nextId;
    this.nextId += 1;
    const promise = new Promise((resolve, reject) => {
      this.pending.set(id, { resolve, reject });
    });
    this.send({ jsonrpc: "2.0", id, method, params });
    return promise;
  }

  notify(method, params = undefined) {
    this.send({ jsonrpc: "2.0", method, ...(params === undefined ? {} : { params }) });
  }

  async initialize() {
    await this.request("initialize", {
      protocolVersion,
      capabilities: {},
      clientInfo: {
        name: "campaign-report-command",
        version: "1.0.0",
      },
    });
    this.notify("notifications/initialized");
  }

  async listTools() {
    return this.request("tools/list", {});
  }

  async callTool(name, args) {
    return this.request("tools/call", {
      name,
      arguments: args,
    });
  }

  async close() {
    this.child.stdin.end();
    if (!this.child.killed) {
      this.child.kill();
    }
  }
}

async function loadServerConfig(mcpConfigPath) {
  const parsed = JSON.parse(await readFile(mcpConfigPath, "utf8"));
  const config = parsed?.mcpServers?.postgres_prod;
  if (!config?.command || !Array.isArray(config?.args)) {
    throw new Error(`postgres_prod is not configured in ${mcpConfigPath}`);
  }
  return config;
}

async function prepareSql(campaignId) {
  const { stdout } = await runCommand("uv", ["run", prepareSqlScript, campaignId]);
  return stdout;
}

async function fetchSnapshot(sql, mcpConfigPath) {
  const serverConfig = await loadServerConfig(mcpConfigPath);
  const client = new McpClient(serverConfig.command, serverConfig.args, serverConfig.env ?? {});
  try {
    await client.initialize();
    const tools = await client.listTools();
    const hasQueryTool = Array.isArray(tools?.tools) && tools.tools.some((tool) => tool?.name === "query");
    if (!hasQueryTool) {
      throw new Error("postgres_prod MCP server does not expose the query tool");
    }

    const result = await client.callTool("query", { sql });
    const text = result?.content?.find((item) => item?.type === "text")?.text;
    if (!text) {
      throw new Error("postgres_prod query returned no text content");
    }

    const rows = JSON.parse(text);
    if (!Array.isArray(rows) || rows.length === 0 || typeof rows[0]?.summary !== "object") {
      throw new Error("postgres_prod query did not return a summary object");
    }

    return rows[0].summary;
  } finally {
    await client.close();
  }
}

async function maybeOpenInCmux(htmlPath) {
  const fileUrl = pathToFileURL(htmlPath).href;
  try {
    const { stdout, code } = await runCommand("cmux", ["browser", "open", fileUrl], {
      allowFailure: true,
    });
    if (code !== 0) {
      return null;
    }
    const match = stdout.match(/surface=(surface:\S+)/);
    return match ? match[1] : null;
  } catch {
    return null;
  }
}

function buildHeadlineSummary(snapshot) {
  const campaign = snapshot.campaign ?? {};
  const delivery = snapshot.reporting?.delivery_to_date_pct ?? {};
  return `${campaign.name ?? "Campaign"} is ${campaign.status ?? "unknown"}; delivery to date is ${delivery.playouts ?? "n/a"}% playouts and ${delivery.target_contacts ?? "n/a"}% target contacts.`;
}

function collectTopAnomalies(snapshot) {
  const patterns = Array.isArray(snapshot.noteworthy_patterns) ? snapshot.noteworthy_patterns : [];
  const high = patterns.filter((pattern) => pattern?.severity === "high");
  const source = high.length > 0 ? high : patterns;
  return source.slice(0, 5).map((pattern) => pattern.message).filter(Boolean);
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const tempDir = await mkdtemp(join(tmpdir(), "campaign-report-"));
  const prefix = join(tempDir, `campaign-${args.campaignId}`);
  const snapshotPath = `${prefix}-snapshot.json`;
  const markdownPath = `${prefix}-report.md`;
  const htmlPath = `${prefix}-report.html`;

  const sql = await prepareSql(args.campaignId);
  const snapshot = await fetchSnapshot(sql, args.mcpConfig);
  await writeFile(snapshotPath, `${JSON.stringify(snapshot, null, 2)}\n`);

  await runCommand("uv", ["run", renderScript, snapshotPath, "-o", markdownPath]);
  await runCommand("uv", ["run", htmlScript, markdownPath, "-o", htmlPath]);

  const surfaceId = args.open ? await maybeOpenInCmux(htmlPath) : null;

  const result = {
    tempDir,
    snapshotPath,
    markdownPath,
    htmlPath,
    surfaceId,
    headlineSummary: buildHeadlineSummary(snapshot),
    topAnomalies: collectTopAnomalies(snapshot),
  };

  process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
}

main().catch((error) => {
  process.stderr.write(`${error instanceof Error ? error.stack ?? error.message : String(error)}\n`);
  process.exit(1);
});
