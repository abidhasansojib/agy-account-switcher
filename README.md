# agy-account-switcher

> Seamless multi-account manager, instant switcher, and quota monitor for Google Antigravity (`agy`).

Switch between multiple Google Antigravity accounts instantly without re-entering browser authentication codes every time. Tracks token expiration, auto-refreshes credentials, checks API rate limits, provides an interactive menu, and adds a `/accounts` shortcut inside Antigravity.

---

## ⚡ Quick Install

Run this one-liner in your terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/abidhasansojib/agy-account-switcher/main/install.sh | bash
```

*Prerequisites: Standard Linux/macOS with `bash`, `curl`, and `perl` (preinstalled on virtually all distributions). Zero external runtime dependencies.*

---

## 🗑️ Quick Uninstall

To completely remove `agy-account-switcher`:

```bash
curl -fsSL https://raw.githubusercontent.com/abidhasansojib/agy-account-switcher/main/uninstall.sh | bash
```

*(Or run `agy-accounts uninstall` from your terminal)*

---

## 🚀 How to Use

### 1. Interactive Terminal Menu
Run with no arguments to open the color interactive menu:
```bash
agy-accounts
```
*(or alias `agy-switcher`)*

```text
╔════════════════════════════════════════════════════════════╗
║              AGY ACCOUNT SWITCHER & LIMITS                 ║
╚════════════════════════════════════════════════════════════╝
  Active Profile: default

  [1] Switch Account
  [2] List Accounts
  [3] Add Account (OAuth / Import)
  [4] Check Limits & Status
  [5] Current Account Info
  [6] Refresh Token
  [7] Remove Account
  [0] Exit
```

### 2. Fast CLI Commands

```bash
# List all accounts and their active status
agy-accounts list

# Switch to another account instantly
agy-accounts switch <name|email>

# Check token expiration countdown and rate-limit status
agy-accounts limits

# View details of the currently active account
agy-accounts current

# Save your current active Antigravity session as a named profile
agy-accounts add <name> --import

# Log into a new Google account via OAuth link
agy-accounts add <name>

# Remove an account profile
agy-accounts remove <name> -y

# Force refresh token
agy-accounts refresh [name]
```

### 3. Antigravity Chat Shortcut (`/accounts`)

Inside any Antigravity chat session (`agy`), simply type:

- `/accounts` — displays the accounts table, active marker `*`, and remaining quota
- `/accounts switch <name>` — switches session credentials to that account
- `/accounts current` — shows your active account

---

## 🔒 Security & Privacy

- All stored credentials in `~/.gemini/agy-accounts/profiles/` are locked down with strict `0600` permissions.
- Credential swapping to `~/.gemini/antigravity-cli/antigravity-oauth-token` is atomic.
- Zero telemetry, zero external third-party servers. All authentication communicates directly with Google's official OAuth endpoints.

---

## 📄 License
[Apache-2.0](LICENSE)
