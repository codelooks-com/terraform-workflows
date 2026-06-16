#!/usr/bin/env bash
# Translate `plan -detailed-exitcode` status into a drift action.
#   0 -> none   (no changes)
#   2 -> drift  (changes detected)
#   1 -> error  (plan failed)
# Usage: decide.sh <plan-exit-code>
set -euo pipefail

code="${1:?usage: decide.sh <plan-exit-code>}"
case "${code}" in
  0) echo "none" ;;
  2) echo "drift" ;;
  *) echo "error" ;;
esac
