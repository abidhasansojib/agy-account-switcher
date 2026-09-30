#!/usr/bin/env bash
# lib/storage.sh: Storage, profile management, and credential switching
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR"
AUTH_PL="$LIB_DIR/auth.pl"

export AGY_ACCOUNTS_DIR="${AGY_ACCOUNTS_DIR:-$HOME/.gemini/agy-accounts}"
export AGY_OAUTH_TOKEN_PATH="${AGY_OAUTH_TOKEN_PATH:-$HOME/.gemini/antigravity-cli/antigravity-oauth-token}"

storage_init() {
  mkdir -p "$AGY_ACCOUNTS_DIR/profiles"
  mkdir -p "$AGY_ACCOUNTS_DIR/backup"
  chmod 700 "$AGY_ACCOUNTS_DIR"
  chmod 700 "$AGY_ACCOUNTS_DIR/profiles"
  chmod 700 "$AGY_ACCOUNTS_DIR/backup"
}

storage_get_active() {
  local active_file="$AGY_ACCOUNTS_DIR/active"
  if [[ -f "$active_file" ]]; then
    tr -d '[:space:]' < "$active_file"
  else
    echo ""
  fi
}

storage_set_active() {
  local name="$1"
  storage_init
  echo "$name" > "$AGY_ACCOUNTS_DIR/active"
}

