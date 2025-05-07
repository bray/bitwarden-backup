#!/usr/bin/env bash

# This script is licensed under the MIT License.
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 Brian Ray
#
# This script backs up your Bitwarden vault to a local directory.
#
# It requires the following environment variables to be set:
# - AGE_PUBLIC_KEY: Your public key for age encryption.
#
# It also requires the following files to be present (don't forget to make these only readable by your user!):
# - ${HOME}/.config/bitwarden/client_id: The client ID for Bitwarden.
# - ${HOME}/.config/bitwarden/client_secret: The client secret for Bitwarden.
# - ${HOME}/.config/bitwarden/vault_password: The password for your Bitwarden vault.
# - ${HOME}/.config/bitwarden/json_password: A password to set for the encrypted JSON export.

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

  log_success "Logged in and unlocked Bitwarden."
}

export_bitwarden_specific_json() {
  local filename="$1"
  local json_password="$2"

  bw export --session "${BW_SESSION}" --format encrypted_json \
    --password "${json_password}" --output "${filename}.json"
}

export_plain_text_json_and_encrypt() {
  local filename="$1"

  bw export --session "${BW_SESSION}" --format json --raw | \
    age --encrypt -r "${AGE_PUBLIC_KEY}" -o "${filename}.json.age"
}

export_plain_text_csv_and_encrypt() {
  local filename="$1"

  bw export --session "${BW_SESSION}" --format csv --raw | \
    age --encrypt -r "${AGE_PUBLIC_KEY}" -o "${filename}.csv.age"
}

cleanup() {
  log "Cleaning up..."

  if bw login --check >/dev/null 2>&1; then
    bw logout
  else
    log_success "Already logged out of Bitwarden."
  fi
}

trap cleanup EXIT

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
