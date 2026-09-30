#!/usr/bin/env bash
# lib/tui.sh: Terminal UI, ANSI styling, tables, badges, and interactive menus
set -euo pipefail

# ANSI color definitions (disabled if NO_COLOR is set or stdout is not a tty)
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  BOLD=$'\033[1m'
  DIM=$'\033[2m'
  RESET=$'\033[0m'
  RED=$'\033[0;31m'
  GREEN=$'\033[0;32m'
  YELLOW=$'\033[0;33m'
  BLUE=$'\033[0;34m'
  MAGENTA=$'\033[0;35m'
  CYAN=$'\033[0;36m'
  GRAY=$'\033[0;90m'
  BG_CYAN=$'\033[46;30m'
  BG_GREEN=$'\033[42;30m'
else
  BOLD=""
  DIM=""
  RESET=""
  RED=""
  GREEN=""
  YELLOW=""
  BLUE=""
  MAGENTA=""
  CYAN=""
  GRAY=""
  BG_CYAN=""
  BG_GREEN=""
fi

tui_banner() {
  local active="${1:-none}"
  echo "${CYAN}${BOLD}╔════════════════════════════════════════════════════════════╗${RESET}"
  echo "${CYAN}${BOLD}║              AGY ACCOUNT SWITCHER & LIMITS                 ║${RESET}"
  echo "${CYAN}${BOLD}╚════════════════════════════════════════════════════════════╝${RESET}"
  if [[ -n "$active" && "$active" != "none" ]]; then
    echo "  ${DIM}Active Profile:${RESET} ${GREEN}${BOLD}$active${RESET}"
  else
    echo "  ${DIM}Active Profile:${RESET} ${YELLOW}None selected${RESET}"
  fi
  echo ""
}

tui_success() {
  echo "${GREEN}✔${RESET} $*"
}

tui_error() {
  echo "${RED}✖${RESET} $*" >&2
}

tui_warn() {
  echo "${YELLOW}▲${RESET} $*"
}

tui_info() {
  echo "${CYAN}ℹ${RESET} $*"
}

tui_status_badge() {
  local status="$1"
  case "$status" in
    ACTIVE_CURRENT)
      echo "${BG_CYAN}${BOLD} ACTIVE * ${RESET}"
      ;;
    ACTIVE)
      echo "${GREEN}${BOLD}✔ ACTIVE ${RESET}"
      ;;
    RATE_LIMITED)
      echo "${YELLOW}${BOLD}⚠ RATE LIMITED${RESET}"
      ;;
    EXPIRED)
      echo "${RED}${BOLD}✖ EXPIRED${RESET}"
      ;;
    AUTH_REVOKED)
      echo "${RED}${BOLD}✖ REVOKED${RESET}"
      ;;
    *)
      echo "${GRAY}$status${RESET}"
      ;;
  esac
}

tui_table_header() {
  printf "  ${BOLD}%-15s %-30s %-20s %-16s${RESET}\n" "PROFILE" "EMAIL" "TOKEN EXPIRY" "STATUS"
  printf "  ${GRAY}%-15s %-30s %-20s %-16s${RESET}\n" "---------------" "------------------------------" "--------------------" "----------------"
}

tui_table_row() {
  local name="$1"
  local email="$2"
  local expiry="$3"
  local badge="$4"

  # Truncate fields if necessary
  if [[ ${#name} -gt 15 ]]; then name="${name:0:12}..."; fi
  if [[ ${#email} -gt 30 ]]; then email="${email:0:27}..."; fi
  if [[ ${#expiry} -gt 20 ]]; then expiry="${expiry:0:17}..."; fi

  printf "  %-15s %-30s %-20s %s\n" "$name" "$email" "$expiry" "$badge"
}

tui_prompt() {
  local prompt_text="$1"
  local default_val="${2:-}"
  local val=""

  if [[ -n "$default_val" ]]; then
    read -r -p "  ${BOLD}$prompt_text${RESET} [${CYAN}$default_val${RESET}]: " val
    val="${val:-$default_val}"
  else
    read -r -p "  ${BOLD}$prompt_text${RESET}: " val
  fi
  echo "$val"
}

tui_confirm() {
  local question="$1"
  local default_yes="${2:-Y}"
  local prompt="[y/N]"
  if [[ "$default_yes" =~ ^[Yy]$ ]]; then
    prompt="[Y/n]"
  fi

  read -r -p "  ${YELLOW}?${RESET} $question $prompt " choice
  choice="${choice:-$default_yes}"
  if [[ "$choice" =~ ^[Yy]$ ]]; then
    return 0
  else
    return 1
  fi
}
