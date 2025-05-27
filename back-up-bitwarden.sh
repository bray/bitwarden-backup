#!/usr/bin/env bash

# Bitwarden Vault Backup Script
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 Brian Ray
#
# Backs up your Bitwarden vault to a local directory.
#
# The backup includes:
#   - Encrypted JSON export (Bitwarden format)
#   - Age-encrypted JSON export
#   - Age-encrypted CSV export
#
# Optional: Syncs backups to Proton Drive via rclone
#
# Requirements:
#   - Commands:
#       bw (Bitwarden CLI)
#       age (encryption tool)
#       rclone (optional, for Proton Drive sync)
#   - Scripts:
#       common-functions.sh (a library of common functions)
#
# Configuration:
#   All configuration is done via environment variables in:
#   $HOME/.config/back-up-bitwarden/.env
#
#   Required variables:
#     BW_CLIENTID         - Bitwarden API client ID
#     BW_CLIENTSECRET     - Bitwarden API client secret
#     BW_VAULT_PASSWORD   - Your Bitwarden master password
#     BW_JSON_PASSWORD    - Password for encrypted JSON export
#     AGE_PUBLIC_KEY      - Your age public key for encryption
#
#   Optional variables:
#     BW_BIN                         - Path to bw CLI (default: $(command -v bw))
#     AGE_BIN                        - Path to age CLI (default: $(command -v age))
#     RCLONE_BIN                     - Path to rclone CLI (default: $(command -v rclone))
#     BACKUP_DIR_BASE                - Backup directory (default: ./bitwarden_backups)
#     PROTON_DRIVE_REMOTE_NAME       - Rclone remote name for Proton Drive
#     PROTON_DRIVE_DIR_BASE          - Base destination path in Proton Drive
#
# Security:
#   - The .env file should be readable only by your user (chmod 600)
#   - Backups are encrypted with `age` using your public key
#   - Sensitive credentials are never written to disk
#   - All backup files are set to mode 600

set -euo pipefail
IFS=$'\n\t'

CONFIG_DIR="${HOME}/.config/back-up-bitwarden"
ENV_FILE="${CONFIG_DIR}/.env"


source_common_functions() {
  local path="${XDG_DATA_HOME:-${HOME}/.local/share}/scripts/common-functions.sh"

  if [[ -f "$path" ]]; then
    # shellcheck source=/dev/null
    source "$path"
  else
    echo "Error: common-functions.sh not found. Please install it first."
    exit 1
  fi
}

set_env_var_defaults() {
  BW_BIN="${BW_BIN:-$(command -v bw 2>/dev/null || true)}"
  AGE_BIN="${AGE_BIN:-$(command -v age 2>/dev/null || true)}"
  RCLONE_BIN="${RCLONE_BIN:-$(command -v rclone 2>/dev/null || true)}"
}

check_commands() {
  if [[ ! -x "$BW_BIN" ]]; then
    command_not_found "bw" "BW_BIN"
  fi

  if [[ ! -x "$AGE_BIN" ]]; then
    command_not_found "age" "AGE_BIN"
  fi
}

check_proton_drive_env_vars() {
  [[ -x "${RCLONE_BIN:-}" ]] || return 0

  local remote_name_set=0
  local dest_path_set=0

  if [[ -n "${PROTON_DRIVE_REMOTE_NAME:-}" ]]; then
    remote_name_set=1
  fi

  if [[ -n "${PROTON_DRIVE_DIR_BASE:-}" ]]; then
    dest_path_set=1
  fi

  if (( remote_name_set || dest_path_set )); then
    if (( !remote_name_set || !dest_path_set )); then
      fail "If either PROTON_DRIVE_REMOTE_NAME or PROTON_DRIVE_DIR_BASE is set, both must be set."
    fi

    if [[ ! -x "${RCLONE_BIN:-}" ]]; then
      fail "RCLONE_BIN is required when using Proton Drive upload, but was not found."
    fi

    PROTON_DRIVE_DIR="${PROTON_DRIVE_DIR_BASE}/${YEAR}/${MONTH}/${DAY}/"
    PROTON_DRIVE_CONFIGURED=1
  fi
}

check_file() {
  if [[ ! -f "$1" ]]; then
    fail "File $1 not found. Please create it first."
  fi
}

check_files() {
  check_file "$ENV_FILE"
}

