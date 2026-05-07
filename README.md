# Infisical Secret Infrastructure

Private repo for the local Infisical-backed secret-management setup.

This repo is a sanitized control-plane guide. It documents how agents and humans
should migrate repo `.env` files into Infisical, run local workflows without
printing secrets, encrypt any unavoidable secret-bearing files at rest, and back
up the self-hosted Infisical deployment.

## What Belongs Here

- Agent operating rules for secret work.
- Migration runbooks.
- Backup and restore runbooks.
- Sanitized scripts and launchd examples.
- Sanitized compose/config templates.
- Checklists and inventory templates.

## What Must Not Belong Here

- Secret values.
- Real `.env` files.
- Infisical exports.
- Plaintext Postgres dumps.
- Encrypted backup archives.
- Backup passphrases.
- SSH private keys.
- API tokens.

## Local Source Of Truth

On the Mac, the live vault control plane is:

```text
/Users/joshka/.vault
```

The local Infisical UI is:

```text
http://127.0.0.1:18080
```

The self-hosted service checkout is:

```text
/Users/joshka/services/infisical
```

## Current Defaults

- Infisical is the source of truth for app/runtime secrets.
- Agent Vault is for brokered agent HTTP access, not repo dotenv injection.
- Secret-bearing files under `~/.vault` outside Infisical must be encrypted.
- Nightly Infisical backups run at `03:00`.
- Backups keep `7` local encrypted archives and `14` remote encrypted archives.
- Remote encrypted backup target is `dev:backups/infisical`.

## Start Here

1. Read [AGENTS.md](AGENTS.md).
2. For repo migrations, use [docs/migration-runbook.md](docs/migration-runbook.md).
3. For backup operations, use [docs/backup-restore.md](docs/backup-restore.md).
4. For agent behavior, use [docs/agent-guide.md](docs/agent-guide.md).

## Safety Standard

Agents should report only paths, key names, counts, hashes, and statuses. They
should never print, summarize, or quote secret values.
