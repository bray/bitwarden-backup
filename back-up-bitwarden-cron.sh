#!/usr/bin/env bash

# Bitwarden Vault Backup Script - Cron Wrapper
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 Brian Ray
#
# Script to run the Bitwarden backup script via cron,
# with optional healthchecks.io integration as a dead man's switch.
#
# Requirements:
#   - Commands:
#       back-up-bitwarden.sh (the main backup script)
#   - Environment variables:
#       HEALTHCHECKS_URL (optional)

set -euo pipefail
IFS=$'\n\t'

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ping_healthchecks() {
  local status="$1"
  local ping_url="${HEALTHCHECKS_URL:-}"

  if [[ -z "$ping_url" ]]; then
    return
  fi

  case "$status" in
    start|fail)
      ping_url="$ping_url/$status"
      ;;
    *)
      ;; # use base url
  esac

  curl --max-time 10 --retry 5 "$ping_url" >/dev/null 2>&1 || \
    log_error "Failed to ping healthchecks.io"
}

main() {
  ping_healthchecks "start"

  if "${CURRENT_DIR}/back-up-bitwarden.sh"; then
    ping_healthchecks "done"
  else
    ping_healthchecks "fail"
  fi
}

main "$@"
