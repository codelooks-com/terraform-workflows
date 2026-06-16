#!/usr/bin/env bash
# Map caller-provided credential inputs (IN_<NAME>) into $GITHUB_ENV, but ONLY
# when non-empty. Cloud runners pass creds as GitHub secrets (IN_* populated);
# cluster (ARC) runners receive creds via pod envFrom (IN_* empty), so skipping
# empties preserves the runner-provided environment. Uses the heredoc form so
# multiline secrets (e.g. PEM keys) survive.
set -euo pipefail

: "${GITHUB_ENV:?GITHUB_ENV must be set}"

CRED_VARS=(
  AWS_ACCESS_KEY_ID
  AWS_SECRET_ACCESS_KEY
  CLOUDFLARE_API_TOKEN
  TS_OAUTH_CLIENT_ID
  TS_OAUTH_SECRET
  NEXTDNS_API_KEY
  GITHUB_APP_ID
  GITHUB_APP_INSTALLATION_ID
  GITHUB_APP_PEM_FILE
  VSPHERE_USER
  VSPHERE_PASSWORD
  VSPHERE_SERVER
)

for name in "${CRED_VARS[@]}"; do
  in_var="IN_${name}"
  value="${!in_var:-}"
  if [ -n "${value}" ]; then
    {
      echo "${name}<<__CRED_EOF__"
      printf '%s\n' "${value}"
      echo "__CRED_EOF__"
    } >> "${GITHUB_ENV}"
  fi
done
