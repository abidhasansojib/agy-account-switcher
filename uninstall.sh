#!/usr/bin/env bash
# uninstall.sh: Clean uninstaller for agy-account-switcher
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

echo "${YELLOW}${BOLD}╔════════════════════════════════════════════════════════════╗${RESET}"
echo "${YELLOW}${BOLD}║          AGY ACCOUNT SWITCHER - UNINSTALLATION             ║${RESET}"
echo "${YELLOW}${BOLD}╚════════════════════════════════════════════════════════════╝${RESET}"
echo ""

PURGE_DATA=false
if [[ "${1:-}" == "--purge" ]]; then
  PURGE_DATA=true
fi

# Detect install locations
if [[ -f "/usr/local/bin/agy-accounts" ]]; then
  INSTALL_BIN="/usr/local/bin"
  INSTALL_SHARE="/usr/local/share/agy-accounts"
elif [[ -f "$HOME/.local/bin/agy-accounts" ]]; then
  INSTALL_BIN="$HOME/.local/bin"
  INSTALL_SHARE="$HOME/.local/share/agy-accounts"
else
  INSTALL_BIN=""
  INSTALL_SHARE=""
fi

# 1. Remove binaries
if [[ -n "$INSTALL_BIN" ]]; then
  echo "Removing executable binaries..."
  rm -f "$INSTALL_BIN/agy-accounts"
  rm -f "$INSTALL_BIN/agy-switcher"
  echo "${GREEN}✔${RESET} Removed binaries from $INSTALL_BIN"
fi

# 2. Remove shared libraries
if [[ -n "$INSTALL_SHARE" && -d "$INSTALL_SHARE" ]]; then
  echo "Removing library files..."
  rm -rf "$INSTALL_SHARE"
  echo "${GREEN}✔${RESET} Removed $INSTALL_SHARE"
fi

# 3. Remove Antigravity Skill
SKILL_TARGET="$HOME/.gemini/config/skills/accounts"
if [[ -d "$SKILL_TARGET" ]]; then
  echo "Removing Antigravity skill..."
  rm -rf "$SKILL_TARGET"
  echo "${GREEN}✔${RESET} Removed $SKILL_TARGET"
fi

# 4. Handle saved profiles
DATA_DIR="$HOME/.gemini/agy-accounts"
if [[ -d "$DATA_DIR" ]]; then
  if [[ "$PURGE_DATA" == true ]]; then
    rm -rf "$DATA_DIR"
    echo "${GREEN}✔${RESET} Purged saved profiles in $DATA_DIR"
  elif [[ -t 0 || -e /dev/tty ]]; then
    echo ""
    del_choice=""
    if [[ -t 0 ]]; then
      read -r -p "Do you want to delete all saved account profiles in $DATA_DIR? [y/N] " del_choice || true
    else
      read -r -p "Do you want to delete all saved account profiles in $DATA_DIR? [y/N] " del_choice </dev/tty || true
    fi
    if [[ "$del_choice" =~ ^[Yy]$ ]]; then
      rm -rf "$DATA_DIR"
      echo "${GREEN}✔${RESET} Removed $DATA_DIR"
    else
      echo "  Retained saved account data in $DATA_DIR"
    fi
  else
    echo "  Retained saved account data in $DATA_DIR (use --purge to delete)"
  fi
fi

echo ""
echo "${GREEN}${BOLD}agy-account-switcher has been successfully uninstalled.${RESET}"
