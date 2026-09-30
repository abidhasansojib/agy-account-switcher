#!/usr/bin/env bash
# Unit tests for lib/auth.pl
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AUTH_PL="$PROJECT_ROOT/lib/auth.pl"

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

echo "Testing auth.pl..."

# 1. Existence and execution check
if [[ ! -x "$AUTH_PL" ]]; then
  echo "  [FAIL] auth.pl not found or not executable at $AUTH_PL"
  exit 1
fi

# 2. Test decode-jwt with mock token
# Header: {"alg":"none"} -> eyJhbGciOiJub25lIn0
# Payload: {"email":"test@example.com","name":"Test User","sub":"12345"}
# Base64url payload: eyJlbWFpbCI6InRlc3RAZXhhbXBsZS5jb20iLCJuYW1lIjoiVGVzdCBVc2VyIiwic3ViIjoiMTIzNDUifQ
MOCK_JWT="eyJhbGciOiJub25lIn0.eyJlbWFpbCI6InRlc3RAZXhhbXBsZS5jb20iLCJuYW1lIjoiVGVzdCBVc2VyIiwic3ViIjoiMTIzNDUifQ."
DECODED=$("$AUTH_PL" decode-jwt "$MOCK_JWT")
assert_contains "decode-jwt extracts email" "$DECODED" "test@example.com"
assert_contains "decode-jwt extracts name" "$DECODED" "Test User"
assert_contains "decode-jwt extracts sub" "$DECODED" "12345"

# 3. Test is-expired
# Past date should report expired (exit code 1 or output "1")
if "$AUTH_PL" is-expired "2020-01-01T00:00:00Z"; then
  assert_eq "is-expired on 2020 date" "not-expired" "expired"
else
  assert_eq "is-expired on 2020 date" "expired" "expired"
fi

# Future date should report valid (exit code 0 or output "0")
if "$AUTH_PL" is-expired "2035-01-01T00:00:00Z"; then
  assert_eq "is-expired on 2035 date" "valid" "valid"
else
  assert_eq "is-expired on 2035 date" "expired" "valid"
fi

# 4. Test expiry-countdown
COUNTDOWN_PAST=$("$AUTH_PL" countdown "2020-01-01T00:00:00Z")
assert_contains "countdown past returns Expired" "$COUNTDOWN_PAST" "Expired"

COUNTDOWN_FUTURE=$("$AUTH_PL" countdown "2035-01-01T00:00:00Z")
assert_contains "countdown future returns remaining" "$COUNTDOWN_FUTURE" "remaining"

# 5. Test oauth-url and PKCE verifier generation
TMP_VERIFIER=$(mktemp)
trap 'rm -f "$TMP_VERIFIER"' EXIT
OAUTH_URL=$("$AUTH_PL" oauth-url "$TMP_VERIFIER")
assert_contains "oauth-url uses Google auth endpoint" "$OAUTH_URL" "https://accounts.google.com/o/oauth2/auth"
assert_contains "oauth-url uses antigravity.google callback" "$OAUTH_URL" "redirect_uri=https%3A%2F%2Fantigravity.google%2Foauth-callback"
assert_contains "oauth-url uses PKCE S256 challenge" "$OAUTH_URL" "code_challenge_method=S256"
assert_contains "oauth-url contains client_id parameter" "$OAUTH_URL" "client_id="

VERIFIER_LEN=$(wc -c < "$TMP_VERIFIER" | tr -d '[:space:]')
assert_eq "verifier file written with 64 chars" "$VERIFIER_LEN" "64"

# 6. Test quota output rendering
TMP_PROF=$(mktemp)
echo '{"email":"test_quota@example.com","token":{"access_token":"ya29.fake"}}' > "$TMP_PROF"
QUOTA_OUT=$("$AUTH_PL" quota "$TMP_PROF")
assert_contains "quota output has Models & Quota header" "$QUOTA_OUT" "Models & Quota"
assert_contains "quota output has Account email" "$QUOTA_OUT" "Account: test_quota@example.com"
assert_contains "quota output has GEMINI MODELS section" "$QUOTA_OUT" "GEMINI MODELS"
assert_contains "quota output has CLAUDE AND GPT MODELS section" "$QUOTA_OUT" "CLAUDE AND GPT MODELS"
assert_contains "quota output has weekly limit" "$QUOTA_OUT" "Weekly Limit Remaining"
assert_contains "quota output has five hour limit" "$QUOTA_OUT" "Five Hour Limit Remaining"
assert_contains "quota output has explanatory footer" "$QUOTA_OUT" "Within each group, models share a weekly limit"
rm -f "$TMP_PROF"

echo "Results: $((TOTAL - FAILED))/$TOTAL tests passed."
if [[ $FAILED -gt 0 ]]; then
  exit 1
fi
