#!/usr/bin/env bash

# Bitwarden Vault Backup Script
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 Brian Ray
#
# Backs up your Bitwarden vault to a local directory, encrypting with age.
#
# Requirements:
#   - Commands:
#       bw (Bitwarden CLI)
#       age (encryption tool)
#       rclone (syncing to the cloud, optional)
#   - Environment variables:
#       AGE_PUBLIC_KEY
#       BW_BIN (optional, default: $(command -v bw))
#       AGE_BIN (optional, default: $(command -v age))
#       RCLONE_BIN (optional, default: $(command -v rclone))
#       OUTPUT_DIR (optional, default: ./bitwarden_backups)
#       PROTON_DRIVE_REMOTE_NAME (optional, default: proton-drive)
#       PROTON_DRIVE_DESTINATION_PATH (optional, default: Bitwarden Backups/<today>)
#   - Files (readable only by your user!):
#       $HOME/.config/bitwarden/client_id
#       $HOME/.config/bitwarden/client_secret
#       $HOME/.config/bitwarden/vault_password
#       $HOME/.config/bitwarden/json_password

set -euo pipefail
IFS=$'\n\t'

CONFIG_BASE_PATH="${HOME}/.config/bitwarden"
CLIENT_ID_FILE="${CONFIG_BASE_PATH}/client_id"
CLIENT_SECRET_FILE="${CONFIG_BASE_PATH}/client_secret"
VAULT_PASSWORD_FILE="${CONFIG_BASE_PATH}/vault_password"
JSON_PASSWORD_FILE="${CONFIG_BASE_PATH}/json_password"

OUTPUT_DIR="${OUTPUT_DIR:-bitwarden_backups}"
PROTON_DRIVE_CONFIGURED=0

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

log() {
  echo -e "$*";
}

log_success() {
  log "${GREEN}$*${NC}"
}

log_error() {
  log "${RED}$*${NC}" >&2
}

fail() {
  log_error "$*"
  exit 1
}

command_not_found() {
  local command_name="$1"
  local command_env_var="$2"

  fail "Required command '$command_name' not found in PATH or via \$${command_env_var}."
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

check_env_var() {
  local var_name="$1"

  if [[ -z "${!var_name:-}" ]]; then
    fail "You must set an env var $1."
  fi
}

check_env_vars() {
  check_env_var "AGE_PUBLIC_KEY"
  check_proton_drive_env_vars
}

check_file() {
  if [[ ! -f "$1" ]]; then
    fail "File $1 not found. Please create it first."
  fi
}

check_files() {
  check_file "$CLIENT_ID_FILE"
  check_file "$CLIENT_SECRET_FILE"
  check_file "$VAULT_PASSWORD_FILE"
  check_file "$JSON_PASSWORD_FILE"
}

load_secrets() {
  read -r bw_clientid < "$CLIENT_ID_FILE"
  read -r bw_clientsecret < "$CLIENT_SECRET_FILE"
  read -r json_password < "$JSON_PASSWORD_FILE"
}

print_config() {
  log "\nConfiguration:"
  log "  Bitwarden CLI: ${BW_BIN}"
  log "  Age CLI: ${AGE_BIN}"
  log "  Output directory: ${OUTPUT_DIR}"

  if (( PROTON_DRIVE_CONFIGURED )); then
    log "  Rclone CLI: ${RCLONE_BIN}"
    log "  Proton Drive remote name: ${PROTON_DRIVE_REMOTE_NAME:-}"
    log "  Proton Drive destination path: ${PROTON_DRIVE_DESTINATION_PATH:-}"
  else
    log "  Proton Drive backup: [not configured]"
  fi

  log
}

log_in_and_unlock() {
  log "Logging in to Bitwarden..."

  BW_CLIENTID="$bw_clientid" BW_CLIENTSECRET="$bw_clientsecret" \
    "$BW_BIN" login --raw --apikey

  BW_SESSION="$("$BW_BIN" unlock --raw --passwordfile "$VAULT_PASSWORD_FILE")"

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
  local filename="$1"
  local json_password="$2"
  local desc="Bitwarden-specific encrypted JSON"
  local output_file_path="${filename}-encrypted.json"

  log_export_start "${desc}"

  "$BW_BIN" export --session "${BW_SESSION}" --format encrypted_json \
    --password "${json_password}" --output "${output_file_path}" > /dev/null

  chmod 600 "${output_file_path}"

  log_export_end "${output_file_path}"
}

export_and_age_encrypt() {
  local filename="$1"
  local format="$2" # json or csv
  local desc="$3"
  local output_file_path="${filename}.${format}.age"

  log_export_start "${desc}"

  "$BW_BIN" export --session "${BW_SESSION}" --format "$format" --raw | \
    "$AGE_BIN" --encrypt -r "$AGE_PUBLIC_KEY" -o "$output_file_path"

  chmod 600 "${output_file_path}"

  log_export_end "${output_file_path}"
}

export_backups() {
  local timestamp
  timestamp=$(date +'%Y-%m-%d_%H-%M-%S')

  local output_dir="${OUTPUT_DIR}/${TODAY}"
  local filename_base_path="${output_dir}/bitwarden_backup_${timestamp}"

  mkdir -p "${output_dir}"
  chmod 700 "${output_dir}"

  export_bitwarden_encrypted "${filename_base_path}" "${json_password}"
  export_and_age_encrypt "${filename_base_path}" "json" "plain text JSON, encrypted with age"
  export_and_age_encrypt "${filename_base_path}" "csv" "plain text CSV, encrypted with age"
}

check_proton_drive_env_vars() {
  [[ -x "${RCLONE_BIN:-}" ]] || return

  local remote_name_set=0
  local dest_path_set=0

  if [[ -n "${PROTON_DRIVE_REMOTE_NAME:-}" ]]; then
    remote_name_set=1
  fi

  if [[ -n "${PROTON_DRIVE_DESTINATION_PATH:-}" ]]; then
    dest_path_set=1
  fi

  if (( remote_name_set || dest_path_set )); then
    if (( !remote_name_set || !dest_path_set )); then
      fail "If either PROTON_DRIVE_REMOTE_NAME or PROTON_DRIVE_DESTINATION_PATH is set, both must be set."
    fi

    if [[ ! -x "${RCLONE_BIN:-}" ]]; then
      fail "RCLONE_BIN is required when using Proton Drive upload, but was not found."
    fi

    PROTON_DRIVE_CONFIGURED=1
  fi
}

rclone_to_proton_drive() {
  (( PROTON_DRIVE_CONFIGURED )) || return 0

  local output_dir="${OUTPUT_DIR}/${TODAY}"

  if [[ -d "${output_dir}" ]]; then
    log "\nUploading backups to Proton Drive..."

    "$RCLONE_BIN" copy -v --stats-one-line "${output_dir}" "${PROTON_DRIVE_REMOTE_NAME}:${PROTON_DRIVE_DESTINATION_PATH}/"

    log_success "Backups uploaded to Proton Drive."
  else
    log_error "Output directory path not found: ${output_dir}"
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

  TODAY=$(date +"%Y-%m-%d")

  set_env_var_defaults
  check_commands
  check_env_vars
  check_files
  
  load_secrets
  print_config

  log_in_and_unlock
  export_backups
  rclone_to_proton_drive
}

main "$@"
