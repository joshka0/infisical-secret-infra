---
name: local-secrets
description: Handle local secrets without exposing values. Use when a task needs env vars, API keys, Infisical, Agent Vault, .env files, repo runtime secrets, or secret discovery.
---

# Local Secrets

Use this skill whenever a command, repo, agent, MCP, API client, CI flow, or
local dev server needs secrets or environment variables.

Prime directive: do not print, summarize, quote, or expose secret values. Report
only paths, key names, counts, hashes, and statuses unless the user explicitly
requests a value and the request is appropriate for the current security
context.

## Control Plane

Default local vault root:

```text
~/.vault
```

Before touching files under the local vault, read and follow:

```text
~/.vault/AGENTS.md
```

That file is the machine-specific operating contract and may contain newer
rules than this skill.

## Responsibility Split

- Infisical is the source of truth for app/runtime secrets, repo `.env`
  replacement, local `~/.env`, and migrated file-like secrets.
- Any secret-bearing file kept under `~/.vault` outside Infisical must be
  encrypted at rest.
- Agent Vault, if installed, is for brokered HTTP access by AI agents. Agents
  should receive scoped proxy/session access, not raw API keys.
- OS keychains or local secret managers are for bootstrap material such as
  backup passphrases, agent-vault master passwords, and SSH key passphrases.
- SSH private keys should not be stored in Agent Vault.

## Infisical Defaults

Default local UI:

```text
http://127.0.0.1:18080
```

Default control directory:

```text
~/.vault/umbrella/home-root
```

Runtime pattern for repos:

```sh
infisical run --env dev --path /repos/personal/example -- <command>
```

Export only when a tool requires a file, and write to ignored/generated paths.
Do not use `infisical export` or `infisical secrets --output dotenv` as routine
discovery.

## Discovery

Discover required secret names from code and config, not by dumping vault
contents.

Use this order:

1. Identify the command or workflow the user wants to run.
2. Inspect repo files for required environment variable names only.
3. Map names to the repo's Infisical path or to an Agent Vault service.
4. Check whether keys exist without printing values.
5. Run the workflow through Infisical or Agent Vault.
6. If a secret is missing, report the missing key name and expected provider.

Good discovery commands:

```sh
rg -n "process\\.env\\.|Deno\\.env|getenv\\(|System\\.getenv|ENV\\[|import\\.meta\\.env|VITE_|NEXT_PUBLIC_|EXPO_PUBLIC_" .
rg -n "OPENAI_API_KEY|ANTHROPIC_API_KEY|GITHUB_TOKEN|SUPABASE|TURSO|DATABASE_URL|AWS_|KUBECONFIG" .
find . -maxdepth 3 \( -name '.env.example' -o -name '.env.template' -o -name '.env.sample' -o -name '.envrc' \) -print
```

Do not run commands that print values:

```sh
env
printenv
infisical secrets --output dotenv
infisical export
cat .env
cat ~/.env
cat ~/.aws/credentials
cat ~/.kube/config
cat ~/.ssh/*
```

## Repo Path Mapping

Recommended path mapping:

```text
~/repos/personal/foo -> /repos/personal/foo
~/repos/foxway/foo   -> /repos/foxway/foo
~/repos/mobiles/foo  -> /repos/mobiles/foo
home-level secrets   -> /home
migrated raw files   -> /migration/...
```

Check for a key without printing the value:

```sh
infisical run --env dev --path /repos/personal/example -- sh -lc 'test -n "${OPENAI_API_KEY:-}" && echo OPENAI_API_KEY=present || echo OPENAI_API_KEY=missing'
```

## Dotenv Imports

When a secret-bearing `.env` lands in a repo, do not inspect values and do not
leave the file in the repo. Promote it with:

```sh
~/.vault/scripts/infisical-import-dotenv.sh \
  /path/to/repo/.env \
  /repos/personal/example \
  dev \
  --move-source-to-vault
```

The helper imports through Infisical with command output suppressed, verifies
key presence with `present`/`missing` logic only, stores an encrypted copy under
`~/.vault/staging`, writes a redacted report under `~/.vault/imports`, and
prints only paths, key counts, hashes, and statuses.

If a key looks misspelled, import it as written to avoid data loss and call out
the suspected typo separately.

## Vault File Encryption

Use these helpers for secret-bearing files that must remain on disk outside
Infisical:

```sh
~/.vault/scripts/vault-encrypt-file.sh /path/to/file /path/to/file.enc --remove-plaintext
~/.vault/scripts/vault-decrypt-file.sh /path/to/file.enc /tmp/file
```

Rules:

- Prefer deleting plaintext once it has been imported into Infisical.
- Decrypt only to a temporary ignored path, use it briefly, then delete it.
- Do not print decrypted content.
- Do not store encryption keys in this repo.

## Infisical Backups

The self-hosted Infisical instance can be backed up by:

```text
~/.vault/scripts/backup-infisical-if-changed.sh
```

Operational rules:

- The recommended nightly schedule is 03:00 local time.
- The backup creates a Postgres dump plus restore metadata, then encrypts the
  archive.
- Only completed `*.tar.enc` archives and redacted reports should leave the
  machine.
- Do not sync live Docker volumes, plaintext dumps, plaintext `.env` files, or
  all of `~/.vault`.
- The backup passphrase must be recoverable from a human password vault and must
  not live only inside Infisical.

## Final Response Pattern

For secret tasks, report:

- What path was used.
- Which key names were checked or imported.
- Counts and present/missing status.
- Whether plaintext was removed or encrypted.
- Any follow-up needed.

Never include secret values.
