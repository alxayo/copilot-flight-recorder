#!/usr/bin/env bash
# build-plugin.sh — Package copilot-flight-recorder as a distributable Copilot CLI agent plugin
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Read version from plugin.json
PLUGIN_JSON="$REPO_ROOT/.github/plugin/plugin.json"
if ! command -v jq &>/dev/null; then
  echo "ERROR: jq is required to build the plugin package." >&2
  exit 1
fi

PLUGIN_NAME=$(jq -r '.name' "$PLUGIN_JSON")
PLUGIN_VERSION=$(jq -r '.version' "$PLUGIN_JSON")
PACKAGE_NAME="${PLUGIN_PACKAGE_NAME_OVERRIDE:-$PLUGIN_NAME}"
PACKAGE_VERSION="${PLUGIN_VERSION_OVERRIDE:-$PLUGIN_VERSION}"
BUILD_DIR="$REPO_ROOT/dist"
STAGE_DIR="$BUILD_DIR/$PACKAGE_NAME"

echo "==> Building $PACKAGE_NAME v$PACKAGE_VERSION"

# Clean previous build
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR/.github/plugin"
mkdir -p "$STAGE_DIR/.github/hooks/scripts"

# ---- Copy plugin manifest and README ----
cp "$REPO_ROOT/.github/plugin/plugin.json" "$STAGE_DIR/.github/plugin/plugin.json"
cp "$REPO_ROOT/.github/plugin/README.md"   "$STAGE_DIR/.github/plugin/README.md"

# ---- Copy hook configuration ----
cp "$REPO_ROOT/.github/hooks/copilot-cli-audit.json" "$STAGE_DIR/.github/hooks/copilot-cli-audit.json"

# ---- Copy all hook scripts ----
cp "$REPO_ROOT/.github/hooks/scripts/"*.sh  "$STAGE_DIR/.github/hooks/scripts/"
cp "$REPO_ROOT/.github/hooks/scripts/"*.ps1 "$STAGE_DIR/.github/hooks/scripts/"

# ---- Copy config example and docs ----
cp "$REPO_ROOT/.env.example"  "$STAGE_DIR/.env.example"
cp "$REPO_ROOT/README.md"     "$STAGE_DIR/README.md"

# ---- Ensure bash scripts are executable ----
chmod +x "$STAGE_DIR/.github/hooks/scripts/"*.sh

# ---- Create the archives ----
echo "==> Creating archives in $BUILD_DIR/"

# Tar.gz (Linux/macOS)
tar -czf "$BUILD_DIR/${PACKAGE_NAME}-${PACKAGE_VERSION}.tar.gz" \
  -C "$BUILD_DIR" "$PACKAGE_NAME"

# Zip (Windows / universal)
(cd "$BUILD_DIR" && zip -rq "${PACKAGE_NAME}-${PACKAGE_VERSION}.zip" "$PACKAGE_NAME")

# ---- Summary ----
echo ""
echo "Plugin package built successfully:"
echo "  $BUILD_DIR/${PACKAGE_NAME}-${PACKAGE_VERSION}.tar.gz"
echo "  $BUILD_DIR/${PACKAGE_NAME}-${PACKAGE_VERSION}.zip"
echo ""
echo "Install locally by extracting to your workspace .github directory."
