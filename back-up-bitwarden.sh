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
#   - Environment variables:
#       AGE_PUBLIC_KEY
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
OUTPUT_DIR="bitwarden_backups"

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

check_file() {
  if [[ ! -f "$1" ]]; then
    fail "$1 not found. Please create it first."
  fi
}

check_env_var() {
  local var_name="$1"

  if [[ -z "${!var_name:-}" ]]; then
    fail "You must set an env var $1."
  fi
}

check_command() {
  command -v "$1" >/dev/null 2>&1 || \
    fail "Required command '$1' not found. Please install it."
}

log_in_and_unlock() {
  log "Logging in to Bitwarden..."

  BW_CLIENTID="$bw_clientid" BW_CLIENTSECRET="$bw_clientsecret" \
    bw login --raw --apikey

  BW_SESSION="$(bw unlock --raw --passwordfile "$VAULT_PASSWORD_FILE")"

  log_success "Logged in to Bitwarden."
}

log_export_start() {
  local description="$1"
  log "\nExporting Bitwarden vault via: ${description} ..."
}

log_export_end() {
  local file_path="$1"
  log_success "🔒Exported to ${file_path}."
}

export_bitwarden_encrypted() {
  local filename="$1"
  local json_password="$2"
  local desc="Bitwarden-specific encrypted JSON"
  local output_file_path="${filename}-encrypted.json"

  log_export_start "${desc}"

  bw export --session "${BW_SESSION}" --format encrypted_json \
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

  bw export --session "${BW_SESSION}" --format "$format" --raw | \
    age --encrypt -r "$AGE_PUBLIC_KEY" -o "$output_file_path"

  chmod 600 "${output_file_path}"

  log_export_end "${output_file_path}"
}

clean_up() {
  log "\nCleaning up..."

  if bw login --check >/dev/null 2>&1; then
    if output=$(bw logout); then
      log_success "Logged out of Bitwarden."
    else
      fail "Failed to log out of Bitwarden: ${output}."
    fi
  else
    log_success "Already logged out of Bitwarden."
  fi
}

trap clean_up EXIT

main() {
  check_command bw
  check_command age

  check_env_var "AGE_PUBLIC_KEY"

  check_file "$CLIENT_ID_FILE"
  check_file "$CLIENT_SECRET_FILE"
  check_file "$VAULT_PASSWORD_FILE"
  check_file "$JSON_PASSWORD_FILE"

  read -r bw_clientid < "$CLIENT_ID_FILE"
  read -r bw_clientsecret < "$CLIENT_SECRET_FILE"
  read -r json_password < "$JSON_PASSWORD_FILE"

  log_in_and_unlock

  timestamp=$(date +"%Y-%m-%d_%H-%M-%S")
  today=$(date +"%Y-%m-%d")
  output_dir="${OUTPUT_DIR}/${today}"
  filename_base_path="${output_dir}/bitwarden_backup_${timestamp}"

  mkdir -p "${output_dir}"
  chmod 700 "${output_dir}"

  export_bitwarden_encrypted "${filename_base_path}" "${json_password}"
  export_and_age_encrypt "${filename_base_path}" "json" "plain text JSON, encrypted with age"
  export_and_age_encrypt "${filename_base_path}" "csv" "plain text CSV, encrypted with age"
}

main "$@"