load_config() {
  if [[ -f "$ENV_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$ENV_FILE"
  fi
  
  local required_vars=(
    "BW_CLIENTID"
    "BW_CLIENTSECRET"
    "BW_VAULT_PASSWORD"
    "BW_JSON_PASSWORD"
    "AGE_PUBLIC_KEY"
  )

  for var in "${required_vars[@]}"; do
    if [[ -z "${!var:-}" ]]; then
      fail "Required variable ${var} not set in ${ENV_FILE}"
    fi
  done

  PROTON_DRIVE_CONFIGURED=0

  BACKUP_DIR_BASE="${BACKUP_DIR_BASE:-bitwarden_backups}"
  YEAR=$(date +'%Y')
  MONTH=$(date +'%m')
  DAY=$(date +'%d')
  TIMESTAMP=$(date +'%Y-%m-%d_%H-%M-%S')
  BACKUP_DIR="${BACKUP_DIR_BASE}/${YEAR}/${MONTH}/${DAY}"
}

print_config() {
  log "\nConfiguration:"
  log "  Bitwarden CLI: ${BW_BIN}"
  log "  Age CLI: ${AGE_BIN}"
  log "  Output directory: ${BACKUP_DIR}/"

  if (( PROTON_DRIVE_CONFIGURED )); then
    log "  Rclone CLI: ${RCLONE_BIN}"
    log "  Proton Drive remote name: ${PROTON_DRIVE_REMOTE_NAME:-}"
    log "  Proton Drive destination path: ${PROTON_DRIVE_DIR:-}"
  else
    log "  Proton Drive backup: [not configured]"
  fi

  log
}

log_in_and_unlock() {
  log "Logging in to Bitwarden..."

  BW_CLIENTID="$BW_CLIENTID" BW_CLIENTSECRET="$BW_CLIENTSECRET" \
    "$BW_BIN" login --raw --apikey

  BW_SESSION="$(BW_VAULT_PASSWORD="$BW_VAULT_PASSWORD" "$BW_BIN" unlock --raw --passwordenv BW_VAULT_PASSWORD)"

  log_success "Logged in to Bitwarden."
}

log_export_start() {
  local description="$1"
  log "\nExporting Bitwarden vault via: ${description} ..."
}

log_export_end() {
  local file_path="$1"
  log_success "🔒Exported to $(basename "${file_path}")."
}

export_bitwarden_encrypted() {
  local filename_base_path="$1"
  local desc="Bitwarden-specific encrypted JSON"
  local output_file_path="${filename_base_path}-encrypted.json"

  log_export_start "${desc}"

  "$BW_BIN" export --session "${BW_SESSION}" --format encrypted_json \
    --password "${BW_JSON_PASSWORD}" --output "${output_file_path}" > /dev/null

  chmod 600 "${output_file_path}"

  log_export_end "${output_file_path}"
}

export_and_age_encrypt() {
  local filename_base_path="$1"
  local format="$2" # json or csv
  local desc="$3"
  local output_file_path="${filename_base_path}.${format}.age"

  log_export_start "${desc}"

  "$BW_BIN" export --session "${BW_SESSION}" --format "$format" --raw | \
    "$AGE_BIN" --encrypt -r "$AGE_PUBLIC_KEY" -o "$output_file_path"

  chmod 600 "${output_file_path}"

  log_export_end "${output_file_path}"
}

export_backups() {
  local filename_base_path="${BACKUP_DIR}/bitwarden_backup_${TIMESTAMP}"

  mkdir -p "${BACKUP_DIR}"
  chmod 700 "${BACKUP_DIR}"

  export_bitwarden_encrypted "${filename_base_path}"
  export_and_age_encrypt "${filename_base_path}" "json" "plain text JSON, encrypted with age"
  export_and_age_encrypt "${filename_base_path}" "csv" "plain text CSV, encrypted with age"
}

rclone_to_proton_drive() {
  (( PROTON_DRIVE_CONFIGURED )) || return 0

  if [[ -d "${BACKUP_DIR}" ]]; then
    log "\nUploading backups to Proton Drive..."

    "$RCLONE_BIN" copy -v --stats-one-line "${BACKUP_DIR}" "${PROTON_DRIVE_REMOTE_NAME}:${PROTON_DRIVE_DIR}"

    log_success "Backups uploaded to Proton Drive."
  else
    log_error "Backups directory path not found: ${BACKUP_DIR}"
  fi
}

now() {
  date +"%-m/%-d/%Y %-I:%M:%S %p %Z"
}

clean_up() {
  log "\nCleaning up..."

  if "$BW_BIN" login --check >/dev/null 2>&1; then
    if output=$("$BW_BIN" logout); then
      log_success "Logged out of Bitwarden."
    else
      fail "Failed to log out of Bitwarden: ${output}."
    fi
  else
    log_success "Already logged out of Bitwarden."
  fi

  echo -e "\nFinished Bitwarden backup process at $(now)."
}

trap clean_up EXIT

main() {
  echo "Started Bitwarden backup process at $(now)."

  source_common_functions
  set_env_var_defaults
  check_commands
  load_config
  check_proton_drive_env_vars
  check_files
  print_config

  log_in_and_unlock
  export_backups
  rclone_to_proton_drive
}

main "$@"
