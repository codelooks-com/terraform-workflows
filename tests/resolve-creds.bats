#!/usr/bin/env bats

SCRIPT=".github/actions/resolve-creds/resolve-creds.sh"

setup() {
  GITHUB_ENV="$(mktemp)"
  export GITHUB_ENV
}

teardown() {
  rm -f "$GITHUB_ENV"
}

@test "maps a provided credential into GITHUB_ENV" {
  export IN_CLOUDFLARE_API_TOKEN="tok123"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q "CLOUDFLARE_API_TOKEN<<__CRED_EOF__" "$GITHUB_ENV"
  grep -qx "tok123" "$GITHUB_ENV"
}

@test "skips an unset credential so runner-provided env survives" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  ! grep -q "CLOUDFLARE_API_TOKEN" "$GITHUB_ENV"
}

@test "skips an empty-string credential" {
  export IN_CLOUDFLARE_API_TOKEN=""
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  ! grep -q "CLOUDFLARE_API_TOKEN" "$GITHUB_ENV"
}

@test "maps multiple credentials" {
  export IN_AWS_ACCESS_KEY_ID="ak"
  export IN_AWS_SECRET_ACCESS_KEY="sk"
  run bash "$SCRIPT"
  grep -q "AWS_ACCESS_KEY_ID<<__CRED_EOF__" "$GITHUB_ENV"
  grep -q "AWS_SECRET_ACCESS_KEY<<__CRED_EOF__" "$GITHUB_ENV"
}

@test "preserves multiline secrets (PEM)" {
  export IN_GITHUB_APP_PEM_FILE=$'-----BEGIN-----\nline2\n-----END-----'
  run bash "$SCRIPT"
  grep -q "GITHUB_APP_PEM_FILE<<__CRED_EOF__" "$GITHUB_ENV"
  grep -qx "line2" "$GITHUB_ENV"
}