storage_find_profile() {
  local query="$1"
  local direct="$AGY_ACCOUNTS_DIR/profiles/${query}.json"
  if [[ -f "$direct" ]]; then
    echo "$direct"
    return 0
  fi

  # Search by email or sub if not found by filename
  for p in "$AGY_ACCOUNTS_DIR/profiles"/*.json; do
    [[ -e "$p" ]] || continue
    if grep -q "\"email\" *: *\"$query\"" "$p" 2>/dev/null; then
      echo "$p"
      return 0
    fi
  done
  return 1
}

storage_save_profile() {
  local name="$1"
  local content_or_file="$2"
  storage_init

  local target="$AGY_ACCOUNTS_DIR/profiles/${name}.json"
  local tmp_target="${target}.tmp.$$"

  if [[ -f "$content_or_file" ]]; then
    cp "$content_or_file" "$tmp_target"
  else
    printf "%s\n" "$content_or_file" > "$tmp_target"
  fi

  # Validate and normalize JSON using perl with single-quoted script
  local update_ok
  if ! perl -MJSON::PP -e '
    my ($file, $pname) = @ARGV;
    local $/;
    open(my $fh, "<", $file) or die $!;
    my $d = eval { JSON::PP::decode_json(<$fh>) };
    close($fh);
    die "Invalid JSON" unless $d && ref($d) eq "HASH";
    die "No token in profile" unless $d->{token};

    $d->{name} = $pname;
    $d->{created_at} ||= time();
    $d->{last_used_at} ||= time();

    # If id_token is present but email not set, decode email
    if ($d->{id_token} && (!$d->{email} || $d->{email} eq "unknown")) {
      use MIME::Base64 qw(decode_base64);
      my @parts = split(/\./, $d->{id_token});
      if (@parts >= 2) {
        my $b64 = $parts[1];
        $b64 =~ tr/-_/+\//;
        $b64 .= "=" x ((4 - length($b64) % 4) % 4);
        my $payload = eval { JSON::PP::decode_json(decode_base64($b64)) };
        if ($payload) {
          $d->{email} = $payload->{email} if $payload->{email};
          $d->{display_name} = $payload->{name} if $payload->{name} && !$d->{display_name};
          $d->{sub} = $payload->{sub} if $payload->{sub};
        }
      }
    }

    open(my $out, ">", $file) or die $!;
    print $out JSON::PP->new->utf8->pretty->encode($d);
    close($out);
  ' "$tmp_target" "$name" 2>/dev/null; then
    rm -f "$tmp_target"
    echo "Error: Failed to validate or save profile JSON" >&2
    return 1
  fi

  chmod 0600 "$tmp_target"
  mv -f "$tmp_target" "$target"
}

storage_remove_profile() {
  local name="$1"
  local file
  if file=$(storage_find_profile "$name"); then
    rm -f "$file"
    local active
    active=$(storage_get_active)
    local base_clean
    base_clean=$(basename "$file" .json)
    if [[ "$active" == "$name" || "$active" == "$base_clean" ]]; then
      rm -f "$AGY_ACCOUNTS_DIR/active"
    fi
    return 0
  else
    echo "Profile '$name' not found." >&2
    return 1
  fi
}

storage_list_profiles() {
  storage_init
  local list=()
  for p in "$AGY_ACCOUNTS_DIR/profiles"/*.json; do
    [[ -e "$p" ]] || continue
    local b
    b=$(basename "$p" .json)
    list+=("$b")
  done
  printf "%s\n" "${list[@]}"
}

storage_sync_current() {
  local active
  active=$(storage_get_active)
  if [[ -n "$active" && -f "$AGY_OAUTH_TOKEN_PATH" ]]; then
    local p_file
    if p_file=$(storage_find_profile "$active"); then
      perl -MJSON::PP -e '
        my ($curr_file, $prof_file) = @ARGV;
        local $/;
        open(my $f1, "<", $curr_file) or exit 0;
        my $curr = eval { JSON::PP::decode_json(<$f1>) };
        close($f1);
        open(my $f2, "<", $prof_file) or exit 0;
        my $prof = eval { JSON::PP::decode_json(<$f2>) };
        close($f2);
        exit 0 unless $curr && $prof;
        if ($curr->{token}->{access_token} && $curr->{token}->{access_token} ne ($prof->{token}->{access_token} // "")) {
            $prof->{token} = $curr->{token};
            $prof->{last_used_at} = time();
            open(my $out, ">", $prof_file) or exit 0;
            print $out JSON::PP->new->utf8->pretty->encode($prof);
            close($out);
        }
      ' "$AGY_OAUTH_TOKEN_PATH" "$p_file" 2>/dev/null || true
    fi
  fi
}

storage_backup_current() {
  if [[ -f "$AGY_OAUTH_TOKEN_PATH" ]]; then
    storage_init
    local ts
    ts=$(date +%Y%m%d_%H%M%S)
    cp "$AGY_OAUTH_TOKEN_PATH" "$AGY_ACCOUNTS_DIR/backup/token_${ts}.json" 2>/dev/null || true
  fi
}

storage_switch() {
  local target_name="$1"
  storage_init

  local target_file
  if ! target_file=$(storage_find_profile "$target_name"); then
    echo "Error: Account '$target_name' not found." >&2
    return 1
  fi

  # 1. Sync current credentials before switching away
  storage_sync_current

  # 2. Check token expiry and auto-refresh if needed
  if [[ -x "$AUTH_PL" ]]; then
    local expiry
    expiry=$(perl -MJSON::PP -e '
      local $/;
      my $d = JSON::PP::decode_json(<>);
      print $d->{token}->{expiry} || "";
    ' "$target_file" 2>/dev/null || echo "")

    if [[ -n "$expiry" ]] && ! "$AUTH_PL" is-expired "$expiry" 2>/dev/null; then
      # Expired or close to expiring -> refresh
      "$AUTH_PL" refresh "$target_file" 2>/dev/null || true
    fi
  fi

  # 3. Create backup of current token
  storage_backup_current

  # 4. Extract standard antigravity-oauth-token structure
  local parent_dir
  parent_dir="$(dirname "$AGY_OAUTH_TOKEN_PATH")"
  mkdir -p "$parent_dir"

  local tmp_oauth="${AGY_OAUTH_TOKEN_PATH}.tmp.$$"
  perl -MJSON::PP -e '
    local $/;
    my $d = JSON::PP::decode_json(<>);
    my $oauth_token = {
      auth_method => $d->{auth_method} || "consumer",
      id_token    => $d->{id_token} || "",
      token       => $d->{token} || {}
    };
    print JSON::PP->new->utf8->pretty->encode($oauth_token);
  ' "$target_file" > "$tmp_oauth"

  chmod 0600 "$tmp_oauth"
  mv -f "$tmp_oauth" "$AGY_OAUTH_TOKEN_PATH"

  # 5. Update active marker and last_used timestamp
  local clean_name
  clean_name=$(basename "$target_file" .json)
  storage_set_active "$clean_name"

  perl -MJSON::PP -e '
    my ($file) = @ARGV;
    local $/;
    open(my $fh, "<", $file) or exit 0;
    my $d = JSON::PP::decode_json(<$fh>);
    close($fh);
    $d->{last_used_at} = time();
    open(my $out, ">", $file) or exit 0;
    print $out JSON::PP->new->utf8->pretty->encode($d);
    close($out);
  ' "$target_file" 2>/dev/null || true
}
