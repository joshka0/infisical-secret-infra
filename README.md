# Infisical Secret Infrastructure

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

## Recommended Local Layout

On each machine, the live vault control plane should be:

```text
~/.vault
```

The default local Infisical UI is:

```text
http://127.0.0.1:18080
```

The recommended self-hosted service checkout is:

```text
~/services/infisical
```

## Current Defaults

- Infisical is the source of truth for app/runtime secrets.
- Agent Vault is for brokered agent HTTP access, not repo dotenv injection.
- Secret-bearing files under `~/.vault` outside Infisical must be encrypted.
- Nightly Infisical backups run at `03:00`.
- Backups keep `7` local encrypted archives and `14` remote encrypted archives.
- Remote encrypted backup target is operator-configured, for example
  `dev:backups/infisical`.

## Start Here

1. New machine setup: [setup.md](setup.md).
2. Agent operating rules: [AGENTS.md](AGENTS.md).
3. Repo migrations: [docs/migration-runbook.md](docs/migration-runbook.md).
4. Backup operations: [docs/backup-restore.md](docs/backup-restore.md).
5. Agent behavior: [docs/agent-guide.md](docs/agent-guide.md).

## Safety Standard

Agents should report only paths, key names, counts, hashes, and statuses. They
should never print, summarize, or quote secret values.
