---
name: accounts
description: Manage, list, inspect rate limits, and switch Antigravity Google accounts. Activate when user types /accounts, asks to switch accounts, check account limits, or manage credentials.
---

# Antigravity Account Switcher (`/accounts`)

This skill manages multiple Google Antigravity accounts, displays live Models & Quota progress bars, and allows instant credential switching.

## Instructions When User Runs `/accounts`

### 1. Default Interactive Menu (`/accounts` or `/accounts menu` or `/accounts list`)
When the user types `/accounts` without specific arguments:
1. Run `agy-accounts limits` via terminal.
2. Print the exact verbatim stdout of `agy-accounts limits` (containing the account table and the `└ Models & Quota` progress bars). Do NOT summarize, rewrite, or convert it into conversational bullet points.
3. Immediately call `ask_question` with an interactive action menu:
   - Question: "Antigravity Account Switcher — Select an action:"
   - Options:
     - "Switch active account"
     - "Add new Google account (OAuth)"
     - "Import current session as new profile"
     - "Refresh limits and quota cache"
     - "Remove an account profile"
4. When the user selects an option:
   - "Switch active account": Run `agy-accounts list` to get profiles, then call `ask_question` listing each available profile to switch to. Run `agy-accounts switch <selected>`.
   - "Add new Google account (OAuth)": Prompt for profile name and run `agy-accounts add <name>`.
   - "Import current session as new profile": Prompt for profile name and run `agy-accounts add <name> --import`.
   - "Refresh limits and quota cache": Run `agy-accounts limits --refresh`.
   - "Remove an account profile": Ask which profile to remove and run `agy-accounts remove <name> -y`.

### 2. Direct Subcommands
If the user passes arguments with `/accounts`, execute directly without displaying the menu:
- `/accounts switch <name>`: Run `agy-accounts switch <name>`.
- `/accounts add <name>`: If current session, run `agy-accounts add <name> --import`. Otherwise run `agy-accounts add <name>`.
- `/accounts remove <name>`: Run `agy-accounts remove <name> -y`.
- `/accounts current`: Run `agy-accounts current`.
- `/accounts limits` or `/accounts quota`: Run `agy-accounts limits`.

### 3. Response Style
- Never generate conversational AI fluff, markdown lists, or "Quick Actions" bullets when `/accounts` is called.
- Always output the exact `└ Models & Quota` card and use the native interactive question modal for user navigation.
