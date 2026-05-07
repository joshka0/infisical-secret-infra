# Setup Guide

This guide is for a human or agent setting up the Infisical secret
infrastructure pattern on a new machine or server.

The repo contains sanitized docs and scripts only. It does not contain secret
values, backup passphrases, live `.env` files, or backup archives.

## 1. Clone The Repo

Use a private GitLab project for your own deployment.

```sh
mkdir -p "$HOME/repos"
cd "$HOME/repos"
git clone git@gitlab.com:<namespace>/infisical-secret-infra.git
cd infisical-secret-infra
```

If you fork this repo, keep the fork private.

## 2. Create Local Directories

Recommended layout:

```text
~/.vault
~/.vault/scripts
~/.vault/umbrella/home-root
~/.vault/staging
~/.vault/imports
~/.vault/inventory
~/.vault/infisical/backups
~/.vault/logs
~/services/infisical
~/repos
```

Create them:

```sh
mkdir -p \
  "$HOME/.vault/scripts" \
  "$HOME/.vault/umbrella/home-root" \
  "$HOME/.vault/staging" \
  "$HOME/.vault/imports" \
  "$HOME/.vault/inventory" \
  "$HOME/.vault/infisical/backups" \
  "$HOME/.vault/logs" \
  "$HOME/services/infisical" \
  "$HOME/repos"

chmod 700 "$HOME/.vault" "$HOME/.vault"/*
```

## 3. Install Required Tools

Required:

```text
docker
node
infisical
shasum or sha256sum
tar
ssh/scp, optional for remote backup upload
```

macOS automation additionally uses:

```text
launchd
security
```

Linux automation uses:

```text
systemd --user
```

## 4. Install Scripts

Copy the scripts into the local vault:

```sh
cp scripts/* "$HOME/.vault/scripts/"
chmod 700 "$HOME/.vault/scripts/"*
```

The scripts use these defaults:

```text
VAULT_ROOT=$HOME/.vault
INFISICAL_SERVICE_DIR=$HOME/services/infisical
INFISICAL_CONTROL_DIR=$HOME/.vault/umbrella/home-root
REPOS_ROOT=$HOME/repos
INFISICAL_API_URL=http://127.0.0.1:18080
```

Override them with environment variables if your machine layout differs.

## 5. Deploy Or Link Infisical

Copy the sanitized compose template:

```sh
cp deploy/compose.yaml "$HOME/services/infisical/compose.yaml"
```

Create a real service `.env` manually. Do not commit it. Required values depend
on your Infisical version and deployment, but typically include database,
encryption, auth, Redis, and site URL settings.

Start Infisical from the service directory:

```sh
cd "$HOME/services/infisical"
docker compose up -d
```

Verify the local UI:

```text
http://127.0.0.1:18080
```

## 6. Link The Infisical Control Directory

Login and link a control directory for the project/environment that will hold
home-level secrets.

```sh
cd "$HOME/.vault/umbrella/home-root"
infisical login
infisical init
```

Do not commit `.infisical.json` unless your repo intentionally tracks a
non-secret project link.

## 7. Create The Local File Encryption Key

Secret-bearing files under `~/.vault` outside Infisical must be encrypted at
rest. Generate a key and store it in Infisical path `/home` as
`LOCAL_VAULT_FILE_ENCRYPTION_KEY`.

Example:

```sh
openssl rand -base64 32 > /tmp/local-vault-file-encryption-key.txt
cd "$HOME/.vault/umbrella/home-root"
infisical secrets set \
  LOCAL_VAULT_FILE_ENCRYPTION_KEY="$(tr -d '\n' < /tmp/local-vault-file-encryption-key.txt)" \
  --env dev \
  --path /home \
  --domain http://127.0.0.1:18080 \
  --silent >/dev/null
rm /tmp/local-vault-file-encryption-key.txt
```

Do not print the key.

## 8. Configure Infisical Backups

Generate a separate backup passphrase. This must be recoverable without
Infisical, so copy it into your password vault.

```sh
openssl rand -base64 48 > /tmp/infisical-backup-passphrase.txt
chmod 600 /tmp/infisical-backup-passphrase.txt
```

macOS Keychain:

```sh
security add-generic-password \
  -a "$USER" \
  -s infisical-backup-passphrase \
  -w "$(tr -d '\n' < /tmp/infisical-backup-passphrase.txt)" \
  -U
```

Linux or non-Keychain systems can use a root-owned file or another local secret
manager:

```sh
install -m 600 /tmp/infisical-backup-passphrase.txt "$HOME/.vault/infisical-backup-passphrase.txt"
```

Then run backups with:

