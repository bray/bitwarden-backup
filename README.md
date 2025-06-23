# Bitwarden Backup

## Description

Back up your Bitwarden vault to a local directory, and optionally sync backups to Proton Drive via `rclone`.

The backup includes:
- Encrypted JSON export (Bitwarden format)
- Age-encrypted JSON export
- Age-encrypted CSV export

Also see [keepassxc-backup](https://github.com/bray/keepassxc-backup) for a similar script that backs up your KeePassXC database(s).

## Usage

1. Install required dependencies:
   - [Bitwarden CLI](https://bitwarden.com/help/cli/)
   - [age](https://github.com/FiloSottile/age)
   - [rclone](https://rclone.org/install/) (optional, for Proton Drive sync)
   - [common-functions.sh](https://github.com/bray/dotfiles/blob/main/.local/share/scripts/common-functions.sh)

2. Set up your environment:
   ```bash
   # Create and secure the configuration file
   mkdir -p ~/.config/back-up-bitwarden
   touch ~/.config/back-up-bitwarden/.env
   chmod 600 ~/.config/back-up-bitwarden/.env
   
   # Generate a key pair for `age`
   mkdir -p ~/.config/age
   age-keygen -o ~/.config/age/identity.txt
   ```

3. Configure your `.env` file with the following variables:
   ```bash
   # Required variables
   BW_CLIENTID="your_client_id"
   BW_CLIENTSECRET="your_client_secret"
   BW_VAULT_PASSWORD="your_master_password"
   BW_JSON_PASSWORD="any_strong_password_for_encrypted_json_export"
   AGE_PUBLIC_KEY="your_age_public_key"

   # Optional variables

   # Path to `bw` CLI (default: $(command -v bw))
   # BW_BIN="/path/to/bw"

   # Path to `age` CLI (default: $(command -v age))
   # AGE_BIN="/path/to/age"

   # Path to `rclone` CLI (default: $(command -v rclone))
   # RCLONE_BIN="/path/to/rclone"

   # Backup directory (default: ./bitwarden_backups)
   # BACKUP_DIR_BASE="./bitwarden_backups"

   # Rclone remote name for Proton Drive
   # PROTON_DRIVE_REMOTE_NAME="proton"

   # Base destination path in Proton Drive
   # PROTON_DRIVE_DIR_BASE="backups/bitwarden"

   # Enable healthchecks.io integration
   # HEALTHCHECKS_URL="your_url"
   ```

4. Run the backup:
   ```bash
   # Manual backup
   ./back-up-bitwarden.sh
   
   # Or use the wrapper for automated backups
   ./back-up-bitwarden-wrapper.sh
   ```

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
