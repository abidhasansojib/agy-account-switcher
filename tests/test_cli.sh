#!/usr/bin/env bash
# End-to-end integration tests for bin/agy-accounts
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CLI="$PROJECT_ROOT/bin/agy-accounts"

FAILED=0
TOTAL=0

assert_contains() {
  local desc="$1"
  local haystack="$2"
  local needle="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$haystack" == *"$needle"* ]]; then
    echo "  [PASS] $desc"
  else
    echo "  [FAIL] $desc: expected to contain '$needle', got '$haystack'"
    FAILED=$((FAILED + 1))
  fi
}

echo "Testing agy-accounts CLI..."

if [[ ! -x "$CLI" ]]; then
  echo "  [FAIL] bin/agy-accounts not found or not executable"
  exit 1
fi

TEST_TMP=$(mktemp -d)
trap 'rm -rf "$TEST_TMP"' EXIT

export AGY_ACCOUNTS_DIR="$TEST_TMP/accounts"
export AGY_OAUTH_TOKEN_PATH="$TEST_TMP/antigravity-oauth-token"
export AGY_LIB_DIR="$PROJECT_ROOT/lib"

# 1. Test version
VERSION_OUT=$("$CLI" version)
assert_contains "CLI reports version" "$VERSION_OUT" "agy-accounts version"

# 2. Setup mock active token
MOCK_TOKEN='{
  "auth_method": "consumer",
  "id_token": "eyJhbGciOiJub25lIn0.eyJlbWFpbCI6ImFjYzFAZ21haWwuY29tIiwibmFtZSI6IkFjY291bnQgT25lIn0.",
  "token": {
    "access_token": "ya29.acc1",
    "token_type": "Bearer",
    "refresh_token": "1//ref1",
    "expiry": "2035-01-01T00:00:00Z"
  }
}'
mkdir -p "$(dirname "$AGY_OAUTH_TOKEN_PATH")"
printf "%s\n" "$MOCK_TOKEN" > "$AGY_OAUTH_TOKEN_PATH"
chmod 0600 "$AGY_OAUTH_TOKEN_PATH"

# 3. Test add --import
ADD_OUT=$("$CLI" add acc1 --import)
assert_contains "add --import imports account" "$ADD_OUT" "acc1"

# Setup second mock active token
MOCK_TOKEN2='{
  "auth_method": "consumer",
  "id_token": "eyJhbGciOiJub25lIn0.eyJlbWFpbCI6ImFjYzJAZ21haWwuY29tIiwibmFtZSI6IkFjY291bnQgVHdvIn0.",
  "token": {
    "access_token": "ya29.acc2",
    "token_type": "Bearer",
    "refresh_token": "1//ref2",
    "expiry": "2035-01-01T00:00:00Z"
  }
}'
printf "%s\n" "$MOCK_TOKEN2" > "$AGY_OAUTH_TOKEN_PATH"
"$CLI" add acc2 --import

# 4. Test list
LIST_OUT=$("$CLI" list)
assert_contains "list includes acc1" "$LIST_OUT" "acc1"
assert_contains "list includes acc2" "$LIST_OUT" "acc2"
assert_contains "list includes email1" "$LIST_OUT" "acc1@gmail.com"
assert_contains "list includes email2" "$LIST_OUT" "acc2@gmail.com"

# 5. Test switch
SWITCH_OUT=$("$CLI" switch acc1)
assert_contains "switch outputs success" "$SWITCH_OUT" "Switched to acc1"

# 6. Test current
CURRENT_OUT=$("$CLI" current)
assert_contains "current reports acc1" "$CURRENT_OUT" "acc1"
assert_contains "current reports acc1 email" "$CURRENT_OUT" "acc1@gmail.com"

# Check active file
assert_contains "token file updated to ya29.acc1" "$(cat "$AGY_OAUTH_TOKEN_PATH")" "ya29.acc1"

# 7. Test limits
LIMITS_OUT=$("$CLI" limits)
assert_contains "limits shows acc1" "$LIMITS_OUT" "acc1"
assert_contains "limits shows acc2" "$LIMITS_OUT" "acc2"

# 8. Test remove
REMOVE_OUT=$("$CLI" remove acc2 -y)
assert_contains "remove outputs confirmation" "$REMOVE_OUT" "acc2"
LIST_AFTER_REMOVE=$("$CLI" list)
if [[ "$LIST_AFTER_REMOVE" != *"acc2"* ]]; then
  TOTAL=$((TOTAL + 1))
  echo "  [PASS] acc2 not in list after removal"
else
  TOTAL=$((TOTAL + 1))
  echo "  [FAIL] acc2 still in list"
  FAILED=$((FAILED + 1))
fi

echo "Results: $((TOTAL - FAILED))/$TOTAL tests passed."
if [[ $FAILED -gt 0 ]]; then
  exit 1
fi
