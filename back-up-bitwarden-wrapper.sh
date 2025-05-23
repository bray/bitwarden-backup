#!/usr/bin/env bash

# Bitwarden Vault Backup Script - LaunchAgent Wrapper
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 Brian Ray
#
# Script to run the Bitwarden backup script via LaunchAgent,
# with optional healthchecks.io integration as a dead man's switch.
#
# Requirements:
#   - Commands:
#       back-up-bitwarden.sh (the main backup script)
#   - Environment variables:
#       See back-up-bitwarden.sh for other required and optional variables
#       HEALTHCHECKS_URL (optional)

set -euo pipefail
IFS=$'\n\t'

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() {
  echo -e "$*"
}

log_ping_healthchecks_error() {
  log "Failed to ping healthchecks.io start"
}

check_healthchecks_url() {
  HEALTHCHECKS_URL="${HEALTHCHECKS_URL:-}"

  if [[ -z "${HEALTHCHECKS_URL}" ]]; then
    log "HEALTHCHECKS_URL is not set. Skipping healthchecks.io integration.\n"
  fi
}

ping_healthchecks() {
  local status="$1"  # "start", "0", or "1"
  local stderr="${2:-}"  # Optional stderr for status pings

  [[ -n "$HEALTHCHECKS_URL" ]] || return 0

  local clean_stderr
  if [[ -n "$stderr" ]]; then
    # Remove ANSI escape codes (e.g. colors) from stderr
    clean_stderr=$(echo "$stderr" | sed $'s/\x1b\\[[0-9;?]*[ -/]*[@-~]//g')
  fi

  case "$status" in
    "start")
      curl -fsS --max-time 10 --retry 5 "${HEALTHCHECKS_URL}/start" > /dev/null || \
        log_ping_healthchecks_error
      ;;
    [0-9]*)
      curl -fsS --max-time 10 --retry 5 --data-raw "$clean_stderr" "${HEALTHCHECKS_URL}/${status}" > /dev/null || \
        log_ping_healthchecks_error
      ;;
    *)
      log "Invalid healthchecks status: ${status}"
      return 1
      ;;
  esac
}

run_with_capture() {
  local stderr_file=$(mktemp)
  local status_code
  local stderr_content

  set +e
  "$@" 2> >(tee "$stderr_file" >&2)
  status_code=$?
  set -e

  stderr_content=$(cat "$stderr_file")
  rm -f "$stderr_file"

  CAPTURED_STATUS=$status_code
  CAPTURED_STDERR="$stderr_content"
}

main() {
  check_healthchecks_url
  ping_healthchecks "start"
  run_with_capture "${CURRENT_DIR}/back-up-bitwarden.sh"
  ping_healthchecks "$CAPTURED_STATUS" "$CAPTURED_STDERR"
}

main "$@"
