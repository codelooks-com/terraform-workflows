#!/usr/bin/env bats

SCRIPT=".github/actions/drift-decide/decide.sh"

@test "exit 0 maps to none" {
  run bash "$SCRIPT" 0
  [ "$status" -eq 0 ]
  [ "$output" = "none" ]
}

@test "exit 2 maps to drift" {
  run bash "$SCRIPT" 2
  [ "$output" = "drift" ]
}

@test "exit 1 maps to error" {
  run bash "$SCRIPT" 1
  [ "$output" = "error" ]
}

@test "unknown code maps to error" {
  run bash "$SCRIPT" 7
  [ "$output" = "error" ]
}

@test "missing argument exits non-zero" {
  run bash "$SCRIPT"
  [ "$status" -ne 0 ]
}