```sh
INFISICAL_BACKUP_PASSPHRASE_FILE="$HOME/.vault/infisical-backup-passphrase.txt" \
  "$HOME/.vault/scripts/backup-infisical-if-changed.sh" --dry-run
```

After copying the passphrase into your password vault:

```sh
rm /tmp/infisical-backup-passphrase.txt
```

## 9. Configure Remote Backup Upload

Remote upload is optional. If configured, only completed encrypted archives and
redacted reports are uploaded.

Example:

```sh
export INFISICAL_BACKUP_REMOTE=dev
export INFISICAL_BACKUP_REMOTE_DIR=backups/infisical
ssh "$INFISICAL_BACKUP_REMOTE" "mkdir -p '$INFISICAL_BACKUP_REMOTE_DIR'"
```

If `INFISICAL_BACKUP_REMOTE` is empty, backups stay local.

## 10. Run A Manual Backup

Dry run:

```sh
"$HOME/.vault/scripts/backup-infisical-if-changed.sh" --dry-run
```

Create backup if changed:

```sh
"$HOME/.vault/scripts/backup-infisical-if-changed.sh"
```

Force a fresh archive:

```sh
"$HOME/.vault/scripts/backup-infisical-if-changed.sh" --force
```

Skip remote upload:

```sh
"$HOME/.vault/scripts/backup-infisical-if-changed.sh" --no-remote
```

## 11. Schedule Nightly Backups

### macOS LaunchAgent

Copy and customize:

```sh
mkdir -p "$HOME/Library/LaunchAgents"
cp examples/launchd/com.example.infisical-backup.plist \
  "$HOME/Library/LaunchAgents/com.example.infisical-backup.plist"
```

Edit placeholders:

```text
__HOME__ -> your actual home directory, for example /Users/alex
INFISICAL_BACKUP_REMOTE -> your remote alias, or remove it
```

Load:

```sh
launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.example.infisical-backup.plist"
launchctl print "gui/$(id -u)/com.example.infisical-backup"
```

### Linux systemd User Timer

Copy and customize:

```sh
mkdir -p "$HOME/.config/systemd/user"
cp examples/systemd/infisical-backup.service "$HOME/.config/systemd/user/"
cp examples/systemd/infisical-backup.timer "$HOME/.config/systemd/user/"
```

If you need a passphrase file, add this to the service:

```text
Environment=INFISICAL_BACKUP_PASSPHRASE_FILE=%h/.vault/infisical-backup-passphrase.txt
```

Enable:

```sh
systemctl --user daemon-reload
systemctl --user enable --now infisical-backup.timer
systemctl --user list-timers infisical-backup.timer
```

## 12. Migrate A Repo `.env`

Use the import helper:

```sh
"$HOME/.vault/scripts/infisical-import-dotenv.sh" \
  /path/to/repo/.env \
  /repos/personal/example \
  dev \
  --move-source-to-vault
```

Then update the repo to run commands through Infisical:

```sh
infisical run --env dev --path /repos/personal/example -- <command>
```

Use `templates/repo-agents-snippet.md` in the target repo's `AGENTS.md`.

## 13. Agent Skills And Guides

For agents, install or reference the local-secrets skill in your agent system.

The reusable skill is included in:

```text
skills/local-secrets/SKILL.md
```

Example installs:

```sh
mkdir -p "$HOME/.codex/skills" "$HOME/.claude/skills" "$HOME/.gemini/skills"
cp -R skills/local-secrets "$HOME/.codex/skills/"
cp -R skills/local-secrets "$HOME/.claude/skills/"
cp -R skills/local-secrets "$HOME/.gemini/skills/"
```

If your agent uses a central skills repo, copy or symlink `skills/local-secrets`
into that repo's shared provider tree.

The core behavior is:

- Do not print secret values.
- Discover required key names from code/config.
- Import `.env` files with the helper.
- Verify with `present` / `missing` only.
- Use `infisical run` for repo commands.
- Use Agent Vault for brokered agent HTTP access, if you run Agent Vault.
- Keep unavoidable secret-bearing files encrypted at rest.

Key docs:

```text
AGENTS.md
docs/agent-guide.md
docs/migration-runbook.md
docs/backup-restore.md
docs/checklists/repo-migration.md
```

## 14. Validation Checklist

- [ ] Git repo remains private.
- [ ] No real `.env` or backup archive is committed.
- [ ] Infisical UI is reachable.
- [ ] Control directory is linked.
- [ ] `LOCAL_VAULT_FILE_ENCRYPTION_KEY` exists in Infisical `/home`.
- [ ] Backup passphrase is in the human password vault.
- [ ] Manual backup creates an encrypted archive.
- [ ] Remote upload works if configured.
- [ ] Nightly timer is loaded.
- [ ] A test repo `.env` can be migrated without printing values.
