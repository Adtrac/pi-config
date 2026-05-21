#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EXPECTED_DIR="$HOME/.pi/agent"

# Verify we're in the right place
if [ "$SCRIPT_DIR" != "$EXPECTED_DIR" ]; then
  echo "⚠️  This repo should be cloned to ~/.pi/agent/"
  echo "   Current location: $SCRIPT_DIR"
  echo "   Expected: $EXPECTED_DIR"
  echo ""
  echo "   Run: git clone git@github.com:Mathuv/pi-config $EXPECTED_DIR"
  exit 1
fi

echo "Setting up pi-config at $EXPECTED_DIR"
echo ""

# Create settings.json if it doesn't exist
if [ ! -f "$EXPECTED_DIR/settings.json" ]; then
  echo "Creating settings.json..."
  cat > "$EXPECTED_DIR/settings.json" << 'EOF'
{
  "lastChangelogVersion": "0.75.4",
  "defaultProvider": "github-copilot",
  "defaultModel": "gpt-5.4",
  "defaultThinkingLevel": "xhigh",
  "packages": [
    "git:github.com/pasky/chrome-cdp-skill",
    "-git:github.com/HazAT/glimpse",
    "-git:github.com/HazAT/pi-autoresearch",
    "git:github.com/badlogic/pi-diff-review",
    "npm:@tmustier/pi-files-widget",
    "npm:pi-markdown-preview",
    "git:github.com/Mathuv/pi-smart-sessions",
    "npm:pi-interview",
    "git:github.com/earendil-works/pi-review",
    "npm:@ff-labs/pi-fff",
    "git:github.com/hiasinho/pi-dumb",
    "git:github.com/nicobailon/pi-powerline-footer",
    "git:github.com/nicobailon/pi-boomerang",
    "git:github.com/mattleong/pi-code-previews",
    "git:github.com/fu5ha/pi-treebase",
    "git:github.com/nicobailon/pi-mcp-adapter",
    "git:github.com/Mathuv/pi-symbol-autocomplete",
    "git:github.com/Mathuv/pi-interactive-subagents",
    "npm:pi-subagents",
    "npm:pi-intercom",
    "git:github.com/HazAT/pi-parallel"
  ],
  "hideThinkingBlock": false,
  "extensions": [
    "+extensions/cmux/index.ts"
  ],
  "compaction": {
    "enabled": false
  },
  "terminal": {
    "clearOnShrink": false,
    "showTerminalProgress": true
  },
  "powerline": {
    "preset": "default",
    "fixedEditor": false
  },
  "subagents": {
    "agentOverrides": {
      "reviewer": {
        "model": "openai-codex/gpt-5.3-codex",
        "thinking": "high",
        "fallbackModels": [
          "opencode-go/deepseek-v4-pro"
        ]
      },
      "worker": {
        "model": "opencode-go/deepseek-v4-flash",
        "thinking": "xhigh"
      },
      "scout": {
        "model": "opencode-go/deepseek-v4-flash",
        "thinking": "high"
      },
      "planner": {
        "model": "openai-codex/gpt-5.3-codex",
        "thinking": "xhigh"
      }
    }
  },
  "transport": "websocket-cached"
}
EOF
else
  echo "settings.json already exists — skipping creation"
  echo ""
fi

# Install packages — install only active (non-excluded) packages from settings.json
echo "Installing packages..."
pi install git:github.com/pasky/chrome-cdp-skill 2>/dev/null || echo "  chrome-cdp-skill already installed"
pi install git:github.com/badlogic/pi-diff-review 2>/dev/null || echo "  pi-diff-review already installed"
pi install npm:@tmustier/pi-files-widget 2>/dev/null || echo "  @tmustier/pi-files-widget already installed"
pi install npm:pi-markdown-preview 2>/dev/null || echo "  pi-markdown-preview already installed"
pi install git:github.com/Mathuv/pi-smart-sessions 2>/dev/null || echo "  pi-smart-sessions already installed"
pi install npm:pi-interview 2>/dev/null || echo "  pi-interview already installed"
pi install git:github.com/earendil-works/pi-review 2>/dev/null || echo "  pi-review already installed"
pi install npm:@ff-labs/pi-fff 2>/dev/null || echo "  @ff-labs/pi-fff already installed"
pi install git:github.com/hiasinho/pi-dumb 2>/dev/null || echo "  pi-dumb already installed"
pi install git:github.com/nicobailon/pi-powerline-footer 2>/dev/null || echo "  pi-powerline-footer already installed"
pi install git:github.com/nicobailon/pi-boomerang 2>/dev/null || echo "  pi-boomerang already installed"
pi install git:github.com/mattleong/pi-code-previews 2>/dev/null || echo "  pi-code-previews already installed"
pi install git:github.com/fu5ha/pi-treebase 2>/dev/null || echo "  pi-treebase already installed"
pi install git:github.com/nicobailon/pi-mcp-adapter 2>/dev/null || echo "  pi-mcp-adapter already installed"
pi install git:github.com/Mathuv/pi-symbol-autocomplete 2>/dev/null || echo "  pi-symbol-autocomplete already installed"
pi install git:github.com/Mathuv/pi-interactive-subagents 2>/dev/null || echo "  pi-interactive-subagents already installed"
pi install npm:pi-subagents 2>/dev/null || echo "  pi-subagents already installed"
pi install npm:pi-intercom 2>/dev/null || echo "  pi-intercom already installed"
pi install git:github.com/HazAT/pi-parallel 2>/dev/null || echo "  pi-parallel already installed"
echo ""

echo "✅ Setup complete!"
echo ""
echo "Restart pi to pick up all changes."
