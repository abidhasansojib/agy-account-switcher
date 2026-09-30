#!/usr/bin/env bash
# Unit tests for lib/storage.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STORAGE_SH="$PROJECT_ROOT/lib/storage.sh"

FAILED=0
TOTAL=0

assert_eq() {
  local desc="$1"
  local actual="$2"
  local expected="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$actual" == "$expected" ]]; then
    echo "  [PASS] $desc"
  else
    echo "  [FAIL] $desc: expected '$expected', got '$actual'"
    FAILED=$((FAILED + 1))
  fi
}

assert_file_exists() {
  local desc="$1"
  local file="$2"
  TOTAL=$((TOTAL + 1))
  if [[ -e "$file" ]]; then
    echo "  [PASS] $desc"
  else
    echo "  [FAIL] $desc: '$file' does not exist"
    FAILED=$((FAILED + 1))
  fi
}

assert_perms_0600() {
  local desc="$1"
  local file="$2"
  TOTAL=$((TOTAL + 1))
  local perms
  perms=$(stat -c "%a" "$file" 2>/dev/null || stat -f "%Lp" "$file" 2>/dev/null)
  if [[ "$perms" == "600" ]]; then
    echo "  [PASS] $desc (permissions: $perms)"
  else
    echo "  [FAIL] $desc: expected 600, got $perms"
    FAILED=$((FAILED + 1))
  fi
}

echo "Testing storage.sh..."

if [[ ! -f "$STORAGE_SH" ]]; then
  echo "  [FAIL] storage.sh not found at $STORAGE_SH"
  exit 1
fi

# Setup isolated environment
TEST_TMP=$(mktemp -d)
trap 'rm -rf "$TEST_TMP"' EXIT

export AGY_ACCOUNTS_DIR="$TEST_TMP/accounts"
export AGY_OAUTH_TOKEN_PATH="$TEST_TMP/antigravity-oauth-token"

source "$STORAGE_SH"

# 1. Test storage_init
storage_init
assert_file_exists "Init creates profiles dir" "$AGY_ACCOUNTS_DIR/profiles"
assert_file_exists "Init creates backup dir" "$AGY_ACCOUNTS_DIR/backup"

# 2. Test storage_save_profile
MOCK_PROFILE='{
  "name": "personal",
  "email": "personal@gmail.com",
  "display_name": "Personal Account",
  "auth_method": "consumer",
  "id_token": "eyJhbGciOiJub25lIn0.eyJlbWFpbCI6InBlcnNvbmFsQGdtYWlsLmNvbSJ9.",
  "token": {
    "access_token": "ya29.personal_token",
    "token_type": "Bearer",
    "refresh_token": "1//refresh_personal",
    "expiry": "2035-01-01T00:00:00Z"
  }
}'
storage_save_profile "personal" "$MOCK_PROFILE"
assert_file_exists "Profile personal.json saved" "$AGY_ACCOUNTS_DIR/profiles/personal.json"
assert_perms_0600 "Profile personal.json has 0600 perms" "$AGY_ACCOUNTS_DIR/profiles/personal.json"

# Save second profile
MOCK_WORK='{
  "name": "work",
  "email": "work@company.com",
  "display_name": "Work Account",
  "auth_method": "consumer",
  "id_token": "eyJhbGciOiJub25lIn0.eyJlbWFpbCI6IndvcmtAY29tcGFueS5jb20ifQ.",
  "token": {
    "access_token": "ya29.work_token",
    "token_type": "Bearer",
    "refresh_token": "1//refresh_work",
    "expiry": "2035-01-01T00:00:00Z"
  }
}'
storage_save_profile "work" "$MOCK_WORK"
assert_file_exists "Profile work.json saved" "$AGY_ACCOUNTS_DIR/profiles/work.json"

# 3. Test storage_list_profiles
PROFILES=$(storage_list_profiles)
if [[ "$PROFILES" == *"personal"* && "$PROFILES" == *"work"* ]]; then
  assert_eq "storage_list_profiles contains both profiles" "yes" "yes"
else
  assert_eq "storage_list_profiles contains both profiles" "$PROFILES" "contains personal and work"
fi

# 4. Test storage_switch
storage_switch "personal"
ACTIVE=$(storage_get_active)
assert_eq "Active profile is personal" "$ACTIVE" "personal"
assert_file_exists "Active oauth token exists" "$AGY_OAUTH_TOKEN_PATH"
assert_perms_0600 "Active oauth token has 0600 perms" "$AGY_OAUTH_TOKEN_PATH"

# Check active token content has personal token
if grep -q "ya29.personal_token" "$AGY_OAUTH_TOKEN_PATH"; then
  assert_eq "antigravity-oauth-token contains personal access_token" "found" "found"
else
  assert_eq "antigravity-oauth-token contains personal access_token" "missing" "found"
fi

# 5. Switch to work
storage_switch "work"
ACTIVE=$(storage_get_active)
assert_eq "Active profile is now work" "$ACTIVE" "work"
if grep -q "ya29.work_token" "$AGY_OAUTH_TOKEN_PATH"; then
  assert_eq "antigravity-oauth-token contains work access_token" "found" "found"
else
  assert_eq "antigravity-oauth-token contains work access_token" "missing" "found"
fi

# 6. Test storage_remove_profile
storage_remove_profile "personal"
if [[ ! -f "$AGY_ACCOUNTS_DIR/profiles/personal.json" ]]; then
  assert_eq "personal.json removed" "removed" "removed"
else
  assert_eq "personal.json removed" "still exists" "removed"
fi

echo "Results: $((TOTAL - FAILED))/$TOTAL tests passed."
if [[ $FAILED -gt 0 ]]; then
  exit 1
fi
