import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { getAgentDir } from "@mariozechner/pi-coding-agent";
import { spawn } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const baseDir = dirname(fileURLToPath(import.meta.url));
const runnerScript = join(baseDir, "scripts", "run_campaign_report.mjs");
const uuidPattern =
	/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

interface CommandResult {
	tempDir: string;
	snapshotPath: string;
	markdownPath: string;
	htmlPath: string;
	surfaceId: string | null;
	headlineSummary: string;
	topAnomalies: string[];
}

function runNodeCommand(args: string[], cwd: string): Promise<{ stdout: string; stderr: string }> {
	return new Promise((resolve, reject) => {
		const child = spawn("node", args, {
			cwd,
			env: process.env,
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
			if (code === 0) {
				resolve({ stdout, stderr });
				return;
			}

			reject(
				new Error(
					stderr.trim() || stdout.trim() || `campaign-report runner exited with code ${code}`,
				),
			);
		});
	});
}

export default function (pi: ExtensionAPI) {
	pi.registerCommand("campaign-report", {
		description:
			"Generate a campaign report via postgres_prod without an LLM roundtrip. Usage: /campaign-report <campaign-id>",
		handler: async (args, ctx) => {
			const campaignId = args.trim();
			if (!campaignId) {
				ctx.ui.notify("Usage: /campaign-report <campaign-id>", "error");
				return;
			}

			if (!uuidPattern.test(campaignId)) {
				ctx.ui.notify(`Invalid campaign UUID: ${campaignId}`, "error");
				return;
			}

			ctx.ui.notify(`Generating campaign report for ${campaignId}...`, "info");

			try {
				const { stdout } = await runNodeCommand(
					[runnerScript, campaignId, "--mcp-config", join(getAgentDir(), "mcp.json")],
					ctx.cwd,
				);
				const result = JSON.parse(stdout) as CommandResult;
				const lines = [
					result.headlineSummary,
					`Temp dir: ${result.tempDir}`,
					`Snapshot: ${result.snapshotPath}`,
					`Markdown: ${result.markdownPath}`,
					`HTML: ${result.htmlPath}`,
					result.surfaceId ? `Opened in cmux: ${result.surfaceId}` : "HTML generated; cmux surface not opened.",
				];

				if (result.topAnomalies.length > 0) {
					lines.push("Top anomalies:");
					for (const anomaly of result.topAnomalies) {
						lines.push(`- ${anomaly}`);
					}
				}

				ctx.ui.notify(lines.join("\n"), "info");
			} catch (error) {
				ctx.ui.notify(
					error instanceof Error ? error.message : String(error),
					"error",
				);
			}
		},
	});
}
