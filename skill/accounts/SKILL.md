---
name: accounts
description: Manage, list, inspect rate limits, and switch Antigravity Google accounts. Activate when user types /accounts, asks to switch accounts, check account limits, or manage credentials.
---

# Antigravity Account Switcher (`/accounts`)

This skill allows the user to manage multiple Google Antigravity accounts, inspect rate limits, and switch active credentials directly within an active Antigravity session without needing to re-login via browser every time.

## Available Actions

### 1. Show Accounts & Rate Limits
When the user types `/accounts`, `/accounts list`, or asks to see their accounts/limits:
- Run `agy-accounts limits` or `agy-accounts list` via terminal.
- Display the clean summary table showing:
  - Profile name
  - Google email address
  - Token expiration countdown
  - Current active status (`ACTIVE *` vs `ACTIVE`)
  - Quota and rate-limit status

### 2. Switch Active Account
When the user types `/accounts switch <name>` or asks to switch to another account (e.g., "switch to work account"):
- Run `agy-accounts switch <name>`.
- Confirm the new active account, email address, and token lifetime to the user.

### 3. Add an Account
When the user types `/accounts add <name>`:
- If importing the current session: run `agy-accounts add <name> --import`.
- If logging in a new Google account: inform the user to run `agy-accounts add <name>` in their terminal to open the authorization link.

### 4. Remove an Account
When the user types `/accounts remove <name>`:
- Run `agy-accounts remove <name> -y`.
- Confirm profile removal.

### 5. Check Active Account
When the user types `/accounts current` or asks which account is active:
- Run `agy-accounts current`.
- Report active profile name, email, and token expiry.
