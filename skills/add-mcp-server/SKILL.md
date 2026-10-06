---
name: add-mcp-server
description: Add or change an MCP server in pi's built-in MCP support (pi 0.99.0 and later). Use when asked to "add mcp server", "configure mcp", "add mcp", "new mcp server", "setup mcp", "connect mcp server", or "register mcp server". Handles global and project-local configurations.
---

# Add an MCP Server

Pi 0.99.0 and later has built-in MCP support. Use the `pi mcp` commands to add, list, and remove servers. Edit `mcp.json` by hand only for settings that the commands cannot set.

The full reference is `docs/mcp.md` in the installed pi package. To find it:

```bash
P=$(dirname "$(readlink -f "$(command -v pi)")")/../..
less "$P/docs/mcp.md"
```

Do not install `pi-mcp-adapter` or another extension that registers `/mcp`. Such an extension replaces the built-in MCP support, and pi then does not read `mcp.json`.

## Step 1: Choose the scope

| Scope | File | Option |
|---|---|---|
| Global (default) | `~/.pi/agent/mcp.json` | none |
| Project | `.pi/mcp.json` | `-l` or `--local` |

- A project entry replaces a global entry with the same name.
- Pi reads the project file only in a trusted project.
- Put servers with credentials in the global file.

Ask the user when the scope is not clear.

## Step 2: Check the name

Run `pi mcp list` and look for a server with the same name. `pi mcp add` replaces an existing server, so ask the user before you replace one.

A server name can contain only letters, digits, `_`, and `-`. Pi treats two names that differ only in `-` and `_` as the same server.

## Step 3: Add the server

Stdio server (a local process):

```bash
pi mcp add <name> -- <command> [args...]
pi mcp add <name> --env API_KEY='${MY_API_KEY}' -- npx -y <package>
```

HTTP server (streamable HTTP):

```bash
pi mcp add <name> --url https://example.com/mcp --bearer-token-env-var MY_TOKEN
pi mcp add <name> --url https://example.com/mcp --header 'X-Api-Key=${MY_KEY}'
```

Other options: `--cwd <dir>`, `--exposure <mode>`, `--description <text>`, and `-l`. Run `pi mcp --help` for the OAuth options.

Rules:

- `command` is one executable, and `args` holds its arguments. It is not a shell command string.
- Do not write a secret into `mcp.json`. Use `${NAME}` for an environment variable, or `!command` for a command that prints the value. The command must be the complete value.
- Pi does not support SSE. Many servers also offer streamable HTTP, often at `/mcp`.
- Give each server a `--description`. Pi shows it in the system prompt, and tool search uses it to rank the tools.

## Step 4: Choose the exposure

Pi names each tool `mcp__<server>__<tool>`. It replaces each character that is not a letter, a digit, or `_` with `_`. For example, the server `parallel-search` gives `mcp__parallel_search__web_search`.

| Exposure | Effect | Use for |
|---|---|---|
| `codemode` (default) | Only `codemode` scripts can call the tools. | Most servers |
| `deferred` | `tool_search` declares a tool before the model calls it. | Large servers |
| `direct` | Pi declares the tools to the model like built-in tools. | Small tool sets that agents use often |
| `hidden` | Pi registers the tools, but no call can reach them. | Tools to block |

- A `codemode` script calls a tool as `await tools.mcp__<server>__<tool>({ ... })`. It finds tools with `searchTools()` or `describeNamespace("<server>")`.
- Pi declares only `direct` tools to the model. An agent that uses a `codemode` server needs `codemode` in its `tools:` list.
- `toolExposure` sets the exposure of single tools. See `docs/mcp.md`.
- To change the exposure of an existing server, open `/mcp`, select the server, and change it. Pi saves the change to the file that defines the server.

## Step 5: Verify

1. Run `pi mcp list`. It connects to every enabled server and prints the state, the tools, and the errors. It exits with status 1 when a server does not connect.
2. In a running session, run `/reload` after a change outside the session.
3. Run `/mcp` to see the state, the tools, the exposure, and the full error of each server. Run `/mcp reconnect <server>` to connect again.
4. Call one read-only tool. For a `codemode` server, use a `codemode` script.

Pi appends the log notifications that a server sends (`notifications/message`) to `~/.pi/agent/mcp.log`. The file exists only after a server sends one. Connection errors are in `/mcp`, which also shows the end of the stderr output of a failed server.

## OAuth servers

A server that uses OAuth needs no credentials in `mcp.json`. Sign in with `pi mcp login <server>` or `/mcp login <server>`. Pi stores the tokens in `~/.pi/agent/mcp-auth.json`. `pi mcp logout <server>` deletes them.

## Other changes

- To remove a server, run `pi mcp remove <name>`. Add `-l` for the project file.
- To keep a server but not connect it, set `"enabled": false`, or disable it in `/mcp`.
- To change the request timeout, set `timeout` in seconds. The default is 60.
- Before you edit `mcp.json` by hand, read it. Change only the entry that you need, and keep the other content.
