# Bitwarden Backup

## Description

Back up your Bitwarden vault to a local directory.

The backup includes:
- Encrypted JSON export (Bitwarden format)
- Age-encrypted JSON export
- Age-encrypted CSV export

Optional: Syncs backups to Proton Drive via `rclone`.

## Requirements

- Commands:
  - [bw](https://bitwarden.com/help/cli/) (Bitwarden CLI)
  - [age](https://github.com/FiloSottile/age) (encryption tool)
  - [rclone](https://rclone.org/install/) (optional, for Proton Drive sync)
- Scripts:
  - [common-functions.sh](https://github.com/bray/dotfiles/blob/main/.local/share/scripts/common-functions.sh) (a library of common functions)
- Identity file for age encryption:
  - Generate an `age` asymmetric key pair with `age-keygen -o ~/.config/age/identity.txt`

## Configuration

All configuration is done via environment variables in: `$HOME/.config/back-up-bitwarden/.env` (make sure to `chmod 600` this file).

### Required variables:
- `BW_CLIENTID` - Bitwarden API client ID
- `BW_CLIENTSECRET` - Bitwarden API client secret
- `BW_VAULT_PASSWORD` - Your Bitwarden master password
- `BW_JSON_PASSWORD` - Password for encrypted JSON export
- `AGE_PUBLIC_KEY` - Your age public key for encryption

### Optional variables:
- `BW_BIN` - Path to `bw` CLI (default: `$(command -v bw)`)
- `AGE_BIN` - Path to `age` CLI (default: `$(command -v age)`)
- `RCLONE_BIN` - Path to `rclone` CLI (default: `$(command -v rclone)`)
- `BACKUP_DIR_BASE` - Backup directory (default: `./bitwarden_backups`)
- `PROTON_DRIVE_REMOTE_NAME` - Rclone remote name for Proton Drive
- `PROTON_DRIVE_DIR_BASE` - Base destination path in Proton Drive

## Security

- The `.env` file should be readable only by your user (`chmod 600`)
- Backups are encrypted with `age` using your public key
- Sensitive credentials are never written to disk
- All backup files are set to mode 600

## Decrypting backups

To decrypt the age-encrypted backups, you need your private key:
```bash
age --decrypt -i ~/.config/age/identity.txt /path/to/bitwarden_backups/DATE/bitwarden_backup_TIMESTAMP.json.age | less
```

## Wrapper

The wrapper script (`back-up-bitwarden-wrapper.sh`) is designed to run the main backup script via `cron` or `LaunchAgent`, with optional [healthchecks.io](https://healthchecks.io/) integration as a dead man's switch.

### Requirements

- Scripts:
  - `back-up-bitwarden.sh` (the main backup script)
- Environment variables:
  - `HEALTHCHECKS_URL` (optional)
