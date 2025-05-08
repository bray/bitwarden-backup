#!/usr/bin/env bash

# Bitwarden Vault Backup Script
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 Brian Ray
#
# Backs up your Bitwarden vault to a local directory, encrypting with age.
#
# Requirements:
#   - Environment variable: AGE_PUBLIC_KEY
#   - Files (readable only by your user!):
#       $HOME/.config/bitwarden/client_id
#       $HOME/.config/bitwarden/client_secret
#       $HOME/.config/bitwarden/vault_password
#       $HOME/.config/bitwarden/json_password

set -euo pipefail
IFS=$'\n\t'

green='\033[0;32m'
red='\033[0;31m'
nc='\033[0m'

log() {
  echo -e "$*";
}

log_success() {
  log "${green}$*${nc}"
}

log_err_and_exit() {
  log "${red}$*${nc}" >&2
  exit 1
}

check_file() {
  if [[ ! -f "$1" ]]; then
    log_err_and_exit "$1 not found. Please create it first."
  fi
}

check_env_var() {
  local var_name="$1"

  if [[ -z "${!var_name:-}" ]]; then
    log_err_and_exit "You must set an env var $1."
  fi
}

log_in_and_unlock() {
  log "Logging in to Bitwarden..."

  BW_CLIENTID="$bw_clientid" BW_CLIENTSECRET="$bw_clientsecret" \
    bw login --raw --apikey

  BW_SESSION="$(bw unlock --raw --passwordfile "$vault_password_file")"

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

export_bitwarden_specific_json() {
  local filename="$1"
  local json_password="$2"
  local desc="Bitwarden-specific encrypted JSON"
  local output_file_path="${filename}-encrypted.json"

  log_export_start "${desc}"

  bw export --session "${BW_SESSION}" --format encrypted_json \
    --password "${json_password}" --output "${output_file_path}" > /dev/null

  log_export_end "${output_file_path}"
}

export_plain_text_json_and_encrypt() {
  local filename="$1"
  local desc="plain text JSON, encrypted with age"
  local output_file_path="${filename}.json.age"

  log_export_start "${desc}"

  bw export --session "${BW_SESSION}" --format json --raw | \
    age --encrypt -r "${AGE_PUBLIC_KEY}" -o "${output_file_path}"

  log_export_end "${output_file_path}"
}

export_plain_text_csv_and_encrypt() {
  local filename="$1"
  local desc="plain text CSV, encrypted with age"
  local output_file_path="${filename}.csv.age"

  log_export_start "${desc}"

  bw export --session "${BW_SESSION}" --format csv --raw | \
    age --encrypt -r "${AGE_PUBLIC_KEY}" -o "${output_file_path}"

  log_export_end "${output_file_path}"
}

clean_up() {
  log "\nCleaning up..."

  if bw login --check >/dev/null 2>&1; then
    if output=$(bw logout); then
      log_success "Logged out of Bitwarden."
    else
      log_err_and_exit "Failed to log out of Bitwarden: ${output}."
    fi
  else
    log_success "Already logged out of Bitwarden."
  fi
}

trap clean_up EXIT

check_env_var "AGE_PUBLIC_KEY"

base_path="${HOME}/.config/bitwarden"

client_id_file="${base_path}/client_id"
client_secret_file="${base_path}/client_secret"
vault_password_file="${base_path}/vault_password"
json_password_file="${base_path}/json_password"

check_file "$client_id_file"
check_file "$client_secret_file"
check_file "$vault_password_file"
check_file "$json_password_file"

read -r bw_clientid < "$client_id_file"
read -r bw_clientsecret < "$client_secret_file"
read -r json_password < "$json_password_file"

log_in_and_unlock


timestamp=$(date +"%Y-%m-%d_%H-%M-%S")
today=$(date +"%Y-%m-%d")
output_dir="bitwarden_backups/${today}"
filename_base_path="${output_dir}/bitwarden_backup_${timestamp}"

mkdir -p "${output_dir}"

export_bitwarden_specific_json "${filename_base_path}" "${json_password}"
export_plain_text_json_and_encrypt "${filename_base_path}" "$AGE_PUBLIC_KEY"
export_plain_text_csv_and_encrypt "${filename_base_path}" "$AGE_PUBLIC_KEY"


# TODO: send ping to healthcheck.io or cronitor
