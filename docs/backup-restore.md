# Backup And Restore

## Backup Policy

The local self-hosted Infisical deployment is backed up nightly.

Defaults:

```text
schedule: 03:00 local time
local retention: 7 encrypted archives
remote retention: 14 encrypted archives
remote: dev:backups/infisical
```

The script is:

```text
/Users/joshka/.vault/scripts/backup-infisical-if-changed.sh
```

The launchd job is:

```text
/Users/joshka/Library/LaunchAgents/com.joshka.infisical-backup.plist
```

## Backup Contents

The encrypted archive contains:

- Postgres dump from `infisical-db`
- Service `compose.yaml`
- Service `.env`
- Redacted key-name list
- Restore metadata

The archive is encrypted before it is retained locally or uploaded.

## Backup Passphrase

The backup passphrase is read from:

1. `INFISICAL_BACKUP_PASSPHRASE`
2. `INFISICAL_BACKUP_PASSPHRASE_FILE`
3. macOS Keychain item `infisical-backup-passphrase`

The passphrase must also be kept in the human password vault. It must not live
only inside Infisical.

## Manual Backup

Dry run:

```sh
/Users/joshka/.vault/scripts/backup-infisical-if-changed.sh --dry-run
```

Create if changed and upload if `dev` is reachable:

```sh
/Users/joshka/.vault/scripts/backup-infisical-if-changed.sh
```

Force a fresh encrypted archive:

```sh
/Users/joshka/.vault/scripts/backup-infisical-if-changed.sh --force
```

Skip upload:

```sh
/Users/joshka/.vault/scripts/backup-infisical-if-changed.sh --no-remote
```

## Restore Shape

High-level restore flow:

1. Copy the encrypted archive from local backups or `dev`.
2. Decrypt it using the password-vault passphrase.
3. Inspect only metadata first.
4. Bring up a fresh Infisical Postgres service.
5. Restore the Postgres dump into the new database.
6. Restore service config from the archived metadata.
7. Start Infisical.
8. Verify UI access and key presence checks.
9. Delete plaintext restored artifacts after use.

Do not restore into the live service without a separate restore plan and a fresh
backup of the current state.

## Remote Transport

SSH upload is preferred for the primary path because it is explicit and atomic
enough for completed encrypted files.

Syncthing may be used only for a folder containing completed encrypted archives
and redacted reports. Do not sync live Docker volumes, plaintext dumps,
plaintext `.env`, or all of `~/.vault`.
