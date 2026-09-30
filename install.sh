#!/usr/bin/env bash
# install.sh: Automated installer for agy-account-switcher
set -euo pipefail

# ANSI color codes
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  BOLD=$'\033[1m'
  RESET=$'\033[0m'
  GREEN=$'\033[0;32m'
  CYAN=$'\033[0;36m'
  YELLOW=$'\033[0;33m'
  RED=$'\033[0;31m'
else
  BOLD=""
  RESET=""
  GREEN=""
  CYAN=""
  YELLOW=""
  RED=""
fi

echo "${CYAN}${BOLD}╔════════════════════════════════════════════════════════════╗${RESET}"
echo "${CYAN}${BOLD}║           AGY ACCOUNT SWITCHER - INSTALLATION              ║${RESET}"
echo "${CYAN}${BOLD}╚════════════════════════════════════════════════════════════╝${RESET}"
echo ""

# 1. Dependency checks
echo "Checking prerequisites..."
for req in bash curl perl; do
  if ! command -v "$req" >/dev/null 2>&1; then
    echo "${RED}Error:${RESET} Required dependency '$req' is missing." >&2
    exit 1
  fi
done
echo "${GREEN}✔${RESET} All prerequisites (bash, curl, perl) are available."

# 2. Determine source directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || echo "")"
TEMP_DIR=""

if [[ -n "$SCRIPT_DIR" && -f "$SCRIPT_DIR/bin/agy-accounts" ]]; then
  SRC_DIR="$SCRIPT_DIR"
else
  # Running via curl pipe; clone or download repository
  echo "Downloading latest release..."
  TEMP_DIR=$(mktemp -d)
  trap 'rm -rf "$TEMP_DIR"' EXIT
  local downloaded=false
  if command -v git >/dev/null 2>&1; then
    if git clone --depth 1 https://github.com/abidhasansojib/agy-account-switcher.git "$TEMP_DIR" 2>/dev/null; then
      downloaded=true
    fi
  fi

  if [[ "$downloaded" != true ]]; then
    curl -fsSL https://github.com/abidhasansojib/agy-account-switcher/archive/refs/heads/main.tar.gz | tar -xz -C "$TEMP_DIR" --strip-components=1 2>/dev/null || {
      if [[ -d "/root/agy-account-switcher" ]]; then
        cp -r /root/agy-account-switcher/* "$TEMP_DIR/"
      fi
    }
  fi
  SRC_DIR="$TEMP_DIR"
fi

# 3. Determine target install directories
if [[ $EUID -eq 0 ]]; then
  INSTALL_BIN="/usr/local/bin"
  INSTALL_SHARE="/usr/local/share/agy-accounts"
else
  INSTALL_BIN="$HOME/.local/bin"
  INSTALL_SHARE="$HOME/.local/share/agy-accounts"
fi

mkdir -p "$INSTALL_BIN"
mkdir -p "$INSTALL_SHARE/lib"

echo "Installing to $INSTALL_BIN..."

# 4. Copy libraries
cp "$SRC_DIR/lib/storage.sh" "$INSTALL_SHARE/lib/"
cp "$SRC_DIR/lib/auth.pl" "$INSTALL_SHARE/lib/"
cp "$SRC_DIR/lib/tui.sh" "$INSTALL_SHARE/lib/"
chmod +x "$INSTALL_SHARE/lib/auth.pl"

# 5. Copy uninstaller
cp "$SRC_DIR/uninstall.sh" "$INSTALL_SHARE/uninstall.sh"
chmod +x "$INSTALL_SHARE/uninstall.sh"

# 6. Copy binary
cp "$SRC_DIR/bin/agy-accounts" "$INSTALL_BIN/agy-accounts"
chmod +x "$INSTALL_BIN/agy-accounts"

# Create symlink for agy-switcher
ln -sf "$INSTALL_BIN/agy-accounts" "$INSTALL_BIN/agy-switcher"

# 7. Install Antigravity Skill
SKILL_TARGET="$HOME/.gemini/config/skills/accounts"
mkdir -p "$SKILL_TARGET"
cp "$SRC_DIR/skill/accounts/SKILL.md" "$SKILL_TARGET/SKILL.md"
echo "${GREEN}✔${RESET} Installed Antigravity skill to ${SKILL_TARGET}/SKILL.md"

# 8. Ensure INSTALL_BIN is in PATH
if [[ ":$PATH:" != *":$INSTALL_BIN:"* ]]; then
  echo "${YELLOW}▲${RESET} Notice: $INSTALL_BIN is not currently in your PATH."
  PROFILE_RC=""
  if [[ -f "$HOME/.bashrc" ]]; then
    PROFILE_RC="$HOME/.bashrc"
  elif [[ -f "$HOME/.zshrc" ]]; then
    PROFILE_RC="$HOME/.zshrc"
  fi

  if [[ -n "$PROFILE_RC" ]]; then
    if ! grep -q "export PATH=.*$INSTALL_BIN" "$PROFILE_RC" 2>/dev/null; then
      echo "export PATH=\"\$PATH:$INSTALL_BIN\"" >> "$PROFILE_RC"
      echo "${GREEN}✔${RESET} Added $INSTALL_BIN to $PROFILE_RC"
    fi
  fi
fi

# 9. Auto-import existing Antigravity session if present
DEFAULT_TOKEN="$HOME/.gemini/antigravity-cli/antigravity-oauth-token"
if [[ -f "$DEFAULT_TOKEN" ]]; then
  echo ""
  echo "Existing Antigravity login detected."
  # Run import
  AGY_LIB_DIR="$INSTALL_SHARE/lib" "$INSTALL_BIN/agy-accounts" add default --import >/dev/null 2>&1 || true
  echo "${GREEN}✔${RESET} Current session automatically saved as profile '${BOLD}default${RESET}'."
fi

echo ""
echo "${GREEN}${BOLD}Installation Complete!${RESET}"
echo "--------------------------------------------------------"
echo "  Run '${CYAN}${BOLD}agy-accounts${RESET}' to open the interactive menu."
echo "  Or use CLI shortcuts:"
echo "    ${CYAN}agy-accounts list${RESET}            # List accounts and status"
echo "    ${CYAN}agy-accounts switch <name>${RESET}   # Switch active account"
echo "    ${CYAN}agy-accounts limits${RESET}          # View quota & health status"
echo "    ${CYAN}agy-accounts add <name>${RESET}      # Add a new account"
echo ""
echo "  Inside Antigravity, type '${CYAN}${BOLD}/accounts${RESET}' to view & switch accounts!"
echo "--------------------------------------------------------"
