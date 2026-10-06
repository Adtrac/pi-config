/**
 * Stop the agent when gcloud needs re-authentication.
 *
 * The Google Cloud session of a user ends after 16 hours. After that, gcloud,
 * kubectl (through gke-gcloud-auth-plugin), and Application Default Credentials
 * clients fail in a non-interactive shell. Only the user can log in again.
 *
 * When a bash result shows one of these errors, this extension:
 * - puts a STOP notice at the top of that result,
 * - blocks every later tool call until the user sends the next message.
 *
 * The agent can still write text, so it can tell the user (or its parent
 * session) which command failed. Subagents can still use intercom and
 * subagent_done to report the error.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const AUTH_ERRORS = [
	// gcloud, and kubectl through gke-gcloud-auth-plugin
	"Reauthentication failed. cannot prompt during non-interactive execution",
	// Application Default Credentials (google-auth)
	"Reauthentication is needed. Please run `gcloud auth application-default login`",
	// gcloud without a logged-in account
	"You do not currently have an active account selected.",
];

const ALLOWED_TOOLS = ["intercom", "subagent_done"];

const STOP_NOTICE = [
	"STOP: gcloud needs re-authentication. Only the user can log in.",
	"Do not continue the task. Do not use other sources instead of gcloud.",
	"Tell the user which command failed and show the error lines.",
	"Ask the user to run the login command that the error shows, for example `gcloud auth login`.",
	"Then end your turn. A subagent sends this report to its parent session.",
	"All tool calls stay blocked until the user sends the next message.",
	"After the user confirms the login, run the failed command again. Then continue the task.",
].join("\n");

export default function gcloudReauthGuard(pi: ExtensionAPI) {
	let blocked = false;

	pi.on("session_start", () => {
		blocked = false;
	});

	pi.on("input", (event) => {
		if (event.source === "interactive" || event.source === "rpc") {
			blocked = false;
		}
		return { action: "continue" };
	});

	pi.on("tool_result", (event, ctx) => {
		if (event.toolName !== "bash") {
			return;
		}
		const output = event.content.map((part) => (part.type === "text" ? part.text : "")).join("\n");
		if (!AUTH_ERRORS.some((error) => output.includes(error))) {
			return;
		}

		blocked = true;
		if (ctx.hasUI) {
			ctx.ui.notify("gcloud needs re-authentication. Run the login command from the error, then reply.", "warning");
		}
		return {
			content: [{ type: "text", text: STOP_NOTICE }, ...event.content],
			isError: true,
		};
	});

	pi.on("tool_call", (event) => {
		if (!blocked || ALLOWED_TOOLS.includes(event.toolName)) {
			return;
		}
		return { block: true, reason: STOP_NOTICE };
	});
}
