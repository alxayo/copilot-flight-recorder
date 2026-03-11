#!/usr/bin/env bash
# install-plugin.sh — Install copilot-flight-recorder plugin locally for VS Code
#
# Usage:
#   ./scripts/install-plugin.sh [--target DIR]
#
# If --target is omitted the plugin is installed to ~/.copilot-plugins/copilot-flight-recorder
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PLUGIN_NAME="copilot-flight-recorder"
DEFAULT_TARGET="$HOME/.copilot-plugins/$PLUGIN_NAME"
TARGET_DIR="$DEFAULT_TARGET"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --target) TARGET_DIR="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

echo "==> Installing $PLUGIN_NAME to $TARGET_DIR"

# Create target directory
mkdir -p "$TARGET_DIR/.github/plugin"
mkdir -p "$TARGET_DIR/.github/hooks/scripts"

# Copy plugin manifest
cp "$REPO_ROOT/.github/plugin/plugin.json" "$TARGET_DIR/.github/plugin/plugin.json"
cp "$REPO_ROOT/.github/plugin/README.md"   "$TARGET_DIR/.github/plugin/README.md"

# Copy hooks config and scripts
cp "$REPO_ROOT/.github/hooks/copilot-audit.json"  "$TARGET_DIR/.github/hooks/copilot-audit.json"
cp "$REPO_ROOT/.github/hooks/scripts/"*.sh         "$TARGET_DIR/.github/hooks/scripts/"
cp "$REPO_ROOT/.github/hooks/scripts/"*.ps1        "$TARGET_DIR/.github/hooks/scripts/"

# Copy supporting files
cp "$REPO_ROOT/.env.example" "$TARGET_DIR/.env.example"
cp "$REPO_ROOT/README.md"    "$TARGET_DIR/README.md"

# Ensure bash scripts are executable
chmod +x "$TARGET_DIR/.github/hooks/scripts/"*.sh

echo ""
echo "Plugin installed to: $TARGET_DIR"
echo ""
echo "To activate it, add the following to your VS Code settings.json:"
echo ""
echo '  "chat.plugins.paths": {'
echo "    \"$TARGET_DIR\": true"
echo '  }'
echo ""
echo "Or open VS Code and run the command:"
echo "  Preferences: Open User Settings (JSON)"
echo "then add the chat.plugins.paths entry above."
echo ""
echo "Don't forget to configure your audit repo:"
echo "  export COPILOT_AUDIT_REPO=/path/to/your/audit-repo"
echo "  (or create a .env file in your workspace root)"
